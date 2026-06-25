"""
补全全文 v4 — 自动检测编码 + 彻底清理
"""
import urllib.request
import re
import json
import ssl
import time
import os
import sys

ssl._create_default_https_context = ssl._create_unverified_context

CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "xjp_speech_cache.json")
UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36"

# ─── Find garbled or short articles ───
def needs_fix(item):
    c = item.get("content", "")
    if len(c) < 500:
        return True
    # Check for encoding corruption (replacement char or low CJK ratio)
    if '�' in c:
        return True
    if len(c) > 200:
        cjk = len(re.findall(r'[\u4e00-\u9fff]', c))
        total = len(c.replace(' ', '').replace('\n', ''))
        if total > 100 and cjk / max(total, 1) < 0.15:
            return True
    return False

def fix_url(item):
    aid = item.get("articleId", "")
    date = item.get("date", "")
    if not aid or not date: return item.get("url", "")
    parts = date.split("-")
    if len(parts) == 3:
        return f"http://cpc.people.com.cn/n1/{parts[0]}/{parts[1]}{parts[2]}/c64094-{aid}.html"
    return item.get("url", "")

def fetch_and_decode(url):
    """Fetch page and decode with correct encoding"""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    resp = urllib.request.urlopen(req, timeout=15)
    raw = resp.read()

    # Detect encoding from meta tag
    head = raw[:3000].decode('latin-1', errors='replace')
    m = re.search(r'charset[= ]+[\"\']?([a-zA-Z0-9\-_]+)', head, re.IGNORECASE)
    enc = m.group(1).lower() if m else 'utf-8'

    # Normalize encoding names
    enc_map = {'gb2312': 'gbk', 'gbk': 'gbk', 'gb18030': 'gbk',
               'utf-8': 'utf-8', 'utf8': 'utf-8'}
    enc = enc_map.get(enc, 'utf-8')

    try:
        return raw.decode(enc, errors='replace')
    except:
        return raw.decode('utf-8', errors='replace')

def clean_text(raw_html_chunk):
    """Clean HTML chunk to pure text"""
    # Strip tags
    text = re.sub(r'<[^>]+>', '\n', raw_html_chunk)
    # Decode entities
    text = text.replace('&nbsp;', ' ').replace('&ldquo;', '\u201c')
    text = text.replace('&rdquo;', '\u201d').replace('&mdash;', '\u2014')
    text = text.replace('&lt;', '<').replace('&gt;', '>').replace('&amp;', '&')
    text = re.sub(r'&[a-z]+;', '', text)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)

    lines = [l.strip() for l in text.split('\n') if l.strip()]
    # Remove metadata lines
    skip = {'订阅','取消订阅','已收藏','收藏','大字号','点击播报本文，约','txt">'}
    lines = [l for l in lines if l not in skip and 'class="text_con' not in l]

    # Find content start
    start = 0
    for i, l in enumerate(lines):
        if len(l) >= 6 and re.search(r'[\u4e00-\u9fff]', l):
            if not l.startswith('来源：') and not l.startswith('http'):
                start = i
                break

    # Find content end
    end_cut = [
        '(责编：','责编：','相关专题','var wxData','Copyright',
        '人 民 网 版 权 所 有','学习路上','时习之','系列重要讲话数据库',
        '中央文件','推荐阅读','打开客户端','<script','延伸阅读',
        '习近平活动报道专页','中国共产党新闻网>>','分享','专题报道',
        '微信','扫一扫','客户端','人民日报','党建',
        '|','网站地图','网站律师','信息网络传播','联系',
    ]
    end = len(lines)
    for i in range(start + 5, len(lines)):
        for m in end_cut:
            if m in lines[i] and len(lines[i]) < 80:
                end = i
                break
        if end < len(lines):
            break

    # Cut at 人民日报 footer
    for i in range(start + 5, min(len(lines), end + 1)):
        if '《 人民日报 》' in lines[i] or '《人民日报》' in lines[i]:
            if i + 1 < len(lines) and len(lines[i+1]) > 15:
                continue
            end = min(end, i + 1)
            break

    result = '\n\n'.join(lines[start:end]).strip()
    if len(result) > 80000:
        result = result[:80000]
    return result

def extract_content(html):
    idx = html.rfind('<div class="show_text">')
    if idx < 0:
        idx = html.rfind('class="text_con')
        if idx < 0:
            return ""

    if 'show_text' in html[idx:idx+30]:
        chunk = html[idx + 26:idx + 100000]
    else:
        chunk = html[idx:idx + 100000]

    end_m = re.search(r'<div class="(?:zanclear|editor|relateNews|page_3)"', chunk)
    if not end_m:
        end_m = re.search(r'</div>\s*<div class="editor"', chunk)
    if end_m:
        chunk = chunk[:end_m.start()]

    return clean_text(chunk)

def main():
    with open(CACHE, "r", encoding="utf-8") as f:
        data = json.load(f)

    to_fix = [i for i, item in enumerate(data) if needs_fix(item)]
    print(f"Total: {len(data)}, need fix: {len(to_fix)}")

    fixed = 0
    failed = 0
    skipped_good = 0

    for count, idx in enumerate(to_fix):
        item = data[idx]
        url = fix_url(item)
        title = item.get("title", "")[:50]
        old_len = len(item.get("content", ""))

        sys.stdout.write(f"\r[{count+1}/{len(to_fix)}] [{old_len}c] {title}...")
        sys.stdout.flush()

        try:
            html = fetch_and_decode(url)
            full = extract_content(html)

            if full and len(full) > max(old_len + 100, 500):
                item["content"] = full
                item["snippet"] = full[:300]
                fixed += 1
            elif full and len(full) > old_len + 50:
                item["content"] = full
                item["snippet"] = full[:300]
                fixed += 1
            else:
                failed += 1
        except Exception as e:
            failed += 1

        if (count + 1) % 50 == 0:
            with open(CACHE, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"  [saved {count+1}]")

        time.sleep(0.3)

    print(f"\n\nFixed: {fixed}, Failed: {failed}")

    with open(CACHE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    # Stats
    lengths = [len(i.get("content", "")) for i in data]
    garbled = sum(1 for i in data if '�' in i.get('content', ''))
    cjk_ok = sum(1 for i in data if len(i.get('content',''))>200 and len(re.findall(r'[\u4e00-\u9fff]', i.get('content',''))) / max(len(i.get('content','').replace(' ','').replace('\n','')),1) >= 0.15)
    print(f"Garbled left: {garbled}")
    print(f"<200: {sum(1 for l in lengths if l<200)}")
    print(f"200-500: {sum(1 for l in lengths if 200<=l<500)}")
    print(f"500-2000: {sum(1 for l in lengths if 500<=l<2000)}")
    print(f">=2000: {sum(1 for l in lengths if l>=2000)}")
    print(f"Size: {os.path.getsize(CACHE)/1024/1024:.1f} MB")

if __name__ == "__main__":
    main()
