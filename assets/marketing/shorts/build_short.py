"""Builds a vertical YouTube Short for Monster Mutations in Blender.

Usage (from this folder):
  blender -b ../../models/Monsters.blend -P build_short.py -- <short> frames [f1,f2,...]
      renders the 3D frames to out/<short>/frames/ (all frames, or just the listed ones)
  blender -b --factory-startup -P build_short.py -- <short> edit
      cuts frames + voice (out/<short>/lineN.wav from tts.ps1) + captions + music/SFX
      into out/<short>.mp4

Every short is a pure function of time: build() makes the objects once, then
animate(t) poses them for each frame, so any frame can be rendered on its own.
"""

import bpy, bmesh, json, math, os, random, sys, wave, colorsys
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ARGS = sys.argv[sys.argv.index("--") + 1:]
SHORT, MODE = ARGS[0], ARGS[1]
ONLY = [int(x) for x in ARGS[2].split(",")] if len(ARGS) > 2 else None
OUT = os.path.join(HERE, "out", SHORT)
FPS, W, H = 30, 1080, 1920

SCRIPT = json.load(open(os.path.join(HERE, "scripts.json"), encoding="utf-8")).get(SHORT, {"lines": []})
DUR = json.load(open(os.path.join(OUT, "durations.json"), encoding="utf-8-sig")) if SCRIPT["lines"] else []

PAD_BEFORE = {"reveal": 0.45, "pop": 0.35, "tier8": 0.45}
PAD_AFTER = {"charge": 1.0, "reveal": 1.0, "spin": 0.5, "pop": 0.3, "cta": 1.6, "tier8": 0.9, "dark": 0.2, "fail": 0.3}

# Beat windows: B[beat] = (voice start, next line start). LINES keeps every line's voice span.
B, LINES = {}, []
_t = 0.35
for _i, _line in enumerate(SCRIPT["lines"]):
    _t += PAD_BEFORE.get(_line["beat"], 0)
    LINES.append((_t, _t + DUR[_i]))
    _t += DUR[_i] + 0.12 + PAD_AFTER.get(_line["beat"], 0)
for _i, _line in enumerate(SCRIPT["lines"]):
    nxt = LINES[_i + 1][0] if _i + 1 < len(LINES) else _t
    B[_line["beat"]] = (LINES[_i][0], nxt)
TOTAL = _t
NFRAMES = int(math.ceil(TOTAL * FPS))

RARITY = [  # Rarity.luau colours and scales, tier 1..8
    ((190, 190, 190), 1.0), ((90, 210, 90), 1.08), ((70, 150, 255), 1.18), ((175, 90, 255), 1.3),
    ((255, 170, 30), 1.45), ((255, 70, 90), 1.6), ((120, 230, 255), 1.8), ((255, 255, 255), 2.0),
]
def rcol(tier):
    c = RARITY[tier - 1][0]
    return tuple((v / 255) ** 2.2 for v in c)

# --------------------------------------------------------------------------- maths

def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def lerp(a, b, x): return a + (b - a) * x
def smooth(x): x = clamp(x); return x * x * (3 - 2 * x)
def phase(t, a, b): return clamp((t - a) / max(b - a, 1e-6))
def back(x):
    x = clamp(x); c = 1.9
    return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2
def vlerp(a, b, x): return Vector(a).lerp(Vector(b), x)

def track(t, keys):
    """keys: [(time, value tuple)], smoothly eased between neighbouring keys."""
    if t <= keys[0][0]: return Vector(keys[0][1])
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1: return vlerp(v0, v1, smooth(phase(t, t0, t1)))
    return Vector(keys[-1][1])

def wobble(t, amp, f, seed=0.0):
    return amp * (math.sin(t * f * 6.283 + seed) * 0.6 + math.sin(t * f * 13.7 + seed * 2.1) * 0.4)

# --------------------------------------------------------------------------- scene

def link(o):
    bpy.context.scene.collection.objects.link(o)
    return o

def mesh_obj(name, bm, mat=None, smooth_shade=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    if smooth_shade:
        for p in me.polygons: p.use_smooth = True
    o = link(bpy.data.objects.new(name, me))
    if mat: me.materials.append(mat)
    return o

def principled(name, color, rough=0.5, emit=(0, 0, 0), strength=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Emission Color"].default_value = (*emit, 1)
    b.inputs["Emission Strength"].default_value = strength
    if coat: b.inputs["Coat Weight"].default_value = coat
    return m

class Glow:
    """Emissive see-through material. mode: rim (fresnel shell), radial (fades out
    from the object origin over `reach`), flat. Animate .color/.strength/.alpha."""
    def __init__(self, name, color, strength=3.0, mode="flat", reach=1.0):
        m = self.mat = bpy.data.materials.new(name)
        nt = m.node_tree; nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        self.em = nt.nodes.new("ShaderNodeEmission")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        self.mul = nt.nodes.new("ShaderNodeMath"); self.mul.operation = "MULTIPLY"
        self.mul.inputs[0].default_value = 1.0; self.mul.inputs[1].default_value = 1.0
        if mode == "rim":
            lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs[0].default_value = 0.35
            pw = nt.nodes.new("ShaderNodeMath"); pw.operation = "POWER"; pw.inputs[1].default_value = 2.6
            nt.links.new(lw.outputs["Facing"], pw.inputs[0]); nt.links.new(pw.outputs[0], self.mul.inputs[0])
        elif mode == "radial":
            tc = nt.nodes.new("ShaderNodeTexCoord")
            ln = nt.nodes.new("ShaderNodeVectorMath"); ln.operation = "LENGTH"
            mr = nt.nodes.new("ShaderNodeMapRange")
            mr.inputs["From Min"].default_value = 0.0; mr.inputs["From Max"].default_value = reach
            mr.inputs["To Min"].default_value = 1.0; mr.inputs["To Max"].default_value = 0.0
            nt.links.new(tc.outputs["Object"], ln.inputs[0]); nt.links.new(ln.outputs["Value"], mr.inputs["Value"])
            nt.links.new(mr.outputs["Result"], self.mul.inputs[0])
        nt.links.new(self.mul.outputs[0], mix.inputs[0])
        nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(self.em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        try: m.surface_render_method = "BLENDED"
        except Exception: pass
        self.color, self.strength = color, strength
        self.alpha = 1.0
    @property
    def color(self): return tuple(self.em.inputs[0].default_value)[:3]
    @color.setter
    def color(self, c): self.em.inputs[0].default_value = (*c[:3], 1)
    @property
    def strength(self): return self.em.inputs[1].default_value
    @strength.setter
    def strength(self, s): self.em.inputs[1].default_value = s
    @property
    def alpha(self): return self.mul.inputs[1].default_value
    @alpha.setter
    def alpha(self, a): self.mul.inputs[1].default_value = clamp(a, 0, 1)

def sphere(name, r, mat, seg=32):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
    return mesh_obj(name, bm, mat)

def ico(name, r, mat, sub=1):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    return mesh_obj(name, bm, mat, smooth_shade=False)

def cylinder(name, r, h, mat, z=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=64, radius1=r, radius2=r, depth=h,
                          matrix=Matrix.Translation((0, 0, z + h / 2)))
    o = mesh_obj(name, bm, mat, smooth_shade=False)
    return o

def hide(o, hidden=True):
    for x in [o] + list(o.children_recursive):
        x.hide_render = hidden

# ---- groups of pieces from Monsters.blend (monsters and meadow props)

_cache = {}
def parts_for(name):
    if name not in _cache:
        col = bpy.data.collections.get(name)
        if col is not None and name in ("Mossling", "Cindermite"):
            objs = [o for o in col.all_objects if o.type == "MESH"]
        else:
            objs = [o for c in ("Upgraded", "MeadowProps") for o in bpy.data.collections[c].all_objects
                    if o.type == "MESH" and o.name.startswith(name + "_")]
        objs = [o for o in objs if "_Origin" not in o.name and "LeafCard" not in o.name]
        mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
        for o in objs:
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
        _cache[name] = (objs, mn, mx)
    return _cache[name]

# ---- colours: the baked textures are greyscale; the game tints every piece like the
# nearest same-named part of the species' part rig (dumped in rigs.txt), see
# MonsterVisuals.buildMeshFromRig. Mossling/Cindermite use MeshTones instead.

def srgb(c): return tuple((v / 255) ** 2.2 for v in c)

RIGS = {}
for _ln in open(os.path.join(HERE, "..", "..", "models", "rigs.txt"), encoding="utf-8"):
    _p = _ln.split()
    if len(_p) < 20: continue
    RIGS.setdefault(_p[0], {}).setdefault(_p[1], []).append(
        (Vector((float(_p[6]), float(_p[7]), float(_p[8]))), _p[18], srgb([int(v) for v in _p[19].split(",")])))

def shade(c, f):
    return tuple(v + (1 - v) * f for v in c) if f >= 0 else tuple(v * (1 + f) for v in c)
MOSS = (110 / 255, 170 / 255, 80 / 255)
TONES = {"Mossling": {"Body": 0, "Belly": 0.45, "Foot": -0.18, "Claw": -0.55, "BackSpike": -0.45}}

def base_name(o):
    n = o.name.split(".")[0]
    return n.split("_", 1)[1] if "_" in n else n

def centre_of(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return sum(pts, Vector()) / 8

_tinted = {}
def tinted(src, color, plain_mat=None):
    """Copy of the piece's material with its texture multiplied by `color`
    (Neon/Glass parts become plain glowing/see-through colour)."""
    key = (src.name if src else None, color, plain_mat)
    if key in _tinted: return _tinted[key]
    if plain_mat == "Neon":
        m = principled("Neon", color, 0.3, color, 4.0)
    elif plain_mat == "Glass":
        m = principled("Glass", color, 0.05, color, 0.4)
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        b.inputs["Transmission Weight"].default_value = 0.6
    elif src is None:
        m = principled("Plain", color, 0.45)
    else:
        m = src.copy(); nt = m.node_tree
        img = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        if img:
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (*color, 1)
            nt.links.new(img.outputs["Color"], mix.inputs[6])
            nt.links.new(mix.outputs[2], b.inputs["Base Color"])
        else:
            b.inputs["Base Color"].default_value = (*color, 1)
        b.inputs["Roughness"].default_value = 0.45
    _tinted[key] = m
    return m

def colour_piece(species, o, local):
    """Material for a monster piece; `local` is its centre in rig (Roblox) space."""
    nm = base_name(o)
    if species in TONES:
        tone = TONES[species].get(nm)
        if tone is None: return None
        mat0 = o.data.materials[0] if o.data.materials else None
        return tinted(mat0, shade(MOSS, tone))
    if species == "Cindermite":
        if "Flame" in nm: return tinted(None, srgb((255, 125, 25)), "Neon")
        return None
    cands = RIGS.get(species, {}).get(nm)
    if not cands: return None
    pos, material, col = min(cands, key=lambda c: (c[0] - local).length)
    mat0 = o.data.materials[0] if o.data.materials else None
    return tinted(mat0, col, material if material in ("Neon", "Glass") else None)

def rig_flip(species, objs, centre):
    """The meshes may be turned 180 deg from the part rig; pick whichever matches."""
    rig = RIGS.get(species)
    if not rig: return False
    err = [0.0, 0.0]
    for o in objs:
        c = centre_of(o) - centre
        for k, sgn in enumerate((1, -1)):
            local = Vector((sgn * c.x, c.z, -sgn * c.y))
            cands = rig.get(base_name(o))
            if cands: err[k] += min((p - local).length for p, _, _ in cands)
    return err[1] < err[0]

# ---- faces: the game draws eyes as separate parts; place cute ones on the head.

_eye_mats = {}
def eye_mats():
    if not _eye_mats:
        _eye_mats["white"] = principled("EyeWhite", (0.95, 0.95, 0.95), 0.15, coat=1.0)
        _eye_mats["pupil"] = principled("Pupil", (0.01, 0.01, 0.02), 0.1, coat=1.0)
        _eye_mats["shine"] = principled("Shine", (1, 1, 1), 0.2, (1, 1, 1), 3.0)
    return _eye_mats

def add_eye(root, p, normal, size):
    m = eye_mats()
    rot = normal.to_track_quat("Y", "Z").to_euler()
    for nm, r, off, sc in (("white", size, 0.0, (1, 0.55, 1)), ("pupil", size * 0.62, size * 0.32, (1, 0.5, 1)),
                           ("shine", size * 0.22, size * 0.62, (1, 0.5, 1))):
        e = sphere(f"{root.name}_{nm}", r, m[nm], 24)
        e.rotation_euler = rot
        loc = p + normal * off
        if nm == "shine": loc += Vector((size * 0.25, 0, size * 0.3))
        e.location = loc; e.scale = sc
        e.parent = root

def add_face(root, species, objs, inv):
    """Ray-cast from the front onto the head (or eye bulbs/stalks) and stick eyes on."""
    names = {base_name(o): o for o in objs}
    world = lambda o: [inv @ (o.matrix_world @ Vector(c)) for c in o.bound_box]
    def front_hit(o, x, z):
        from mathutils.bvhtree import BVHTree
        me = o.data
        tree = BVHTree.FromPolygons([inv @ (o.matrix_world @ v.co) for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        loc, nrm, _, _ = tree.ray_cast(Vector((x, 50, z)), Vector((0, -1, 0)))
        if loc is None: return None
        return loc, nrm.normalized()
    if "EyeBulb" in names or "EyeStalk" in names:
        key = "EyeBulb" if "EyeBulb" in names else "EyeStalk"
        for o in objs:
            if base_name(o) != key: continue
            pts = world(o)
            cx = sum(p.x for p in pts) / 8
            zt = max(p.z for p in pts) if key == "EyeStalk" else sum(p.z for p in pts) / 8
            if key == "EyeStalk":
                y = max(p.y for p in pts)
                add_eye(root, Vector((cx, y, zt)), Vector((0, 1, 0)), 0.2)
            else:
                hit = front_hit(o, cx, zt)
                if hit: add_eye(root, hit[0], hit[1], 0.36)
        return
    head = names.get("Head") or names.get("Body")
    pts = world(head)
    xs = [p.x for p in pts]; zs = [p.z for p in pts]
    w = max(xs) - min(xs); h = max(zs) - min(zs)
    cx = (max(xs) + min(xs)) / 2
    z = min(zs) + h * (0.62 if "Head" in names else 0.7)
    size = max(0.16, min(0.42, w * 0.15))
    for side in (-1, 1):
        hit = front_hit(head, cx + side * w * 0.2, z)
        if hit: add_eye(root, hit[0], hit[1], size)

_fallback = {}
def group(name, loc=(0, 0, 0), scale=1.0, rotz=0.0, is_monster=False):
    """A movable copy of a monster/prop: an empty at its bottom centre, facing +Y."""
    objs, mn, mx = parts_for(name)
    root = link(bpy.data.objects.new(name + "_root", None))
    centre = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    flip = is_monster and rig_flip(name, objs, centre)
    inv = (Matrix.Rotation(math.pi, 4, "Z") if flip else Matrix()) @ Matrix.Translation(-centre)
    for p in objs:
        c = p.copy(); link(c)
        c.hide_render = False
        c.parent = root
        c.matrix_parent_inverse = inv
        mat = None
        if is_monster:
            cc = centre_of(p) - centre
            sgn = -1 if flip else 1
            mat = colour_piece(name, p, Vector((sgn * cc.x, cc.z, -sgn * cc.y)))
        if mat is None and not c.data.materials:
            key = "flame" if "Flame" in p.name else "plain"
            if key not in _fallback:
                _fallback[key] = (principled("Flame", (1, 0.35, 0.05), 0.4, (1, 0.4, 0.05), 6) if key == "flame"
                                  else principled("Plain", (0.85, 0.85, 0.8), 0.4))
            mat = _fallback[key]
        if mat is not None:
            if not c.material_slots:
                c.data = c.data.copy(); c.data.materials.append(mat)
            c.material_slots[0].link = "OBJECT"; c.material_slots[0].material = mat
    if is_monster:
        add_face(root, name, objs, inv)
    root.location = loc; root.scale = (scale,) * 3; root.rotation_euler.z = rotz
    root["h"] = mx.z - mn.z
    root["r"] = max(mx.x - mn.x, mx.y - mn.y) / 2
    return root

def monster(name, height, loc=(0, 0, 0), rotz=0.0):
    """Monster scaled so it stands `height` tall."""
    g = group(name, loc, 1.0, rotz, is_monster=True)
    s = height / g["h"]
    g["s"] = s; g.scale = (s,) * 3
    return g

def pose(m, t, base_scale, pop_t=None, hop=0.0, loc=None, rotz=None, breathe=1.0, seed=0.0):
    """Places a monster: pop-in from pop_t, idle breathing, optional hop height."""
    k = back(phase(t, pop_t, pop_t + 0.45)) if pop_t is not None else 1.0
    b = 1 + 0.035 * breathe * math.sin(t * 7.0 + seed)
    m.scale = (base_scale * k * (2 - b), base_scale * k * (2 - b), base_scale * k * b)
    if loc is not None: m.location = Vector(loc) + Vector((0, 0, hop))
    if rotz is not None: m.rotation_euler.z = rotz
    hide(m, k <= 0.001)

def hop_curve(t, t0, dur=0.45, h=1.0):
    x = phase(t, t0, t0 + dur)
    return 4 * h * x * (1 - x) if 0 < x < 1 else 0.0

# ---- the stage

def setup_render():
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = W, H, 100
    sc.render.fps = FPS
    try: sc.render.engine = "BLENDER_EEVEE"
    except TypeError as e: print(e)
    sc.eevee.taa_render_samples = 24
    for attr, val in (("use_raytracing", False), ("use_shadows", True), ("shadow_ray_count", 1)):
        try: setattr(sc.eevee, attr, val)
        except Exception: pass
    sc.view_settings.view_transform = "AgX"
    for look in ("AgX - Punchy", "Punchy"):
        try: sc.view_settings.look = look; break
        except TypeError: pass
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.film_transparent = False
    # bloom
    try:
        ng = bpy.data.node_groups.new("Bloom", "CompositorNodeTree")
        ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        rl = ng.nodes.new("CompositorNodeRLayers")
        gl = ng.nodes.new("CompositorNodeGlare")
        out = ng.nodes.new("NodeGroupOutput")
        for name, val in (("Type", "Bloom"), ("Quality", "High"), ("Threshold", 1.0), ("Strength", 0.6), ("Size", 0.6)):
            if name in gl.inputs:
                try: gl.inputs[name].default_value = val
                except Exception as e: print("glare", name, e)
        if hasattr(gl, "glare_type"):
            try: gl.glare_type = "BLOOM"
            except Exception: pass
        ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
        ng.links.new(gl.outputs["Image"], out.inputs[0])
        sc.compositing_node_group = ng
    except Exception as e:
        print("BLOOM FAILED", e)

def world(top=(0.18, 0.45, 0.95), horizon=(0.75, 0.9, 1.0), strength=1.0):
    w = bpy.data.worlds.new("Sky"); bpy.context.scene.world = w
    nt = w.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0; ramp.color_ramp.elements[0].color = (*horizon, 1)
    ramp.color_ramp.elements[1].position = 0.45; ramp.color_ramp.elements[1].color = (*top, 1)
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs[0])
    bg.inputs["Strength"].default_value = strength
    return bg

def ground():
    m = bpy.data.materials.new("Grass")
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 0.08
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.10, 0.36, 0.06, 1)
    ramp.color_ramp.elements[1].color = (0.30, 0.62, 0.12, 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"]); nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.9
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=400)
    return mesh_obj("Ground", bm, m, smooth_shade=False)

def scenery(seed=4):
    rnd = random.Random(seed)
    trees = ["Oak", "Pine", "Birch", "Oak", "Pine"]
    small = ["Bush", "RockA", "RockB", "Bush", "Flowers", "Grass"]
    for _ in range(26):
        x = rnd.uniform(-45, 45); y = rnd.uniform(-75, -16)
        if abs(x) < 7 and y > -30: x += 14 * (1 if x >= 0 else -1)
        group(rnd.choice(trees), (x, y, 0), rnd.uniform(0.8, 1.25), rnd.uniform(0, 6.28))
    for _ in range(36):
        x = rnd.uniform(-20, 20); y = rnd.uniform(-22, 9)
        if abs(x) < 6.5 and y > -9: continue
        group(rnd.choice(small), (x, y, 0), rnd.uniform(0.35, 0.8), rnd.uniform(0, 6.28))
    try:
        group("Mountain", (0, -320, -10), 0.9, 0)
    except Exception as e:
        print("mountain", e)

def lights():
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 4.0; sun_data.angle = math.radians(6); sun_data.color = (1, 0.95, 0.85)
    sun = link(bpy.data.objects.new("Sun", sun_data))
    sun.rotation_euler = (math.radians(50), 0, math.radians(150))
    return sun

def point(name, color, energy, loc):
    d = bpy.data.lights.new(name, "POINT"); d.color = color; d.energy = energy; d.shadow_soft_size = 1.0
    o = link(bpy.data.objects.new(name, d)); o.location = loc
    return o

def camera():
    d = bpy.data.cameras.new("Cam"); d.lens = 30; d.sensor_fit = "VERTICAL"; d.sensor_height = 36 * 16 / 9 * 0.5
    d.clip_end = 2000
    cam = link(bpy.data.objects.new("Cam", d))
    tgt = link(bpy.data.objects.new("CamTarget", None))
    c = cam.constraints.new("TRACK_TO"); c.target = tgt
    c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
    bpy.context.scene.camera = cam
    return cam, tgt

def orbit_cam(cam, tgt, t, dist, height, target_z, angle=0.0, shake=0.0, x_off=0.0):
    a = math.radians(angle)
    cam.location = Vector((math.sin(a) * dist + x_off + wobble(t, shake, 2.3),
                           math.cos(a) * dist, height + wobble(t, shake, 2.9, 1.3)))
    tgt.location = Vector((x_off + wobble(t, shake * 0.5, 3.1, 0.7), 0, target_z + wobble(t, shake * 0.5, 2.7, 2.2)))

def pedestal():
    base = cylinder("PodBase", 1.7, 0.5, principled("Pod", (0.12, 0.13, 0.2), 0.35, coat=0.6))
    ring_glow = Glow("PodRing", (0.2, 0.9, 1.0), 6.0)
    ring = cylinder("PodRing", 1.78, 0.08, ring_glow.mat, z=0.42)
    top = cylinder("PodTop", 1.45, 0.06, principled("PodTop", (0.25, 0.27, 0.4), 0.25, coat=0.8), z=0.5)
    return ring_glow

def egg_mesh(name, mat, size=1.0):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=1)
    for v in bm.verts:
        if v.co.z > 0:
            v.co.z *= 1.32
            taper = 1 - 0.16 * v.co.z / 1.32
            v.co.x *= taper; v.co.y *= taper
        v.co.z += 1.0
        v.co *= size
    return mesh_obj(name, bm, mat)

def egg_material(name, shell, spot):
    m = bpy.data.materials.new(name); nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 3.2
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.22; ramp.color_ramp.elements[0].color = (*spot, 1)
    ramp.color_ramp.elements[1].position = 0.25; ramp.color_ramp.elements[1].color = (*shell, 1)
    nt.links.new(vor.outputs["Distance"], ramp.inputs["Fac"]); nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.3
    b.inputs["Coat Weight"].default_value = 0.7
    b.inputs["Emission Color"].default_value = (1, 0.85, 0.4, 1)
    b.inputs["Emission Strength"].default_value = 0
    return m, b

class Egg:
    def __init__(self, name, shell=(0.95, 0.9, 0.8), spot=(0.45, 0.2, 0.8), size=0.85, z=0.5):
        self.mat, self.bsdf = egg_material(name, shell, spot)
        self.obj = egg_mesh(name, self.mat, size)
        self.z = z
        rnd = random.Random(name)
        self.shards = []
        for i in range(16):
            s = ico(f"{name}_shard{i}", rnd.uniform(0.12, 0.24), self.mat)
            d = Vector((rnd.uniform(-1, 1), rnd.uniform(-0.4, 1), rnd.uniform(0.6, 1.6))).normalized()
            self.shards.append((s, d * rnd.uniform(4, 7), Vector((rnd.uniform(-9, 9) for _ in range(3)))))
    def set(self, t, appear, hatch, shake=0.0, glow=0.0, glow_color=(1, 0.85, 0.4)):
        """Visible from `appear` (pops in) until `hatch`, then bursts into shards."""
        vis = appear <= t < hatch
        hide(self.obj, not vis)
        k = back(phase(t, appear, appear + 0.3))
        self.obj.scale = (k,) * 3
        self.obj.location = (0, 0, self.z)
        self.obj.rotation_euler = (wobble(t, shake, 2.2), wobble(t, shake, 1.9, 1.0), 0)
        self.bsdf.inputs["Emission Strength"].default_value = glow
        self.bsdf.inputs["Emission Color"].default_value = (*glow_color, 1)
        dt = t - hatch
        for s, vel, spin in self.shards:
            on = 0 <= dt < 1.0
            hide(s, not on)
            if on:
                s.location = Vector((0, 0, self.z + 1.2)) + vel * dt + Vector((0, 0, -9.8 * dt * dt))
                s.rotation_euler = spin * dt
                s.scale = (1 - dt,) * 3

class Sparkles:
    """Small glowing bits that orbit a point (or burst)."""
    def __init__(self, name, n, color, r=0.07, seed=1):
        self.glow = Glow(name, color, 12.0)
        rnd = random.Random(seed)
        self.items = [(ico(f"{name}{i}", r * rnd.uniform(0.6, 1.4), self.glow.mat, 0),
                       rnd.uniform(0, 6.28), rnd.uniform(0.6, 1.0), rnd.uniform(0, 1), rnd.uniform(0.7, 1.3))
                      for i in range(n)]
    def orbit(self, t, centre, radius, height, speed=1.0, on=True, rise=0.0):
        for o, a, rr, hh, sp in self.items:
            hide(o, not on)
            if not on: continue
            ang = a + t * speed * sp
            z = (hh * height + rise * t * sp) % max(height, 0.01)
            o.location = Vector(centre) + Vector((math.cos(ang) * radius * rr, math.sin(ang) * radius * rr, z))
            tw = 0.6 + 0.4 * math.sin(t * 9 * sp + a)
            o.scale = (tw,) * 3
    def burst(self, t, t0, centre, speed=6.0, life=1.0):
        dt = t - t0
        for o, a, rr, hh, sp in self.items:
            on = 0 <= dt < life
            hide(o, not on)
            if on:
                d = Vector((math.cos(a), math.sin(a) * 0.5, hh * 2 - 0.6)).normalized()
                o.location = Vector(centre) + d * speed * sp * dt * (1 - dt / (2 * life))
                o.scale = ((1 - dt / life) * 1.6,) * 3

class Aura:
    def __init__(self, name, color):
        self.glow = Glow(name, color, 4.0, "rim")
        self.obj = sphere(name, 1.0, self.glow.mat)
        self.light = point(name + "L", color, 0, (0, 0, 0))
    def set(self, centre, radius, color, amount, t=0.0):
        hide(self.obj, amount <= 0.01)
        self.obj.location = centre
        pul = 1 + 0.04 * math.sin(t * 5)
        self.obj.scale = (radius * pul, radius * pul, radius * 1.15 * pul)
        self.glow.color = color; self.glow.alpha = amount * 0.55
        self.light.location = Vector(centre) + Vector((0, radius * 0.8, 0))
        self.light.data.color = color; self.light.data.energy = 220 * amount * radius

class Rays:
    def __init__(self, name, color, n=14, length=9.0):
        self.glow = Glow(name, color, 5.0, "radial", reach=length)
        bm = bmesh.new()
        for i in range(n):
            a = i / n * 6.283; w = 0.11 if i % 2 else 0.07
            c = bm.verts.new((0, 0, 0))
            p1 = bm.verts.new((math.cos(a - w) * length, 0, math.sin(a - w) * length))
            p2 = bm.verts.new((math.cos(a + w) * length, 0, math.sin(a + w) * length))
            bm.faces.new((c, p1, p2))
        self.obj = mesh_obj(name, bm, self.glow.mat, smooth_shade=False)
    def set(self, t, centre, amount, scale=1.0):
        hide(self.obj, amount <= 0.01)
        self.obj.location = centre
        self.obj.rotation_euler = (0, t * 0.5, 0)
        self.obj.scale = (scale * (0.3 + 0.7 * amount),) * 3
        self.glow.alpha = amount * 0.55

def rainbow(t, speed=0.6):
    return colorsys.hsv_to_rgb((t * speed) % 1.0, 0.75, 1.0)

def common_stage():
    setup_render()
    sky = world()
    ground(); scenery(); sun = lights()
    cam, tgt = camera()
    return sky, sun, cam, tgt

def cue(t, name):
    CUES.append((t, name))

CUES = []
FLASHES = []  # times of white flashes (added in the edit pass)

# --------------------------------------------------------------------------- shorts

def build_hatch():
    sky, sun, cam, tgt = common_stage()
    ring = pedestal()
    egg = Egg("Egg", spot=(0.35, 0.2, 0.75))
    gold = Egg("GoldEgg", shell=(1.0, 0.9, 0.55), spot=(0.95, 0.4, 0.1))
    mossling = monster("Mossling", 2.1)
    spots = [(-3.1, 1.2, 0), (3.1, 1.2, 0), (-3.6, -1.8, 0), (3.6, -1.8, 0)]
    commons = [monster(n, 1.9) for n in ("Pebbleback", "Brookhopper", "Sporeling")]
    hero = monster("Frostfang", 8.0)
    aura = Aura("HeroAura", (1, 1, 1))
    rays = Rays("HeroRays", (1.0, 0.9, 0.6))
    sp = Sparkles("Spark", 24, (1.0, 0.85, 0.4))
    burst = Sparkles("Burst", 30, (1, 1, 1), 0.1, seed=5)

    i0, glow, fail, retry, charge, reveal, cta = (B[k] for k in ("intro", "glow", "fail", "retry", "charge", "reveal", "cta"))
    fail_hatch = fail[0] + 0.25
    rs = retry[0]; rlen = LINES[3][1] - rs
    cycles = [rs + 0.05, rs + rlen * 0.45, rs + rlen * 0.75]
    gold_hatch = reveal[0]
    for c in cycles: cue(c, "pop_small")
    for c in cycles: cue(c + 0.55, "pop")
    cue(fail_hatch, "pop"); cue(glow[0], "chime"); cue(charge[0], "riser"); cue(gold_hatch, "boom")
    cue(gold_hatch + 0.1, "sparkle"); cue(cta[0], "chime")
    FLASHES.append(gold_hatch)

    def animate(t):
        # eggs: the plain egg hatches once for the fail, then 3 quick retries
        if t < cycles[0]:
            egg.set(t, -1.0, fail_hatch, shake=0.05 + 0.04 * (t > glow[0]),
                    glow=1.5 * smooth(phase(t, glow[0], glow[0] + 0.4)) * (0.6 + 0.4 * math.sin(t * 8)))
        else:
            # the next egg drops in as soon as the last little guy has hopped off
            hatches = [c + 0.55 for c in cycles]
            k = min(2, sum(1 for h in hatches if t >= h + 0.6))
            appear = cycles[0] if k == 0 else hatches[k - 1] + 0.6
            egg.set(t, appear, hatches[k], shake=0.12)
        gold.set(t, charge[0], gold_hatch, shake=0.05 + 0.25 * phase(t, charge[0], gold_hatch),
                 glow=6 * phase(t, charge[0], gold_hatch), glow_color=rainbow(t, 1.2))
        # little guys
        pose(mossling, t, mossling["s"], fail_hatch, loc=(0, 0, 0.5) if t < cycles[0] else spots[0],
             hop=hop_curve(t, cycles[0] - 0.4, 0.4, 1.2) + hop_curve(t, fail[0] + 1.6, 0.35, 0.4))
        for i, m in enumerate(commons):
            h = cycles[i] + 0.55
            if t < h:
                hide(m); continue
            moved = t > h + 0.55
            look = math.atan2(-spots[i + 1][0], spots[i + 1][1]) if t > charge[0] + 0.3 else 0.0
            pose(m, t, m["s"], h, loc=spots[i + 1] if moved else (0, 0, 0.5),
                 hop=hop_curve(t, h + 0.3, 0.35, 1.0), rotz=look, seed=i)
        if t > charge[0] + 0.3:
            mossling.rotation_euler.z = math.atan2(-spots[0][0], spots[0][1])
        # the hero
        if t >= gold_hatch:
            pose(hero, t, hero["s"], gold_hatch, loc=(0, 0, 0.5), breathe=0.6)
        else:
            hide(hero)
        a = smooth(phase(t, gold_hatch, gold_hatch + 0.6))
        centre = Vector((0, -0.5, 4.3))
        aura.set(centre, 4.6, (1, 0.95, 0.85), a * 0.35, t)
        rays.set(t, Vector((0, -5.5, 4.6)), a, 1.4)
        sp.glow.color = rainbow(t) if t < gold_hatch else (1, 0.95, 0.7)
        sp.orbit(t, (0, 0, 0.6), 1.8 if t < gold_hatch else 5.0, 3 if t < gold_hatch else 9, 2.5,
                 on=(glow[0] < t < cycles[0]) or (charge[0] < t) , rise=0.6)
        burst.burst(t, gold_hatch, (0, 0, 2.5), 9)
        ring.color = rainbow(t, 0.8) if charge[0] < t < gold_hatch else (0.2, 0.9, 1.0)
        ring.strength = 6 + 10 * phase(t, charge[0], gold_hatch) * (t < gold_hatch)
        # camera
        keys = [(0, (6.6, 2.3, 1.6)), (i0[1], (5.4, 2.0, 1.6)), (fail[0] + 0.5, (5.4, 2.0, 1.6)),
                (fail[1] - 0.2, (4.2, 1.9, 1.7)), (retry[0] + 0.6, (10.5, 3.6, 1.3)),
                (charge[0] + 0.2, (10.5, 3.6, 1.3)), (gold_hatch, (5.0, 1.8, 1.7)),
                (gold_hatch + 0.35, (15.5, 1.8, 4.6)), (cta[1], (17.5, 2.8, 4.6))]
        d, hgt, tz = track(t, keys)
        ang = 15 * smooth(phase(t, reveal[0] + 0.6, cta[1]))
        shk = 0.06 * phase(t, charge[0], gold_hatch) * (t < gold_hatch) + 0.25 * max(0, 1 - (t - gold_hatch) * 2.5) * (t >= gold_hatch)
        orbit_cam(cam, tgt, t, d, hgt, tz, ang, shk)
    return animate

def build_fusion():
    sky, sun, cam, tgt = common_stage()
    swirl_glow = Glow("Swirl", (0.6, 0.2, 1.0), 6.0, "radial", reach=2.6)
    bm = bmesh.new()
    for k in range(4):
        prev = None
        for i in range(26):
            a = k * 1.5708 + i * 0.22; r = 0.15 + i * 0.09; w = 0.16 * (1 - i / 30)
            inner = bm.verts.new((math.cos(a) * (r - w), math.sin(a) * (r - w), 0))
            outer = bm.verts.new((math.cos(a) * (r + w), math.sin(a) * (r + w), 0))
            if prev: bm.faces.new((prev[0], prev[1], outer, inner))
            prev = (inner, outer)
    swirl = mesh_obj("Swirl", bm, swirl_glow.mat, smooth_shade=False)
    pad = cylinder("Pad", 2.7, 0.1, principled("Pad", (0.15, 0.1, 0.25), 0.3, coat=0.6))
    orb_glow = Glow("Orb", (0.7, 0.3, 1.0), 8.0, "rim")
    orb = sphere("Orb", 1.0, orb_glow.mat)
    orb_light = point("OrbLight", (0.7, 0.3, 1.0), 0, (0, 0.5, 1.5))
    left = monster("Sporeling", 2.4); right = monster("Miretoad", 2.2)
    hero = monster("Venomtail", 3.6 * 1.18)
    vortex = Sparkles("Vortex", 40, (0.8, 0.4, 1.0), 0.08)
    burst = Sparkles("Burst", 30, (0.9, 0.6, 1.0), 0.1, seed=7)
    aura = Aura("RareAura", rcol(3))

    L, R, J, S, P, RA, C = (B[k] for k in ("left", "right", "jump", "spin", "pop", "rare", "cta"))
    land = J[0] + 1.0
    pop = P[0]
    cue(L[0] + 0.1, "boing"); cue(R[0] + 0.1, "boing"); cue(J[0] + 0.1, "whoosh"); cue(S[0], "riser")
    cue(pop, "boom"); cue(pop + 0.1, "sparkle"); cue(RA[0], "chime")
    FLASHES.append(pop)
    # The camera looks down -Y, so screen-left is +X.
    LX, RX = Vector((2.1, 0.6, 0)), Vector((-2.1, 0.6, 0))

    def animate(t):
        jx = smooth(phase(t, J[0], land))
        for m, start, sgn, hop_t, seed in ((left, LX, -1, L[0], 0), (right, RX, 1, R[0], 2)):
            if t >= land:
                hide(m); continue
            pos = start.lerp(Vector((0, 0, 0.1)), jx)
            arc = 4 * 2.8 * jx * (1 - jx)
            s = m["s"] * (1 - 0.85 * smooth(phase(t, land - 0.35, land)))
            pose(m, t, s, None, loc=pos, hop=arc + hop_curve(t, hop_t, 0.45, 1.3), seed=seed,
                 rotz=sgn * math.radians(-35) + sgn * 12 * smooth(phase(t, J[0] + 0.2, land)))
        speed = 1.0 + 6 * phase(t, J[0], pop) + (-5 * phase(t, pop, pop + 1)) * (t > pop)
        swirl.location = (0, 0, 0.12); swirl.rotation_euler.z = -t * 2.0 - 4 * max(0, t - J[0]) ** 1.6 * (t < pop)
        swirl_glow.strength = 5 + 20 * phase(t, J[0], pop) * (t < pop)
        o = smooth(phase(t, land - 0.3, pop - 0.1)) * (t < pop)
        hide(orb, o <= 0.01)
        orb.location = (0, 0, 1.6); orb.scale = (0.4 + 1.0 * o + 0.08 * math.sin(t * 20),) * 3
        orb_glow.alpha = o; orb_glow.color = rainbow(t, 0.4) if t > S[0] else (0.7, 0.3, 1.0)
        orb_light.data.energy = 3000 * o
        vortex.orbit(t * (1 + 3 * phase(t, S[0], pop)), (0, 0, 0.1), 2.4 * (1 - 0.5 * phase(t, S[0], pop)), 4.0, 3.0,
                     on=J[0] + 0.5 < t < pop, rise=2.0)
        burst.burst(t, pop, (0, 0, 1.8), 8)
        if t >= pop:
            pose(hero, t, hero["s"], pop, loc=(0, 0, 0.1), hop=hop_curve(t, RA[0], 0.5, 1.2) + hop_curve(t, pop + 1.2, 0.4, 0.5))
        else:
            hide(hero)
        aura.set(Vector((0, 0, 2.2)), 3.0, rcol(3), smooth(phase(t, RA[0], RA[0] + 0.5)), t)
        keys = [(0, (13.0, 3.0, 1.5)), (J[0], (13.0, 3.0, 1.5)), (land, (9.5, 3.5, 2.0)),
                (pop, (7.0, 2.2, 1.8)), (pop + 0.6, (10.5, 2.8, 2.3)), (C[1], (11.0, 3.2, 2.3))]
        d, hgt, tz = track(t, keys)
        xo = track(t, [(L[0], (0.7, 0, 0)), (R[0], (0.7, 0, 0)), (R[0] + 0.4, (-0.7, 0, 0)), (J[0] + 0.2, (-0.7, 0, 0)), (land, (0, 0, 0))]).x
        ang = 18 * smooth(phase(t, RA[0], C[1]))
        shk = 0.08 * phase(t, S[0], pop) * (t < pop) + 0.25 * max(0, 1 - (t - pop) * 2.5) * (t >= pop)
        orbit_cam(cam, tgt, t, d, hgt, tz, ang, shk, xo)
    return animate

def build_ladder():
    sky, sun, cam, tgt = common_stage()
    ring = pedestal()
    egg = Egg("Egg", spot=(0.2, 0.6, 0.9))
    white = Egg("WhiteEgg", shell=(1, 1, 1), spot=(0.75, 0.85, 1.0))
    species = ["Mossling", "Brookhopper", "Sparkhare", "Coralback", "Basaltback", "Ashwing", "Glimmerseal", "Thunderhorn"]
    base_h = 2.6
    mons = [monster(n, base_h * RARITY[i][1] ** 1.6) for i, n in enumerate(species)]
    aura = Aura("Aura", (1, 1, 1))
    rays = Rays("Rays", (1, 0.95, 0.8), 16, 11)
    sp = Sparkles("Spark", 28, (1, 1, 1))
    burst = Sparkles("Burst", 24, (1, 1, 1), 0.09, seed=3)
    tiers = [B[f"tier{i}"] for i in range(1, 9)]
    dark = B["dark"]; cta = B["cta"]
    tier_t = [w[0] - 0.05 for w in tiers]
    for i, tt in enumerate(tier_t):
        cue(tt, "pop" if i < 7 else "boom")
        cue(tt + 0.02, "ding%d" % (i + 1))
    cue(dark[0], "riser"); cue(tier_t[7] + 0.1, "sparkle")
    FLASHES.append(tier_t[7])

    def current(t):
        k = -1
        for i, tt in enumerate(tier_t):
            if t >= tt: k = i
        if dark[0] <= t < tier_t[7]: k = -2
        return k

    def animate(t):
        k = current(t)
        egg.set(t, 0.0, tier_t[0], shake=0.06 + 0.1 * phase(t, B["intro"][0], tier_t[0]))
        white.set(t, dark[0] + 0.1, tier_t[7], shake=0.05 + 0.3 * phase(t, dark[0], tier_t[7]),
                  glow=4 * phase(t, dark[0], tier_t[7]), glow_color=(0.8, 0.9, 1.0))
        for i, m in enumerate(mons):
            if i == k:
                pose(m, t, m["s"], tier_t[i], loc=(0, 0, 0.5), seed=i)
            else:
                hide(m)
        h = mons[k]["s"] * mons[k]["h"] if k >= 0 else 2.4
        tier = k + 1
        col = rcol(tier) if k >= 0 else (0.8, 0.9, 1.0)
        amt = 0 if k <= 0 else (0.4 if tier == 8 else min(1.0, 0.35 + 0.1 * tier))
        aura.set(Vector((0, 0, 0.5 + h * 0.5)), h * 0.75, col, amt, t)
        rays.set(t, Vector((0, -4, 0.5 + h * 0.55)), smooth(phase(t, tier_t[7], tier_t[7] + 0.5)), 1.2)
        sp.glow.color = col
        sp.orbit(t, (0, 0, 0.5), h * 0.9, h * 1.1, 2.0, on=k >= 3 or k == -2, rise=0.5)
        burst.glow.color = col
        last = max([tt for tt in tier_t if tt <= t], default=-9)
        burst.burst(t, last, (0, 0, 0.5 + h * 0.5), 5 + 4 * (last == tier_t[7]))
        ring.color = col if k > 0 else (0.2, 0.9, 1.0)
        # lights dim for "and the rarest of all..."
        d = smooth(phase(t, dark[0], dark[0] + 0.4)) * (1 - smooth(phase(t, tier_t[7], tier_t[7] + 0.3)))
        sky.inputs["Strength"].default_value = 1.0 - 0.85 * d
        sun.data.energy = 4.0 * (1 - 0.9 * d)
        # camera frames the current monster
        hh = h if k != -2 else 2.6
        tz = 0.5 + hh * 0.5
        dist = 3.2 + hh * 1.9
        if k == 7: dist += 2.5 * smooth(phase(t, tier_t[7] + 0.4, cta[1]))
        ang = 10 * math.sin(t * 0.5)
        shk = 0.05 * d + 0.25 * max(0, 1 - (t - tier_t[7]) * 2.5) * (t >= tier_t[7])
        orbit_cam(cam, tgt, t, dist, tz + 0.8, tz, ang, shk)
    # smooth the camera between tiers by easing towards the target each frame
    return animate

def build_lineup():
    """Test card: every species side by side, to check colours and faces."""
    sky, sun, cam, tgt = common_stage()
    names = ["Mossling", "Pebbleback", "Brookhopper", "Snowmote", "Frostfang", "Glimmerseal", "Cindermite", "Basaltback",
             "Ashwing", "Reefling", "Coralback", "Seamist", "Sparkhare", "Stormcrest", "Thunderhorn", "Sporeling",
             "Miretoad", "Venomtail"]
    for i, n in enumerate(names):
        r, c = divmod(i, 3)
        monster(n, 2.4, ((c - 1) * 3.6, -r * 4.5, 0))
    def animate(t):
        cam.data.lens = 24
        cam.location = (0, 12, 9); tgt.location = (0, -11, 0.5)
    return animate

BUILDERS = {"hatch": build_hatch, "fusion": build_fusion, "ladder": build_ladder, "lineup": build_lineup}

# --------------------------------------------------------------------------- render frames

def render_frames():
    for o in bpy.data.objects:
        o.hide_render = True
    animate = BUILDERS[SHORT]()
    cam = bpy.context.scene.camera
    frames_dir = os.path.join(OUT, "frames"); os.makedirs(frames_dir, exist_ok=True)
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, NFRAMES
    todo = ONLY or range(1, NFRAMES + 1)
    smooth_cam = None
    for f in todo:
        path = os.path.join(frames_dir, "%04d.png" % f)
        if ONLY is None and os.path.exists(path):
            continue  # resume an interrupted run
        t = (f - 1) / FPS
        animate(t)
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("FRAME", f, "/", NFRAMES, flush=True)
    json.dump({"cues": CUES, "flashes": FLASHES, "frames": NFRAMES, "total": TOTAL},
              open(os.path.join(OUT, "timeline.json"), "w"))

# --------------------------------------------------------------------------- audio

import array
RATE = 44100

def write_wav(path, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    g = min(1.0, 0.9 / peak)
    data = array.array("h", (int(max(-1, min(1, s * g)) * 32767) for s in samples))
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data.tobytes())

def sfx(name):
    rnd = random.Random(name)
    def env(i, n, a=0.005, curve=3.0):
        x = i / n
        return min(1.0, x / a) * (1 - x) ** curve
    out = []
    if name in ("pop", "pop_small"):
        n = int(RATE * 0.16)
        f0 = 900 if name == "pop" else 1300
        ph = 0
        for i in range(n):
            f = f0 * (1 - 0.7 * i / n); ph += f / RATE
            out.append(math.sin(ph * 6.283) * env(i, n, 0.002, 4) * 0.9)
    elif name == "boing":
        n = int(RATE * 0.35); ph = 0
        for i in range(n):
            x = i / n; f = 220 + 260 * x + 40 * math.sin(x * 60); ph += f / RATE
            out.append(math.sin(ph * 6.283) * env(i, n, 0.01, 2))
    elif name == "whoosh":
        n = int(RATE * 0.7); lp = 0
        for i in range(n):
            x = i / n; a = 0.02 + 0.25 * math.sin(math.pi * x)
            lp += a * (rnd.uniform(-1, 1) - lp)
            out.append(lp * math.sin(math.pi * x) * 3)
    elif name == "riser":
        n = int(RATE * 2.2); ph = ph2 = 0; lp = 0
        for i in range(n):
            x = i / n; f = 180 + 900 * x * x; ph += f / RATE; ph2 += f * 1.5 / RATE
            lp += 0.1 * (rnd.uniform(-1, 1) - lp)
            out.append((math.sin(ph * 6.283) * 0.3 + math.sin(ph2 * 6.283) * 0.15 + lp * 0.6 * x) * x)
    elif name == "boom":
        n = int(RATE * 1.6); ph = 0; lp = 0
        for i in range(n):
            x = i / n; f = 70 * (1 - 0.5 * x); ph += f / RATE
            lp += 0.05 * (rnd.uniform(-1, 1) - lp)
            out.append((math.sin(ph * 6.283) * 1.0 + lp * 3) * env(i, n, 0.003, 2.5))
    elif name in ("chime", "sparkle"):
        n = int(RATE * 1.2)
        notes = [1318.5, 1568, 1975.5, 2637] if name == "chime" else [2093, 2637, 3136, 3520, 4186]
        out = [0.0] * n
        for k, fq in enumerate(notes):
            st = int(k * RATE * (0.07 if name == "chime" else 0.045))
            for i in range(st, n):
                j = i - st
                out[i] += math.sin(j * fq / RATE * 6.283) * math.exp(-j / RATE * 5) * 0.3
    elif name.startswith("ding"):
        tier = int(name[4:])
        fq = 440 * 2 ** ((tier * 2 - 2) / 12)
        n = int(RATE * 0.6)
        for i in range(n):
            out.append((math.sin(i * fq / RATE * 6.283) + 0.4 * math.sin(i * fq * 2 / RATE * 6.283)) * math.exp(-i / RATE * 6) * 0.6)
    return out

def music(seconds, bpm=112):
    """A light, bouncy loop: bass on the beat, plucked arpeggio over I-V-vi-IV."""
    n = int(RATE * seconds)
    out = [0.0] * n
    beat = 60 / bpm
    chords = [(261.6, 329.6, 392.0), (196.0, 246.9, 293.7), (220.0, 261.6, 329.6), (174.6, 220.0, 261.6)]
    step = beat / 2
    i = 0; tt = 0.0
    while tt < seconds:
        bar = int(tt / (beat * 4)) % 4
        ch = chords[bar]
        fq = ch[i % 3] * (2 if (i // 3) % 2 else 1)
        st = int(tt * RATE); ln = int(RATE * 0.35)
        for j in range(ln):
            if st + j >= n: break
            out[st + j] += math.sin(j * fq / RATE * 6.283) * math.exp(-j / RATE * 9) * 0.22
        if i % 2 == 0:
            bq = ch[0] / 2
            ln = int(RATE * beat * 0.9)
            for j in range(ln):
                if st + j >= n: break
                out[st + j] += math.sin(j * bq / RATE * 6.283) * math.exp(-j / RATE * 3) * 0.3
        i += 1; tt += step
    fade = int(RATE * 1.0)
    for j in range(fade):
        out[n - 1 - j] *= j / fade
    return out

# --------------------------------------------------------------------------- edit

def chunks(cap):
    words = cap.split(); res = []; cur = []
    for w in words:
        hi = "*" in w
        if hi:
            if cur: res.append((" ".join(cur), False)); cur = []
            res.append((w.replace("*", ""), True)); continue
        cur.append(w)
        if len(" ".join(cur)) > 13 or len(cur) >= 4 or w.endswith((".", "?", "!", "...")):
            res.append((" ".join(cur), False)); cur = []
    if cur: res.append((" ".join(cur), False))
    return res

def edit(stills=None):
    tl = json.load(open(os.path.join(OUT, "timeline.json")))
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = W, H, 100
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 1, (ONLY[0] if ONLY and not stills else tl["frames"])
    sc.view_settings.view_transform = "Standard"
    se = sc.sequence_editor_create()
    frames_dir = os.path.join(OUT, "frames")
    names = sorted(os.listdir(frames_dir))[: sc.frame_end]
    img = se.strips.new_image("frames", os.path.join(frames_dir, names[0]), 1, 1, fit_method="FIT")
    for nme in names[1:]:
        img.elements.append(nme)
    snd = os.path.join(OUT, "sfx"); os.makedirs(snd, exist_ok=True)
    # voice
    for i, (a, b) in enumerate(LINES):
        s = se.strips.new_sound(f"v{i}", os.path.join(OUT, f"line{i}.wav"), 2 + i % 2, int(a * FPS) + 1)
        s.volume = 1.6
    # sfx + music
    made = {}
    for k, (t, name) in enumerate(tl["cues"]):
        if name not in made:
            p = os.path.join(snd, name + ".wav"); write_wav(p, sfx(name)); made[name] = p
        s = se.strips.new_sound(f"sfx{k}", made[name], 4 + k % 4, max(1, int(t * FPS) + 1))
        s.volume = 0.5 if name not in ("boom", "riser") else 0.7
    mp = os.path.join(snd, "music.wav"); write_wav(mp, music(tl["total"]))
    m = se.strips.new_sound("music", mp, 8, 1); m.volume = 0.18
    # captions
    font = bpy.data.fonts.load(r"C:\Windows\Fonts\ariblk.ttf")
    tiers = {f"tier{i}": RARITY[i - 1][0] for i in range(1, 9)}
    ch = 0
    for i, line in enumerate(SCRIPT["lines"]):
        a, b = LINES[i]
        parts = chunks(line["cap"])
        total_chars = sum(len(p) + 2 for p, _ in parts)
        t = a
        hi_col = tiers.get(line["beat"], (255, 214, 40))
        for j, (text, hi) in enumerate(parts):
            d = (b - a) * (len(text) + 2) / total_chars
            end = t + d if j < len(parts) - 1 else max(t + d, b + 0.15)
            f0, f1 = int(t * FPS) + 1, int(end * FPS) + 1
            st = se.strips.new_effect(f"cap{i}_{j}", "TEXT", 10 + ch % 2, f0, length=max(2, f1 - f0))
            ch += 1
            st.text = text.upper(); st.font = font
            st.font_size = 120 if hi else 96
            st.color = (*[c / 255 for c in hi_col], 1) if hi else (1, 1, 1, 1)
            st.use_outline = True; st.outline_color = (0, 0, 0, 1); st.outline_width = 0.35
            st.use_shadow = True; st.shadow_color = (0, 0, 0, 0.6)
            st.location = (0.5, 0.30); st.wrap_width = 0.9
            st.alignment_x = "CENTER"; st.anchor_x = "CENTER"; st.anchor_y = "CENTER"
            try:
                st.transform.scale_x = st.transform.scale_y = 0.6
                st.transform.keyframe_insert("scale_x", frame=f0); st.transform.keyframe_insert("scale_y", frame=f0)
                st.transform.scale_x = st.transform.scale_y = 1.08
                st.transform.keyframe_insert("scale_x", frame=f0 + 3); st.transform.keyframe_insert("scale_y", frame=f0 + 3)
                st.transform.scale_x = st.transform.scale_y = 1.0
                st.transform.keyframe_insert("scale_x", frame=f0 + 5); st.transform.keyframe_insert("scale_y", frame=f0 + 5)
            except Exception as e:
                print("caption pop", e)
            t = end if j < len(parts) - 1 else t
    # white flashes
    for k, ft in enumerate(tl["flashes"]):
        f0 = int(ft * FPS) + 1
        c = se.strips.new_effect(f"flash{k}", "COLOR", 14, f0, length=10)
        c.color = (1, 1, 1); c.blend_type = "ALPHA_OVER"
        for fr, al in ((f0, 1.0), (f0 + 2, 0.9), (f0 + 9, 0.0)):
            c.blend_alpha = al; c.keyframe_insert("blend_alpha", frame=fr)
    # end card: icon + title over the last line
    ca, cb = B["cta"]
    f0 = int(ca * FPS) + 1; f1 = tl["frames"]
    icon = se.strips.new_image("icon", os.path.join(HERE, "..", "icon_512.png"), 15, f0, fit_method="ORIGINAL")
    icon.frame_final_end = f1 + 1
    icon.transform.offset_y = H * 0.24
    for fr, s in ((f0, 0.2), (f0 + 5, 1.15), (f0 + 8, 1.0)):
        icon.transform.scale_x = icon.transform.scale_y = s
        icon.transform.keyframe_insert("scale_x", frame=fr); icon.transform.keyframe_insert("scale_y", frame=fr)
    for k, (text, size, y, col) in enumerate((("MONSTER MUTATIONS", 84, 0.59, (1, 0.84, 0.16, 1)),
                                              ("PLAY FREE ON ROBLOX", 64, 0.52, (1, 1, 1, 1)))):
        st = se.strips.new_effect(f"title{k}", "TEXT", 16 + k, f0 + 4, length=f1 - f0 - 3)
        st.text = text; st.font = font; st.font_size = size; st.color = col; st.wrap_width = 1.0
        st.use_outline = True; st.outline_color = (0, 0, 0, 1); st.outline_width = 0.4
        st.location = (0.5, y); st.alignment_x = "CENTER"; st.anchor_x = "CENTER"; st.anchor_y = "CENTER"
    # output
    r = sc.render
    if stills:
        for f in stills:
            sc.frame_set(f)
            r.filepath = os.path.join(OUT, "still_%04d.png" % f)
            bpy.ops.render.render(write_still=True)
        return
    if hasattr(r.image_settings, "media_type"):
        r.image_settings.media_type = "VIDEO"
    r.image_settings.file_format = "FFMPEG"
    r.ffmpeg.format = "MPEG4"; r.ffmpeg.codec = "H264"
    r.ffmpeg.constant_rate_factor = "HIGH"; r.ffmpeg.ffmpeg_preset = "GOOD"
    r.ffmpeg.audio_codec = "AAC"; r.ffmpeg.audio_bitrate = 192; r.ffmpeg.audio_mixrate = 44100
    r.ffmpeg.audio_channels = "STEREO"
    r.filepath = os.path.join(HERE, "out", f"{SHORT}_test.mp4" if ONLY else f"{SHORT}.mp4")
    bpy.ops.render.render(animation=True)
    print("WROTE", r.filepath)

if MODE == "frames":
    render_frames()
elif MODE == "edit":
    edit()
elif MODE == "editstill":
    edit(stills=ONLY)
