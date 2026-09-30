# 视觉验收（restyle）：首页全图 -> 设置页上/下 -> 地图节点详情
import os
from playwright.sync_api import sync_playwright

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"
os.makedirs(OUT, exist_ok=True)
URL = "http://127.0.0.1:8081"

errors = []
console_err = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("pageerror", lambda e: errors.append(str(e)[:400]))
    page.on("console", lambda m: console_err.append(m.text[:300]) if m.type == "error" else None)

    page.goto(URL)
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(6000)

    # 1) 首页全图
    page.screenshot(path=os.path.join(OUT, "restyle_1_home.png"), full_page=True)

    # 2) 点右上设置 (1238, 40)
    page.mouse.click(1238, 40)
    page.wait_for_timeout(2500)
    page.screenshot(path=os.path.join(OUT, "restyle_2_settings_top.png"))

    # 3) 设置页下滚两张
    for i, dy in enumerate([700, 700, 700], start=1):
        page.mouse.move(640, 500)
        page.mouse.wheel(0, dy)
        page.wait_for_timeout(900)
        page.screenshot(path=os.path.join(OUT, f"restyle_3_settings_scroll{i}.png"))

    # 4) 返回：点左上返回（约 40,40），再点地图中部节点 (548,437)
    page.mouse.click(40, 40)
    page.wait_for_timeout(2000)
    page.mouse.click(548, 437)
    page.wait_for_timeout(2000)
    page.screenshot(path=os.path.join(OUT, "restyle_4_node_detail.png"))

    browser.close()

print("PAGE ERRORS:", errors if errors else "无")
print("CONSOLE ERRORS:", console_err if console_err else "无")
print("done ->", OUT)
