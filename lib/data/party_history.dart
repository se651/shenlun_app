/// 党史谱系 —— 重要会议 + 党的精神谱系
class PartyHistoryItem {
  final String title;
  final String time;
  final String content;
  final String category; // meeting / spirit
  final String significance; // for meetings: 申论考点

  const PartyHistoryItem({
    required this.title,
    required this.time,
    required this.content,
    required this.category,
    this.significance = '',
  });
}

const partyHistoryData = [
  // ═══════════════════════════════════════
  // 重要会议
  // ═══════════════════════════════════════

  // ── 新民主主义革命时期 ──
  PartyHistoryItem(category: 'meeting', time: '1921年7月', title: '中共一大',
    content: '在上海召开，最后一天转移到浙江嘉兴南湖。宣告中国共产党正式成立。通过了党的第一个纲领，确定党的名称为"中国共产党"，选举陈独秀为中央局书记。',
    significance: '开天辟地的大事变。深刻改变了近代以后中华民族发展的方向和进程，改变了中国人民和中华民族的前途和命运，改变了世界发展的趋势和格局。从此中国革命有了坚强的领导核心。'),

  PartyHistoryItem(category: 'meeting', time: '1922年7月', title: '中共二大',
    content: '在上海召开。制定了党的最高纲领和最低纲领。最高纲领：实现共产主义。最低纲领：打倒军阀、推翻国际帝国主义压迫、统一中国为真正的民主共和国。在中国近代史上第一次明确提出了彻底的反帝反封建的民主革命纲领。',
    significance: '第一次提出反帝反封建的民主革命纲领，为中国革命指明方向。'),

  PartyHistoryItem(category: 'meeting', time: '1923年6月', title: '中共三大',
    content: '在广州召开。决定共产党员以个人身份加入国民党，实现国共合作。同时保持党在政治上、思想上和组织上的独立性。',
    significance: '确立国共合作方针，推动大革命高潮到来。'),

  PartyHistoryItem(category: 'meeting', time: '1927年8月', title: '八七会议',
    content: '在汉口召开。批判了陈独秀右倾机会主义错误，确定了土地革命和武装反抗国民党反动派的总方针。毛泽东提出"枪杆子里出政权"的著名论断。',
    significance: '由大革命失败到土地革命战争兴起的历史性转折点。'),

  PartyHistoryItem(category: 'meeting', time: '1929年12月', title: '古田会议',
    content: '在福建上杭古田召开。确立了思想建党、政治建军的原则。批判了各种非无产阶级思想，强调用无产阶级思想克服非无产阶级思想。重申了党对军队的绝对领导。',
    significance: '建党建军的纲领性文献，为党的建设指明了方向。'),

  PartyHistoryItem(category: 'meeting', time: '1935年1月', title: '遵义会议',
    content: '在贵州遵义召开。集中解决了当时具有决定意义的军事问题和组织问题。批判了"左"倾冒险主义军事路线，确立了毛泽东在红军和党中央的领导地位。',
    significance: '党的历史上一个生死攸关的转折点，标志着中国共产党在政治上开始走向成熟。挽救了党、挽救了红军、挽救了中国革命。'),

  PartyHistoryItem(category: 'meeting', time: '1935年12月', title: '瓦窑堡会议',
    content: '在陕北瓦窑堡召开。制定了抗日民族统一战线的策略方针。指出党的任务是把红军的活动和全国工人、农民、学生、小资产阶级、民族资产阶级的一切活动汇合起来，成为一个统一的民族革命战线。',
    significance: '为迎接全国抗日新高潮的到来做了政治上和理论上的准备。'),

  PartyHistoryItem(category: 'meeting', time: '1937年8月', title: '洛川会议',
    content: '在陕北洛川召开。通过了《抗日救国十大纲领》，提出了全面抗战路线。决定在敌后放手发动独立自主的游击战争，建立敌后抗日根据地。',
    significance: '为全民族抗战指明了方向。'),

  PartyHistoryItem(category: 'meeting', time: '1945年4-6月', title: '中共七大',
    content: '在延安召开。毛泽东作《论联合政府》的政治报告。确立了毛泽东思想为党的指导思想并写入党章。总结了党的三大优良作风：理论联系实际、密切联系群众、批评与自我批评。',
    significance: '以"团结的大会、胜利的大会"载入史册。确立了毛泽东思想的指导地位，使全党在思想上政治上组织上达到空前统一。'),

  // ── 社会主义革命和建设时期 ──
  PartyHistoryItem(category: 'meeting', time: '1949年3月', title: '七届二中全会',
    content: '在河北平山西柏坡召开。毛泽东提出"两个务必"：务必使同志们继续地保持谦虚谨慎不骄不躁的作风，务必使同志们继续地保持艰苦奋斗的作风。决定工作重心由乡村转移到城市。',
    significance: '为夺取全国胜利和建设新中国做了政治上、思想上的准备。"两个务必"至今仍是全面从严治党的重要遵循。'),

  PartyHistoryItem(category: 'meeting', time: '1956年9月', title: '中共八大',
    content: '在北京召开。正确分析了国内主要矛盾的变化：人民对于建立先进工业国的要求同落后农业国的现实之间的矛盾，人民对于经济文化迅速发展的需要同当前经济文化不能满足人民需要状况之间的矛盾。提出集中力量发展社会生产力的主要任务。',
    significance: '探索中国自己社会主义建设道路的开端，为社会主义建设指明了方向。'),

  PartyHistoryItem(category: 'meeting', time: '1962年1-2月', title: '七千人大会',
    content: '在北京召开。初步总结了"大跃进"以来的经验教训，开展了批评与自我批评。毛泽东作自我批评，强调要发扬民主。',
    significance: '对推动国民经济调整、克服困难起了重要作用。体现了党内民主的优良传统。'),

  // ── 改革开放和社会主义现代化建设新时期 ──
  PartyHistoryItem(category: 'meeting', time: '1978年12月', title: '十一届三中全会',
    content: '在北京召开。彻底否定了"两个凡是"方针，重新确立了马克思主义的思想路线、政治路线和组织路线。作出把党和国家工作中心转移到经济建设上来、实行改革开放的历史性决策。',
    significance: '新中国成立以来党的历史上具有深远意义的伟大转折，开启了改革开放和社会主义现代化建设的新时期。工作中不再以阶级斗争为纲，确立了以经济建设为中心的基本路线。'),

  PartyHistoryItem(category: 'meeting', time: '1981年6月', title: '十一届六中全会',
    content: '通过《关于建国以来党的若干历史问题的决议》，科学评价了毛泽东的历史地位和毛泽东思想。标志着党在指导思想上拨乱反正的胜利完成。',
    significance: '统一了全党思想，为改革开放和社会主义现代化建设奠定了思想基础。'),

  PartyHistoryItem(category: 'meeting', time: '1987年10-11月', title: '中共十三大',
    content: '系统阐述了社会主义初级阶段理论，提出了党在社会主义初级阶段的基本路线：领导和团结全国各族人民，以经济建设为中心，坚持四项基本原则，坚持改革开放，自力更生，艰苦创业。即"一个中心、两个基本点"。',
    significance: '为改革开放和现代化建设提供了理论指导，社会主义初级阶段理论成为制定一切方针政策的根本依据。'),

  PartyHistoryItem(category: 'meeting', time: '1992年1-2月', title: '邓小平南方谈话',
    content: '邓小平视察武昌、深圳、珠海、上海等地。提出"发展才是硬道理"；"三个有利于"标准——是否有利于发展社会主义社会的生产力，是否有利于增强社会主义国家的综合国力，是否有利于提高人民的生活水平；计划多一点还是市场多一点，不是社会主义与资本主义的本质区别。',
    significance: '将改革开放和现代化建设推向新阶段，破除了姓"社"姓"资"的思想禁锢。'),

  PartyHistoryItem(category: 'meeting', time: '1992年10月', title: '中共十四大',
    content: '确立了邓小平建设有中国特色社会主义理论在全党的指导地位。明确我国经济体制改革的目标是建立社会主义市场经济体制。',
    significance: '社会主义市场经济体制目标的确立，标志着改革开放进入新阶段。'),

  PartyHistoryItem(category: 'meeting', time: '1997年9月', title: '中共十五大',
    content: '将邓小平理论确立为党的指导思想并写入党章。系统论述了社会主义初级阶段的基本纲领。提出"依法治国"基本方略。',
    significance: '高举邓小平理论伟大旗帜，为跨世纪发展指明方向。'),

  PartyHistoryItem(category: 'meeting', time: '2002年11月', title: '中共十六大',
    content: '将"三个代表"重要思想确立为党的指导思想。提出全面建设小康社会的奋斗目标。',
    significance: '标志着党在指导思想上的又一次与时俱进。'),

  PartyHistoryItem(category: 'meeting', time: '2007年10月', title: '中共十七大',
    content: '提出科学发展观，第一要义是发展，核心是以人为本，基本要求是全面协调可持续，根本方法是统筹兼顾。将中国特色社会主义理论体系概括为包括邓小平理论、"三个代表"重要思想以及科学发展观等在内的科学理论体系。',
    significance: '为全面建设小康社会提供了科学指南。'),

  PartyHistoryItem(category: 'meeting', time: '2012年11月', title: '中共十八大',
    content: '将科学发展观确立为党的指导思想。提出全面建成小康社会的目标。提出经济建设、政治建设、文化建设、社会建设、生态文明建设"五位一体"总体布局。选举习近平为中共中央总书记。',
    significance: '开启了中国特色社会主义新时代。'),

  // ── 中国特色社会主义新时代 ──
  PartyHistoryItem(category: 'meeting', time: '2013年11月', title: '十八届三中全会',
    content: '审议通过《中共中央关于全面深化改革若干重大问题的决定》。提出全面深化改革的总目标是完善和发展中国特色社会主义制度，推进国家治理体系和治理能力现代化。',
    significance: '对全面深化改革作出了总部署、总动员，标志着改革开放进入新阶段。'),

  PartyHistoryItem(category: 'meeting', time: '2014年10月', title: '十八届四中全会',
    content: '审议通过《中共中央关于全面推进依法治国若干重大问题的决定》。提出建设中国特色社会主义法治体系，建设社会主义法治国家的总目标。',
    significance: '党的历史上首次以依法治国为主题的中央全会。'),

  PartyHistoryItem(category: 'meeting', time: '2016年10月', title: '十八届六中全会',
    content: '审议通过《关于新形势下党内政治生活的若干准则》和《中国共产党党内监督条例》。明确习近平总书记的核心地位。',
    significance: '为全面从严治党提供了重要制度保障。'),

  PartyHistoryItem(category: 'meeting', time: '2017年10月', title: '中共十九大',
    content: '将习近平新时代中国特色社会主义思想确立为党的指导思想。作出中国特色社会主义进入新时代的重大政治判断。提出新时代坚持和发展中国特色社会主义的"十四个坚持"基本方略。明确新时代我国社会主要矛盾是人民日益增长的美好生活需要和不平衡不充分的发展之间的矛盾。',
    significance: '描绘了决胜全面建成小康社会、夺取新时代中国特色社会主义伟大胜利的宏伟蓝图。'),

  PartyHistoryItem(category: 'meeting', time: '2018年2月', title: '十九届三中全会',
    content: '审议通过《中共中央关于深化党和国家机构改革的决定》和《深化党和国家机构改革方案》。',
    significance: '推进国家治理体系和治理能力现代化的深刻变革。'),

  PartyHistoryItem(category: 'meeting', time: '2019年10月', title: '十九届四中全会',
    content: '审议通过《中共中央关于坚持和完善中国特色社会主义制度、推进国家治理体系和治理能力现代化若干重大问题的决定》。提出了我国国家制度和治理体系的"十三个显著优势"。',
    significance: '为把制度优势转化为治理效能提供了行动纲领。'),

  PartyHistoryItem(category: 'meeting', time: '2020年10月', title: '十九届五中全会',
    content: '审议通过《中共中央关于制定国民经济和社会发展第十四个五年规划和二〇三五年远景目标的建议》。提出加快构建以国内大循环为主体、国内国际双循环相互促进的新发展格局。',
    significance: '为全面建设社会主义现代化国家开好局、起好步。'),

  PartyHistoryItem(category: 'meeting', time: '2021年11月', title: '十九届六中全会',
    content: '审议通过《中共中央关于党的百年奋斗重大成就和历史经验的决议》。总结出"十个坚持"历史经验。提出"两个确立"：确立习近平同志党中央的核心、全党的核心地位，确立习近平新时代中国特色社会主义思想的指导地位。',
    significance: '以史为鉴、开创未来的纲领性文献。"两个确立"是党的十八大以来最重要的政治成果。'),

  PartyHistoryItem(category: 'meeting', time: '2022年10月', title: '中共二十大',
    content: '提出"三个务必"。明确中心任务：团结带领全国各族人民全面建成社会主义现代化强国、实现第二个百年奋斗目标，以中国式现代化全面推进中华民族伟大复兴。系统阐述中国式现代化的中国特色和本质要求。',
    significance: '擘画了全面建设社会主义现代化国家的宏伟蓝图，是推进中华民族伟大复兴的政治宣言和行动纲领。'),

  PartyHistoryItem(category: 'meeting', time: '2024年7月', title: '二十届三中全会',
    content: '审议通过《中共中央关于进一步全面深化改革、推进中国式现代化的决定》。提出300多项重要改革举措。总目标：继续完善和发展中国特色社会主义制度，推进国家治理体系和治理能力现代化。聚焦构建高水平社会主义市场经济体制、聚焦发展全过程人民民主等"七个聚焦"。',
    significance: '新征程上进一步全面深化改革的纲领性文件，是推动中国式现代化的强大动力。'),

  // ═══════════════════════════════════════
  // 党的精神谱系
  // ═══════════════════════════════════════
  PartyHistoryItem(category: 'spirit', time: '1921-', title: '伟大建党精神',
    content: '坚持真理、坚守理想，践行初心、担当使命，不怕牺牲、英勇斗争，对党忠诚、不负人民。这是中国共产党的精神之源。'),

  PartyHistoryItem(category: 'spirit', time: '1927-1937', title: '井冈山精神',
    content: '坚定信念、艰苦奋斗，实事求是、敢闯新路，依靠群众、勇于胜利。'),

  PartyHistoryItem(category: 'spirit', time: '1931-1937', title: '苏区精神',
    content: '坚定信念、求真务实、一心为民、清正廉洁、艰苦奋斗、争创一流、无私奉献。'),

  PartyHistoryItem(category: 'spirit', time: '1934-1936', title: '长征精神',
    content: '把全国人民和中华民族的根本利益看得高于一切，坚定革命的理想和信念，坚信正义事业必然胜利的精神；为了救国救民，不怕任何艰难险阻，不惜付出一切牺牲的精神；坚持独立自主、实事求是，一切从实际出发的精神；顾全大局、严守纪律、紧密团结的精神；紧紧依靠人民群众，同人民群众生死相依、患难与共、艰苦奋斗的精神。'),

  PartyHistoryItem(category: 'spirit', time: '1935', title: '遵义会议精神',
    content: '坚定信念、实事求是、独立自主、敢闯新路、民主团结。'),

  PartyHistoryItem(category: 'spirit', time: '1935-1948', title: '延安精神',
    content: '坚定正确的政治方向，解放思想、实事求是的思想路线，全心全意为人民服务的根本宗旨，自力更生、艰苦奋斗的创业精神。'),

  PartyHistoryItem(category: 'spirit', time: '1931-1945', title: '东北抗联精神',
    content: '坚定的信仰信念、高尚的爱国情操、伟大的牺牲精神。'),

  PartyHistoryItem(category: 'spirit', time: '1937-1945', title: '抗战精神',
    content: '天下兴亡、匹夫有责的爱国情怀，视死如归、宁死不屈的民族气节，不畏强暴、血战到底的英雄气概，百折不挠、坚忍不拔的必胜信念。'),

  PartyHistoryItem(category: 'spirit', time: '1940s', title: '红岩精神',
    content: '坚如磐石的理想信念、和衷共济的爱国情怀、不折不挠的凛然斗志、坚贞不屈的浩然正气。'),

  PartyHistoryItem(category: 'spirit', time: '1948-1949', title: '西柏坡精神',
    content: '谦虚谨慎、艰苦奋斗、实事求是、一心为民。核心是"两个务必"：务必使同志们继续地保持谦虚谨慎不骄不躁的作风，务必使同志们继续地保持艰苦奋斗的作风。'),

  PartyHistoryItem(category: 'spirit', time: '1950-1953', title: '抗美援朝精神',
    content: '祖国和人民利益高于一切的爱国主义精神，英勇顽强、舍生忘死的革命英雄主义精神，不畏艰难困苦的革命乐观主义精神，为完成使命慷慨奉献一切的革命忠诚精神，为人类和平与正义事业而奋斗的国际主义精神。'),

  PartyHistoryItem(category: 'spirit', time: '1950s-1960s', title: '"两弹一星"精神',
    content: '热爱祖国、无私奉献，自力更生、艰苦奋斗，大力协同、勇于登攀。'),

  PartyHistoryItem(category: 'spirit', time: '1960s', title: '雷锋精神',
    content: '热爱党、热爱祖国、热爱社会主义的崇高理想和坚定信念；服务人民、助人为乐的奉献精神；干一行爱一行、专一行精一行的敬业精神；锐意进取、自强不息的创新精神；艰苦奋斗、勤俭节约的创业精神。'),

  PartyHistoryItem(category: 'spirit', time: '1960s', title: '焦裕禄精神',
    content: '亲民爱民、艰苦奋斗、科学求实、迎难而上、无私奉献。'),

  PartyHistoryItem(category: 'spirit', time: '1960s', title: '红旗渠精神',
    content: '自力更生、艰苦创业、团结协作、无私奉献。'),

  PartyHistoryItem(category: 'spirit', time: '1960s-1970s', title: '大庆精神（铁人精神）',
    content: '爱国、创业、求实、奉献。'),

  PartyHistoryItem(category: 'spirit', time: '1978-', title: '改革开放精神',
    content: '解放思想、实事求是，敢闯敢试、勇于创新，互利合作、命运与共。'),

  PartyHistoryItem(category: 'spirit', time: '1980-', title: '特区精神',
    content: '敢闯敢试、敢为人先、埋头苦干。'),

  PartyHistoryItem(category: 'spirit', time: '1998', title: '抗洪精神',
    content: '万众一心、众志成城，不怕困难、顽强拼搏，坚韧不拔、敢于胜利。'),

  PartyHistoryItem(category: 'spirit', time: '2008', title: '抗震救灾精神',
    content: '万众一心、众志成城，不畏艰险、百折不挠，以人为本、尊重科学。'),

  PartyHistoryItem(category: 'spirit', time: '2003-', title: '载人航天精神',
    content: '特别能吃苦、特别能战斗、特别能攻关、特别能奉献。'),

  PartyHistoryItem(category: 'spirit', time: '2015-2020', title: '脱贫攻坚精神',
    content: '上下同心、尽锐出战、精准务实、开拓创新、攻坚克难、不负人民。'),

  PartyHistoryItem(category: 'spirit', time: '2020-', title: '抗疫精神',
    content: '生命至上、举国同心、舍生忘死、尊重科学、命运与共。'),

  PartyHistoryItem(category: 'spirit', time: '2021-', title: '"三牛"精神',
    content: '为民服务孺子牛、创新发展拓荒牛、艰苦奋斗老黄牛。'),

  PartyHistoryItem(category: 'spirit', time: '', title: '科学家精神',
    content: '胸怀祖国、服务人民的爱国精神，勇攀高峰、敢为人先的创新精神，追求真理、严谨治学的求实精神，淡泊名利、潜心研究的奉献精神，集智攻关、团结协作的协同精神，甘为人梯、奖掖后学的育人精神。'),

  PartyHistoryItem(category: 'spirit', time: '', title: '企业家精神',
    content: '爱国敬业、遵纪守法、艰苦奋斗，创新发展、专注品质、追求卓越，履行责任、敢于担当、服务社会。'),

  PartyHistoryItem(category: 'spirit', time: '', title: '新时代北斗精神',
    content: '自主创新、开放融合、万众一心、追求卓越。'),

  PartyHistoryItem(category: 'spirit', time: '', title: '探月精神',
    content: '追逐梦想、勇于探索、协同攻坚、合作共赢。'),

  PartyHistoryItem(category: 'spirit', time: '', title: '丝路精神',
    content: '和平合作、开放包容、互学互鉴、互利共赢。'),
];
