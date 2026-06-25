import json, sqlite3, re, shutil, uuid
from datetime import datetime

DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'

shutil.copy2(DB_PATH, DB_PATH + f'.bak_xdflowus_{datetime.now().strftime("%Y%m%d_%H%M%S")}')

with open('extracted_xuandiao_data.json', 'r', encoding='utf-8') as f:
    all_data = json.load(f)

db = sqlite3.connect(DB_PATH)

def reconstruct_questions(questions_list, answers_list):
    """Reconstruct full question texts from out-of-order FlowUs fragments.
    Returns list of (question_text, reference_answer) tuples, ordered by question number."""
    
    # Step 1: Group fragments by question number
    # Fragments like: '第一题', '问题1：...', '要求：...', '第二题', etc.
    q_groups = {}  # {1: [fragments], 2: [fragments], ...}
    current_num = None
    
    for frag in questions_list:
        if not frag or frag == '题本下载：':
            continue
        
        # Check for 第N题 or 问题N markers
        m1 = re.search(r'第([一二三四五六七八九十\d]+)题', frag)
        m2 = re.search(r'问题(\d+)[：:]', frag)
        
        if m2:
            current_num = int(m2.group(1))
        elif m1:
            cn = m1.group(1)
            cn_map = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9,'十':10}
            current_num = cn_map.get(cn) if not cn.isdigit() else int(cn)
        
        if current_num is not None:
            if current_num not in q_groups:
                q_groups[current_num] = []
            q_groups[current_num].append(frag)
    
    # Step 2: Build full question text for each number
    questions = []
    for num in sorted(q_groups.keys()):
        fragments = q_groups[num]
        # Join fragments, remove redundant headers
        cleaned = []
        for f in fragments:
            # Skip standalone 第N题 headers if we already have content
            if re.match(r'第[一二三四五六七八九十\d]+题$', f.strip()):
                if any(not re.match(r'第[一二三四五六七八九十\d]+题$', x.strip()) for x in fragments):
                    continue
            cleaned.append(f)
        
        full_q = '\n'.join(cleaned).strip()
        
        # Ensure it starts with 问题N：
        if not re.match(r'问题\d+[：:]', full_q):
            full_q = f'问题{num}：' + full_q
        
        if len(full_q) > 10:
            questions.append(full_q)
    
    # Step 3: Build reference answers
    ref_parts = []
    for ans in answers_list:
        org = ans.get('organization', '')
        text = ans.get('text', '')
        if text and len(text) > 20:
            ref_parts.append(f'【{org}】\n{text.strip()}')
    
    ref_answer = '\n\n'.join(ref_parts) if ref_parts else ''
    
    return questions, ref_answer

def detect_type(q_text):
    if re.search(r'(?:写一篇议论|写一篇文章|自拟题目|议论文|议论性文章)', q_text):
        if not re.search(r'(?:发言提纲|发言稿|简报|短评|评论|提纲|拟写|起草)', q_text):
            return '文章论述（大作文）'
    if re.search(r'(?:发言提纲|发言稿|讲话稿|简报|短评|公开信|倡议书|建议书|报告提纲|调研报告|工作方案|宣传稿|推荐材料|汇报提纲|申报材料|工作简报|约稿|总结发言|拟写|起草|撰写|评论)', q_text):
        # 评论/短评 is 应用文
        if re.search(r'(?:撰写一篇评论|写一则短评|为.*撰写|拟写)', q_text):
            return '应用文写作'
    if re.search(r'(?:概括|归纳|梳理|总结)', q_text):
        return '概括归纳'
    if re.search(r'(?:分析|理解|谈谈|说明|解释|原因)', q_text):
        return '综合分析'
    if re.search(r'(?:对策|建议|措施|提出|解决)', q_text):
        return '对策建议'
    return '概括归纳'

def parse_refs(q_text, q_type, num_materials):
    if q_type == '文章论述（大作文）':
        return None  # ALL materials
    refs = set()
    for m in re.finditer(r'[材料资料](\d+)', q_text):
        refs.add(int(m.group(1)))
    for m in re.finditer(r'[材料资料](\d+)[-–](\d+)', q_text):
        for x in range(int(m.group(1)), int(m.group(2))+1):
            refs.add(x)
    if not refs:
        # No specific ref: for small papers (<=3 materials) use ALL, else default to material 1
        if num_materials <= 3:
            return None
        else:
            return {1}
    return refs

# Map JSON keys to DB metadata
PAPER_META = {
    '2020年浙江省选调生考试《申论》题': (2020, '浙江', '省考', '', '选调生'),
    '2020年重庆市选调生考试《申论》题': (2020, '重庆', '省考', '', '选调生'),
    '2022年湖北省选调生考试《申论》题': (2022, '湖北', '省考', '', '选调生'),
    '2022年山东省选调生考试《申论》题': (2022, '山东', '省考', '', '选调生'),
    '2023年安徽省定向选调生考试《申论》题': (2023, '安徽', '省考', '', '选调生'),
    '2023年浙江省选调生考试《申论》题': (2023, '浙江', '省考', '', '选调生'),
    '2024江西选调生申论考试': (2024, '江西', '省考', '', '选调生'),
    '2024重庆定向选调生申论考试': (2024, '重庆', '省考', '', '选调生'),
    '2025北京定向选调生申论考试': (2025, '北京', '省考', '', '选调生'),
    '2025河南定向选调申论考试': (2025, '河南', '省考', '', '选调生'),
    '2025湖北选调生申论考试': (2025, '湖北', '省考', '', '选调生'),
    '2025重庆定向选调生申论考试': (2025, '重庆', '省考', '', '选调生'),
    '2026河南定向选调生申论考试': (2026, '河南', '省考', '', '选调生'),
}

imported = 0
for paper_title, entry in all_data.items():
    if paper_title not in PAPER_META:
        print(f"SKIP: no metadata for '{paper_title}'")
        continue
    
    year, region, exam_type, exam_subtype, exam_category = PAPER_META[paper_title]
    
    # Check if already in DB
    existing = db.execute('SELECT paper_id FROM paper_questions WHERE paper_title=? AND is_deleted=0 LIMIT 1', (paper_title,)).fetchone()
    if existing:
        # Update existing paper - delete and re-insert
        db.execute('DELETE FROM paper_questions WHERE paper_id=?', (existing[0],))
        paper_id = existing[0]
    else:
        paper_id = str(uuid.uuid4())[:12]
    
    materials = entry.get('materials', {})
    questions_list = entry.get('questions', [])
    answers_list = entry.get('answers', [])
    
    # Reconstruct questions
    recon_qs, ref_answer_all = reconstruct_questions(questions_list, answers_list)
    
    print(f"\n{'='*80}")
    print(f"IMPORTING: {paper_title}")
    print(f"  Materials: {list(materials.keys())}")
    print(f"  Questions: {len(recon_qs)}")
    print(f"  Answers: {len(answers_list)}")
    
    count = 0
    for q_idx, q_text in enumerate(recon_qs):
        q_num = q_idx + 1
        q_type = detect_type(q_text)
        refs = parse_refs(q_text, q_type, len(materials))
        
        # Build content
        parts = []
        if refs is None:
            for mk in sorted(materials.keys(), key=lambda x: int(re.search(r'\d+', x).group())):
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
        
        parts.append(q_text)
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
            str(uuid.uuid4())[:12], paper_id, paper_title, q_num, q_type,
            f'第{q_num}题', content, ref_answer_all[:8000],
            year, region, exam_type, exam_subtype,
            exam_category, 0, 0, 0
        ))
        
        dz_flag = ' [大作文→ALL]' if refs is None else ''
        mat_used = re.findall(r'【材料(\d+)】', content)
        print(f"  Q{q_num} ({q_type}){dz_flag}: mats={mat_used[:4]}, len={len(content)}")
        count += 1
    
    imported += 1

db.commit()

# Stats
total_xd = db.execute("SELECT COUNT(DISTINCT paper_id) FROM paper_questions WHERE exam_category='选调生' AND is_deleted=0").fetchone()[0]
total_q = db.execute('SELECT COUNT(*) FROM paper_questions WHERE is_deleted=0').fetchone()[0]
total_p = db.execute('SELECT COUNT(DISTINCT paper_id) FROM paper_questions WHERE is_deleted=0').fetchone()[0]
print(f"\n{'='*80}")
print(f"Total: {total_q} questions, {total_p} papers, {total_xd} 选调生 papers")
db.close()
print("Done.")
