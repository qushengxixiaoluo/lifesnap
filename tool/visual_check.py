# 拾光手册 · 视觉验收侦察脚本
# 用法: D:\Python\python.exe visual_check.py
# 步骤: 打开首页 -> 截图 -> 点设置 -> 截图 -> 返回 -> 输出控制台错误
import os
import sys
from playwright.sync_api import sync_playwright

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"
os.makedirs(OUT, exist_ok=True)
URL = "http://127.0.0.1:8080"

console_msgs = []
page_errors = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("console", lambda m: console_msgs.append(f"[{m.type}] {m.text[:300]}"))
    page.on("pageerror", lambda e: page_errors.append(str(e)[:500]))

    page.goto(URL)
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(5000)  # Flutter web 启动 + 首帧

    # 1) 首页（日光皮肤 + 当前月地图）
    page.screenshot(path=os.path.join(OUT, "01_home_daylight.png"))

    # 页面结构侦察（canvas / semantics）
    info = page.evaluate("""() => ({
        title: document.title,
        canvases: document.querySelectorAll('canvas').length,
        flutterViews: document.querySelectorAll('flutter-view, flutter-glass-pane').length,
        semantics: document.querySelectorAll('flt-semantics').length,
        bodyFirstChild: document.body.firstChild ? document.body.firstChild.nodeName : 'none',
    })""")
    print("PAGE_INFO:", info)

    # 2) 点右上角设置（AppBar actions 区域）
    page.mouse.click(1280 - 42, 44)
    page.wait_for_timeout(2500)
    page.screenshot(path=os.path.join(OUT, "02_settings_top.png"))

    # 3) 滚动到设置页底部（外观分区）
    page.mouse.move(640, 500)
    page.mouse.wheel(0, 2000)
    page.wait_for_timeout(1200)
    page.screenshot(path=os.path.join(OUT, "03_settings_bottom.png"))

    # 4) 再滚动找 AI 配置区
    page.mouse.wheel(0, -800)
    page.wait_for_timeout(1000)
    page.screenshot(path=os.path.join(OUT, "04_settings_middle.png"))

    browser.close()

print("=== PAGE ERRORS ===")
for e in page_errors:
    print(e)
print("=== CONSOLE (errors/warnings) ===")
for m in console_msgs:
    if m.startswith("[error]") or m.startswith("[warning]"):
        print(m)
print(f"console total: {len(console_msgs)}, pageerrors: {len(page_errors)}")
print("shots saved to", OUT)
