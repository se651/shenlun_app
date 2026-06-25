import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../database/db_helper.dart';
import '../services/journal_service.dart';
import '../services/news_cache.dart';

/// 通用政论文章详情页（先锋文汇 + 求是网评共用）
class ArticleDetailScreen extends StatefulWidget {
  final String title;
  final String date;
  final String articleUrl; // full URL or tid
  final bool isTid; // true if articleUrl is a tid for 12371.cn
  const ArticleDetailScreen({
    super.key,
    required this.title,
    required this.date,
    required this.articleUrl,
    this.isTid = false,
  });

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = await _fetchContent(widget.articleUrl, widget.isTid);
      if (mounted) setState(() { _content = content; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<String> _fetchContent(String url, bool isTid) async {
    final fetchUrl = isTid
        ? 'https://tougao.12371.cn/forum.php?mod=viewthread&tid=$url'
        : url.startsWith('http') ? url : 'https://www.qstheory.cn/$url';

    final resp = await http.get(Uri.parse(fetchUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
    }).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

    var html = utf8.decode(resp.bodyBytes, allowMalformed: true);
    // Remove style/script/nav/footer blocks
    html = html.replaceAll(RegExp(r'<(?:style|script|nav|header|footer)[^>]*>[\s\S]*?</(?:style|script|nav|header|footer)>', multiLine: true), '');
    // Replace <br> and </p> with newline
    html = html.replaceAll(RegExp(r'<(?:br|BR)\s*/?>'), '\n');
    html = html.replaceAll(RegExp(r'</p>'), '\n');
    html = html.replaceAll(RegExp(r'</div>'), '\n');
    // Strip remaining tags
    html = html.replaceAll(RegExp(r'<[^>]+>'), '');
    // Decode entities
    html = html.replaceAll('&emsp;', '').replaceAll('&ensp;', '').replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '\"').replaceAll('&emsp;', '');
    // Collapse whitespace but keep paragraph breaks
    final lines = html.split('\n');
    final all = <String>[];
    for (var line in lines) {
      line = line.replaceAll(RegExp(r'[\u2000-\u200f\s]+'), '');
      line = line.replaceAll(RegExp(r'^[　\s]+'), '').trim();
      if (line.isEmpty) continue;
      final cnCount = RegExp(r'[\u4e00-\u9fff]').allMatches(line).length;
      if (cnCount < 10) continue;
      // Stop at end-of-article markers
      if (line.contains('责编：') || line.contains('责任编辑：') || line.contains('(责编')) break;
      if (line.contains('人民日报社概况') || line.contains('人民网股份有限公司')) break;
      all.add(line);
    }

    // Return content from first article line to stop marker
    // Skip breadcrumb/title prefix lines
    int start = 0;
    for (int i = 0; i < all.length; i++) {
      if (all[i].contains('>>') || all[i].contains('求是网') && all[i].length < 80) continue;
      start = i;
      break;
    }
    // Find end: stop at 扫描/sharing/editor lines
    int end = all.length;
    for (int i = start; i < all.length; i++) {
      if (all[i].contains('扫描二维码') || all[i].contains('分享到手机') ||
          all[i].contains('校对-') || all[i].contains('网站编辑') ||
          all[i].contains('【网站声明】')) {
        end = i;
        break;
      }
    }
    if (end > start) {
      return all.sublist(start, end).join('\n\n');
    }
    return all.join('\n\n');
  }

  Future<void> _aiSummary(BuildContext parentContext) async {
    final db = DatabaseHelper();
    final apiKey = await db.getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先设置 DeepSeek API Key')));
      return;
    }

    var dialogActive = true;
    showDialog(context: context, barrierDismissible: true, builder: (_) => const Center(child: CircularProgressIndicator()))
        .whenComplete(() => dialogActive = false);

    try {
      final prompt = '你是申论备考助手。请将以下文章总结为一段150字以内的摘要，提炼核心论点和申论可用素材。\n\n${_content.length > 3000 ? _content.substring(0, 3000) : _content}';
      final r = await http.post(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
        body: jsonEncode({'model': 'deepseek-chat', 'messages': [
          {'role': 'system', 'content': '你是申论辅导专家。回复简洁，200字以内。'},
          {'role': 'user', 'content': prompt},
        ], 'temperature': 0.3, 'max_tokens': 400}),
      ).timeout(const Duration(seconds: 20));

      if (dialogActive) { Navigator.pop(context); dialogActive = false; }
      if (!mounted) return;

      if (r.statusCode == 200) {
        final ans = jsonDecode(r.body)['choices'][0]['message']['content'] as String;
        _showSummaryDialog(parentContext, ans);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI请求失败')));
      }
    } catch (_) {
      if (dialogActive) { Navigator.pop(context); dialogActive = false; }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网络错误')));
    }
  }

  void _showSummaryDialog(BuildContext ctx, String summary) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Row(children: [Icon(Icons.auto_awesome, color: Color(0xFFA29BFE), size: 18), SizedBox(width: 6), Text('AI 摘要', style: TextStyle(fontSize: 16))]),
      content: SingleChildScrollView(child: SelectableText(summary, style: const TextStyle(fontSize: 14, height: 1.8))),
      actions: [
        TextButton.icon(icon: const Icon(Icons.copy, size: 16), label: const Text('复制'), onPressed: () {
          Clipboard.setData(ClipboardData(text: summary));
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
        }),
        TextButton.icon(icon: const Icon(Icons.bookmark_add, size: 16), label: const Text('导入积累本'), onPressed: () async {
          final now = DateTime.now();
          await JournalService.add(JournalEntry(
            id: now.millisecondsSinceEpoch.toString(),
            date: '${now.year}-${now.month.toString().padLeft(2,"0")}-${now.day.toString().padLeft(2,"0")}',
            content: '【AI摘要】${widget.title}\n\n$summary',
            createdAt: now.toIso8601String(),
          ));
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已加入积累本'), duration: Duration(seconds: 1)));
        }),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文章详情'), actions: [
        _loading ? const SizedBox() : IconButton(
          icon: const Icon(Icons.auto_awesome),
          tooltip: 'AI总结',
          onPressed: () => _aiSummary(context),
        ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (widget.date.isNotEmpty)
                  Text(widget.date, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                SelectableText(
                  _content.isNotEmpty ? _content : '加载失败，请返回重试。',
                  style: const TextStyle(fontSize: 15, height: 1.9),
                ),
              ]),
            ),
    );
  }
}
