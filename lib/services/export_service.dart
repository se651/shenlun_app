import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory, getDownloadsDirectory;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../database/db_helper.dart';

class ExportService {
  /// 导出为 PDF，保存到下载目录，返回文件路径
  static Future<String> exportToPdf(String title, String content) async {
    // 加载中文字体（华文行楷）
    final fontData = await rootBundle.load('assets/fonts/STXingkai.ttf');
    final font = pw.Font.ttf(fontData);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Text(title, style: pw.TextStyle(font: font, fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Text(content, style: pw.TextStyle(font: font, fontSize: 12, height: 1.8)),
        ],
      ),
    );

    final bytes = await pdf.save();
    final dir = await _getSaveDir();
    final file = File('${dir.path}/$title.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// 导出为 DOCX，保存到下载目录，返回文件路径
  static Future<String> exportToDocx(String title, String content) async {
    final bytes = _buildDocx(title, content);
    final dir = await _getSaveDir();
    final file = File('${dir.path}/$title.docx');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// 获取保存目录（优先下载目录）
  static Future<Directory> _getSaveDir() async {
    try {
      final dl = await getDownloadsDirectory();
      if (dl != null) return dl;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  /// 手写最小有效的 .docx（Office Open XML）
  static List<int> _buildDocx(String title, String content) {
    final paragraphs = content.split('\n').where((l) => l.trim().isNotEmpty);
    final pXml = paragraphs.map(_escapeXmlParagraph).join();

    final docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
            xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
            xmlns:o="urn:schemas-microsoft-com:office:office"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
            xmlns:v="urn:schemas-microsoft-com:vml"
            xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="32"/></w:rPr>
        <w:t xml:space="preserve">${_escapeXml(title)}</w:t>
      </w:r>
    </w:p>
    <w:p><w:r><w:t xml:space="preserve"> </w:t></w:r></w:p>
$pXml
  </w:body>
</w:document>''';

    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    const docRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';

    final archive = Archive();
    final ctBytes = utf8.encode(contentTypesXml);
    final relsBytes = utf8.encode(relsXml);
    final docBytes = utf8.encode(docXml);
    final docRelsBytes = utf8.encode(docRelsXml);
    archive.addFile(ArchiveFile('[Content_Types].xml', ctBytes.length, ctBytes));
    archive.addFile(ArchiveFile('_rels/.rels', relsBytes.length, relsBytes));
    archive.addFile(ArchiveFile('word/document.xml', docBytes.length, docBytes));
    archive.addFile(ArchiveFile('word/_rels/document.xml.rels', docRelsBytes.length, docRelsBytes));

    return ZipEncoder().encode(archive)!;
  }

  static String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _escapeXmlParagraph(String line) {
    return '    <w:p><w:r><w:t xml:space="preserve">${_escapeXml(line)}</w:t></w:r></w:p>';
  }

  /// 保存到指定路径的 PDF（用户选择的位置）
  static Future<String> exportToPdfAt(String path, String title, String content) async {
    final fontData = await rootBundle.load('assets/fonts/STXingkai.ttf');
    final font = pw.Font.ttf(fontData);
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text(title, style: pw.TextStyle(font: font, fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.Text(content, style: pw.TextStyle(font: font, fontSize: 12, height: 1.8)),
      ],
    ));
    final bytes = await pdf.save();
    final file = File(path);
    await file.writeAsBytes(bytes);
    await _recordDownload(path, 'pdf', title);
    return path;
  }

  /// 保存到指定路径的 DOCX
  static Future<String> exportToDocxAt(String path, String title, String content) async {
    final bytes = _buildDocx(title, content);
    final file = File(path);
    await file.writeAsBytes(bytes);
    await _recordDownload(path, 'docx', title);
    return path;
  }

  /// 保存材料到下载列表（不导出文件，仅记录）
  static Future<void> saveToDownloadList(String title, String content) async {
    try {
      final db = DatabaseHelper();
      final historyJson = await db.getSetting('download_history');
      final List<dynamic> list = historyJson.isNotEmpty
          ? json.decode(historyJson) as List<dynamic>
          : [];
      list.insert(0, {
        'title': title,
        'content': content,
        'format': '',
        'path': '',
        'date': DateTime.now().toIso8601String(),
      });
      if (list.length > 50) list.removeRange(50, list.length);
      await db.setSetting('download_history', json.encode(list));
    } catch (_) {}
  }

  /// 生成 PDF 字节（不保存文件）
  static Future<Uint8List> buildPdfBytes(String title, String content) async {
    final fontData = await rootBundle.load('assets/fonts/STXingkai.ttf');
    final font = pw.Font.ttf(fontData);
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text(title, style: pw.TextStyle(font: font, fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.Text(content, style: pw.TextStyle(font: font, fontSize: 12, height: 1.8)),
      ],
    ));
    return await pdf.save();
  }

  /// 生成 DOCX 字节（不保存文件）
  static Uint8List buildDocxBytes(String title, String content) {
    return Uint8List.fromList(_buildDocx(title, content));
  }

  /// 导出后更新记录
  static Future<void> recordExport(String path, String fmt, String title) async {
    await _recordDownload(path, fmt, title);
  }

  /// 记录下载历史
  static Future<void> _recordDownload(String path, String fmt, String title) async {
    try {
      final db = DatabaseHelper();
      final historyJson = await db.getSetting('download_history');
      final List<dynamic> list = historyJson.isNotEmpty
          ? json.decode(historyJson) as List<dynamic>
          : [];
      list.insert(0, {
        'path': path,
        'format': fmt,
        'title': title,
        'date': DateTime.now().toIso8601String(),
      });
      if (list.length > 50) list.removeRange(50, list.length);
      await db.setSetting('download_history', json.encode(list));
    } catch (_) {}
  }

  /// 获取下载历史
  static Future<List<Map<String, dynamic>>> getDownloadHistory() async {
    try {
      final db = DatabaseHelper();
      final raw = await db.getSetting('download_history');
      if (raw.isEmpty) return [];
      return (json.decode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// 删除下载记录
  static Future<void> removeRecord(int index) async {
    final list = await getDownloadHistory();
    if (index < list.length) list.removeAt(index);
    final db = DatabaseHelper();
    await db.setSetting('download_history', json.encode(list));
  }
}
