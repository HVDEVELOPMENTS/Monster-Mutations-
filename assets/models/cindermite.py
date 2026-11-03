"""Cindermite, reference style: a chunky molten-rock block on stubby legs, with
bevelled edges, glowing lava cracks (baked texture), arms and a crown of flames.

Pieces (names drive MonsterVisuals animation roles): Body, Leg x2, Arm x2,
Flame (one object per flame tongue). Eyes and mouth are drawn by drawFace
("Molten" style) from RigAnchors.Cindermite.
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

col = mf.reset_collection("Cindermite")
rng = random.Random(7)


def rock_block(name, size, center, bevel, rough=0.05, seed=0):
    """Rounded box: bevelled cube, subdivided, nudged with noise so it reads as
    hewn rock rather than plastic."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=4, profile=0.5, affect="EDGES")
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    for v in bm.verts:
        n = noise.noise(v.co * 1.7 + Vector((seed, seed * 2, seed * 3)))
        v.co += v.normal * n * rough
    # bm verts are in local Roblox space (x, y=up, z) at this point.
    mf._place(bm, cf(center))
    return mf._object(col, name, bm)


# Body: about 2.5 studs wide/tall, a touch deeper at the base.
rock_block("Body", (2.5, 2.3, 2.2), (0, 1.85, 0), 0.38, rough=0.06, seed=1)

for side in (-1, 1):
    rock_block("Leg", (0.75, 0.7, 0.8), (side * 0.62, 0.36, 0.05), 0.2, rough=0.03, seed=2 + side)
    rock_block("Arm", (0.55, 0.95, 0.6), (side * 1.42, 1.5, -0.05), 0.2, rough=0.03, seed=5 + side)

# Crown of flames: tongues of different heights, leaning outward, curling back.
for i, (x, z, h, lean) in enumerate(
    [(0, -0.1, 1.3, 0.0), (-0.6, 0.15, 0.95, 0.35), (0.6, 0.1, 1.0, -0.35), (-0.25, 0.55, 0.8, 0.2), (0.3, -0.5, 0.75, -0.15)]
):
    mf.flame(col, "Flame", cf((x, 2.75, z), rx=0.1, rz=lean), h, 0.32 + h * 0.1, wave=0.14, phase=i * 1.3)

# UVs for the baked texture (flames are untextured Neon in Roblox).
for o in col.objects:
    if o.name.startswith("Flame"):
        continue
    bpy.context.view_layer.objects.active = o
    for s in bpy.context.selected_objects:
        s.select_set(False)
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")



def lava(nodes, links):
    """Molten rock: red-orange plates split by glowing yellow cracks, with a
    soft glow bleeding out of each crack and mottled rock in between."""
    coord = nodes.new("ShaderNodeTexCoord")
    warp = nodes.new("ShaderNodeTexNoise")
    warp.inputs["Scale"].default_value = 3.0
    links.new(coord.outputs["Object"], warp.inputs["Vector"])
    mix = nodes.new("ShaderNodeVectorMath")
    mix.operation = "MULTIPLY_ADD"
    links.new(warp.outputs["Color"], mix.inputs[0])
    mix.inputs[1].default_value = (0.35, 0.35, 0.35)
    links.new(coord.outputs["Object"], mix.inputs[2])
    vor = nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 1.3
    links.new(mix.outputs[0], vor.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
    els = ramp.color_ramp.elements
    stops = [
        (0.0, (1.0, 0.85, 0.3)),
        (0.025, (1.0, 0.42, 0.04)),
        (0.07, (0.45, 0.06, 0.015)),
        (0.16, (0.2, 0.035, 0.015)),
        (1.0, (0.13, 0.025, 0.012)),
    ]
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
    els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1)
    for pos, c in stops[1:-1]:
        e = els.new(pos)
        e.color = (*c, 1)
    mottle = nodes.new("ShaderNodeTexNoise")
    mottle.inputs["Scale"].default_value = 9.0
    links.new(coord.outputs["Object"], mottle.inputs["Vector"])
    mramp = nodes.new("ShaderNodeMapRange")
    links.new(mottle.outputs["Fac"], mramp.inputs["Value"])
    mramp.inputs["To Min"].default_value = 0.75
    mramp.inputs["To Max"].default_value = 1.25
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    # The Mix node has float/vector/colour variants of A, B and Result; pick the colour ones.
    a = next(s for s in mul.inputs if s.name == "A" and s.type == "RGBA")
    b = next(s for s in mul.inputs if s.name == "B" and s.type == "RGBA")
    links.new(ramp.outputs["Color"], a)
    links.new(mramp.outputs["Result"], b)
    return next(s for s in mul.outputs if s.type == "RGBA")


for o in list(col.objects):
    if not o.name.startswith("Flame"):
        base = o.name.split(".")[0]
        idx = o.name.split(".")[1] if "." in o.name else "0"
        fname = "Cindermite_%s%s.png" % (base, "" if base == "Body" else idx)
        mf.bake_color(o, lava, 1024 if base == "Body" else 256, os.path.join(HERE, "textures", fname))

print("Cindermite objects:", sorted(o.name for o in col.objects), "tris:", mf.tri_count(col))
