"""导出 shenlun.db 全部数据到 full_questions.json"""
import sqlite3, json

import os
db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets', 'shenlun.db')
db = sqlite3.connect(db_path)
db.row_factory = sqlite3.Row

# 导出题目
questions = []
for row in db.execute("SELECT * FROM questions WHERE is_deleted=0"):
    questions.append({
        'id': row['id'],
        'type': row['question_type'],
        'title': row['title'] or '',
        'score': '',
        'content': row['content'] or '',
        'word_limit': row['word_limit'] or 0,
        'year': row['year'] or 2024,
        'region': row['region'] or '国考',
        'exam_type': row['exam_type'] or '',
        'exam_subtype': row['exam_subtype'] or '',
        'exam_category': row['exam_category'] or '',
    })

# 导出规范词 — 先探测实际列名
cols = [d[1] for d in db.execute("PRAGMA table_info(high_freq_words)")]
print(f"high_freq_words columns: {cols}")
words = []
for row in db.execute("SELECT * FROM high_freq_words ORDER BY category"):
    d = dict(row)
    words.append({
        'category': d.get('category', ''),
        'word': d.get('word', d.get('name', '')),
        'context': d.get('context', d.get('example', d.get('usage', ''))),
    })

data = {'questions': questions, 'words': words}

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'full_questions.json')
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False)

print(f"导出完成：{len(questions)} 道题，{len(words)} 个规范词")

db.close()
