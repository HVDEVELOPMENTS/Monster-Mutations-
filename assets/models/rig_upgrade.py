"""Rebuilds the part-built species rigs (rigs.txt, dumped from Studio) as
sculpted, textured meshes, keeping every part's name and transform so the
game's anchors, colours and animation roles still line up.

rigs.txt rows: Species Name Kind Sx Sy Sz X Y Z R00 R01 R02 R10 R11 R12 R20 R21 R22 Material R,G,B
Kind: E ellipsoid, B ball, C cylinder (axis X), K block, W wedge (slope faces -Z).

Output objects are named "<Species>_<Piece>"; touching parts with the same name
are fused into one piece (a fin made of two wedges becomes one fin). Each species
also gets "<Species>_Origin", a tiny marker at its rig origin, which the Studio
normalise step uses to put pieces back in rig space. Species are laid out along
+X (8 studs apart) so they can be reviewed side by side.

Textures are grey-scale detail (one atlas per species, pattern per creature);
MonsterVisuals tints each piece with the colour its rig part would have had, so
palettes keep working. Neon/Glass/ForceField parts stay untextured.
Run in Blender with MF_MODELS set (see mossling.py).
"""

import math
import os
import sys

HERE = os.environ["MF_MODELS"]
sys.path.insert(0, HERE)

import importlib

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import mf_blender as mf

importlib.reload(mf)

SPACING = 8.0
PLAIN = {"Neon", "Glass", "ForceField"}

# Surface pattern per species (grey-scale detail under the palette tint).
PATTERN = {
    "Pebbleback": "rock", "Basaltback": "rock", "Thunderhorn": "fur",
    "Brookhopper": "skin", "Miretoad": "skin", "Sporeling": "speckle",
    "Snowmote": "fur", "Frostfang": "fur", "Sparkhare": "fur", "Ashwing": "fur",
    "Glimmerseal": "skin", "Reefling": "scales", "Coralback": "rock",
    "Seamist": "skin", "Stormcrest": "feathers", "Venomtail": "scales",
}


def load_rows():
    rows = {}
    with open(os.path.join(HERE, "rigs.txt"), encoding="utf-8") as fh:
        for line in fh:
            t = line.split()
            if len(t) < 20:
                continue
            sp = t[0]
            rows.setdefault(sp, []).append({
                "name": t[1], "kind": t[2],
                "size": Vector(tuple(float(v) for v in t[3:6])),
                "pos": Vector(tuple(float(v) for v in t[6:9])),
                "rot": Matrix([[float(t[9]), float(t[10]), float(t[11])],
                               [float(t[12]), float(t[13]), float(t[14])],
                               [float(t[15]), float(t[16]), float(t[17])]]),
                "material": t[18],
                "color": tuple(int(c) / 255 for c in t[19].split(",")),
            })
    return rows


# ----- local-space shapes (Roblox local axes, centred on the part) -----
def shape_verts_faces(kind, size, organic):
    bm = bmesh.new()
    sx, sy, sz = size
    if kind in ("E", "B"):
        segs = max(12, min(32, int(10 + max(size) * 7)))
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(8, segs // 2 + 2), radius=0.5)
        for v in bm.verts:
            bx, by, bz = v.co  # Z-up sphere: bz is Roblox y
            d = Vector((bx, bz, -by))
            if organic and max(size) > 0.9:
                d *= 1 + 0.035 * noise.noise(d * 3.1 + Vector((sx, sy, sz)))
            v.co = Vector((d.x * sx, d.y * sy, d.z * sz))
    elif kind == "C":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=18, radius1=0.5, radius2=0.5, depth=1.0)
        bmesh.ops.bevel(bm, geom=[e for e in bm.edges if len(e.link_faces) == 2 and abs(e.link_faces[0].normal.z) != abs(e.link_faces[1].normal.z)], offset=0.08, segments=3, affect="EDGES")
        for v in bm.verts:
            bx, by, bz = v.co  # cylinder axis Z -> Roblox X
            v.co = Vector((bz * sx, bx * sy, by * sz))
    elif kind == "K":
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(size) * 0.3, segments=3, affect="EDGES")
    else:  # wedge: bottom face, back face (+Z), slope down to the front-bottom edge
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        p = [bm.verts.new(c) for c in [
            (-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz),
            (-hx, hy, hz), (hx, hy, hz)]]
        for f in [(0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)]:
            bm.faces.new([p[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(size) * 0.22, segments=2, affect="EDGES")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def world_aabb(row):
    """Axis-aligned box of a rotated part (for fusing touching parts)."""
    half = row["size"] / 2
    ext = Vector((sum(abs(row["rot"][i][j]) * half[j] for j in range(3)) for i in range(3)))
    return row["pos"] - ext, row["pos"] + ext


def clusters(parts):
    """Groups same-named parts whose boxes touch."""
    n = len(parts)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    boxes = [world_aabb(p) for p in parts]
    for i in range(n):
        for j in range(i + 1, n):
            if parts[i]["name"] != parts[j]["name"]:
                continue
            if parts[i]["kind"] == "W" and parts[j]["kind"] == "W":
                # fin()/spike() place their wedges one wedge-depth apart around a
                # shared base; neighbouring spikes in a row are further apart.
                reach = max(parts[i]["size"].z, parts[j]["size"].z) * 1.05
                if (parts[i]["pos"] - parts[j]["pos"]).length <= reach:
                    parent[find(i)] = find(j)
                continue
            (a0, a1), (b0, b1) = boxes[i], boxes[j]
            if all(a0[k] <= b1[k] + 0.03 and b0[k] <= a1[k] + 0.03 for k in range(3)):
                parent[find(i)] = find(j)
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(parts[i])
    return list(groups.values())


def build_species(sp, parts, offset, col):
    objs = []
    for group in clusters(parts):
        bm = bmesh.new()
        name = group[0]["name"]
        plain = group[0]["material"] in PLAIN
        wedges = all(row["kind"] == "W" for row in group)
        if wedges:
            # Fins, ears, spikes, beaks and crests are built from thin wedge pairs or
            # quads; their convex hull is the clean shape they stand for.
            pts = []
            for row in group:
                hx, hy, hz = row["size"] / 2
                for c in [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), (-hx, hy, hz), (hx, hy, hz)]:
                    w = row["pos"] + row["rot"] @ Vector(c)
                    pts.append(bm.verts.new(mf.R(w.x + offset, w.y, w.z)))
            bmesh.ops.convex_hull(bm, input=pts)
            loose = [v for v in bm.verts if not v.link_faces]
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
            thin = min(min(row["size"]) for row in group)
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=thin * 0.18, segments=2, affect="EDGES", clamp_overlap=True)
        else:
            for row in group:
                sub = shape_verts_faces(row["kind"], row["size"], organic=not plain)
                for v in sub.verts:
                    w = row["pos"] + row["rot"] @ Vector(v.co)
                    v.co = mf.R(w.x + offset, w.y, w.z)
                me_tmp = bpy.data.meshes.new("tmp")
                sub.to_mesh(me_tmp)
                sub.free()
                bm.from_mesh(me_tmp)
                bpy.data.meshes.remove(me_tmp)
        o = mf._object(col, "%s_%s" % (sp, name), bm, smooth=not wedges)
        o["plain"] = plain
        o["rig_color"] = group[0]["color"]
        objs.append(o)
    # Rig-origin marker for the Studio normaliser.
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=0.1)
    for v in bm.verts:
        v.co = mf.R(v.co.x + offset, v.co.z, -v.co.y)
    mf._object(col, sp + "_Origin", bm, smooth=False)
    return objs


# ----- grey-scale detail patterns (multiplied by the palette tint in Roblox) -----
def pattern(kind):
    def build(nodes, links):
        if kind == "fur":
            tc = nodes.new("ShaderNodeTexCoord")
            mp = nodes.new("ShaderNodeMapping")
            mp.inputs["Scale"].default_value = (22.0, 22.0, 4.0)
            links.new(tc.outputs["Object"], mp.inputs["Vector"])
            nz = nodes.new("ShaderNodeTexNoise")
            nz.inputs["Detail"].default_value = 10
            links.new(mp.outputs[0], nz.inputs["Vector"])
            rng = nodes.new("ShaderNodeMapRange")
            links.new(nz.outputs["Fac"], rng.inputs["Value"])
            rng.inputs["From Min"].default_value = 0.3
            rng.inputs["From Max"].default_value = 0.7
            rng.inputs["To Min"].default_value = 0.62
            rng.inputs["To Max"].default_value = 1.0
            return mf.gray(nodes, links, rng.outputs["Result"])
        if kind in ("scales", "feathers"):
            vor = nodes.new("ShaderNodeTexVoronoi")
            vor.feature = "DISTANCE_TO_EDGE"
            vor.inputs["Scale"].default_value = 9.0 if kind == "scales" else 5.0
            tc = nodes.new("ShaderNodeTexCoord")
            if kind == "feathers":
                mp = nodes.new("ShaderNodeMapping")
                mp.inputs["Scale"].default_value = (1.0, 1.0, 2.5)
                links.new(tc.outputs["Object"], mp.inputs["Vector"])
                links.new(mp.outputs[0], vor.inputs["Vector"])
            else:
                links.new(tc.outputs["Object"], vor.inputs["Vector"])
            rng = nodes.new("ShaderNodeMapRange")
            links.new(vor.outputs["Distance"], rng.inputs["Value"])
            rng.inputs["From Min"].default_value = 0.0
            rng.inputs["From Max"].default_value = 0.12
            rng.inputs["To Min"].default_value = 0.45
            rng.inputs["To Max"].default_value = 1.0
            fine = mf.noise_value(nodes, links, 30, detail=4, lo=0.85, hi=1.05)
            return mf.gray(nodes, links, mf.multiply(nodes, links, rng.outputs["Result"], fine))
        if kind == "rock":
            base = mf.noise_value(nodes, links, 4, detail=8, lo=0.55, hi=1.0, roughness=0.65)
            vor = nodes.new("ShaderNodeTexVoronoi")
            vor.feature = "DISTANCE_TO_EDGE"
            vor.inputs["Scale"].default_value = 3.5
            tc = nodes.new("ShaderNodeTexCoord")
            links.new(tc.outputs["Object"], vor.inputs["Vector"])
            cracks = nodes.new("ShaderNodeMapRange")
            links.new(vor.outputs["Distance"], cracks.inputs["Value"])
            cracks.inputs["From Min"].default_value = 0.0
            cracks.inputs["From Max"].default_value = 0.05
            cracks.inputs["To Min"].default_value = 0.5
            cracks.inputs["To Max"].default_value = 1.0
            return mf.gray(nodes, links, mf.multiply(nodes, links, base, cracks.outputs["Result"]))
        if kind == "speckle":
            base = mf.noise_value(nodes, links, 6, detail=4, lo=0.8, hi=1.0)
            dots = mf.noise_value(nodes, links, 40, detail=1, lo=0.7, hi=1.15)
            return mf.gray(nodes, links, mf.multiply(nodes, links, base, dots))
        # "skin": soft mottling with a few darker blotches
        blot = mf.noise_value(nodes, links, 5, detail=3, lo=0.68, hi=1.0)
        fine = mf.noise_value(nodes, links, 25, detail=6, lo=0.88, hi=1.04)
        return mf.gray(nodes, links, mf.multiply(nodes, links, blot, fine))
    return build


def bake_atlas(sp, objs, size=1024):
    """One shared UV atlas + one bake for all textured pieces of a species."""
    textured = [o for o in objs if not o["plain"]]
    if not textured:
        return
    for s in bpy.context.selected_objects:
        s.select_set(False)
    for o in textured:
        o.select_set(True)
    bpy.context.view_layer.objects.active = textured[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(sp + "_Atlas", size, size)
    builder = pattern(PATTERN.get(sp, "skin"))
    for o in textured:
        mat = bpy.data.materials.new(o.name + "_Bake")
        mat.use_nodes = True
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        for nd in list(nodes):
            nodes.remove(nd)
        out = nodes.new("ShaderNodeOutputMaterial")
        emit = nodes.new("ShaderNodeEmission")
        links.new(builder(nodes, links), emit.inputs["Color"])
        links.new(emit.outputs["Emission"], out.inputs["Surface"])
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = img
        nodes.active = tex
        o.data.materials.clear()
        o.data.materials.append(mat)
    scene = bpy.context.scene
    try:
        scene.render.engine = "CYCLES"
    except TypeError:
        pass
    scene.cycles.samples = 1
    bpy.ops.object.bake(type="EMIT", margin=6)
    img.filepath_raw = os.path.join(HERE, "textures", sp + "_Atlas.png")
    img.file_format = "PNG"
    img.save()
    # Swap each bake material to a plain textured one (what the FBX exporter embeds).
    for o in textured:
        nt = o.data.materials[0].node_tree
        for nd in list(nt.nodes):
            if nd.type not in ("OUTPUT_MATERIAL", "TEX_IMAGE"):
                nt.nodes.remove(nd)
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        tex = next(nd for nd in nt.nodes if nd.type == "TEX_IMAGE")
        out = next(nd for nd in nt.nodes if nd.type == "OUTPUT_MATERIAL")
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])


def run(only=None):
    rows = load_rows()
    col = mf.reset_collection("Upgraded")
    os.makedirs(os.path.join(HERE, "textures"), exist_ok=True)
    report = {}
    for i, sp in enumerate(sorted(rows)):
        if only and sp not in only:
            continue
        objs = build_species(sp, rows[sp], i * SPACING, col)
        bake_atlas(sp, objs)
        report[sp] = (len(objs), sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs))
    return col, report


if __name__ == "__main__":
    col, report = run()
    for sp, (pieces, tris) in sorted(report.items()):
        print("%-12s %3d pieces %6d tris" % (sp, pieces, tris))
