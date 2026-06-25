import sqlite3, re, json, hashlib, uuid
from datetime import datetime

DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'

db = sqlite3.connect(DB_PATH)
db.row_factory = sqlite3.Row

# Load FlowUs data for reference answers
with open('extracted_guokao_data.json', 'r', encoding='utf-8') as f:
    gk_data = json.load(f)

# Map paper_questions paper_title -> FlowUs key
def match_flowus(title):
    for k in gk_data:
        # e.g. "2023国考申论（副省级卷）" -> match FlowUs key with 2023 and 副省级
        m = re.search(r'(\d{4})', title)
        if not m: continue
        year = m.group(1)
        if year in k:
            if '副省级' in title and '副省级' in k: return k
            if '地市级' in title and '地市级' in k: return k
            if '行政执法' in title and '行政执法' in k: return k
    return None

# Detect detailed question type (matches existing questions table subtypes)
def detect_detailed_type(q_text):
    # 大作文 first (strongest signal)
    if re.search(r'(?:写一篇议论|写一篇文章|自拟题目.*文章|议论文|议论性文章|自选角度.*写一篇)', q_text):
        if not re.search(r'(?:发言提纲|发言稿|简报|短评|评论|提纲|拟写|起草)', q_text):
            return '文章论述（大作文）'
    
    # 应用文 subtypes - match specific task descriptions
    if re.search(r'(?:宣传材料|宣传稿)', q_text): return '应用文（宣传材料）'
    if re.search(r'短评', q_text): return '应用文（短评）'
    if re.search(r'(?:讲话稿|发言稿)', q_text): return '应用文（讲话稿）'
    if re.search(r'(?:推荐材料|推荐书)', q_text): return '应用文（推荐材料）'
    if re.search(r'(?:公开信)', q_text): return '应用文（公开信）'
    if re.search(r'(?:讲解稿|解说词)', q_text): return '应用文（讲解稿）'
    if re.search(r'(?:条例)', q_text): return '应用文（条例）'
    if re.search(r'(?:提纲|提要)', q_text): return '应用文（提纲）'
    if re.search(r'(?:要点)', q_text): return '应用文（要点）'
    
    # Generic 应用文 patterns
    if re.search(r'(?:拟写|起草|撰写|编者按|汇报提纲|建议书|倡议书|工作方案|调研报告|申报材料|工作简报|约稿|发言提纲|总结发言)', q_text):
        return '应用文'
    
    # 概括归纳
    if re.search(r'(?:概括|归纳|梳理|总结|有哪些|主要做法|主要举措|措施和成效)', q_text):
        return '概括归纳'
    
    # 综合分析
    if re.search(r'(?:分析|理解|谈谈|说明|解释|原因|为什么|怎么理解|如何理解)', q_text):
        return '综合分析'
    
    # 提出对策
    if re.search(r'(?:对策|建议|措施|提出|解决|如何|怎样)', q_text):
        return '提出对策'
    
    return '概括归纳'

def extract_score_hint(q_text):
    m = re.search(r'（(\d+)分）', q_text)
    if m: return m.group(1) + '分'
    return ''

def extract_word_limit(q_text):
    m = re.search(r'不超过(\d+)字', q_text)
    if m: return int(m.group(1))
    m = re.search(r'字数(\d+)[-–](\d+)字', q_text)
    if m: return int(m.group(2))
    m = re.search(r'字数(\d+)字左右', q_text)
    if m: return int(m.group(1))
    return 0

# Get existing questions for dedup
existing_hashes = set()
for row in db.execute('SELECT content_hash FROM questions WHERE is_deleted=0').fetchall():
    if row[0]:
        existing_hashes.add(row[0])

# Get 9 国考 papers
papers = db.execute('''
    SELECT paper_title, year, exam_subtype 
    FROM paper_questions 
    WHERE exam_type='国考' AND is_deleted=0 AND year < 2026
    GROUP BY paper_id 
    ORDER BY year, exam_subtype
''').fetchall()

imported = 0
skipped = 0

for paper in papers:
    title = paper['paper_title']
    year = paper['year']
    subtype = paper['exam_subtype']
    
    # Get questions from paper_questions
    qs = db.execute('''
        SELECT question_index, question_type, content, reference_answer 
        FROM paper_questions 
        WHERE paper_title=? AND is_deleted=0 
        ORDER BY question_index
    ''', (title,)).fetchall()
    
    # Get FlowUs answers
    fk = match_flowus(title)
    flowus_answers = {}
    if fk and fk in gk_data:
        for ans in gk_data[fk].get('answers', []):
            org = ans.get('organization', '')
            text = ans.get('text', '')
            if text and len(text) > 20:
                if org not in flowus_answers:
                    flowus_answers[org] = []
                flowus_answers[org].append(text)
    
    print('\n=== %s (%d questions) ===' % (title, len(qs)))
    
    # Create a parent_id for this paper's questions
    parent_id = str(uuid.uuid4())[:12]
    
    for q in qs:
        q_idx = q['question_index']
        content = q['content']
        
        # Build new content: simple marker replacement 【材料N】→【给定资料N】
        new_content = re.sub(r'【材料(\d+)】', r'【给定资料\1】', content)
        
        # Content hash for dedup
        content_hash = hashlib.md5(new_content.encode()).hexdigest()
        
        if content_hash in existing_hashes:
            print('  Q%d: SKIP (duplicate)' % q_idx)
            skipped += 1
            continue
        
        existing_hashes.add(content_hash)
        
        # Extract question text for type detection (find "问题N：" pattern)
        q_match = re.search(r'问题\d+[：:].*', new_content, re.DOTALL)
        q_for_type = q_match.group(0) if q_match else new_content
        
        q_type = detect_detailed_type(q_for_type)
        score = extract_score_hint(q_for_type)
        word_limit = extract_word_limit(q_for_type)
        
        # Build reference answer
        ref_parts = []
        # First try existing answer from paper_questions
        existing_ans = q['reference_answer'] or ''
        if existing_ans and len(existing_ans) > 20:
            ref_parts.append(existing_ans)
        
        # Then add FlowUs answers
        for org, texts in flowus_answers.items():
            # Try to match to question index (use modulo for multi-question answers)
            if len(texts) >= q_idx:
                ans_text = texts[q_idx - 1]
                if ans_text and len(ans_text) > 20:
                    ref_parts.append('【%s】\n%s' % (org, ans_text.strip()))
        
        ref_answer = '\n\n'.join(ref_parts) if ref_parts else ''
        
        db.execute('''
            INSERT INTO questions (id, type, source_type, exam_category, region, 
                applicable_regions, year, exam_type, exam_subtype, question_type,
                title, content, content_hash, reference_answer, parent_id,
                word_limit, score_hint, is_deleted, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            str(uuid.uuid4())[:12], 'exam', 'imported', '公务员', '国家',
            '["国家"]', year, '国考', subtype, q_type,
            '第%d题' % q_idx, new_content, content_hash, ref_answer, parent_id,
            word_limit, score, 0, datetime.now().isoformat(), datetime.now().isoformat()
        ))
        
        print('  Q%d (%s): len=%d score=%s word=%d' % (q_idx, q_type, len(new_content), score, word_limit))
        imported += 1

db.commit()

total = db.execute('SELECT COUNT(*) FROM questions WHERE is_deleted=0').fetchone()[0]
print('\n=== DONE ===')
print('Imported: %d, Skipped: %d, Total questions: %d' % (imported, skipped, total))
db.close()
