/// 模拟题数据服务 — 生成记录保存、历史管理
import 'dart:convert';
import '../database/db_helper.dart';

class MockExam {
  final String id;
  final String title;      // 主题名称
  final String questionType; // 题型: 概括归纳题/大作文/整套题目 等
  final String material;    // 给定材料
  final String questions;   // 题目内容（含作答要求）
  String userAnswer;        // 用户答案
  String aiAnalysis;        // AI 评分+分析
  final String source;      // 'theme' 或 'concept'
  final String createdAt;

  MockExam({
    required this.id,
    required this.title,
    required this.questionType,
    required this.material,
    required this.questions,
    this.userAnswer = '',
    this.aiAnalysis = '',
    required this.source,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'questionType': questionType,
    'material': material,
    'questions': questions,
    'userAnswer': userAnswer,
    'aiAnalysis': aiAnalysis,
    'source': source,
    'createdAt': createdAt,
  };

  factory MockExam.fromJson(Map<String, dynamic> json) => MockExam(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    questionType: json['questionType'] ?? '',
    material: json['material'] ?? '',
    questions: json['questions'] ?? '',
    userAnswer: json['userAnswer'] ?? '',
    aiAnalysis: json['aiAnalysis'] ?? '',
    source: json['source'] ?? '',
    createdAt: json['createdAt'] ?? '',
  );
}

class MockExamService {
  static const _key = 'mock_exams';

  static Future<List<MockExam>> getAll() async {
    final db = DatabaseHelper();
    final raw = await db.getSetting(_key);
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => MockExam.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(MockExam exam) async {
    final db = DatabaseHelper();
    final all = await getAll();
    // Remove existing with same id, then insert at beginning
    all.removeWhere((e) => e.id == exam.id);
    all.insert(0, exam);
    await db.setSetting(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> delete(String id) async {
    final db = DatabaseHelper();
    final all = await getAll();
    all.removeWhere((e) => e.id == id);
    await db.setSetting(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> updateAnswer(String id, String answer) async {
    final db = DatabaseHelper();
    final all = await getAll();
    final idx = all.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      all[idx].userAnswer = answer;
      await db.setSetting(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
    }
  }

  static Future<void> updateAnalysis(String id, String analysis) async {
    final db = DatabaseHelper();
    final all = await getAll();
    final idx = all.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      all[idx].aiAnalysis = analysis;
      await db.setSetting(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
    }
  }
}
