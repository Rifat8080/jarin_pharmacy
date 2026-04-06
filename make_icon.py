#!/usr/bin/env python3
"""Generate a 1024x1024 Jarin Pharmacy app icon."""

import os
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Colors
BG_COLOR = (14, 48, 100, 255)      # dark navy
GREEN    = (16, 185, 129, 255)     # emerald green
WHITE    = (255, 255, 255, 255)
BLUE_LIGHT = (147, 197, 253, 255)

def rounded_rect_shape(draw, x0, y0, x1, y1, radius, fill):
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=fill)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=fill)
    draw.ellipse([x0, y0, x0 + 2*radius, y0 + 2*radius], fill=fill)
    draw.ellipse([x1 - 2*radius, y0, x1, y0 + 2*radius], fill=fill)
    draw.ellipse([x0, y1 - 2*radius, x0 + 2*radius, y1], fill=fill)
    draw.ellipse([x1 - 2*radius, y1 - 2*radius, x1, y1], fill=fill)

# Background rounded rectangle
rounded_rect_shape(draw, 0, 0, SIZE, SIZE, 140, BG_COLOR)

# Medical cross (green, centered upper half)
cx = SIZE // 2
cy = SIZE // 2 - 60
arm_w = 120
arm_h = 380

# Vertical arm
draw.rounded_rectangle(
    [cx - arm_w//2, cy - arm_h//2, cx + arm_w//2, cy + arm_h//2],
    radius=35, fill=GREEN
)
# Horizontal arm
draw.rounded_rectangle(
    [cx - arm_h//2, cy - arm_w//2, cx + arm_h//2, cy + arm_w//2],
    radius=35, fill=GREEN
)

# White circle in centre of cross
r = 50
draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE)

# Text: "JARIN" and "PHARMACY"
candidates = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNSDisplay.otf",
    "/Library/Fonts/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Futura.ttc",
    "/System/Library/Fonts/Geneva.ttf",
]

font_path = None
for c in candidates:
    if os.path.exists(c):
        font_path = c
        break

if font_path:
    try:
        font_big   = ImageFont.truetype(font_path, 148)
        font_small = ImageFont.truetype(font_path, 68)
    except Exception:
        font_big = font_small = ImageFont.load_default()
else:
    font_big = font_small = ImageFont.load_default()

# "JARIN"
label = "JARIN"
bb = draw.textbbox((0, 0), label, font=font_big)
tw = bb[2] - bb[0]
draw.text((SIZE//2 - tw//2, 710), label, font=font_big, fill=WHITE)

# "PHARMACY"
sub = "PHARMACY"
bb2 = draw.textbbox((0, 0), sub, font=font_small)
tw2 = bb2[2] - bb2[0]
draw.text((SIZE//2 - tw2//2, 875), sub, font=font_small, fill=BLUE_LIGHT)

# Save
out_path = os.path.join(os.path.dirname(__file__), "assets", "app_icon.png")
os.makedirs(os.path.dirname(out_path), exist_ok=True)
img.save(out_path, "PNG")
print(f"Saved: {out_path}  ({SIZE}x{SIZE})")
