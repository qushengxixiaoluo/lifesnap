# 诊断：为何 flutter web 白屏
from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:8081"
logs, req_fail, errs = [], [], []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("pageerror", lambda e: errs.append(str(e)[:400]))
    page.on("console", lambda m: logs.append(f"[{m.type}] {m.text[:300]}"))
    page.on("requestfailed", lambda r: req_fail.append(f"{r.url[:150]} :: {r.failure}"))

    page.goto(URL, wait_until="load", timeout=90000)
    page.wait_for_timeout(20000)
    print("body innerHTML len:", page.evaluate("() => document.body.innerHTML.length"))
    print("body innerHTML head:", page.evaluate("() => document.body.innerHTML.slice(0,600)"))
    print("has _flutter:", page.evaluate("() => typeof window._flutter"))
    print("flutterLoader:", page.evaluate("() => typeof window.FlutterLoader"))
    page.screenshot(path=r"D:\PythonCode\Shiguang_Handbook\.shots\restyle_dbg_home2.png")
    browser.close()

print("PAGE ERRORS:", errs if errs else "无")
print("REQ FAILED:", *req_fail[:10], sep="\n  " if req_fail else " 无")
print("CONSOLE tail:")
for line in logs[-40:]:
    print(" ", line)
