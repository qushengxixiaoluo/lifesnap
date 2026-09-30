# 修复验证：小节点 + 居中数字 + 无光束 + 详情面板
import os
from playwright.sync_api import sync_playwright

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"
URL = "http://127.0.0.1:8080"
errors = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("pageerror", lambda e: errors.append(str(e)[:300]))

    page.goto(URL)
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(6000)
    page.screenshot(path=os.path.join(OUT, "fix_1_home.png"))

    # 点 15 号节点（布局中心区域）→ 等 3 秒让面板动画走完再截
    page.mouse.click(548, 437)
    page.wait_for_timeout(3000)
    page.screenshot(path=os.path.join(OUT, "fix_2_detail.png"))

    browser.close()

print("PAGE ERRORS:", errors if errors else "无")
