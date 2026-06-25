/// DeepSeek AI 评分引擎
/// 用户提供 API Key，通过 HTTPS 直接调用 DeepSeek API 进行申论批改
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'local_scorer.dart';

/// 概括练习 AI 分析结果
class SummaryAnalysisResult {
  final String referenceAnswer;   // AI 生成的参考答案
  final String gapAnalysis;       // 差距分析
  final String techniqueBreakdown; // 归纳技巧拆解

  SummaryAnalysisResult({
    required this.referenceAnswer,
    required this.gapAnalysis,
    required this.techniqueBreakdown,
  });
}

/// 要点答题评分结果
class OutlineScoreResult {
  final int totalScore;
  final int score;
  final Map<String, int> breakdown; // 切题/逻辑/深度/可行性
  final Map<String, String> analyses; // 四位名师评析
  final String suggestion; // 综合建议

  OutlineScoreResult({
    required this.totalScore,
    required this.score,
    required this.breakdown,
    required this.analyses,
    required this.suggestion,
  });
}

class AIScorer {
  static const _endpoint = 'https://api.deepseek.com/v1/chat/completions';
  static const _model = 'deepseek-chat';

  /// 从 DeepSeek API 评分，失败则返回 null（由调用方降级到本地评分）
  static Future<ScoreResult?> score({
    required String apiKey,
    required String userAnswer,
    required String referenceAnswer,
    required String materialText,
    required String questionType,
    String? scoreHint,
    int? wordLimit,
  }) async {
    try {
      final totalScore = _totalScore(questionType, scoreHint);
      final prompt = _buildPrompt(
        userAnswer: userAnswer,
        referenceAnswer: referenceAnswer,
        materialText: materialText,
        questionType: questionType,
        totalScore: totalScore,
        wordLimit: wordLimit,
      );

      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content': _systemPrompt,
            },
            {
              'role': 'user',
              'content': prompt,
            },
          ],
          'temperature': 0.3,
          'max_tokens': 4000,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return null;

      return _parseResponse(content, totalScore);
    } catch (_) {
      return null; // 任何异常降级到本地评分
    }
  }

  /// 忠政方法论评分
  static Future<ScoreResult?> scoreZhongzheng({
    required String apiKey,
    required String userAnswer,
    required String referenceAnswer,
    required String materialText,
    required String questionType,
    String? scoreHint,
    int? wordLimit,
  }) async {
    try {
      final totalScore = _totalScore(questionType, scoreHint);
      final prompt = _buildPrompt(
        userAnswer: userAnswer,
        referenceAnswer: referenceAnswer,
        materialText: materialText,
        questionType: questionType,
        totalScore: totalScore,
        wordLimit: wordLimit,
      );

      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _zhongzhengPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 4000,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return null;

      return _parseResponse(content, totalScore);
    } catch (_) {
      return null;
    }
  }

  static int _totalScore(String questionType, String? scoreHint) {
    if (scoreHint != null) {
      final m = RegExp(r'(\d+)').firstMatch(scoreHint);
      if (m != null) return int.parse(m.group(1)!);
    }
    if (questionType.contains('文章论述') || questionType.contains('大作文')) return 35;
    if (questionType.contains('应用文')) return 25;
    if (questionType.contains('提出对策')) return 20;
    if (questionType.contains('综合分析')) return 15;
    if (questionType.contains('概括归纳')) return 10;
    return 20;
  }

  static const _zhongzhengPrompt = '''你是五位国家公务员考试申论名师组成的评审团。请按照忠政方法论批改考生的申论答案。

## 忠政方法论体系（主评框架）

### 申论答题三步走
1. 审题干：明确作答范围、作答要求、身份定位
2. 读材料：第一遍划分段落层次总结大意，第二遍概括归纳要点
3. 整答案：能合并的合并，分不清的分开写

### 材料结构：一个主题 + 四要素
每则材料围绕一个主题，包含四大要素：问题（现状）、原因（根源）、影响（意义/危害）、对策（措施）

### 基本题型及作答要素
- 概括归纳：题干含"概括/梳理/归纳/总结"→ 直接从材料提取要点
- 提出对策：题干含"建议/措施/办法"→ 问题+对策一一对应
- 综合分析：题干含"理解/评析/认识/看法"→ 是什么→为什么→怎么办
- 应用文：宣传单/公开信/简报/讲话稿 → 格式+背景+主体+结尾
- 大作文：以…为题/话题 → 总论点(材料提炼)+3-4分论点+论据

### 袁东老师（化大为小·规范表达）
采用赋分制：内容40% + 结构30% + 语言20% + 规范10%

### 名师评析 — 五位老师各写一段
- 袁东：宏观立意和规范表达角度
- 白鹭（紧贴材料·原文提取）：紧扣材料，指出遗漏要点
- 飞扬（五大原则·系统框架）：逻辑框架和结构层次
- 小马哥（材料是爹·找大哥）：实战得分，关键提分点
- 忠政（忠政方法论·三步走）：五维评分体系（材料扣合度30分、逻辑结构20分、政策素养20分、语言规范15分、完整性15分）

### 范文生成 — 五位老师各生成一份完整参考答案
- 袁东风：规范严谨，总分结构，善用政策术语
- 白鹭风：紧贴材料原文，要点式作答，标注材料来源
- 飞扬风：逻辑框架清晰，小标题分层
- 小马哥风：实战导向，简洁有力直接得分
- 忠政风：严格三步走+五维体系框架

请用以下 JSON 格式回复：
{
  "score": 数字,
  "feedback": "一句话总体评价",
  "details": "逐条具体分析",
  "breakdown": {"内容": 数字, "结构": 数字, "语言": 数字, "规范": 数字},
  "weaknesses": ["不足1", "不足2"],
  "analyses": {"袁东": "...", "白鹭": "...", "飞扬": "...", "小马哥": "...", "忠政": "..."},
  "suggestion": "综合建议...",
  "modelAnswers": {"袁东": "完整范文...", "白鹭": "完整范文...", "飞扬": "完整范文...", "小马哥": "完整范文...", "忠政": "完整范文..."}
}''';

  static const _systemPrompt = '''你是五位国家公务员考试申论名师组成的评审团。请按照以下分工批改考生的申论答案：

【袁东老师主评 — 化大为小·规范表达】
采用赋分制（从0分起，逐项加分，不扣分）：
1. 内容质量（40%权重）：要点覆盖、观点准确、紧扣材料 → 按命中率给分
2. 结构逻辑（30%权重）：层次分明、有序号标记和层次词 → 有则加分
3. 语言表达（20%权重）：用词精准规范、有政策术语 → 有则加分
4. 卷面规范（10%权重）：字数合理、无明显格式问题 → 达标则加分
5. 特殊情况：作答少于20字或无实质内容 → 直接给0分

【名师评析 — 五位老师各写一段】
- 袁东：从宏观立意和规范表达角度点评
- 白鹭（紧贴材料·原文提取）：检查是否紧扣材料，指出遗漏的材料要点
- 飞扬（五大原则·系统框架）：从逻辑框架和结构层次角度点评
- 小马哥（材料是爹·找大哥）：从实战得分角度，指出最关键的1-2个提分点
- 忠政（忠政方法论·三步走）：审题干→读材料→整答案，从五维评分体系点评（材料扣合度30分、逻辑结构20分、政策素养20分、语言规范15分、完整性15分），标注材料来源，给出参考答案框架

【范文生成 — 五位老师各生成一份该题的完整参考答案】
- 袁东风：规范严谨，总分结构，善用政策术语
- 白鹭风：紧贴材料原文，要点式作答，每个要点标注材料来源
- 飞扬风：逻辑框架清晰，用小标题分层，结构美观
- 小马哥风：实战导向，抓大放小，简洁有力直接得分
- 忠政风：严格遵循三步走方法论，五维评分体系框架

【综合建议】综合五位老师的意见，给出2-3条具体可操作的改进建议。

请用以下 JSON 格式回复（不要输出其他内容）：
{
  "score": 数字,
  "feedback": "一句话总体评价",
  "details": "逐条具体分析",
  "breakdown": {"内容": 数字, "结构": 数字, "语言": 数字, "规范": 数字},
  "weaknesses": ["缺点1", "缺点2"],
  "analyses": {"袁东": "...", "白鹭": "...", "飞扬": "...", "小马哥": "...", "忠政": "..."},
  "suggestion": "综合建议...",
  "modelAnswers": {"袁东": "完整范文...", "白鹭": "完整范文...", "飞扬": "完整范文...", "小马哥": "完整范文...", "忠政": "完整范文..."}
}''';

  static String _buildPrompt({
    required String userAnswer,
    required String referenceAnswer,
    required String materialText,
    required String questionType,
    required int totalScore,
    int? wordLimit,
  }) {
    final refSection = referenceAnswer.isNotEmpty && !referenceAnswer.startsWith('【综合')
        ? '\n参考答案：$referenceAnswer'
        : '\n（本题暂无官方参考答案，请根据材料和题型自行判断要点）';

    return '''请批改以下申论答案：

题型：$questionType
满分：$totalScore分
${wordLimit != null && wordLimit > 0 ? '字数要求：不超过${wordLimit}字' : ''}
${materialText.length > 2000 ? '材料概要：${materialText.substring(0, 2000)}...' : '材料内容：$materialText'}
$refSection

考生答案：$userAnswer''';
  }

  static ScoreResult _parseResponse(String content, int totalScore) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      final score = (json['score'] as num?)?.toInt() ?? totalScore ~/ 2;
      final feedback = json['feedback'] as String? ?? 'AI 评分完成';
      final details = json['details'] as String? ?? '';

      final breakdownRaw = json['breakdown'] as Map<String, dynamic>?;
      final breakdown = <String, int>{
        '内容': (breakdownRaw?['内容'] as num?)?.toInt() ?? 0,
        '结构': (breakdownRaw?['结构'] as num?)?.toInt() ?? 0,
        '语言': (breakdownRaw?['语言'] as num?)?.toInt() ?? 0,
        '规范': (breakdownRaw?['规范'] as num?)?.toInt() ?? 0,
      };

      final analysesRaw = json['analyses'] as Map<String, dynamic>?;
      final analyses = <String, String>{
        '袁东': analysesRaw?['袁东'] as String? ?? '',
        '白鹭': analysesRaw?['白鹭'] as String? ?? '',
        '飞扬': analysesRaw?['飞扬'] as String? ?? '',
        '小马哥': analysesRaw?['小马哥'] as String? ?? '',
        '忠政': analysesRaw?['忠政'] as String? ?? '',
      };
      final suggestion = json['suggestion'] as String? ?? '';

      final modelAnswersRaw = json['modelAnswers'] as Map<String, dynamic>?;
      final modelAnswers = <String, String>{
        '袁东': modelAnswersRaw?['袁东'] as String? ?? '',
        '白鹭': modelAnswersRaw?['白鹭'] as String? ?? '',
        '飞扬': modelAnswersRaw?['飞扬'] as String? ?? '',
        '小马哥': modelAnswersRaw?['小马哥'] as String? ?? '',
        '忠政': modelAnswersRaw?['忠政'] as String? ?? '',
      };

      return ScoreResult(
        totalScore: totalScore,
        score: score.clamp(0, totalScore),
        feedback: feedback,
        details: details,
        breakdown: breakdown,
        weaknesses: _parseWeaknesses(content),
        analyses: analyses,
        suggestion: suggestion,
        modelAnswers: modelAnswers,
      );
    } catch (_) {
      // JSON 解析失败，取文本中的分数
      final scoreMatch = RegExp(r'"score"\s*:\s*(\d+)').firstMatch(content);
      final sc = scoreMatch != null ? int.parse(scoreMatch.group(1)!) : totalScore ~/ 2;
      return ScoreResult(
        totalScore: totalScore,
        score: sc.clamp(0, totalScore),
        feedback: 'AI 评分完成',
        details: content,
        breakdown: {},
      );
    }
  }

  // ═══════════════════════════════════════════
  // 要点答题评分（仅限大作文）
  // ═══════════════════════════════════════════

  static Future<OutlineScoreResult?> scoreOutline({
    required String apiKey,
    required String mainArgument,
    required List<String> subArguments,
    required String questionText,
    required String materialText,
    String? scoreHint,
  }) async {
    try {
      final totalScore = _totalScore('大作文', scoreHint);
      final prompt = _buildOutlinePrompt(
        mainArgument: mainArgument,
        subArguments: subArguments,
        questionText: questionText,
        materialText: materialText,
        totalScore: totalScore,
      );

      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _outlineSystemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 1200,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return null;

      return _parseOutlineResponse(content, totalScore);
    } catch (_) {
      return null;
    }
  }

  static const _outlineSystemPrompt = '''你是四位国家公务员考试申论名师组成的评审团。考生提交的是大作文的论点提纲（不是完整文章），你需要按照以下分工进行评审：

【评分标准 — 袁东老师主评】
采用赋分制（从0分起，逐项加分）：
1. 论点切题（40%）：总论点精准回应题干，分论点紧扣总论点并覆盖材料核心 → 有则加分
2. 逻辑层次（30%）：分论点间有递进/并列/因果关系，逻辑自洽 → 有则加分
3. 思想深度（20%）：有政策视野、辩证思维 → 有则加分
4. 特殊情况：作答少于10字或无实质内容 → 直接给0分
4. 可行性（10%）：展开成文的可操作性，论据支撑潜力

【名师评析 — 四位老师各写一段】
- 袁东（化大为小·规范表达）：从宏观立意和规范表达角度点评
- 白鹭（紧贴材料·原文提取）：检查论点是否紧扣材料，指出遗漏的材料要点
- 飞扬（五大原则·系统框架）：从逻辑框架和结构层次角度点评
- 小马哥（材料是爹·找大哥）：从实战得分角度，指出最关键的1-2个提分点

【综合建议】综合四位老师的意见，给出2-3条具体可操作的改进建议。

请用以下 JSON 格式回复（不要输出其他内容）：
{
  "score": 数字,
  "breakdown": {"切题": 数字, "逻辑": 数字, "深度": 数字, "可行性": 数字},
  "analyses": {
    "袁东": "袁东老师的评析...",
    "白鹭": "白鹭老师的评析...",
    "飞扬": "飞扬老师的评析...",
    "小马哥": "小马哥老师的评析..."
  },
  "suggestion": "综合建议..."
}''';

  static String _buildOutlinePrompt({
    required String mainArgument,
    required List<String> subArguments,
    required String questionText,
    required String materialText,
    required int totalScore,
  }) {
    final subs = subArguments.asMap().entries
        .map((e) => '分论点${e.key + 1}：${e.value}')
        .join('\n');

    return '''请评审以下大作文论点提纲：

题目要求：$questionText
满分：$totalScore分
${materialText.length > 1500 ? '材料概要：${materialText.substring(0, 1500)}...' : '材料内容：$materialText'}

考生论点：
总论点：$mainArgument
$subs''';
  }

  static OutlineScoreResult _parseOutlineResponse(String content, int totalScore) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      final score = (json['score'] as num?)?.toInt() ?? totalScore ~/ 2;

      final breakdownRaw = json['breakdown'] as Map<String, dynamic>?;
      final breakdown = <String, int>{
        '切题': (breakdownRaw?['切题'] as num?)?.toInt() ?? 0,
        '逻辑': (breakdownRaw?['逻辑'] as num?)?.toInt() ?? 0,
        '深度': (breakdownRaw?['深度'] as num?)?.toInt() ?? 0,
        '可行性': (breakdownRaw?['可行性'] as num?)?.toInt() ?? 0,
      };

      final analysesRaw = json['analyses'] as Map<String, dynamic>?;
      final analyses = <String, String>{
        '袁东': analysesRaw?['袁东'] as String? ?? '',
        '白鹭': analysesRaw?['白鹭'] as String? ?? '',
        '飞扬': analysesRaw?['飞扬'] as String? ?? '',
        '小马哥': analysesRaw?['小马哥'] as String? ?? '',
      };

      final suggestion = json['suggestion'] as String? ?? '';

      return OutlineScoreResult(
        totalScore: totalScore,
        score: score.clamp(0, totalScore),
        breakdown: breakdown,
        analyses: analyses,
        suggestion: suggestion,
      );
    } catch (_) {
      final scoreMatch = RegExp(r'"score"\s*:\s*(\d+)').firstMatch(content);
      final sc = scoreMatch != null ? int.parse(scoreMatch.group(1)!) : totalScore ~/ 2;
      return OutlineScoreResult(
        totalScore: totalScore,
        score: sc.clamp(0, totalScore),
        breakdown: {},
        analyses: {'袁东': content, '白鹭': '', '飞扬': '', '小马哥': ''},
        suggestion: '',
      );
    }
  }

  // ═══════════════════════════════════════════
  // 概括练习 AI 分析
  // ═══════════════════════════════════════════

  static Future<SummaryAnalysisResult?> analyzeSummary({
    required String apiKey,
    required String originalText,
    required String userAnswer,
    required String levelName,
  }) async {
    try {
      final prompt = '''请分析以下概括练习：

原文（需概括的材料）：
$originalText

考生答案：$userAnswer

练习类型：$levelName''';

      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _summarySystemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 1000,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return null;

      return _parseSummaryResponse(content);
    } catch (_) {
      return null;
    }
  }

  static const _summarySystemPrompt = '''你是一位申论概括归纳题的专业教练。请完成以下三项任务：

1. 【参考答案】按照申论概括题的规范，给出这段原文的参考答案。要求：紧扣原文、保留关键信息、删除冗余、语言精炼。对于短句概括控制在30字内，段落概括控制在20-60字，全文概括控制在60-200字。

2. 【差距分析】逐条对比考生的答案与参考答案的差距，包括：
   - 遗漏了哪些原文要点
   - 哪些内容属于冗余或不必要
   - 表述是否准确规范

3. 【归纳技巧】针对这段原文，讲解归纳概括的方法和技巧，包括：
   - 如何抓主旨句
   - 合并同类项的方法
   - 删除冗余信息的技巧
   - 如果有数字、时间、地名等关键信息如何处理

请用以下 JSON 格式回复（不要输出其他内容）：
{
  "referenceAnswer": "参考答案...",
  "gapAnalysis": "差距分析：1. ... 2. ... 3. ...",
  "techniqueBreakdown": "归纳技巧：1. ... 2. ... 3. ..."
}''';

  static SummaryAnalysisResult _parseSummaryResponse(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      return SummaryAnalysisResult(
        referenceAnswer: json['referenceAnswer'] as String? ?? '',
        gapAnalysis: json['gapAnalysis'] as String? ?? '',
        techniqueBreakdown: json['techniqueBreakdown'] as String? ?? '',
      );
    } catch (_) {
      // JSON 解析失败时，将原始内容作为参考答案返回
      return SummaryAnalysisResult(
        referenceAnswer: content,
        gapAnalysis: '',
        techniqueBreakdown: '',
      );
    }
  }

  // ═══════════════════════════════════════════
  // 历史答案对比分析
  // ═══════════════════════════════════════════

  /// 返回 null 表示失败；成功返回 Map 含 progress 和 issues
  static Future<Map<String, String>?> compareAttempts({
    required String apiKey,
    required String answer1,
    required String time1,
    required String answer2,
    required String time2,
    required String questionTitle,
    required String questionType,
    String? referenceAnswer,
  }) async {
    try {
      final refSection = referenceAnswer != null && referenceAnswer.isNotEmpty
          ? '\n参考答案：$referenceAnswer'
          : '';
      final prompt = '''请对比分析以下两次申论作答：

题目：$questionTitle
题型：$questionType
$refSection

第一次作答（$time1）：
$answer1

第二次作答（$time2）：
$answer2''';

      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _compareSystemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
          'max_tokens': 800,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return null;

      final json = jsonDecode(content) as Map<String, dynamic>;
      return {
        'progress': json['progress'] as String? ?? '',
        'issues': json['issues'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  static const _compareSystemPrompt = '''你是一位申论阅卷老师。请对比分析考生的两次作答，重点关注：

1. 【进步点】第二次相比第一次有哪些进步？是否在内容覆盖、结构逻辑、语言表达等方面有提升？
2. 【仍存问题】第一次存在的问题中，哪些在第二次依然存在？需要如何改进？

请用以下 JSON 格式回复（不要输出其他内容）：
{
  "progress": "进步点：1. ... 2. ... 3. ...",
  "issues": "仍存在：1. ... 2. ..."
}''';

  static List<String> _parseWeaknesses(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      final w = json['weaknesses'];
      if (w is List) return w.cast<String>();
      return [];
    } catch (_) {
      return [];
    }
  }

  /// AI 从文章生成概括练习题
  static Future<List<Map<String, String>>?> generateExercises({
    required String apiKey,
    required String articleText,
  }) async {
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
            {'role': 'system', 'content': _exerciseGenPrompt},
            {'role': 'user', 'content': articleText},
          ],
          'temperature': 0.5,
          'max_tokens': 2000,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return null;

      final json = jsonDecode(content) as Map<String, dynamic>;
      final exercises = json['exercises'] as List?;
      if (exercises == null) return null;
      return exercises.cast<Map<String, dynamic>>().map((e) => e.map((k, v) => MapEntry(k, v.toString()))).toList();
    } catch (_) {
      return null;
    }
  }

  static const _exerciseGenPrompt = '''你是一位申论培训专家。请从给定的时政新闻文章中提取内容，生成4个概括练习题。严格按以下 JSON 格式回复（不要输出其他内容）：

{
  "exercises": [
    {
      "level": "short",
      "material": "提取文章中80-160字的关键段落",
      "answer": "用30字以内概括这段内容的核心观点"
    },
    {
      "level": "paragraph", 
      "material": "提取文章中150-300字的一个自然段",
      "answer": "用50-80字归纳这段的要点"
    },
    {
      "level": "full",
      "material": "将全文压缩到300-500字",
      "answer": "用150-200字概括全文中心思想"
    },
    {
      "level": "outline",
      "material": "将全文压缩到300-500字",
      "answer": "用序号列出3-5个核心要点，每条10-20字"
    }
  ]
}

要求：material 必须直接从原文提取（不编造），answer 要精炼准确。''';
}
