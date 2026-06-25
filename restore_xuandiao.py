# Restore missing 选调生 papers from PDFs in 申论文档/选调生 folder
import os, re, sqlite3, shutil, uuid
from datetime import datetime
import pdfplumber

DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'
PDF_DIR = r'C:\Users\ryq\Desktop\申论文档\选调生'

shutil.copy2(DB_PATH, DB_PATH + f'.bak_restore_xd_{datetime.now().strftime("%Y%m%d_%H%M%S")}')

db = sqlite3.connect(DB_PATH)
db.row_factory = sqlite3.Row

def extract_from_pdf(pdf_path):
    """Extract materials and questions from a 选调生 PDF"""
    pdf = pdfplumber.open(pdf_path)
    all_text = ''
    for page in pdf.pages:
        t = page.extract_text() or ''
        all_text += t + '\n'
    pdf.close()
    
    all_text = re.sub(r'公考沉思录.*?(?:\n|$)', '', all_text)
    all_text = re.sub(r'\n{3,}', '\n\n', all_text)
    
    # Try Arabic numeral materials: 【材料1】...【材料N】
    pattern = r'【材料(\d+)】\s*\n'
    parts = re.split(pattern, all_text)
    
    materials = {}
    if len(parts) > 1:
        # Has 【材料N】 markers
        i = 1
        while i < len(parts) - 1:
            num = int(parts[i])
            content = parts[i+1]
            # Truncate at question start
            for m in re.finditer(r'\n(\d+)[.、]\s*(?:请|根据|给定|结合|阅读|假如|为|如果|要求|健康)', content):
                content = content[:m.start()]
                break
            content = content.strip()
            if content and len(content) > 50:
                materials[num] = content
            i += 2
    else:
        # Try 【给定资料】 format
        gd_start = all_text.find('【给定资料】')
        if gd_start >= 0:
            zy_start = all_text.find('【作答要求】')
            if zy_start < 0:
                zy_start = len(all_text)
            section = all_text[gd_start + len('【给定资料】'):zy_start]
            parts2 = re.split(r'(?:^|\n)(\d+)\s*[.．、]\s*', section)
            j = 1
            while j < len(parts2) - 1:
                if parts2[j].isdigit():
                    num = int(parts2[j])
                    if 1 <= num <= 20:
                        content = parts2[j+1].strip()
                        if content and len(content) > 50:
                            materials[num] = content
                j += 2
    
    # Extract questions from end of text
    questions = []
    # Find numbered question list at end
    q_match = re.search(r'\n(\d+)[.、]\s*(?:请|根据|给定|结合|阅读|假如|为|如果|要求|健康|材料)', all_text)
    if q_match:
        q_section = all_text[q_match.start():].strip()
        q_texts = re.split(r'\n(?=\d+[.、]\s*(?:请|根据|给定|结合|阅读|假如|为|如果|要求|健康|材料))', q_section)
        questions = [q.strip() for q in q_texts if q.strip() and len(q.strip()) > 10]
    
    return materials, questions

def detect_type(q_text):
    if re.search(r'(?:写一篇议论|写一篇文章|自拟题目|议论文|议论性文章)', q_text):
        if not re.search(r'(?:发言提纲|发言稿|简报|短评|提纲|拟写|起草)', q_text):
            return '文章论述（大作文）'
    if re.search(r'(?:发言提纲|发言稿|讲话稿|简报|短评|公开信|倡议书|建议书|报告提纲|调研报告|工作方案|宣传稿|推荐材料|汇报提纲|申报材料|工作简报|约稿|总结发言|拟写|起草|撰写)', q_text):
        return '应用文写作'
    if re.search(r'(?:概括|归纳|梳理|总结)', q_text):
        return '概括归纳'
    if re.search(r'(?:分析|理解|谈谈|说明|解释|原因)', q_text):
        return '综合分析'
    if re.search(r'(?:对策|建议|措施|提出|解决)', q_text):
        return '对策建议'
    return '概括归纳'

def parse_refs(q_text, q_type):
    if q_type == '文章论述（大作文）':
        return None
    refs = set()
    for m in re.finditer(r'[材料资料](\d+)', q_text):
        refs.add(int(m.group(1)))
    if not refs:
        return None
    return refs

# Papers to restore (PDF name -> DB title + metadata)
RESTORE = [
    ('2020年浙江省选调生考试《申论》题.pdf', '2020年浙江省选调生考试《申论》题', 2020, '浙江', '省考', '', '选调生'),
    ('2020年重庆市选调生考试《申论》题.pdf', '2020年重庆市选调生考试《申论》题', 2020, '重庆', '省考', '', '选调生'),
    ('2022年湖北省选调生考试《申论》题.pdf', '2022年湖北省选调生考试《申论》题', 2022, '湖北', '省考', '', '选调生'),
    ('2022年山东省选调生考试《申论》题.pdf', '2022年山东省选调生考试《申论》题', 2022, '山东', '省考', '', '选调生'),
    ('2023年安徽省定向选调生考试《申论》题.pdf', '2023年安徽省定向选调生考试《申论》题', 2023, '安徽', '省考', '', '选调生'),
    ('2023年浙江省选调生考试《申论》题.pdf', '2023年浙江省选调生考试《申论》题', 2023, '浙江', '省考', '', '选调生'),
    ('2024江西选调生申论考试.pdf', '2024江西选调生申论考试', 2024, '江西', '省考', '', '选调生'),
    ('2024重庆定向选调生申论考试.pdf', '2024重庆定向选调生申论考试', 2024, '重庆', '省考', '', '选调生'),
    ('2025北京定向选调生申论考试.pdf', '2025北京定向选调生申论考试', 2025, '北京', '省考', '', '选调生'),
    ('2025河南定向选调申论考试.pdf', '2025河南定向选调申论考试', 2025, '河南', '省考', '', '选调生'),
    ('2025湖北选调生申论考试.pdf', '2025湖北选调生申论考试', 2025, '湖北', '省考', '', '选调生'),
    ('2025重庆定向选调生申论考试.pdf', '2025重庆定向选调生申论考试', 2025, '重庆', '省考', '', '选调生'),
    ('2026河南定向选调生申论考试.pdf', '2026河南定向选调生申论考试', 2026, '河南', '省考', '', '选调生'),
]

for pdf_fname, paper_title, year, region, exam_type, exam_subtype, exam_category in RESTORE:
    pdf_path = os.path.join(PDF_DIR, pdf_fname)
    if not os.path.exists(pdf_path):
        print(f"SKIP: PDF not found: {pdf_fname}")
        continue
    
    # Check if already in DB
    existing = db.execute('SELECT paper_id FROM paper_questions WHERE paper_title=? AND is_deleted=0 LIMIT 1', (paper_title,)).fetchone()
    if existing:
        print(f"SKIP: already in DB: {paper_title}")
        continue
    
    materials, questions = extract_from_pdf(pdf_path)
    
    if not materials:
        print(f"SKIP: no materials extracted from {pdf_fname}")
        continue
    
    if not questions:
        print(f"SKIP: no questions extracted from {pdf_fname}")
        continue
    
    paper_id = str(uuid.uuid4())[:12]
    print(f"\nRESTORING: {paper_title}")
    print(f"  Materials: {sorted(materials.keys())}")
    print(f"  Questions: {len(questions)}")
    
    for i, q_text in enumerate(questions):
        q_idx = i + 1
        clean_q = q_text.strip()
        q_type = detect_type(clean_q)
        refs = parse_refs(clean_q, q_type)
        
        parts = []
        if refs is None:
            for num in sorted(materials.keys()):
                parts.append(f'【材料{num}】\n{materials[num]}')
        elif refs:
            for num in sorted(refs):
                if num in materials:
                    parts.append(f'【材料{num}】\n{materials[num]}')
        
        parts.append(clean_q)
        content = '\n\n'.join(parts)
        
        if len(content) < 100:
            print(f"  Q{q_idx}: SHORT ({len(content)}), skipping")
            continue
        
        db.execute('''
            INSERT INTO paper_questions (id, paper_id, paper_title, question_index, question_type,
                title, content, reference_answer, year, region, exam_type, exam_subtype,
                exam_category, word_limit, score_hint, is_deleted)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            str(uuid.uuid4())[:12], paper_id, paper_title, q_idx, q_type,
            f'第{q_idx}题', content, '',
            year, region, exam_type, exam_subtype,
            exam_category, 0, 0, 0
        ))
        
        dz_flag = ' [大作文→ALL]' if refs is None else ''
        mat_used = re.findall(r'【材料(\d+)】', content)
        print(f"  Q{q_idx} ({q_type}){dz_flag}: mats={mat_used}, len={len(content)}")

db.commit()

# Final count

print(f"\n{'='*80}")
xd_count = db.execute("SELECT COUNT(DISTINCT paper_id) FROM paper_questions WHERE exam_category='选调生' AND is_deleted=0").fetchone()[0]
ql = db.execute('SELECT COUNT(*) FROM paper_questions WHERE is_deleted=0').fetchone()[0]
pl = db.execute('SELECT COUNT(DISTINCT paper_id) FROM paper_questions WHERE is_deleted=0').fetchone()[0]
print(f"Total: {ql} questions, {pl} papers, {xd_count} 选调生 papers")
db.close()
print("Done.")
