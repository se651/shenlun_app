"""
预爬取 jhsjk.people.cn 全部讲话（含全文）
API: testnew/result?form=706&else=501&page=N&source=2
"""
import urllib.request
import json
import ssl
import time
import os
import sys

ssl._create_default_https_context = ssl._create_unverified_context

API = "https://jhsjk.people.cn/testnew/result?form=706&else=501&source=2&page="
OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "xjp_speech_cache.json")
UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36"

def fetch_page(page):
    url = API + str(page)
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Referer": "https://jhsjk.people.cn/",
    })
    resp = urllib.request.urlopen(req, timeout=20)
    return json.loads(resp.read().decode("utf-8", errors="replace"))

def main():
    all_items = []
    seen = set()
    page = 1
    total = 0

    while True:
        sys.stdout.write(f"\r抓取第 {page} 页...")
        sys.stdout.flush()
        try:
            data = fetch_page(page)
            if data.get("status") != "success":
                print(f" 状态异常: {data.get('status')}")
                break

            if total == 0:
                total = int(data.get("total", "0"))

            items = data.get("list", [])
            if not items:
                print(" 无数据，停止")
                break

            new_count = 0
            for item in items:
                aid = str(item.get("article_id", ""))
                if aid and aid not in seen:
                    seen.add(aid)
                    # 清理标题
                    title = item.get("title", "").strip()
                    # 清理全文
                    content = item.get("newcontent", "").strip()

                    all_items.append({
                        "articleId": aid,
                        "title": title,
                        "source": item.get("origin_name", "").strip(),
                        "date": (item.get("input_date", "") or "")[:10],
                        "url": f"http://cpc.people.com.cn/n1/{(item.get('input_date','') or '')[:4]}/{item.get('input_date','') or ''}/{aid}.html",
                        "snippet": content[:200] if content else "",
                        "content": content,
                    })
                    new_count += 1

            print(f" +{new_count} (累计 {len(all_items)}/{total})", end="")

            if new_count == 0:
                break

            page += 1
            time.sleep(0.5)

        except Exception as e:
            print(f" 错误: {e}")
            time.sleep(2)
            # Retry once
            try:
                data = fetch_page(page)
                items = data.get("list", [])
                if not items:
                    break
                for item in items:
                    aid = str(item.get("article_id", ""))
                    if aid and aid not in seen:
                        seen.add(aid)
                        title = item.get("title", "").strip()
                        content = item.get("newcontent", "").strip()
                        all_items.append({
                            "articleId": aid,
                            "title": title,
                            "source": item.get("origin_name", "").strip(),
                            "date": (item.get("input_date", "") or "")[:10],
                            "url": f"http://cpc.people.com.cn/n1/{(item.get('input_date','') or '')[:4]}/{item.get('input_date','') or ''}/{aid}.html",
                            "snippet": content[:200] if content else "",
                            "content": content,
                        })
                page += 1
                time.sleep(0.5)
            except Exception as e2:
                print(f" 重试也失败: {e2}")
                break

    # Sort by date desc
    all_items.sort(key=lambda x: x["date"], reverse=True)

    print(f"\n\n总共 {len(all_items)} 条")

    # Save
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(all_items, f, ensure_ascii=False, indent=2)

    size_mb = os.path.getsize(OUTPUT) / (1024 * 1024)
    print(f"已保存: {OUTPUT} ({size_mb:.1f} MB)")
    print("完成!")

if __name__ == "__main__":
    main()
