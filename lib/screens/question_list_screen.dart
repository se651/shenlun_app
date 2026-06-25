import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'question_detail_screen.dart';
import 'answer_editor.dart';

class QuestionListScreen extends StatefulWidget {
  final String questionType;
  final String? keyword;
  final String? region;
  const QuestionListScreen({super.key, required this.questionType, this.keyword, this.region});

  @override
  State<QuestionListScreen> createState() => _QuestionListScreenState();
}

class _QuestionListScreenState extends State<QuestionListScreen> {
  final _db = DatabaseHelper();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _questions = [];
  final Set<String> _favoriteIds = {};
  bool _loading = true;
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.keyword != null && widget.keyword!.isNotEmpty) {
      _searchController.text = widget.keyword!;
      _isSearchMode = true;
    }
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final keyword = _searchController.text.trim();
      final questions = keyword.isNotEmpty
          ? await _db.searchQuestions(keyword,
              questionType: widget.questionType, region: widget.region)
          : await _db.getQuestions(
              questionType: widget.questionType,
              region: widget.region == '全部' ? null : widget.region);
      final ids = questions.map((q) => q['id'] as String).toList();
      if (ids.isNotEmpty) {
        try {
          final db2 = await _db.database;
          if (db2 != null) {
            final placeholders = ids.map((_) => '?').join(',');
            final favs = await db2.rawQuery(
              'SELECT question_id FROM favorites WHERE question_id IN ($placeholders)',
              ids,
            );
            _favoriteIds
                .addAll(favs.map((r) => r['question_id'] as String).toSet());
          }
        } catch (_) {}
      }
      await _sortPracticedToBottom(questions, ids);
      if (mounted) {
        setState(() {
          _questions = questions;
          _loading = false;
          _isSearchMode = keyword.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String value) {
    setState(() {
      _isSearchMode = value.trim().isNotEmpty;
    });
    _load();
  }

  void _clearSearch() {
    _searchController.clear();
    _focusNode.unfocus();
    setState(() => _isSearchMode = false);
    _load();
  }

  Future<void> _sortPracticedToBottom(
      List<Map<String, dynamic>> questions, List<String> ids) async {
    try {
      final db = await _db.database;
      if (db == null || ids.isEmpty) return;
      final placeholders = ids.map((_) => '?').join(',');
      final practiced = await db.rawQuery(
        'SELECT DISTINCT question_id FROM practice_records WHERE question_id IN ($placeholders)',
        ids,
      );
      final practicedIds =
          practiced.map((r) => r['question_id'] as String).toSet();
      questions.sort((a, b) {
        final aDone = practicedIds.contains(a['id']);
        final bDone = practicedIds.contains(b['id']);
        if (aDone && !bDone) return 1;
        if (!aDone && bDone) return -1;
        return 0;
      });
    } catch (_) {}
  }

  void _toggleFavorite(String questionId) async {
    await _db.toggleFavorite(questionId);
    setState(() {
      if (_favoriteIds.contains(questionId)) {
        _favoriteIds.remove(questionId);
      } else {
        _favoriteIds.add(questionId);
      }
    });
  }

  Widget _highlightText(String text, String keyword, {int maxLines = 2, TextStyle? style}) {
    if (keyword.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final escaped = RegExp.escape(keyword);
    final regex = RegExp(escaped, caseSensitive: false);
    final matches = regex.allMatches(text);
    if (matches.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final m in matches) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, m.start)));
      }
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: TextStyle(
          backgroundColor: const Color(0xFFFFEB3B).withOpacity(0.5),
          color: const Color(0xFFE94560),
          fontWeight: FontWeight.bold,
        ),
      ));
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Color _typeColor(String type) {
    if (type.contains('概括')) return const Color(0xFF4ECDC4);
    if (type.contains('综合')) return const Color(0xFFA29BFE);
    if (type.contains('对策') || type.contains('应用文')) return const Color(0xFFF9CA24);
    if (type.contains('大作文') || type.contains('文章')) return const Color(0xFFE94560);
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSearchMode ? '搜索结果' : widget.questionType)),
      body: Column(
        children: [
          // ── 搜索栏 ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '搜索题目材料…',
                prefixIcon:
                    const Icon(Icons.search, size: 20, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _clearSearch,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 14),
              textInputAction: TextInputAction.search,
              onSubmitted: _onSearch,
              onChanged: (v) => setState(() {}),
            ),
          ),

          // ── 搜索结果计数 ──
          if (_isSearchMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '找到 ${_questions.length} 条结果',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _clearSearch,
                    child: Text(
                      '返回全部',
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).primaryColor),
                    ),
                  ),
                ],
              ),
            ),

          // ── 列表 ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _questions.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(_isSearchMode ? '没有匹配的题目' : '暂无题目',
                              style: TextStyle(color: Colors.grey.shade400)),
                        ]),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _questions.length,
                        itemBuilder: (_, i) {
                          final q = _questions[i];
                          final title =
                              (q['title'] as String?) ?? '（无标题）';
                          final content = (q['content'] as String?) ?? '';
                          final year = q['year'];
                          final region = (q['region'] as String?) ?? '';
                          final qType =
                              (q['question_type'] as String?) ?? '';
                          final qId = q['id'] as String;
                          final isFaved = _favoriteIds.contains(qId);
                          final typeColor = _typeColor(qType);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          QuestionDetailScreen(
                                        questionId: qId,
                                        questionType:
                                            widget.questionType,
                                      ),
                                    )),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 14, 4, 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // 标签行：年份 + 题型 + 地区
                                            if (year != null ||
                                                qType.isNotEmpty ||
                                                region.isNotEmpty)
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  if (year != null)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                                0xFF4ECDC4)
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text('$year',
                                                          style: const TextStyle(
                                                              fontSize: 10,
                                                              color: Color(
                                                                  0xFF4ECDC4))),
                                                    ),
                                                  if (qType.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: typeColor
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        qType.length > 6
                                                            ? '${qType.substring(0, 6)}…'
                                                            : qType,
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: typeColor),
                                                      ),
                                                    ),
                                                  if (region.isNotEmpty)
                                                    Text(
                                                      region,
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          color: Colors
                                                              .grey.shade500),
                                                    ),
                                                ],
                                              ),
                                            const SizedBox(height: 6),
                                            _highlightText(title, _searchController.text.trim(),
                                                maxLines: 2,
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600, color: Colors.black)),
                                            if (content.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              _highlightText(content, _searchController.text.trim(),
                                                  maxLines: 3,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey.shade600)),
                                            ],
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                            isFaved
                                                ? Icons.bookmark
                                                : Icons.bookmark_border,
                                            color: isFaved
                                                ? const Color(0xFFE94560)
                                                : Colors.grey.shade400,
                                            size: 22),
                                        onPressed: () =>
                                            _toggleFavorite(qId),
                                        tooltip: isFaved
                                            ? '取消收藏'
                                            : '加入收藏',
                                        padding:
                                            const EdgeInsets.all(8),
                                        constraints:
                                            const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}


