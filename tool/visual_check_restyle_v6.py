# 视觉验收 v6：每步用像素轮询确认画面真正到位再截图
import io
import os
from PIL import Image
from playwright.sync_api import sync_playwright

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"
os.makedirs(OUT, exist_ok=True)
URL = "http://127.0.0.1:8081"

errors = []
console_err = []


def shot(page, name):
    data = page.screenshot()
    path = os.path.join(OUT, name)
    with open(path, "wb") as f:
        f.write(data)
    return Image.open(io.BytesIO(data)).convert("RGB")


def pixel(im, xy):
    return im.getpixel(xy)


def is_blue(px):
    r, g, b = px
    return b > 140 and b > r + 40 and g > 80  # 天空蓝


def is_cream(px):
    r, g, b = px
    return r > 225 and g > 205 and b > 180 and 15 <= (r - b) <= 70  # 暖奶油底，排除白云/蓝天


def is_scrim(px):
    r, g, b = px
    return r < 110 and b > r and 70 < b < 160 and g < 150  # 被遮罩压暗的天空


def wait_until(page, pred, timeout_s=60, name=""):
    for _ in range(timeout_s):
        im = shot(page, "_poll_tmp.png")
        if pred(im):
            return True
        page.wait_for_timeout(1000)
    print(f"TIMEOUT waiting for: {name}")
    return False


with sync_playwright() as p:
    browser = p.chromium.launch(headless=True,
                                 args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.on("pageerror", lambda e: errors.append(str(e)[:400]))
    page.on("console", lambda m: console_err.append(m.text[:300]) if m.type == "error" else None)

    # ---------- 1) 首页：等天空蓝出现 ----------
    page.goto(URL, wait_until="load", timeout=90000)
    ok = wait_until(page, lambda im: is_blue(pixel(im, (200, 300))), 120, "home sky blue")
    print("home painted:", ok)
    page.wait_for_timeout(1500)
    shot(page, "restyle_1_home.png")

    # ---------- 2) 点设置：等奶油底设置页 ----------
    navigated = False
    for xy in [(1259, 27), (1238, 40), (1259, 28), (1248, 27)]:
        page.mouse.click(*xy)
        page.wait_for_timeout(1000)
        if "settings" in page.url:
            navigated = True
            break
    if not navigated:
        print("gear click failed, direct goto")
        page.goto(URL + "/#/settings", wait_until="load", timeout=90000)
    ok = wait_until(page, lambda im: is_cream(pixel(im, (60, 300))), 45, "settings cream bg")
    print("settings painted:", ok, "url:", page.url)
    page.wait_for_timeout(1000)
    shot(page, "restyle_2_settings_top.png")

    # ---------- 3) 设置页下滚 ----------
    for i, dy in enumerate([700, 700, 700], start=1):
        page.mouse.move(640, 500)
        page.mouse.wheel(0, dy)
        page.wait_for_timeout(1200)
        shot(page, f"restyle_3_settings_scroll{i}.png")

    # ---------- 4) 回首页点节点 ----------
    page.goto(URL, wait_until="load", timeout=90000)
    ok = wait_until(page, lambda im: is_blue(pixel(im, (200, 300))), 60, "home2 sky blue")
    print("home2 painted:", ok, "url:", page.url)
    page.wait_for_timeout(1000)
    page.mouse.click(548, 437)
    # 详情弹出后遮罩压暗天空
    ok = wait_until(page, lambda im: is_scrim(pixel(im, (200, 300))), 30, "detail scrim")
    print("detail painted:", ok)
    page.wait_for_timeout(800)
    shot(page, "restyle_4_node_detail.png")

    # ---------- 5) 关详情 + 细节放大 ----------
    page.mouse.click(640, 60)
    page.wait_for_timeout(2500)
    shot(page, "restyle_5_path_zoom.png")  # 先全页，再裁
    im = Image.open(os.path.join(OUT, "restyle_5_path_zoom.png"))
    im.crop((180, 150, 600, 450)).save(os.path.join(OUT, "restyle_5_path_zoom.png"))
    im.crop((80, 140, 440, 420)).save(os.path.join(OUT, "restyle_6_node_zoom.png"))

    browser.close()

os.path.exists(os.path.join(OUT, "_poll_tmp.png")) and os.remove(os.path.join(OUT, "_poll_tmp.png"))
print("PAGE ERRORS:", errors if errors else "无")
print("CONSOLE ERRORS:", console_err if console_err else "无")
print("done ->", OUT)
