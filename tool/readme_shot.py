# README 门面图：真实字体的闯关地图截图（带防白屏重试与质量校验）
import io
import os
import time

from PIL import Image, ImageStat
from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:8080"
OUT_DIR = r"D:\PythonCode\Shiguang_Handbook\screenshots"
os.makedirs(OUT_DIR, exist_ok=True)


def is_good(png_bytes: bytes) -> bool:
    """空白/单色画布判废：灰度标准差太低 = 白屏。"""
    im = Image.open(io.BytesIO(png_bytes)).convert("L")
    return ImageStat.Stat(im).stddev[0] > 20.0


with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.goto(URL)
    page.wait_for_load_state("networkidle")

    shot = None
    for attempt in range(4):
        page.wait_for_timeout(8000 if attempt == 0 else 4000)
        # 轻微晃动鼠标唤起渲染（部分无头环境画布要事件才刷）
        page.mouse.move(640, 400)
        page.mouse.move(641, 401)
        shot = page.screenshot()
        if is_good(shot):
            print(f"第 {attempt + 1} 次截图通过质量校验")
            break
        print(f"第 {attempt + 1} 次截图疑似空白，重试")
    else:
        raise SystemExit("4 次截图均为空白，放弃")

    out = os.path.join(OUT_DIR, "home_map.png")
    with open(out, "wb") as f:
        f.write(shot)

    # 顺手补一张设置页（三件套配置区），README 配置章节用
    page.mouse.click(1280 - 42, 40)
    page.wait_for_timeout(3000)
    shot2 = page.screenshot()
    if is_good(shot2):
        with open(os.path.join(OUT_DIR, "settings.png"), "wb") as f:
            f.write(shot2)
        print("设置页截图通过")
    else:
        print("设置页截图空白，跳过")

    browser.close()

for name in os.listdir(OUT_DIR):
    kb = os.path.getsize(os.path.join(OUT_DIR, name)) // 1024
    print(f"{name}  {kb}KB")
