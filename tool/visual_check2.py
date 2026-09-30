# 视觉验收 v2：设置入口回归 + 点节点弹详情 + 设置页巡览
import os
from playwright.sync_api import sync_playwright

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"
os.makedirs(OUT, exist_ok=True)
URL = "http://127.0.0.1:8080"

errors = []
console_err = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("pageerror", lambda e: errors.append(str(e)[:400]))
    page.on("console", lambda m: console_err.append(m.text[:300]) if m.type == "error" else None)

    page.goto(URL)
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(5000)

    # 1) 点 15 号节点（布局截图中约 (548, 437)）→ 详情面板
    page.mouse.click(548, 437)
    page.wait_for_timeout(2000)
    page.screenshot(path=os.path.join(OUT, "10_node_tap_detail.png"))

    # 2) 关面板：点面板上方遮罩
    page.mouse.click(640, 80)
    page.wait_for_timeout(1500)

    # 3) 点右上设置
    page.mouse.click(1280 - 42, 40)
    page.wait_for_timeout(2500)
    page.screenshot(path=os.path.join(OUT, "11_settings_top.png"))

    # 4) 分段下滚截图
    for i, dy in enumerate([700, 700, 700, 700], start=1):
        page.mouse.move(640, 500)
        page.mouse.wheel(0, dy)
        page.wait_for_timeout(900)
        page.screenshot(path=os.path.join(OUT, f"12_settings_scroll{i}.png"))

    browser.close()

print("PAGE ERRORS:", errors if errors else "无")
print("CONSOLE ERRORS:", console_err if console_err else "无")
print("done ->", OUT)
