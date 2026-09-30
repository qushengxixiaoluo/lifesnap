# 复检：长等待 + 控制台捕获 + 逐阶段截图
import os
from playwright.sync_api import sync_playwright

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"
URL = "http://127.0.0.1:8080"
errors, console = [], []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("pageerror", lambda e: errors.append(str(e)[:300]))
    page.on("console", lambda m: console.append(f"[{m.type}] {m.text[:200]}"))

    page.goto(URL)
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(12000)  # debug 模式首编译慢，给足时间
    page.screenshot(path=os.path.join(OUT, "v2_1_home.png"))
    print("title:", page.title())

    page.mouse.click(548, 437)
    page.wait_for_timeout(3500)
    page.screenshot(path=os.path.join(OUT, "v2_2_after_tap.png"))

    browser.close()

print("PAGE ERRORS:", errors if errors else "无")
print("CONSOLE:", [c for c in console if "error" in c.lower()][:5] or "无错误级")
