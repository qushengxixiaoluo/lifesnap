# 补拍：设置页（点击失败则直达 /#/settings）+ 首页放大细节
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

    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(8000)

    # 点右上设置齿轮（先试 1238,40，再试 1259,27）
    page.mouse.click(1238, 40)
    page.wait_for_timeout(1500)
    if "settings" not in page.url:
        page.mouse.click(1259, 27)
        page.wait_for_timeout(1500)
    if "settings" not in page.url:
        page.goto(URL + "/#/settings")
        page.wait_for_timeout(3000)
    page.wait_for_timeout(1500)
    print("URL after settings nav:", page.url)
    page.screenshot(path=os.path.join(OUT, "restyle_2_settings_top.png"))

    for i, dy in enumerate([700, 700, 700], start=1):
        page.mouse.move(640, 500)
        page.mouse.wheel(0, dy)
        page.wait_for_timeout(900)
        page.screenshot(path=os.path.join(OUT, f"restyle_3_settings_scroll{i}.png"))

    # 回首页，拍路径/节点细节放大
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(6000)
    page.screenshot(path=os.path.join(OUT, "restyle_5_path_zoom.png"),
                    clip={"x": 180, "y": 160, "width": 420, "height": 300})
    page.screenshot(path=os.path.join(OUT, "restyle_6_node_zoom.png"),
                    clip={"x": 80, "y": 150, "width": 340, "height": 260})

    browser.close()

print("PAGE ERRORS:", errors if errors else "无")
print("CONSOLE ERRORS:", console_err if console_err else "无")
print("done ->", OUT)
