import json, sqlite3, re, shutil, uuid
from datetime import datetime

DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'

shutil.copy2(DB_PATH, DB_PATH + f'.bak_gk_{datetime.now().strftime("%Y%m%d_%H%M%S")}')

with open('extracted_guokao_data.json', 'r', encoding='utf-8') as f:
    all_data = json.load(f)

db = sqlite3.connect(DB_PATH)

# Map FlowUs titles to DB metadata
def get_meta(title):
    m = re.search(r'(\d{4})', title)
    year = int(m.group(1)) if m else 2023
    subtype_map = {
        '副省级': '副省级卷', '地市级': '地市级卷', '行政执法': '行政执法卷'
    }
    subtype = ''
    for k, v in subtype_map.items():
        if k in title:
            subtype = v
            break
    return year, '国家', '国考', subtype, ''

def detect_type(q_text):
    if re.search(r'(?:写一篇议论|写一篇文章|自拟题目|议论文|议论性文章|自选角度.*文章)', q_text):
        if not re.search(r'(?:发言提纲|发言稿|简报|短评|评论|提纲)', q_text):
            return '文章论述（大作文）'
    if re.search(r'(?:发言提纲|发言稿|讲话稿|简报|短评|公开信|倡议书|建议书|报告提纲|调研报告|工作方案|宣传稿|推荐材料|汇报提纲|申报材料|工作简报|约稿|总结发言|拟写|起草|撰写|评论|编者按)', q_text):
        return '应用文写作'
    if re.search(r'(?:概括|归纳|梳理|总结|有哪些|主要做法|主要举措)', q_text):
        return '概括归纳'
    if re.search(r'(?:分析|理解|谈谈|说明|解释|原因|为什么|怎么理解)', q_text):
        return '综合分析'
    if re.search(r'(?:对策|建议|措施|提出|解决|如何|怎样)', q_text):
        return '对策建议'
    return '概括归纳'

def parse_refs(q_text, q_type, num_materials):
    if q_type == '文章论述（大作文）':
        return None
    refs = set()
    for m in re.finditer(r'[材料资料](\d+)', q_text):
        refs.add(int(m.group(1)))
    for m in re.finditer(r'[材料资料](\d+)[-–](\d+)', q_text):
        for x in range(int(m.group(1)), int(m.group(2))+1):
            refs.add(x)
    if not refs:
        if num_materials <= 3:
            return None
        else:
            return {1}
    return refs

imported = 0
for title, entry in all_data.items():
    year, region, exam_type, exam_subtype, exam_category = get_meta(title)
    db_title = f'{year}国考申论（{exam_subtype}）'
    
    # Check if exists
    existing = db.execute('SELECT paper_id FROM paper_questions WHERE paper_title LIKE ? AND is_deleted=0 LIMIT 1', (f'%{year}%{exam_subtype}%',)).fetchone()
    if existing:
        db.execute('DELETE FROM paper_questions WHERE paper_id=?', (existing[0],))
        paper_id = existing[0]
    else:
        paper_id = str(uuid.uuid4())[:12]
    
    materials = entry.get('materials', {})
    questions = entry.get('questions', [])
    answers = entry.get('answers', [])
    
    # Build reference answer
    ref_parts = []
    for ans in answers:
        org = ans.get('organization', '')
        text = ans.get('text', '')
        if text and len(text) > 20:
            ref_parts.append(f'【{org}】\n{text.strip()}')
    ref_answer = '\n\n'.join(ref_parts) if ref_parts else ''
    
    print(f"\n{'='*80}")
    print(f"IMPORTING: {db_title}")
    print(f"  Materials: {list(materials.keys())}")
    print(f"  Questions: {len(questions)}")
    print(f"  Answers: {len(answers)}")
    
    count = 0
    for q_idx, q_text in enumerate(questions):
        q_num = q_idx + 1
        if not q_text or len(q_text.strip()) < 10:
            continue
        
        q_type = detect_type(q_text)
        refs = parse_refs(q_text, q_type, len(materials))
        
        # Build content
        parts = []
        if refs is None:
            for mk in sorted(materials.keys(), key=lambda x: int(re.search(r'\d+', x).group()) if re.search(r'\d+', x) else 0):
                parts.append(f'【{mk}】\n{materials[mk]}')
        elif refs:
            for num in sorted(refs):
                found = False
                for mk in materials:
                    m = re.search(r'(\d+)', mk)
                    if m and int(m.group(1)) == num:
                        parts.append(f'【材料{num}】\n{materials[mk]}')
                        found = True
                        break
                if not found:
                    print(f"    WARNING: material {num} not found")
        
        parts.append(q_text.strip())
        content = '\n\n'.join(parts)
        
        if len(content) < 100:
            print(f"  Q{q_num}: SHORT ({len(content)}), skipping")
            continue
        
        db.execute('''
            INSERT INTO paper_questions (id, paper_id, paper_title, question_index, question_type,
                title, content, reference_answer, year, region, exam_type, exam_subtype,
                exam_category, word_limit, score_hint, is_deleted)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            str(uuid.uuid4())[:12], paper_id, db_title, q_num, q_type,
            f'第{q_num}题', content, ref_answer[:10000],
            year, region, exam_type, exam_subtype,
            exam_category, 0, 0, 0
        ))
        
        dz_flag = ' [大作文→ALL]' if refs is None else ''
        mat_used = re.findall(r'【材料(\d+)】', content)
        print(f"  Q{q_num} ({q_type}){dz_flag}: mats={mat_used[:4]}, len={len(content)}")
        count += 1
    
    imported += 1

db.commit()

total_gk = db.execute("SELECT COUNT(DISTINCT paper_id) FROM paper_questions WHERE exam_type='国考' AND is_deleted=0").fetchone()[0]
total_q = db.execute('SELECT COUNT(*) FROM paper_questions WHERE is_deleted=0').fetchone()[0]
total_p = db.execute('SELECT COUNT(DISTINCT paper_id) FROM paper_questions WHERE is_deleted=0').fetchone()[0]
print(f"\n{'='*80}")
print(f"Total: {total_q} questions, {total_p} papers, {total_gk} 国考 papers")
db.close()
print("Done.")
