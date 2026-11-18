"""Repaint the game's hi-res pictures at high resolution for the 'enhanced' display style.

Each picture is decoded from the original disk asset and repainted at SCALE x the
Apple's 280x192, keeping every shape where it was (the game logic depends on the
geography).  The results go to odyssey/assets/art/*.jpg.

Development-time only (the game itself needs nothing but pygame-ce):

    uv run --with pillow --with numpy --with scipy python tools/render_art.py [names...]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
from odyssey.hires import Hires, HEIGHT, WIDTH  # noqa: E402

SCALE = 6
W, H = WIDTH * SCALE, HEIGHT * SCALE
ASSETS = os.path.join(ROOT, 'odyssey', 'assets')
OUT = os.path.join(ASSETS, 'art')
FONTS = os.path.join(HERE, 'fonts')
BLACK, WHITE, VIOLET, GREEN, BLUE, ORANGE = range(6)
RNG = np.random.default_rng(1980)


# --- decoding and shapes --------------------------------------------------------------------
def decode(name):
    """The picture as a 192x280 array of colour classes (BLACK..ORANGE)."""
    h = Hires()
    h.load(open(os.path.join(ASSETS, name + '.hgr'), 'rb').read())
    return np.array([h.render_row(y, range(6)) for y in range(HEIGHT)], dtype=np.uint8)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def up(mask, soft=0.45, level=0.5, edge=0.08, tall=1.0):
    """A 280x192 pixel mask as a smooth, anti-aliased alpha at full resolution.
    `tall` > 1 smooths more vertically (hi-res dither runs in rows)."""
    f = ndi.zoom(mask.astype(np.float32), SCALE, order=1)
    f = ndi.gaussian_filter(f, (SCALE * soft * tall, SCALE * soft))
    return smoothstep(level - edge, level + edge, f)


def lines(mask, soft=0.38, level=0.3):
    """Thin pixel lines as smooth strokes (a lower threshold keeps them joined)."""
    return up(mask, soft, level, 0.1)


def noise(sigma, amp=1.0, shape=(H, W)):
    n = ndi.gaussian_filter(RNG.standard_normal(shape).astype(np.float32), sigma)
    return n / (n.std() + 1e-6) * amp


def mix(a, b, t):
    """Blend colour arrays/tuples a->b by t (H,W)."""
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    return a + (b - a) * t[..., None]


def over(img, color, alpha):
    """Paint colour (tuple or HxWx3) over img with alpha (HxW)."""
    c = np.asarray(color, np.float32)
    img += (c - img) * alpha[..., None]


def shade(alpha, sigma, light=(-0.6, -0.8), strength=2.2):
    """Lambert-ish lighting of a shape from its blurred height field: 0..1."""
    h = ndi.gaussian_filter(alpha, sigma)
    gy, gx = np.gradient(h)
    lx, ly = light
    lit = -(gx * lx + gy * ly) * sigma * strength
    return np.clip(0.5 + lit, 0, 1)


def disk(r):
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return x * x + y * y <= r * r


def parchment(base=(236, 223, 188)):
    img = np.empty((H, W, 3), np.float32)
    img[:] = base
    img += noise(SCALE * 30, 9)[..., None]
    img += noise(SCALE * 4, 4)[..., None] * np.array([1.0, 0.9, 0.7])
    img += noise(0.7, 2.5)[..., None]
    y, x = np.mgrid[0:H, 0:W]
    d = np.hypot((x - W / 2) / (W / 2), (y - H / 2) / (H / 2))
    img *= (1 - 0.22 * smoothstep(0.55, 1.45, d))[..., None]
    return img


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(
        os.path.join(OUT, name + '.jpg'), quality=92, subsampling=0)


def text_mask(text, font_file, box, italic=False):
    """Render text fitted into box (x0,y0,x1,y1 in Apple pixels): returns (alpha, mask of each glyph start)."""
    x0, y0, x1, y1 = [v * SCALE for v in box]
    size = int((y1 - y0) * 1.5)
    font = ImageFont.truetype(os.path.join(FONTS, font_file), size)
    while True:
        l, t, r, b = font.getbbox(text)
        if r - l <= x1 - x0 and b - t <= (y1 - y0) * 1.35:
            break
        size -= 2
        font = ImageFont.truetype(os.path.join(FONTS, font_file), size)
    im = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(im)
    l, t, r, b = font.getbbox(text)
    ox = x0 + ((x1 - x0) - (r - l)) / 2 - l
    oy = y1 - b + (b - t) * 0.08
    d.text((ox, oy), text, font=font, fill=255)
    first = Image.new('L', (W, H), 0)
    ImageDraw.Draw(first).text((ox, oy), text[0], font=font, fill=255)
    return np.asarray(im, np.float32) / 255, np.asarray(first, np.float32) / 255


# --- the title picture ----------------------------------------------------------------------
def logo():
    A = decode('logo')
    nonwhite = A != WHITE
    green = A == GREEN
    # The dragon is whatever touches its big green areas (the letters have only
    # small green colour fringes).
    glab, gn = ndi.label(green, structure=np.ones((3, 3)))
    gsize = ndi.sum(green, glab, range(1, gn + 1))
    big_green = np.isin(glab, [i + 1 for i, s in enumerate(gsize) if s >= 60])
    lab, n = ndi.label(nonwhite, structure=np.ones((3, 3)))
    dragon = np.isin(lab, list(set(np.unique(lab[big_green])) - {0}))
    green = green & dragon
    # The title was printed over the wing tip, leaving a white box; mend the wing.
    box = np.zeros_like(green)
    box[74:100, 118:170] = True
    mended = ndi.binary_fill_holes(ndi.binary_closing(green, disk(6))) & box & ~green
    notch = np.zeros_like(green)
    notch[80:97, 149:157] = True            # the white box itself
    mended |= notch & (A == WHITE)
    green = green | mended
    dragon = dragon | mended
    body = ndi.binary_fill_holes(dragon)
    # tidy the hi-res dither: tiny specks of anything become hide
    green = ndi.binary_opening(green, np.ones((2, 2))) | (ndi.binary_closing(green, disk(1)) & green)
    belly = ndi.binary_fill_holes(ndi.binary_closing(body & (A == WHITE) & ~green, disk(2))) & body
    belly = ndi.binary_opening(belly, disk(1))
    flame = (A == ORANGE) & body
    head = np.zeros_like(flame)
    head[0:30, 180:262] = True
    flame = ndi.binary_opening(flame | ndi.binary_closing(flame, disk(1)), np.ones((1, 2))) & head
    eye = flame.copy()
    eye[15:, :] = False                     # the eye is the orange spot high on the head
    flame = flame & ~eye

    img = parchment()

    # soft shadow of the dragon on the parchment
    a_body = up(body, 0.6, tall=1.6)
    sh = ndi.gaussian_filter(np.roll(np.roll(a_body, SCALE * 3, 0), SCALE * 2, 1), SCALE * 3)
    img *= (1 - 0.28 * sh)[..., None]

    # outline / dark hide
    over(img, (18, 34, 20), a_body)

    # green scales, lit from the upper left
    a_green = up(green, 0.55, 0.47, tall=1.6)
    lit = shade(a_green, SCALE * 2.5)
    col = mix((22, 92, 38), (128, 205, 88), lit)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    c = SCALE * 2.1
    v = y / (c * 0.75)
    u = x / c + 0.5 * (np.floor(v) % 2)
    du = u - np.floor(u) - 0.5
    dv = v - np.floor(v)
    arc = np.abs(np.hypot(du, dv * 0.9) - 0.5)
    scales = 1 - 0.22 * (1 - smoothstep(0.0, 0.09, arc))
    col *= scales[..., None]
    col *= (1 + noise(SCALE * 1.2, 0.05))[..., None]
    over(img, col, a_green)

    # belly plates: ivory, rounded across the belly, regular curved seams
    a_belly = up(belly, 0.6, 0.5)
    inner = ndi.distance_transform_edt(a_belly > 0.5)
    roundness = smoothstep(0, SCALE * 3.5, inner)
    plate = SCALE * 4.6
    seam_y = y + 0.9 * SCALE * np.sin((x / W) * 40)          # slight curve
    ph = (seam_y % plate) / plate
    seam = 1 - smoothstep(0.0, 0.16, ph) * smoothstep(1.0, 0.8, ph)
    belly_col = mix((172, 146, 100), (246, 234, 202), roundness * (0.75 + 0.25 * ph))
    belly_col = mix(belly_col, (96, 74, 48), seam * 0.85)
    over(img, belly_col, a_belly)

    # fire in the mouth, and a glowing eye
    a_flame = up(flame, 0.5, 0.4)
    glow = ndi.gaussian_filter(a_flame, SCALE * 4)
    img += (np.array([255, 120, 20]) * np.clip(glow * 1.6, 0, 1)[..., None] * 0.55)
    fl = shade(a_flame, SCALE, (0, -1), 3)
    over(img, mix((200, 30, 10), (255, 214, 80), fl), a_flame)
    a_eye = up(ndi.binary_dilation(eye), 0.4, 0.45)
    img += np.array([255, 200, 40]) * ndi.gaussian_filter(a_eye, SCALE * 2)[..., None] * 0.9
    over(img, (255, 226, 70), a_eye)
    eye_core = up(eye, 0.3, 0.6)
    over(img, (40, 10, 0), eye_core * 0.9)

    # the title, in blackletter, with red initials
    ink = (24, 16, 12)
    red = (150, 22, 24)
    for text, box in (('Odyssey: The', (12, 13, 182, 31)),
                      ('Compleat', (40, 46, 152, 63)),
                      ('Apventure', (25, 76, 155, 96))):
        a, first = text_mask(text, 'UnifrakturCook-Bold.ttf', box)
        halo = np.clip(ndi.gaussian_filter(ndi.maximum_filter(a, SCALE * 2), SCALE * 1.5) * 1.6, 0, 1)
        halo *= 1 - a_body                  # (not over the dragon's wing)
        over(img, (238, 226, 192), halo * 0.85)
        over(img, ink, a)
        over(img, red, np.minimum(a, ndi.maximum_filter(first, 3)))
    a, _ = text_mask('by Robert C. Clardy', 'IMFellEnglish-Italic.ttf', (24, 100, 150, 112))
    over(img, (70, 40, 22), a)
    a, _ = text_mask('Copyright © 1980', 'IMFellEnglish-Regular.ttf', (70, 175, 200, 183))
    over(img, (70, 40, 22), a)
    a, _ = text_mask('by Synergistic Software', 'IMFellEnglish-Italic.ttf', (60, 183, 212, 192))
    over(img, (70, 40, 22), a)
    save(img, 'logo')


# --- maps -----------------------------------------------------------------------------------
YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)


def sea(land_alpha, deep=(10, 40, 92), shallow=(34, 132, 160)):
    """Open water: deep far from land, shallow near it, gentle swell and foam."""
    dist = ndi.distance_transform_edt(land_alpha < 0.5) / SCALE      # Apple pixels to land
    depth = smoothstep(0, 14, dist)
    img = mix(shallow, deep, depth)
    swell = np.sin(XX / (SCALE * 3.1) + YY / (SCALE * 5.3) + noise(SCALE * 6, 2.2))
    glint = smoothstep(0.86, 1.0, swell) * (0.25 + 0.75 * noise(SCALE * 2, 0.5) ** 2)
    img += (np.array([40, 60, 70]) * glint[..., None] * 0.5)
    img *= (1 + noise(SCALE * 2.5, 0.04))[..., None]
    foam = smoothstep(1.6, 0.4, dist) * (land_alpha < 0.5)
    img = mix(img, (226, 238, 236), foam * (0.55 + 0.25 * noise(SCALE * 0.8, 1)))
    return img


def land(land_alpha, terrain=None):
    """Land with a sandy rim; `terrain` is an optional HxW 0..2 field (jungle/swamp/mountain)."""
    jungle = np.array([42, 96, 44], np.float32)
    swamp = np.array([84, 92, 52], np.float32)
    rock = np.array([118, 104, 82], np.float32)
    if terrain is None:
        base = np.broadcast_to(jungle, (H, W, 3)).copy()
    else:
        t = terrain
        base = (jungle * np.clip(1 - t, 0, 1)[..., None] + swamp * np.clip(1 - abs(t - 1), 0, 1)[..., None]
                + rock * np.clip(t - 1, 0, 1)[..., None])
    canopy = noise(SCALE * 1.1, 1)
    base *= (1 + 0.13 * canopy + noise(SCALE * 8, 0.06))[..., None]
    base *= (0.85 + 0.3 * shade(land_alpha, SCALE * 6))[..., None]
    inner = ndi.distance_transform_edt(land_alpha > 0.5) / SCALE
    sand = smoothstep(2.2, 0.9, inner)
    sandc = np.array([214, 194, 138]) * (1 + noise(SCALE * 0.7, 0.05))[..., None]
    return mix(base, sandc, sand)


def ridges(img, mask, snow=(244, 244, 240)):
    """Mountain ridge lines: a drop shadow, a rocky flank and a snowy crest."""
    crest = lines(mask, 0.42, 0.28)
    flank = up(ndi.binary_dilation(mask, np.ones((3, 1))), 0.6, 0.35)
    shadow = ndi.gaussian_filter(np.roll(np.roll(flank, SCALE * 2, 0), SCALE, 1), SCALE * 1.2)
    img *= (1 - 0.45 * shadow)[..., None]
    over(img, (128, 112, 92), flank * 0.7)
    lit = shade(crest, SCALE * 0.8, strength=3)
    over(img, mix((150, 150, 160), snow, lit), crest)


def water_lines(img, mask, alpha_soft=0.42):
    mask = ndi.binary_closing(mask, disk(3)) & ndi.binary_dilation(mask, disk(3)) | mask   # join a dotted river up
    a = lines(mask, alpha_soft, 0.3)
    over(img, (36, 120, 170), a)
    over(img, (90, 175, 205), lines(mask, alpha_soft * 0.6, 0.55) * 0.6)


def stream(img, mask, step=3, smooth=5, mouth=None):
    """A river traced through its pixels from west to east as one continuous, widening stroke."""
    ys, xs = np.nonzero(mask)
    if not len(xs):
        return
    pts = []
    for x0 in range(xs.min(), xs.max() + 1, step):
        sel = (xs >= x0) & (xs < x0 + step)
        if sel.any():
            pts.append((x0 + step / 2, ys[sel].mean()))
    pts = np.array(pts)
    k = np.ones(smooth) / smooth
    pts[:, 1] = np.convolve(np.pad(pts[:, 1], smooth // 2, mode='edge'), k, 'valid')
    if mouth is not None:                       # run on into the lake
        ly, lx = np.nonzero(mouth)
        i = np.argmin((lx - pts[-1, 0]) ** 2 + (ly - pts[-1, 1]) ** 2)
        pts = np.vstack([pts, [lx[i] + 1.5, ly[i] + 1.5]])
    im = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(im)
    n = len(pts)
    for i in range(n - 1):
        w = SCALE * (0.9 + 1.1 * i / n)                     # wider downstream
        (x0, y0), (x1, y1) = pts[i] * SCALE, pts[i + 1] * SCALE
        d.line((x0, y0, x1, y1), fill=255, width=int(w))
        d.ellipse((x1 - w / 2, y1 - w / 2, x1 + w / 2, y1 + w / 2), fill=255)
    a = ndi.gaussian_filter(np.asarray(im, np.float32) / 255, SCALE * 0.25)
    bank = ndi.gaussian_filter(ndi.maximum_filter(a, SCALE), SCALE * 0.5)
    img *= (1 - 0.25 * bank)[..., None]
    over(img, (30, 110, 160), a)
    over(img, (110, 190, 215), np.clip(a * 2 - 1.2, 0, 1) * 0.6)


def island_terrain():
    """The island's terrain codes (0 jungle, 1 swamp, 2 mountains) as a smooth field."""
    from odyssey import data
    t = np.zeros((HEIGHT, WIDTH), np.float32)
    for col in range(20):
        for row in range(20):
            v = data.ISLAND_MAP[col * 20 + row + 1] // 10000
            t[row * 8:row * 8 + 8, col * 14:col * 14 + 14] = min(v, 2) if v != 3 else 0
    t = ndi.gaussian_filter(t, 3)
    return ndi.zoom(t, SCALE, order=1)


def island1():
    A = decode('island1')
    A[158:, :] = BLUE                                    # (the caption under the map is never shown)
    blue = A == BLUE
    white = A == WHITE
    fringe = (A != BLACK) & (A != BLUE) & ~white
    ridge = white | fringe | (blue & ndi.binary_dilation(white, np.ones((3, 3))))
    lab, n = ndi.label(blue)
    outer = np.isin(lab, list(set(np.unique(np.r_[lab[0], lab[-1], lab[:, 0], lab[:, -1]])) - {0}))
    inland_water = blue & ~outer & ~ridge
    land_mask = ~outer
    a_land = up(land_mask, 0.8, tall=1.4)
    img = sea(a_land)
    over(img, land(a_land, island_terrain()), a_land)
    lake = ndi.binary_opening(inland_water, disk(2))
    river = inland_water & ~ndi.binary_dilation(lake, disk(3))
    stream(img, river, mouth=lake)
    a_lake = up(lake, 0.7)
    over(img, mix((34, 132, 160), (22, 90, 140), smoothstep(0, SCALE * 6, ndi.distance_transform_edt(a_lake > 0.5))), a_lake)
    ridges(img, ridge)
    save(img, 'island1')


def seamap():
    A = decode('seamap')
    compass = np.zeros((HEIGHT, WIDTH), bool)
    compass[108:160, 0:56] = True
    green = (A == GREEN) & ~compass
    reef = (A == ORANGE) & ~compass
    green = ndi.binary_opening(green, np.ones((2, 2))) | ndi.binary_closing(green, disk(1)) & green
    a_land = up(green, 0.8, tall=1.4)
    a_reef = up(ndi.binary_dilation(reef, np.ones((2, 2))), 0.5, 0.45)
    img = sea(np.maximum(a_land, a_reef * 0.6), deep=(6, 22, 58), shallow=(22, 96, 132))
    hills = shade(a_land, SCALE * 4)
    over(img, land(a_land) * (0.8 + 0.4 * hills)[..., None], a_land)
    over(img, mix((90, 60, 40), (176, 140, 100), shade(a_reef, SCALE)), a_reef)
    compass_rose(img, cx=28.5, cy=134.5, r=20)
    save(img, 'seamap')


def compass_rose(img, cx, cy, r):
    """A drawn compass rose with its four letters (replacing the hi-res one)."""
    cx, cy, r = cx * SCALE, cy * SCALE, r * SCALE
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    gold, dark, light = (214, 180, 96, 255), (90, 64, 30, 255), (246, 230, 180, 255)
    d.ellipse((cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55), outline=gold, width=SCALE)
    import math
    for k in range(8):
        ang = k * math.pi / 4 - math.pi / 2
        long = r * (0.95 if k % 2 == 0 else 0.55)
        wid = r * (0.16 if k % 2 == 0 else 0.11)
        tip = (cx + long * math.cos(ang), cy + long * math.sin(ang))
        l = (cx + wid * math.cos(ang - math.pi / 2), cy + wid * math.sin(ang - math.pi / 2))
        rr = (cx + wid * math.cos(ang + math.pi / 2), cy + wid * math.sin(ang + math.pi / 2))
        d.polygon([(cx, cy), l, tip], fill=light)
        d.polygon([(cx, cy), rr, tip], fill=gold if k % 2 == 0 else dark)
    font = ImageFont.truetype(os.path.join(FONTS, 'IMFellEnglish-Regular.ttf'), int(r * 0.42))
    for letter, (dx, dy) in (('N', (0, -1)), ('S', (0, 1)), ('E', (1, 0)), ('W', (-1, 0))):
        x, y = cx + dx * r * 1.18, cy + dy * r * 1.18
        d.text((x, y), letter, font=font, fill=light, anchor='mm', stroke_width=SCALE // 2, stroke_fill=dark)
    rgba = np.asarray(im, np.float32)
    a = rgba[..., 3] / 255
    shadow = ndi.gaussian_filter(np.roll(np.roll(a, SCALE, 0), SCALE, 1), SCALE)
    img *= (1 - 0.5 * shadow)[..., None]
    over(img, rgba[..., :3], a)


def island2():
    A = decode('island2')
    blue = A == BLUE
    lab, n = ndi.label(blue)
    outer = np.isin(lab, list(set(np.unique(np.r_[lab[0], lab[-1], lab[:, 0], lab[:, -1]])) - {0}))
    land_mask = ~outer
    ship = np.zeros_like(blue)
    ship[136:156, 168:205] = True
    ship &= (A != BLUE)
    land_mask &= ~ship
    land_mask = ndi.binary_fill_holes(ndi.binary_closing(land_mask, disk(1)))
    a_land = up(land_mask, 0.8, tall=1.4)
    img = sea(a_land)
    over(img, land(a_land), a_land)
    castle_box = np.zeros_like(blue)
    castle_box[20:74, 146:194] = True
    river = blue & ~outer & ~castle_box
    water_lines(img, river)
    # mountains
    trees = (A == GREEN) & ~castle_box
    trunks = (A == WHITE) & ndi.binary_dilation(trees, np.ones((7, 3))) & ~castle_box
    mountains = (A == WHITE) & ~castle_box & ~ship & ~trunks
    mountains |= ((A == ORANGE) | (A == VIOLET)) & ~castle_box & ~ship & land_mask
    ridges(img, mountains)
    # trees: shaded foliage with trunks
    a_tree = up(trees, 0.42, 0.42)
    tlit = shade(a_tree, SCALE * 1.2, strength=3)
    tshadow = ndi.gaussian_filter(np.roll(np.roll(a_tree, SCALE * 2, 0), SCALE * 2, 1), SCALE)
    img *= (1 - 0.4 * tshadow)[..., None]
    over(img, mix((20, 70, 30), (110, 190, 80), tlit) * (1 + noise(SCALE * 0.6, 0.08))[..., None], a_tree)
    over(img, (92, 64, 40), up(trunks, 0.35, 0.4))
    castle(img)
    # the ship at anchor
    a_ship = up(ship & (A == WHITE), 0.4, 0.4)
    over(img, mix((150, 140, 120), (250, 246, 236), shade(a_ship, SCALE, strength=3)), a_ship)
    save(img, 'island2')


def castle(img):
    """The Caliph's fortress, drawn afresh in the footprint of the hi-res one."""
    S = SCALE

    def P(*pts):
        return [(x * S, y * S) for x, y in pts]

    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    stone, dark, slate, wood = (178, 170, 156, 255), (70, 64, 60, 255), (60, 58, 80, 255), (92, 58, 34, 255)
    d.polygon(P((150, 71), (194, 71), (191, 74), (152, 74)), fill=(110, 98, 84, 255))       # rocky footing
    d.polygon(P((149, 70), (149, 56), (153, 51), (156, 51), (156, 70)), fill=stone)      # buttress
    d.rectangle(P((155, 46), (176, 70)), fill=stone)                                     # keep
    for x0 in (155, 160.5, 166, 171.5):                                                  # merlons
        d.rectangle(P((x0, 42), (x0 + 3.5, 46)), fill=stone)
    d.rectangle(P((179, 40), (188, 70)), fill=stone)                                     # tower
    d.rectangle(P((176, 56), (179, 70)), fill=stone)                                     # curtain
    d.polygon(P((177, 41), (190, 41), (183.5, 30)), fill=slate)                          # roof
    d.line(P((183.5, 31), (183.5, 22)), fill=dark, width=S // 2)                        # flagpole
    d.polygon(P((183.5, 22), (175, 24.5), (183.5, 27)), fill=(170, 30, 30, 255))         # pennant
    d.rectangle(P((161, 49), (164, 54)), fill=dark)                                      # window
    d.rectangle(P((183, 47), (185, 52)), fill=dark)
    d.ellipse(P((164, 59), (175, 67)), fill=wood)                                        # gate
    d.rectangle(P((164, 63), (175, 70)), fill=wood)
    d.line(P((169.5, 60), (169.5, 70)), fill=dark, width=max(1, S // 3))
    rgba = np.asarray(im, np.float32)
    a = ndi.gaussian_filter(rgba[..., 3] / 255, 0.6)
    col = rgba[..., :3]
    # light from the upper left, mortar courses, weathering
    lit = shade(a, S * 1.5, strength=2.5)
    course = (YY / S) % 2.5
    mortar = 1 - 0.22 * (1 - smoothstep(0.0, 0.35, course))
    is_stone = (np.abs(col - np.array(stone[:3])).sum(-1) < 30)
    col = col * np.where(is_stone, mortar, 1)[..., None] * (0.8 + 0.4 * lit)[..., None]
    col *= (1 + noise(S * 0.8, 0.05))[..., None]
    shadow = ndi.gaussian_filter(np.roll(np.roll(a, S * 3, 0), S * 2, 1), S * 1.5)
    img *= (1 - 0.45 * shadow)[..., None]
    over(img, col, a)


PICTURES = {'logo': logo, 'island1': island1, 'seamap': seamap, 'island2': island2}

if __name__ == '__main__':
    for name in sys.argv[1:] or PICTURES:
        print('painting', name)
        PICTURES[name]()
