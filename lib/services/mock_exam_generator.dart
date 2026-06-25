/// 申论模拟题 AI 生成器
/// 根据主题内容，按真实考试格式生成给定资料+作答要求
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/db_helper.dart';
import 'mock_exam_service.dart';

class MockExamGenerator {
  static const _endpoint = 'https://api.deepseek.com/v1/chat/completions';
  static const _model = 'deepseek-chat';

  /// 题型标签（用户可选）
  static const questionTypeLabels = {
    '概括归纳': '10分·概括归纳题',
    '综合分析': '15分·综合分析题',
    '提出对策': '20分·提出对策题',
    '应用文': '25分·应用文写作题',
    '大作文': '35分·文章论述题（大作文）',
  };

  /// 生成模拟题
  /// [topic] 主题标签，[content] 主题内容/概念详情，[types] 选中题型，[isFullSet] 是否整套试卷
  static Future<MockExam?> generate({
    required String topic,
    required String content,
    required List<String> types,
    required bool isFullSet,
  }) async {
    final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
    if (apiKey.isEmpty) return null;

    final prompt = isFullSet ? _buildFullSetPrompt(topic, content) : _buildPrompt(topic, content, types);

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.5,
          'max_tokens': 4000,
        }),
      ).timeout(const Duration(seconds: 90));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final text = data['choices']?[0]?['message']?['content'] as String?;
      if (text == null || text.isEmpty) return null;

      return _parseResponse(text, topic, types, isFullSet);
    } catch (_) {
      return null;
    }
  }

  static const _systemPrompt = '''你是国家公务员考试申论命题专家。你需要按照真实申论考试的格式和逻辑出题。

## 出题规范
1. **给定资料** 必须包含多个段落（资料1、资料2...），每段150-600字
2. 资料内容必须 **紧扣主题**，有案例、数据、政策文件引用，风格模仿真实的申论给定资料
3. 大作文必须提供 **完整的给定资料**（至少3-4段，总计1500-3000字），涵盖问题现状、原因分析、对策措施等
4. **作答要求** 格式：一题一题标清，包含题型说明、字数要求、分值
5. 题目要有区分度——概括归纳侧重提取要点，综合分析侧重深度理解，提出对策侧重解决问题，应用文侧重格式+内容，大作文侧重立意论证
6. 整套试卷应包含4-5道题：概括归纳+综合分析+提出对策+应用文+大作文，总分100分

请用以下JSON格式回复（不要输出其他内容）：
{
  "material": "给定资料全文（markdown格式，资料之间用空行分隔）",
  "questions": "作答要求全文（markdown格式，一题一题标清）",
  "title": "试卷标题（如：XX主题·申论模拟题）"
}''';

  static String _buildPrompt(String topic, String content, List<String> types) {
    final typeList = types.join('、');
    return '''请围绕以下主题，生成${typeList}题型的申论模拟题。

【主题】$topic
【参考材料】$content
【生成题型】$typeList

要求：
- 给定资料紧扣上述主题，模仿真实申论考试的资料风格（案例+数据+政策）
- 按上述题型各出一道题，分值按标准分配
- 如果是大作文，给定资料必须充足（至少3-4段，总计1500字以上）
- 用JSON格式回复''';
  }

  static String _buildFullSetPrompt(String topic, String content) {
    return '''请围绕以下主题，生成一套完整的申论模拟试卷。

【主题】$topic
【参考材料】$content

要求：
- 包含4-5道题，覆盖：概括归纳（10分）、综合分析（15分）、提出对策（20分）、应用文（25分）、大作文（30分），总计100分
- 给定资料必须充足（至少4-5段，总计2000-3500字），涵盖问题现状、原因分析、解决措施、政策背景
- 题目之间要有逻辑递进关系
- 大作文需要给出明确的主题和写作要求
- 整套题风格模仿真实的国考/省考申论试卷
- 用JSON格式回复''';
  }

  static MockExam _parseResponse(String text, String topic, List<String> types, bool isFullSet) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      final material = json['material'] as String? ?? '';
      final questions = json['questions'] as String? ?? '';
      final title = json['title'] as String? ?? '$topic·申论模拟题';

      final typeLabel = isFullSet ? '整套试卷' : types.join('、');

      return MockExam(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        questionType: typeLabel,
        material: material,
        questions: questions,
        source: 'concept',
        createdAt: DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // JSON 解析失败，尝试按文本格式处理
      final parts = text.split(RegExp(r'##\s*作答要求|##\s*题目'));
      final material = parts.isNotEmpty ? parts.first.trim() : '';
      final questions = parts.length > 1 ? parts.sublist(1).join('\n').trim() : text;

      final typeLabel = isFullSet ? '整套试卷' : types.join('、');
      return MockExam(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '$topic·申论模拟题',
        questionType: typeLabel,
        material: material,
        questions: questions,
        source: 'concept',
        createdAt: DateTime.now().toIso8601String(),
      );
    }
  }
}
