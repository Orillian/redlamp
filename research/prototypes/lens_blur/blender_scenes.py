#!/usr/bin/env python3
"""3D scenes rendered with Blender Cycles, for continuous depth (OTH-03, #138).

Ground planes receding, a slanted wall, tree trunks, foliage and grass, built in bpy from Poly
Haven's CC0 HDRIs, textures and models (fetch_polyhaven.py) plus procedural geometry, with small
emissive spheres as point lights. Blender is GPL and only renders data here.

The thin lens is exact: a lens of focal length f focused at s is a pinhole camera with its
sensor v = f s / (s - f) behind and an aperture f/N, so each variant sets Blender's lens to v and
its f-stop to N v / f (Cycles' aperture radius is lens / (2 f-stop)). The CoC formula in each
variant's JSON then holds exactly.

    build/lens-blur-bpy-venv/bin/python research/prototypes/lens_blur/blender_scenes.py render [scene...]
    build/research-venv/bin/python research/prototypes/lens_blur/blender_scenes.py export

`render` writes multilayer EXRs (Combined and Depth) to build/proto-data/lens_blur/blender-raw/;
`export` turns them into the layout the layered set uses, under blender/.
"""

import json
import math
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import common  # noqa: E402
from common import DATA  # noqa: E402

PH = DATA / "polyhaven"
RAW = DATA / "blender-raw"
WIDTH, HEIGHT = 720, 480
FOCAL = 50.0
APERTURES = (1.8, 4.0)
BLADES = (0, 5)
INPUT_SAMPLES = 256
DOF_SAMPLES = 256
NOISE_THRESHOLD = 0.01
DEPTH_SAMPLES = 32
NEAR_CLIP = 0.05


# MARK: - Scene building (bpy)

def bpy_modules():
    import bpy
    import mathutils
    return bpy, mathutils


def reset():
    bpy, _ = bpy_modules()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type == "METAL"
    c = scene.cycles
    c.device = "GPU"
    c.use_denoising = False
    c.pixel_filter_type = "BOX"
    c.filter_width = 1.0
    c.sample_clamp_direct = 0
    c.sample_clamp_indirect = 0
    c.max_bounces = 4
    # Dense alpha-textured foliage stacks more than the default 8 transparent layers.
    c.transparent_max_bounces = 64
    c.diffuse_bounces = 2
    c.glossy_bounces = 2
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.seed = 1
    c.use_animated_seed = False
    scene.render.resolution_x, scene.render.resolution_y = WIDTH, HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    settings = scene.render.image_settings
    if hasattr(settings, "media_type"):
        settings.media_type = "MULTI_LAYER_IMAGE"
    else:
        settings.file_format = "OPEN_EXR_MULTILAYER"
    settings.color_depth = "32"
    settings.exr_codec = "ZIP"
    scene.view_layers[0].use_pass_z = True
    return scene


def node_material(name):
    bpy, _ = bpy_modules()
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    return material, material.node_tree, out


def texture_material(asset, scale=1.0, roughness=0.8, uv_size=None):
    """Principled material with a Poly Haven texture tiled every `scale` metres in world space."""
    bpy, _ = bpy_modules()
    material, tree, out = node_material(asset)
    nodes, links = tree.nodes, tree.links
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    mapping = nodes.new("ShaderNodeMapping")
    if uv_size:
        # A rotated plane: its UVs span its size in metres.
        coords = nodes.new("ShaderNodeTexCoord")
        mapping.inputs["Scale"].default_value = (uv_size[0] / scale, uv_size[1] / scale, 1)
        links.new(coords.outputs["UV"], mapping.inputs["Vector"])
    else:
        coords = nodes.new("ShaderNodeNewGeometry")
        mapping.inputs["Scale"].default_value = (1 / scale, 1 / scale, 1 / scale)
        links.new(coords.outputs["Position"], mapping.inputs["Vector"])
    diffuse = next((PH / "textures" / asset).glob("*diff*"))
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(str(diffuse))
    image.projection = "FLAT" if uv_size else "BOX"
    image.projection_blend = 0.2
    links.new(mapping.outputs["Vector"], image.inputs["Vector"])
    links.new(image.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return material


def colour_material(name, colour, roughness=0.6, noise=0.0, checker=None):
    bpy, _ = bpy_modules()
    material, tree, out = node_material(name)
    nodes, links = tree.nodes, tree.links
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    if checker:
        tex = nodes.new("ShaderNodeTexChecker")
        tex.inputs["Scale"].default_value = checker
        tex.inputs["Color1"].default_value = (*colour, 1)
        tex.inputs["Color2"].default_value = (colour[0] * 0.25, colour[1] * 0.25, colour[2] * 0.25, 1)
        coords = nodes.new("ShaderNodeNewGeometry")
        links.new(coords.outputs["Position"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    elif noise:
        tex = nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = noise
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (colour[0] * 0.3, colour[1] * 0.3, colour[2] * 0.3, 1)
        ramp.color_ramp.elements[1].color = (*colour, 1)
        links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return material


def emission_material(name, colour, strength):
    material, tree, out = node_material(name)
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*colour, 1)
    emission.inputs["Strength"].default_value = strength
    tree.links.new(emission.outputs["Emission"], out.inputs["Surface"])
    return material


def link(obj, collection=None):
    bpy, _ = bpy_modules()
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def plane(name, size, location, rotation, material, collection=None):
    bpy, _ = bpy_modules()
    bpy.ops.mesh.primitive_plane_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[1], 1)
    obj.data.materials.append(material)
    move_to(obj, collection)
    return obj


def move_to(obj, collection):
    bpy, _ = bpy_modules()
    if collection is None:
        return
    for c in obj.users_collection:
        c.objects.unlink(obj)
    collection.objects.link(obj)


def sphere(name, radius, location, material, collection=None, segments=48):
    bpy, _ = bpy_modules()
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=segments, ring_count=segments // 2)
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(material)
    move_to(obj, collection)
    return obj


def cylinder(name, radius, depth, location, material, collection=None, rotation=(0, 0, 0)):
    bpy, _ = bpy_modules()
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, rotation=rotation, vertices=48)
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(material)
    move_to(obj, collection)
    return obj


def world_and_backdrop(state, hdri=None, median=0.25, sky=(0.5, 0.6, 0.8), radius=400.0):
    """The world lights the scene; an inside-out emissive sphere shows it to the camera at a finite depth."""
    bpy, _ = bpy_modules()
    import numpy as np
    world = bpy.data.worlds.new("world")
    bpy.context.scene.world = world
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    background = nodes["Background"]
    strength = 1.0
    image = None
    if hdri:
        path = next((PH / "hdris" / hdri).glob("*.hdr"))
        image = bpy.data.images.load(str(path))
        pixels = np.empty(image.size[0] * image.size[1] * 4, np.float32)
        image.pixels.foreach_get(pixels)
        luminance = pixels.reshape(-1, 4)[::97, :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        strength = median / float(np.median(luminance))
        env = nodes.new("ShaderNodeTexEnvironment")
        env.image = image
        links.new(env.outputs["Color"], background.inputs["Color"])
    else:
        background.inputs["Color"].default_value = (*sky, 1)
    background.inputs["Strength"].default_value = strength
    material, tree, out = node_material("backdrop")
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = strength
    if image:
        env = tree.nodes.new("ShaderNodeTexEnvironment")
        env.image = image
        geometry = tree.nodes.new("ShaderNodeNewGeometry")
        tree.links.new(geometry.outputs["Incoming"], env.inputs["Vector"])
        negate = tree.nodes.new("ShaderNodeVectorMath")
        negate.operation = "SCALE"
        negate.inputs["Scale"].default_value = -1
        tree.links.new(geometry.outputs["Incoming"], negate.inputs[0])
        tree.links.new(negate.outputs["Vector"], env.inputs["Vector"])
        tree.links.new(env.outputs["Color"], emission.inputs["Color"])
    else:
        gradient = tree.nodes.new("ShaderNodeTexGradient")
        ramp = tree.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (0.25, 0.22, 0.2, 1)
        ramp.color_ramp.elements[1].color = (*sky, 1)
        coords = tree.nodes.new("ShaderNodeTexCoord")
        tree.links.new(coords.outputs["Generated"], gradient.inputs["Vector"])
        tree.links.new(gradient.outputs["Fac"], ramp.inputs["Fac"])
        tree.links.new(ramp.outputs["Color"], emission.inputs["Color"])
    tree.links.new(emission.outputs["Emission"], out.inputs["Surface"])
    obj = sphere("backdrop", radius, state["camera_location"], material, state["scenery"], segments=96)
    for attribute in ("visible_diffuse", "visible_glossy", "visible_transmission", "visible_volume_scatter",
                      "visible_shadow"):
        setattr(obj, attribute, False)
    bpy.ops.object.shade_flat()


def model(asset):
    """Appends a Poly Haven model's meshes into an unlinked collection; returns it and its bounds."""
    bpy, mathutils = bpy_modules()
    folder = PH / "models" / asset
    path = next(folder.glob("*.blend"))
    with bpy.data.libraries.load(str(path), link=False) as (source, target):
        target.objects = list(source.objects)
    collection = bpy.data.collections.new(asset)
    lo = mathutils.Vector((1e9, 1e9, 1e9))
    hi = -lo
    for obj in target.objects:
        if obj is None or obj.type not in {"MESH", "EMPTY", "CURVE"}:
            continue
        collection.objects.link(obj)
        if obj.type == "MESH":
            for corner in obj.bound_box:
                p = obj.matrix_world @ mathutils.Vector(corner)
                lo = mathutils.Vector(map(min, lo, p))
                hi = mathutils.Vector(map(max, hi, p))
    for image in bpy.data.images:
        if image.filepath and not pathlib.Path(bpy.path.abspath(image.filepath)).exists():
            candidate = folder / "textures" / pathlib.Path(image.filepath).name
            if candidate.exists():
                image.filepath = str(candidate)
    collection.instance_offset = ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)
    return collection, hi.z - lo.z


def place(state, asset, location, height, rotation=0.0, collection=None):
    """Linked duplicates of a model's meshes (instances ignore holdouts), standing on the ground at `location`."""
    bpy, _ = bpy_modules()
    role = "subject" if collection is state["subject"] else "scenery"
    if (asset, role) not in state["models"]:
        state["models"][(asset, role)] = model(asset)
    source, native = state["models"][(asset, role)]
    _, mathutils = bpy_modules()
    k = height / native
    transform = (mathutils.Matrix.Translation(location) @ mathutils.Matrix.Rotation(rotation, 4, "Z")
                 @ mathutils.Matrix.Diagonal((k, k, k, 1)) @ mathutils.Matrix.Translation(-source.instance_offset))
    copies = []
    for obj in source.objects:
        if obj.type != "MESH":
            continue
        copy = obj.copy()
        copy.parent = None
        copy.matrix_world = transform @ obj.matrix_world
        link(copy, collection or state["scenery"])
        copies.append(copy)
    return copies


def light(state, location, radius, strength, colour=(1.0, 0.85, 0.6)):
    material = emission_material(f"light-{len(state['lights'])}", colour, strength)
    sphere(f"light-{len(state['lights'])}", radius, location, material, state["scenery"], segments=24)
    state["lights"].append({"location": list(location), "radius_m": radius,
                            "value": [strength * c for c in colour]})


def begin(camera_location, look_down_deg=0.0):
    bpy, _ = bpy_modules()
    reset()
    scene = bpy.context.scene
    scenery = bpy.data.collections.new("scenery")
    subject = bpy.data.collections.new("subject")
    scene.collection.children.link(scenery)
    scene.collection.children.link(subject)
    data = bpy.data.cameras.new("camera")
    cam = bpy.data.objects.new("camera", data)
    scene.collection.objects.link(cam)
    cam.location = camera_location
    cam.rotation_euler = (math.radians(90 - look_down_deg), 0, 0)
    scene.camera = cam
    data.sensor_width = common.SENSOR_WIDTH_MM
    data.sensor_fit = "HORIZONTAL"
    data.clip_start = NEAR_CLIP
    data.clip_end = 2000
    return {"scenery": scenery, "subject": subject, "camera": cam, "camera_location": camera_location,
            "models": {}, "lights": []}


def scatter(rng, count, x, y):
    return [(rng.uniform(*x), rng.uniform(*y)) for _ in range(count)]


# MARK: - Scenes

def cobble_path(rng):
    s = begin((0, 0, 0.45), 6)
    world_and_backdrop(s, "birchwood")
    plane("ground", (80, 120), (0, 50, 0), (0, 0, 0), texture_material("cobblestone_floor_01", 1.5), s["scenery"])
    place(s, "dandelion_01", (0.05, 1.5, 0), 0.4, collection=s["subject"])
    for x, y in scatter(rng, 10, (-3, 3), (3, 14)):
        place(s, "fern_02", (x, y, 0), rng.uniform(0.4, 0.8), rng.uniform(0, 6))
    for x, y in scatter(rng, 14, (-12, 12), (15, 40)):
        place(s, "shrub_02", (x, y, 0), rng.uniform(1.0, 2.5), rng.uniform(0, 6))
    for x, y in scatter(rng, 14, (-8, 8), (18, 60)):
        light(s, (x, y, rng.uniform(0.3, 3.0)), rng.uniform(0.02, 0.06), rng.uniform(40, 400))
    return s, {"subject": 1.5, "background": 25.0}


def brick_wall(rng):
    s = begin((0, 0, 1.2), 3)
    world_and_backdrop(s, "alps_field")
    plane("ground", (80, 120), (0, 50, 0), (0, 0, 0), texture_material("leafy_grass", 1.0), s["scenery"])
    angle = math.radians(62)
    plane("wall", (60, 6), (-1.2 + 30 * math.cos(angle), 1.5 + 30 * math.sin(angle), 3), (math.radians(90), 0, angle),
          texture_material("brick_wall_001", 2.0, 0.9, (60, 6)), s["scenery"])
    # Toward the camera, off the wall's face.
    normal = (0.12 * math.sin(angle), -0.12 * math.cos(angle))
    place(s, "potted_plant_04", (0.35, 2.2, 0.0), 0.9, collection=s["subject"])
    for k in range(18):
        t = 0.6 + k * 1.6
        light(s, (-1.2 + t * math.cos(angle) + normal[0], 1.5 + t * math.sin(angle) + normal[1],
                  2.2 + 0.15 * math.sin(k)), 0.025,
              rng.uniform(80, 300))
    return s, {"subject": 2.2, "background": 12.0}


def trunk_forest(rng):
    s = begin((0, 0, 1.0), 2)
    world_and_backdrop(s, "autumn_forest_04")
    plane("ground", (100, 140), (0, 60, 0), (0, 0, 0), texture_material("forest_leaves_02", 1.5), s["scenery"])
    bark = texture_material("bark_brown_02", 1.0, 0.9)
    for x, y in scatter(rng, 45, (-15, 15), (3.5, 55)):
        if abs(x) < 0.6 and y < 8:
            continue
        cylinder("trunk", rng.uniform(0.12, 0.4), 16, (x, y, 8), bark, s["scenery"])
    place(s, "fern_02", (0.1, 1.8, 0.0), 0.9, collection=s["subject"])
    place(s, "nettle_plant", (-0.38, 0.75, 0.0), 1.0, 0.7)
    for x, y in scatter(rng, 10, (-10, 10), (10, 50)):
        light(s, (x, y, rng.uniform(0.5, 4)), rng.uniform(0.03, 0.08), rng.uniform(60, 300), (1.0, 0.95, 0.85))
    return s, {"subject": 1.8, "background": 15.0}


def night_street(rng):
    s = begin((0, 0, 1.5), 1)
    world_and_backdrop(s, "cobblestone_street_night", median=0.03)
    plane("ground", (60, 160), (0, 70, 0), (0, 0, 0), texture_material("cobblestone_floor_01", 1.5, 0.5), s["scenery"])
    for y in (7, 15, 23, 31, 39):
        for x in (-4.0, 4.0):
            place(s, "street_lamp_01", (x, y, 0), 4.5, 0 if x < 0 else math.pi)
            light(s, (x * 0.8, y, 4.3), 0.08, rng.uniform(150, 400), (1.0, 0.75, 0.45))
    for x, y in scatter(rng, 40, (-25, 25), (45, 120)):
        light(s, (x, y, rng.uniform(1, 12)), rng.uniform(0.08, 0.25), rng.uniform(20, 120),
              tuple(rng.choice([[1.0, 0.8, 0.5], [0.6, 0.8, 1.0], [1.0, 0.4, 0.3]])))
    place(s, "shrub_02", (0.3, 3.0, 0), 1.4, collection=s["subject"])
    light(s, (-1.2, 2.5, 0.9), 0.05, 30, (1.0, 0.85, 0.7))
    return s, {"subject": 3.0, "background": 20.0}


def foliage_layers(rng):
    s = begin((0, 0, 0.9), 0)
    world_and_backdrop(s, "alps_field")
    plane("ground", (60, 120), (0, 50, 0), (0, 0, 0), texture_material("leafy_grass", 1.0), s["scenery"])
    place(s, "nettle_plant", (0.0, 2.0, 0), 1.2, collection=s["subject"])
    for x in (-0.55, 0.6):
        place(s, "shrub_02", (x, 0.9, 0), 1.0, rng.uniform(0, 6))
    for x, y in scatter(rng, 30, (-6, 6), (4, 12)):
        place(s, rng.choice(["shrub_02", "fern_02", "nettle_plant"]), (x, y, 0), rng.uniform(0.8, 2.0), rng.uniform(0, 6))
    for x, y in scatter(rng, 8, (-4, 4), (6, 14)):
        light(s, (x, y, rng.uniform(0.6, 2.2)), 0.03, rng.uniform(60, 250))
    return s, {"subject": 2.0, "background": 8.0}


def tabletop(rng):
    s = begin((0, 0, 0.22), 8)
    world_and_backdrop(s, "birchwood", median=0.15)
    plane("table", (5, 6), (0, 2.5, 0), (0, 0, 0), texture_material("brown_planks_03", 1.0, 0.5), s["scenery"])
    plane("wall", (8, 4), (0, 5.0, 2), (math.radians(90), 0, 0), texture_material("brick_wall_001", 1.5, uv_size=(8, 4)), s["scenery"])
    sphere("subject", 0.06, (0.0, 0.7, 0.06), colour_material("orange", (0.8, 0.3, 0.05), 0.4, noise=30),
           s["subject"])
    cylinder("cup", 0.04, 0.1, (0.18, 1.1, 0.05), colour_material("cup", (0.7, 0.7, 0.75), 0.2), s["scenery"])
    cylinder("cup2", 0.035, 0.12, (-0.2, 0.45, 0.06), colour_material("cup2", (0.1, 0.3, 0.6), 0.3), s["scenery"])
    sphere("glossy", 0.05, (-0.12, 1.6, 0.05), colour_material("chrome", (0.9, 0.9, 0.9), 0.05), s["scenery"])
    for k in range(5):
        sphere(f"ball{k}", 0.04, (rng.uniform(-0.6, 0.6), rng.uniform(1.5, 4.0), 0.04),
               colour_material(f"ball{k}", tuple(rng.uniform(0.1, 0.8, 3)), 0.5, noise=20), s["scenery"])
    for k in range(24):
        light(s, (-2.0 + k * 0.17, 4.9, 0.6 + 0.25 * math.sin(k * 0.8)), 0.012, rng.uniform(60, 250))
    place(s, "potted_plant_04", (0.5, 2.2, 0), 0.5)
    return s, {"subject": 0.7, "background": 4.9}


def meadow(rng):
    s = begin((0, 0, 0.35), 4)
    world_and_backdrop(s, "alps_field")
    plane("ground", (80, 120), (0, 50, 0), (0, 0, 0), texture_material("leafy_grass", 1.0), s["scenery"])
    place(s, "dandelion_01", (0.0, 1.2, 0), 0.4, collection=s["subject"])
    for x, y in scatter(rng, 110, (-6, 6), (0.8, 25)):
        if abs(x) < 0.25 and 0.9 < y < 1.5:
            continue
        place(s, "grass_medium_01", (x * (y / 8 + 0.2), y, 0), rng.uniform(0.15, 0.35), rng.uniform(0, 6))
    for x, y in scatter(rng, 12, (-3, 3), (2, 14)):
        place(s, "dandelion_01", (x, y, 0), rng.uniform(0.3, 0.45), rng.uniform(0, 6))
    for x, y in scatter(rng, 10, (-8, 8), (12, 30)):
        light(s, (x, y, rng.uniform(0.2, 1.5)), 0.03, rng.uniform(80, 300), (1.0, 1.0, 0.95))
    return s, {"subject": 1.2, "background": 15.0}


def spheres_grid(rng):
    s = begin((0, 0, 1.0), 4)
    world_and_backdrop(s, None, sky=(0.45, 0.55, 0.75))
    bpy, _ = bpy_modules()
    world = s["scenery"]
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
    link(sun, world)
    plane("ground", (60, 80), (0, 38, 0), (0, 0, 0), colour_material("checker", (0.7, 0.68, 0.6), 0.7, checker=40),
          world)
    panel = plane("panel", (6, 2.5), (3.5, 8, 1.25), (math.radians(90), 0, math.radians(35)),
                  colour_material("panel", (0.2, 0.5, 0.7), 0.5, noise=40), world)
    panel.name = "slanted-panel"
    sphere("subject", 0.25, (0.0, 2.0, 0.9), colour_material("subject", (0.85, 0.2, 0.15), 0.4, noise=25), s["subject"])
    for k, (x, y) in enumerate(scatter(rng, 30, (-6, 6), (3, 30))):
        r = rng.uniform(0.15, 0.6)
        sphere(f"sphere{k}", r, (x, y, r), colour_material(f"s{k}", tuple(rng.uniform(0.1, 0.9, 3)), 0.5,
                                                           noise=rng.uniform(5, 40)), world)
    for x, y in scatter(rng, 20, (-8, 8), (6, 35)):
        light(s, (x, y, rng.uniform(0.5, 4)), rng.uniform(0.02, 0.05), rng.uniform(50, 500),
              tuple(rng.choice([[1.0, 0.85, 0.6], [0.7, 0.85, 1.0], [1.0, 1.0, 1.0]])))
    return s, {"subject": 2.0, "background": 20.0}


SCENES = {"cobble-path": cobble_path, "brick-wall": brick_wall, "trunk-forest": trunk_forest,
          "night-street": night_street, "foliage-layers": foliage_layers, "tabletop": tabletop,
          "meadow": meadow, "spheres-grid": spheres_grid}


# MARK: - Rendering

def camera_space_depth(cam, location):
    """Planar depth (m) of a world point along the camera's view axis."""
    _, mathutils = bpy_modules()
    p = cam.matrix_world.inverted() @ mathutils.Vector(location)
    return -p.z


def render_to(scene, path, samples, dof=None):
    scene.cycles.samples = samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = NOISE_THRESHOLD
    scene.cycles.adaptive_min_samples = 128
    data = scene.camera.data
    data.dof.use_dof = dof is not None
    if dof:
        data.dof.focus_distance = dof["focus"]
        data.dof.aperture_fstop = dof["fstop"]
        data.dof.aperture_blades = dof["blades"]
        data.dof.aperture_rotation = 0.0
        data.dof.aperture_ratio = 1.0
    scene.render.filepath = str(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    bpy_modules()[0].ops.render.render(write_still=True)
    return time.time() - started


def render_scene(name):
    import numpy as np
    bpy, _ = bpy_modules()
    rng = np.random.default_rng(sum(map(ord, name)))
    state, focus = SCENES[name](rng)
    scene = bpy.context.scene
    cam = state["camera"]
    bpy.context.view_layer.update()
    record = {"scene": name, "camera_matrix_world": [list(row) for row in cam.matrix_world],
              "lights": [], "focus": focus, "renders": {}}
    _, mathutils = bpy_modules()
    for item in state["lights"]:
        record["lights"].append({**item, "depth_m": camera_space_depth(cam, item["location"]),
                                 "camera_space": list(cam.matrix_world.inverted() @ mathutils.Vector(item["location"]))})
    out = RAW / name
    started = time.time()
    for focus_name, s in focus.items():
        base = common.camera(FOCAL, APERTURES[0], s, WIDTH, HEIGHT)
        cam.data.lens = base["image_distance_mm"]
        seconds = render_to(scene, out / focus_name / "input.exr", INPUT_SAMPLES)
        record["renders"][f"{focus_name}/input"] = round(seconds, 1)
        alpha_seconds = render_alpha(scene, state, out / focus_name / "alpha.exr")
        record["renders"][f"{focus_name}/alpha"] = round(alpha_seconds, 1)
        record["renders"][f"{focus_name}/depth"] = round(render_depth(scene, out / focus_name / "depth.exr"), 1)
        for n_stop in APERTURES:
            for blades in BLADES:
                variant = f"f{n_stop}-{'circle' if blades == 0 else f'blade{blades}'}"
                cam_json = common.camera(FOCAL, n_stop, s, WIDTH, HEIGHT, blades)
                seconds = render_to(scene, out / focus_name / f"{variant}.exr", DOF_SAMPLES,
                                    {"focus": s, "fstop": cam_json["blender"]["fstop"], "blades": blades})
                record["renders"][f"{focus_name}/{variant}"] = round(seconds, 1)
                print(f"{name} {focus_name} {variant}: {seconds:.1f} s", flush=True)
    record["seconds"] = round(time.time() - started, 1)
    record["samples"] = {"input_max": INPUT_SAMPLES, "dof_max": DOF_SAMPLES, "adaptive_threshold": NOISE_THRESHOLD,
                         "depth": DEPTH_SAMPLES, "pixel_filter": "box, 1 px", "denoising": False}
    (out / "render.json").write_text(json.dumps(record, indent=1))


def render_alpha(scene, state, path):
    """The subject's visible coverage: everything else held out, film transparent, DOF off."""
    holdouts = list(state["scenery"].objects)
    for obj in holdouts:
        obj.is_holdout = True
    scene.render.film_transparent = True
    seconds = render_to(scene, path, 128)
    for obj in holdouts:
        obj.is_holdout = False
    scene.render.film_transparent = False
    return seconds


def render_depth(scene, path):
    """Planar depth as emission (Camera Data's View Z Depth), keeping each material's alpha: box-filtered,
    so a pixel's value is its coverage-weighted mean depth."""
    bpy, _ = bpy_modules()
    changes = []
    for material in bpy.data.materials:
        if not material.use_nodes:
            continue
        tree = material.node_tree
        outputs = [n for n in tree.nodes if n.type == "OUTPUT_MATERIAL"]
        out = next((n for n in outputs if n.is_active_output), outputs[0] if outputs else None)
        if out is None:
            continue
        surface = out.inputs["Surface"]
        previous = surface.links[0].from_socket if surface.links else None
        bsdf = next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        added = [tree.nodes.new(kind) for kind in ("ShaderNodeCameraData", "ShaderNodeEmission",
                                                    "ShaderNodeBsdfTransparent", "ShaderNodeMixShader")]
        camera_data, emission, transparent, mix = added
        tree.links.new(camera_data.outputs["View Z Depth"], emission.inputs["Color"])
        emission.inputs["Strength"].default_value = 1.0
        mix.inputs["Fac"].default_value = 1.0
        if bsdf is not None:
            alpha = bsdf.inputs["Alpha"]
            if alpha.links:
                tree.links.new(alpha.links[0].from_socket, mix.inputs["Fac"])
            else:
                mix.inputs["Fac"].default_value = alpha.default_value
        tree.links.new(transparent.outputs[0], mix.inputs[1])
        tree.links.new(emission.outputs[0], mix.inputs[2])
        tree.links.new(mix.outputs[0], surface)
        changes.append((tree, surface, previous, added))
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.samples = DEPTH_SAMPLES
    scene.camera.data.dof.use_dof = False
    scene.render.filepath = str(path)
    started = time.time()
    bpy.ops.render.render(write_still=True)
    for tree, surface, previous, added in changes:
        for node in added:
            tree.nodes.remove(node)
        if previous is not None:
            tree.links.new(previous, surface)
    return time.time() - started


# MARK: - Export (research venv)

def read_multilayer(path):
    import numpy as np
    import OpenEXR
    with OpenEXR.File(str(path), separate_channels=True) as f:
        channels = f.parts[0].channels
        def get(suffix):
            key = next(k for k in channels if k.endswith(suffix))
            return np.asarray(channels[key].pixels, dtype=np.float32)
        rgb = np.stack([get("Combined.R"), get("Combined.G"), get("Combined.B")], -1)
        alpha = get("Combined.A")
        depth = get("Depth.Z") if any(k.endswith("Depth.Z") for k in channels) else None
    return rgb, alpha, depth


def export():
    import numpy as np
    for raw in sorted(RAW.glob("*/render.json")):
        record = json.loads(raw.read_text())
        name = record["scene"]
        out = DATA / "blender" / name
        variants = []
        repaired = {}
        for focus_name, s in record["focus"].items():
            src, dst = RAW / name / focus_name, out / focus_name
            rgb, _, _ = read_multilayer(src / "input.exr")
            depth = read_multilayer(src / "depth.exr")[0][..., 0]
            # Renders made with Cycles' default of 8 transparent bounces end some paths through dense
            # leaves early, leaving a depth below the near clip; those take their neighbourhood's median.
            short = depth < NEAR_CLIP
            for y, x in np.argwhere(short):
                window = depth[max(y - 2, 0):y + 3, max(x - 2, 0):x + 3]
                good = window[window >= NEAR_CLIP]
                depth[y, x] = np.median(good) if good.size else NEAR_CLIP
            repaired[focus_name] = int(short.sum())
            common.write_exr(dst / "input.exr", rgb)
            common.write_exr(dst / "input_clipped.exr", np.clip(rgb, 0, 1))
            common.write_exr(dst / "depth.exr", depth)
            common.save_preview(dst / "input.png", rgb)
            _, alpha, _ = read_multilayer(src / "alpha.exr")
            common.write_exr(dst / "alpha.exr", alpha)
            for path in sorted(src.glob("f*.exr")):
                variant = path.stem
                n_stop = float(variant.split("-")[0][1:])
                blades = 0 if variant.endswith("circle") else int(variant.rsplit("blade", 1)[1])
                cam = common.camera(FOCAL, n_stop, s, WIDTH, HEIGHT, blades)
                truth, _, _ = read_multilayer(path)
                common.write_exr(dst / f"{variant}.exr", truth)
                common.save_preview(dst / f"{variant}.png", truth)
                pitch, v = cam["pixel_pitch_mm"], cam["image_distance_mm"]
                lights = []
                for item in record["lights"]:
                    x, y, z = item["camera_space"]
                    depth_m = -z
                    lights.append(dict(x=WIDTH / 2 + v * x / depth_m / pitch, y=HEIGHT / 2 - v * y / depth_m / pitch,
                                       radius_px=v * item["radius_m"] / depth_m / pitch, depth_m=depth_m,
                                       coc_px=abs(float(common.coc_px(cam, depth_m))), value=item["value"]))
                common.write_json(dst / f"{variant}.json", dict(
                    set="blender", scene=name, focus=focus_name, variant=variant, **cam,
                    depth_convention="planar distance from the lens plane along the optical axis, metres (Cycles Z pass)",
                    camera_matrix_world=record["camera_matrix_world"], lights=lights,
                    samples=record["samples"], render_seconds=record["renders"].get(f"{focus_name}/{variant}")))
                variants.append(f"{focus_name}/{variant}")
        common.write_json(out / "scene.json", {"set": "blender", "scene": name, "focus_m": record["focus"],
                                               "variants": variants, "render_seconds": record["seconds"],
                                               "depth_pixels_repaired": repaired})
        print(f"{name}: {len(variants)} variants")


def main(argv):
    global DOF_SAMPLES, INPUT_SAMPLES, APERTURES, BLADES, RAW
    if "--quick" in argv:
        argv = [a for a in argv if a != "--quick"]
        DOF_SAMPLES, INPUT_SAMPLES, APERTURES, BLADES = 64, 64, (1.8,), (5,)
        RAW = DATA / "blender-quick"
    if argv[:1] == ["render"]:
        names = argv[1:] or list(SCENES)
        for name in names:
            render_scene(name)
    elif argv[:1] == ["export"]:
        export()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
