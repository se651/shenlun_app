/// 习主席讲话详情页 — 全文展示 + AI 总结 + 复制 + 导入积累本
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/xjp_speech_scraper.dart';
import '../services/journal_service.dart';
import '../database/db_helper.dart';

class XjpSpeechDetailScreen extends StatefulWidget {
  final XjpSpeech speech;
  const XjpSpeechDetailScreen({super.key, required this.speech});

  @override
  State<XjpSpeechDetailScreen> createState() => _XjpSpeechDetailScreenState();
}

class _XjpSpeechDetailScreenState extends State<XjpSpeechDetailScreen> {
  String _summary = '';
  bool _summarizing = false;
  String? _summaryError;

  @override
  Widget build(BuildContext context) {
    final s = widget.speech;
    final hasContent = s.content.isNotEmpty && s.content.length > 20;

    return Scaffold(
      appBar: AppBar(title: const Text('讲话全文')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Text(s.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
            const SizedBox(height: 12),
            // 来源 + 日期
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(s.source,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFC62828))),
              ),
              const SizedBox(width: 10),
              Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(s.date, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // 正文
            if (hasContent)
              SelectableText(
                s.content,
                style: const TextStyle(fontSize: 15, height: 2.0),
              )
            else
              Center(
                child: Column(children: [
                  const SizedBox(height: 20),
                  Icon(Icons.article_outlined, size: 40, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(s.snippet.isNotEmpty ? s.snippet : '暂无内容',
                      style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.8)),
                ]),
              ),

            const SizedBox(height: 32),
            const Divider(),

            // ── AI 总结区域 ──
            if (_summarizing) ...[
              const SizedBox(height: 20),
              const Center(child: Column(children: [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(height: 12),
                Text('AI 正在总结…', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ])),
            ] else if (_summaryError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, size: 18, color: Colors.red.shade300),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_summaryError!, style: TextStyle(fontSize: 13, color: Colors.red.shade700))),
                ]),
              ),
            ] else if (_summary.isNotEmpty) ...[
              const SizedBox(height: 16),
              // 总结标题行
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFC62828), Color(0xFFE94560)]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('AI 总结', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const Spacer(),
                // 复制按钮
                _SmallButton(
                  icon: Icons.copy, label: '复制',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _summary));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // 导入积累本按钮
                _SmallButton(
                  icon: Icons.bookmark_add, label: '导入积累本',
                  color: const Color(0xFF4ECDC4),
                  onTap: () => _importToJournal(),
                ),
              ]),
              const SizedBox(height: 10),
              // 总结内容
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828).withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFC62828).withOpacity(0.12)),
                ),
                child: SelectableText(
                  _summary,
                  style: const TextStyle(fontSize: 14, height: 1.9),
                ),
              ),
            ],
          ],
        ),
      ),
      // ── 底部 AI 总结按钮 ──
      bottomNavigationBar: _summarizing || _summary.isNotEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: hasContent ? _doSummarize : null,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('AI 总结本文', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _doSummarize() async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      setState(() => _summaryError = '请先在「我的」页面设置 DeepSeek API Key');
      return;
    }

    final content = widget.speech.content;
    if (content.length < 50) {
      setState(() => _summaryError = '文章内容太短，无法总结');
      return;
    }

    setState(() { _summarizing = true; _summaryError = null; });

    try {
      final summary = await _callDeepSeek(apiKey, widget.speech.title, content);
      if (mounted) setState(() { _summary = summary; _summarizing = false; });
    } catch (e) {
      if (mounted) setState(() { _summaryError = '总结失败：$e'; _summarizing = false; });
    }
  }

  Future<String> _callDeepSeek(String apiKey, String title, String content) async {
    // 截取前 8000 字发给 AI（节省 token）
    final input = content.length > 8000 ? content.substring(0, 8000) : content;

    final response = await http.post(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {
            'role': 'system',
            'content': '你是申论备考助手。请用 200-400 字概括以下讲话/文章的核心观点和框架，提取可用于申论写作的金句（3-5句），并用提纲形式列出文章的逻辑结构。格式：\n\n【核心观点】…\n【逻辑框架】\n1. …\n2. …\n【可引用金句】\n• …\n• …',
          },
          {
            'role': 'user',
            'content': '标题：$title\n\n正文：$input',
          },
        ],
        'temperature': 0.3,
        'max_tokens': 1000,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('API 返回 ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final text = data['choices']?[0]?['message']?['content'] as String?;
    if (text == null || text.isEmpty) throw Exception('API 返回空内容');
    return text.trim();
  }

  Future<void> _importToJournal() async {
    final title = widget.speech.title;
    final date = widget.speech.date;
    final source = widget.speech.source;
    final entryContent = '【${title}】\n来源：$source  $date\n\n$_summary';

    final entry = JournalEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
      content: entryContent,
      tags: ['习主席讲话', 'AI总结'],
      createdAt: DateTime.now().toIso8601String(),
    );

    await JournalService.add(entry);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已导入积累本'), duration: Duration(seconds: 2)),
      );
    }
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _SmallButton({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFFC62828);
    return SizedBox(
      height: 28,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 13),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: c,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: c.withOpacity(0.3)),
          ),
        ),
      ),
    );
  }
}
