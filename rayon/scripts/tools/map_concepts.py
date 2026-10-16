#!/usr/bin/env python3
"""Draws original top-down concept maps for RAYON (several layouts).

    python3 scripts/tools/map_concepts.py docs/maps

Each variant is described by land blobs, water features, roads, districts and
labels in normalised coordinates (0..1). Rendering: noise-shaped land with
hill shading, beaches, shallow water glow, forests, city blocks with buildings,
roads with outlines, bridges, landmarks, labels, legend and compass.
"""
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1100, 1500          # final size
S = 2                      # supersampling
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_I = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-BoldItalic.ttf"
if not Path(FONT_I).exists():
    FONT_I = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def font(size, italic=False):
    return ImageFont.truetype(FONT_I if italic else FONT_B, size * S)


# --- noise -------------------------------------------------------------------

def value_noise(w, h, cells, rng):
    g = rng.random((cells + 1, cells + 1))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def fbm(w, h, rng, octaves=5, base=4):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(w, h, base * 2 ** o, rng) * amp
        tot += amp
        amp *= 0.5
    return out / tot


# --- geometry helpers ------------------------------------------------------------

def P(pt):
    return (pt[0] * W * S, pt[1] * H * S)


def chaikin(pts, it=3):
    pts = [tuple(p) for p in pts]
    for _ in range(it):
        out = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
            out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
        out.append(pts[-1])
        pts = out
    return pts


def closed_chaikin(pts, it=3):
    pts = [tuple(p) for p in pts]
    for _ in range(it):
        out = []
        n = len(pts)
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
            out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
        pts = out
    return pts


def ellipse_pts(cx, cy, rx, ry, n=48, start=0.0, end=math.tau):
    return [(cx + math.cos(start + (end - start) * i / n) * rx, cy + math.sin(start + (end - start) * i / n) * ry) for i in range(n + 1)]


def point_in_poly(x, y, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


# --- palette -----------------------------------------------------------------------

DEEP = np.array([22, 70, 120], np.float32)
SEA = np.array([38, 112, 168], np.float32)
SHALLOW = np.array([70, 170, 196], np.float32)
SAND = np.array([226, 206, 150], np.float32)
GRASS_LO = np.array([128, 176, 82], np.float32)
GRASS_HI = np.array([96, 146, 64], np.float32)
ROCK = np.array([150, 128, 108], np.float32)
SNOW = np.array([238, 240, 244], np.float32)
ROAD = (122, 124, 130)
ROAD_EDGE = (62, 64, 70)
ROAD_LINE = (236, 232, 214)
CITY_GROUND = (170, 168, 162)
LABEL = (255, 255, 255)
STROKE = (32, 30, 34)


class Map:
    def __init__(self, spec):
        self.spec = spec
        self.rng = random.Random(spec["seed"])
        self.nrng = np.random.default_rng(spec["seed"])
        self.w, self.h = W * S, H * S
        self.labels = []

    # -- terrain -------------------------------------------------------------------
    def terrain(self):
        w, h = W // 2, H // 2          # work at half res, upscale later
        ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
        x = xs / w
        y = ys / h
        f = np.full((h, w), -1.0, np.float32)
        for (cx, cy, rx, ry) in self.spec["land"]:
            d = 1.0 - ((x - cx) / rx) ** 2 - ((y - cy) / ry) ** 2
            f = np.maximum(f, d)
        for (cx, cy, rx, ry) in self.spec.get("cut", []):
            d = 1.0 - ((x - cx) / rx) ** 2 - ((y - cy) / ry) ** 2
            f = np.minimum(f, -d * 1.3)
        n = fbm(w, h, self.nrng, 5, 3)
        f = f + (n - 0.5) * self.spec.get("rough", 0.55)
        if self.spec.get("inland"):
            f = np.maximum(f, 0.05 + n * 0.1)
        land = f > 0.0
        # elevation: grows inland plus mountains
        hgt = np.clip(f, 0, None) * 0.5 + fbm(w, h, self.nrng, 4, 6) * 0.35
        for (cx, cy, rx, ry, k) in self.spec.get("mountains", []):
            d = np.clip(1.0 - ((x - cx) / rx) ** 2 - ((y - cy) / ry) ** 2, 0, None)
            hgt += d * k * (0.7 + fbm(w, h, self.nrng, 3, 10) * 0.6)
        self.land_small = land
        self.hgt_small = hgt
        return land, hgt

    def render_base(self):
        land, hgt = self.terrain()
        h, w = land.shape
        # distance-ish field from blurred mask
        m = Image.fromarray((land * 255).astype(np.uint8))
        near = np.asarray(m.filter(ImageFilter.GaussianBlur(14)), np.float32) / 255.0
        far = np.asarray(m.filter(ImageFilter.GaussianBlur(60)), np.float32) / 255.0
        img = np.zeros((h, w, 3), np.float32)
        # water
        t = np.clip(far * 2.2, 0, 1)[..., None]
        water = DEEP * (1 - t) + SEA * t
        sh = np.clip((near - 0.05) * 2.4, 0, 1)[..., None]
        water = water * (1 - sh) + SHALLOW * sh
        # waves sparkle
        wn = fbm(w, h, self.nrng, 3, 40)
        water += ((wn > 0.62) * 10)[..., None]
        # land colours with hill shading
        gy, gx = np.gradient(hgt)
        shade = np.clip(0.75 + (-gx * 0.7 - gy * 0.7) * 30.0, 0.45, 1.25)[..., None]
        gn = fbm(w, h, self.nrng, 4, 12)[..., None]
        grass = GRASS_LO * (1 - gn) + GRASS_HI * gn
        hh = hgt[..., None]
        rock_t = np.clip((hh - 0.85) * 3.0, 0, 1)
        snow_t = np.clip((hh - 1.6) * 3.0, 0, 1)
        ground = grass * (1 - rock_t) + ROCK * rock_t
        ground = ground * (1 - snow_t) + SNOW * snow_t
        ground = ground * shade
        # contour lines on hills
        bands = (np.abs(((hgt * 9.0) % 1.0) - 0.5) < 0.04) & (hgt > 0.45)
        ground[bands] *= 0.88
        # beach
        edge = np.asarray(m.filter(ImageFilter.GaussianBlur(4)), np.float32) / 255.0
        beach = ((edge < 0.88) & land & (not self.spec.get("inland")))[..., None]
        ground = np.where(beach, SAND * shade * 0.5 + SAND * 0.5, ground)
        img = np.where(land[..., None], ground, water)
        base = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((self.w, self.h), Image.BICUBIC)
        self.img = base
        self.d = ImageDraw.Draw(self.img)
        self.land_big = np.asarray(Image.fromarray((land * 255).astype(np.uint8)).resize((W, H), Image.NEAREST)) > 127
        self.hgt_big = np.asarray(Image.fromarray(np.clip(hgt * 120, 0, 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)) / 120.0

    def is_land(self, x, y):
        xi = int(min(max(x, 0), 0.999) * W)
        yi = int(min(max(y, 0), 0.999) * H)
        return bool(self.land_big[yi, xi])

    def height(self, x, y):
        xi = int(min(max(x, 0), 0.999) * W)
        yi = int(min(max(y, 0), 0.999) * H)
        return float(self.hgt_big[yi, xi])

    # -- water features drawn on land -------------------------------------------------
    def river(self, pts, width):
        sp = [P(p) for p in chaikin(pts, 4)]
        self.d.line(sp, fill=(52, 138, 186), width=int(width * S * 1.25), joint="curve")
        self.d.line(sp, fill=(66, 156, 200), width=int(width * S), joint="curve")

    def lake(self, poly):
        sp = [P(p) for p in closed_chaikin(poly, 3)]
        self.d.polygon(sp, fill=(226, 206, 150))
        inner = [((x - c[0]) * 0.94 + c[0], (y - c[1]) * 0.94 + c[1]) for (x, y), c in zip(sp, [self._centroid(sp)] * len(sp))]
        self.d.polygon(inner, fill=(60, 150, 196))

    @staticmethod
    def _centroid(pts):
        return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))

    # -- vegetation -----------------------------------------------------------------------
    def forest(self, cx, cy, r, n):
        for _ in range(n):
            a = self.rng.random() * math.tau
            d = math.sqrt(self.rng.random()) * r
            x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * 1.1
            if not self.is_land(x, y) or self.height(x, y) > 1.2:
                continue
            rr = self.rng.uniform(4, 8) * S
            px, py = P((x, y))
            self.d.ellipse((px - rr + 2 * S, py - rr + 3 * S, px + rr + 2 * S, py + rr + 3 * S), fill=(40, 70, 36))
            g = self.rng.randint(0, 30)
            self.d.ellipse((px - rr, py - rr, px + rr, py + rr), fill=(48 + g, 104 + g, 46 + g // 2))
            self.d.ellipse((px - rr * 0.45, py - rr * 0.7, px + rr * 0.15, py - rr * 0.1), fill=(84 + g, 140 + g, 70))

    def scatter_trees(self, n):
        for _ in range(n):
            x, y = self.rng.random(), self.rng.random()
            if self.is_land(x, y) and 0.35 < self.height(x, y) < 1.0 and not self._in_city(x, y):
                self.forest(x, y, 0.004, 2)

    # -- districts --------------------------------------------------------------------------
    def _in_city(self, x, y):
        for c in self.spec.get("cities", []):
            if point_in_poly(x, y, c["poly"]):
                return True
        return False

    def city(self, poly, angle=0.0, block=0.045, kind="city"):
        sp = [P(p) for p in poly]
        self.d.polygon(sp, fill=CITY_GROUND if kind == "city" else (152, 150, 146))
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        span = max(max(xs) - min(xs), max(ys) - min(ys)) * 0.8
        ca, sa = math.cos(angle), math.sin(angle)
        n = int(span / block) + 2
        streets = []
        for i in range(-n, n + 1):
            for j in range(-n, n + 1):
                u, v = i * block, j * block
                bx = cx + u * ca - v * sa
                by = cy + u * sa + v * ca
                if not point_in_poly(bx, by, poly):
                    continue
                self._block(bx, by, block * 0.78, angle, kind)
        # outline street around the district
        self.d.line(sp + [sp[0]], fill=ROAD_EDGE, width=7 * S, joint="curve")
        self.d.line(sp + [sp[0]], fill=ROAD, width=5 * S, joint="curve")

    def _block(self, bx, by, size, angle, kind):
        ca, sa = math.cos(angle), math.sin(angle)

        def rect(u0, v0, u1, v1):
            pts = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
            return [P((bx + u * ca - v * sa, by + u * sa + v * ca)) for u, v in pts]

        h = size / 2
        self.d.polygon(rect(-h, -h, h, h), fill=(196, 194, 186))
        r = self.rng.random()
        if kind == "city" and r < 0.08:
            # little park
            self.d.polygon(rect(-h * 0.9, -h * 0.9, h * 0.9, h * 0.9), fill=(120, 172, 86))
            for _ in range(5):
                u = self.rng.uniform(-h * 0.7, h * 0.7)
                v = self.rng.uniform(-h * 0.7, h * 0.7)
                px, py = P((bx + u * ca - v * sa, by + u * sa + v * ca))
                rr = 4 * S
                self.d.ellipse((px - rr, py - rr, px + rr, py + rr), fill=(62, 120, 54))
            return
        nb = self.rng.randint(1, 4)
        cols = [(236, 232, 222), (226, 212, 186), (214, 214, 214), (232, 200, 176), (206, 218, 226), (230, 214, 150)]
        if kind == "industry":
            cols = [(176, 180, 186), (150, 156, 164), (190, 186, 170)]
        for k in range(nb):
            if nb == 1:
                u0, v0, u1, v1 = -h * 0.85, -h * 0.85, h * 0.85, h * 0.85
            else:
                q = k % 4
                su = -1 if q in (0, 3) else 1
                sv = -1 if q < 2 else 1
                u0, u1 = sorted((su * h * 0.08, su * h * self.rng.uniform(0.6, 0.9)))
                v0, v1 = sorted((sv * h * 0.08, sv * h * self.rng.uniform(0.6, 0.9)))
            col = self.rng.choice(cols)
            sh = 0.012 * (1.6 if kind == "industry" else 1.0)
            self.d.polygon(rect(u0 + sh * 0.6, v0 + sh, u1 + sh * 0.6, v1 + sh), fill=(98, 96, 96))
            self.d.polygon(rect(u0, v0, u1, v1), fill=col, outline=(70, 70, 74), width=S)
            if self.rng.random() < 0.4:
                m = (u1 - u0) * 0.25
                self.d.polygon(rect(u0 + m, v0 + m, u1 - m, v1 - m), fill=tuple(int(c * 0.9) for c in col))

    def village(self, cx, cy, r, n):
        for _ in range(n):
            a = self.rng.random() * math.tau
            d = math.sqrt(self.rng.random()) * r
            x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
            if not self.is_land(x, y):
                continue
            px, py = P((x, y))
            s = self.rng.uniform(5, 8) * S
            ang = self.rng.random() * math.pi
            pts = [(px + math.cos(ang + t) * s * (1.4 if i % 2 == 0 else 1.0), py + math.sin(ang + t) * s * (1.4 if i % 2 == 0 else 1.0)) for i, t in enumerate([0.6, 2.5, 3.7, 5.6])]
            self.d.polygon([(x2 + 3 * S, y2 + 3 * S) for x2, y2 in pts], fill=(90, 80, 70))
            self.d.polygon(pts, fill=self.rng.choice([(186, 92, 62), (166, 78, 54), (204, 120, 80), (150, 96, 70)]), outline=(70, 50, 40))

    # -- roads ------------------------------------------------------------------------------
    def road(self, pts, kind="main", smooth=3):
        sp = [P(p) for p in chaikin(pts, smooth)]
        widths = {"hw": (15, 11), "main": (11, 8), "small": (8, 5), "dirt": (6, 4)}
        wo, wi = widths[kind]
        fill = ROAD if kind != "dirt" else (176, 156, 120)
        edge = ROAD_EDGE if kind != "dirt" else (120, 104, 80)
        self.d.line(sp, fill=edge, width=wo * S, joint="curve")
        for p in (sp[0], sp[-1]):
            r = wo * S / 2
            self.d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=edge)
        self.d.line(sp, fill=fill, width=wi * S, joint="curve")
        for p in (sp[0], sp[-1]):
            r = wi * S / 2
            self.d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=fill)
        if kind == "hw":
            self._dashes(sp)
        return sp

    def _dashes(self, sp):
        acc = 0.0
        on = True
        for a, b in zip(sp[:-1], sp[1:]):
            seg = math.dist(a, b)
            if on:
                self.d.line([a, b], fill=ROAD_LINE, width=2 * S)
            acc += seg
            if acc > 9 * S:
                acc = 0.0
                on = not on

    def bridge(self, a, b):
        pa, pb = P(a), P(b)
        self.d.line([pa, pb], fill=(70, 66, 64), width=18 * S)
        self.d.line([pa, pb], fill=(200, 196, 186), width=14 * S)
        self.d.line([pa, pb], fill=ROAD, width=10 * S)
        self._dashes([pa, pb])

    # -- landmarks ---------------------------------------------------------------------------
    def drift_pad(self, x, y, w, h):
        a, b = P((x - w / 2, y - h / 2)), P((x + w / 2, y + h / 2))
        self.d.rounded_rectangle((a[0], a[1], b[0], b[1]), radius=14 * S, fill=(84, 86, 92), outline=(50, 50, 56), width=3 * S)
        for i in range(2):
            cx = x - w / 4 + i * w / 2
            c = P((cx, y))
            r = min(w, h) * 0.32 * W * S
            for k in range(24):
                if k % 2 == 0:
                    a0 = k / 24 * 360
                    self.d.arc((c[0] - r, c[1] - r, c[0] + r, c[1] + r), a0, a0 + 15, fill=(242, 196, 78), width=2 * S)
            for k in range(6):
                ang = self.rng.random() * math.tau
                rr = r * self.rng.uniform(0.3, 0.9)
                self.d.arc((c[0] - rr, c[1] - rr * 0.8, c[0] + rr, c[1] + rr * 0.8), math.degrees(ang), math.degrees(ang) + 120, fill=(40, 40, 44), width=2 * S)

    def race_track(self, pts):
        sp = [P(p) for p in closed_chaikin(pts, 3)]
        sp.append(sp[0])
        self.d.line(sp, fill=(200, 60, 60), width=16 * S, joint="curve")
        self.d.line(sp, fill=(240, 240, 236), width=13 * S, joint="curve")
        self.d.line(sp, fill=(90, 92, 98), width=10 * S, joint="curve")
        a = sp[0]
        self.d.rectangle((a[0] - 6 * S, a[1] - 6 * S, a[0] + 6 * S, a[1] + 6 * S), fill=(255, 255, 255), outline=(0, 0, 0), width=S)

    def stadium(self, x, y, rx, ry):
        a, b = P((x - rx, y - ry)), P((x + rx, y + ry))
        self.d.ellipse((a[0], a[1], b[0], b[1]), fill=(198, 102, 72), outline=(120, 70, 50), width=2 * S)
        m = 0.012 * W * S
        self.d.ellipse((a[0] + m, a[1] + m, b[0] - m, b[1] - m), fill=(96, 162, 80))
        c = P((x, y))
        self.d.rectangle((c[0] - rx * W * S * 0.55, c[1] - ry * H * S * 0.45, c[0] + rx * W * S * 0.55, c[1] + ry * H * S * 0.45), outline=(240, 240, 240), width=S)
        self.d.line((c[0], c[1] - ry * H * S * 0.45, c[0], c[1] + ry * H * S * 0.45), fill=(240, 240, 240), width=S)

    def airport(self, x, y, length, angle):
        ca, sa = math.cos(angle), math.sin(angle)

        def tp(u, v):
            return P((x + u * ca - v * sa, y + u * sa + v * ca))
        hw = 0.012
        self.d.polygon([tp(-length / 2, -hw * 3), tp(length / 2, -hw * 3), tp(length / 2, hw * 3), tp(-length / 2, hw * 3)], fill=(150, 168, 120))
        self.d.polygon([tp(-length / 2, -hw), tp(length / 2, -hw), tp(length / 2, hw), tp(-length / 2, hw)], fill=(70, 72, 78))
        for i in range(14):
            u = -length / 2 + (i + 0.5) * length / 14
            self.d.line([tp(u - 0.008, 0), tp(u + 0.008, 0)], fill=(240, 240, 236), width=2 * S)
        self.d.polygon([tp(-0.06, hw * 4), tp(0.06, hw * 4), tp(0.06, hw * 7), tp(-0.06, hw * 7)], fill=(200, 202, 206), outline=(80, 80, 84))

    def docks(self, x, y, n, dx, dy):
        for i in range(n):
            a = (x + i * dx, y + i * dy)
            b = (a[0] - dy * 3.5, a[1] + dx * 3.5) if abs(dx) > abs(dy) else (a[0] - 0.05, a[1])
            pa, pb = P(a), P(b)
            self.d.line([pa, pb], fill=(110, 90, 66), width=7 * S)
            self.d.line([pa, pb], fill=(170, 140, 100), width=5 * S)

    def power_plant(self, x, y):
        c = P((x, y))
        s = 0.035 * W * S
        self.d.rectangle((c[0] - s, c[1] - s * 0.8, c[0] + s, c[1] + s * 0.8), fill=(140, 144, 150), outline=(60, 60, 64), width=2 * S)
        for i in range(3):
            px = c[0] - s * 0.6 + i * s * 0.6
            r = s * 0.22
            self.d.ellipse((px - r, c[1] - r, px + r, c[1] + r), fill=(210, 210, 214), outline=(70, 70, 74), width=2 * S)
            self.d.ellipse((px - r * 0.5, c[1] - r * 0.5, px + r * 0.5, c[1] + r * 0.5), fill=(90, 92, 96))

    def lighthouse(self, x, y):
        c = P((x, y))
        r = 7 * S
        self.d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=(245, 245, 245), outline=(200, 40, 40), width=3 * S)
        self.d.ellipse((c[0] - r * 0.4, c[1] - r * 0.4, c[0] + r * 0.4, c[1] + r * 0.4), fill=(255, 210, 60))

    def dam(self, a, b):
        pa, pb = P(a), P(b)
        self.d.line([pa, pb], fill=(110, 110, 112), width=14 * S)
        self.d.line([pa, pb], fill=(196, 196, 198), width=9 * S)

    # -- labels -------------------------------------------------------------------------------
    def label(self, x, y, text, size=26, icon=None, color=LABEL, italic=True):
        self.labels.append((x, y, text, size, icon, color, italic))

    def draw_labels(self):
        for (x, y, text, size, icon, color, italic) in self.labels:
            px, py = P((x, y))
            f = font(size, italic)
            if icon:
                r = 16 * S
                ix = px - r - 8 * S
                self.d.ellipse((ix - r, py - r, ix + r, py + r), fill=icon[1], outline=STROKE, width=3 * S)
                fi = font(15)
                self.d.text((ix, py), icon[0], font=fi, fill=(255, 255, 255), anchor="mm", stroke_width=2 * S, stroke_fill=STROKE)
                self.d.text((px, py), text, font=f, fill=color, anchor="lm", stroke_width=4 * S, stroke_fill=STROKE)
            else:
                self.d.text((px, py), text, font=f, fill=color, anchor="mm", stroke_width=4 * S, stroke_fill=STROKE)

    def compass(self, x, y):
        c = P((x, y))
        r = 46 * S
        self.d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), outline=(30, 30, 34), width=2 * S)
        for k, ang in enumerate([-90, 0, 90, 180]):
            a = math.radians(ang)
            tip = (c[0] + math.cos(a) * r * 1.1, c[1] + math.sin(a) * r * 1.1)
            l = (c[0] + math.cos(a + 2.6) * r * 0.25, c[1] + math.sin(a + 2.6) * r * 0.25)
            rr = (c[0] + math.cos(a - 2.6) * r * 0.25, c[1] + math.sin(a - 2.6) * r * 0.25)
            self.d.polygon([tip, l, c], fill=(30, 30, 34))
            self.d.polygon([tip, rr, c], fill=(240, 240, 240), outline=(30, 30, 34))
        f = font(16)
        for t, ang in (("С", -90), ("В", 0), ("Ю", 90), ("З", 180)):
            a = math.radians(ang)
            self.d.text((c[0] + math.cos(a) * r * 1.45, c[1] + math.sin(a) * r * 1.45), t, font=f, fill=(255, 255, 255), anchor="mm", stroke_width=3 * S, stroke_fill=STROKE)

    def title(self, name, sub):
        self._title = (name, sub)

    def draw_title(self):
        name, sub = self._title
        self.d.rounded_rectangle((24 * S, 22 * S, 520 * S, 112 * S), radius=14 * S, fill=(20, 22, 28))
        self.d.text((44 * S, 44 * S), name, font=font(40, True), fill=(255, 255, 255), anchor="lt")
        self.d.text((46 * S, 92 * S), sub, font=font(16), fill=(143, 216, 208), anchor="lm")

    def finish(self, path, items):
        band = 120
        img = Image.new("RGB", (W * S, (H + band) * S), (20, 22, 28))
        img.paste(self.img, (0, 0))
        d = ImageDraw.Draw(img)
        f = font(17)
        cols = 4
        for i, (sym, col, text) in enumerate(items):
            x = (24 + (i % cols) * 268) * S
            y = (H + 34 + (i // cols) * 46) * S
            r = 13 * S
            d.ellipse((x, y - r, x + 2 * r, y + r), fill=col, outline=(255, 255, 255), width=2 * S)
            d.text((x + r, y), sym, font=font(13), fill=(255, 255, 255), anchor="mm")
            d.text((x + 2 * r + 12 * S, y), text, font=f, fill=(235, 235, 235), anchor="lm")
        img.resize((W, H + band), Image.LANCZOS).save(path, optimize=True)


ICONS = {
    "garage": ("G", (232, 168, 40)), "gas": ("А", (210, 60, 50)), "shop": ("М", (40, 150, 140)),
    "police": ("П", (40, 80, 180)), "drift": ("Д", (120, 60, 160)), "race": ("К", (200, 60, 60)),
    "port": ("⚓", (40, 90, 140)), "power": ("Э", (230, 190, 30)), "air": ("✈", (90, 110, 130)),
    "hide": ("У", (60, 60, 60)), "bazar": ("Б", (190, 110, 40)),
}

LEGEND = [
    ("G", ICONS["garage"][1], "Гараж, тюнинг"), ("А", ICONS["gas"][1], "АЗС"),
    ("Б", ICONS["bazar"][1], "Базар"), ("П", ICONS["police"][1], "Полиция"),
    ("Д", ICONS["drift"][1], "Дрифт-площадка"), ("К", ICONS["race"][1], "Кольцевая гонка"),
    ("У", ICONS["hide"][1], "Укрытие от погони"), ("⚓", ICONS["port"][1], "Порт"),
]


# --- variants ----------------------------------------------------------------------------------

def variant_a(m: Map):
    """Подкова: остров-«C», залив открыт на восток, город на западном берегу."""
    m.title("ПОДКОВА", "вариант A · остров с заливом на восток")
    m.render_base()
    m.lake([(0.36, 0.30), (0.46, 0.27), (0.50, 0.34), (0.44, 0.40), (0.36, 0.38)])
    m.river([(0.40, 0.33), (0.36, 0.45), (0.30, 0.52)], 7)
    for (x, y, r, n) in [(0.62, 0.17, 0.08, 120), (0.30, 0.18, 0.06, 90), (0.72, 0.83, 0.06, 70), (0.23, 0.36, 0.05, 60)]:
        m.forest(x, y, r, n)
    city = [(0.12, 0.47), (0.36, 0.45), (0.44, 0.54), (0.42, 0.72), (0.18, 0.74), (0.10, 0.62)]
    m.city(city, 0.18, 0.04)
    ind = [(0.44, 0.78), (0.62, 0.76), (0.66, 0.90), (0.46, 0.92)]
    m.city(ind, -0.05, 0.05, "industry")
    # coastal ring
    ring = [(0.16, 0.44), (0.12, 0.30), (0.20, 0.14), (0.38, 0.07), (0.60, 0.07), (0.80, 0.14), (0.88, 0.26), (0.82, 0.34), (0.64, 0.33)]
    m.road(ring, "hw")
    m.road([(0.16, 0.44), (0.08, 0.60), (0.14, 0.80), (0.30, 0.90), (0.46, 0.94), (0.68, 0.93), (0.84, 0.85), (0.86, 0.72), (0.70, 0.66), (0.58, 0.66)], "hw")
    m.road([(0.36, 0.45), (0.55, 0.40), (0.64, 0.33)], "main")
    m.road([(0.42, 0.62), (0.58, 0.66)], "main")
    m.road([(0.30, 0.74), (0.44, 0.84)], "main")
    m.road([(0.36, 0.30), (0.30, 0.22), (0.46, 0.16), (0.56, 0.24), (0.50, 0.30)], "dirt")
    m.road([(0.70, 0.14), (0.66, 0.24), (0.74, 0.28)], "small")
    m.bridge((0.64, 0.335), (0.70, 0.66))
    m.drift_pad(0.76, 0.76, 0.12, 0.06)
    m.race_track([(0.52, 0.12), (0.68, 0.11), (0.74, 0.20), (0.62, 0.26), (0.52, 0.22)])
    m.power_plant(0.55, 0.86)
    m.docks(0.07, 0.52, 5, 0.0, 0.03)
    m.village(0.80, 0.22, 0.04, 26)
    m.village(0.28, 0.10, 0.04, 18)
    m.stadium(0.24, 0.66, 0.035, 0.022)
    m.lighthouse(0.86, 0.24)
    m.scatter_trees(160)
    m.label(0.26, 0.56, "Центр", 30)
    m.label(0.56, 0.84, "Промзона", 22)
    m.label(0.43, 0.345, "Озеро Сабз", 18, color=(220, 240, 255))
    m.label(0.80, 0.18, "Кишлак Кӯҳ", 20)
    m.label(0.64, 0.50, "Залив", 30, color=(220, 240, 255))
    m.label(0.30, 0.48, "Гараж", 18, ICONS["garage"])
    m.label(0.20, 0.70, "Базар", 18, ICONS["bazar"])
    m.label(0.36, 0.66, "Полиция", 18, ICONS["police"])
    m.label(0.80, 0.70, "Дрифт", 18, ICONS["drift"])
    m.label(0.61, 0.07, "Кольцо", 18, ICONS["race"])
    m.label(0.50, 0.96, "АЗС", 18, ICONS["gas"])
    m.label(0.16, 0.52, "Порт", 18, ICONS["port"])
    m.label(0.58, 0.29, "Тоннель-мост", 16, ICONS["hide"])


def variant_b(m: Map):
    """Две реки: материковый район в долине, горы по краям, река делит город."""
    m.title("ДОЛИНА", "вариант B · город у реки, горы вокруг")
    m.render_base()
    m.lake([(0.40, 0.06), (0.62, 0.05), (0.66, 0.12), (0.52, 0.16), (0.40, 0.13)])
    m.dam((0.47, 0.155), (0.57, 0.15))
    m.river([(0.52, 0.15), (0.50, 0.30), (0.56, 0.44), (0.50, 0.60), (0.54, 0.76), (0.48, 0.98)], 14)
    m.river([(0.92, 0.40), (0.76, 0.46), (0.62, 0.50), (0.54, 0.52)], 8)
    west = [(0.16, 0.38), (0.46, 0.36), (0.48, 0.70), (0.30, 0.76), (0.14, 0.66)]
    east = [(0.58, 0.56), (0.84, 0.56), (0.86, 0.78), (0.60, 0.80)]
    m.city(west, 0.0, 0.042)
    m.city(east, 0.12, 0.05, "industry")
    for (x, y, r, n) in [(0.18, 0.22, 0.07, 110), (0.80, 0.24, 0.07, 110), (0.30, 0.88, 0.06, 90), (0.76, 0.90, 0.06, 80)]:
        m.forest(x, y, r, n)
    m.road([(0.04, 0.50), (0.16, 0.50), (0.46, 0.52), (0.58, 0.60), (0.96, 0.62)], "hw")
    m.road([(0.30, 0.30), (0.30, 0.76), (0.34, 0.96)], "hw")
    m.road([(0.16, 0.38), (0.12, 0.24), (0.22, 0.14), (0.38, 0.12)], "small")
    m.road([(0.62, 0.14), (0.78, 0.16), (0.88, 0.30), (0.86, 0.48)], "small")
    m.road([(0.46, 0.40), (0.62, 0.42), (0.72, 0.34)], "main")
    m.road([(0.48, 0.70), (0.60, 0.72)], "main")
    m.road([(0.30, 0.76), (0.50, 0.86), (0.70, 0.84), (0.86, 0.78)], "main")
    m.bridge((0.47, 0.52), (0.57, 0.53))
    m.bridge((0.48, 0.71), (0.59, 0.72))
    m.bridge((0.47, 0.40), (0.57, 0.41))
    m.race_track([(0.62, 0.86), (0.82, 0.85), (0.88, 0.94), (0.66, 0.95)])
    m.drift_pad(0.70, 0.68, 0.10, 0.05)
    m.power_plant(0.78, 0.74)
    m.village(0.16, 0.18, 0.05, 30)
    m.village(0.82, 0.30, 0.04, 22)
    m.stadium(0.22, 0.45, 0.035, 0.022)
    m.scatter_trees(180)
    m.label(0.32, 0.58, "Старый город", 26)
    m.label(0.72, 0.62, "Завод", 22)
    m.label(0.53, 0.09, "Водохранилище", 20, color=(220, 240, 255))
    m.label(0.16, 0.12, "Кишлак Варзоб", 20)
    m.label(0.52, 0.96, "Река", 18, color=(220, 240, 255))
    m.label(0.24, 0.40, "Гараж", 18, ICONS["garage"])
    m.label(0.38, 0.66, "Базар", 18, ICONS["bazar"])
    m.label(0.40, 0.46, "Полиция", 18, ICONS["police"])
    m.label(0.74, 0.70, "Дрифт", 18, ICONS["drift"])
    m.label(0.72, 0.82, "Кольцо", 18, ICONS["race"])
    m.label(0.10, 0.54, "АЗС", 18, ICONS["gas"])
    m.label(0.56, 0.34, "Дамба", 16, ICONS["hide"])


def variant_c(m: Map):
    """Полуостров: горы на севере, море на юге и востоке, аэропорт и пляж."""
    m.title("ПОЛУОСТРОВ", "вариант C · горы, пляж и аэропорт")
    m.render_base()
    m.river([(0.30, 0.22), (0.34, 0.40), (0.28, 0.56), (0.32, 0.70)], 8)
    city = [(0.36, 0.48), (0.66, 0.46), (0.70, 0.66), (0.52, 0.74), (0.36, 0.68)]
    m.city(city, -0.3, 0.04)
    old = [(0.12, 0.58), (0.28, 0.58), (0.28, 0.72), (0.14, 0.74)]
    m.city(old, 0.1, 0.04)
    for (x, y, r, n) in [(0.18, 0.40, 0.07, 120), (0.80, 0.34, 0.05, 70), (0.46, 0.34, 0.05, 60)]:
        m.forest(x, y, r, n)
    m.road([(0.02, 0.45), (0.20, 0.50), (0.36, 0.48), (0.52, 0.40), (0.72, 0.42), (0.86, 0.52), (0.90, 0.66)], "hw")
    m.road([(0.06, 0.82), (0.24, 0.78), (0.40, 0.76), (0.52, 0.74), (0.70, 0.70), (0.84, 0.74), (0.90, 0.66)], "hw")
    m.road([(0.36, 0.48), (0.36, 0.68)], "main")
    m.road([(0.66, 0.46), (0.70, 0.66)], "main")
    m.road([(0.20, 0.50), (0.20, 0.30), (0.34, 0.16), (0.50, 0.20)], "small")
    m.road([(0.72, 0.42), (0.78, 0.26), (0.66, 0.14)], "dirt")
    m.airport(0.82, 0.86, 0.22, -0.25)
    m.race_track([(0.44, 0.84), (0.58, 0.82), (0.62, 0.90), (0.48, 0.93)])
    m.drift_pad(0.22, 0.86, 0.12, 0.05)
    m.docks(0.40, 0.77, 4, 0.03, 0.0)
    m.power_plant(0.86, 0.58)
    m.village(0.34, 0.18, 0.05, 26)
    m.village(0.70, 0.18, 0.04, 18)
    m.stadium(0.60, 0.58, 0.035, 0.022)
    m.lighthouse(0.92, 0.60)
    m.scatter_trees(160)
    m.label(0.52, 0.60, "Новый район", 24)
    m.label(0.20, 0.66, "Махалля", 20)
    m.label(0.50, 0.08, "Горы Хисор", 26, color=(255, 255, 255))
    m.label(0.36, 0.13, "Кишлак", 18)
    m.label(0.86, 0.94, "Аэропорт", 18, ICONS["air"])
    m.label(0.42, 0.54, "Гараж", 18, ICONS["garage"])
    m.label(0.20, 0.62, "Базар", 18, ICONS["bazar"])
    m.label(0.62, 0.50, "Полиция", 18, ICONS["police"])
    m.label(0.24, 0.91, "Дрифт", 18, ICONS["drift"])
    m.label(0.54, 0.96, "Кольцо", 18, ICONS["race"])
    m.label(0.10, 0.50, "АЗС", 18, ICONS["gas"])
    m.label(0.46, 0.80, "Порт", 18, ICONS["port"])
    m.label(0.18, 0.34, "Лесная тропа", 16, ICONS["hide"])


def variant_d(m: Map):
    """Архипелаг: большой остров с городом и два малых, соединённых мостами."""
    m.title("АРХИПЕЛАГ", "вариант D · три острова и мосты")
    m.render_base()
    city = [(0.24, 0.46), (0.52, 0.42), (0.62, 0.56), (0.50, 0.70), (0.26, 0.68)]
    m.city(city, 0.25, 0.04)
    for (x, y, r, n) in [(0.72, 0.16, 0.06, 90), (0.20, 0.30, 0.05, 70), (0.70, 0.62, 0.04, 50), (0.24, 0.88, 0.04, 40)]:
        m.forest(x, y, r, n)
    m.lake([(0.62, 0.20), (0.70, 0.18), (0.72, 0.25), (0.64, 0.27)])
    loop = [(0.20, 0.48), (0.18, 0.62), (0.28, 0.74), (0.48, 0.76), (0.66, 0.68), (0.70, 0.52), (0.60, 0.40), (0.40, 0.36), (0.24, 0.40), (0.20, 0.48)]
    m.road(loop, "hw")
    m.road([(0.40, 0.36), (0.42, 0.56), (0.48, 0.76)], "main")
    m.road([(0.20, 0.55), (0.42, 0.56), (0.70, 0.58)], "main")
    m.road([(0.58, 0.12), (0.72, 0.10), (0.80, 0.18), (0.76, 0.28), (0.62, 0.30)], "small")
    m.road([(0.16, 0.86), (0.30, 0.84), (0.32, 0.94)], "small")
    m.bridge((0.56, 0.38), (0.62, 0.30))
    m.bridge((0.26, 0.74), (0.24, 0.84))
    m.race_track([(0.14, 0.82), (0.30, 0.80), (0.36, 0.90), (0.20, 0.95)])
    m.drift_pad(0.62, 0.64, 0.08, 0.05)
    m.docks(0.66, 0.70, 4, 0.025, 0.012)
    m.power_plant(0.78, 0.22)
    m.village(0.70, 0.12, 0.04, 22)
    m.village(0.18, 0.34, 0.04, 20)
    m.stadium(0.34, 0.50, 0.03, 0.02)
    m.lighthouse(0.84, 0.22)
    m.bridge((0.25, 0.41), (0.29, 0.47))
    m.scatter_trees(140)
    m.label(0.42, 0.62, "Остров Марказ", 24)
    m.label(0.70, 0.07, "Северный остров", 20)
    m.label(0.26, 0.98, "Остров Гонок", 18)
    m.label(0.50, 0.30, "Мост «Дӯстӣ»", 16, color=(255, 240, 200))
    m.label(0.30, 0.44, "Гараж", 18, ICONS["garage"])
    m.label(0.52, 0.48, "Базар", 18, ICONS["bazar"])
    m.label(0.46, 0.70, "Полиция", 18, ICONS["police"])
    m.label(0.66, 0.66, "Дрифт", 18, ICONS["drift"])
    m.label(0.22, 0.79, "Кольцо", 18, ICONS["race"])
    m.label(0.22, 0.58, "АЗС", 18, ICONS["gas"])
    m.label(0.72, 0.74, "Порт", 18, ICONS["port"])
    m.label(0.78, 0.30, "Маяк", 16, ICONS["hide"])


VARIANTS = {
    "A_podkova": ({"seed": 11, "rough": 0.5,
                   "land": [(0.48, 0.20, 0.44, 0.17), (0.22, 0.52, 0.18, 0.30), (0.50, 0.84, 0.44, 0.14), (0.34, 0.60, 0.16, 0.18)],
                   "cut": [(0.70, 0.50, 0.24, 0.16)],
                   "mountains": [(0.50, 0.20, 0.20, 0.08, 0.9)],
                   "cities": [{"poly": [(0.12, 0.47), (0.36, 0.45), (0.44, 0.54), (0.42, 0.72), (0.18, 0.74), (0.10, 0.62)]}]}, variant_a),
    "B_dolina": ({"seed": 23, "rough": 0.4, "inland": True,
                  "land": [(0.5, 0.5, 0.9, 0.9)],
                  "mountains": [],
                  "cities": [{"poly": [(0.16, 0.38), (0.46, 0.36), (0.48, 0.70), (0.30, 0.76), (0.14, 0.66)]}]}, variant_b),
    "C_poluostrov": ({"seed": 37, "rough": 0.45,
                      "land": [(0.45, 0.18, 0.75, 0.40), (0.50, 0.60, 0.48, 0.24), (0.84, 0.70, 0.12, 0.14), (0.20, 0.82, 0.22, 0.10)],
                      "mountains": [(0.45, 0.04, 0.6, 0.16, 1.7)],
                      "cities": [{"poly": [(0.36, 0.48), (0.66, 0.46), (0.70, 0.66), (0.52, 0.74), (0.36, 0.68)]}]}, variant_c),
    "D_arhipelag": ({"seed": 51, "rough": 0.5,
                     "land": [(0.44, 0.56, 0.30, 0.22), (0.70, 0.19, 0.17, 0.11), (0.25, 0.89, 0.15, 0.08), (0.20, 0.36, 0.08, 0.07)],
                     "mountains": [(0.70, 0.16, 0.10, 0.06, 0.8)],
                     "cities": [{"poly": [(0.24, 0.46), (0.52, 0.42), (0.62, 0.56), (0.50, 0.70), (0.26, 0.68)]}]}, variant_d),
}


def _ridge(seed):
    """Peaks scattered along the map border for the valley variant."""
    r = random.Random(seed)
    out = []
    for i in range(34):
        t = i / 34
        side = i % 4
        k = r.uniform(1.0, 1.9)
        rad = r.uniform(0.07, 0.13)
        if side == 0:
            out.append((t, r.uniform(-0.02, 0.05), rad, rad * 0.75, k))
        elif side == 1:
            out.append((r.uniform(-0.02, 0.05), t, rad * 0.8, rad, k))
        elif side == 2:
            out.append((r.uniform(0.95, 1.02), t, rad * 0.8, rad, k))
        else:
            out.append((t, r.uniform(0.98, 1.03), rad, rad * 0.5, k * 0.6))
    return out


VARIANTS["B_dolina"][0]["mountains"] = _ridge(5)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/maps")
    out.mkdir(parents=True, exist_ok=True)
    for name, (spec, fn) in VARIANTS.items():
        m = Map(spec)
        fn(m)
        m.draw_labels()
        m.draw_title()
        m.compass(0.90, 0.06)
        m.finish(out / f"map_{name}.png", LEGEND)
        print("saved", out / f"map_{name}.png")


if __name__ == "__main__":
    main()
