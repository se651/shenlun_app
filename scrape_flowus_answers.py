"""从 FlowUs API 批量提取申论真题答案"""
import json, urllib.request, ssl, re, sqlite3, time

ssl._create_default_https_context = ssl._create_unverified_context
PAGE_ID = 'a1178f38-791e-4722-8699-4320d4ceec31'
DB_PATH = r'C:\Users\ryq\shenlun_app\assets\shenlun.db'

def flowus_api(path):
    url = f'https://flowus.cn/api{path}'
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json',
    })
    resp = urllib.request.urlopen(req, timeout=15)
    return json.loads(resp.read())

# 1. Get page blocks
print('Fetching page blocks...')
blocks = flowus_api(f'/blocks/{PAGE_ID}/children?limit=500')
block_list = blocks.get('results', [])

# 2. Find all sub-page blocks (paper documents)
paper_blocks = []
for b in block_list:
    if b.get('type') == 'page':
        title = b.get('properties', {}).get('title', [{}])[0].get('plain_text', '')
        bid = b.get('id', '')
        if bid:
            paper_blocks.append((bid, title))

print(f'Found {len(paper_blocks)} sub-pages')

# 3. For each sub-page, check if it contains answers (tables with 答案 text)
found_answers = {}
for bid, title in paper_blocks[:30]:  # limit to avoid rate limiting
    try:
        # Check if title matches any paper missing answers
        kids = flowus_api(f'/blocks/{bid}/children?limit=100')
        for k in kids.get('results', []):
            text = ''
            if k.get('type') == 'table':
                for r in k.get('children', []):
                    cells = []
                    for c in r.get('children', []):
                        for t in c.get('children', []):
                            if t.get('type') == 'text':
                                cells.append(t.get('text', ''))
                    text += ' | '.join(cells) + '\n'
            if text and len(text) > 100:
                found_answers[title] = text
                print(f'  {title[:40]}: {len(text)} chars')
        time.sleep(0.3)
    except Exception as e:
        print(f'  Error: {title[:30]} - {e}')

# 4. Save
with open('scraped_answers.json', 'w', encoding='utf-8') as f:
    json.dump(found_answers, f, ensure_ascii=False, indent=2)

print(f'\nSaved {len(found_answers)} papers with answers')
