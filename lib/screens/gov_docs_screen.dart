import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/web_data_loader.dart';
import 'package:path/path.dart' as p;

class GovDocsScreen extends StatefulWidget {
  const GovDocsScreen({super.key});
  @override State<GovDocsScreen> createState() => _GovDocsScreenState();
}

class _GovDocsScreenState extends State<GovDocsScreen> {
  static Database? _cachedDb;
  Database? get _db => _cachedDb;
  List<String> _types = [];
  String? _selectedType;
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _allDocs = [];
  Map<String, dynamic>? _detail;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (kIsWeb) {
      _allDocs = await WebDataLoader().loadGovDocs();
      final counts = <String, int>{};
      for (final d in _allDocs) { final t = d['doc_type'] as String? ?? '其他'; counts[t] = (counts[t] ?? 0) + 1; }
      _types = counts.entries.map((e) => e.key).toList()..sort((a,b) => (counts[b]??0).compareTo(counts[a]??0));
      if (_types.isNotEmpty) _selectedType = _types.first;
    } else {
      if (_cachedDb == null) _cachedDb = await _openDb();
      if (_cachedDb == null) return;
      final rows = await _cachedDb!.rawQuery('SELECT doc_type, COUNT(*) as cnt FROM docs GROUP BY doc_type ORDER BY cnt DESC');
      _types = rows.map((r) => r['doc_type'] as String).toList();
      if (_types.isNotEmpty) _selectedType = _types.first;
    }
    await _loadDocs();
    if (mounted) setState(() {});
  }

  Future<Database?> _openDb() async {
    try {
      final data = await rootBundle.load('assets/gov_docs.db');
      final dir = await getDatabasesPath();
      final path = p.join(dir, 'gov_docs_temp.db');
      if (!File(path).existsSync()) await File(path).writeAsBytes(data.buffer.asUint8List());
      return await openDatabase(path, readOnly: true);
    } catch (_) { return null; }
  }

  Future<void> _loadDocs() async {
    if (_selectedType == null) return;
    if (kIsWeb) {
      _docs = _allDocs.where((d) => d['doc_type'] == _selectedType).toList();
    } else {
      if (_cachedDb == null) return;
      _docs = await _cachedDb!.rawQuery('SELECT id, title, org, doc_number, date, substr(body,1,120) as preview FROM docs WHERE doc_type = ? ORDER BY id DESC', [_selectedType]);
    }
  }

  Future<void> _showDetail(int id) async {
    if (kIsWeb) {
      final m = _allDocs.where((d) => d['id'] == id).toList();
      if (m.isNotEmpty) setState(() => _detail = m.first);
      return;
    }
    final rows = await _cachedDb!.rawQuery('SELECT * FROM docs WHERE id = ?', [id]);
    if (rows.isNotEmpty) setState(() => _detail = rows.first);
  }

  @override void dispose() { _cachedDb?.close(); _cachedDb = null; super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_types.isEmpty) return Scaffold(appBar: AppBar(title: const Text('公文示例')), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text('公文示例（${_types.length} 类）')),
      body: _detail != null ? _buildDetailView() : _buildListView(),
    );
  }

  Widget _buildListView() {
    return Row(children: [
      SizedBox(width: 90, child: ListView(children: _types.map((t) {
        final active = t == _selectedType;
        return GestureDetector(
          onTap: () async { _selectedType = t; await _loadDocs(); setState(() {}); },
          child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            color: active ? const Color(0xFFE94560).withOpacity(0.08) : null,
            child: Text(t, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w400, color: active ? const Color(0xFFE94560) : const Color(0xFF333333))),
          ),
        );
      }).toList())),
      Container(width: 1, color: Colors.grey.shade200),
      Expanded(child: _docs.isEmpty ? const Center(child: Text('暂无内容')) : ListView.separated(
        itemCount: _docs.length, separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final d = _docs[i];
          final preview = (kIsWeb ? (d['body'] as String? ?? '') : (d['preview'] as String? ?? '')).toString();
          return ListTile(
            dense: true,
            title: Text(d['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            subtitle: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            onTap: () => _showDetail(kIsWeb ? (d['id'] is int ? d['id'] as int : 0) : (d['id'] as int)),
          );
        },
      )),
    ]);
  }

  Widget _buildDetailView() {
    final d = _detail!;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      GestureDetector(
        onTap: () => setState(() => _detail = null),
        child: const Row(children: [Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFFE94560)), SizedBox(width: 4), Text('返回列表', style: TextStyle(fontSize: 12, color: Color(0xFFE94560)))]),
      ),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFE94560).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
        child: Text(d['doc_type'] as String? ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFFE94560), fontWeight: FontWeight.w600))),
      const SizedBox(height: 8),
      Text(d['title'] as String? ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.5)),
      const SizedBox(height: 8),
      if ((d['org'] as String?)?.isNotEmpty == true) Text('发文机构：${d['org']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      if ((d['doc_number'] as String?)?.isNotEmpty == true) Text('发文字号：${d['doc_number']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      if ((d['date'] as String?)?.isNotEmpty == true) Text('日期：${d['date']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(height: 16), const Divider(), const SizedBox(height: 12),
      _renderBody(d['body'] as String? ?? ''),
      const SizedBox(height: 60),
    ]));
  }

  Widget _renderBody(String text) {
    text = _cleanBody(text);
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final sigStart = _findSigStart(lines);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (int i = 0; i < lines.length; i++)
        i >= sigStart
          ? Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText(lines[i].trim(), style: const TextStyle(fontSize: 14, height: 1.8))))
          : SelectableText(lines[i], style: const TextStyle(fontSize: 14, height: 1.8)),
    ]);
  }

  String _cleanBody(String text) {
    text = text.replaceAll(RegExp(r'首页\s+.*?(?=通知公告|\n\S)', dotAll: true), '');
    text = text.replaceAll(RegExp(r'字号：[大中小]+\s*\n+'), '');
    text = text.replaceAll(RegExp(r'[京津]政[发字函][\d〔（][^\n]*\n+'), '');
    text = text.replaceAll(RegExp(r'您当前的位置：.*?\n+'), '');
    text = text.replaceAll(RegExp(r'^\s*(?:民政资讯|政务公开|办事服务|政策法规|互动平台|通知公告|当前位置)\s*$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'begin-->.*?end-->\s*', dotAll: true), '');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  int _findSigStart(List<String> lines) {
    for (int i = lines.length - 1; i >= lines.length - 5 && i > 0; i--) {
      final p = lines[i].trim();
      if (p.isEmpty || p.length > 60) continue;
      final isDate = RegExp(r'\d{4}年\d{1,2}月\d{1,2}日').hasMatch(p);
      final isOrg = p.endsWith('人民政府') || p.endsWith('管理局') || p.endsWith('委员会') || p.endsWith('组织部') || p.endsWith('办公室') || p.endsWith('党委') || p.endsWith('中共') || p.endsWith('共青团') || p.endsWith('公司') || p.endsWith('大队');
      if (isDate || isOrg) {
        int start = i;
        while (start > 0 && lines[start-1].trim().length < 50 && !lines[start-1].trim().endsWith('。') && !lines[start-1].trim().endsWith('！')) { start--; }
        return start;
      }
    }
    return lines.length;
  }
}
