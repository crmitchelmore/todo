from playwright.sync_api import sync_playwright
import pathlib

url = "file://" + str(pathlib.Path("index.html").resolve())
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True)
    pg = b.new_page(viewport={"width":1240,"height":1000}, device_scale_factor=2)
    pg.goto(url)
    pg.wait_for_timeout(1800)  # fonts + entrance animations
    pg.screenshot(path="png/showcase.png", full_page=True)
    # tight crop of the primary lockup for quick review
    pg.locator(".stage").screenshot(path="png/lockup.png")
    b.close()
print("done")
