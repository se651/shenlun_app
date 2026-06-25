import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/db_helper.dart';
import '../services/journal_service.dart';
import '../services/export_service.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  DateTime _selectedDate = DateTime.now();
  List<JournalEntry> _entries = [];
  int _reviewCount = 0;
  bool _loading = true;
  bool _aiOrganizing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await JournalService.getByDate(_dateKey());
    final reviewCount = await JournalService.getReviewCount();
    if (mounted) setState(() { _entries = entries; _reviewCount = reviewCount; _loading = false; });
  }

  String _dateKey([DateTime? d]) {
    final t = d ?? _selectedDate;
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  String _todayKey() => _dateKey(DateTime.now());
  bool get _isToday => _dateKey() == _todayKey();

  Future<void> _addEntry({String content = '', String imagePath = ''}) async {
    final ctrl = TextEditingController(text: content);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_dateKey()} 笔记'),
        content: TextField(controller: ctrl, maxLines: 6,
          decoration: const InputDecoration(hintText: '记录一些素材或想法...', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result != null && (result.isNotEmpty || imagePath.isNotEmpty)) {
      final entry = JournalEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: _dateKey(),
        content: result ?? '',
        imagePath: imagePath,
        createdAt: DateTime.now().toIso8601String(),
      );
      await JournalService.add(entry);
      _load();
    }
  }

  Future<void> _addImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (picked != null) {
      await _addEntry(imagePath: picked.path);
    }
  }

  Future<void> _markReviewed(JournalEntry entry) async {
    entry.reviewed = true;
    entry.reviewedAt = DateTime.now().toIso8601String();
    await JournalService.update(entry);
    _load();
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    await JournalService.delete(entry.id);
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  Future<void> _exportPage() async {
    if (_entries.isEmpty) return;
    final content = _entries.map((e) {
      var text = e.content;
      if (e.imagePath.isNotEmpty) text += '\n[图片: ${e.imagePath}]';
      if (e.tags.isNotEmpty) text += '\n标签: ${e.tags.join(", ")}';
      return text;
    }).join('\n\n---\n\n');
    
    final title = '素材积累_$_dateKey()';
    final bytes = ExportService.buildDocxBytes(title, content);
    
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出积累本',
      fileName: '$title.docx',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );
    
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出: ${path.split(Platform.pathSeparator).last}'), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _aiOrganize() async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「我的」设置 DeepSeek API Key')),
      );
      return;
    }
    if (_entries.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当天没有笔记需要整理')),
      );
      return;
    }
    setState(() => _aiOrganizing = true);
    try {
      // 收集当天笔记
      final contents = _entries.map((e) => e.content).join('\n---\n');
      final result = await _callAIOrganize(apiKey, contents);
      if (result != null && result.isNotEmpty) {
        // AI 返回分类结果：每行格式为 "分类：内容摘要"
        final tags = result.split('\n').where((l) => l.contains('：') || l.contains(':')).toList();
        if (tags.isNotEmpty) {
          for (final e in _entries) {
            for (final tag in tags) {
              final parts = tag.split(RegExp(r'[：:]'));
              if (parts.length >= 2 && e.content.contains(parts[1].trim().substring(0, parts[1].trim().length.clamp(0, 20)))) {
                e.tags = [parts[0].trim()];
                await JournalService.update(e);
                break;
              }
            }
          }
          _load();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已按 ${tags.length} 个分类整理完成')),
          );
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 整理完成，标签已更新')),
        );
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 整理失败')),
      );
    }
    if (mounted) setState(() => _aiOrganizing = false);
  }

  Future<String?> _callAIOrganize(String apiKey, String contents) async {
    final response = await http.post(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {'role': 'system', 'content': '你是素材整理助手。根据以下笔记内容，按主题分类（如：政治理论、经济发展、民生保障、生态环保、文化教育、科技人才等），为每段内容标注最合适的分类。每行输出格式：分类：内容前20字。只输出分类结果，不要其他说明。'},
          {'role': 'user', 'content': contents.length > 3000 ? contents.substring(0, 3000) : contents},
        ],
        'temperature': 0.3,
        'max_tokens': 500,
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    return data['choices']?[0]?['message']?['content'] as String?;
  }

  void _prevDay() {
    setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
    _load();
  }

  void _nextDay() {
    if (_isToday) return;
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('素材积累本'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, size: 20),
            tooltip: '导出当前页',
            onPressed: _entries.isEmpty ? null : _exportPage,
          ),
          IconButton(
            icon: Icon(_aiOrganizing ? Icons.hourglass_top : Icons.auto_awesome, size: 20),
            tooltip: 'AI 整理',
            onPressed: _aiOrganizing ? null : _aiOrganize,
          ),
          if (_reviewCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: const Icon(Icons.notifications_active, size: 16, color: Colors.white),
                label: Text('$_reviewCount 待复习', style: const TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: const Color(0xFFE94560),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
      body: Column(children: [
        // 日期导航
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevDay),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _isToday ? const Color(0xFFE94560).withOpacity(0.08) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isToday ? '今天 ${_dateKey()}' : _dateKey(),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: _isToday ? const Color(0xFFE94560) : const Color(0xFF1A1A2E)),
                ),
              ),
            ),
            IconButton(
              icon: Icon(_isToday ? Icons.chevron_right : Icons.chevron_right, color: _isToday ? Colors.grey.shade300 : null),
              onPressed: _isToday ? null : _nextDay,
            ),
          ]),
        ),
        // 笔记列表
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.edit_note_rounded, size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(_isToday ? '今天还没有笔记' : '当日无笔记', style: TextStyle(color: Colors.grey.shade400)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('添加笔记'),
                          onPressed: () => _addEntry(),
                        ),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) {
                        final e = _entries[i];
                        return Dismissible(
                          key: Key(e.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => _deleteEntry(e),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                // Tags
                                if (e.tags.isNotEmpty)
                                  Wrap(spacing: 4, children: e.tags.map((t) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFF4ECDC4).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                    child: Text(t, style: const TextStyle(fontSize: 10, color: Color(0xFF4ECDC4))),
                                  )).toList()),
                                if (e.tags.isNotEmpty) const SizedBox(height: 8),
                                // Content
                                Text(e.content, style: const TextStyle(fontSize: 14, height: 1.7)),
                                // Image
                                if (e.imagePath.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(File(e.imagePath), fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        height: 120, color: Colors.grey.shade100,
                                        child: const Icon(Icons.broken_image, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                // Actions
                                Row(children: [
                                  if (e.needsReview)
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.check, size: 14),
                                      label: const Text('标记已复习', style: TextStyle(fontSize: 12)),
                                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE94560), padding: const EdgeInsets.symmetric(horizontal: 10)),
                                      onPressed: () => _markReviewed(e),
                                    ),
                                  const Spacer(),
                                  Text(e.createdAt.length >= 10 ? e.createdAt.substring(0, 16) : '',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                                ]),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButton: _isToday
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              FloatingActionButton.small(
                heroTag: 'img',
                backgroundColor: const Color(0xFF4ECDC4),
                onPressed: () => _addImage(),
                child: const Icon(Icons.image_outlined),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: 'add',
                onPressed: () => _addEntry(),
                child: const Icon(Icons.add),
              ),
            ])
          : null,
    );
  }
}
