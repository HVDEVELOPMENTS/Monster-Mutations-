"""Meadow prop pack: trees, bush, rocks, grass/flower clumps, a mountain-range
segment and a leaf sprite for falling-leaf particles.

Each prop is built at its own X offset (base centre at y = 0, Roblox space) and
its pieces are named "<Prop>_<Piece>" (e.g. Oak_Trunk, Oak_Foliage). The Studio
normalise step groups pieces by prefix into ServerStorage.WorldAssets.Meadow.<Prop>.
Foliage/Blade pieces are what the Ambience client script sways in the wind.
Run in Blender with MF_MODELS set (see mossling.py).
"""

import math
import os
import random
import sys

HERE = os.environ["MF_MODELS"]
sys.path.insert(0, HERE)

import importlib

import bmesh
import bpy
from mathutils import Vector, noise

import mf_blender as mf

importlib.reload(mf)
cf = mf.cframe
col = mf.reset_collection("MeadowProps")
TEX = os.path.join(HERE, "textures")
os.makedirs(TEX, exist_ok=True)
rng = random.Random(42)


# ----- geometry helpers (Roblox space: x, y = up, z) -----
def blob(bm, center, radius, squash=(1, 1, 1), rough=0.18, subdiv=2, seed=0):
    """Displaced icosphere added to bm (lumpy foliage clump / rock)."""
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in ret["verts"]:
        d = Vector(v.co)  # unit direction; icosphere is Z-up: use z as Roblox y
        n = noise.noise(d * 2.2 + Vector((seed, seed * 1.7, seed * 2.3)))
        r = radius * (1 + rough * n)
        v.co = Vector((center[0] + d.x * r * squash[0], center[1] + d.z * r * squash[1], center[2] - d.y * r * squash[2]))
    return ret


def tube(bm, points, radii, segs=8):
    """Tapered tube through Roblox-space points (trunk / branch)."""
    rings = []
    for i, (p, r) in enumerate(zip(points, radii)):
        p = Vector(p)
        t = (Vector(points[min(i + 1, len(points) - 1)]) - Vector(points[max(i - 1, 0)])).normalized()
        a = t.orthogonal().normalized()
        b = t.cross(a).normalized()
        rings.append([bm.verts.new(p + (a * math.cos(k / segs * 2 * math.pi) + b * math.sin(k / segs * 2 * math.pi)) * r) for k in range(segs)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    cap = bm.verts.new(Vector(points[-1]))
    for k in range(segs):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segs], cap))


def obj_from(bm, name):
    """Converts a Roblox-space bmesh into a Blender object."""
    for v in bm.verts:
        x, y, z = v.co
        v.co = mf.R(x, y, z)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mf._object(col, name, bm)


def branchy_trunk(name, base, height, r0, branches, bend=0.6, seed=0):
    bm = bmesh.new()
    lr = random.Random(seed)
    pts = [(base[0] + bend * math.sin(i * 0.9 + seed) * (i / 6), base[1] + height * i / 6, base[2] + bend * math.cos(i * 0.7 + seed) * (i / 6)) for i in range(7)]
    tube(bm, pts, [r0 * (1.5 if i == 0 else 1 - 0.12 * i) for i in range(7)], segs=10)
    tips = []
    for k in range(branches):
        h = height * lr.uniform(0.55, 0.85)
        a = k / branches * 2 * math.pi + lr.uniform(-0.3, 0.3)
        length = height * lr.uniform(0.25, 0.38)
        start = (base[0], base[1] + h, base[2])
        end = (base[0] + math.cos(a) * length, base[1] + h + length * 0.7, base[2] + math.sin(a) * length)
        mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2 + 0.3, (start[2] + end[2]) / 2)
        tube(bm, [start, mid, end], [r0 * 0.45, r0 * 0.32, r0 * 0.15], segs=6)
        tips.append(end)
    return obj_from(bm, name), tips


def foliage(name, centers, radius, squash=(1, 0.8, 1), seed=0):
    """Canopy: a main clump per centre plus two smaller satellite clumps, so the
    outline breaks up like real foliage instead of reading as balloons."""
    bm = bmesh.new()
    lr = random.Random(seed)
    for i, c in enumerate(centers):
        r = radius * lr.uniform(0.8, 1.1)
        blob(bm, c, r, squash, rough=0.2, subdiv=3, seed=seed + i)
        for k in range(2):
            d = Vector((lr.uniform(-1, 1), lr.uniform(-0.3, 0.8), lr.uniform(-1, 1))).normalized() * r * 0.75
            blob(bm, (c[0] + d.x, c[1] + d.y, c[2] + d.z), r * lr.uniform(0.45, 0.6), squash, rough=0.25, subdiv=2, seed=seed + 50 + i * 3 + k)
    return obj_from(bm, name)


# ----- props -----
def oak(x):
    trunk, tips = branchy_trunk("Oak_Trunk", (x, 0, 0), 11, 0.75, 4, seed=1)
    centers = [(x, 14, 0)] + [(t[0], t[1] + 1.0, t[2]) for t in tips] + [(x + 2.2, 11.8, 1.8), (x - 2.2, 12.2, -1.8), (x + 0.5, 12, -2.6)]
    foliage("Oak_Foliage", centers, 3.1, seed=10)


def birch(x):
    trunk, tips = branchy_trunk("Birch_Trunk", (x, 0, 0), 15, 0.42, 3, bend=0.35, seed=2)
    centers = [(x, 17, 0), (x + 1.1, 15, 0.9), (x - 1.2, 14.2, -0.7), (x + 0.3, 12.5, -1.2)] + [(t[0] * 0.6 + x * 0.4, t[1] + 0.6, t[2] * 0.6) for t in tips]
    foliage("Birch_Foliage", centers, 2.1, squash=(0.9, 1.2, 0.9), seed=20)


def pine(x):
    bm = bmesh.new()
    tube(bm, [(x, 0, 0), (x, 8, 0), (x, 18, 0)], [0.6, 0.45, 0.1], segs=8)
    obj_from(bm, "Pine_Trunk")
    bm = bmesh.new()
    for k, (y, r, h) in enumerate([(4, 4.6, 6), (8, 3.7, 5.5), (11.5, 2.8, 5), (14.5, 1.9, 4.5)]):
        ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=14, radius1=r, radius2=0.2, depth=h)
        for v in ret["verts"]:
            bx, by, bz = v.co
            wob = 1 + 0.12 * math.sin(math.atan2(by, bx) * 7 + k)
            v.co = Vector((x + bx * wob, y + h / 2 + bz, -by * wob))
    obj_from(bm, "Pine_Foliage")


def bush(x):
    bm = bmesh.new()
    for i in range(5):
        a = i / 5 * 2 * math.pi
        blob(bm, (x + math.cos(a) * 1.1, 1.2 + rng.uniform(0, 0.4), math.sin(a) * 1.1), 1.5, (1, 0.8, 1), rough=0.25, seed=30 + i)
    blob(bm, (x, 1.9, 0), 1.6, (1, 0.85, 1), rough=0.25, seed=36)
    obj_from(bm, "Bush_Foliage")


def rock(x, name, size, seed):
    bm = bmesh.new()
    blob(bm, (x, size[1] * 0.35, 0), 1.0, size, rough=0.32, subdiv=3, seed=seed)
    for v in bm.verts:  # flatten the underside so it sits on the ground
        if v.co.y < 0:
            v.co.y *= 0.2
    obj_from(bm, name + "_Rock")


def grass_clump(x, name, blades=11, height=2.2, spread=0.55, seed=0):
    bm = bmesh.new()
    lr = random.Random(seed)
    for b in range(blades):
        a = lr.uniform(0, 2 * math.pi)
        r = lr.uniform(0, spread)
        bx, bz = x + math.cos(a) * r, math.sin(a) * r
        h = height * lr.uniform(0.6, 1.1)
        lean = lr.uniform(0.2, 0.7)
        face = lr.uniform(0, math.pi)
        w = lr.uniform(0.09, 0.14)
        verts = []
        steps = 4
        for s in range(steps + 1):
            t = s / steps
            cx = bx + math.cos(a) * lean * t * t
            cz = bz + math.sin(a) * lean * t * t
            half = w * (1 - t) + 0.005
            dx, dz = math.cos(face) * half, math.sin(face) * half
            verts.append((bm.verts.new((cx - dx, h * t, cz - dz)), bm.verts.new((cx + dx, h * t, cz + dz))))
        for (l0, r0), (l1, r1) in zip(verts, verts[1:]):
            bm.faces.new((l0, r0, r1, l1))
    o = obj_from(bm, name + "_Blades")
    o.data.update()
    return o


def flower_clump(x):
    grass_clump(x, "Flowers", blades=7, height=1.6, spread=0.45, seed=5)
    bm = bmesh.new()
    lr = random.Random(9)
    for k in range(4):
        a = lr.uniform(0, 2 * math.pi)
        px, pz = x + math.cos(a) * 0.4, math.sin(a) * 0.4
        h = lr.uniform(1.4, 2.1)
        tube(bm, [(px, 0, pz), (px, h, pz)], [0.04, 0.03], segs=4)
        for p in range(5):
            pa = p / 5 * 2 * math.pi
            blob(bm, (px + math.cos(pa) * 0.17, h, pz + math.sin(pa) * 0.17), 0.13, (1, 0.35, 1), rough=0.0, subdiv=1, seed=p)
        blob(bm, (px, h + 0.03, pz), 0.09, (1, 0.6, 1), rough=0.0, subdiv=1, seed=99)
    obj_from(bm, "Flowers_Petals")


def mountain(x):
    """Range segment ~420 wide, 190 tall, 140 deep: ridged noise on a grid,
    dropping to the ground at every edge."""
    bm = bmesh.new()
    W, D, H = 420.0, 140.0, 190.0
    nx, nz = 70, 24
    grid = []
    for i in range(nx + 1):
        row = []
        for j in range(nz + 1):
            u, v = i / nx, j / nz
            edge = math.sin(math.pi * u) ** 0.7 * math.sin(math.pi * v) ** 0.9
            ridge = 1 - abs(noise.noise(Vector((u * 4.5, v * 2.0, 3.1))))
            peaks = 0.55 + 0.45 * math.sin(u * math.pi * 3.2 + 0.6) ** 2
            detail = noise.noise(Vector((u * 18, v * 9, 7.7))) * 0.08
            y = H * edge * (0.45 * ridge + 0.55 * peaks) + H * detail * edge
            row.append(bm.verts.new((x - W / 2 + u * W, max(y, 0), -D / 2 + v * D)))
        grid.append(row)
    for i in range(nx):
        for j in range(nz):
            bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    obj_from(bm, "Mountain_Range")


oak(0)
birch(40)
pine(80)
bush(115)
rock(135, "RockA", (2.6, 1.8, 2.2), 3)
rock(150, "RockB", (4.2, 2.6, 3.4), 8)
grass_clump(170, "Grass", seed=1)
flower_clump(180)
mountain(500)

for o in col.objects:
    for p in o.data.polygons:
        p.use_smooth = not o.name.endswith("_Blades")


# ----- textures (object-space procedural, baked) -----
def rgb(nodes, c):
    n = nodes.new("ShaderNodeRGB")
    n.outputs[0].default_value = (*c, 1)
    return n.outputs[0]


def mix(nodes, links, fac, a, b, blend="MIX"):
    m = nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = blend
    if isinstance(fac, float):
        m.inputs["Factor"].default_value = fac
    else:
        links.new(fac, m.inputs["Factor"])
    links.new(a, next(s for s in m.inputs if s.name == "A" and s.type == "RGBA"))
    links.new(b, next(s for s in m.inputs if s.name == "B" and s.type == "RGBA"))
    return next(s for s in m.outputs if s.type == "RGBA")


def axis(nodes, links, which):
    """Object-space coordinate component ('X','Y','Z'; Blender Z is up)."""
    tc = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(tc.outputs["Object"], sep.inputs[0])
    return sep.outputs[which]


def ramp(nodes, links, fac, stops):
    r = nodes.new("ShaderNodeValToRGB")
    links.new(fac, r.inputs["Fac"])
    els = r.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
    els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1)
    for pos, c in stops[1:-1]:
        els.new(pos).color = (*c, 1)
    return r.outputs["Color"]


def leafy(base, light):
    def build(nodes, links):
        vor = nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 3.5
        tc = nodes.new("ShaderNodeTexCoord")
        links.new(tc.outputs["Object"], vor.inputs["Vector"])
        cells = ramp(nodes, links, vor.outputs["Distance"], [(0.0, light), (0.55, base), (1.0, tuple(c * 0.45 for c in base))])
        n = mf.gray(nodes, links, mf.noise_value(nodes, links, 14, detail=6, lo=0.7, hi=1.1))
        return mix(nodes, links, 1.0, cells, n, "MULTIPLY")
    return build


def bark(base, dark, streak_scale=(12.0, 12.0, 1.2)):
    def build(nodes, links):
        tc = nodes.new("ShaderNodeTexCoord")
        mapn = nodes.new("ShaderNodeMapping")
        mapn.inputs["Scale"].default_value = streak_scale
        links.new(tc.outputs["Object"], mapn.inputs["Vector"])
        nz = nodes.new("ShaderNodeTexNoise")
        nz.inputs["Detail"].default_value = 8
        links.new(mapn.outputs[0], nz.inputs["Vector"])
        return ramp(nodes, links, nz.outputs["Fac"], [(0.35, dark), (0.55, base), (0.75, tuple(min(1, c * 1.2) for c in base))])
    return build


def birch_bark(nodes, links):
    tc = nodes.new("ShaderNodeTexCoord")
    mapn = nodes.new("ShaderNodeMapping")
    mapn.inputs["Scale"].default_value = (3.0, 3.0, 9.0)
    links.new(tc.outputs["Object"], mapn.inputs["Vector"])
    nz = nodes.new("ShaderNodeTexNoise")
    nz.inputs["Detail"].default_value = 3
    links.new(mapn.outputs[0], nz.inputs["Vector"])
    return ramp(nodes, links, nz.outputs["Fac"], [(0.0, (0.06, 0.05, 0.05)), (0.3, (0.08, 0.07, 0.06)), (0.36, (0.85, 0.83, 0.78)), (1.0, (0.93, 0.92, 0.88))])


def mossy_rock(nodes, links):
    stone = ramp(nodes, links, mf.noise_value(nodes, links, 3, detail=8, lo=0.0, hi=1.0), [(0.0, (0.18, 0.18, 0.17)), (0.5, (0.32, 0.31, 0.29)), (1.0, (0.45, 0.44, 0.41))])
    geo = nodes.new("ShaderNodeNewGeometry")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Normal"], sep.inputs[0])
    up = ramp(nodes, links, sep.outputs["Z"], [(0.45, (0, 0, 0)), (0.75, (1, 1, 1))])
    moss_amt = nodes.new("ShaderNodeSeparateColor")
    links.new(up, moss_amt.inputs[0])
    return mix(nodes, links, moss_amt.outputs[0], stone, rgb(nodes, (0.12, 0.26, 0.06)))


def blades(nodes, links):
    # Dark at the root, sun-bleached towards the tip (object Z = height).
    h = axis(nodes, links, "Z")
    scale = nodes.new("ShaderNodeMath")
    scale.operation = "DIVIDE"
    links.new(h, scale.inputs[0])
    scale.inputs[1].default_value = 2.2
    return ramp(nodes, links, scale.outputs[0], [(0.0, (0.05, 0.14, 0.03)), (0.5, (0.17, 0.38, 0.07)), (1.0, (0.45, 0.6, 0.18))])


def petals(nodes, links):
    v = mf.noise_value(nodes, links, 1.2, detail=1, lo=0, hi=1)
    return ramp(nodes, links, v, [(0.0, (0.95, 0.35, 0.55)), (0.35, (1.0, 0.85, 0.2)), (0.65, (0.65, 0.45, 1.0)), (1.0, (1, 1, 1))])


def mountain_tex(nodes, links):
    h = axis(nodes, links, "Z")
    jitter = mf.noise_value(nodes, links, 0.05, detail=6, lo=-25, hi=25)
    add = nodes.new("ShaderNodeMath")
    links.new(h, add.inputs[0])
    links.new(jitter, add.inputs[1])
    div = nodes.new("ShaderNodeMath")
    div.operation = "DIVIDE"
    links.new(add.outputs[0], div.inputs[0])
    div.inputs[1].default_value = 190.0
    zones = ramp(nodes, links, div.outputs[0], [
        (0.0, (0.12, 0.24, 0.06)), (0.18, (0.16, 0.26, 0.08)), (0.3, (0.22, 0.2, 0.17)),
        (0.62, (0.33, 0.31, 0.3)), (0.72, (0.85, 0.87, 0.9)), (1.0, (0.97, 0.98, 1.0)),
    ])
    grain = mf.gray(nodes, links, mf.noise_value(nodes, links, 0.6, detail=10, lo=0.75, hi=1.1))
    return mix(nodes, links, 1.0, zones, grain, "MULTIPLY")


BAKES = {
    "Oak_Trunk": (bark((0.17, 0.11, 0.06), (0.06, 0.04, 0.02)), 512),
    "Oak_Foliage": (leafy((0.12, 0.33, 0.06), (0.32, 0.55, 0.12)), 1024),
    "Birch_Trunk": (birch_bark, 512),
    "Birch_Foliage": (leafy((0.25, 0.45, 0.08), (0.55, 0.7, 0.18)), 1024),
    "Pine_Trunk": (bark((0.15, 0.09, 0.05), (0.05, 0.03, 0.02)), 256),
    "Pine_Foliage": (leafy((0.04, 0.17, 0.06), (0.1, 0.3, 0.1)), 1024),
    "Bush_Foliage": (leafy((0.1, 0.3, 0.06), (0.3, 0.5, 0.1)), 512),
    "RockA_Rock": (mossy_rock, 512),
    "RockB_Rock": (mossy_rock, 512),
    "Grass_Blades": (blades, 256),
    "Flowers_Blades": (blades, 256),
    "Flowers_Petals": (petals, 256),
    "Mountain_Range": (mountain_tex, 2048),
}
for name, (builder, size) in BAKES.items():
    o = bpy.data.objects[name]
    mf.smart_uv(o)
    mf.bake_color(o, builder, size, os.path.join(TEX, "Meadow_%s.png" % name))


# ----- leaf sprite for falling-leaf particles (RGBA, drawn directly) -----
def leaf_sprite(path, size=128):
    img = bpy.data.images.new("LeafSprite", size, size, alpha=True)
    px = [0.0] * (size * size * 4)
    for yy in range(size):
        for xx in range(size):
            u, v = xx / (size - 1) * 2 - 1, yy / (size - 1) * 2 - 1
            # Leaf outline: pointed ellipse along v, slight curve.
            u2 = u - 0.12 * (v * v - 1) * 0.6
            width = 0.55 * math.sqrt(max(0.0, 1 - v * v)) * (1 - 0.35 * max(0, v))
            inside = abs(u2) < width
            vein = abs(u2) < 0.03 and abs(v) < 0.95
            i = (yy * size + xx) * 4
            if inside:
                shade = 0.85 + 0.15 * v
                c = (0.85 * shade, 0.45 * shade, 0.08) if not vein else (0.95, 0.7, 0.25)
                px[i:i + 4] = [c[0], c[1], c[2], 1.0]
    img.pixels = px
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


leaf_img = leaf_sprite(os.path.join(TEX, "Meadow_LeafSprite.png"))
bm = bmesh.new()
for x, z in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
    bm.verts.new((700 + x, 1, z))
bm.faces.new(bm.verts)
card = obj_from(bm, "LeafCard_Card")
uv = card.data.uv_layers.new()
for li, (u, v) in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
    uv.data[li].uv = (u, v)
mat = bpy.data.materials.new("LeafCard")
mat.use_nodes = True
tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = leaf_img
bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
card.data.materials.append(mat)

print("props:", sorted(o.name for o in col.objects))
print("tris:", {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in col.objects})
