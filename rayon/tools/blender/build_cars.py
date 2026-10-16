"""Builds the FR-Legends-style M5 and CLS in Blender and exports GLB files.

    python build_cars.py <out_dir>        (needs the `bpy` module, Blender 4.2+)

Body: a cage mesh lofted from cross-sections → window insets → Subdivision
Surface → wheel arches cut with booleans. Lights, grilles, trims and plates are
projected onto the body with ray casts. Wheels are separate objects (WheelFL,
WheelFR, WheelRL, WheelRR) with their origin at the wheel centre, plus fixed
brake calipers (CaliperFL …). Blender axes: X right, Y forward (nose at +Y),
Z up; the glTF exporter turns this into Godot's -Z forward / Y up.
"""
import math
import sys
from pathlib import Path

import bpy  # must come first: it makes bmesh / mathutils importable
import bmesh
from mathutils import Vector, Matrix

OUT = Path(sys.argv[-1] if len(sys.argv) > 1 else ".")


# --- scene & materials -----------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, rough=0.5, metal=0.0, emit=0.0, coat=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    if coat > 0 and "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    m.diffuse_color = (*color, 1.0)
    return m


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def materials(paint_hex, caliper_hex):
    return {
        "Paint": mat("Paint", srgb(paint_hex), 0.22, 0.0, coat=1.0),
        "Glass": mat("Glass", srgb("#141a22"), 0.06, 0.0),
        "Trim": mat("Trim", srgb("#121316"), 0.45),
        "Gloss": mat("GlossBlack", srgb("#0b0c0e"), 0.15),
        "Chrome": mat("Chrome", srgb("#cfd4dc"), 0.18, 0.0),
        "Led": mat("Led", srgb("#f4f8ff"), 0.3, 0.0, emit=2.0),
        "Lens": mat("HeadLens", srgb("#20262f"), 0.08),
        "Red": mat("RedLens", srgb("#c3121b"), 0.2, 0.0, emit=0.6),
        "RedDark": mat("RedDark", srgb("#5e0a0e"), 0.2),
        "Plate": mat("Plate", srgb("#f2f2ee"), 0.5),
        "Blue": mat("PlateBlue", srgb("#1f4fb8"), 0.5),
        "Ink": mat("PlateInk", srgb("#15171b"), 0.5),
        "Tyre": mat("Tyre", srgb("#18181b"), 0.85),
        "Rim": mat("Rim", srgb("#2b2d33"), 0.25, 0.0),
        "Disc": mat("Disc", srgb("#6d7178"), 0.35, 0.0),
        "Caliper": mat("Caliper", srgb(caliper_hex), 0.35),
    }


# --- body cage -------------------------------------------------------------------------------------

def ring(st):
    """Half section → full ring (14 points) at station y. Points: x, z."""
    y = st["y"]
    zb, wr, wm, zs, ws, zg, wg, zt, wt = (st[k] for k in ("zb", "wr", "wm", "zs", "ws", "zg", "wg", "zt", "wt"))
    half = [
        (0.0, zb), (wr, zb), (wm, zb + 0.17), (wm, zs - 0.12), (ws, zs), (wg, zg), (wt, zt - 0.035), (0.0, zt),
    ]
    pts = half + [(-x, z) for (x, z) in reversed(half[1:-1])]
    return [Vector((x, y, z)) for (x, z) in pts]


def build_cage(stations, kinds):
    """kinds[i] = per-section-gap tag: 'hood', 'ws', 'side', 'bpillar', 'roofonly', 'rear', 'deck'."""
    bm = bmesh.new()
    rings = []
    for st in stations:
        rings.append([bm.verts.new(p) for p in ring(st)])
    n = len(rings[0])
    faces_by_gap = []
    for j in range(len(rings) - 1):
        row = []
        for i in range(n):
            i2 = (i + 1) % n
            f = bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))
            row.append((i, f))
        faces_by_gap.append(row)
    # end caps
    front = bm.faces.new(list(reversed(rings[-1])))
    back = bm.faces.new(rings[0])
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm, faces_by_gap, front, back


# Material slots: 0 Paint, 1 Glass, 2 Trim
def assign(bm, faces_by_gap, kinds):
    side_windows = {"L": [], "R": []}
    ws_faces, rw_faces = [], []
    for j, row in enumerate(faces_by_gap):
        k = kinds[j]
        for i, f in row:
            f.material_index = 0
            seg = i if i < 7 else 13 - i      # half-profile segment 0..6 (mirror)
            side = "R" if i < 7 else "L"
            if seg in (0,):
                f.material_index = 2          # underside
            elif seg == 1:
                f.material_index = 2          # sills / skirts
            elif seg == 5 and k in ("side", "ws_side"):
                side_windows[side].append(f)
            elif seg >= 6 and k in ("ws", "ws_side"):
                ws_faces.append(f)
            elif seg >= 6 and k == "rear":
                rw_faces.append(f)
    return side_windows, ws_faces, rw_faces


def crease_layer(bm):
    return bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")


def glaze(bm, faces, thickness=0.035, depth=-0.012):
    if not faces:
        return
    cl = crease_layer(bm)
    res = bmesh.ops.inset_region(bm, faces=faces, thickness=thickness, depth=depth, use_even_offset=True)
    for f in res["faces"]:
        f.material_index = 2              # black window frame
        for e in f.edges:
            e[cl] = max(e[cl], 0.45)
    for f in faces:
        f.material_index = 1
        for e in f.edges:
            e[cl] = max(e[cl], 0.7)


def crease_lines(bm, rings_count, ring_size):
    """Longitudinal creases along the shoulder (p4) and window base (p5)."""
    cl = crease_layer(bm)
    bm.verts.ensure_lookup_table()
    wanted = {4: 0.55, 10: 0.55, 5: 0.5, 9: 0.5, 1: 0.5, 13: 0.5}
    for j in range(rings_count - 1):
        for i, w in wanted.items():
            a = bm.verts[j * ring_size + i]
            b = bm.verts[(j + 1) * ring_size + i]
            for e in a.link_edges:
                if e.other_vert(a) == b:
                    e[cl] = max(e[cl], w)


def make_body(spec, mats):
    bm, gaps, front, back = build_cage(spec["stations"], spec["kinds"])
    crease_lines(bm, len(spec["stations"]), 14)
    side_w, ws, rw = assign(bm, gaps, spec["kinds"])
    # B-pillar splits the side windows (gap tagged 'bpillar' stays paint/black)
    for s in ("L", "R"):
        glaze(bm, side_w[s], 0.03, -0.01)
    glaze(bm, ws, 0.04, -0.008)
    glaze(bm, rw, 0.04, -0.008)
    me = bpy.data.meshes.new("Body")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Body", me)
    bpy.context.collection.objects.link(ob)
    for key in ("Paint", "Glass", "Trim"):
        ob.data.materials.append(mats[key])
    # crease the shoulder line for a crisper character line
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    apply_all(ob)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    # wheel arches
    r = spec["radius"] + 0.045
    for y in (spec["axle_f"], spec["axle_r"]):
        cyl = add_cylinder("ArchCut", r, 3.0, Vector((0, y, spec["radius"] + 0.01)), axis="X", verts=48)
        cyl.data.materials.append(mats["Trim"])
        b = ob.modifiers.new("Arch", "BOOLEAN")
        b.operation = "DIFFERENCE"
        b.object = cyl
        b.solver = "EXACT"
        b.material_mode = "TRANSFER"
        apply_all(ob)
        bpy.data.objects.remove(cyl)
    return ob


# --- helpers -----------------------------------------------------------------------------------------

def apply_all(ob):
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def add_cylinder(name, r, depth, loc, axis="Z", verts=32):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r, radius2=r, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.update()
    # bake location into the mesh
    me.transform(Matrix.Translation(loc))
    ob.location = (0, 0, 0)
    return ob


def join(target, other):
    bpy.ops.object.select_all(action="DESELECT")
    other.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()


def ray_hit(body, origin, direction):
    ok, loc, nrm, _ = body.ray_cast(origin, direction)
    return (loc, nrm) if ok else (None, None)


def decal(body, name, outline, view, mat_, lift=0.004, thick=0.008, cuts=3):
    """Projects a 2D outline onto the body. view: 'front', 'rear', 'left', 'right'.
    Outline coords: front/rear → (x, z); sides → (y, z)."""
    bm = bmesh.new()
    vs = [bm.verts.new((u, v, 0)) for (u, v) in outline]
    f = bm.faces.new(vs)
    if cuts:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=False)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    dirs = {"front": Vector((0, -1, 0)), "rear": Vector((0, 1, 0)), "left": Vector((1, 0, 0)), "right": Vector((-1, 0, 0))}
    d = dirs[view]
    ok_all = True
    for v in bm.verts:
        u, w = v.co.x, v.co.y
        if view in ("front", "rear"):
            origin = Vector((u, 6.0 if view == "front" else -6.0, w))
        else:
            origin = Vector((-6.0 if view == "left" else 6.0, u, w))
        loc, nrm = ray_hit(body, origin, d)
        if loc is None:
            ok_all = False
            loc, nrm = origin + d * 5.0, -d
        v.co = loc + nrm * lift
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat_)
    if thick > 0:
        so = ob.modifiers.new("Solid", "SOLIDIFY")
        so.thickness = thick
        so.offset = 1.0
        apply_all(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def rrect(cx, cz, w, h, r=0.03, n=4):
    """Rounded rectangle outline (u, v)."""
    pts = []
    corners = [(cx + w / 2 - r, cz + h / 2 - r, 0), (cx - w / 2 + r, cz + h / 2 - r, 90),
               (cx - w / 2 + r, cz - h / 2 + r, 180), (cx + w / 2 - r, cz - h / 2 + r, 270)]
    for (x, z, a0) in corners:
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((x + math.cos(a) * r, z + math.sin(a) * r))
    return pts


def mirror_pts(pts):
    return [(-u, v) for (u, v) in reversed(pts)]


def box(name, center, size, mat_, bevel=0.01):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat_)
    if bevel > 0:
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width = bevel
        bv.segments = 3
        apply_all(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def text_mesh(name, text, size, mat_):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = 0.002
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    o2 = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o2)
    o2.data.materials.clear()
    o2.data.materials.append(mat_)
    return o2


def plate(body, m, text, y_sign, z):
    """Licence plate on the front (y_sign=+1) or rear (-1) fascia at height z."""
    view = "front" if y_sign > 0 else "rear"
    p = decal(body, "Plate", rrect(0, z, 0.52, 0.12, 0.012, 2), view, m["Plate"], 0.006, 0.006)
    b = decal(body, "PlateBlue", rrect(-0.235, z, 0.045, 0.10, 0.006, 2), view, m["Blue"], 0.014, 0.003, 1)
    loc, nrm = ray_hit(body, Vector((0.02, 6.0 * y_sign, z)), Vector((0, -y_sign, 0)))
    t = text_mesh("PlateText", text, 0.085, m["Ink"])
    # Text faces +Z in its own space: stand it up and face outwards.
    rot = Matrix.Rotation(math.radians(90), 4, "X")
    if y_sign > 0:
        rot = Matrix.Rotation(math.radians(180), 4, "Z") @ rot
    t.data.transform(rot)
    t.data.transform(Matrix.Translation(loc + nrm * 0.016 + Vector((0.02 * y_sign, 0, 0))))
    for o in (p, b, t):
        join(body, o)


# --- wheels ------------------------------------------------------------------------------------------

def make_wheel(name, m, r, w, spokes, x_sign, loc):
    """Tyre + concave multi-spoke rim, outer face towards x_sign. Origin = wheel centre."""
    parts = []
    tyre = add_cylinder(name + "_Tyre", r, w, Vector((0, 0, 0)), axis="X", verts=40)
    tyre.data.materials.append(m["Tyre"])
    bv = tyre.modifiers.new("Bevel", "BEVEL")
    bv.width = 0.045
    bv.segments = 4
    apply_all(tyre)
    parts.append(tyre)
    rr = r * 0.78
    face = x_sign * w * 0.5
    # inner barrel / dish
    dish = add_cylinder(name + "_Dish", rr * 0.98, 0.03, Vector((face - x_sign * 0.07, 0, 0)), axis="X", verts=40)
    dish.data.materials.append(m["Rim"])
    parts.append(dish)
    disc = add_cylinder(name + "_Disc", rr * 0.80, 0.025, Vector((face - x_sign * 0.055, 0, 0)), axis="X", verts=32)
    disc.data.materials.append(m["Disc"])
    parts.append(disc)
    # concave spokes
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        sp = box(name + "_Spoke", Vector((0, 0, 0)), Vector((0.022, 0.03, rr * 0.78)), m["Rim"], 0.004)
        me = sp.data
        for v in me.vertices:
            t = (v.co.z + rr * 0.39) / (rr * 0.78)          # 0 at hub, 1 at lip
            v.co.x += x_sign * (-0.03 + 0.032 * t)           # concave: hub sits deeper
            v.co.y += 0.012 * t                               # slight twist
            v.co.z += rr * 0.39 + rr * 0.2
        me.transform(Matrix.Rotation(a, 4, "X"))
        me.transform(Matrix.Translation(Vector((face, 0, 0))))
        parts.append(sp)
    hub = add_cylinder(name + "_Hub", rr * 0.22, 0.05, Vector((face - x_sign * 0.03, 0, 0)), axis="X", verts=24)
    hub.data.materials.append(m["Rim"])
    parts.append(hub)
    cap = add_cylinder(name + "_Cap", rr * 0.09, 0.01, Vector((face - x_sign * 0.003, 0, 0)), axis="X", verts=16)
    cap.data.materials.append(m["Chrome"])
    parts.append(cap)
    base = parts[0]
    for o in parts[1:]:
        join(base, o)
    base.name = name
    base.data.name = name
    for p in base.data.polygons:
        p.use_smooth = True
    base.location = loc
    return base


def make_caliper(name, m, r, x_sign, loc):
    rr = r * 0.78
    c = box(name, Vector((0, 0, 0)), Vector((0.03, rr * 0.55, rr * 0.30)), m["Caliper"], 0.01)
    c.data.transform(Matrix.Translation(Vector((x_sign * 0.092, -rr * 0.42, rr * 0.42))))
    c.location = loc
    return c


# --- the two cars ----------------------------------------------------------------------------------------

def st(y, zb, wr, wm, zs, ws, zg, wg, zt, wt):
    return dict(y=y, zb=zb, wr=wr, wm=wm, zs=zs, ws=ws, zg=zg, wg=wg, zt=zt, wt=wt)


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def gen_stations(P):
    """Cage stations from a few silhouette parameters (y: nose at +L/2)."""
    L = P["length"]
    hl = L / 2
    ys = []
    y = -hl
    while y < hl - 1e-6:
        ys.append(y)
        d = hl - abs(y)
        y += 0.09 if d < 0.25 else 0.24
    ys.append(hl)
    for k in ("cowl", "ws_top", "roof_end", "rw_base", "b0", "b1"):
        ys.append(P[k])
    ys = sorted(set(round(v, 3) for v in ys))

    def top(y):
        # nose → cowl (hood), windshield, roof, rear glass, boot — y decreases towards the rear
        if y >= P["cowl"]:
            t = (y - P["cowl"]) / (hl - P["cowl"])
            return P["cowl_h"] + (P["nose_h"] - P["cowl_h"]) * t ** 1.6
        if y >= P["ws_top"]:
            t = (P["cowl"] - y) / (P["cowl"] - P["ws_top"])
            return P["cowl_h"] + (P["roof_h"] - P["cowl_h"]) * (1 - (1 - t) ** 1.8)
        if y >= P["roof_end"]:
            t = (P["ws_top"] - y) / (P["ws_top"] - P["roof_end"])
            return P["roof_h"] + math.sin(t * math.pi) * P.get("roof_arch", 0.02) - P.get("roof_drop", 0.0) * t * t
        if y >= P["rw_base"]:
            t = (P["roof_end"] - y) / (P["roof_end"] - P["rw_base"])
            start = P["roof_h"] - P.get("roof_drop", 0.0)
            return start + (P["deck_h"] - start) * t ** P.get("rear_curve", 1.6)
        t = (P["rw_base"] - y) / (P["rw_base"] + hl)
        return P["deck_h"] + (P["tail_h"] - P["deck_h"]) * t * t

    out = []
    for y in ys:
        d = hl - abs(y)
        corner = 0.78 + 0.22 * math.sqrt(max(0.0, 1 - ((0.34 - d) / 0.34) ** 2)) if d < 0.34 else 1.0
        hw = P["hw"] * corner
        flare = sum(math.exp(-((y - a) / 0.42) ** 2) * 0.035 for a in (P["axle_f"], P["axle_r"]))
        zb = P["sill"] + (P["bump_low"] - P["sill"]) * (1 - smooth(0.0, 0.42, d))
        h = top(y)
        cab = smooth(P["belt"] + 0.04, P["belt"] + 0.24, h)
        zs = min(P["belt"] - 0.03, h - 0.02) if cab < 0.5 else P["belt"] - 0.03
        zs = min(zs, h - 0.02)
        zg = P["belt"] * cab + (h - 0.005) * (1 - cab)
        wg = hw * (0.87 + 0.02 * cab)
        wt = P["roof_hw"] * corner * cab + hw * 0.55 * (1 - cab)
        out.append(st(y, zb, hw * 0.86, hw + flare, zs, hw * 0.955 + flare * 0.6, zg, wg, h, wt))
    kinds = []
    for a, b in zip(out[:-1], out[1:]):
        ym = (a["y"] + b["y"]) / 2
        if P["b1"] <= ym <= P["b0"]:
            kinds.append("bpillar")
        elif P["ws_top"] < ym < P["cowl"] - 0.02:
            kinds.append("ws_side" if ym <= P["a_end"] else "ws")
        elif P["rw_base"] + 0.03 < ym < P["roof_end"]:
            kinds.append("rear" if ym < P["c_start"] else "side")
        elif P["roof_end"] <= ym <= P["ws_top"]:
            kinds.append("side")
        else:
            kinds.append("deck" if ym < 0 else "hood")
    return out, kinds


M5 = {
    "name": "M5", "file": "m5_frl.glb", "paint": "#1c1d21", "caliper": "#2f6fd8", "plate": "M5 F90",
    "radius": 0.355, "tyre_w": 0.27, "width": 1.92, "axle_f": 1.50, "axle_r": -1.46, "track": 0.80, "spokes": 14,
    "shape": dict(length=4.96, hw=0.96, axle_f=1.50, axle_r=-1.46, sill=0.20, bump_low=0.27, belt=0.98,
                  nose_h=0.80, cowl=1.18, cowl_h=0.99, ws_top=0.28, roof_h=1.52, roof_end=-0.62, rw_base=-1.38,
                  deck_h=1.03, tail_h=0.99, roof_hw=0.68, b0=-0.02, b1=-0.12, a_end=0.78, c_start=-0.60,
                  roof_arch=0.02, rear_curve=1.5),
}

CLS = {
    "name": "CLS", "file": "cls_frl.glb", "paint": "#f3f2ee", "caliper": "#c3121b", "plate": "CLS 2014",
    "radius": 0.35, "tyre_w": 0.26, "width": 1.88, "axle_f": 1.46, "axle_r": -1.42, "track": 0.79, "spokes": 18,
    "shape": dict(length=4.94, hw=0.94, axle_f=1.46, axle_r=-1.42, sill=0.20, bump_low=0.25, belt=0.95,
                  nose_h=0.76, cowl=1.22, cowl_h=0.95, ws_top=0.30, roof_h=1.47, roof_end=-0.20, rw_base=-1.60,
                  deck_h=1.00, tail_h=0.97, roof_hw=0.65, b0=0.08, b1=-0.02, a_end=0.82, c_start=-0.78,
                  roof_arch=0.035, roof_drop=0.04, rear_curve=1.25),
}
for _car in (M5, CLS):
    _car["stations"], _car["kinds"] = gen_stations(_car["shape"])


def m5_details(body, m):
    parts = []
    for s in (1, -1):
        # headlight housing, LED brows and twin projectors
        hl = [(0.30, 0.69), (0.78, 0.74), (0.86, 0.69), (0.80, 0.62), (0.36, 0.60)]
        hl = hl if s > 0 else mirror_pts(hl)
        parts.append(decal(body, "Head", hl, "front", m["Lens"], 0.004, 0.01))
        brow = [(0.36, 0.69), (0.78, 0.73), (0.79, 0.715), (0.37, 0.675)]
        parts.append(decal(body, "Brow", brow if s > 0 else mirror_pts(brow), "front", m["Led"], 0.012, 0.004, 2))
        for cx in (0.47, 0.64):
            parts.append(decal(body, "Proj", rrect(s * cx, 0.645, 0.07, 0.05, 0.02, 3), "front", m["Led"], 0.012, 0.004, 1))
        # kidney grille with chrome-less black surround and bars
        parts.append(decal(body, "KidneyFrame", rrect(s * 0.15, 0.62, 0.27, 0.24, 0.05, 4), "front", m["Trim"], 0.006, 0.012))
        parts.append(decal(body, "Kidney", rrect(s * 0.15, 0.62, 0.22, 0.19, 0.04, 4), "front", m["Gloss"], 0.016, 0.004))
        for b in range(5):
            x = s * (0.065 + b * 0.042)
            parts.append(decal(body, "Bar", rrect(x, 0.62, 0.012, 0.18, 0.005, 1), "front", m["Trim"], 0.022, 0.004, 1))
        # big side intakes and fog strip
        si = [(0.55, 0.50), (0.82, 0.52), (0.84, 0.30), (0.58, 0.28)]
        parts.append(decal(body, "Intake", si if s > 0 else mirror_pts(si), "front", m["Gloss"], 0.004, 0.01))
        parts.append(decal(body, "Blade", rrect(s * 0.70, 0.40, 0.025, 0.20, 0.008, 2), "front", m["Trim"], 0.014, 0.004, 1))
        # tail lamps (L-shape) and quad exhaust
        tl = [(0.40, 0.92), (0.88, 0.93), (0.90, 0.80), (0.80, 0.80), (0.79, 0.86), (0.42, 0.85)]
        parts.append(decal(body, "Tail", tl if s > 0 else mirror_pts(tl), "rear", m["Red"], 0.004, 0.012))
        tl2 = [(0.46, 0.895), (0.86, 0.905), (0.86, 0.885), (0.46, 0.878)]
        parts.append(decal(body, "TailLight", tl2 if s > 0 else mirror_pts(tl2), "rear", m["Led"], 0.014, 0.003, 1))
        for q in (-1, 1):
            x = s * (0.58 + q * 0.07)
            loc, nrm = ray_hit(body, Vector((x, -6, 0.33)), Vector((0, 1, 0)))
            pipe = add_cylinder("Pipe", 0.045, 0.14, loc + Vector((0, -0.03, 0)), axis="Y", verts=24)
            pipe.data.materials.append(m["Chrome"])
            inner = add_cylinder("PipeIn", 0.033, 0.142, loc + Vector((0, -0.031, 0)), axis="Y", verts=24)
            inner.data.materials.append(m["Gloss"])
            parts += [pipe, inner]
    # centre intake, diffuser, splitter
    parts.append(decal(body, "CenterIntake", rrect(0, 0.37, 0.80, 0.16, 0.04, 3), "front", m["Gloss"], 0.004, 0.01))
    parts.append(decal(body, "Diffuser", rrect(0, 0.33, 1.40, 0.14, 0.03, 3), "rear", m["Trim"], 0.004, 0.012))
    parts.append(box("Lip", Vector((0, -2.20, 1.005)), Vector((1.10, 0.10, 0.03)), m["Paint"], 0.01))
    plate(body, m, "M5 F90", 1, 0.50)
    plate(body, m, "M5 F90", -1, 0.62)
    return parts


def cls_details(body, m):
    parts = []
    for s in (1, -1):
        hl = [(0.36, 0.67), (0.80, 0.72), (0.86, 0.68), (0.78, 0.60), (0.40, 0.61)]
        parts.append(decal(body, "Head", hl if s > 0 else mirror_pts(hl), "front", m["Lens"], 0.004, 0.01))
        brow = [(0.40, 0.665), (0.80, 0.712), (0.81, 0.698), (0.41, 0.652)]
        parts.append(decal(body, "Brow", brow if s > 0 else mirror_pts(brow), "front", m["Led"], 0.012, 0.004, 2))
        parts.append(decal(body, "Proj", rrect(s * 0.60, 0.635, 0.12, 0.05, 0.02, 3), "front", m["Led"], 0.012, 0.004, 1))
        si = [(0.50, 0.46), (0.84, 0.48), (0.86, 0.28), (0.54, 0.27)]
        parts.append(decal(body, "Intake", si if s > 0 else mirror_pts(si), "front", m["Gloss"], 0.004, 0.01))
        parts.append(decal(body, "Blade", rrect(s * 0.68, 0.37, 0.30, 0.025, 0.008, 2), "front", m["Chrome"], 0.014, 0.004, 1))
        tl = [(0.36, 0.89), (0.88, 0.90), (0.90, 0.83), (0.38, 0.83)]
        parts.append(decal(body, "Tail", tl if s > 0 else mirror_pts(tl), "rear", m["Red"], 0.004, 0.012))
        tl2 = [(0.42, 0.872), (0.86, 0.88), (0.86, 0.865), (0.42, 0.858)]
        parts.append(decal(body, "TailLight", tl2 if s > 0 else mirror_pts(tl2), "rear", m["Led"], 0.014, 0.003, 1))
        for q in (-1, 1):
            x = s * (0.56 + q * 0.085)
            parts.append(decal(body, "Pipe", rrect(x, 0.31, 0.12, 0.06, 0.02, 3), "rear", m["Chrome"], 0.01, 0.02))
            parts.append(decal(body, "PipeIn", rrect(x, 0.31, 0.09, 0.035, 0.012, 3), "rear", m["Gloss"], 0.032, 0.004, 1))
    # wide grille with a chrome bar and a plain chrome disc (no logo)
    parts.append(decal(body, "Grille", rrect(0, 0.565, 0.72, 0.24, 0.05, 4), "front", m["Gloss"], 0.006, 0.01))
    parts.append(decal(body, "GrilleBar", rrect(0, 0.565, 0.70, 0.035, 0.012, 2), "front", m["Chrome"], 0.018, 0.006))
    loc, nrm = ray_hit(body, Vector((0, 6, 0.565)), Vector((0, -1, 0)))
    disc = add_cylinder("Disc", 0.075, 0.03, loc + Vector((0, 0.03, 0)), axis="Y", verts=32)
    disc.data.materials.append(m["Chrome"])
    parts.append(disc)
    parts.append(decal(body, "CenterIntake", rrect(0, 0.33, 0.70, 0.11, 0.03, 3), "front", m["Gloss"], 0.004, 0.01))
    parts.append(decal(body, "Diffuser", rrect(0, 0.30, 1.30, 0.12, 0.03, 3), "rear", m["Trim"], 0.004, 0.012))
    plate(body, m, "CLS 2014", 1, 0.44)
    plate(body, m, "CLS 2014", -1, 0.62)
    return parts


def side_details(body, m, spec, chrome_line):
    parts = []
    for s in (1, -1):
        view = "right" if s > 0 else "left"
        # mirrors near the A-pillar
        mz = 1.03
        my = spec["mirror_y"]
        loc, nrm = ray_hit(body, Vector((s * 3, my, mz)), Vector((-s, 0, 0)))
        if loc is not None:
            arm = box("MirrorArm", loc + Vector((s * 0.04, 0, 0)), Vector((0.08, 0.06, 0.04)), m["Trim"], 0.01)
            cap = box("Mirror", loc + Vector((s * 0.15, -0.02, 0.04)), Vector((0.18, 0.11, 0.10)), m["Paint"], 0.03)
            glass = box("MirrorGlass", loc + Vector((s * 0.15, -0.078, 0.04)), Vector((0.15, 0.01, 0.075)), m["Glass"], 0.005)
            parts += [arm, cap, glass]
        # door shut lines
        for y in spec["door_lines"]:
            line = [(y - 0.004, 0.30), (y + 0.004, 0.30), (y + 0.004, 0.90), (y - 0.004, 0.90)]
            parts.append(decal(body, "DoorLine", line, view, m["Gloss"], 0.0015, 0.002, 6))
        for y in spec["handles"]:
            parts.append(decal(body, "Handle", rrect(y, 0.84, 0.15, 0.03, 0.012, 2), view, m["Chrome"] if chrome_line else m["Paint"], 0.008, 0.012, 1))
        # chrome (CLS) or black (M5) window line
        a, b = spec["window_line"]
        parts.append(decal(body, "WindowLine", rrect((a + b) / 2, 0.965, b - a, 0.02, 0.008, 2), view, m["Chrome"] if chrome_line else m["Gloss"], 0.006, 0.006, 1))
        # front fender vent
        fy = spec["axle_f"] - 0.52
        parts.append(decal(body, "Vent", rrect(fy, 0.66, 0.16, 0.05, 0.015, 2), view, m["Gloss"], 0.004, 0.004, 1))
    return parts


def build(spec, details):
    reset()
    m = materials(spec["paint"], spec["caliper"])
    body = make_body(spec, m)
    for p in body.data.polygons:
        p.use_smooth = True
    extra = details(body, m)
    extra += side_details(body, m, spec, spec is CLS)
    for o in extra:
        join(body, o)
    body.name = "Body"
    for wn, x_sign, y in (("FL", -1, spec["axle_f"]), ("FR", 1, spec["axle_f"]), ("RL", -1, spec["axle_r"]), ("RR", 1, spec["axle_r"])):
        loc = Vector((x_sign * spec["track"], y, spec["radius"]))
        make_wheel("Wheel" + wn, m, spec["radius"], spec["tyre_w"], spec["spokes"], x_sign, loc)
        make_caliper("Caliper" + wn, m, spec["radius"], x_sign, loc)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / spec["file"]
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_apply=True, export_yup=True)
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
    print("exported", path, "triangles", tris)


M5.update({"door_lines": [0.86, -0.04, -0.98], "handles": [0.30, -0.62], "window_line": (-0.74, 0.62), "mirror_y": 0.80})
CLS.update({"door_lines": [0.90, 0.02, -0.98], "handles": [0.35, -0.60], "window_line": (-0.82, 0.60), "mirror_y": 0.82})

if __name__ == "__main__":
    build(M5, m5_details)
    build(CLS, cls_details)
