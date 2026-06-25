/// 习主席讲话列表页 — 缓存秒开 + 手动检查更新
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/xjp_speech_scraper.dart';
import '../services/xjp_speech_cache.dart';
import 'xjp_speech_detail_screen.dart';

class XjpSpeechListScreen extends StatefulWidget {
  const XjpSpeechListScreen({super.key});

  @override
  State<XjpSpeechListScreen> createState() => _XjpSpeechListScreenState();
}

class _XjpSpeechListScreenState extends State<XjpSpeechListScreen> {
  final _scraper = XjpSpeechScraper();
  final _searchCtl = TextEditingController();
  List<XjpSpeech> _allSpeeches = [];
  List<XjpSpeech> _filtered = [];
  bool _loading = true;
  bool _checkingUpdate = false;   // 检查更新中
  bool _fullFetching = false;     // 全量拉取中
  String? _error;
  String _statusMsg = '';         // 更新结果提示

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// 读缓存 → 秒开（设备缓存 > 内置 asset > 空）
  Future<void> _loadCache() async {
    setState(() { _loading = true; _error = null; });

    String? jsonStr;
    // 1. 先读设备缓存
    try {
      jsonStr = await readXjpSpeechCache();
    } catch (_) {}

    // 2. 设备为空 → 读内置 asset
    if (jsonStr == null || jsonStr.isEmpty) {
      try {
        jsonStr = await rootBundle.loadString('assets/xjp_speech_cache.json');
        // 写入设备缓存，后续秒开
        if (jsonStr.isNotEmpty) {
          await writeXjpSpeechCache(jsonStr);
        }
      } catch (_) {}
    }

    // 3. 解析
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final list = (json.decode(jsonStr) as List)
            .map((e) => XjpSpeech.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() { _allSpeeches = list; _filtered = list; _loading = false; });
          return;
        }
      } catch (_) {}
    }

    // 4. 都没有 → 提示用户手动拉取
    if (mounted) setState(() => _loading = false);
  }

  /// 检查更新：查最近 3 天日期 JSON，有新增就缓存
  Future<void> _checkUpdate() async {
    if (_checkingUpdate || _fullFetching) return;
    setState(() { _checkingUpdate = true; _statusMsg = ''; });

    try {
      final newItems = await _scraper.fetchRecentDays(days: 3);
      final oldCount = _allSpeeches.length;

      final merged = XjpSpeechScraper.mergeNew(_allSpeeches, newItems);
      final added = merged.length - oldCount;

      if (added > 0) {
        _allSpeeches = merged;
        _applyFilter();
        await writeXjpSpeechCache(json.encode(_allSpeeches.map((e) => e.toJson()).toList()));
        if (mounted) setState(() => _statusMsg = '新增 $added 篇');
      } else {
        if (mounted) setState(() => _statusMsg = '已是最新');
      }
    } catch (e) {
      if (mounted) setState(() => _statusMsg = '检查失败，请重试');
    }

    if (mounted) setState(() => _checkingUpdate = false);
    // 3 秒后自动消失
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _statusMsg = '');
    });
  }

  /// 全量拉取（下拉刷新 / 首次无缓存）
  Future<void> _doFullFetch() async {
    if (_checkingUpdate || _fullFetching) return;
    _fullFetching = true;
    if (_allSpeeches.isEmpty) setState(() => _statusMsg = '首次加载，正在拉取数据…');

    try {
      final speeches = await _scraper.fetchAll(
        onProgress: (current, total) {
          if (mounted) setState(() => _statusMsg = '加载中 $current/$total');
        },
      );
      if (speeches.isNotEmpty) {
        _allSpeeches = speeches;
        _applyFilter();
        await writeXjpSpeechCache(json.encode(_allSpeeches.map((e) => e.toJson()).toList()));
        if (mounted) setState(() => _statusMsg = '');
      }
    } catch (e) {
      if (_allSpeeches.isEmpty && mounted) {
        setState(() => _error = '加载失败');
      }
    }

    _fullFetching = false;
    if (mounted) setState(() { _loading = false; _statusMsg = ''; });
  }

  void _applyFilter() {
    final query = _searchCtl.text.trim();
    if (query.isEmpty) {
      _filtered = List.from(_allSpeeches);
    } else {
      _filtered = _allSpeeches.where((s) =>
          s.title.contains(query) || s.snippet.contains(query)
      ).toList();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final fetching = _checkingUpdate || _fullFetching;
    return Scaffold(
      appBar: AppBar(
        title: const Text('习主席讲话数据库'),
        actions: [
          if (fetching)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _doFullFetch,
              tooltip: '全量刷新',
            ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: '搜索讲话标题或内容…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18),
                        onPressed: () { _searchCtl.clear(); _applyFilter(); })
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFC62828), width: 1.5),
                ),
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (_) => _applyFilter(),
            ),
          ),
          // 状态栏：统计 + 检查更新按钮
          if (!_loading && _allSpeeches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Text('共 ${_allSpeeches.length} 篇',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                if (_filtered.length != _allSpeeches.length) ...[
                  const SizedBox(width: 8),
                  Text('（筛选出 ${_filtered.length} 篇）',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFC62828))),
                ],
                const Spacer(),
                // 状态消息
                if (_statusMsg.isNotEmpty && !fetching)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(_statusMsg,
                        style: TextStyle(
                          fontSize: 12,
                          color: _statusMsg.startsWith('新增') ? const Color(0xFF2E7D32) : Colors.grey.shade500,
                          fontWeight: _statusMsg.startsWith('新增') ? FontWeight.w600 : FontWeight.normal,
                        )),
                  ),
                // 检查更新按钮
                _buildUpdateButton(),
              ]),
            ),
          // 全量拉取进度
          if (_fullFetching && _statusMsg.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFFC62828).withOpacity(0.08),
              child: Row(children: [
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                const SizedBox(width: 10),
                Text(_statusMsg, style: const TextStyle(fontSize: 12, color: Color(0xFFC62828))),
              ]),
            ),
          // 列表
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildUpdateButton() {
    if (_allSpeeches.isEmpty) return const SizedBox.shrink();
    if (_checkingUpdate) {
      return const SizedBox(
        width: 14, height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    return SizedBox(
      height: 28,
      child: TextButton.icon(
        onPressed: _checkUpdate,
        icon: const Icon(Icons.cloud_download_outlined, size: 14),
        label: const Text('检查更新', style: TextStyle(fontSize: 11)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: const Color(0xFFC62828),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: const Color(0xFFC62828).withOpacity(0.3)),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _allSpeeches.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: Colors.grey.shade500)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () { _error = null; _loadCache(); },
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重试'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC62828), foregroundColor: Colors.white,
          ),
        ),
      ]));
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(_searchCtl.text.isNotEmpty ? '没有匹配的讲话' : '暂无数据',
              style: TextStyle(color: Colors.grey.shade500)),
          if (_searchCtl.text.isEmpty) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _doFullFetch,
              icon: const Icon(Icons.cloud_download, size: 16),
              label: const Text('从网络拉取数据'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC62828), foregroundColor: Colors.white,
              ),
            ),
          ],
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _doFullFetch,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _filtered.length,
        itemBuilder: (_, i) {
          final s = _filtered[i];
          return _SpeechCard(
            speech: s,
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => XjpSpeechDetailScreen(speech: s),
            )),
          );
        },
      ),
    );
  }
}

class _SpeechCard extends StatelessWidget {
  final XjpSpeech speech;
  final VoidCallback onTap;
  const _SpeechCard({required this.speech, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(speech.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.source_outlined, size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(speech.source, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(width: 10),
                Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(speech.date, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
              ]),
              if (speech.snippet.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(speech.snippet,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.5),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
