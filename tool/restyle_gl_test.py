# 测试：headless chromium 的 canvas2d / webgl 截图是否正常
from playwright.sync_api import sync_playwright
import os

OUT = r"D:\PythonCode\Shiguang_Handbook\.shots"

html = """
<canvas id=c2 width=400 height=200></canvas>
<canvas id=gl width=400 height=200></canvas>
<script>
const c = document.getElementById('c2').getContext('2d');
const g = c.createLinearGradient(0,0,400,0);
g.addColorStop(0,'#ff8800'); g.addColorStop(1,'#0088ff');
c.fillStyle = g; c.fillRect(0,0,400,200);
const gl = document.getElementById('gl').getContext('webgl');
window.glstatus = 'none';
if (gl) {
  gl.clearColor(0.1,0.7,0.2,1); gl.clear(gl.COLOR_BUFFER_BIT);
  window.glstatus = 'ok:' + gl.getParameter(gl.VERSION);
} else { window.glstatus = 'no-webgl'; }
</script>
"""

for args in ([], ["--enable-unsafe-swiftshader"], ["--use-angle=swiftshader"]):
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=args)
        page = browser.new_page(viewport={"width": 500, "height": 300})
        logs = []
        page.on("console", lambda m: logs.append(f"[{m.type}] {m.text[:150]}"))
        page.set_content(html)
        page.wait_for_timeout(1000)
        st = page.evaluate("() => window.glstatus")
        name = "gltest_" + ("default" if not args else "_".join(a.replace("-","") for a in args)) + ".png"
        page.screenshot(path=os.path.join(OUT, name))
        print(f"args={args} gl={st} logs={logs}")
        browser.close()

# 采样截图像素
from PIL import Image
for f in os.listdir(OUT):
    if f.startswith("gltest_"):
        im = Image.open(os.path.join(OUT, f)).convert("RGB")
        px = [im.getpixel((100,100)), im.getpixel((300,250))]
        print(f, "pixels:", px)
