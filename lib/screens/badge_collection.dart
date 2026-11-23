import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';

typedef BadgeLoader = Future<List<Map<String, dynamic>>> Function();

class BadgeCollection extends StatefulWidget {
  final BadgeLoader? catalogLoader;
  final BadgeLoader? earnedLoader;

  const BadgeCollection({super.key, this.catalogLoader, this.earnedLoader});

  @override
  State<BadgeCollection> createState() => _BadgeCollectionState();
}

class _BadgeCollectionState extends State<BadgeCollection> {
  static const _previewCount = 6;
  bool _expanded = false;
  List<Map<String, dynamic>> _badges = [];
  Set<String> _earned = {};
  bool _busy = true;
  bool _failed = false;
  bool _earnedFailed = false;
  int _requestId = 0;

  static Future<List<Map<String, dynamic>>> _fetch(String path) async {
    final response = await Api.get(path);
    if (response is! Map || response['items'] is! List) {
      throw const FormatException('Invalid badge list');
    }
    return (response['items'] as List).map((item) {
      if (item is! Map || item['code'] is! String || item['name'] is! String) {
        throw const FormatException('Invalid badge');
      }
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    LearningRepository.progressRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    LearningRepository.progressRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _busy = true;
      _failed = false;
      _earnedFailed = false;
    });
    try {
      final catalog =
          await (widget.catalogLoader?.call() ?? _fetch(Api.allBadgesEndpoint));
      Set<String> earned = {};
      bool earnedFailed = false;
      try {
        final list =
            await (widget.earnedLoader?.call() ?? _fetch(Api.myBadgesEndpoint));
        earned = list.map((b) => b['code'] as String).toSet();
      } catch (_) {
        earnedFailed = true;
      }
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _badges = catalog;
        _earned = earned;
        _earnedFailed = earnedFailed;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Widget _icon(String code, {double size = 64}) {
    final valid = RegExp(r'^BDG-\d{3}$').hasMatch(code);
    if (!valid) return Icon(Icons.workspace_premium_outlined, size: size);
    return Image.asset(
      'img/badges/$code.png',
      width: size,
      height: size,
      errorBuilder: (_, error, stack) =>
          Icon(Icons.workspace_premium_outlined, size: size),
    );
  }

  void _showBadge(Map<String, dynamic> badge) {
    final code = badge['code'] as String;
    final description = badge['description']?.toString().trim();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(badge['name'] as String),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(code, size: 100),
              const SizedBox(height: 16),
              Text(
                description == null || description.isEmpty
                    ? '설명이 아직 등록되지 않았어요.'
                    : description,
              ),
              const SizedBox(height: 12),
              Text(
                _earnedFailed
                    ? '획득 상태를 확인하지 못했어요.'
                    : _earned.contains(code)
                    ? '획득한 배지'
                    : '아직 획득하지 않은 배지',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '내 배지 도감 🏅',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      if (_busy)
        const Center(child: CircularProgressIndicator())
      else if (_failed) ...[
        const Text('배지를 불러오지 못했어요.'),
        TextButton(onPressed: _load, child: const Text('다시 시도')),
      ] else ...[
        if (_earnedFailed) ...[
          const Text('배지 목록은 불러왔지만 획득 상태를 확인하지 못했어요.'),
          TextButton(onPressed: _load, child: const Text('획득 상태 다시 확인')),
        ],
        if (_badges.isEmpty) const Text('등록된 배지가 아직 없어요.'),
        // Wrap accommodates long database names and large text without tile overflow.
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 260 ? 2 : 3;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                for (final badge
                    in _expanded ? _badges : _badges.take(_previewCount))
                  SizedBox(
                    width: width,
                    child: Semantics(
                      button: true,
                      label:
                          '${badge['name']}, ${_earnedFailed
                              ? '획득 상태 확인 불가'
                              : _earned.contains(badge['code'])
                              ? '획득'
                              : '미획득'}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showBadge(badge),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            children: [
                              Opacity(
                                opacity:
                                    _earnedFailed ||
                                        _earned.contains(badge['code'])
                                    ? 1
                                    : 0.4,
                                child: _icon(badge['code'] as String),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                badge['name'] as String,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_badges.length > _previewCount)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(_expanded ? '접기' : '더보기 (전체 ${_badges.length}개)'),
            ),
          ),
      ],
    ],
  );
}
