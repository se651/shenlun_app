# 从 申论文档/js/ 导入 JSON 题库 → paper_questions 表（套卷专用）
import sqlite3, json, os, re, shutil, uuid
from datetime import datetime

DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'
JS_DIR = os.path.join(os.environ['USERPROFILE'], 'Desktop', '申论文档', 'js')

# ====== 文件名解析 ======
def parse_filename(fname):
    name = fname.replace('.json', '')
    result = {'year': None, 'region': '', 'exam_type': '', 'exam_subtype': '', 'exam_category': ''}
    
    ym = re.search(r'(\d{4})年?', name)
    if ym: result['year'] = int(ym.group(1))
    
    regions = ['黑龙江','内蒙古','北京','上海','天津','重庆','河北','山西','辽宁','吉林',
               '江苏','浙江','安徽','福建','江西','山东','河南','湖北','湖南',
               '广东','广西','海南','四川','贵州','云南','西藏','陕西','甘肃',
               '青海','宁夏','新疆','深圳']
    for r in sorted(regions, key=len, reverse=True):
        if r in name: result['region'] = r; break
    
    if '国考' in name or '国家' in name:
        result['exam_type'] = '国考'; result['region'] = '国家'
    
    if '选调生' in name or '定向选调' in name or '选调' in name:
        result['exam_category'] = '选调生'
    
    subtypes = ['副省级','地市级','行政执法','省市卷','县乡卷','乡镇卷','县级卷',
                'A卷','B卷','C卷','甲卷','乙卷','丙卷','一卷','二卷','三卷',
                '县乡','省市','乡镇','县级','州市卷','市区卷','街镇卷',
                '盟市卷','旗县卷','通用卷','县镇','省直卷','州县卷']
    for st in sorted(subtypes, key=len, reverse=True):
        if st in name:
            norm = st
            if not norm.endswith('卷'): norm += '卷'
            norm = norm.replace('甲卷','A卷').replace('乙卷','B卷').replace('丙卷','C卷')
            result['exam_subtype'] = norm; break
    
    if not result['exam_type'] and result['region'] and result['region'] != '国家':
        result['exam_type'] = '省考'
    if '深圳' in name: result['exam_type'] = '市考'
    
    return result

# ====== 答案分离 ======
ANSWER_MARKERS = ['某笔', '某图', '中公', '粉笔', '站长', '袁东', '千寻']
def clean_question_text(q_text):
    cut_pos = len(q_text)
    for marker in ANSWER_MARKERS:
        pos = q_text.find(marker)
        if 0 < pos < cut_pos:
            line_start = q_text.rfind('\n', 0, pos)
            cut_pos = line_start if line_start >= 0 else pos
    if cut_pos < len(q_text):
        return q_text[:cut_pos].strip(), q_text[cut_pos:].strip()
    return q_text, ''

def clean_material(text):
    """Remove separator lines and paper title tags from material text"""
    text = re.sub(r'-{20,}.*?(?:\n|$)', '', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()

# ====== 主导入 ======
def main():
    shutil.copy2(DB_PATH, DB_PATH + f'.bak_paper_{datetime.now().strftime("%Y%m%d_%H%M%S")}')
    db = sqlite3.connect(DB_PATH)
    
    # Create paper_questions table
    db.execute('DROP TABLE IF EXISTS paper_questions')
    db.execute('''
        CREATE TABLE paper_questions (
            id TEXT PRIMARY KEY,
            paper_id TEXT NOT NULL,
            paper_title TEXT NOT NULL,
            question_index INTEGER,
            question_type TEXT,
            title TEXT,
            content TEXT,
            reference_answer TEXT,
            year INTEGER,
            region TEXT,
            exam_type TEXT,
            exam_subtype TEXT,
            exam_category TEXT,
            word_limit INTEGER,
            score_hint INTEGER,
            is_deleted INTEGER DEFAULT 0
        )
    ''')
    db.execute('CREATE INDEX IF NOT EXISTS idx_paper_pid ON paper_questions(paper_id)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_paper_yr ON paper_questions(year)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_paper_reg ON paper_questions(region)')
    
    files = sorted([f for f in os.listdir(JS_DIR) if f.endswith('.json')])
    print(f'Found {len(files)} files')
    
    imported = 0
    papers = 0
    
    for fname in files:
        path = os.path.join(JS_DIR, fname)
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception as e:
            print(f'  SKIP {fname}: {e}')
            continue
        
        info = parse_filename(fname)
        if data.get('year'): info['year'] = data['year']
        if data.get('region'): info['region'] = data['region']
        
        questions = data.get('questions', [])
        if not questions: continue
        
        # Paper ID and title
        paper_id = str(uuid.uuid4())[:12]
        
        # Build paper title from filename
        paper_title = fname.replace('.json', '')
        # Simplify: remove redundant parts
        paper_title = re.sub(r'（网友回忆版）', '', paper_title)
        
        # Build full paper materials
        paper_materials = []
        top_materials = data.get('materials', [])
        if top_materials:
            for m in top_materials:
                if isinstance(m, str) and m.strip():
                    paper_materials.append(clean_material(m))
        
        for q in questions:
            q_index = q.get('index', 0)
            q_type = q.get('type', '')
            q_text = q.get('question', '')
            q_score = q.get('score', 0)
            q_word_limit = q.get('word_limit', 0)
            q_materials = q.get('materials', {})
            q_answers = q.get('answers', {})
            
            clean_q, extracted_answer = clean_question_text(q_text)
            
            # Build reference answer
            ref_parts = []
            for inst in ['某笔', '某图', '中公', '粉笔', '站长', '袁东']:
                ans = q_answers.get(inst, '')
                if ans and ans.strip():
                    ref_parts.append(f'【{inst}】\n{ans.strip()}')
            if not ref_parts and extracted_answer:
                ref_parts.append(extracted_answer)
            reference_answer = '\n\n'.join(ref_parts)
            
            # Build content: materials + question
            content_parts = []
            for mat_name, mat_text in q_materials.items():
                mat_clean = clean_material(mat_text)
                if mat_clean and len(mat_clean) > 10:
                    content_parts.append(f'【{mat_name}】\n{mat_clean}')
            
            if not content_parts and paper_materials:
                for i, m in enumerate(paper_materials):
                    if m and len(m) > 10:
                        content_parts.append(m)
            
            content_parts.append(clean_q.strip())
            content = '\n\n'.join(content_parts)
            
            if not content.strip(): continue
            
            type_map = {'概括归纳':'概括归纳','综合分析':'综合分析','提出对策':'提出对策',
                       '应用文':'应用文写作','文章论述':'文章论述（大作文）','大作文':'文章论述（大作文）'}
            db_type = type_map.get(q_type, q_type)
            
            db.execute('''
                INSERT INTO paper_questions (id, paper_id, paper_title, question_index, question_type,
                    title, content, reference_answer, year, region, exam_type, exam_subtype,
                    exam_category, word_limit, score_hint)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                str(uuid.uuid4())[:12], paper_id, paper_title, q_index, db_type,
                f'第{q_index}题', content, reference_answer,
                info['year'], info['region'], info['exam_type'], info['exam_subtype'],
                info['exam_category'], q_word_limit, q_score
            ))
            imported += 1
        
        papers += 1
    
    db.commit()
    
    total = db.execute('SELECT COUNT(*) FROM paper_questions').fetchone()[0]
    paper_count = db.execute('SELECT COUNT(DISTINCT paper_id) FROM paper_questions').fetchone()[0]
    with_ref = db.execute('SELECT COUNT(*) FROM paper_questions WHERE reference_answer IS NOT NULL AND reference_answer != ""').fetchone()[0]
    
    # Show sample papers
    samples = db.execute('SELECT DISTINCT paper_title, year, region, exam_subtype, COUNT(*) as cnt FROM paper_questions GROUP BY paper_id ORDER BY year DESC LIMIT 10').fetchall()
    
    print(f'\n=== Import Complete ===')
    print(f'JSON files: {len(files)}')
    print(f'Papers: {paper_count}')
    print(f'Questions: {total}')
    print(f'With answers: {with_ref}')
    print(f'\nSample papers:')
    for s in samples:
        print(f'  {s[1]} {s[2]} {s[3] or ""} | {s[0][:50]}... | {s[4]}题')
    
    db.close()

if __name__ == '__main__':
    main()
