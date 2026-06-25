import json, sqlite3, re, shutil, uuid
from datetime import datetime

DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'

shutil.copy2(DB_PATH, DB_PATH + f'.bak_flowus_{datetime.now().strftime("%Y%m%d_%H%M%S")}')

with open('extracted_exam_data.json', 'r', encoding='utf-8') as f:
    all_data = json.load(f)

db = sqlite3.connect(DB_PATH)
db.row_factory = sqlite3.Row

# Map JSON keys to DB paper_titles
KEY_TO_DB = {
    '2025河南市级卷': '2025年公务员多省联考《申论》题（河南市级卷）',
    '2025天津市级卷': '2025年公务员多省联考《申论》题（天津市级卷）',
    '2024河南市级卷': '2024年公务员多省联考《申论》题（河南市级卷）',
    '2023河南市级卷': '2023年公务员多省联考《申论》题（河南市级卷）',
    '2024北京': '2024年北京市公考《申论》题',
    '2023北京': '2023年北京市公考《申论》题',
    '2024山西省市卷': '2024年公务员多省联考《申论》题（山西省市卷）',
    '2024江西省市卷': '2024年公务员多省联考《申论》题（江西省市卷）',
    '2021新疆县级卷': '2021年新疆下半年公考《申论》题（县级卷）',
    '2025安徽选调（A卷）': '2025年公务员多省联考《申论》题（安徽A、普通选调卷）',
}

def clean_question_text(q_text):
    """Extract just the question requirements, strip answer text"""
    # Question typically starts with "问题N：" or "问题N:"
    # Answers start after the requirements line (e.g., "不超过300字。")
    # Find where requirements end - look for patterns like "不超过XXX字" or "XX分" at end
    
    # Try to find the boundary: requirement line ending
    req_end = None
    for pat in [r'不超过\d+字[。．.]?', r'字数\d+[-–]\d+字[。．.]?', r'字数\d+字左右[。．.]?',
                r'\d+[-–]\d+字[。．.]?', r'篇幅不超过\d+字[。．.]?', r'总字数\d+[-–]\d+字[。．.]?']:
        m = re.search(pat, q_text)
        if m:
            req_end = m.end()
            break
    
    if req_end is None:
        # Try to find where answers start: numbered list after requirements
        m = re.search(r'(?:。|；)\s*\n\s*(?:\d+[.、]|【)', q_text)
        if m:
            req_end = m.start() + 1
    
    if req_end and req_end < len(q_text):
        question_part = q_text[:req_end].strip()
        answer_part = q_text[req_end:].strip()
        return question_part, answer_part
    
    return q_text, ''

def detect_type(q_text):
    """Detect question type from text"""
    # 大作文
    if re.search(r'(?:写一篇议论|写一篇文章|自拟题目|自选角度.*文章|议论文|议论性文章)', q_text):
        if not re.search(r'(?:发言提纲|发言稿|讲话稿|简报|短评|公开信|倡议书|建议书|提纲)', q_text):
            return '文章论述（大作文）'
    
    # 应用文
    if re.search(r'(?:发言提纲|发言稿|讲话稿|简报|短评|公开信|倡议书|建议书|报告提纲|调研报告|工作方案|宣传稿|推荐材料|汇报提纲|申报材料|工作简报|约稿|发言提纲|总结发言|拟写|起草|撰写)', q_text):
        return '应用文写作'
    
    # 概括归纳
    if re.search(r'(?:概括|归纳|梳理|总结)', q_text):
        return '概括归纳'
    
    # 综合分析
    if re.search(r'(?:分析|理解|谈谈|说明|解释|原因)', q_text):
        return '综合分析'
    
    # 对策建议
    if re.search(r'(?:对策|建议|措施|提出|解决|问题.*建议)', q_text):
        return '对策建议'
    
    return '概括归纳'

def parse_refs(q_text, q_type):
    """Parse material references"""
    if q_type == '文章论述（大作文）':
        return None  # ALL
    
    refs = set()
    for m in re.finditer(r'[材料资料](\d+)', q_text):
        refs.add(int(m.group(1)))
    
    if not refs:
        return None  # No specific ref → ALL
    
    return refs

for key, db_title in KEY_TO_DB.items():
    if key not in all_data:
        print(f"SKIP: {key} not in JSON")
        continue
    
    entry = all_data[key]
    paper = db.execute('SELECT paper_id, year, region, exam_type, exam_subtype, exam_category FROM paper_questions WHERE paper_title=? LIMIT 1', (db_title,)).fetchone()
    if not paper:
        print(f"SKIP: '{db_title}' not in DB")
        continue
    
    paper_id = paper['paper_id']
    materials_list = entry.get('materials', [])
    questions_list = entry.get('questions', [])
    
    # Build materials dict
    materials = {}
    for m in materials_list:
        header = m.get('header', '')
        content = m.get('content', '')
        if content and len(content) > 50:
            materials[header] = content
    
    print(f"\n{'='*80}")
    print(f"FIXING: {db_title}")
    print(f"  Materials: {list(materials.keys())}")
    print(f"  Questions: {len(questions_list)}")
    
    # Delete existing
    db.execute('DELETE FROM paper_questions WHERE paper_id=?', (paper_id,))
    
    real_q_idx = 0
    for i, q in enumerate(questions_list):
        q_text = q.get('content', '')
        
        # Skip empty placeholder questions
        if not q_text or len(q_text.strip()) < 10:
            print(f"  SKIP Q{i+1}: empty")
            continue
        
        real_q_idx += 1
        q_idx = real_q_idx
        
        # Clean question
        clean_q, answer_part = clean_question_text(q_text)
        q_type = detect_type(clean_q)
        refs = parse_refs(clean_q, q_type)
        
        # Build content
        parts = []
        if refs is None:
            for mk in sorted(materials.keys()):
                parts.append(f'【{mk}】\n{materials[mk]}')
        else:
            for num in sorted(refs):
                mk = f'材料{num}'
                if mk in materials:
                    parts.append(f'【{mk}】\n{materials[mk]}')
                elif str(num) in materials:
                    parts.append(f'【材料{num}】\n{materials[str(num)]}')
                else:
                    # Try fuzzy match
                    for mat_k in materials:
                        if str(num) in mat_k or mat_k.endswith(str(num)):
                            parts.append(f'【{mat_k}】\n{materials[mat_k]}')
                            break
                    else:
                        print(f"    WARNING: material {num} not found")
        
        parts.append(clean_q)
        content = '\n\n'.join(parts)
        
        if len(content) < 100:
            print(f"  Q{q_idx}: SHORT ({len(content)} chars), skipping")
            continue
        
        # Reference answer
        ref_answer = answer_part[:5000] if answer_part and len(answer_part) > 20 else ''
        
        db.execute('''
            INSERT INTO paper_questions (id, paper_id, paper_title, question_index, question_type,
                title, content, reference_answer, year, region, exam_type, exam_subtype,
                exam_category, word_limit, score_hint)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            str(uuid.uuid4())[:12], paper_id, db_title, q_idx, q_type,
            f'第{q_idx}题', content, ref_answer,
            paper['year'], paper['region'], paper['exam_type'], paper['exam_subtype'],
            paper['exam_category'], 0, 0
        ))
        
        dz_flag = ' [大作文→ALL]' if refs is None else ''
        mat_used = re.findall(r'【(材料\d+)】', content)
        print(f"  Q{q_idx} ({q_type}){dz_flag}: mats={mat_used}, len={len(content)}")

db.commit()

# Verify
print(f"\n{'='*80}")
print("VERIFY:")
short = db.execute('SELECT paper_title, question_index, length(content) as clen FROM paper_questions WHERE length(content) < 300').fetchall()
for s in short:
    print(f"  SHORT: {s['paper_title'][:50]} Q{s['question_index']} len={s['clen']}")

total_q = db.execute('SELECT COUNT(*) FROM paper_questions').fetchone()[0]
total_p = db.execute('SELECT COUNT(DISTINCT paper_id) FROM paper_questions').fetchone()[0]
print(f"\nTotal: {total_q} questions, {total_p} papers")

db.close()
print("Done.")
