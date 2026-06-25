/// 重要会议数据 — 2024-2026年中央重要工作会议内容
/// 侧重申论考点：政策方向、具体措施、标志性表述
class ImportantMeeting {
  final String title;
  final String date;
  final String summary;
  final String keyPoints;
  final String category; // economy / agriculture / ecology / party / tech / livelihood

  const ImportantMeeting({
    required this.title,
    required this.date,
    required this.summary,
    required this.keyPoints,
    required this.category,
  });
}

const importantMeetingsData = [
  // ═══════════════════════════════════════
  // 2026年
  // ═══════════════════════════════════════
  ImportantMeeting(
    category: 'economy',
    date: '2026年3月',
    title: '十四届全国人大四次会议',
    summary: '审议政府工作报告，审查国民经济和社会发展第十五个五年规划纲要草案。全面部署2026年经济社会发展目标任务，强调稳中求进、以进促稳，实施更加积极的财政政策和适度宽松的货币政策。',
    keyPoints: '1. 实施"十五五"规划开局之年\n2. 扩大国内需求，提振消费和投资\n3. 加快发展新质生产力\n4. 深化重点领域改革\n5. 防范化解重点领域风险',
  ),
  ImportantMeeting(
    category: 'economy',
    date: '2025年12月',
    title: '中央经济工作会议',
    summary: '总结2025年经济工作，分析当前经济形势，部署2026年经济工作。强调坚持稳中求进工作总基调，实施更加积极的财政政策和适度宽松的货币政策，扩大国内需求，推动经济持续回升向好。',
    keyPoints: '1. 实施更加积极的财政政策\n2. 适度宽松的货币政策\n3. 大力提振消费、提高投资效益\n4. 以科技创新引领新质生产力发展\n5. 扩大高水平对外开放',
  ),
  ImportantMeeting(
    category: 'agriculture',
    date: '2025年12月',
    title: '中央农村工作会议',
    summary: '分析当前"三农"工作面临的形势任务，部署2026年农业农村工作。强调坚持农业农村优先发展，全面推进乡村振兴，加快建设农业强国，全方位夯实粮食安全根基。',
    keyPoints: '1. 粮食安全：守住18亿亩耕地红线\n2. 防止规模性返贫\n3. 发展乡村特色产业\n4. 推进宜居宜业和美乡村建设\n5. 强化农业科技和装备支撑',
  ),
  ImportantMeeting(
    category: 'ecology',
    date: '2025年7月',
    title: '全国生态环境保护大会',
    summary: '深入学习贯彻习近平生态文明思想，部署全面推进美丽中国建设。强调把建设美丽中国摆在强国建设民族复兴的突出位置，推动经济社会发展全面绿色转型。',
    keyPoints: '1. 打好污染防治攻坚战\n2. 推进碳达峰碳中和\n3. 实施全面节约战略\n4. 加强生态系统保护修复\n5. 构建现代环境治理体系',
  ),

  // ═══════════════════════════════════════
  // 2025年
  // ═══════════════════════════════════════
  ImportantMeeting(
    category: 'economy',
    date: '2025年3月',
    title: '十四届全国人大三次会议',
    summary: '审议政府工作报告，部署2025年经济社会发展目标任务。实施更加积极的财政政策和适度宽松的货币政策，GDP增长目标5%左右，城镇新增就业1200万人以上。',
    keyPoints: '1. GDP增长5%左右\n2. 实施积极财政政策和宽松货币政策\n3. 发展新质生产力\n4. 扩大内需\n5. 深化改革扩大开放',
  ),
  ImportantMeeting(
    category: 'party',
    date: '2024年7月',
    title: '党的二十届三中全会',
    summary: '审议通过《中共中央关于进一步全面深化改革、推进中国式现代化的决定》。提出300多项重要改革举措，涉及经济、政治、文化、社会、生态文明各领域，是新时代新征程上推动全面深化改革向广度和深度进军的总动员总部署。',
    keyPoints: '1. 构建高水平社会主义市场经济体制\n2. 健全推动高质量发展体制机制\n3. 构建支持全面创新体制机制\n4. 健全宏观经济治理体系\n5. 完善城乡融合发展体制机制\n6. 完善高水平对外开放体制机制',
  ),
  ImportantMeeting(
    category: 'economy',
    date: '2024年12月',
    title: '中央经济工作会议',
    summary: '总结2024年经济工作，部署2025年经济工作。实施更加积极的财政政策和适度宽松的货币政策，首次提出"超常规逆周期调节"，彰显稳增长决心。',
    keyPoints: '1. 首次提出超常规逆周期调节\n2. 积极财政+适度宽松货币政策组合\n3. 全方位扩大国内需求\n4. 稳住楼市股市\n5. 推动标志性改革举措落地',
  ),
  ImportantMeeting(
    category: 'agriculture',
    date: '2024年12月',
    title: '中央农村工作会议',
    summary: '部署2025年"三农"工作。学习运用"千万工程"经验，推进乡村全面振兴。强调保障粮食和重要农产品稳定安全供给，持续巩固拓展脱贫攻坚成果。',
    keyPoints: '1. 学习运用"千万工程"经验\n2. 粮食产量保持在1.3万亿斤以上\n3. 推进种业振兴\n4. 建设宜居宜业和美乡村\n5. 拓宽农民增收渠道',
  ),
  ImportantMeeting(
    category: 'ecology',
    date: '2024年7月',
    title: '全国生态环境保护大会',
    summary: '部署全面推进美丽中国建设。强调正确处理高质量发展和高水平保护的关系，坚持山水林田湖草沙一体化保护和系统治理，推动绿色低碳发展。',
    keyPoints: '1. 美丽中国建设总体部署\n2. 污染防治与生态保护并重\n3. 推进碳达峰碳中和\n4. 加强生物多样性保护\n5. 推动绿色生产生活方式',
  ),
  ImportantMeeting(
    category: 'tech',
    date: '2024年6月',
    title: '全国科技大会',
    summary: '部署加快建设科技强国。强调中国式现代化关键在科技现代化，坚持创新在现代化建设全局中的核心地位，加快实现高水平科技自立自强。',
    keyPoints: '1. 科技强国建设目标\n2. 强化基础研究\n3. 突破关键核心技术\n4. 深化科技体制改革\n5. 培养创新型人才',
  ),
  ImportantMeeting(
    category: 'livelihood',
    date: '2024年5月',
    title: '中央政治局会议（民生专题）',
    summary: '研究部署保障和改善民生工作。强调坚持以人民为中心的发展思想，着力解决群众急难愁盼问题，在高质量发展中增进民生福祉。',
    keyPoints: '1. 就业优先政策\n2. 健全社会保障体系\n3. 推进健康中国建设\n4. 完善养老服务体系\n5. 保障教育公平',
  ),
];

/// 类别映射
const meetingCategoryLabels = {
  'economy': '经济发展',
  'agriculture': '三农工作',
  'ecology': '生态文明',
  'party': '党的建设',
  'tech': '科技创新',
  'livelihood': '民生保障',
};
