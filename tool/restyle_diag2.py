# 诊断2：DDC 模块加载进度
from playwright.sync_api import sync_playwright
import time

URL = "http://127.0.0.1:8081"
n_resp = [0]
n_fail = [0]
codes = {}
logs = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})

    def on_resp(r):
        n_resp[0] += 1
        codes[r.status] = codes.get(r.status, 0) + 1
        if r.status >= 400 and codes.get("bad_examples") is None:
            logs.append(f"BAD {r.status} {r.url[:200]}")
            codes["bad_examples"] = 1
    page.on("response", on_resp)
    page.on("requestfailed", lambda r: (n_fail.__setitem__(0, n_fail[0]+1), logs.append(f"FAIL {r.url[:150]} {r.failure}")))
    page.on("console", lambda m: logs.append(f"[{m.type}] {m.text[:200]}"))

    t0 = time.time()
    page.goto(URL, wait_until="load", timeout=90000)
    for i in range(30):  # 120s 每 4s 报一次
        page.wait_for_timeout(4000)
        mounted = page.evaluate("() => document.body.querySelectorAll('canvas, flutter-view, flt-glass-pane').length")
        print(f"t={time.time()-t0:.0f}s resp={n_resp[0]} fail={n_fail[0]} mounted={mounted}")
        if mounted:
            break
    print("codes:", {k: v for k, v in codes.items() if k != "bad_examples"})
    print("logs tail:")
    for line in logs[-15:]:
        print("  ", line)
    browser.close()
