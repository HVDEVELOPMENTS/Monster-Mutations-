"""World prop packs for the five non-meadow biomes (one FBX, BiomeProps.fbx).

Pieces are named "<Biome>-<Prop>_<Piece>" (e.g. FrostfallTundra-SnowPine_Foliage).
normalise_props.luau groups them into ServerStorage.WorldAssets.<Biome>.<Prop>
and gives special pieces their Roblox look:
  Foliage / Blades / Fronds   sway in the wind (Ambience client script)
  Lava / Spark / Bloom        glow (Neon)
  Ice / Crystal / Obsidian    glassy
Every set has a "Range" prop: a mountain-range segment WorldBuilder puts beyond
the zone walls.

Run in Blender (MCP execute_blender_code):
  os.environ["MF_MODELS"] = <this folder>; exec(open(<this file>).read())
  then build(<biome>) for each biome, then export_all().
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
import prop_kit as pk

importlib.reload(mf)
importlib.reload(pk)

TEX = os.path.join(HERE, "textures")
os.makedirs(TEX, exist_ok=True)
COLLECTION = "BiomeProps"


def collection():
    col = bpy.data.collections.get(COLLECTION)
    if not col:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    return col


def bake(kit, bakes):
    for piece_name, (builder, size) in bakes.items():
        name = "%s-%s" % (kit.set, piece_name)
        o = bpy.data.objects[name]
        for p in o.data.polygons:
            p.use_smooth = not (name.endswith("_Blades") or name.endswith("_Fronds"))
        mf.smart_uv(o)
        mf.bake_color(o, builder, size, os.path.join(TEX, "%s.png" % name))


def clear_set(set_name):
    col = collection()
    for o in list(col.objects):
        if o.name.startswith(set_name + "-"):
            bpy.data.objects.remove(o, do_unlink=True)


# ======================= Frostfall Tundra =======================
def tundra(kit):
    B = bmesh.new
    # Snow-laden pine.
    bm = B()
    pk.tube(bm, [(0, 0, 0), (0, 9, 0), (0, 20, 0)], [0.7, 0.5, 0.1], segs=8)
    kit.obj(bm, "SnowPine", "Trunk")
    bm = B()
    pk.cone_tiers(bm, 0, [(3.5, 5.2, 6.5), (8, 4.2, 6), (12, 3.2, 5.5), (15.5, 2.2, 5)], wobble=0.16)
    kit.obj(bm, "SnowPine", "Foliage")
    # Ice spires: a cluster of clear crystals.
    bm = B()
    lr = random.Random(4)
    for k in range(6):
        a = k / 6 * 2 * math.pi
        r = 0 if k == 0 else lr.uniform(1.6, 2.6)
        pk.crystal(bm, (40 + math.cos(a) * r, -0.5, math.sin(a) * r), lr.uniform(6, 15) * (1.3 if k == 0 else 1), lr.uniform(0.9, 1.5), (math.cos(a) * 0.25 * (r > 0), math.sin(a) * 0.25 * (r > 0)))
    kit.obj(bm, "IceSpire", "Ice")
    # Snowy boulder.
    bm = B()
    pk.rock(bm, 70, (4.5, 3, 3.8), seed=11)
    pk.flatten_base(bm)
    kit.obj(bm, "SnowRock", "Rock")
    # Frosted shrub.
    bm = B()
    for i in range(5):
        a = i / 5 * 2 * math.pi
        pk.blob(bm, (95 + math.cos(a) * 1.1, 1.2, math.sin(a) * 1.1), 1.4, (1, 0.8, 1), rough=0.3, seed=60 + i)
    kit.obj(bm, "FrostBush", "Foliage")
    # Pale frozen grass.
    bm = B()
    pk.blades(bm, 115, count=10, height=1.8, seed=7)
    kit.obj(bm, "FrozenGrass", "Blades")
    # Snowy mountain range (taller and sharper than the meadow's).
    bm = B()
    pk.heightfield(bm, 600, 420, 140, 70, 24, pk.range_fn(230, peaks=3.6, sharp=1.6, seed=5.5))
    kit.obj(bm, "Range", "Rock")
    bake(kit, {
        "SnowPine_Trunk": (pk.bark((0.16, 0.1, 0.06), (0.05, 0.03, 0.02)), 256),
        "SnowPine_Foliage": (pk.snowy(pk.leafy((0.03, 0.15, 0.08), (0.08, 0.28, 0.12)), lo=0.25, hi=0.5), 1024),
        "IceSpire_Ice": (pk.gradient_z(18, [(0.0, (0.35, 0.65, 0.9)), (0.6, (0.7, 0.9, 1.0)), (1.0, (0.97, 1.0, 1.0))]), 256),
        "SnowRock_Rock": (pk.snowy(pk.stone((0.2, 0.22, 0.26), (0.36, 0.38, 0.42), (0.52, 0.55, 0.6)), lo=0.6, hi=0.8), 512),
        "FrostBush_Foliage": (pk.snowy(pk.leafy((0.12, 0.25, 0.22), (0.35, 0.5, 0.48)), lo=0.6, hi=0.85), 512),
        "FrozenGrass_Blades": (pk.gradient_z(1.8, [(0.0, (0.25, 0.35, 0.3)), (0.5, (0.55, 0.65, 0.62)), (1.0, (0.9, 0.95, 1.0))]), 128),
        "Range_Rock": (pk.height_bands(230, [(0.0, (0.55, 0.6, 0.66)), (0.2, (0.38, 0.4, 0.45)), (0.38, (0.85, 0.88, 0.93)), (1.0, (0.98, 0.99, 1.0))]), 1024),
    })


# ======================= Emberpeak Volcano =======================
VOLCANO_W, VOLCANO_H, CRATER = 190.0, 85.0, 0.13


def volcano_fn(u, v):
    du, dv = (u - 0.5) * 2, (v - 0.5) * 2
    r = math.sqrt(du * du + dv * dv)
    a = math.atan2(dv, du)
    ridges = 1 + 0.08 * math.sin(a * 9) + 0.05 * noise.noise(Vector((du * 3, dv * 3, 1.7)))
    if r >= 1:
        return 0.0
    h = VOLCANO_H * max(0.0, 1 - r * ridges) ** 1.35
    if r < CRATER:  # bowl-shaped crater
        rim = VOLCANO_H * max(0.0, 1 - CRATER * ridges) ** 1.35
        h = rim - (CRATER - r) / CRATER * VOLCANO_H * 0.22
    return h


def volcano(kit):
    B = bmesh.new
    bm = B()
    pk.heightfield(bm, 0, VOLCANO_W, VOLCANO_W, 64, 64, volcano_fn)
    kit.obj(bm, "Volcano", "Rock")
    # Lava: a pool in the crater and three rivers running down the slopes.
    bm = B()
    rim = volcano_fn(0.5 + CRATER / 2, 0.5)
    pool_y = rim - VOLCANO_H * 0.16
    ret = bmesh.ops.create_circle(bm, cap_ends=True, segments=24, radius=VOLCANO_W / 2 * CRATER * 0.85)
    for vtx in ret["verts"]:
        x, y, _ = vtx.co
        vtx.co = Vector((x, pool_y, y))
    for k, a in enumerate((0.4, 2.5, 4.3)):
        pts, widths = [], []
        for s in range(14):
            t = CRATER * 0.9 + s / 13 * (0.92 - CRATER)
            wob = a + 0.15 * math.sin(s * 0.8 + k)
            u, v = 0.5 + math.cos(wob) * t / 2, 0.5 + math.sin(wob) * t / 2
            pts.append(((u - 0.5) * VOLCANO_W, volcano_fn(u, v) + 0.4, (v - 0.5) * VOLCANO_W))
            widths.append(1.6 + 2.2 * s / 13)
        # A flat ribbon following the slope.
        prev = None
        for (p, w), nxt in zip(zip(pts, widths), pts[1:] + [None]):
            d = (Vector(nxt) - Vector(p)) if nxt else (Vector(p) - Vector(pts[-2]))
            side = Vector((-d.z, 0, d.x)).normalized() * w
            l, r = bm.verts.new(Vector(p) - side), bm.verts.new(Vector(p) + side)
            if prev:
                bm.faces.new((prev[0], prev[1], r, l))
            prev = (l, r)
    kit.obj(bm, "Volcano", "Lava")
    # Basalt columns.
    bm = B()
    lr = random.Random(8)
    for k in range(9):
        a = k / 9 * 2 * math.pi
        r = 0 if k == 0 else lr.uniform(1.6, 3.2)
        pk.crystal(bm, (130 + math.cos(a) * r, 0, math.sin(a) * r), lr.uniform(3, 10), 1.0, sides=6, point=0.02)
    kit.obj(bm, "BasaltColumns", "Rock")
    # Rock with glowing lava seams.
    bm = B()
    pk.rock(bm, 160, (4, 2.6, 3.4), seed=21)
    pk.flatten_base(bm)
    kit.obj(bm, "LavaRock", "Rock")
    # Charred dead tree.
    bm = B()
    pk.branchy(bm, (185, 0, 0), 12, 0.6, 5, bend=1.2, seed=9, up=0.9, reach=(0.3, 0.45))
    kit.obj(bm, "DeadTree", "Trunk")
    # Obsidian spire.
    bm = B()
    pk.crystal(bm, (210, -0.5, 0), 16, 1.8, (0.12, 0.05), sides=5, point=0.5)
    pk.crystal(bm, (212, -0.5, 1.5), 8, 1.0, (0.35, 0.2), sides=5, point=0.5)
    kit.obj(bm, "ObsidianSpire", "Obsidian")
    # Ash grass with ember tips.
    bm = B()
    pk.blades(bm, 230, count=9, height=1.6, seed=13)
    kit.obj(bm, "AshGrass", "Blades")
    # Dark volcanic range.
    bm = B()
    pk.heightfield(bm, 700, 420, 140, 70, 24, pk.range_fn(200, peaks=2.6, sharp=1.3, seed=8.2))
    kit.obj(bm, "Range", "Rock")
    basalt = pk.stone((0.06, 0.05, 0.05), (0.13, 0.11, 0.11), (0.22, 0.19, 0.18), scale=4)
    bake(kit, {
        "Volcano_Rock": (pk.height_bands(VOLCANO_H, [(0.0, (0.22, 0.17, 0.15)), (0.5, (0.14, 0.11, 0.1)), (0.85, (0.09, 0.07, 0.07)), (1.0, (0.35, 0.12, 0.05))]), 1024),
        "Volcano_Lava": (pk.flat((1.0, 0.45, 0.1)), 128),
        "BasaltColumns_Rock": (basalt, 512),
        "LavaRock_Rock": (pk.cracked(basalt, (1.0, 0.42, 0.08), width=0.05), 512),
        "DeadTree_Trunk": (pk.bark((0.12, 0.09, 0.08), (0.03, 0.02, 0.02)), 256),
        "ObsidianSpire_Obsidian": (pk.gradient_z(16, [(0.0, (0.06, 0.04, 0.08)), (0.7, (0.14, 0.1, 0.2)), (1.0, (0.35, 0.25, 0.45))]), 256),
        "AshGrass_Blades": (pk.gradient_z(1.6, [(0.0, (0.15, 0.13, 0.12)), (0.7, (0.35, 0.32, 0.3)), (1.0, (1.0, 0.45, 0.1))]), 128),
        "Range_Rock": (pk.height_bands(200, [(0.0, (0.2, 0.15, 0.13)), (0.3, (0.13, 0.1, 0.1)), (0.8, (0.08, 0.07, 0.07)), (1.0, (0.3, 0.12, 0.08))]), 1024),
    })


# ======================= Tidebreak Coast =======================
def coast(kit):
    B = bmesh.new
    # Palm tree: a curved ringed trunk, coconuts and arching fronds.
    bm = B()
    pts = [(math.sin(t / 8 * 1.2) * 3.2, t / 8 * 16, 0) for t in range(9)]
    pk.tube(bm, pts, [0.75 - 0.04 * i for i in range(9)], segs=10)
    top = Vector(pts[-1])
    for k in range(3):
        a = k / 3 * 2 * math.pi
        pk.blob(bm, (top.x + math.cos(a) * 0.55, top.y - 0.5, top.z + math.sin(a) * 0.55), 0.45, rough=0.05, subdiv=2, seed=k)
    kit.obj(bm, "Palm", "Trunk")
    bm = B()
    for k in range(9):
        a = k / 9 * 2 * math.pi + 0.2
        length = 6.5 + (k % 3) * 0.6
        prev = None
        for s in range(9):
            t = s / 8
            d = length * t
            p = Vector((top.x + math.cos(a) * d, top.y + 1.6 * math.sin(t * math.pi * 0.8) - 2.8 * t * t, top.z + math.sin(a) * d))
            w = 0.9 * math.sin(math.pi * min(t * 1.3, 1)) + 0.05
            side = Vector((-math.sin(a), 0, math.cos(a))) * w
            l, r = bm.verts.new(p - side + Vector((0, -0.15 * w, 0))), bm.verts.new(p + side + Vector((0, -0.15 * w, 0)))
            c = bm.verts.new(p)
            if prev:
                bm.faces.new((prev[0], prev[2], c, l))
                bm.faces.new((prev[2], prev[1], r, c))
            prev = (l, r, c)
    kit.obj(bm, "Palm", "Fronds")
    # Coral: branching arms with round tips (two colour variants).
    for name, x, seed in (("CoralPink", 40, 3), ("CoralBlue", 55, 7)):
        bm = B()
        lr = random.Random(seed)
        for k in range(6):
            a = k / 6 * 2 * math.pi + lr.uniform(-0.3, 0.3)
            reach = lr.uniform(0.6, 1.5)
            h = lr.uniform(2.2, 4)
            p0 = (x, 0, 0)
            p1 = (x + math.cos(a) * reach * 0.4, h * 0.5, math.sin(a) * reach * 0.4)
            p2 = (x + math.cos(a) * reach, h, math.sin(a) * reach)
            pk.tube(bm, [p0, p1, p2], [0.35, 0.25, 0.16], segs=6)
            pk.blob(bm, p2, 0.3, rough=0.1, subdiv=1, seed=k)
        kit.obj(bm, name, "Coral")
    # Sea rock with algae near the bottom.
    bm = B()
    pk.rock(bm, 75, (4.6, 3.4, 3.8), seed=31)
    pk.flatten_base(bm)
    kit.obj(bm, "SeaRock", "Rock")
    # Starfish.
    bm = B()
    for k in range(5):
        a = k / 5 * 2 * math.pi
        pk.tube(bm, [(95, 0.25, 0), (95 + math.cos(a) * 1.2, 0.2, math.sin(a) * 1.2)], [0.42, 0.08], segs=6)
    pk.blob(bm, (95, 0.25, 0), 0.5, (1, 0.45, 1), rough=0.05, subdiv=1, seed=2)
    kit.obj(bm, "Starfish", "Body")
    # Beach grass.
    bm = B()
    pk.blades(bm, 110, count=12, height=2.4, width=(0.06, 0.1), lean=(0.4, 1.0), seed=17)
    kit.obj(bm, "BeachGrass", "Blades")
    # Sea cliffs.
    bm = B()
    pk.heightfield(bm, 600, 420, 140, 70, 24, pk.range_fn(150, peaks=2.2, sharp=0.8, seed=11.1))
    kit.obj(bm, "Range", "Rock")
    bake(kit, {
        "Palm_Trunk": (pk.bark((0.42, 0.3, 0.17), (0.2, 0.13, 0.07), streak=(2.0, 2.0, 14.0)), 256),
        "Palm_Fronds": (pk.leafy((0.12, 0.4, 0.08), (0.35, 0.65, 0.15)), 512),
        "CoralPink_Coral": (pk.spotted((1.0, 0.42, 0.5), (1.0, 0.75, 0.55), scale=8, size=0.12), 256),
        "CoralBlue_Coral": (pk.spotted((0.35, 0.45, 1.0), (0.55, 0.95, 0.95), scale=8, size=0.12), 256),
        "SeaRock_Rock": (pk.height_bands(4, [(0.0, (0.15, 0.28, 0.12)), (0.2, (0.3, 0.33, 0.25)), (0.35, (0.48, 0.46, 0.42)), (1.0, (0.62, 0.6, 0.55))]), 512),
        "Starfish_Body": (pk.spotted((1.0, 0.5, 0.15), (1.0, 0.85, 0.5), scale=12, size=0.15), 256),
        "BeachGrass_Blades": (pk.gradient_z(2.4, [(0.0, (0.3, 0.38, 0.12)), (0.6, (0.6, 0.65, 0.3)), (1.0, (0.9, 0.85, 0.55))]), 128),
        "Range_Rock": (pk.height_bands(150, [(0.0, (0.85, 0.76, 0.55)), (0.12, (0.6, 0.55, 0.48)), (0.75, (0.45, 0.43, 0.4)), (0.85, (0.25, 0.45, 0.15)), (1.0, (0.3, 0.55, 0.18))]), 1024),
    })


# ======================= Thunderwild Highlands =======================
def highlands(kit):
    B = bmesh.new
    # Storm crystals: tall golden crystals around a glowing core.
    bm = B()
    lr = random.Random(5)
    for k in range(7):
        a = k / 7 * 2 * math.pi
        r = 0 if k == 0 else lr.uniform(1.4, 2.4)
        pk.crystal(bm, (math.cos(a) * r, -0.4, math.sin(a) * r), lr.uniform(4, 10) * (1.4 if k == 0 else 1), lr.uniform(0.7, 1.1), (math.cos(a) * 0.3 * (r > 0), math.sin(a) * 0.3 * (r > 0)))
    kit.obj(bm, "StormCrystal", "Crystal")
    bm = B()
    pk.blob(bm, (0, 1.2, 0), 1.1, rough=0.1, subdiv=2, seed=3)
    kit.obj(bm, "StormCrystal", "Spark")
    # Wind-bent tree: trunk leaning with the wind, canopy swept to one side.
    bm = B()
    pts = [(t / 6 * 4.5 * (t / 6), t / 6 * 13, 0) for t in range(7)]
    pk.tube(bm, pts, [0.8 - 0.1 * i for i in range(7)], segs=10)
    kit.obj(bm, "WindTree", "Trunk")
    bm = B()
    top = pts[-1]
    pk.canopy(bm, [(top[0] + 1.5, top[1], 0), (top[0] + 4, top[1] - 0.8, 0.8), (top[0] - 0.5, top[1] + 0.6, -0.8)], 2.6, squash=(1.4, 0.6, 1), seed=40)
    kit.obj(bm, "WindTree", "Foliage")
    # Big boulder.
    bm = B()
    pk.rock(bm, 40, (6, 4.2, 5), seed=44, rough=0.4)
    pk.flatten_base(bm)
    kit.obj(bm, "Boulder", "Rock")
    # Stone arch.
    bm = B()
    arc = [(60 + math.cos(t / 10 * math.pi) * 7, math.sin(t / 10 * math.pi) * 9, 0) for t in range(11)]
    pk.tube(bm, arc, [1.6 + 0.4 * math.cos(t / 10 * math.pi * 2) for t in range(11)], segs=10, cap=False)
    for p in (arc[0], arc[-1]):
        pk.blob(bm, (p[0], 0.8, 0), 2.2, (1, 0.6, 1), rough=0.25, seed=int(p[0]))
    kit.obj(bm, "StoneArch", "Rock")
    # Tall golden grass.
    bm = B()
    pk.blades(bm, 85, count=12, height=3, width=(0.06, 0.1), lean=(0.5, 1.2), seed=21)
    kit.obj(bm, "GoldGrass", "Blades")
    # Jagged storm peaks.
    bm = B()
    pk.heightfield(bm, 600, 420, 140, 80, 26, pk.range_fn(240, peaks=4.4, sharp=2.2, seed=13.7))
    kit.obj(bm, "Range", "Rock")
    slate = pk.stone((0.18, 0.18, 0.22), (0.3, 0.3, 0.35), (0.45, 0.45, 0.5))
    bake(kit, {
        "StormCrystal_Crystal": (pk.gradient_z(14, [(0.0, (0.75, 0.55, 0.1)), (0.5, (1.0, 0.85, 0.25)), (1.0, (1.0, 1.0, 0.75))]), 256),
        "StormCrystal_Spark": (pk.flat((1.0, 0.95, 0.5)), 64),
        "WindTree_Trunk": (pk.bark((0.3, 0.22, 0.15), (0.12, 0.08, 0.05)), 256),
        "WindTree_Foliage": (pk.leafy((0.2, 0.35, 0.1), (0.45, 0.55, 0.2)), 512),
        "Boulder_Rock": (pk.snowy(slate, cover=(0.35, 0.45, 0.2), lo=0.55, hi=0.8), 512),
        "StoneArch_Rock": (slate, 512),
        "GoldGrass_Blades": (pk.gradient_z(3, [(0.0, (0.35, 0.3, 0.1)), (0.6, (0.75, 0.6, 0.2)), (1.0, (0.98, 0.85, 0.45))]), 128),
        "Range_Rock": (pk.height_bands(240, [(0.0, (0.3, 0.38, 0.22)), (0.2, (0.28, 0.27, 0.33)), (0.7, (0.2, 0.2, 0.26)), (1.0, (0.55, 0.5, 0.65))]), 1024),
    })


# ======================= Toxic Bloom Swamp =======================
def swamp(kit):
    B = bmesh.new
    # Weeping willow: crooked trunk, droopy canopy and hanging strands.
    bm = B()
    tips = pk.branchy(bm, (0, 0, 0), 10, 0.9, 5, bend=1.0, seed=12, up=0.5, reach=(0.3, 0.45))
    kit.obj(bm, "Willow", "Trunk")
    bm = B()
    centers = [(0, 12, 0)] + [(t[0], t[1] + 0.5, t[2]) for t in tips]
    pk.canopy(bm, centers, 2.8, squash=(1.2, 0.6, 1.2), seed=70)
    lr = random.Random(3)
    for c in centers:
        for _ in range(6):
            a = lr.uniform(0, 2 * math.pi)
            r = lr.uniform(1.5, 3.2)
            x0, z0 = c[0] + math.cos(a) * r, c[2] + math.sin(a) * r
            pk.tube(bm, [(x0, c[1], z0), (x0 + 0.2, c[1] - 3, z0), (x0, c[1] - lr.uniform(5, 8), z0 + 0.2)], [0.18, 0.12, 0.05], segs=4)
    kit.obj(bm, "Willow", "Foliage")
    # Giant spotted mushroom.
    bm = B()
    pk.tube(bm, [(40, 0, 0), (40.4, 4, 0), (40, 8, 0)], [1.3, 0.9, 0.8], segs=10)
    kit.obj(bm, "Mushroom", "Stem")
    bm = B()
    pk.blob(bm, (40, 8.6, 0), 4.2, (1, 0.45, 1), rough=0.08, subdiv=3, seed=5)
    for v in bm.verts:
        if v.co.y < 8.2:
            v.co.y = 8.2 - (8.2 - v.co.y) * 0.25
    kit.obj(bm, "Mushroom", "Cap")
    # Glowing mushroom cluster.
    bm = B()
    lr = random.Random(9)
    for k in range(4):
        a = k / 4 * 2 * math.pi
        x, z = 60 + math.cos(a) * 1.2, math.sin(a) * 1.2
        h = lr.uniform(1.5, 3.5)
        pk.tube(bm, [(x, 0, z), (x, h, z)], [0.3, 0.25], segs=6)
    kit.obj(bm, "GlowShrooms", "Stem")
    bm = B()
    lr = random.Random(9)
    for k in range(4):
        a = k / 4 * 2 * math.pi
        x, z = 60 + math.cos(a) * 1.2, math.sin(a) * 1.2
        h = lr.uniform(1.5, 3.5)
        pk.blob(bm, (x, h + 0.2, z), 1.0, (1, 0.45, 1), rough=0.05, subdiv=2, seed=k)
    kit.obj(bm, "GlowShrooms", "Bloom")
    # Cattail reeds.
    bm = B()
    pk.blades(bm, 80, count=10, height=3.2, width=(0.05, 0.08), lean=(0.1, 0.4), seed=31)
    lr = random.Random(2)
    for k in range(3):
        a = lr.uniform(0, 2 * math.pi)
        x, z = 80 + math.cos(a) * 0.3, math.sin(a) * 0.3
        pk.tube(bm, [(x, 0, z), (x, 3.4, z)], [0.04, 0.03], segs=4)
        pk.blob(bm, (x, 3.6, z), 0.2, (1, 2.6, 1), rough=0.0, subdiv=1, seed=k)
    kit.obj(bm, "Reeds", "Blades")
    # Mossy fallen log.
    bm = B()
    pk.tube(bm, [(95, 0.9, -4), (95.3, 1.0, 0), (95, 0.9, 4)], [1.0, 1.05, 0.95], segs=12, cap=False)
    kit.obj(bm, "MossyLog", "Trunk")
    # Lily pads with a pink flower.
    bm = B()
    lr = random.Random(6)
    for k in range(5):
        cx, cz = 115 + lr.uniform(-2, 2), lr.uniform(-2, 2)
        r = lr.uniform(0.8, 1.4)
        ret = bmesh.ops.create_circle(bm, cap_ends=True, segments=14, radius=r)
        for vtx in ret["verts"]:
            x, y, _ = vtx.co
            vtx.co = Vector((cx + x, 0.05, cz + y))
    kit.obj(bm, "LilyPads", "Pads")
    # Low, gloomy hills.
    bm = B()
    pk.heightfield(bm, 600, 420, 140, 60, 20, pk.range_fn(110, peaks=2.0, sharp=0.7, seed=17.3))
    kit.obj(bm, "Range", "Rock")
    bake(kit, {
        "Willow_Trunk": (pk.bark((0.18, 0.15, 0.1), (0.06, 0.05, 0.03)), 256),
        "Willow_Foliage": (pk.leafy((0.18, 0.28, 0.08), (0.4, 0.5, 0.15)), 1024),
        "Mushroom_Stem": (pk.flat((0.9, 0.86, 0.75)), 128),
        "Mushroom_Cap": (pk.spotted((0.55, 0.15, 0.6), (0.95, 0.9, 0.7), scale=1.6, size=0.18), 512),
        "GlowShrooms_Stem": (pk.flat((0.85, 0.85, 0.7)), 64),
        "GlowShrooms_Bloom": (pk.flat((0.6, 1.0, 0.25)), 64),
        "Reeds_Blades": (pk.gradient_z(3.6, [(0.0, (0.2, 0.25, 0.08)), (0.8, (0.45, 0.5, 0.2)), (0.9, (0.3, 0.18, 0.08)), (1.0, (0.25, 0.15, 0.07))]), 128),
        "MossyLog_Trunk": (pk.snowy(pk.bark((0.22, 0.16, 0.1), (0.08, 0.06, 0.04)), cover=(0.25, 0.4, 0.1), lo=0.3, hi=0.6), 256),
        "LilyPads_Pads": (pk.leafy((0.15, 0.4, 0.1), (0.35, 0.6, 0.2)), 128),
        "Range_Rock": (pk.height_bands(110, [(0.0, (0.18, 0.2, 0.1)), (0.4, (0.22, 0.26, 0.14)), (1.0, (0.3, 0.33, 0.25))]), 1024),
    })


BUILDERS = {
    "FrostfallTundra": tundra,
    "EmberpeakVolcano": volcano,
    "TidebreakCoast": coast,
    "ThunderwildHighlands": highlands,
    "ToxicBloomSwamp": swamp,
}
# Each set is laid out in its own lane (Blender only; positions are normalised in Studio).
LANES = {name: i * 300 for i, name in enumerate(BUILDERS)}


def build(set_name):
    clear_set(set_name)
    col = collection()
    before = set(col.objects)
    BUILDERS[set_name](pk.Kit(col, set_name))
    for o in col.objects:
        if o not in before:
            o.location.y -= LANES[set_name]  # Blender -Y = Roblox +Z
    return sorted(o.name for o in col.objects if o not in before)


def export_all():
    col = collection()
    mf.export(col, os.path.join(HERE, "BiomeProps.fbx"))
    return {"objects": len(col.objects), "tris": mf.tri_count(col)}
