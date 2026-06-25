import json, urllib.request, re, ssl
ssl._create_default_https_context = ssl._create_unverified_context

urls = [
    'http://www.people.com.cn/rss/politics.xml',
]

all_items = []
for url in urls:
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        resp = urllib.request.urlopen(req, timeout=15)
        body = resp.read().decode('utf-8', errors='replace')
        
        items = re.findall(r'<item>(.*?)</item>', body, re.DOTALL)
        for item_xml in items:
            title_m = re.search(r'<title><!\[CDATA\[(.*?)\]\]></title>', item_xml)
            link_m = re.search(r'<link>(.*?)</link>', item_xml)
            date_m = re.search(r'<pubDate>(.*?)</pubDate>', item_xml)
            if title_m and link_m and date_m:
                title = title_m.group(1).strip()
                link = link_m.group(1).strip()
                pub_date = date_m.group(1).strip()
                # Clean title
                title = re.sub(r'\s+', ' ', title)
                if len(title) >= 8 and not re.match(r'^[\d\s\-:]+$', title):
                    all_items.append({
                        'title': title,
                        'url': link,
                        'source': 'people',
                        'sourceName': '人民网',
                        'publishDate': pub_date,
                    })
        print('%s: %d items' % (url, len(items)))
    except Exception as e:
        print('%s: FAIL - %s' % (url, e))

print('\nTotal: %d items' % len(all_items))
dates = set(item['publishDate'] for item in all_items)
print('Dates: %s' % sorted(dates, reverse=True)[:10])

# Save
with open(r'C:\Users\ryq\shenlun_app\assets\news_cache.json', 'w', encoding='utf-8') as f:
    json.dump(all_items, f, ensure_ascii=False, indent=2)
print('\nSaved to assets/news_cache.json')
