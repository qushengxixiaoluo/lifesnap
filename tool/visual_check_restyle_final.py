# 视觉验收（restyle）v5：轮询 body 直到 Flutter 视图真正挂载
import os
from playwright.sync_api import sync_playwright

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"
os.makedirs(OUT, exist_ok=True)
URL = "http://127.0.0.1:8081"

errors = []
console_err = []


def wait_ready(page, budget_s=300):
    """DDC 首次编译 1164 个模块很慢；networkidle 会在编译停顿期误触发。
    以 body 里出现 Flutter 渲染元素为准。"""
    steps = int(budget_s / 2)
    for _ in range(steps):
        n = page.evaluate("""() => {
            const b = document.body;
            if (!b) return 0;
            const flt = b.querySelectorAll('canvas, flutter-view, flt-glass-pane, flt-scene, flt-semantics-host');
            if (flt.length) return flt.length;
            // canvaskit 也可能塞在 shadow root 里
            let shadow = 0;
            b.querySelectorAll('*').forEach(el => { if (el.shadowRoot) shadow++; });
            return shadow ? 99 : 0;
        }""")
        if n:
            page.wait_for_timeout(6000)  # 首帧 + 字体/图片
            return True
        page.wait_for_timeout(2000)
    return False


with sync_playwright() as p:
    browser = p.chromium.launch(headless=True,
                                 args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("pageerror", lambda e: errors.append(str(e)[:400]))
    page.on("console", lambda m: console_err.append(m.text[:300]) if m.type == "error" else None)

    page.goto(URL, wait_until="load", timeout=90000)
    ok = wait_ready(page)
    print("home ready:", ok)

    # 1) 首页全图
    page.screenshot(path=os.path.join(OUT, "restyle_1_home.png"))

    # 2) 点右上设置齿轮
    for xy in [(1259, 27), (1238, 40)]:
        page.mouse.click(*xy)
        page.wait_for_timeout(1500)
        if "settings" in page.url:
            break
    if "settings" not in page.url:
        page.goto(URL + "/#/settings", wait_until="load", timeout=90000)
        ok = wait_ready(page, budget_s=60)
        print("settings direct ready:", ok)
    page.wait_for_timeout(2500)
    print("settings url:", page.url)
    page.screenshot(path=os.path.join(OUT, "restyle_2_settings_top.png"))

    # 3) 设置页下滚
    for i, dy in enumerate([700, 700, 700], start=1):
        page.mouse.move(640, 500)
        page.mouse.wheel(0, dy)
        page.wait_for_timeout(900)
        page.screenshot(path=os.path.join(OUT, f"restyle_3_settings_scroll{i}.png"))

    # 4) 回首页点地图中部节点 (548,437)
    page.goto(URL, wait_until="load", timeout=90000)
    ok = wait_ready(page, budget_s=120)
    print("home2 ready:", ok)
    page.mouse.click(548, 437)
    page.wait_for_timeout(2000)
    page.screenshot(path=os.path.join(OUT, "restyle_4_node_detail.png"))

    # 5) 细节放大：路径 / 节点
    page.mouse.click(640, 80)
    page.wait_for_timeout(1200)
    page.screenshot(path=os.path.join(OUT, "restyle_5_path_zoom.png"),
                    clip={"x": 180, "y": 150, "width": 420, "height": 300})
    page.screenshot(path=os.path.join(OUT, "restyle_6_node_zoom.png"),
                    clip={"x": 80, "y": 140, "width": 360, "height": 280})

    browser.close()

print("PAGE ERRORS:", errors if errors else "无")
print("CONSOLE ERRORS:", console_err if console_err else "无")
print("done ->", OUT)
