/// 概括练习素材服务 — 从权威党媒爬取文章做概括训练
import 'dart:convert';
import 'dart:io' show File, HttpClient;
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:html/parser.dart' as parser;
import 'package:path_provider/path_provider.dart';
import '../scorer/ai_scorer.dart';
import '../database/db_helper.dart';

class SummaryExercise {
  final String id;
  final String level;
  final String levelName;
  final String source;
  final String content;
  final String? hint;
  final String? referenceAnswer; // AI 或本地生成的参考答案
  SummaryExercise({required this.id, required this.level, required this.levelName, required this.source, required this.content, this.hint, this.referenceAnswer = null});
}

class SummaryPracticeService {

  static String _fixEncoding(http.Response resp) {
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }
  final Random _random = Random();
  final List<_PartyArticle> _articles = [];
  bool _loaded = false;
  String _errorMsg = '';

  // 去重：最近 10 次用过的素材哈希，避免刷新重复
  final List<int> _recentHashes = [];
  static const int _maxRecent = 10;
  // 各题型位置轮转计数器
  int _sentenceOffset = 0;
  int _paragraphOffset = 0;
  int _fullOffset = 0;
  int _outlineOffset = 0;

  // 离线兜底 — 36 段覆盖申论高频主题，每段 150-400 字
  static const _fallbackArticles = [
    // ── 经济发展 ──
    '坚持稳中求进工作总基调，推动高质量发展取得新成效。各地区各部门完整准确全面贯彻新发展理念，加快构建新发展格局，着力推动经济实现质的有效提升和量的合理增长。面对复杂严峻的国际环境和国内改革发展稳定任务，我们保持战略定力，坚持问题导向，迎难而上、砥砺前行。',
    '深入实施创新驱动发展战略，强化国家战略科技力量。基础研究投入持续加大，关键核心技术攻关取得重要突破，科技自立自强迈出坚实步伐。要完善科技创新体系，优化配置创新资源，提升国家创新体系整体效能，强化企业科技创新主体地位。',
    '加快数字化转型，促进数字经济与实体经济深度融合。培育壮大人工智能、大数据、云计算等新兴产业集群，抢占未来发展制高点。要加快推进数字产业化、产业数字化，推动数字技术在各行各业的广泛应用，打造具有国际竞争力的数字产业集群。',
    '深化改革开放，持续优化营商环境。推动有效市场和有为政府更好结合，激发各类经营主体内生动力和创新活力，为高质量发展注入强劲动能。要坚决破除体制机制障碍，营造市场化、法治化、国际化一流营商环境。',
    '建设现代化产业体系，坚持把发展经济的着力点放在实体经济上。推进新型工业化，加快建设制造强国、质量强国、航天强国、交通强国、网络强国、数字中国。实施产业基础再造工程和重大技术装备攻关工程，推动制造业高端化、智能化、绿色化发展。',
    '加快全国统一大市场建设，破除地方保护和市场分割。完善产权保护、市场准入、公平竞争、社会信用等市场经济基础制度，为各类经营主体创造公平竞争环境。推动生产要素畅通流动、各类资源高效配置、市场潜力充分释放。',
    // ── 乡村振兴 ──
    '全面推进乡村振兴，加快建设农业强国。巩固拓展脱贫攻坚成果，拓宽农民增收致富渠道，建设宜居宜业和美乡村，让广大农民共享现代化成果。全方位夯实粮食安全根基，牢牢守住十八亿亩耕地红线，确保中国人的饭碗牢牢端在自己手中。',
    '发展乡村特色产业，拓宽农民增收致富渠道。完善联农带农机制，把更多农业增值收益留在农村、留给农民。深化农村土地制度改革，赋予农民更加充分的财产权益。保障进城落户农民合法土地权益，鼓励依法自愿有偿转让。',
    '学习运用"千万工程"经验，扎实推进农村人居环境整治。持续抓好农村厕所革命、生活污水垃圾治理、村容村貌提升，逐步让农村基本具备现代生活条件。加强传统村落和乡村特色风貌保护，留住乡风乡韵乡愁。',
    // ── 生态文明 ──
    '坚持绿色发展，推动经济社会发展全面绿色转型。深入打好污染防治攻坚战，积极稳妥推进碳达峰碳中和，让绿水青山真正成为金山银山。统筹产业结构调整、污染治理、生态保护、应对气候变化，协同推进降碳、减污、扩绿、增长。',
    '持续深入打好蓝天碧水净土保卫战，建设人与自然和谐共生的美丽中国。生态文明建设是关系中华民族永续发展的根本大计，要像保护眼睛一样保护生态环境，推动形成绿色生产方式和生活方式。',
    '加快推动能源结构调整优化，大力发展风电、光伏等清洁能源。完善能源消耗总量和强度调控，逐步转向碳排放总量和强度双控制度。推动能源清洁低碳高效利用，推进工业、建筑、交通等领域清洁低碳转型。',
    // ── 民生保障 ──
    '完善社会保障体系，织密扎牢民生兜底保障网。养老、医疗、教育等领域改革持续深化，人民群众获得感、幸福感、安全感不断增强。健全覆盖全民、统筹城乡、公平统一、可持续的多层次社会保障体系，让发展成果更多更公平惠及全体人民。',
    '坚持以人民为中心的发展思想，着力解决群众急难愁盼问题。把增进民生福祉作为发展的根本目的，在发展中补齐民生短板。聚焦教育、医疗、养老、住房等民生重点领域，持续加大投入力度，不断提高公共服务水平和可及性。',
    '全面推进健康中国建设，深化医药卫生体制改革。坚持预防为主的方针，加强重大疾病防治，提升基层医疗服务能力，让群众就近享有公平可及的健康服务。加快构建强大的公共卫生体系，提高应对突发公共卫生事件能力。',
    '健全就业公共服务体系，完善重点群体就业支持体系。实施更加积极的就业政策，支持高校毕业生、农民工、退役军人等群体就业创业。健全终身职业技能培训制度，推动解决结构性就业矛盾。',
    '加快建立多主体供给、多渠道保障、租购并举的住房制度。坚持房子是用来住的不是用来炒的定位，支持刚性和改善性住房需求，解决好新市民、青年人等住房问题。',
    // ── 教育科技人才 ──
    '深入实施科教兴国战略，强化现代化建设人才支撑。坚持教育优先发展、科技自立自强、人才引领驱动，加快建设教育强国、科技强国、人才强国。全面提高人才自主培养质量，着力造就拔尖创新人才，聚天下英才而用之。',
    '加快义务教育优质均衡发展，缩小区域、城乡、校际差距。优化区域教育资源配置，持续巩固"双减"治理成果。推进职业教育和高等教育内涵式发展，培养更多高素质技术技能人才和大国工匠。',
    '完善科技创新体系，健全新型举国体制。强化国家战略科技力量，优化国家科研机构、高水平研究型大学、科技领军企业定位和布局。深化科技评价改革，加大多元化科技投入，加强知识产权法治保障。',
    // ── 法治建设 ──
    '加强法治建设，推进全面依法治国。坚持法治国家、法治政府、法治社会一体建设，让人民群众在每一个司法案件中感受到公平正义。完善以宪法为核心的中国特色社会主义法律体系，扎实推进依法行政，严格公正司法。',
    '加快建设法治政府，推进机构、职能、权限、程序、责任法定化。深化行政执法体制改革，全面推进严格规范公正文明执法。加大关系群众切身利益的重点领域执法力度，完善行政执法程序。',
    // ── 文化建设 ──
    '弘扬中华优秀传统文化，推动文化自信自强。深入挖掘中华文明的精神标识和文化精髓，讲好中国故事，传播好中国声音。推动中华优秀传统文化创造性转化、创新性发展，让悠久灿烂的中华文明在新时代焕发新的生机与活力。',
    '繁荣发展文化事业和文化产业，坚持以人民为中心的创作导向。推出更多增强人民精神力量的优秀作品，培育造就大批德艺双馨的文学艺术家和规模宏大的文化文艺人才队伍。健全现代公共文化服务体系，创新实施文化惠民工程。',
    '加强全媒体传播体系建设，塑造主流舆论新格局。加快传统媒体和新兴媒体融合发展，推动优质网络文化产品供给。加强国际传播能力建设，全面提升国际传播效能，形成同我国综合国力和国际地位相匹配的国际话语权。',
    // ── 社会治理 ──
    '完善社会治理体系，健全共建共治共享的社会治理制度。坚持和发展新时代"枫桥经验"，完善正确处理新形势下人民内部矛盾机制。加快推进市域社会治理现代化，提高市域社会治理能力。',
    '强化社会治安整体防控，推进扫黑除恶常态化。依法严惩群众反映强烈的各类违法犯罪活动，发展壮大群防群治力量，营造见义勇为社会氛围。建设人人有责、人人尽责、人人享有的社会治理共同体。',
    '提高公共安全治理水平，坚持安全第一、预防为主。建立大安全大应急框架，完善公共安全体系，推动公共安全治理模式向事前预防转型。加强食品药品安全监管，切实保障人民群众"舌尖上的安全"。',
    // ── 党的建设 ──
    '落实新时代党的建设总要求，健全全面从严治党体系。全面推进党的自我净化、自我完善、自我革新、自我提高，使我们党坚守初心使命，始终成为中国特色社会主义事业的坚强领导核心。',
    '锲而不舍落实中央八项规定精神，持续深化纠治"四风"。重点纠治形式主义、官僚主义，坚决破除特权思想和特权行为。把握作风建设地区性、行业性、阶段性特点，抓住普遍发生、反复出现的问题深化整治。',
    '坚持不敢腐、不能腐、不想腐一体推进，深化标本兼治。加强新时代廉洁文化建设，教育引导广大党员干部增强不想腐的自觉。深化整治权力集中、资金密集、资源富集领域的腐败，坚决惩治群众身边的"蝇贪"。',
    // ── 基层治理 ──
    '加强基层组织建设，完善基层直接民主制度体系和工作体系。拓宽基层各类群体有序参与基层治理渠道，健全以职工代表大会为基本形式的企事业单位民主管理制度，保障人民依法管理基层公共事务和公益事业。',
    '推进政务服务标准化、规范化、便利化，深化"放管服效"改革。全面推行"一网通办"，让数据多跑路、群众少跑腿。构建亲清政商关系，健全常态化政企沟通机制，及时回应企业合理诉求，保护企业合法权益。',
    // ── 外交与国际 ──
    '坚持独立自主的和平外交政策，推动构建人类命运共同体。中国始终坚持维护世界和平、促进共同发展的外交政策宗旨，致力于推动建设相互尊重、公平正义、合作共赢的新型国际关系。',
    '推动共建"一带一路"高质量发展，打造国际合作新平台。深化拓展平等、开放、合作的全球伙伴关系，致力于扩大同各国利益的汇合点。促进大国协调和良性互动，推动构建和平共处、总体稳定、均衡发展的大国关系格局。',
    '积极参与全球治理体系改革和建设，践行共商共建共享的全球治理观。坚持真正的多边主义，推进国际关系民主化，推动全球治理朝着更加公正合理的方向发展，坚定维护以联合国为核心的国际体系。',
    // ── 综合论述 ──
    '统筹发展和安全，以新安全格局保障新发展格局。增强忧患意识，坚持底线思维，做到居安思危、未雨绸缪。强化粮食、能源资源、重要产业链供应链安全，加强海外安全保障能力建设，维护我国公民法人在海外合法权益。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 经济发展
    // ═══════════════════════════════════════════
    '大力发展数字经济，提升常态化监管水平。支持平台企业在引领发展、创造就业、国际竞争中大显身手。加快数字基础设施建设，推进5G规模化应用，促进工业互联网创新发展，为经济社会数字化转型提供坚实支撑。',
    '推动产业结构优化升级，加快传统产业数字化改造。实施先进制造业集群发展行动，培育壮大战略性新兴产业，推动现代服务业同先进制造业深度融合。鼓励企业加大技术改造和设备更新力度，提升全要素生产率。',
    '完善促进消费体制机制，增强消费对经济发展的基础性作用。多渠道增加城乡居民收入，稳定汽车等大宗消费，推动餐饮、文化、旅游等生活服务消费恢复。培育壮大新型消费，倡导绿色低碳消费。',
    '优化民营经济发展环境，依法保护民营企业产权和企业家权益。全面梳理涉企法律法规政策，持续破除影响平等准入的各种壁垒。完善公平竞争制度，加强反垄断和反不正当竞争，为各类所有制企业创造公平市场环境。',
    '推动区域协调发展战略，构建优势互补的区域经济布局。深入实施西部大开发、东北全面振兴、中部地区崛起、东部率先发展战略。有序推进京津冀协同发展、长江经济带发展和粤港澳大湾区建设。',
    '深化金融体制改革，增强金融服务实体经济能力。健全资本市场功能，提高直接融资比重。加强金融法治建设，压实各方责任，防范化解重大经济金融风险。保持人民币汇率在合理均衡水平上的基本稳定。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 乡村振兴
    // ═══════════════════════════════════════════
    '强化农业科技和装备支撑，加快推进种业振兴行动。实施新一轮千亿斤粮食产能提升行动，推进高标准农田建设和国家黑土地保护工程。健全种粮农民收益保障机制和主产区利益补偿机制，调动农民种粮积极性。',
    '巩固和完善农村基本经营制度，深化农村集体产权制度改革。发展新型农村集体经济，培育新型农业经营主体和社会化服务组织。健全农村金融服务体系，为乡村振兴提供可持续的资金保障。',
    '扎实推进乡村建设和乡村治理，提升农村基础设施和公共服务水平。持续加强农村道路、供水、能源、通信等基础设施建设，推动基本公共服务资源下沉。深入开展农村精神文明创建活动，培育文明乡风。',
    '推动人才下乡和返乡创业，培育乡村本土人才队伍。实施高素质农民培育计划，大力发展面向乡村振兴的职业教育。完善乡村人才引进和激励机制，引导各类人才在乡村振兴中建功立业。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 生态文明
    // ═══════════════════════════════════════════
    '建立健全生态产品价值实现机制，拓宽绿水青山转化金山银山的路径。完善生态保护补偿制度，探索建立碳排放权、用能权、用水权等市场化交易制度。推广GEP（生态系统生产总值）核算，让保护者受益。',
    '持续加强生物多样性保护，推动人与自然和谐共生。推进自然保护地体系建设和国家公园体制完善，实施生物多样性保护重大工程。严厉打击非法捕猎、交易野生动物等违法行为。',
    '深入实施国家节水行动，强化水资源刚性约束。坚持以水定城、以水定地、以水定人、以水定产，推动用水方式由粗放低效向节约集约转变。加强水源涵养区和重要水源地保护，保障城乡供水安全。',
    '加快构建废弃物循环利用体系，全面推进"无废城市"建设。推动生活垃圾分类提质增效，加强塑料污染全链条治理。推进退役动力电池、光伏组件等新型废弃物回收利用，促进资源节约和循环利用。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 民生保障
    // ═══════════════════════════════════════════
    '实施积极应对人口老龄化国家战略，完善养老服务体系。推动实现全体老年人享有基本养老服务，发展普惠型养老服务和互助性养老。健全居家社区机构相协调、医养康养相结合的养老服务体系。',
    '健全生育支持政策体系，降低生育养育教育成本。完善生育保险制度，发展普惠托育服务体系。推动实现适度生育水平，促进人口长期均衡发展，为经济社会持续健康发展提供坚实人口基础。',
    '完善分配制度，构建初次分配、再分配、三次分配协调配套的基础性制度安排。努力提高居民收入在国民收入分配中的比重，提高劳动报酬在初次分配中的比重。完善按要素分配政策制度，增加中低收入群体收入。',
    '加强社会救助体系建设，切实保障困难群众基本生活。健全分层分类社会救助体系，实现低收入人口动态监测和常态化救助帮扶。保障妇女儿童、残疾人、孤儿等特殊群体合法权益。',
    '深化医疗保障制度改革，促进多层次医疗保障有序衔接。完善大病保险和医疗救助制度，积极发展商业医疗保险。推进医保支付方式改革，加强医保基金监管，确保基金安全可持续。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 教育科技人才
    // ═══════════════════════════════════════════
    '推进高等教育内涵式发展，加快建设世界一流大学和一流学科。优化学科专业布局，加强基础学科、新兴学科、交叉学科建设。深化高校创新创业教育改革，提升大学生创新精神和实践能力。',
    '加强师德师风建设，培养高素质教师队伍。弘扬尊师重教社会风尚，完善中小学教师待遇保障机制。推进教师队伍治理体系和治理能力现代化，吸引更多优秀人才长期从教、终身从教。',
    '健全关键核心技术攻关新型举国体制，打赢关键核心技术攻坚战。加快实现高水平科技自立自强，强化基础研究前瞻性、战略性、系统性布局。鼓励自由探索，完善基础研究多元化投入机制。',
    '加快科技成果转化应用，打通产学研用通道。健全技术转移体系，完善科技成果评价机制。促进创新链产业链资金链人才链深度融合，推动科技成果加快转化为现实生产力。',
    '推进教育数字化战略行动，建设全民终身学习的学习型社会。加快数字教育资源的共建共享，提升全民数字素养和技能。完善国家学分银行制度，畅通各类学习成果的认定、积累和转换渠道。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 法治建设
    // ═══════════════════════════════════════════
    '完善宪法监督制度，加强备案审查制度和能力建设。维护宪法权威和尊严，确保宪法在治国理政各方面得到全面实施。健全保证宪法全面实施的制度体系，让宪法观念深入人心。',
    '加强重点领域和新兴领域立法，推进科学立法、民主立法、依法立法。统筹立改废释纂，增强立法系统性、整体性、协同性、时效性。完善和加强备案审查制度，切实维护国家法治统一。',
    '强化行政执法监督机制和能力建设，健全行政裁量权基准制度。完善基层综合执法体制机制，推动执法重心下移。畅通违法行为投诉举报渠道，保障人民群众监督权。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 文化建设
    // ═══════════════════════════════════════════
    '推进城乡公共文化服务体系一体建设，提升公共文化服务水平。鼓励社会力量参与公共文化服务供给，创新实施文化惠民工程。推动公共文化数字化建设，让人民享有更加充实的精神文化生活。',
    '加强文化遗产系统性保护利用，推动非遗融入现代生活。加大文物和文化遗产保护力度，加强城乡建设中历史文化保护传承。建好用好国家文化公园，让厚重历史与现代生活交相辉映。',
    '推动文化和旅游深度融合发展，释放文旅消费潜力。坚持以文塑旅、以旅彰文，建设一批富有文化底蕴的世界级旅游景区和度假区。培育壮大文旅市场主体，打造文旅融合新业态新模式。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 社会治理
    // ═══════════════════════════════════════════
    '健全城乡社区治理体系，推进市域社会治理现代化。完善网格化管理、精细化服务、信息化支撑的基层治理平台。发挥社会组织在基层治理中的积极作用，构建多元共治格局。',
    '完善社会矛盾纠纷多元预防调处化解综合机制，从源头上减少社会矛盾。畅通和规范群众诉求表达、利益协调、权益保障通道。加强和改进人民信访工作，推动领导干部接访下访制度化常态化。',
    '健全社会心理服务体系和危机干预机制，培育自尊自信、理性平和、积极向上的社会心态。加强青少年心理健康教育和生命教育，完善精神卫生服务体系，为人民群众心理健康保驾护航。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 党的建设
    // ═══════════════════════════════════════════
    '完善党的自我革命制度规范体系，健全党内法规制度体系。坚持制度治党、依规治党，形成坚持真理、修正错误、发现问题、纠正偏差的有效机制。推动党内法规与国家法律有机衔接，形成完善的党内法规体系。',
    '建设堪当民族复兴重任的高素质干部队伍，优化干部选育管用工作。坚持德才兼备、以德为先、五湖四海、任人唯贤。加强干部斗争精神和斗争本领养成，激励干部敢于担当、积极作为。',
    '增强党组织政治功能和组织功能，把各领域广大群众组织凝聚好。持续整顿软弱涣散基层党组织，推进以党建引领基层治理。注重从青年、产业工人、知识分子中发展党员，不断优化党员队伍结构。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 基层治理与城市发展
    // ═══════════════════════════════════════════
    '推进以人为核心的新型城镇化，加快农业转移人口市民化。深化户籍制度改革，完善财政转移支付与农业转移人口市民化挂钩机制。保障随迁子女平等接受义务教育，健全常住地提供基本公共服务制度。',
    '有序推进城市更新行动，着力打造宜居、韧性、智慧城市。加强城市基础设施建设，推进地下综合管廊和海绵城市建设。完善城市防洪排涝体系，提升城市防灾减灾能力。',
    '完善基层应急管理体系，增强城乡社区应急管理能力。健全基层应急指挥机制，强化应急物资储备和保障。加强基层应急救援队伍建设，提高群众自救互救能力。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 外交与国际合作
    // ═══════════════════════════════════════════
    '推动落实全球发展倡议，加大对全球发展合作的资源投入。坚持发展优先、以人民为中心，深化在减贫、粮食安全、发展筹资等领域务实合作。为发展中国家提供更多发展支持，促进全球均衡发展。',
    '推动落实全球安全倡议，走对话而不对抗、结伴而不结盟的国与国交往新路。坚持共同、综合、合作、可持续的安全观，推动政治解决热点问题。维护核不扩散体系，倡导和平利用外层空间。',
    '参与全球数字治理，推动制定全球数字治理规则。积极参与数据安全、数字货币、数字税等国际规则和数字技术标准制定。推动全球数字经济发展，弥合数字鸿沟，让各国共享数字时代红利。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 改革开放
    // ═══════════════════════════════════════════
    '稳步扩大规则、规制、管理、标准等制度型开放，营造国际一流营商环境。合理缩减外资准入负面清单，依法保护外商投资权益。推动货物贸易优化升级，创新服务贸易发展机制，加快建设贸易强国。',
    '深化"放管服效"改革，加快数字政府建设。全面实行行政许可事项清单管理，推进政务服务事项集成化办理。完善一体化在线政务服务平台功能，让更多服务事项实现"一网通办""跨省通办"。',
    '完善产权保护制度，建立统一规范的产权交易市场。依法保护各类市场主体的财产权和其他合法权益，落实公平竞争审查制度。健全知识产权快速协同保护机制，加大对侵权行为的打击力度。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 国防与安全
    // ═══════════════════════════════════════════
    '全面加强国家安全教育，提高全民国家安全意识和素养。筑牢国家安全人民防线，打好防范化解重大风险的人民战争。广泛开展国家安全宣传教育活动，推动总体国家安全观深入人心。',
    '加强网络安全保障体系和能力建设，切实维护国家网络空间主权。健全网络综合治理体系，推动形成良好网络生态。加快关键信息基础设施安全保护，强化数据安全保障和个人信息保护。',
    '加强能源安全保障，推动能源生产和消费革命。立足我国能源资源禀赋，坚持先立后破，有计划分步骤实施碳达峰行动。深入推进能源革命，加强煤炭清洁高效利用，加快规划建设新型能源体系。',
    // ═══════════════════════════════════════════
    // 扩展素材 — 综合论述补充
    // ═══════════════════════════════════════════
    '提升防灾减灾救灾能力，加强国家区域应急力量建设。强化灾害监测预警和风险防范，完善灾害保险制度。健全应急救援指挥体系，加强基层应急力量建设和应急物资保障，提高全社会抵御灾害的综合能力。',
    '加强民族团结进步教育，铸牢中华民族共同体意识。全面贯彻党的民族政策，促进各民族交往交流交融。支持民族地区加快发展，推动各族人民共同走向社会主义现代化。',
    '推进健康中国建设，把保障人民健康放在优先发展的战略位置。完善人民健康促进政策，深入开展爱国卫生运动。优化人口发展战略，建立生育支持政策体系，降低生育、养育、教育成本。',
    '加快构建新发展格局，着力推动高质量发展。把实施扩大内需战略同深化供给侧结构性改革有机结合起来，增强国内大循环内生动力和可靠性。提升国际循环质量和水平，推动国内国际双循环相互促进。',
    '强化就业优先政策，健全就业促进机制。完善高校毕业生、退役军人、农民工等重点群体就业支持体系。统筹城乡就业政策，破除妨碍劳动力、人才流动的体制和政策弊端，消除就业歧视。',
    '发展全过程人民民主，保障人民当家作主。健全全面、广泛、有机衔接的人民当家作主制度体系。完善基层直接民主制度体系和工作体系，拓宽基层各类群体有序参与基层治理的渠道。',
    '加快发展方式绿色转型，推动经济社会发展绿色化、低碳化。加快推动产业结构、能源结构、交通运输结构等调整优化。推进各类资源节约集约利用，加快构建废弃物循环利用体系。',
    '加强城乡建设中历史文化保护传承，延续城市文脉。在城乡建设中系统保护、利用、传承好历史文化遗产。推进历史文化名城名镇名村保护，让城市留下记忆，让人们记住乡愁。',
    '推进义务教育优质均衡发展和城乡一体化，优化区域教育资源配置。加快学前教育普惠发展，坚持高中阶段学校多样化发展。完善覆盖全学段学生资助体系，不让一个孩子因家庭困难而失学。',
    '完善志愿服务制度和工作体系，弘扬奉献、友爱、互助、进步的志愿精神。健全社会工作体制机制，加强社会工作者队伍建设。引导支持有意愿有能力的企业、社会组织和个人积极参与公益慈善事业。',
    '加快培育完整内需体系，全面促进消费。顺应居民消费升级趋势，把扩大消费同改善人民生活品质结合起来。鼓励发展消费新模式新业态，推动线上线下消费深度融合，培育壮大智慧零售、智慧旅游等新型消费。',
    '深入实施区域重大战略，推动区域协调发展。推进京津冀协同发展、长江经济带发展、粤港澳大湾区建设、长三角一体化发展，打造引领高质量发展的第一梯队。推动黄河流域生态保护和高质量发展。',
    '坚持创新在我国现代化建设全局中的核心地位。面向世界科技前沿、面向经济主战场、面向国家重大需求、面向人民生命健康，加快实现高水平科技自立自强。强化国家战略科技力量，提升企业技术创新能力。',
    '加快发展现代服务业，推动生产性服务业向专业化和价值链高端延伸。推动生活性服务业向高品质和多样化升级。加快发展健康、养老、育幼、文化、旅游、体育、家政等服务业，加强公益性基础性服务业供给。',
    '全面推进健康乡村建设，提升村卫生室标准化建设和健康管理水平。推动乡村医生向执业医师转变，采取派驻巡诊等方式提高基层卫生服务水平。加强妇幼、老年人、残疾人等重点人群健康服务。',
    '完善农业支持保护制度，健全农村金融服务体系。发展农业保险和再保险，增强农业抗风险能力。深化供销合作社综合改革，完善社会化为农服务体系，把小农户引入现代农业发展轨道。',
    '全面推进城市生活垃圾分类，加快建立分类投放、分类收集、分类运输、分类处理的生活垃圾处理系统。推进生活垃圾焚烧处理设施建设，减少垃圾填埋量，提高资源化利用水平。',
    '健全现代环境治理体系，完善生态环境管理制度。全面实行排污许可制，推进排污权、用能权、用水权、碳排放权市场化交易。完善环境保护、节能减排约束性指标管理。',
    '实施城市更新行动，推进城市生态修复、功能完善工程。加强城镇老旧小区改造和社区建设，增强城市防洪排涝能力。建设韧性城市，提高城市治理水平，打造宜居韧性智慧的现代化城市。',
    '加快数字社会建设步伐，提升公共服务数字化智能化水平。推进学校、医院、养老院等公共服务机构资源数字化，加大开放共享和应用力度。推动购物消费、居家生活、旅游休闲等各类场景数字化。',
    '深化教育领域综合改革，加快建设高质量教育体系。发展素质教育，促进教育公平。推动义务教育优质均衡发展和城乡一体化，完善普惠性学前教育和特殊教育保障机制。',
    '完善科技创新体制机制，激发人才创新活力。改进科技项目组织管理方式，实行揭榜挂帅等制度。完善科技评价机制，优化科技奖励项目。加快科研院所改革，扩大科研自主权。',
    '加强和创新社会治理，维护社会和谐稳定。完善基层民主协商制度，实现政府治理同社会调节、居民自治良性互动。建设人人有责、人人尽责、人人享有的社会治理共同体。',
    '全面推进文化繁荣兴盛，增强人民精神力量。加强党史、新中国史、改革开放史、社会主义发展史教育。建设长城、大运河、长征、黄河等国家文化公园，传承弘扬中华优秀传统文化。',
    '加快国防和军队现代化，实现富国和强军相统一。加快军事理论现代化、军队组织形态现代化、军事人员现代化、武器装备现代化，提高捍卫国家主权安全发展利益的战略能力。',
    '完善现代金融监管体系，提高金融监管透明度和法治化水平。健全金融风险预防预警处置问责制度体系，对违法违规行为零容忍。维护金融安全，守住不发生系统性风险的底线。',
    '加快推动绿色低碳发展，强化国土空间规划和用途管控。落实生态保护、基本农田、城镇开发等空间管控边界。强化绿色发展的法律和政策保障，发展绿色金融。',
    '全面促进农村消费，加快完善县乡村三级物流配送体系。改造提升农村寄递物流基础设施，推进电子商务进农村和农产品出村进城。推动城乡生产与消费有效对接。',
    '推动长江经济带高质量发展，谱写生态优先绿色发展新篇章。持续做好长江十年禁渔工作，加强长江水生生物多样性保护。统筹沿江港口岸线产业布局，建设绿色低碳的长江黄金经济带。',
    '完善公共文化服务体系，推动公共文化数字化建设。创新实施文化惠民工程，提升基层综合性文化服务中心功能。广泛开展群众性文化活动，推动公共文化服务向基层延伸覆盖。',
    '实施乡村建设行动，把乡村建设摆在社会主义现代化建设的重要位置。统筹县域城镇和村庄规划建设，保护传统村落和乡村风貌。完善乡村水、电、路、气、通信等基础设施。',
    '加快发展跨境电商，鼓励建设海外仓，保障外贸产业链供应链畅通运转。创新发展服务贸易，推进贸易数字化。完善出口管制体系，优化通关流程，提高贸易便利化水平。',
    '健全工资合理增长机制，提高劳动报酬在初次分配中的比重。完善按要素分配政策制度，多渠道增加城乡居民财产性收入。完善再分配机制，加大税收社保转移支付等调节力度和精准性。',
    '完善国家应急管理体系，加强应急物资保障体系建设。健全分级负责、属地为主、部门协同的应急管理体制。发展巨灾保险，提高防灾减灾抗灾救灾能力，筑牢应急管理人民防线。',
    '提升生态系统质量和稳定性，增强生态产品供给能力。坚持山水林田湖草沙系统治理，构建以国家公园为主体的自然保护地体系。加强大江大河和重要湖泊湿地生态保护治理。',
    '深入推进优质粮食工程，实施新一轮高标准农田建设工程。开展粮食节约行动，减少粮食损耗。加强种子库建设，推进生物育种产业化应用，有序推进生物育种产业化。',
    '强化就业优先导向，提高经济增长的就业带动力。健全灵活就业劳动用工和社会保障政策，保障新就业形态劳动者权益。开展大规模职业技能培训，共建共享一批公共实训基地。',
    '加快构建现代能源体系，大力提升能源供给保障能力。加快发展非化石能源，建设一批多能互补的清洁能源基地。推进能源革命，建设清洁低碳、安全高效的能源体系。',
    '完善基本养老保险全国统筹制度，实施渐进式延迟法定退休年龄。发展多层次多支柱养老保险体系，推进社保转移接续。健全重大疾病医疗保险和救助制度。',
    '强化反垄断和防止资本无序扩张，健全公平竞争审查机制。加强平台经济、科技创新、信息安全、民生保障等重点领域监管执法。加强消费者权益保护，营造安全放心消费环境。',
    '保障进城落户农民土地承包权、宅基地使用权、集体收益分配权，鼓励依法自愿有偿转让。健全城乡统一的建设用地市场，探索实施农村集体经营性建设用地入市制度。',
    '推动文化和旅游融合发展，建设一批富有文化底蕴的世界级旅游景区。推进红色旅游、乡村旅游、文化遗产旅游等创新发展。规范在线旅游经营服务，提升旅游服务质量。',
    '加强国家实验室建设，重组国家重点实验室体系。布局建设综合性国家科学中心和区域性创新高地，支持有条件的地方建设科技创新中心。强化企业创新主体地位，促进各类创新要素向企业集聚。',
    '加快国有经济布局优化和结构调整，发挥国有经济战略支撑作用。完善中国特色现代企业制度，推进国有企业混合所有制改革。健全管资本为主的国有资产监管体制。',
    '推进服务业扩大开放综合试点，有序扩大服务业对外开放。健全外商投资准入前国民待遇加负面清单管理制度，进一步缩减外资准入负面清单。推动电信、互联网、教育、文化、医疗等重点领域有序开放。',
    '推进政法领域全面深化改革，健全社会公平正义法治保障制度。深化司法责任制综合配套改革，健全纪检监察机关公安机关检察机关审判机关司法行政机关各司其职的体制机制。',
    '加快构建以国家公园为主体的自然保护地体系，科学划定自然保护地类型。健全国家公园管理体制，完善特许经营制度。加强野生动植物保护，严厉打击非法捕猎采集交易野生动植物行为。',
    '统筹推进现代流通体系建设，完善流通领域制度规范和标准。加快形成内外联通安全高效的物流网络，完善现代商贸流通体系。推动交通物流、商贸流通、信用信息等基础设施数字化智能化升级。',
    '全面推进健康中国建设，健全全民医保制度。推动基本医疗保险省级统筹，健全重大疾病医疗保险和救助制度。稳步建立长期护理保险制度，积极发展商业医疗保险。',
    '健全基层群众自治制度，完善村民委员会居民委员会等基层群众性自治组织。拓宽人民群众反映意见和建议的渠道。完善基层直接民主制度体系和工作体系，保障人民依法管理基层公共事务。',
    '加快构建废旧物资循环利用体系，推进快递包装绿色转型。加强塑料污染全链条治理，推行垃圾分类和减量化资源化。推进退役动力电池、光伏组件、风电机组叶片等新型废弃物回收利用。',
    '健全党组织领导的自治法治德治相结合的城乡基层治理体系。完善基层民主协商制度，扩大人民有序政治参与。完善社会矛盾纠纷多元预防调处化解综合机制。',
    '实施区域协调发展战略，构建优势互补高质量发展的区域经济布局。健全区域战略统筹、市场一体化发展、区域合作互助、区际利益补偿等机制，促进区域间融合互动融通补充。',
    '加快数字化发展，建设数字中国。打造数字经济新优势，加快数字社会建设步伐，提高数字政府建设水平。营造良好数字生态，建立健全数据要素市场规则。',
    '建设更高水平开放型经济新体制，推动贸易和投资自由化便利化。完善外商投资准入前国民待遇加负面清单管理制度，有序扩大服务业对外开放。推动共建一带一路高质量发展。',
    '完善生态文明领域统筹协调机制，构建生态文明体系。健全生态环境监测和评价制度，完善中央生态环境保护督察制度。健全自然资源资产产权制度和法律法规。',
    '健全防止返贫监测和帮扶机制，对易返贫致贫人口及时发现及时帮扶。坚持和完善东西部协作和对口支援、社会力量参与帮扶等机制，推动减贫战略和工作体系平稳转型。',
    '完善国家行政体系，建设职责明确、依法行政的政府治理体系。深化简政放权放管结合优化服务改革，全面实行政府权责清单制度。推进政务服务标准化规范化便利化。',
    '加快发展现代产业体系，推动经济体系优化升级。坚持把发展经济着力点放在实体经济上，推进产业基础高级化、产业链现代化。发展战略性新兴产业，加快发展现代服务业。',
    '推动黄河流域生态保护和高质量发展，加强黄河保护治理。改善黄河流域生态环境，优化水资源配置，促进全流域高质量发展。保护传承弘扬黄河文化，让黄河成为造福人民的幸福河。',
  ];

  bool get isUsingFallback => _articles.isEmpty;

  /// AI 生成的练习题（供历史查看）
  Future<List<Map<String, String>>> get aiExercises => _loadAIExercises();

  /// 删除一条 AI 练习题
  Future<void> removeAIExercise(int index) async {
    final list = await _loadAIExercises();
    if (index < list.length) list.removeAt(index);
    final db = DatabaseHelper();
    await db.setSetting('ai_summary_exercises', jsonEncode(list));
  }

  List<_PartyArticle> get _pool =>
      _articles.isNotEmpty ? _articles : _fallbackArticles.map((s) => _PartyArticle(s, '离线素材', '')).toList();

  /// 初始化 — 优先从本地缓存加载，无缓存时用离线素材
  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;

    // 尝试从本地缓存加载（异步但不阻塞）
    _loadCache().then((cached) {
      if (cached.isNotEmpty) _articles.addAll(cached);
    });
    // 用离线素材立即可用，不等待爬取
    _errorMsg = _articles.isEmpty ? '点击刷新获取最新党媒文章' : '';
  }

  /// 手动刷新 — 重新爬取文章
  Future<void> refresh() async {
    _articles.clear();
    _errorMsg = '正在抓取...';

    // 每个源多抓一些链接
    var links = <_PartyArticle>[];
    for (final source in [
      ('https://opinion.people.com.cn/', '人民网', (String href) => href.contains('/n1/')),
      ('https://www.xinhuanet.com/comments/', '新华网', (String href) => href.contains('/comments/') || href.contains('news.cn/')),
      ('https://www.qstheory.cn/', '求是网', (String href) => href.contains('qstheory.cn') && href.contains('.html')),
    ]) {
      var sourceLinks = await _scrapeLinks(source.$1, source.$2, source.$3);
      if (sourceLinks.isEmpty) {
        sourceLinks = await _scrapeLinks(source.$1.replaceFirst('https', 'http'), source.$2, source.$3);
      }
      links.addAll(sourceLinks);
    }

    if (links.isNotEmpty) {
      // 取足够链接保证正文抓取成功
      final toFetch = links.take(30).toList();
      final futures = toFetch.map((a) => _fetchArticleBody(a));
      final enriched = await Future.wait(futures);
      _articles.addAll(enriched.where((a) => a.body.length > 80));
    }

    if (_articles.isNotEmpty) {
      await _saveCache();
      // 有 AI Key 时生成练习题
      await _tryAIGenerate();
      _errorMsg = '';
    } else {
      _errorMsg = '党媒抓取失败，使用离线素材';
    }
  }

  /// AI Key 可用时从抓取的文章生成练习题并缓存
  Future<void> _tryAIGenerate() async {
    try {
      final apiKey = await DatabaseHelper().getSetting('deepseek_api_key');
      if (apiKey.isEmpty || _articles.isEmpty) return;
      // 取前2篇文章生成练习题
      final articles = _articles.take(2).toList();
      final allExercises = <Map<String, String>>[];
      for (final art in articles) {
        if (art.body.length < 100) continue;
        final exercises = await AIScorer.generateExercises(
          apiKey: apiKey,
          articleText: art.body,
        );
        if (exercises != null) allExercises.addAll(exercises);
      }
      if (allExercises.isNotEmpty) {
        await _saveAIExercises(allExercises);
      }
    } catch (_) {}
  }

  /// 加载 AI 生成的练习题
  Future<List<Map<String, String>>> _loadAIExercises() async {
    try {
      final db = DatabaseHelper();
      final json = await db.getSetting('ai_summary_exercises');
      if (json.isEmpty) return [];
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>()
          .map((e) => e.map((k, v) => MapEntry(k, v.toString()))).toList();
    } catch (_) { return []; }
  }

  Future<void> _saveAIExercises(List<Map<String, String>> exercises) async {
    try {
      final db = DatabaseHelper();
      // 追加到已有缓存
      final existing = await _loadAIExercises();
      existing.insertAll(0, exercises);
      if (existing.length > 40) existing.removeRange(40, existing.length);
      await db.setSetting('ai_summary_exercises', jsonEncode(existing));
    } catch (_) {}
  }

  /// 获取缓存文件路径
  Future<String> _cachePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/summary_articles.json';
  }

  /// 加载本地缓存的文章
  Future<List<_PartyArticle>> _loadCache() async {
    try {
      final path = await _cachePath();
      final file = File(path);
      if (!await file.exists()) return [];
      final jsonStr = await file.readAsString();
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => _PartyArticle(
        e['title'] ?? '',
        e['source'] ?? '',
        e['url'] ?? '',
        body: e['body'] ?? '',
        publishDate: e['publishDate'],
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存文章到本地缓存
  Future<void> _saveCache() async {
    try {
      final list = _articles.map((a) => {
        'title': a.title,
        'source': a.source,
        'url': a.url,
        'body': a.body,
        'publishDate': a.publishDate,
      }).toList();
      final path = await _cachePath();
      await File(path).writeAsString(jsonEncode(list));
    } catch (_) {}
  }

  Future<List<_PartyArticle>> _scrapeLinks(
    String url, String source, bool Function(String) urlFilter,
  ) async {
    try {
      final resp = await _httpGet(url);
      if (resp.statusCode != 200) return [];

      final html = _fixEncoding(resp);
      final doc = parser.parse(html);
      final allLinks = doc.querySelectorAll('a[href]');
      final results = <_PartyArticle>[];

      for (final el in allLinks) {
        final href = el.attributes['href'] ?? '';
        final title = el.text.trim();
        if (title.length < 10 || title.length > 200) continue;
        if (!urlFilter(href)) continue;

        final fullUrl = Uri.parse(url).resolve(href).toString();
        final date = _extractDateFromUrl(fullUrl);
        results.add(_PartyArticle(title, source, fullUrl, publishDate: date));
        if (results.length >= 8) break;
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// 统一的 HTTP GET 请求（容忍自签/过期证书）
  Future<http.Response> _httpGet(String url) async {
    final ioClient = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    final client = IOClient(ioClient);
    try {
      return await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 12));
    } finally {
      client.close();
    }
  }

  Future<_PartyArticle> _fetchArticleBody(_PartyArticle article) async {
    // 尝试 HTTPS → HTTP 各一次
    final urls = <String>[article.url];
    if (article.url.startsWith('https://')) urls.add(article.url.replaceFirst('https://', 'http://'));
    else if (article.url.startsWith('http://')) urls.insert(0, article.url.replaceFirst('http://', 'https://'));

    for (final tryUrl in urls) {
      try {
        final resp = await _httpGet(tryUrl);
        if (resp.statusCode != 200) continue;

        final html = _fixEncoding(resp);
        final doc = parser.parse(html);
        // 先清除所有非正文元素
        doc.querySelectorAll(
          'script, style, noscript, iframe, img, video, audio, nav, header, footer, '
          '.nav, .header, .footer, .sidebar, .menu, .comment, .recommend, .share, '
          '.related, .ad, .banner, .copyright, .breadcrumb, .pagination, .pageNav, '
          '[class*="nav"], [class*="header"], [class*="footer"], [class*="sidebar"], '
          '[class*="menu"], [class*="comment"], [class*="share"], [class*="recommend"], '
          '[class*="ad"], [class*="banner"], [class*="bottom"], [class*="top-"], '
          '[class*="copyright"], [class*="paging"]'
        ).forEach((e) => e.remove());

        // 策略1：正文容器选择器
        final containers = [
          '#rm_txt_zw', '#detailContent', '#articleEdit', '.detail-content', '.article-content',
          '.article', '.content', '.text', '.main-content', '#article-content', '.post-content',
          '.detail-content', '.art-con', '.rm_txt', '#content', '.highlight', '.box_con',
          '.show_text', '.text_con', '.art_con', '.se-main-content', '.cnt_bd', '#text_area',
          '.article-text', '.entry-content', '.news-content', '.post-body',
        ];
        String? bestText;
        for (final sel in containers) {
          final el = doc.querySelector(sel);
          if (el != null) {
            final text = el.text.trim();
            if (text.length >= 200) { bestText = text; break; }
          }
        }

        // 策略2：收集所有 <p> 标签
        bestText ??= (() {
          final paragraphs = doc.querySelectorAll('p');
          if (paragraphs.isNotEmpty) {
            final texts = paragraphs
                .map((p) => p.text.trim())
                .where((t) => t.length > 15)
                .take(30)
                .join('\n\n');
            if (texts.length >= 200) return texts;
          }
          return null;
        })();

        // 策略3：body 全文兜底
        bestText ??= (() {
          final body = doc.body;
          if (body != null) {
            final text = body.text.trim();
            return text.length > 200 ? text.substring(0, 3000) : null;
          }
          return null;
        })();

        if (bestText != null && bestText.length > 80) {
          return _PartyArticle(article.title, article.source, article.url,
              body: bestText, publishDate: article.publishDate);
        }
      } catch (_) {
        continue;
      }
    }
    return article;
  }

  String get errorMsg => _errorMsg;

  /// 清理文章 — 只保留正文，去掉元数据、导航、编辑信息等所有非正文内容
  static String _cleanArticle(String raw) {
    var text = raw
        .replaceAll(RegExp(r'[ \t\r]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    // 全文剥离图片文件名（如 wenti.jpg），无论嵌在何处
    // 剥离图片/文件引用（.jpg .png .pdf 等）和纯 URL
    text = text.replaceAll(RegExp(r'[^\s。；！？\n]*\.(?:jpg|jpeg|png|gif|bmp|svg|webp|pdf|docx?|xlsx?|zip|rar)[^\s。；！？\n]*', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'https?://[^\s。；！？\n]+'), '');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 找到"责任编辑""热门排行"等结尾标记，从最早出现处截断后续垃圾
    final tailPatterns = [
      '责任编辑', '责编', '编辑：', '编辑:',
      '热门排行', '推荐阅读', '相关新闻', '延伸阅读',
      '猜你喜欢', '为您推荐', '版权声明', '免责声明',
      '返回搜狐', '返回首页', '阅读原文', '查看原文',
    ];
    int? cutIdx;
    for (final kw in tailPatterns) {
      final idx = text.indexOf(kw);
      if (idx > text.length * 0.4 && (cutIdx == null || idx < cutIdx)) {
        cutIdx = idx;
      }
    }
    if (cutIdx != null) { text = text.substring(0, cutIdx); }

    // 逐行过滤，剔除所有非正文行
    final lines = text.split('\n');
    final clean = <String>[];
    for (final line in lines) {
      final s = line.trim();
      if (s.isEmpty) { clean.add(''); continue; }

      // 责任编辑/推荐等尾注行
      if (RegExp(r'^(?:责任编辑|责编|编辑[：:]|热门排行|推荐阅读|相关新闻|延伸阅读|猜你喜欢|为您推荐|版权声明|免责声明|返回搜狐|返回首页|阅读原文)').hasMatch(s)) continue;
      // 记者/通讯员/实习生署名（行首或句中）
      if (RegExp(r'(?:记者|通讯员|实习生|本报记者|光明日报记者|新华社记者|人民日报记者|央视记者|中新网记者)\s*[：:：]?').hasMatch(s) && s.length < 50) continue;
      // 来源/作者标注
      if (RegExp(r'^(?:来源|作者|原(?:标)?题)[：:]').hasMatch(s)) continue;
      // 媒体名称残留
      if (RegExp(r'^(?:人民日报|新华社|光明日报|央视网|中新网|人民网|新华网|求是网)[讯电讯报]?。?$').hasMatch(s) && s.length < 20) continue;
      // 含有记者署名 + 媒体名的混排行
      if (RegExp(r'[记者通讯员].{0,10}(?:人民日报|新华社|光明日报|央视|中新)').hasMatch(s) && s.length < 80) continue;
      // 日期时间行（2025年01月15日08:30 等）
      if (RegExp(r'^\d{4}[-/年]\d{1,2}[-/月]\d{1,2}').hasMatch(s) && s.length < 35) continue;
      // 分享/关注等社交引导
      if (RegExp(r'^(?:分享|转发|收藏|点赞)').hasMatch(s)) continue;
      if (s == '扫码' || (s.startsWith('关注') && s.length < 20)) continue;
      // 图片说明 / 文件名
      if (RegExp(r'^(?:图为|图片|资料图片|新华社发|图片来源)').hasMatch(s)) continue;
      if (RegExp(r'\.(?:jpg|jpeg|png|gif|bmp|svg|webp|pdf|doc|docx|xls)').hasMatch(s)) continue;
      // 短标记行（【xxx】引导的）
      if (RegExp(r'^【.*】$').hasMatch(s) && s.length < 20) continue;
      // 纯数字/符号行
      if (RegExp(r'^[\d\s\.\-,，、;；:：|/]+$').hasMatch(s) && s.length < 15) continue;
      // URL / 路径残留
      if (RegExp(r'^https?://').hasMatch(s) || RegExp(r'^www\.').hasMatch(s)) continue;
      // 日期行（含前缀如"发布时间""发布日期"等）
      if (RegExp(r'(?:发布|发表|更新|上传|录入|编辑)?(?:时间|日期|于)[：:]\s*\d{4}').hasMatch(s)) continue;
      // 标题行（原标题/标题/题目 等标记）
      if (RegExp(r'^[原标题目文章新闻报]{1,3}[标题题目]?[：:：]').hasMatch(s)) continue;
      // 英文/数字占比超过 60% 且含中文过少的行（HTML 残余）
      if (s.length < 80) {
        final cn = RegExp(r'[\u4e00-\u9fff]').allMatches(s).length;
        if (cn == 0 || cn.toDouble() / s.length < 0.15) continue;
      }

      clean.add(s);
    }

    var result = clean.join('\n');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 再次去掉首尾空行及无意义短行
    final finalLines = result.split('\n');
    final start = finalLines.indexWhere((l) => l.trim().length >= 10 && RegExp(r'[\u4e00-\u9fff]').hasMatch(l));
    final end = finalLines.lastIndexWhere((l) => l.trim().length >= 10 && RegExp(r'[\u4e00-\u9fff]').hasMatch(l));
    if (start > 0 || (end >= 0 && end < finalLines.length - 1)) {
      result = finalLines.sublist(start.clamp(0, finalLines.length), (end + 1).clamp(0, finalLines.length)).join('\n').trim();
    }

    // 最终清理：去掉嵌入文本中的媒体名和记者署名
    result = result.replaceAll(RegExp(r'(?:人民日报|新华社|光明日报|央视新闻|中新网)[讯电]?(?:记者|客户端)?'), '');
    result = result.replaceAll(RegExp(r'[（(](?:记者|通讯员)\s*[^）)]{2,6}[）)]'), '');
    result = result.replaceAll(RegExp(r'[（(](?:责编|责任编辑)\s*[^）)]*[）)]'), '');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result;
  }

  /// 把文章按句子切分，返回有意义的句子列表
  static List<String> _splitSentences(String text) {
    return text
        .split(RegExp(r'(?<=[。；！？])'))
        .map((s) => s.trim())
        .where((s) => s.length > 5 && RegExp(r'[\u4e00-\u9fff]').hasMatch(s))
        .toList();
  }

  /// 从句子列表取 count 句，offset 每次轮转位置避免重复
  /// 从句子列表中取 count 句，确保总长度 ≥ minLen
  static String _pickMiddleSentences(List<String> sentences, int count, [int offset = 0, int minLen = 30]) {
    if (sentences.isEmpty) return '';
    final skip = ((sentences.length * 0.15).round() + offset * 3) % sentences.length.clamp(1, 9999);
    final start = skip.clamp(0, sentences.length - 1);
    final available = sentences.sublist(start);
    String result = '';
    int taken = 0;
    for (int i = 0; i < available.length && (taken < count || result.length < minLen); i++) {
      result += (result.isEmpty ? '' : '。') + available[i];
      taken++;
    }
    if (result.isEmpty) result = sentences.take(count + 1).join('。');
    return '$result。';
  }

  /// 过滤句子：去疑问句、序号标记句、非正文内容
  /// 只过滤明确的列表序号（一、/1./（一）/首先/第一），不误杀量词（一个/一种/三人）
  static final _ordinalRe = RegExp(
    r'(?:^|。|；|！|？|\n)[ \t]*[一二三四五六七八九十][、，。．]|'
    r'(?:^|。|；|！|？|\n)[ \t]*第[一二三四五六七八九十][章节条课]|'
    r'[（(][一二三四五六七八九十][）)]|'
    r'(?:^|。|；|！|？|\n)[ \t]*(?:首先|其次|再次|最后|此外|另外|总之|综上|总的来看)|'
    r'(?:^|。|；|！|？|\n)[ \t]*\d+[、\\.．]',
  );

  static List<String> _filterCleanSentences(List<String> sentences) {
    return sentences.where((s) {
      // 1. 不要疑问句
      if (s.endsWith('？') || s.endsWith('?')) return false;
      // 2. 不要带序号的
      if (_ordinalRe.hasMatch(s)) return false;
      // 3. 不能是纯导航/标题类短句（无实质内容）
      if (s.length < 8) return false;
      if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(s)) return false;
      return true;
    }).toList();
  }

  /// 短句概括 — 从文章中间取 1~2 句独立完整的短句
  SummaryExercise shortSentenceExercise() {
    final raw = _pickArticle();
    final text = _cleanArticle(raw);
    final sentences = _splitSentences(text);
    final clean = _filterCleanSentences(sentences);
    // 优先选长度 15~50 字的句子
    final short = clean.where((s) => s.length >= 10 && s.length <= 50).toList();
    final pool = short.length >= 2 ? short : (clean.length >= 2 ? clean : sentences);
    var content = _pickMiddleSentences(pool, 3, _sentenceOffset, 60);
    // 过滤后句子太少时回退到原始句子池
    if (content.length < 60) {
      final rawPool = _splitSentences(text).where((s) => s.length >= 6).toList();
      content = _pickMiddleSentences(rawPool, 3, _sentenceOffset, 50);
    }
    _sentenceOffset = (_sentenceOffset + 1) % 20;
    return SummaryExercise(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      level: 'short', levelName: '短句概括', source: _randomSource(),
      content: content.length > 160 ? '${content.substring(0, 160)}' : content,
      hint: '抓核心删修饰，浓缩为一句（≤30字）',
    );
  }

  /// 段落概括 — 取一个完整段落（50~350字），位置每次轮转
  SummaryExercise paragraphExercise() {
    final raw = _pickArticle();
    final text = _cleanArticle(raw);
    final paragraphs = text.split('\n').where((p) => p.trim().length > 20).toList();
    String content;
    if (paragraphs.length >= 3) {
      // 轮转选段：跳过首尾各 1 段，在中间区域轮换
      final pickable = paragraphs.sublist(1, paragraphs.length - 1);
      final idx = _paragraphOffset % pickable.length;
      content = pickable[idx].trim();
      _paragraphOffset = (_paragraphOffset + 1) % 20;
      // 不够 50 字则向前后补充
      final realIdx = idx + 1; // pickable 是 paragraphs[1..len-1]，还原真实位置
      if (content.length < 50 && realIdx + 1 < paragraphs.length) {
        content = '$content\n${paragraphs[realIdx + 1].trim()}';
      }
      if (content.length < 50 && realIdx - 1 >= 0) {
        content = '${paragraphs[realIdx - 1].trim()}\n$content';
      }
      // 截到合适长度
      if (content.length > 350) {
        final end = _findSentenceEnd(content, 200, 350);
        content = content.substring(0, end).trim();
      }
    } else {
      // 只有一大段，从 1/4 处开始取
      final start = (text.length * 0.2).round();
      final chunk = text.substring(start.clamp(0, text.length));
      final end = chunk.length > 350 ? _findSentenceEnd(chunk, 200, 350) : chunk.length;
      content = chunk.substring(0, end.clamp(50, chunk.length)).trim();
      // 保证从句首开始
      final firstPeriod = content.indexOf('。');
      if (firstPeriod > 0 && firstPeriod < 20) {
        content = content.substring(firstPeriod + 1).trim();
      }
      // 如果还不够，回退到从更前的位置取
      if (content.length < 50) {
        final start2 = (text.length * 0.05).round();
        final chunk2 = text.substring(start2.clamp(0, text.length));
        final end2 = chunk2.length > 400 ? _findSentenceEnd(chunk2, 100, 400) : chunk2.length;
        content = chunk2.substring(0, end2.clamp(50, chunk2.length)).trim();
      }
    }
    return SummaryExercise(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      level: 'paragraph', levelName: '段落概括', source: _randomSource(),
      content: content,
      hint: '50字以内概括本段大意',
    );
  }

  /// 全文概括 — 取 600~1000 字，起始位置每次轮转且对齐句子边界
  SummaryExercise fullArticleExercise() {
    final raw = _pickArticle();
    final text = _cleanArticle(raw);
    String chunk;
    if (text.length > 1000) {
      final step = (text.length / 10).round().clamp(50, 300);
      final rawStart = (_fullOffset * step).clamp(0, (text.length - 600).clamp(0, text.length));
      // 对齐到最近句号之后，避免截断句子
      final start = _nextSentenceStart(text, rawStart);
      chunk = text.substring(start);
      final end = chunk.length > 1000 ? _findSentenceEnd(chunk, 600, 1000) : chunk.length;
      chunk = chunk.substring(0, end).trim();
      _fullOffset = (_fullOffset + 1) % 10;
    } else {
      chunk = text;
    }
    final content = chunk;
    return SummaryExercise(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      level: 'full', levelName: '全文概括', source: _randomSource(),
      content: content,
      hint: '200字以内归纳全文要点',
    );
  }

  /// 提纲提炼 — 同一篇文章取两段 250~400 字，截取位置每次轮转且对齐句子边界
  SummaryExercise outlineExercise() {
    final text = _cleanArticle(_pickArticle());
    final off1 = _outlineOffset;
    final off2 = (_outlineOffset + 5) % 10;
    _outlineOffset = (_outlineOffset + 1) % 10;

    String takeMiddleChunk(int offset) {
      if (text.length <= 400) return text;
      final step = (text.length / 10).round().clamp(50, 300);
      final rawStart = (offset * step).clamp(0, (text.length - 250).clamp(0, text.length));
      final start = _nextSentenceStart(text, rawStart);
      final chunk = text.substring(start);
      final end = chunk.length > 400 ? _findSentenceEnd(chunk, 250, 400) : chunk.length;
      return chunk.substring(0, end).trim();
    }

    final chunk1 = takeMiddleChunk(off1);
    final chunk2 = takeMiddleChunk(off2);
    final combined = '【材料一】\n$chunk1\n\n【材料二】\n$chunk2';
    return SummaryExercise(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      level: 'outline', levelName: '提纲提炼', source: _randomSource(),
      content: combined,
      hint: '只写结构提纲，列出要点序号，不展开论述',
    );
  }

  /// 找到指定范围内的最后一个句子结尾
  static int _findSentenceEnd(String text, int minLen, int maxLen) {
    final end = maxLen.clamp(0, text.length);
    for (final p in ['。', '！', '？', '；']) {
      final idx = text.lastIndexOf(p, end);
      if (idx > minLen) return idx + 1;
    }
    return end;
  }

  /// 从 from 位置向后找最近的句子起始位置（句号/换行之后），避免截断句子
  static int _nextSentenceStart(String text, int from) {
    if (from <= 0) return 0;
    for (final p in ['。', '！', '？']) {
      final idx = text.indexOf(p, from);
      if (idx >= 0 && idx < from + 80) return idx + 1;
    }
    // 找不到标点，退到最近换行
    final nl = text.lastIndexOf('\n', from);
    if (nl > 0) return nl + 1;
    return from;
  }

  /// 按日期权重选文章：距今天越近权重越高（今=10，-1/天，最低1），同时排除最近10次已用
  String _pickArticle() {
    final pool = _pool;
    if (pool.isEmpty) return '';
    // 构建加权列表
    final today = DateTime.now();
    final weighted = <_PartyArticle>[];
    for (final art in pool) {
      int weight = 1;
      if (art.publishDate != null) {
        try {
          final d = DateTime.parse(art.publishDate!);
          final daysAgo = today.difference(d).inDays;
          weight = (10 - daysAgo).clamp(1, 10);
        } catch (_) {}
      }
      for (int i = 0; i < weight; i++) { weighted.add(art); }
    }
    // 避免重复：先选不在最近10次的
    for (int attempt = 0; attempt < 20; attempt++) {
      final art = weighted[_random.nextInt(weighted.length)];
      final hash = (art.body.isNotEmpty ? art.body : art.title).hashCode;
      if (!_recentHashes.contains(hash)) {
        _recentHashes.add(hash);
        if (_recentHashes.length > _maxRecent) _recentHashes.removeAt(0);
        return art.body.isNotEmpty ? art.body : art.title;
      }
    }
    // 全命中，放行
    final art = weighted[_random.nextInt(weighted.length)];
    return art.body.isNotEmpty ? art.body : art.title;
  }

  String _randomSource() {
    final sources = ['人民网', '新华网', '求是网'];
    return sources[_random.nextInt(sources.length)];
  }

  /// 从 URL 提取发布日期
  static String? _extractDateFromUrl(String url) {
    var m = RegExp(r'/n1/(\d{4})/(\d{2})(\d{2})/').firstMatch(url);
    if (m != null) return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
    m = RegExp(r'/(\d{4})(\d{2})(\d{2})/').firstMatch(url);
    if (m != null) return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
    m = RegExp(r'/(\d{4})-(\d{2})/(\d{2})/').firstMatch(url);
    if (m != null) return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
    return null;
  }
}

class _PartyArticle {
  final String title;
  final String source;
  final String url;
  final String body;
  final String? publishDate;
  _PartyArticle(this.title, this.source, this.url, {this.body = '', this.publishDate});
}
