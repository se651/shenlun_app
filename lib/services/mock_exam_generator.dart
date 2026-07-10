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

  static const _systemPrompt = '''你是国家公务员考试申论命题专家。你必须严格按照真实申论考试的格式和逻辑出题。

## 申论试卷标准格式

### 给定资料（核心要求）
1. **必须包含5个独立资料**（资料1、资料2、资料3、资料4、资料5），整套试卷可扩展到7-8个
2. 每个资料300-1200字，围绕主题从**不同角度**展开：案例叙述、数据分析、政策文件、专家观点、基层实践、国际经验等
3. 资料风格必须模仿真实申论：有具体地名/人名（可用"某省""某市""某某村"等）、有数据（百分比、增长率等）、有时间节点
4. 资料之间要有内在逻辑——或并列（不同视角）、或递进（现象→原因→对策）

### 作答要求
1. 一题一题标清：题号、题型、字数要求、分值
2. 题型顺序：概括归纳→综合分析→提出对策→应用文→大作文
3. 每题必须明确指出"根据给定资料X"或"参考给定资料"
4. 大作文要求明确主题，通常"参考给定资料，但不拘泥于给定资料"

### 分值标准
- 概括归纳题：10-15分，200-300字
- 综合分析题：15-20分，300-400字
- 提出对策题：20-25分，400-500字
- 应用文写作题：25分，500-600字
- 文章论述题（大作文）：30-35分，1000-1200字

请用以下JSON格式回复（不要输出其他内容）：
{
  "material": "给定资料全文（格式：**资料1**\\n内容...\\n\\n**资料2**\\n内容... 以此类推，共5个资料）",
  "questions": "作答要求全文（格式：**一、根据给定资料1，概括...**（10分）\\n要求：...\\n不超过200字。\\n\\n以此类推）",
  "title": "试卷标题（如：XX主题·申论模拟试卷）"
}''';

  static String _buildPrompt(String topic, String content, List<String> types) {
    final typeList = types.join('、');
    return '''请围绕以下主题，生成${typeList}题型的申论试题。

【主题】$topic
【参考材料】$content
【生成题型】$typeList

要求：
- 生成5个独立给定资料（资料1-5），每个300-800字，从不同角度切入主题
- 如果包含大作文，资料要更充实，资料4和资料5可扩展到800-1200字
- 资料风格：有案例、有数据、有政策引用，模仿真实申论试卷
- 按选中题型各出一道题，每题标明分值、字数要求、"参考给定资料X"
- 用JSON格式回复''';
  }

  static String _buildFullSetPrompt(String topic, String content) {
    return '''请围绕以下主题，生成一套完整的申论模拟试卷。

【主题】$topic
【参考材料】$content

要求：
- 生成5个独立给定资料（资料1-5），每个500-1200字，总计3000-5000字
- 资料角度要多样化：案例叙述、数据分析、政策背景、基层实践、专家观点各占一个资料
- 题目覆盖全题型共5道题，按顺序：概括归纳（10分·200字）、综合分析（15分·300字）、提出对策（20分·400字）、应用文（25分·500字）、大作文（30分·1000字），总分100分
- 每题明确"根据给定资料X"，大作文为"参考给定资料但不拘泥于给定资料"
- 题目之间逻辑递进：先提取要点→再深入分析→再解决问题→再应用写作→最后升华论述
- 风格模仿真实的国考/省考申论试卷
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
