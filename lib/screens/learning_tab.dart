import 'package:flutter/material.dart';

import '../services/learning_repository.dart';
import '../services/student_knowledge.dart';
import 'knowledge_widgets.dart';
import 'learning_history_screen.dart';
import 'skill_tree_tab.dart';

class LearningTab extends StatefulWidget {
  final VoidCallback onExperienceChanged;
  final LearningRepository? repository;
  const LearningTab({
    super.key,
    required this.onExperienceChanged,
    this.repository,
  });
  @override
  State<LearningTab> createState() => _LearningTabState();
}

class _LearningTabState extends State<LearningTab> {
  static const _purple = Color(0xFF7C5CFA);
  static const _text = Color(0xFF171717);
  late final _repo = widget.repository ?? LearningRepository();
  int _subTabIndex = 0, _request = 0;
  bool _showSkillTree = false, _loading = true;
  String? _grade, _error;
  String _search = '';
  StudentKnowledge? _knowledge;
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    LearningRepository.progressRevision.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    LearningRepository.progressRevision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await StudentKnowledge.load(_repo);
      if (!mounted || request != _request) return;
      final grades = data.concepts
          .map((c) => c['grade_level'])
          .whereType<String>()
          .toSet();
      setState(() {
        _knowledge = data;
        if (!grades.contains(_grade)) _grade = grades.firstOrNull;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = learningError(error);
        _knowledge = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSkillTree) {
      return ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showSkillTree = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('단원/개념 목록으로'),
                ),
              ),
            ),
            Expanded(
              child: SkillTreeTab(
                onExperienceChanged: widget.onExperienceChanged,
                repository: _repo,
              ),
            ),
          ],
        ),
      );
    }
    final grades =
        _knowledge?.concepts
            .map((c) => c['grade_level'])
            .whereType<String>()
            .toSet()
            .toList() ??
        <String>[];
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _grade,
                            isExpanded: true,
                            isDense: true,
                            hint: const Text(
                              '학년·과정',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _text,
                                ),
                            items: [
                              for (final grade in grades)
                                DropdownMenuItem(
                                  value: grade,
                                  child: Text(
                                    grade,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: grades.isEmpty
                                ? null
                                : (value) => setState(() => _grade = value),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '역추적 스킬맵 보기',
                      onPressed: () => setState(() => _showSkillTree = true),
                      icon: const Icon(
                        Icons.account_tree_outlined,
                        color: _purple,
                      ),
                    ),
                    IconButton(
                      tooltip: '학습 기록 · 오답노트',
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                LearningHistoryScreen(repository: _repo),
                          ),
                        );
                        if (!mounted) return;
                        await _refresh();
                        widget.onExperienceChanged();
                      },
                      icon: const Icon(Icons.history_rounded, color: _text),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (final (index, label) in [(0, '단원/개념'), (1, '기출문제')])
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _subTabIndex = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: _subTabIndex == index
                                    ? _text
                                    : Colors.transparent,
                                width: 2.2,
                              ),
                            ),
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: _subTabIndex == index
                                  ? FontWeight.w900
                                  : FontWeight.w500,
                              color: _subTabIndex == index
                                  ? _text
                                  : const Color(0xFF888888),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              Expanded(child: _subTabIndex == 0 ? _units() : _exams()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _units() {
    final units = <String, List<Map<String, dynamic>>>{};
    for (final concept in _knowledge?.concepts ?? <Map<String, dynamic>>[]) {
      if (concept['grade_level'] != _grade) continue;
      final subject = '${concept['subject']}';
      if (_search.isNotEmpty &&
          !subject.contains(_search) &&
          !'${concept['name']}'.contains(_search) &&
          !_knowledge!
              .skillsFor(concept['code'])
              .any((s) => '${s['name']}'.contains(_search))) {
        continue;
      }
      units.putIfAbsent(subject, () => []).add(concept);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              onChanged: (value) => setState(() => _search = value.trim()),
              decoration: const InputDecoration(
                icon: Icon(
                  Icons.search_rounded,
                  color: Color(0xFF888888),
                  size: 20,
                ),
                hintText: '학습하고 싶은 개념을 검색해보세요',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFF888888)),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '개념별 숙련도',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _purple,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '진단·문제 풀이 후 확인된 숙련도를 보여드려요.',
            style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(color: _purple),
          if (_error != null)
            KnowledgeNotice(message: _error!, onRetry: _refresh),
          if (!_loading && _error == null && units.isEmpty)
            KnowledgeNotice(
              message: _search.isEmpty ? '아직 등록된 개념이 없어요.' : '검색한 개념을 찾지 못했어요.',
            ),
          for (final entry in units.entries) ...[
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                if (!_collapsed.add(entry.key)) _collapsed.remove(entry.key);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _collapsed.contains(entry.key)
                          ? Icons.arrow_right_rounded
                          : Icons.arrow_drop_down_rounded,
                      color: _text,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!_collapsed.contains(entry.key))
              for (final concept in entry.value)
                KnowledgeConceptCard(
                  concept: concept,
                  knowledge: _knowledge!,
                  repository: _repo,
                ),
          ],
        ],
      ),
    );
  }

  Widget _exams() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.description_outlined, color: _purple, size: 30),
            SizedBox(height: 12),
            Text(
              '기출문제를 준비하고 있어요',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              '시험지와 문항 정보가 준비되면 여기에 표시돼요. 지금은 단원/개념에서 학습을 시작해 주세요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: Color(0xFF888888),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => setState(() => _subTabIndex = 0),
        child: const Text('단원/개념으로 이동'),
      ),
    ],
  );
}
