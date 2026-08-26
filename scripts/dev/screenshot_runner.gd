extends Node
## Dev tool: boot a scene, let it settle, save a PNG of the viewport, quit.
##
## Usage:
##   Godot --path . --scene res://scenes/dev/screenshot.tscn -- \
##         --out=/abs/path.png --frames=90 [--scene-path=res://scenes/main.tscn]
##
## Runs windowed (viewport capture needs a real renderer, so not --headless).

var out_path := "/tmp/pocket_arcana_shot.png"
var frames := 90
var target_scene := "res://scenes/main.tscn"

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
        elif arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
        elif arg.begins_with("--scene-path="): target_scene = arg.trim_prefix("--scene-path=")
    var packed: PackedScene = load(target_scene)
    if packed == null:
        push_error("screenshot_runner: could not load " + target_scene)
        get_tree().quit(1)
        return
    add_child(packed.instantiate())
    for _i in range(frames):
        await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    var err := image.save_png(out_path)
    if err != OK:
        push_error("screenshot_runner: save_png failed (%d) for %s" % [err, out_path])
        get_tree().quit(1)
        return
    print("SCREENSHOT SAVED: ", out_path)
    get_tree().quit(0)
