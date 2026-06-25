import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import '../services/export_service.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});
  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const _fixedItemTitle = '申论答题纸（标准格子纸）';
  static const _fixedItemKey = '__fixed_answer_sheet__';
  String? _fixedFilePath;

  Future<void> _load() async {
    // 确保固定答题纸已复制到本地
    if (_fixedFilePath == null) {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/answer_sheet.pdf');
      if (!await dest.exists()) {
        final data = await rootBundle.load('assets/answer_sheet.pdf');
        await dest.writeAsBytes(data.buffer.asUint8List());
      }
      _fixedFilePath = dest.path;
    }

    final items = await ExportService.getDownloadHistory();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _exportItem(int index, String fmt) async {
    final item = _items[index];
    final title = item['title'] as String? ?? '材料';
    final content = item['content'] as String? ?? '';
    final ext = fmt == 'pdf' ? 'pdf' : 'docx';
    try {
      // 先生成文件字节
      final bytes = fmt == 'pdf'
          ? await ExportService.buildPdfBytes(title, content)
          : ExportService.buildDocxBytes(title, content);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '选择导出位置',
        fileName: '$title.$ext',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (path == null) return;
      // 记录导出历史
      ExportService.recordExport(path, fmt, title);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出: ${path.split('/').last}'), duration: const Duration(seconds: 2)),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _shareItem(int index) async {
    final item = _items[index];
    final title = item['title'] as String? ?? '材料';
    final content = item['content'] as String? ?? '';

    final fmt = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFE94560)),
            title: const Text('分享为 PDF'),
            subtitle: const Text('通用格式，任何设备可打开'),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.description, color: Color(0xFF2B579A)),
            title: const Text('分享为 DOCX'),
            subtitle: const Text('Word 文档，方便继续编辑'),
            onTap: () => Navigator.pop(ctx, 'docx'),
          ),
        ]),
      ),
    );
    if (fmt == null) return;

    try {
      final ext = fmt == 'pdf' ? 'pdf' : 'docx';
      final bytes = fmt == 'pdf'
          ? await ExportService.buildPdfBytes(title, content)
          : ExportService.buildDocxBytes(title, content);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$title.$ext');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: title,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _deleteAt(int index) {
    final item = _items[index];
    if (item['fixed'] == true) return; // 固定项不可删除
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除材料'),
        content: Text('确定删除「${item['title']}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final path = item['path'] as String? ?? '';
              if (path.isNotEmpty) {
                try { File(path).deleteSync(); } catch (_) {}
              }
              ExportService.removeRecord(index);
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的下载')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _items.length + 1, // +1 for fixed item
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    // 固定答题纸卡片
                    if (i == 0) {
                      return _buildFixedCard();
                    }
                    final item = _items[i - 1];
                    final title = item['title'] as String? ?? '未命名';
                    final date = item['date'] as String? ?? '';
                    final exported = (item['path'] as String? ?? '').isNotEmpty;

                    return Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: exported ? Colors.green.shade50 : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                exported ? Icons.check_circle_outline : Icons.description_outlined,
                                color: exported ? Colors.green : Colors.orange,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '${date.length >= 10 ? date.substring(0, 10) : date} · ${exported ? "已导出" : "未导出"}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ]),
                            ),
                            if (i > 0)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                onPressed: () => _deleteAt(i - 1),
                              ),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.description, size: 16),
                                label: const Text('导出 DOCX'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2B579A),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _exportItem(i - 1, 'docx'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.picture_as_pdf, size: 16),
                                label: const Text('导出 PDF'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFE94560),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _exportItem(i - 1, 'pdf'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('分享'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4CAF50),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () => _shareItem(i - 1),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildFixedCard() {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFFFF8E1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFFA000), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFA000).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.article, color: Color(0xFFFFA000), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_fixedItemTitle, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text('固定 · 可打印和分享', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
            const Icon(Icons.lock, size: 16, color: Color(0xFFFFA000)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.print, size: 16),
                label: const Text('打印'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF5D4037),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () => _printSheet(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: const Text('分享'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4CAF50),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () => _shareSheet(),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _printSheet() async {
    if (_fixedFilePath != null) {
      try {
        await OpenFile.open(_fixedFilePath!);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请安装 PDF 阅读器后重试'), duration: Duration(seconds: 2)),
          );
        }
      }
    }
  }

  Future<void> _shareSheet() async {
    if (_fixedFilePath != null) {
      await Share.shareXFiles(
        [XFile(_fixedFilePath!)],
        subject: _fixedItemTitle,
      );
    }
  }
}
