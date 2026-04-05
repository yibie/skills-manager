"""Skills Manager Logo — Ordered Void: 3×3 grid on dark field."""
from PIL import Image, ImageDraw, ImageFilter
import os

SIZE = 1024
OUT = "/Users/chenyibin/Documents/prj/skills-manager/SkillsManager_Logo.png"
ICON_DIR = "/Users/chenyibin/Documents/prj/skills-manager/SkillsManager/Assets.xcassets/AppIcon.appiconset"

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

# Squircle mask
mask = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=220, fill=255)

# Background gradient
bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
bgd = ImageDraw.Draw(bg)
for y in range(SIZE):
    t = y / SIZE
    rv = int(28 + 4 * t)
    bv = int(34 + 2 * t)
    bgd.line([(0, y), (SIZE, y)], fill=(rv, rv, bv, 255))
bg.putalpha(mask)
img = Image.alpha_composite(img, bg)

# Grid params
PAD, GAP, CR = 148, 38, 36
CELL = (SIZE - 2 * PAD - 2 * GAP) // 3  # ~203

PATTERN = [
    [1, 1, 0],
    [1, 0, 1],
    [0, 1, 1],
]

# Drop shadows for lit cells
shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
for row in range(3):
    for col in range(3):
        if PATTERN[row][col]:
            cx = PAD + col * (CELL + GAP)
            cy = PAD + row * (CELL + GAP) + 10
            sd.rounded_rectangle(
                [cx - 3, cy, cx + CELL + 3, cy + CELL + 6],
                radius=CR + 4, fill=(0, 0, 0, 70),
            )
shadow = shadow.filter(ImageFilter.GaussianBlur(18))
shadow.putalpha(mask)
img = Image.alpha_composite(img, shadow)

# Draw all 9 cells
for row in range(3):
    for col in range(3):
        x0 = PAD + col * (CELL + GAP)
        y0 = PAD + row * (CELL + GAP)

        if PATTERN[row][col]:
            # --- Lit cell ---
            ci = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
            cd = ImageDraw.Draw(ci)
            for py in range(CELL):
                t = py / CELL
                v = int(235 - 30 * t)
                cd.line([(0, py), (CELL, py)], fill=(v, v, min(v + 6, 255), 255))
            cm = Image.new("L", (CELL, CELL), 0)
            ImageDraw.Draw(cm).rounded_rectangle([0, 0, CELL - 1, CELL - 1], radius=CR, fill=255)
            ci.putalpha(cm)
            img.paste(ci, (x0, y0), ci)

            # Glass highlight
            hl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            ImageDraw.Draw(hl).rounded_rectangle(
                [x0 + 5, y0 + 5, x0 + CELL - 6, y0 + 18],
                radius=8, fill=(255, 255, 255, 60),
            )
            img = Image.alpha_composite(img, hl)
        else:
            # --- Dark cell ---
            dc = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
            dd = ImageDraw.Draw(dc)
            dd.rounded_rectangle(
                [x0, y0, x0 + CELL, y0 + CELL],
                radius=CR, fill=(12, 12, 16, 255),
            )
            dd.rounded_rectangle(
                [x0 + 3, y0 + 3, x0 + CELL - 4, y0 + 14],
                radius=6, fill=(0, 0, 0, 40),
            )
            dd.rounded_rectangle(
                [x0, y0, x0 + CELL, y0 + CELL],
                radius=CR, outline=(255, 255, 255, 16), width=1,
            )
            img = Image.alpha_composite(img, dc)

# Icon border
bdr = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(bdr).rounded_rectangle(
    [1, 1, SIZE - 2, SIZE - 2], radius=220,
    outline=(255, 255, 255, 18), width=1,
)
bdr.putalpha(mask)
img = Image.alpha_composite(img, bdr)

# Save
img.save(OUT, "PNG")
print(f"Logo: {OUT}")
for s in [512, 256, 128, 64, 32, 16]:
    img.resize((s, s), Image.LANCZOS).save(os.path.join(ICON_DIR, f"icon_{s}.png"), "PNG")
    print(f"  icon_{s}.png")
print("Done.")
