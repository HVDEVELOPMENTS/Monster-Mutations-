"""Mossling: round moss blob with two head leaves and a spiky back.

Proportions follow Rigs.Mossling in MonsterVisuals so the anchors there
(eyes, mouth, Head/Back, Body = { Center = (0, 1.75, 0), Radius = 1.35 }) still fit.
Run in Blender: exec(open(path).read()) with this folder on sys.path.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.environ["MF_MODELS"]
sys.path.insert(0, HERE)

import importlib

import mf_blender as mf

importlib.reload(mf)
cf = mf.cframe

col = mf.reset_collection("Mossling")


def body_shape(x, y, z):
    k = y / 1.35
    widen = 1 + 0.08 * -k  # pear: fuller at the bottom
    x, z = x * widen, z * widen
    if y < -1.0:  # sits flat
        y = -1.0 + (y + 1.0) * 0.4
    return x, y, z


mf.ellipsoid(col, "Body", (3.0, 2.7, 2.8), cf((0, 1.75, 0)), body_shape, segs=32, rings=18)


def belly_shape(x, y, z):
    # Edges curve back into the body so the patch hugs it.
    return x, y, z + 0.5 * (x / 0.95) ** 2 + 0.38 * (y / 0.8) ** 2


mf.ellipsoid(col, "Belly", (1.9, 1.6, 0.6), cf((0, 1.3, -1.08)), belly_shape)


def foot_shape(x, y, z):
    if y < -0.15:
        y = -0.15 + (y + 0.15) * 0.3
    return x, y, z - 0.04


for x in (-0.85, 0.85):
    for z in (-0.75, 0.75):
        mf.ellipsoid(col, "Foot", (0.85, 0.7, 0.85), cf((x, 0.35, z)), foot_shape, segs=16, rings=10)
    claws = [
        mf.cone(col, "Claw", cf((x + dx, 0.2, -1.02), rx=-math.pi / 2), 0.3, 0.08, bend=-0.06, segs=8)
        for dx in (-0.15, 0.15)
    ]
    mf.join(claws, "Claw")

for x, rz in ((-0.32, 0.4), (0.32, -0.4)):
    mf.leaf(col, "Leaf", cf((x, 2.92, 0), rz=rz), 1.3, 0.85, thick=0.07, cup=0.1, curl=0.12)

spikes = [
    mf.cone(col, "BackSpike", cf((0, 2.85 - k * 0.3, 0.45 + k * 0.42), rx=0.5 + k * 0.3), 0.6, 0.21, bend=0.12)
    for k in range(3)
]
mf.join(spikes, "BackSpike")



# ===== Textures =====
# Body, belly and feet get grey-scale moss detail: Roblox tints it with the
# palette colour (SurfaceAppearance.Color), so Moss/Fern/Lime variants still work.
# Leaves get a fixed coloured texture. Claws and spikes stay plain.
def moss(nodes, links):
    # Values are linear; the sRGB PNG brightens them, so the range is wide on purpose.
    clumps = mf.noise_value(nodes, links, 4.5, detail=3, lo=0.3, hi=0.95)
    fine = mf.noise_value(nodes, links, 26.0, detail=8, lo=0.55, hi=1.05, roughness=0.7)
    return mf.gray(nodes, links, mf.multiply(nodes, links, clumps, fine))


def fuzz(nodes, links):
    return mf.gray(nodes, links, mf.noise_value(nodes, links, 30.0, detail=6, lo=0.6, hi=1.0))


def leaf_color(nodes, links):
    v = mf.noise_value(nodes, links, 9.0, detail=4, lo=0.78, hi=1.12)
    base = nodes.new("ShaderNodeRGB")
    base.outputs[0].default_value = (0.2, 0.62, 0.12, 1)
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    a = next(s for s in mix.inputs if s.name == "A" and s.type == "RGBA")
    b = next(s for s in mix.inputs if s.name == "B" and s.type == "RGBA")
    links.new(base.outputs[0], a)
    links.new(mf.gray(nodes, links, v), b)
    return next(s for s in mix.outputs if s.type == "RGBA")


TEX = os.path.join(HERE, "textures")
os.makedirs(TEX, exist_ok=True)
for o in list(col.objects):
    base = o.name.split(".")[0]
    maker = {"Body": moss, "Foot": moss, "Belly": fuzz, "Leaf": leaf_color}.get(base)
    if not maker:
        continue
    mf.smart_uv(o)
    idx = o.name.split(".")[1] if "." in o.name else "0"
    size = 1024 if base == "Body" else 256
    mf.bake_color(o, maker, size, os.path.join(TEX, "Mossling_%s%s.png" % (base, idx)))

print("Mossling objects:", sorted(o.name for o in col.objects), "tris:", mf.tri_count(col))
