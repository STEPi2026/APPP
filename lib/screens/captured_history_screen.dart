import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/capture_service.dart';
import '../services/learning_repository.dart';
import '../services/tutor_session_service.dart';
import 'tutor_session_screen.dart';
import 'capture_learning_screen.dart';
import 'knowledge_widgets.dart';
import 'xp_history_screen.dart';

class CapturedHistoryScreen extends StatefulWidget {
  final LearningRepository? repository;
  const CapturedHistoryScreen({super.key, this.repository});
  @override
  State<CapturedHistoryScreen> createState() => _CapturedHistoryScreenState();
}

class _CapturedHistoryScreenState extends State<CapturedHistoryScreen> {
  late final repo = widget.repository ?? LearningRepository();
  late Future<List<JsonMap>> future;
  @override
  void initState() {
    super.initState();
    future = repo.all('/api/v1/captured-problems');
  }

  Future<void> refresh() async {
    final next = repo.all('/api/v1/captured-problems');
    setState(() => future = next);
    try {
      await next;
    } catch (_) {}
  }

  String label(JsonMap? a) => CaptureService.assessmentLabel(a);
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8FF),
    appBar: AppBar(title: const Text('사진 풀이 이력')),
    body: FutureBuilder<List<JsonMap>>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: knowledgePurple),
          );
        }
        if (s.hasError) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: KnowledgeNotice(
              message: learningError(s.error!),
              onRetry: refresh,
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              if (s.data!.isEmpty)
                const KnowledgeNotice(
                  message: '아직 저장된 사진 풀이가 없어요. 아래 카메라 버튼으로 문제와 풀이를 올려 보세요.',
                ),
              for (final row in s.data!)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFECE7F5)),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const Icon(
                        Icons.photo_library_outlined,
                        color: knowledgePurple,
                      ),
                      title: Text(
                        '${row['problem_text'] ?? '사진으로 올린 문제'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${recordTime(row['created_at'])}\n${label(row['latest_analysis'] is Map ? Map<String, dynamic>.from(row['latest_analysis']) : null)}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: row['id'] is! int
                          ? null
                          : () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => SavedCaptureScreen(
                                    captureId: row['id'],
                                    repository: repo,
                                  ),
                                ),
                              );
                              if (mounted) refresh();
                            },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// Viewing is read-only. Corrections require an explicit action and open a
/// separate editor without finishing the historical learning session.
class SavedCaptureScreen extends StatefulWidget {
  final int captureId;
  final LearningRepository? repository;
  final Future<Uint8List> Function(int)? imageLoader;
  const SavedCaptureScreen({
    super.key,
    required this.captureId,
    this.repository,
    this.imageLoader,
  });
  @override
  State<SavedCaptureScreen> createState() => _SavedCaptureScreenState();
}

class _SavedCaptureScreenState extends State<SavedCaptureScreen> {
  late final repo = widget.repository ?? LearningRepository();
  JsonMap? capture, analysis;
  Uint8List? image;
  bool busy = true;
  bool editing = false;
  String? error, imageError, analysisError;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
      imageError = null;
      analysisError = null;
    });
    try {
      final row = await repo.get(
        '/api/v1/captured-problems/${widget.captureId}',
      );
      if (row['id'] != widget.captureId) {
        throw const FormatException('요청한 사진과 응답이 달라요.');
      }
      if (!mounted) return;
      setState(() => capture = row);
      await Future.wait([_image(), _analysis(row)]);
    } catch (e) {
      if (mounted) setState(() => error = captureError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _image() async {
    try {
      final bytes = await (widget.imageLoader ?? Api.getCapturedImage)(
        widget.captureId,
      );
      if (mounted) setState(() => image = bytes);
    } catch (e) {
      if (mounted) {
        setState(() => imageError = '사진을 불러오지 못했어요. 다시 불러오기를 눌러 주세요.');
      }
    }
  }

  Future<void> _analysis(JsonMap row) async {
    final latest = row['latest_analysis'];
    if (latest is! Map || latest['id'] is! int) {
      if (mounted) setState(() => analysis = null);
      return;
    }
    try {
      final result = await CaptureService(repository: repo)
          .analysis(latest['id']);
      if (result['captured_problem_id'] != widget.captureId) {
        throw const FormatException('사진과 분석 결과가 일치하지 않아요.');
      }
      if (mounted) setState(() => analysis = result);
    } catch (e) {
      if (mounted) setState(() => analysisError = captureError(e));
    }
  }

  Future<void> _edit() async {
    if (busy || editing || capture == null) return;
    setState(() => editing = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CaptureLearningScreen(
            savedCaptureId: widget.captureId,
            savedPhoto: image == null ? null : CapturePhoto(image!),
            service: CaptureService(repository: repo),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => editing = false);
        await _load();
      }
    }
  }

  Widget _editButton() => OutlinedButton.icon(
    onPressed: busy || editing || analysisError != null ? null : _edit,
    icon: const Icon(Icons.edit_note_rounded),
    label: Text(
      CaptureService.isPartial(analysis) ? '최종 답 추가하고 다시 분석하기' : '인식 내용 수정하기',
    ),
  );

  Widget _card(String title, Widget body) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFECE7F5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            color: knowledgePurple,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        body,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final first =
        a != null && a['status'] == 'ANALYZED' && a['is_correct'] == false
        ? a['first_error_step']
        : null;
    final steps = a?['solution_steps'] is List
        ? a!['solution_steps'] as List
        : const [];
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(
        title: const Text('저장된 사진 풀이'),
        actions: [
          IconButton(
            onPressed: busy ? null : _load,
            tooltip: '다시 불러오기',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(color: knowledgePurple),
          if (error != null) KnowledgeNotice(message: error!, onRetry: _load),
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(
                image!,
                height: 260,
                fit: BoxFit.contain,
                errorBuilder: (_, e, s) =>
                    const KnowledgeNotice(message: '사진을 표시하지 못했어요.'),
              ),
            ),
          if (imageError != null)
            KnowledgeNotice(message: imageError!, onRetry: busy ? null : _load),
          const SizedBox(height: 16),
          if (capture != null) ...[
            if (capture!['ocr_raw_text'] is String &&
                (capture!['ocr_raw_text'] as String).trim().isNotEmpty)
              _card(
                '인식된 원문',
                SelectableText(
                  capture!['ocr_raw_text'] as String,
                  style: const TextStyle(height: 1.7),
                ),
              ),
            _card(
              '문제',
              SelectableText(
                '${capture!['problem_text'] ?? '인식된 문제 내용이 없어요.'}',
                style: const TextStyle(height: 1.7),
              ),
            ),
            _card(
              '내 풀이',
              SelectableText(
                '${capture!['solution_text'] ?? '인식된 풀이 내용이 없어요.'}',
                style: const TextStyle(height: 1.7),
              ),
            ),
            if (capture!['latest_analysis'] == null)
              const KnowledgeNotice(message: '이 사진은 아직 분석 결과가 없어요.'),
            if (analysis == null) _editButton(),
          ],
          if (analysisError != null)
            KnowledgeNotice(
              message: analysisError!,
              onRetry: busy ? null : _load,
            ),
          if (a != null) ...[
            KnowledgeNotice(message: CaptureService.assessmentLabel(a)),
            if (CaptureService.isPartial(a))
              const KnowledgeNotice(
                message: '최종 답까지 작성한 뒤 다시 분석해 주세요. 이 풀이는 정답이나 오답으로 집계되지 않아요.',
              ),
            if (!CaptureService.pending(a)) _editButton(),
            for (var i = 0; i < steps.length; i++)
              _card(
                first == i + 1 ? '${i + 1}단계 · 최초 오류' : '${i + 1}단계',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      '${steps[i]}',
                      style: const TextStyle(height: 1.7),
                    ),
                    for (final e in LearningRepository.items(
                      a,
                      'errors',
                    ).where((e) => e['step_no'] == i + 1))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${e['content'] ?? ''}',
                          style: const TextStyle(
                            color: Color(0xFFB44050),
                            height: 1.6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (a['status'] == 'ANALYZED' && !CaptureService.isPartial(a))
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => TutorSessionScreen(
                            target: TutorTarget.photo(
                              widget.captureId,
                              withSolution: true,
                            ),
                            service: TutorSessionService(repository: repo),
                            initialAction: 'ANALYZE_RESULT',
                            photo: image == null ? null : CapturePhoto(image!),
                          ),
                        ),
                      ),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('AI 튜터에게 힌트 받기'),
              ),
          ],
        ],
      ),
    );
  }
}
