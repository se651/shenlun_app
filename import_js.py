# 从 申论文档/js/ 导入 JSON 题库到 shenlun.db
import sqlite3, json, os, re, shutil, uuid
from datetime import datetime

JS_DIR = os.path.join(os.environ['USERPROFILE'], 'Desktop', '申论文档', 'js')
DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'

# ====== 文件名解析 ======
def parse_filename(fname):
    """从文件名提取 year, region, exam_type, exam_subtype, exam_category"""
    name = fname.replace('.json', '')
    result = {'year': None, 'region': '', 'exam_type': '', 'exam_subtype': '', 'exam_category': ''}
    
    # 1. 提取年份
    ym = re.search(r'(\d{4})年?', name)
    if ym:
        result['year'] = int(ym.group(1))
    
    # 2. 提取地区
    regions = ['北京', '上海', '天津', '重庆', '河北', '山西', '辽宁', '吉林', '黑龙江',
               '江苏', '浙江', '安徽', '福建', '江西', '山东', '河南', '湖北', '湖南',
               '广东', '广西', '海南', '四川', '贵州', '云南', '西藏', '陕西', '甘肃',
               '青海', '宁夏', '新疆', '内蒙古', '深圳']
    for r in sorted(regions, key=len, reverse=True):
        if r in name:
            result['region'] = r
            break
    
    # 3. 国考识别
    if '国考' in name or '国家' in name:
        result['exam_type'] = '国考'
        result['region'] = '国家'
    
    # 4. 选调生识别
    if '选调生' in name or '定向选调' in name or '选调' in name:
        result['exam_category'] = '选调生'
    
    # 5. 卷型识别
    subtypes = ['副省级', '地市级', '行政执法', '省市卷', '县乡卷', '乡镇卷', '县级卷',
                'A卷', 'B卷', 'C卷', '甲卷', '乙卷', '丙卷', '一卷', '二卷', '三卷',
                '县乡', '省市', '乡镇', '县级', '州市卷', '市区卷', '街镇卷',
                '盟市卷', '旗县卷', '通用卷', '县镇']
    for st in sorted(subtypes, key=len, reverse=True):
        if st in name:
            norm = st
            if not norm.endswith('卷'): norm += '卷'
            if norm == '甲卷': norm = 'A卷'
            if norm == '乙卷': norm = 'B卷'
            if norm == '丙卷': norm = 'C卷'
            result['exam_subtype'] = norm
            break
    
    # 6. 省考/市考
    if not result['exam_type'] and result['region'] and result['region'] != '国家':
        result['exam_type'] = '省考'
    if '深圳' in name:
        result['exam_type'] = '市考'
    
    return result

# ====== 答案分离 ======
ANSWER_MARKERS = ['某笔', '某图', '中公', '粉笔', '站长', '袁东', '千寻']

def clean_question_text(q_text):
    """从题目文本中分离出干净的题目和参考答案"""
    # 找到第一个机构标记的位置
    cut_pos = len(q_text)
    for marker in ANSWER_MARKERS:
        pos = q_text.find(marker)
        if 0 < pos < cut_pos:
            # 从标记所在行开始切
            line_start = q_text.rfind('\n', 0, pos)
            if line_start >= 0:
                cut_pos = line_start
            else:
                cut_pos = pos
    
    if cut_pos < len(q_text):
        question = q_text[:cut_pos].strip()
        answer = q_text[cut_pos:].strip()
        return question, answer
    return q_text, ''

# ====== 主导入 ======
def main():
    # 备份
    shutil.copy2(DB_PATH, DB_PATH + f'.bak_import_{datetime.now().strftime("%Y%m%d_%H%M%S")}')
    
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    
    # 清空旧数据
    db.execute('DELETE FROM questions')
    db.execute('DELETE FROM practice_records')
    db.execute('DELETE FROM favorites')
    print('Cleared old data')
    
    files = [f for f in os.listdir(JS_DIR) if f.endswith('.json')]
    print(f'Found {len(files)} JSON files')
    
    imported = 0
    skipped = 0
    errors = []
    
    for fname in sorted(files):
        path = os.path.join(JS_DIR, fname)
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception as e:
            errors.append(f'{fname}: read error {e}')
            skipped += 1
            continue
        
        info = parse_filename(fname)
        
        # Override with JSON metadata if available
        if data.get('year'):
            info['year'] = data['year']
        if data.get('region'):
            info['region'] = data['region']
        
        questions = data.get('questions', [])
        if not questions:
            skipped += 1
            continue
        
        # Build material map
        all_materials = data.get('materials', [])
        
        for q in questions:
            q_index = q.get('index', 0)
            q_type = q.get('type', '')
            q_text = q.get('question', '')
            q_score = q.get('score', 0)
            q_word_limit = q.get('word_limit', 0)
            q_materials = q.get('materials', {})
            q_answers = q.get('answers', {})
            
            # Clean question text → separate answer
            clean_q, extracted_answer = clean_question_text(q_text)
            
            # Build reference_answer from answers dict
            ref_parts = []
            for inst in ['某笔', '某图', '中公', '粉笔', '站长', '袁东']:
                ans = q_answers.get(inst, '')
                if ans and ans.strip():
                    ref_parts.append(f'【{inst}】\n{ans.strip()}')
            
            if not ref_parts and extracted_answer:
                ref_parts.append(extracted_answer)
            
            reference_answer = '\n\n'.join(ref_parts)
            
            # Build content: materials + question text
            content_parts = []
            for mat_name, mat_text in q_materials.items():
                if mat_text and mat_text.strip():
                    # Clean material text: remove separator lines and title tags
                    mat_clean = re.sub(r'-{30,}.*?-{0,30}', '', mat_text)
                    mat_clean = mat_clean.strip()
                    if mat_clean:
                        content_parts.append(f'【{mat_name}】\n{mat_clean}')
            
            # Also add materials from top-level if not in question-level
            if not content_parts and all_materials:
                for i, m in enumerate(all_materials):
                    if isinstance(m, str) and m.strip():
                        m_clean = re.sub(r'-{30,}.*?-{0,30}', '', m).strip()
                        if m_clean:
                            content_parts.append(m_clean)
            
            content_parts.append(clean_q.strip())
            content = '\n\n'.join(content_parts)
            
            if not content.strip():
                continue
            
            # Generate ID
            qid = str(uuid.uuid4())[:12]
            
            # Normalize question type
            type_map = {
                '概括归纳': '概括归纳',
                '综合分析': '综合分析', 
                '提出对策': '提出对策',
                '应用文': '应用文写作',
                '文章论述': '文章论述（大作文）',
                '大作文': '文章论述（大作文）',
            }
            db_type = type_map.get(q_type, q_type)
            
            db.execute('''
                INSERT INTO questions (id, question_type, title, content, reference_answer,
                    year, region, exam_type, exam_subtype, exam_category, word_limit, score_hint, is_deleted)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            ''', (
                qid, db_type, f'第{q_index}题', content, reference_answer,
                info['year'], info['region'], info['exam_type'], info['exam_subtype'],
                info['exam_category'], q_word_limit, q_score
            ))
            imported += 1
    
    db.commit()
    
    # Stats
    total = db.execute('SELECT COUNT(*) FROM questions WHERE is_deleted=0').fetchone()[0]
    with_ref = db.execute('SELECT COUNT(*) FROM questions WHERE is_deleted=0 AND reference_answer IS NOT NULL AND reference_answer != ""').fetchone()[0]
    print(f'\n=== Import Result ===')
    print(f'Files processed: {len(files)}')
    print(f'Questions imported: {imported}')
    print(f'Skipped: {skipped}')
    print(f'Total questions in DB: {total}')
    print(f'Questions with answer: {with_ref}')
    
    if errors:
        print(f'\nErrors ({len(errors)}):')
        for e in errors[:10]:
            print(f'  {e}')
    
    db.close()

if __name__ == '__main__':
    main()
