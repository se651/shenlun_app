"""验证离线题库短句概括可用性"""
import re

# Dart _filterCleanSentences 逻辑
ordinal_re = re.compile(
    r'(?:^|。|；|！|？|\n)[ \t]*[一二三四五六七八九十][、，。．]|'
    r'(?:^|。|；|！|？|\n)[ \t]*第[一二三四五六七八九十][章节条课]|'
    r'[（(][一二三四五六七八九十][）)]|'
    r'(?:^|。|；|！|？|\n)[ \t]*(?:首先|其次|再次|最后|此外|另外|总之|综上|总的来看)|'
    r'(?:^|。|；|！|？|\n)[ \t]*\d+[、.．]',
)

def filter_clean(sentences):
    result = []
    for s in sentences:
        if s.endswith('？') or s.endswith('?'): continue
        if ordinal_re.search(s): continue
        if len(s) < 8: continue
        if not re.search(r'[\u4e00-\u9fff]', s): continue
        result.append(s)
    return result

# 模拟 _pickMiddleSentences
def pick_middle(sentences, count, min_len=80):
    if len(sentences) < count:
        return '', 0
    # 从第15%位置开始取
    skip = int(len(sentences) * 0.15)
    available = sentences[skip:]
    result = ''
    taken = 0
    for s in available:
        result += ('' if not result else '。') + s
        taken += 1
        if taken >= count and len(result) >= min_len:
            break
    return result + '。', len(result)

# 从 summary_practice.dart 复制的 fallback 文章
articles = [
    '坚持稳中求进工作总基调，推动高质量发展取得新成效。各地区各部门完整准确全面贯彻新发展理念，加快构建新发展格局，着力推动经济实现质的有效提升和量的合理增长。面对复杂严峻的国际环境和国内改革发展稳定任务，我们保持战略定力，坚持问题导向，迎难而上、砥砺前行。',
    '深入实施创新驱动发展战略，强化国家战略科技力量。基础研究投入持续加大，关键核心技术攻关取得重要突破，科技自立自强迈出坚实步伐。要完善科技创新体系，优化配置创新资源，提升国家创新体系整体效能，强化企业科技创新主体地位。',
]

# 全部检查
total = 0
fails = 0
for i, text in enumerate(articles):
    sents = [s.strip() for s in re.split(r'[。！？；\n]', text) if s.strip()]
    clean = filter_clean(sents)
    content, length = pick_middle(clean, 3, 80)
    total += 1
    if length < 80:
        fails += 1
        print(f'FAIL #{i+1}: {length}字 ({len(clean)} clean sentences)')
        for s in clean[:5]:
            print(f'  ({len(s)}字) {s[:60]}')

print(f'\n总计: {total} 篇, 通过: {total-fails}, 失败: {fails}')
