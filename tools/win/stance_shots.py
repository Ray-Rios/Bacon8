# Stance check renders (2026-11-14): Bacon World's combat-ready stance looked wrong on every body, and the
# upper body swung left and right when running in it. Renders the library's clips as authored (the UAL
# mannequin) beside the same clips on the B8 male (art/build/godot: what the games get), body only.
#   blender -b --factory-startup -P stance_shots.py -- <out dir>
import bpy, sys, math, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else r"C:\Bacon8\tmp\stance_shots"
os.makedirs(OUT, exist_ok=True)
H = r"C:\Bacon8\art\build\godot\Humans"
UAL = r"C:\Bacon8\art\pipeline\Animations\Quaternius\UAL1_Standard.glb"
CLIPS = [("Idle_Loop", 0.0), ("Sword_Idle", 0.0), ("Spear_Idle_Loop", 0.0), ("TwoHand_Idle_Loop", 0.0)]
JOG = [("Jog_Fwd_Loop", 0.0), ("Jog_Fwd_Loop", 0.2325), ("Jog_Fwd_Loop", 0.465)]
HIDE = ("Top", "Bottom", "Shoes", "Under", "Wrist", "Hair", "Lashes", "Brows")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "SINGLE"
    sh.single_color = (0.78, 0.72, 0.66)
    sh.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 360, 560
    sc.render.resolution_percentage = 100
    cd = bpy.data.cameras.new("cam")
    cd.lens = 50
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam


def imp(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def action(name):
    a = bpy.data.actions.get(name)
    if a is None:
        a = next((x for x in bpy.data.actions if x.name.split("|")[-1] == name or x.name.startswith(name + "_") or x.name.startswith(name + ".")), None)
    return a


def pose(arm, name, t):
    act = action(name)
    if act is None:
        print("NO ACTION", name, [a.name for a in bpy.data.actions][:12])
        return False
    ad = arm.animation_data or arm.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    ad.action = act
    if hasattr(ad, "action_slot") and len(getattr(act, "slots", [])):
        ad.action_slot = act.slots[0]
    fps = bpy.context.scene.render.fps
    bpy.context.scene.frame_set(int(round(act.frame_range[0] + t * fps)))
    return True


def shot(name, azim, height=1.2, dist=3.6, target=(0.0, 0.0, 0.92)):
    sc = bpy.context.scene
    cam = sc.camera
    a = math.radians(azim)
    # azim 0: in front of the figure (glTF +Z forward is Blender -Y)
    pos = Vector((math.sin(a) * dist, -math.cos(a) * dist, height))
    cam.location = pos
    cam.rotation_euler = (Vector(target) - pos).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("shot", name)


def run(label, body, packs):
    reset()
    objs = imp(body)
    arm = next(o for o in objs if o.type == "ARMATURE")
    for o in objs:
        if o.type == "MESH" and any(k in o.name for k in HIDE):
            o.hide_render = True
    for p in packs:
        for o in imp(p):
            if o not in objs:
                bpy.data.objects.remove(o, do_unlink=True)
    for name, t in CLIPS:
        if pose(arm, name, t):
            shot(f"{label}_{name}_front", -30)
            shot(f"{label}_{name}_side", -90)
    for name, t in JOG:
        if pose(arm, name, t):
            shot(f"{label}_{name}_{int(t * 1000):03d}_back", 180, height=1.6)


run("ual", UAL, [])
run("b8m", os.path.join(H, "Male.glb"), [os.path.join(H, "Anims", "B8_Male_Anims_Core.glb"), os.path.join(H, "Anims", "B8_Male_Anims_Combat.glb")])
print("DONE")
