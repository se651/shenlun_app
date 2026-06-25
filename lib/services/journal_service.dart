/// 积累本数据服务 — 每日笔记 + 复习提醒
import 'dart:convert';
import '../database/db_helper.dart';

class JournalEntry {
  final String id;
  final String date; // YYYY-MM-DD
  final String content;
  final String imagePath;
  List<String> tags;
  final String createdAt;
  String? reviewedAt;
  bool reviewed;

  JournalEntry({
    required this.id,
    required this.date,
    required this.content,
    this.imagePath = '',
    List<String>? tags,
    required this.createdAt,
    this.reviewedAt,
    this.reviewed = false,
  }) : tags = tags ?? [];

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'content': content,
    'imagePath': imagePath, 'tags': tags,
    'createdAt': createdAt, 'reviewedAt': reviewedAt, 'reviewed': reviewed,
  };

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
    id: json['id'] ?? '',
    date: json['date'] ?? '',
    content: json['content'] ?? '',
    imagePath: json['imagePath'] ?? '',
    tags: (json['tags'] as List?)?.cast<String>() ?? [],
    createdAt: json['createdAt'] ?? '',
    reviewedAt: json['reviewedAt'],
    reviewed: json['reviewed'] ?? false,
  );

  /// 是否需要复习（7/14/30天）
  bool get needsReview {
    if (reviewed) return false;
    if (date.isEmpty) return false;
    try {
      final d = DateTime.parse(date);
      final days = DateTime.now().difference(d).inDays;
      return days >= 7 || days >= 14 || days >= 30;
    } catch (_) { return false; }
  }
}

class JournalService {
  static const _key = 'journal_entries';

  static Future<List<JournalEntry>> loadAll() async {
    try {
      final db = DatabaseHelper();
      final raw = await db.getSetting(_key);
      if (raw.isEmpty) return [];
      final list = json.decode(raw) as List;
      return list.map((e) => JournalEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  static Future<void> saveAll(List<JournalEntry> entries) async {
    final db = DatabaseHelper();
    await db.setSetting(_key, json.encode(entries.map((e) => e.toJson()).toList()));
  }

  static Future<void> add(JournalEntry entry) async {
    final list = await loadAll();
    list.insert(0, entry);
    await saveAll(list);
  }

  static Future<void> update(JournalEntry entry) async {
    final list = await loadAll();
    final idx = list.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) list[idx] = entry;
    await saveAll(list);
  }

  static Future<void> delete(String id) async {
    final list = await loadAll();
    list.removeWhere((e) => e.id == id);
    await saveAll(list);
  }

  /// 获取待复习数量
  static Future<int> getReviewCount() async {
    final entries = await loadAll();
    return entries.where((e) => e.needsReview).length;
  }

  /// 某个日期的笔记
  static Future<List<JournalEntry>> getByDate(String date) async {
    final entries = await loadAll();
    return entries.where((e) => e.date == date).toList();
  }
}
