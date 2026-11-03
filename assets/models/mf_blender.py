"""Shared helpers for building Monster Factory species meshes in Blender.

Everything is authored in Roblox space (studs, Y up, monster facing -Z) and
converted on the way in: Roblox (X, Y, Z) -> Blender (X, -Z, Y). The FBX
export (forward -Z, up Y) converts back, so the Studio importer sees the
original Roblox coordinates.

Each animated piece is its own object, named like the part names
MonsterVisuals.ROLE_BY_NAME expects (Body, Foot, Leaf, Tail, ...). Blender
adds ".001" suffixes to repeated names; the Studio normalise step strips them.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector


def R(x, y, z):
    return Vector((x, -z, y))


def cframe(pos=(0, 0, 0), rx=0.0, ry=0.0, rz=0.0):
    """Roblox CFrame.new(pos) * CFrame.Angles(rx, ry, rz), in Roblox space."""
    rot = Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rz, 4, "Z")
    return Matrix.Translation(Vector(pos)) @ rot


def reset_collection(name):
    col = bpy.data.collections.get(name)
    if col:
        for o in list(col.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        col = bpy.data.collections.new(name)
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    return col


def _object(col, name, bm, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    return obj


def _place(bm, cf):
    """Moves Roblox-space verts by cf and converts them to Blender space."""
    for v in bm.verts:
        p = cf @ Vector(v.co)
        v.co = R(p.x, p.y, p.z)


def ellipsoid(col, name, size, cf, deform=None, segs=24, rings=14):
    """Ellipsoid of `size` (studs) at Roblox CFrame `cf`. deform(x, y, z) works
    in local Roblox space on the already-sized shape."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=0.5)
    for v in bm.verts:
        bx, by, bz = v.co  # create_uvsphere is Z-up: use bz as Roblox Y
        x, y, z = bx * size[0], bz * size[1], -by * size[2]
        if deform:
            x, y, z = deform(x, y, z)
        v.co = Vector((x, y, z))
    _place(bm, cf)
    return _object(col, name, bm)


def cone(col, name, cf, h, r, bend=0.0, segs=10, rings=6):
    """Rounded cone: base centre at cf, tip at cf * (0, h, 0), tip curling
    towards +Z by `bend` studs."""
    bm = bmesh.new()
    loops = []
    for i in range(rings + 1):
        t = i / rings
        rad = r * (1 - t) ** 0.9 if i < rings else 0.0
        off = bend * t * t
        if i < rings:
            loop = [bm.verts.new((math.cos(a) * rad, t * h, math.sin(a) * rad + off))
                    for a in (2 * math.pi * k / segs for k in range(segs))]
            loops.append(loop)
        else:
            tip = bm.verts.new((0, h, off))
    for a, b in zip(loops, loops[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    last = loops[-1]
    for k in range(segs):
        bm.faces.new((last[k], last[(k + 1) % segs], tip))
    bm.faces.new(list(reversed(loops[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, cf)
    return _object(col, name, bm)


def flame(col, name, cf, h, r, wave=0.12, phase=0.0, segs=12, rings=10):
    """Flame tongue: teardrop profile (widest a quarter of the way up, needle
    tip) that sways side to side along its height. Base at cf, tip at
    cf * (0, h, 0)."""
    bm = bmesh.new()
    loops = []
    for i in range(rings):
        t = i / rings
        rad = r * math.sin(math.pi * (0.25 + 0.75 * t)) ** 1.2 * (1 - t) ** 0.35
        dx = wave * math.sin(t * math.pi * 1.6 + phase) * t
        dz = 0.35 * wave * t * t
        loops.append([bm.verts.new((math.cos(a) * rad + dx, t * h, math.sin(a) * rad * 0.8 + dz))
                      for a in (2 * math.pi * k / segs for k in range(segs))])
    tip = bm.verts.new((wave * math.sin(math.pi * 1.6 + phase), h, 0.35 * wave))
    for a, b in zip(loops, loops[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    for k in range(segs):
        bm.faces.new((loops[-1][k], loops[-1][(k + 1) % segs], tip))
    bm.faces.new(list(reversed(loops[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, cf)
    return _object(col, name, bm)


def smart_uv(obj, angle=66, margin=0.02):
    """Smart UV project one object (needed before baking a texture onto it)."""
    for s in bpy.context.selected_objects:
        s.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def noise_value(nodes, links, scale, detail=4.0, lo=0.0, hi=1.0, roughness=0.5):
    """Object-space noise remapped to [lo, hi]; returns the float socket."""
    coord = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = detail
    noise.inputs["Roughness"].default_value = roughness
    links.new(coord.outputs["Object"], noise.inputs["Vector"])
    rng = nodes.new("ShaderNodeMapRange")
    links.new(noise.outputs["Fac"], rng.inputs["Value"])
    rng.inputs["From Min"].default_value = 0.3
    rng.inputs["From Max"].default_value = 0.7
    rng.inputs["To Min"].default_value = lo
    rng.inputs["To Max"].default_value = hi
    return rng.outputs["Result"]


def multiply(nodes, links, a, b):
    m = nodes.new("ShaderNodeMath")
    m.operation = "MULTIPLY"
    links.new(a, m.inputs[0])
    links.new(b, m.inputs[1])
    return m.outputs[0]


def gray(nodes, links, value_socket):
    """Float -> grey colour socket."""
    c = nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        links.new(value_socket, c.inputs[i])
    return c.outputs[0]


def bake_color(obj, color_socket_builder, size, path):
    """Bakes a node-built colour (no lighting) into an image texture at `path`.
    color_socket_builder(nodes, links) returns the output socket to bake. The
    object keeps a preview material using the same colour as base + emission."""
    scene = bpy.context.scene
    try:
        scene.render.engine = "CYCLES"
    except TypeError:
        pass
    scene.cycles.samples = 1
    mat = bpy.data.materials.new(obj.name + "_Bake")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    links.new(color_socket_builder(nodes, links), emit.inputs["Color"])
    links.new(emit.outputs["Emission"], out.inputs["Surface"])
    img = bpy.data.images.new(obj.name + "_Color", size, size)
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    nodes.active = tex
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="EMIT", margin=8)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    # Swap to a textured material for preview/export.
    for n in list(nodes):
        if n not in (out, tex):
            nodes.remove(n)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs[0], out.inputs["Surface"])
    return img


def leaf(col, name, cf, length, width, thick=0.08, cup=0.12, curl=0.15, steps=12, across=6):
    """Leaf blade in the local YZ plane (thin in X): base at cf, tip at
    cf * (0, length, 0). `cup` bends the edges towards +X, `curl` bends the
    tip towards +Z."""
    bm = bmesh.new()
    grid = []
    for i in range(steps + 1):
        t = i / steps
        # Narrow stem at the base, pointed tip.
        half = width / 2 * max(math.sin(math.pi * t) ** 0.75 * (1 - 0.25 * t), 0.06 if t < 0.5 else 0.01)
        row = []
        for j in range(across + 1):
            s = j / across * 2 - 1
            z = s * half + curl * t * t
            x = cup * (s * s) * (half / (width / 2 + 1e-6))
            row.append((x, t * length, z))
        grid.append(row)
    top, bot = [], []
    for row in grid:
        top.append([bm.verts.new((x + thick / 2, y, z)) for x, y, z in row])
        bot.append([bm.verts.new((x - thick / 2, y, z)) for x, y, z in row])
    for i in range(steps):
        for j in range(across):
            bm.faces.new((top[i][j], top[i][j + 1], top[i + 1][j + 1], top[i + 1][j]))
            bm.faces.new((bot[i][j], bot[i + 1][j], bot[i + 1][j + 1], bot[i][j + 1]))
    for i in range(steps):  # side walls
        for j in (0, across):
            bm.faces.new((top[i][j], top[i + 1][j], bot[i + 1][j], bot[i][j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, cf)
    return _object(col, name, bm)


def join(objs, name):
    """Joins objects into one (for pieces that animate together)."""
    ctx = bpy.context
    for o in ctx.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    ctx.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def tri_count(col):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in col.objects if o.type == "MESH")


def export(col, fbx_path, blend_path=None):
    ctx = bpy.context
    for o in ctx.selected_objects:
        o.select_set(False)
    for o in col.objects:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="COPY",
        embed_textures=True,
    )
    if blend_path:
        bpy.ops.wm.save_as_mainfile(filepath=blend_path, copy=True)
