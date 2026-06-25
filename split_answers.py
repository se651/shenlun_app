"""
参考答案拆分脚本
将 shenlun.db 中整卷参考答案拆分为每题独立答案
"""
import sqlite3, re, shutil, os

DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'

# ====== 中文数字映射 ======
CN_MAP = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9,'十':10,
          '十一':11,'十二':12,'十三':13,'十四':14,'十五':15}

def cn_to_int(s):
    if not s: return None
    if s.isdigit(): return int(s)
    return CN_MAP.get(s)

def extract_qnum(title):
    """从title提取题号: 第N题 → N"""
    if not title: return None
    m = re.search(r'第\s*(\d+)\s*题', title)
    if m: return int(m.group(1))
    m = re.search(r'\uff08(\d+)\uff09', title)
    if m: return int(m.group(1))
    return None

# ====== 多策略答案节解析 ======
CN = '[一二三四五六七八九十]+'

def parse_sections(ref_text):
    """
    策略1: 标准格式 N、参考答案 / 一、参考答案 / （N）参考答案 / （N）【参考答案】
    策略2: 问题N：参考答案
    策略3: 第一题/答案N 格式
    返回: [(section_num, content), ...]
    """
    if not ref_text: return []
    
    # --- 策略1: 标准"参考答案"标记 ---
    p1 = re.compile(
        r'(?:^|\n)(?:#{1,4}\s*)?'
        r'('
            r'\uff08' + CN + r'\uff09'           # （一）
            r'|'
            r'(?<!\uff08)' + CN + r'(?!\uff09)'  # 一 (bare)
            r'|'
            r'\d+'                                 # 1
        r')'
        r'(?:\s*[、.．]\s*)?'                     # separator (optional)
        r'(?:【)?参考答案(?:】)?'                   # 参考答案 or 【参考答案】
        r'(?:\uff08[A-Za-z]+\uff09)?'             # optional variant （H）
        r'[：:]?'
        , re.MULTILINE
    )
    
    headers = list(p1.finditer(ref_text))
    used_pattern = p1
    
    # --- 策略2: 问题N：参考答案 ---
    if not headers:
        p2 = re.compile(
            r'(?:^|\n)(?:#{1,4}\s*)?'
            r'问题\s*(' + CN + r'|\d+)\s*[：:]\s*'
            r'(?:【)?参考答案(?:】)?[：:]?'
            , re.MULTILINE
        )
        headers = list(p2.finditer(ref_text))
        used_pattern = p2
    
    # --- 策略3: 答案N / 第一题 ---
    if not headers:
        p3 = re.compile(
            r'(?:^|\n)(?:#{1,4}\s*)?'
            r'(?:答案\s*(' + CN + r'|\d+)\s*[：:]|'
            r'第\s*(' + CN + r')\s*题\s*[、.．]\s*(?:【)?参考答案(?:】)?)'
            , re.MULTILINE
        )
        for m in p3.finditer(ref_text):
            num_str = m.group(1) or m.group(2)
            headers.append(m)
        if headers:
            return _build_sections_p3(headers, ref_text)
    
    # --- 策略4: 【试题N】参考答案 / 问题N答案 / 【问题N参考答案】---
    if not headers:
        p4 = re.compile(
            r'(?:^|\n)(?:#{1,4}\s*)?'
            r'(?:【)?(?:试题|问题)\s*(' + CN + r'|\d+)\s*(?:】)?'
            r'(?:【)?参考答案(?:】)?[：:]?'
            , re.MULTILINE
        )
        for m in p4.finditer(ref_text):
            headers.append(m)
        if headers:
            return _build_sections_p3(headers, ref_text)
    
    # --- 策略5: 第N题（参考答案）/ 第一题：参考答案 ---
    if not headers:
        p5 = re.compile(
            r'(?:^|\n)(?:#{1,4}\s*)?'
            r'第\s*(' + CN + r'|\d+)\s*题\s*'
            r'(?:（参考答案）|：参考答案|[：:]\s*(?:【)?参考答案(?:】)?)'
            , re.MULTILINE
        )
        for m in p5.finditer(ref_text):
            headers.append(m)
        if headers:
            return _build_sections_p3(headers, ref_text)
    
    # --- 策略6: 问题N：【审题及答题思路】...【参考答案】---
    # 这种格式的答案在【参考答案】之后
    if not headers:
        p6 = re.compile(
            r'(?:^|\n)(?:#{1,4}\s*)?'
            r'问题\s*(' + CN + r'|\d+)\s*[：:]\s*【审题及答题思路】'
            , re.MULTILINE
        )
        p6_answers = re.compile(
            r'(?:^|\n)(?:#{1,4}\s*)?(?:【)?参考答案(?:】)?[：:]?\s*\n'
            , re.MULTILINE
        )
        q_markers = list(p6.finditer(ref_text))
        a_markers = list(p6_answers.finditer(ref_text))
        if q_markers and len(q_markers) == len(a_markers):
            sections = []
            for i, qm in enumerate(q_markers):
                num_str = qm.group(1)
                start = a_markers[i].end()
                end = a_markers[i+1].start() if i+1 < len(a_markers) else len(ref_text)
                content = ref_text[start:end].strip()
                num = cn_to_int(num_str)
                if num is not None and content:
                    sections.append((num, content))
            if sections:
                return sections
    
    # --- 策略7: 兜底 - 按位置映射（对于没有编号的 【参考答案】 序列）---
    if not headers:
        p7 = re.compile(
            r'(?:^|\n)(?:#{1,4}\s*)?(?:【)?参考答案(?:】)?[：:]?$'
            , re.MULTILINE
        )
        all_markers = list(p7.finditer(ref_text))
        if len(all_markers) >= 2:
            sections = []
            for i, m in enumerate(all_markers):
                start = m.end()
                end = all_markers[i+1].start() if i+1 < len(all_markers) else len(ref_text)
                content = ref_text[start:end].strip()
                if content:
                    sections.append((i + 1, content))
            if sections:
                return sections
    
    if not headers:
        return []
    
    return _build_sections_from_match(headers, ref_text)

def _build_sections_from_match(headers, ref_text):
    """从 regex match 对象构建 sections"""
    sections = []
    for i, m in enumerate(headers):
        label = m.group(1)
        start = m.end()
        end = headers[i+1].start() if i+1 < len(headers) else len(ref_text)
        content = ref_text[start:end].strip()
        
        num = cn_to_int(label.replace('\uff08','').replace('\uff09',''))
        if num is not None and content:
            sections.append((num, content))
    return sections

def _build_sections_p3(headers, ref_text):
    """策略3专用: 处理答案N/第N题格式的match groups"""
    sections = []
    for i, m in enumerate(headers):
        num_str = m.group(1) or m.group(2)
        start = m.end()
        end = headers[i+1].start() if i+1 < len(headers) else len(ref_text)
        content = ref_text[start:end].strip()
        num = cn_to_int(num_str)
        if num is not None and content:
            sections.append((num, content))
    return sections

# ====== 主逻辑 ======
def main():
    # 备份已做，直接打开
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    
    # 获取所有有参考答案的题
    c.execute("SELECT id, title, reference_answer FROM questions WHERE reference_answer IS NOT NULL AND reference_answer != ''")
    all_questions = c.fetchall()
    
    # 按 reference_answer 分组（同一套卷子的题共享同一个 ref）
    groups = {}
    for q in all_questions:
        ref = q['reference_answer']
        if ref not in groups:
            groups[ref] = []
        groups[ref].append(q)
    
    stats = {
        'total_questions': len(all_questions),
        'total_groups': len(groups),
        'matched': 0,
        'no_section_found': 0,
        'no_title_number': 0,
        'title_mismatch': 0,
        'empty_answer': 0,
    }
    
    updates = []  # (question_id, new_reference_answer)
    problems = []
    
    for ref_text, questions in groups.items():
        sections = parse_sections(ref_text)
        
        if not sections:
            # 无法解析，保留原值
            for q in questions:
                stats['no_section_found'] += 1
                problems.append({
                    'id': q['id'][:15],
                    'issue': 'cannot_parse',
                    'ref_head': ref_text[:150]
                })
            continue
        
        # 按题号匹配
        for q in questions:
            qnum = extract_qnum(q['title'])
            
            if qnum is None:
                stats['no_title_number'] += 1
                problems.append({
                    'id': q['id'][:15],
                    'title': q['title'],
                    'issue': 'no_title_number'
                })
                continue
            
            # 找到编号匹配的答案节
            matching = [s for s in sections if s[0] == qnum]
            
            if matching:
                # 取第一个匹配（如果有多个变体答案，取第一个）
                new_answer = matching[0][1]
                if new_answer:
                    updates.append((q['id'], new_answer))
                    stats['matched'] += 1
                else:
                    stats['empty_answer'] += 1
                    problems.append({
                        'id': q['id'][:15],
                        'title': q['title'],
                        'issue': 'empty_section_content'
                    })
            else:
                stats['title_mismatch'] += 1
                problems.append({
                    'id': q['id'][:15],
                    'title': q['title'],
                    'qnum': qnum,
                    'available_sections': [s[0] for s in sections],
                    'issue': 'title_mismatch'
                })
    
    # 执行更新
    print(f'=== 拆分统计 ===')
    print(f'总题数: {stats["total_questions"]}')
    print(f'试卷组数: {stats["total_groups"]}')
    print(f'成功匹配: {stats["matched"]} ({100*stats["matched"]/stats["total_questions"]:.1f}%)')
    print(f'无法解析: {stats["no_section_found"]}')
    print(f'无题号: {stats["no_title_number"]}')
    print(f'题号不匹配: {stats["title_mismatch"]}')
    print(f'答案节为空: {stats["empty_answer"]}')
    
    if updates:
        print(f'\n准备更新 {len(updates)} 条记录...')
        
        # 批量更新
        c.executemany(
            'UPDATE questions SET reference_answer = ? WHERE id = ?',
            [(ans, qid) for qid, ans in updates]
        )
        conn.commit()
        print('更新完成！')
    else:
        print('\n没有需要更新的记录')
    
    # 输出问题详情
    if problems:
        print(f'\n=== 问题详情 ({len(problems)} 条) ===')
        by_issue = {}
        for p in problems:
            issue = p['issue']
            if issue not in by_issue:
                by_issue[issue] = []
            by_issue[issue].append(p)
        
        for issue, items in by_issue.items():
            print(f'\n{issue} ({len(items)} 条):')
            for p in items[:5]:
                print(f'  id={p.get("id","")} title={p.get("title","")} qnum={p.get("qnum","")} sections={p.get("available_sections","")}')
            if len(items) > 5:
                print(f'  ... 还有 {len(items)-5} 条')
    
    # 验证：检查更新后的答案长度分布
    print(f'\n=== 更新后答案长度分布 ===')
    c.execute("SELECT LENGTH(reference_answer) as len FROM questions WHERE reference_answer != ''")
    lengths = [r[0] for r in c.fetchall()]
    if lengths:
        print(f'  最小: {min(lengths)} 字符')
        print(f'  最大: {max(lengths)} 字符')
        print(f'  平均: {sum(lengths)/len(lengths):.0f} 字符')
        # 分布
        buckets = {'<100': 0, '100-500': 0, '500-1000': 0, '1000-3000': 0, '>3000': 0}
        for l in lengths:
            if l < 100: buckets['<100'] += 1
            elif l < 500: buckets['100-500'] += 1
            elif l < 1000: buckets['500-1000'] += 1
            elif l < 3000: buckets['1000-3000'] += 1
            else: buckets['>3000'] += 1
        for k, v in buckets.items():
            print(f'  {k}: {v} ({100*v/len(lengths):.0f}%)')
    
    # 检查空值
    c.execute("SELECT COUNT(*) FROM questions WHERE reference_answer IS NULL OR reference_answer = ''")
    empty = c.fetchone()[0]
    print(f'\n空答案: {empty} / {stats["total_questions"]}')
    
    conn.close()
    print('\n完成！')

if __name__ == '__main__':
    main()
