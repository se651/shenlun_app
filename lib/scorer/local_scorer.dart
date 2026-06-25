/// 申论本地评分引擎
/// 基于打分.txt 规则：内容40% + 结构30% + 语言20% + 规范10%
/// 扣分：抄材料、模式化、偏题
import 'dart:math';

class ScoreResult {
  final int totalScore;
  final int score;
  final String feedback;
  final String details;
  final Map<String, int> breakdown;
  final List<String> weaknesses;
  final Map<String, String> analyses; // 五位名师评析（AI评分时填充）
  final String suggestion; // 综合建议（AI评分时填充）
  final Map<String, String> modelAnswers; // 各名师风格的完整参考答案

  ScoreResult({
    required this.totalScore,
    required this.score,
    required this.feedback,
    required this.details,
    required this.breakdown,
    this.weaknesses = const [],
    this.analyses = const {},
    this.suggestion = '',
    this.modelAnswers = const {},
  });
}

class LocalScorer {
  // ===== 题型对应总分 =====
  static int _totalScore(String questionType, String? scoreHint) {
    // 优先用题目标注的分数
    if (scoreHint != null) {
      final m = RegExp(r'(\d+)').firstMatch(scoreHint);
      if (m != null) return int.parse(m.group(1)!);
    }
    // 默认分值
    if (questionType.contains('文章论述') || questionType.contains('大作文')) return 35;
    if (questionType.contains('应用文') || questionType.contains('贯彻执行')) return 25;
    if (questionType.contains('提出对策')) return 20;
    if (questionType.contains('综合分析')) return 15;
    if (questionType.contains('概括归纳')) return 10;
    return 20;
  }

  // ===== 主评分入口 =====
  static ScoreResult score({
    required String userAnswer,
    required String referenceAnswer,
    required String materialText,
    required String questionType,
    String? scoreHint,
    int? wordLimit,
  }) {
    final totalScore = _totalScore(questionType, scoreHint);
    final user = _normalize(userAnswer);
    final ref = _normalize(referenceAnswer);
    final material = _normalize(materialText);

    // 空答案/无效答案直接 0 分
    final meaningful = user.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
    if (meaningful.length < 5) {
      return ScoreResult(
        totalScore: totalScore,
        score: 0,
        feedback: '作答内容过短或无实质内容，请认真作答',
        details: '',
        breakdown: {'内容': 0, '结构': 0, '语言': 0, '规范': 0},
        weaknesses: ['作答无效：少于5个汉字'],
      );
    }

    // 1. 内容质量（40%）
    final contentResult = _scoreContent(user, ref, material);
    final contentScore = (contentResult['score']! / 100 * totalScore * 0.4).round();

    // 2. 结构逻辑（30%）
    final structureResult = _scoreStructure(user, questionType);
    final structureScore = (structureResult['score']! / 100 * totalScore * 0.3).round();

    // 3. 语言表达（20%）
    final languageResult = _scoreLanguage(user);
    final languageScore = (languageResult['score']! / 100 * totalScore * 0.2).round();

    // 4. 卷面规范（10%）— 格式、字数
    final formatResult = _scoreFormat(user, wordLimit);
    final formatScore = (formatResult['score']! / 100 * totalScore * 0.1).round();

    // 5. 扣分项
    final penaltyResult = _checkPenalties(user, material, questionType);
    final penalty = (penaltyResult['penalty']! / 100 * totalScore).round();

    final rawScore = contentScore + structureScore + languageScore + formatScore - penalty;
    final finalScore = rawScore.clamp(0, totalScore);

    // 收集缺点
    final weaknesses = <String>[];
    if (contentResult['missed'] != null && (contentResult['missed'] as List).isNotEmpty) {
      final missed = contentResult['missed'] as List;
      weaknesses.add('遗漏关键词：${missed.take(4).join("、")}${missed.length > 4 ? "等" : ""}');
    }
    if (structureResult['weakness'] != null) {
      weaknesses.add(structureResult['weakness'] as String);
    }
    if (languageResult['weakness'] != null) {
      weaknesses.add(languageResult['weakness'] as String);
    }
    if (penaltyResult['detail'] != null && (penaltyResult['detail'] as String).isNotEmpty) {
      weaknesses.add(penaltyResult['detail'] as String);
    }

    // 生成反馈
    String feedback;
    final ratio = finalScore / totalScore;
    if (ratio >= 0.85) {
      feedback = '优秀！观点明确，逻辑清晰，表达流畅';
    } else if (ratio >= 0.70) {
      feedback = '良好，结构和内容较完整';
    } else if (ratio >= 0.55) {
      feedback = '一般，部分要点遗漏或表达需改进';
    } else if (ratio >= 0.40) {
      feedback = '需加强，要点覆盖不足，建议多练同类题型';
    } else {
      feedback = '较弱，请认真对照参考答案和材料重新作答';
    }

    // 拼接详细信息
    final details = [
      contentResult['detail'],
      structureResult['detail'],
      languageResult['detail'],
      formatResult['detail'],
      if (penaltyResult['detail']!.isNotEmpty) penaltyResult['detail'],
    ].where((s) => s.toString().isNotEmpty).join('\n');

    return ScoreResult(
      totalScore: totalScore,
      score: finalScore,
      feedback: feedback,
      details: details,
      breakdown: {
        '内容': contentScore,
        '结构': structureScore,
        '语言': languageScore,
        '规范': formatScore,
        if (penalty > 0) '扣分': -penalty,
      },
      weaknesses: weaknesses,
    );
  }

  /// 快速评分（用于套卷练习）
  static int quickScore({
    required String userAnswer,
    required String referenceAnswer,
    required String materialText,
  }) {
    if (userAnswer.isEmpty) return 0;
    if (referenceAnswer.isEmpty) return 60;
    final kw = _extractKeywords(referenceAnswer);
    if (kw.isEmpty) return 65;
    int hits = 0;
    for (final k in kw.take(20)) {
      if (userAnswer.contains(k)) hits++;
    }
    return ((hits / kw.length.clamp(1, 20)) * 100).clamp(30, 95).round();
  }

  // ==================== 评分维度 ====================

  /// 内容质量评分（0-100）— 关键词命中 + 观点深度
  static Map<String, dynamic> _scoreContent(String user, String ref, String material) {
    if (ref.isEmpty) {
      return {'score': 50, 'detail': '⚠️ 暂无参考答案，无法评估内容质量'};
    }

    // 提取参考答案的关键词
    final refKeywords = _extractKeywords(ref);
    if (refKeywords.isEmpty) {
      return {'score': 50, 'detail': '参考答案格式异常'};
    }

    // 关键词命中率
    int matched = 0;
    final missed = <String>[];
    for (final kw in refKeywords) {
      if (user.contains(kw)) {
        matched++;
      } else {
        missed.add(kw);
      }
    }
    final hitRate = matched / refKeywords.length;

    // 用户观点丰富度（独有关键词数量）
    final userKeywords = _extractKeywords(user);
    final uniqueUser = userKeywords.where((w) => !refKeywords.contains(w)).length;

    // 综合评分：命中率70% + 观点丰富度30%
    int score;
    if (hitRate >= 0.85) score = 95;
    else if (hitRate >= 0.70) score = 80;
    else if (hitRate >= 0.55) score = 65;
    else if (hitRate >= 0.40) score = 50;
    else if (hitRate >= 0.25) score = 35;
    else score = 20;

    // 观点丰富度加分
    if (uniqueUser >= 3) score = min(100, score + 10);

    final detail = '内容质量：关键词命中 $matched/${refKeywords.length}'
        '${missed.isNotEmpty ? "，遗漏：${missed.take(4).join("、")}${missed.length > 4 ? "等" : ""}" : ""}';

    return {'score': score, 'detail': detail, 'missed': missed};
  }

  /// 结构逻辑评分（0-100）— 层次分明、条理清晰
  static Map<String, dynamic> _scoreStructure(String user, String questionType) {
    int score = 40; // 基础分
    final notes = <String>[];

    // 有条理标记（一是/二是、第一/第二、1./2.、首先/其次）
    final hasNumList = RegExp(r'(?:一[、，]|二[、，]|三[、，]|1[\.、]|2[\.、]|3[\.、]|（一）|（二）|（三）)').hasMatch(user);
    final hasSeqWords = RegExp(r'(?:第一|第二|第三|首先|其次|最后|再者|此外)').hasMatch(user);

    if (hasNumList) {
      score += 30;
      notes.add('有序号标记');
    }
    if (hasSeqWords) {
      score += 15;
      notes.add('有层次词');
    }

    // 应用文特殊检查：开篇+主体+结尾结构
    if (questionType.contains('应用文') || questionType.contains('贯彻执行')) {
      final hasOpening = user.length > 100 && !RegExp(r'^[\u4e00-\u9fff]{2,4}[：:]').hasMatch(user.substring(0, 30));
      final hasClosing = RegExp(r'(?:以上|特此|望|请|号召|呼吁|让我们)').hasMatch(user.substring(max(0, user.length - 100)));
      if (hasOpening) { score += 10; notes.add('有开篇'); }
      if (hasClosing) { score += 10; notes.add('有结尾'); }
    }

    // 大作文特殊检查：引论+本论+结论
    if (questionType.contains('文章论述') || questionType.contains('大作文')) {
      final paragraphs = user.split(RegExp(r'\n{2,}'));
      if (paragraphs.length >= 3) { score += 15; notes.add('段落分明'); }
      else { score -= 10; notes.add('段落不足'); }
    }

    score = score.clamp(0, 100);
    final weakness = (hasNumList || hasSeqWords) ? null : '缺少序号标记或层次词，条理性待加强';
    return {'score': score, 'detail': '结构逻辑：${notes.isNotEmpty ? notes.join("、") : "条理性有待加强"}', 'weakness': weakness};
  }

  /// 语言表达评分（0-100）— 用词精准、语句通顺
  static Map<String, dynamic> _scoreLanguage(String user) {
    int score = 50;
    final notes = <String>[];

    // 句号使用（表示完整句子）
    final periodCount = '。'.allMatches(user).length;
    if (periodCount >= 3) { score += 20; }
    else if (periodCount >= 1) { score += 10; }
    else { notes.add('缺少完整句子'); }

    // 语句平均长度（15-50字/句为佳）
    final sentences = user.split(RegExp(r'[。！？]')).where((s) => s.trim().isNotEmpty).toList();
    if (sentences.isNotEmpty) {
      final avgLen = sentences.map((s) => s.length).reduce((a, b) => a + b) / sentences.length;
      if (avgLen >= 15 && avgLen <= 60) { score += 15; }
      else if (avgLen >= 10 && avgLen <= 80) { score += 5; }
      else { notes.add('句子长度不均'); }
    }

    // 是否有政策术语
    final hasPolicyTerms = RegExp(r'(?:贯彻|落实|推进|加强|完善|健全|深化|优化|保障|促进|坚持|统筹)').hasMatch(user);
    if (hasPolicyTerms) { score += 15; notes.add('有政策术语'); }

    score = score.clamp(0, 100);
    final weakness = notes.isEmpty ? null : notes.join('；');
    return {'score': score, 'detail': '语言表达：${notes.isNotEmpty ? notes.join("、") : "语句通顺"}', 'weakness': weakness};
  }

  /// 规范评分（0-100）— 字数、格式
  static Map<String, dynamic> _scoreFormat(String user, int? wordLimit) {
    int score = 80;
    String detail = '规范：';

    if (wordLimit != null && wordLimit > 0) {
      final userLen = user.length;
      if (userLen <= wordLimit && userLen >= wordLimit * 0.5) {
        score = 100;
        detail += '字数合理（$userLen/$wordLimit）';
      } else if (userLen > wordLimit) {
        final excess = ((userLen - wordLimit) / wordLimit * 100).round();
        score = (80 - excess).clamp(20, 80);
        detail += '超出字数（$userLen/$wordLimit，超${excess}%）';
      } else {
        score = (userLen / wordLimit * 80).round().clamp(20, 60);
        detail += '字数偏少（$userLen/$wordLimit）';
      }
    } else {
      detail += '无字数要求';
    }

    return {'score': score, 'detail': detail};
  }

  /// 扣分检查 — 抄材料、模式化
  static Map<String, dynamic> _checkPenalties(String user, String material, String questionType) {
    int penalty = 0;
    final notes = <String>[];

    // 检查抄材料比例
    if (material.isNotEmpty) {
      final copyRate = _copyRatio(user, material);
      if (copyRate > 0.50) {
        penalty = 40;
        notes.add('⚠️ 抄材料过多（${(copyRate*100).round()}%），进入四类文');
      } else if (copyRate > 0.30) {
        penalty = 15;
        notes.add('⚠️ 抄材料较多（${(copyRate*100).round()}%），扣分');
      }
    }

    // 检查是否偏题（答案与问题类型不匹配 — 简化检测：答案过短且无关键词）
    if (user.length < 20 && questionType.contains('文章论述')) {
      penalty += 30;
      notes.add('⚠️ 大作文答题过短，可能偏题或未完成');
    }

    return {'penalty': penalty, 'detail': notes.isNotEmpty ? notes.join('\n') : ''};
  }

  // ==================== 工具方法 ====================

  /// 计算抄材料比例
  static double _copyRatio(String user, String material) {
    if (material.length < 10) return 0;
    // 用 5-gram 比对
    final n = 5;
    if (user.length < n) return 0;
    final materialGrams = <String>{};
    for (int i = 0; i <= material.length - n; i++) {
      materialGrams.add(material.substring(i, i + n));
    }
    int copied = 0;
    int total = 0;
    for (int i = 0; i <= user.length - n; i++) {
      total++;
      if (materialGrams.contains(user.substring(i, i + n))) {
        copied++;
      }
    }
    return total > 0 ? copied / total : 0;
  }

  /// 文本标准化
  static String _normalize(String text) {
    return text
        .replaceAll(RegExp(r'[（(][^）)]*[）)]'), '') // 去括号注释
        .replaceAll(RegExp(r'[\s\n\r\t]+'), '') // 去空白
        .replaceAll(RegExp(r'[，,。；;！!？?：:、""''【】《》]'), ' ') // 标点换空格
        .replaceAll(RegExp(r' +'), ' ')
        .trim();
  }

  /// 提取关键词（2-4字中文词）
  static List<String> _extractKeywords(String text) {
    final words = <String>{};
    for (final m in RegExp(r'[\u4e00-\u9fff]{2,4}').allMatches(text)) {
      final w = m.group(0)!;
      if (_stopWords.contains(w) || w.length < 2) continue;
      words.add(w);
    }
    final sorted = words.toList()..sort((a, b) => b.length.compareTo(a.length));
    return sorted.take(20).toList();
  }

  static const _stopWords = {
    '这是', '一个', '可以', '进行', '通过', '对于', '以及', '为了', '不是',
    '没有', '已经', '还是', '或者', '但是', '因为', '所以', '然而',
    '目前', '一定', '需要', '主要', '其中', '问题', '方面', '这个',
    '他们', '我们', '什么', '怎么', '如何', '那么', '这样', '那样',
  };
}
