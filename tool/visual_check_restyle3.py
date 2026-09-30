# 调试：设置页为何白屏
from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:8081"
logs = []
errs = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("pageerror", lambda e: errs.append("PAGEERROR: " + str(e)[:500]))
    page.on("console", lambda m: logs.append(f"[{m.type}] {m.text[:400]}"))

    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(8000)
    print("home url:", page.url)
    # 点齿轮
    page.mouse.click(1259, 27)
    page.wait_for_timeout(3000)
    print("after click url:", page.url)
    body = page.evaluate("() => document.body.innerText.slice(0, 500)")
    print("body text:", repr(body))
    html = page.evaluate("() => document.documentElement.outerHTML.slice(0, 1500)")
    print("html head:", html[:800])
    page.screenshot(path=r"D:\PythonCode\Shiguang_Handbook\.shots\restyle_dbg_settings.png")
    browser.close()

print("ERRORS:", errs if errs else "无")
print("CONSOLE (tail):")
for line in logs[-30:]:
    print(" ", line)
