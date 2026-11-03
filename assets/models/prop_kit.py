"""Shared helpers for world prop packs (biome_props.py): Roblox-space geometry
(blobs, tubes, trunks, foliage, grass, rocks, mountain ranges, crystals, cones)
and procedural colour builders that mf_blender.bake_color bakes to textures.

Everything is built in Roblox space (x, y = up, z) and converted once in
Kit.obj, so prop code reads like the game. Pieces are named
"<Set>-<Prop>_<Piece>"; the Studio normaliser groups them by set and prop.
"""

import math
import random

import bmesh
from mathutils import Vector, noise

import mf_blender as mf


class Kit:
    def __init__(self, col, set_name):
        self.col = col
        self.set = set_name

    # ----- objects -----
    def obj(self, bm, prop, piece):
        for v in bm.verts:
            x, y, z = v.co
            v.co = mf.R(x, y, z)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return mf._object(self.col, "%s-%s_%s" % (self.set, prop, piece), bm)


# ----- geometry (all add to a bmesh, Roblox space) -----
def blob(bm, center, radius, squash=(1, 1, 1), rough=0.18, subdiv=2, seed=0):
    """Displaced icosphere (lumpy foliage clump / rock)."""
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in ret["verts"]:
        d = Vector(v.co)
        n = noise.noise(d * 2.2 + Vector((seed, seed * 1.7, seed * 2.3)))
        r = radius * (1 + rough * n)
        v.co = Vector((center[0] + d.x * r * squash[0], center[1] + d.z * r * squash[1], center[2] - d.y * r * squash[2]))
    return ret


def tube(bm, points, radii, segs=8, cap=True):
    """Tapered tube through points (trunk, branch, stem, coral arm)."""
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
    if cap:
        tip = bm.verts.new(Vector(points[-1]))
        for k in range(segs):
            bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segs], tip))


def trunk_points(base, height, bend, seed, steps=6):
    return [(base[0] + bend * math.sin(i * 0.9 + seed) * (i / steps), base[1] + height * i / steps, base[2] + bend * math.cos(i * 0.7 + seed) * (i / steps)) for i in range(steps + 1)]


def branchy(bm, base, height, r0, branches, bend=0.6, seed=0, up=0.7, reach=(0.25, 0.38)):
    """Trunk with branches; returns branch tip positions."""
    lr = random.Random(seed)
    pts = trunk_points(base, height, bend, seed)
    tube(bm, pts, [r0 * (1.5 if i == 0 else 1 - 0.12 * i) for i in range(7)], segs=10)
    tips = []
    for k in range(branches):
        h = height * lr.uniform(0.5, 0.85)
        a = k / branches * 2 * math.pi + lr.uniform(-0.3, 0.3)
        length = height * lr.uniform(*reach)
        start = (base[0], base[1] + h, base[2])
        end = (base[0] + math.cos(a) * length, base[1] + h + length * up, base[2] + math.sin(a) * length)
        mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2 + 0.3, (start[2] + end[2]) / 2)
        tube(bm, [start, mid, end], [r0 * 0.45, r0 * 0.32, r0 * 0.12], segs=6)
        tips.append(end)
    return tips


def canopy(bm, centers, radius, squash=(1, 0.8, 1), seed=0):
    """A main clump per centre plus two satellites, so the outline breaks up."""
    lr = random.Random(seed)
    for i, c in enumerate(centers):
        r = radius * lr.uniform(0.8, 1.1)
        blob(bm, c, r, squash, rough=0.2, subdiv=3, seed=seed + i)
        for k in range(2):
            d = Vector((lr.uniform(-1, 1), lr.uniform(-0.3, 0.8), lr.uniform(-1, 1))).normalized() * r * 0.75
            blob(bm, (c[0] + d.x, c[1] + d.y, c[2] + d.z), r * lr.uniform(0.45, 0.6), squash, rough=0.25, subdiv=2, seed=seed + 50 + i * 3 + k)


def blades(bm, x, count=11, height=2.2, spread=0.55, width=(0.09, 0.14), lean=(0.2, 0.7), seed=0, z=0.0):
    """Clump of tapered grass blades (also reeds, kelp, dry grass)."""
    lr = random.Random(seed)
    for _ in range(count):
        a = lr.uniform(0, 2 * math.pi)
        r = lr.uniform(0, spread)
        bx, bz = x + math.cos(a) * r, z + math.sin(a) * r
        h = height * lr.uniform(0.6, 1.1)
        ln = lr.uniform(*lean)
        face = lr.uniform(0, math.pi)
        w = lr.uniform(*width)
        verts = []
        steps = 5
        for s in range(steps + 1):
            t = s / steps
            cx = bx + math.cos(a) * ln * t * t
            cz = bz + math.sin(a) * ln * t * t
            half = w * (1 - t) + 0.005
            dx, dz = math.cos(face) * half, math.sin(face) * half
            verts.append((bm.verts.new((cx - dx, h * t, cz - dz)), bm.verts.new((cx + dx, h * t, cz + dz))))
        for (l0, r0), (l1, r1) in zip(verts, verts[1:]):
            bm.faces.new((l0, r0, r1, l1))


def rock(bm, x, size, seed, z=0.0, rough=0.32):
    blob(bm, (x, size[1] * 0.35, z), 1.0, size, rough=rough, subdiv=3, seed=seed)


def flatten_base(bm, floor=0.0):
    for v in bm.verts:
        if v.co.y < floor:
            v.co.y = floor + (v.co.y - floor) * 0.15


def crystal(bm, base, height, radius, tilt=(0.0, 0.0), sides=6, point=0.35):
    """Pointed prism (ice/obsidian/storm crystal)."""
    tx, tz = tilt
    up = Vector((math.sin(tx), 1, math.sin(tz))).normalized()
    a = up.orthogonal().normalized()
    b = up.cross(a).normalized()
    base = Vector(base)
    rings = []
    for h, r in ((0.0, radius), (height * (1 - point), radius * 0.9)):
        rings.append([bm.verts.new(base + up * h + (a * math.cos(k / sides * 2 * math.pi) + b * math.sin(k / sides * 2 * math.pi)) * r) for k in range(sides)])
    for k in range(sides):
        bm.faces.new((rings[0][k], rings[0][(k + 1) % sides], rings[1][(k + 1) % sides], rings[1][k]))
    tip = bm.verts.new(base + up * height)
    for k in range(sides):
        bm.faces.new((rings[1][k], rings[1][(k + 1) % sides], tip))
    bm.faces.new(list(reversed(rings[0])))


def cone_tiers(bm, x, tiers, wobble=0.12, segs=14, z=0.0):
    """Stacked cones (pine tiers): tiers = [(y, radius, height)]."""
    for k, (y, r, h) in enumerate(tiers):
        ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=0.2, depth=h)
        for v in ret["verts"]:
            bx, by, bz = v.co
            wob = 1 + wobble * math.sin(math.atan2(by, bx) * 7 + k)
            v.co = Vector((x + bx * wob, y + h / 2 + bz, z - by * wob))


def heightfield(bm, x, W, D, nx, nz, height_fn):
    """Grid of (W x D) studs centred on x; height_fn(u, v) -> y (>= 0)."""
    grid = []
    for i in range(nx + 1):
        row = []
        for j in range(nz + 1):
            u, v = i / nx, j / nz
            row.append(bm.verts.new((x - W / 2 + u * W, max(height_fn(u, v), 0), -D / 2 + v * D)))
        grid.append(row)
    flat = []
    for i in range(nx):
        for j in range(nz):
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            if all(v.co.y <= 0.001 for v in f.verts):
                flat.append(f)
    # Faces lying flat on the ground would flicker against the terrain: drop them.
    bmesh.ops.delete(bm, geom=flat, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")


def range_fn(H, peaks=3.2, sharp=1.0, seed=3.1):
    """Mountain-range height function (ridged noise, edges drop to 0)."""
    def f(u, v):
        edge = math.sin(math.pi * u) ** 0.7 * math.sin(math.pi * v) ** 0.9
        ridge = (1 - abs(noise.noise(Vector((u * 4.5, v * 2.0, seed))))) ** sharp
        pk = 0.55 + 0.45 * math.sin(u * math.pi * peaks + 0.6) ** 2
        detail = noise.noise(Vector((u * 18, v * 9, seed + 4.6))) * 0.08
        return H * edge * (0.45 * ridge + 0.55 * pk) + H * detail * edge
    return f


# ----- colour builders for mf.bake_color -----
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


def up_mask(nodes, links, lo=0.45, hi=0.75):
    """0 on sides/underside, 1 on up-facing surfaces (for snow, moss, sand)."""
    geo = nodes.new("ShaderNodeNewGeometry")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Normal"], sep.inputs[0])
    m = ramp(nodes, links, sep.outputs["Z"], [(lo, (0, 0, 0)), (hi, (1, 1, 1))])
    s = nodes.new("ShaderNodeSeparateColor")
    links.new(m, s.inputs[0])
    return s.outputs[0]


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


def snowy(inner, cover=(0.92, 0.95, 1.0), lo=0.35, hi=0.6):
    """Any colour builder with snow on everything facing up."""
    def build(nodes, links):
        return mix(nodes, links, up_mask(nodes, links, lo, hi), inner(nodes, links), rgb(nodes, cover))
    return build


def bark(base, dark, streak=(12.0, 12.0, 1.2)):
    def build(nodes, links):
        tc = nodes.new("ShaderNodeTexCoord")
        mapn = nodes.new("ShaderNodeMapping")
        mapn.inputs["Scale"].default_value = streak
        links.new(tc.outputs["Object"], mapn.inputs["Vector"])
        nz = nodes.new("ShaderNodeTexNoise")
        nz.inputs["Detail"].default_value = 8
        links.new(mapn.outputs[0], nz.inputs["Vector"])
        return ramp(nodes, links, nz.outputs["Fac"], [(0.35, dark), (0.55, base), (0.75, tuple(min(1, c * 1.2) for c in base))])
    return build


def stone(dark, mid, light, scale=3.0):
    def build(nodes, links):
        return ramp(nodes, links, mf.noise_value(nodes, links, scale, detail=8, lo=0.0, hi=1.0), [(0.0, dark), (0.5, mid), (1.0, light)])
    return build


def cracked(base_builder, crack, width=0.04, scale=2.5):
    """Voronoi cracks (lava veins, glowing seams) over a base."""
    def build(nodes, links):
        vor = nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = scale
        tc = nodes.new("ShaderNodeTexCoord")
        links.new(tc.outputs["Object"], vor.inputs["Vector"])
        mask = ramp(nodes, links, vor.outputs["Distance"], [(0.0, (1, 1, 1)), (width, (0, 0, 0)), (1.0, (0, 0, 0))])
        s = nodes.new("ShaderNodeSeparateColor")
        links.new(mask, s.inputs[0])
        return mix(nodes, links, s.outputs[0], base_builder(nodes, links), rgb(nodes, crack))
    return build


def height_bands(H, stops, grain=(0.75, 1.1)):
    """Colour by height (object Z) with a little jitter: mountains, cliffs."""
    def build(nodes, links):
        h = axis(nodes, links, "Z")
        jitter = mf.noise_value(nodes, links, 0.05, detail=6, lo=-H * 0.13, hi=H * 0.13)
        add = nodes.new("ShaderNodeMath")
        links.new(h, add.inputs[0])
        links.new(jitter, add.inputs[1])
        div = nodes.new("ShaderNodeMath")
        div.operation = "DIVIDE"
        links.new(add.outputs[0], div.inputs[0])
        div.inputs[1].default_value = H
        zones = ramp(nodes, links, div.outputs[0], stops)
        g = mf.gray(nodes, links, mf.noise_value(nodes, links, 0.6, detail=10, lo=grain[0], hi=grain[1]))
        return mix(nodes, links, 1.0, zones, g, "MULTIPLY")
    return build


def gradient_z(H, stops):
    """Colour by height without jitter (grass blades, reeds, crystals)."""
    def build(nodes, links):
        h = axis(nodes, links, "Z")
        div = nodes.new("ShaderNodeMath")
        div.operation = "DIVIDE"
        links.new(h, div.inputs[0])
        div.inputs[1].default_value = H
        return ramp(nodes, links, div.outputs[0], stops)
    return build


def spotted(base, spot, scale=4.0, size=0.25):
    """Big round spots (mushroom caps, starfish)."""
    def build(nodes, links):
        vor = nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = scale
        tc = nodes.new("ShaderNodeTexCoord")
        links.new(tc.outputs["Object"], vor.inputs["Vector"])
        m = ramp(nodes, links, vor.outputs["Distance"], [(0.0, (1, 1, 1)), (size, (1, 1, 1)), (size + 0.04, (0, 0, 0)), (1.0, (0, 0, 0))])
        s = nodes.new("ShaderNodeSeparateColor")
        links.new(m, s.inputs[0])
        return mix(nodes, links, s.outputs[0], rgb(nodes, base), rgb(nodes, spot))
    return build


def flat(c):
    def build(nodes, links):
        n = mf.gray(nodes, links, mf.noise_value(nodes, links, 6, detail=4, lo=0.85, hi=1.05))
        return mix(nodes, links, 1.0, rgb(nodes, c), n, "MULTIPLY")
    return build
