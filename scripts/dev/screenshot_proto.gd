extends Node
## Review harness for the Arcana Visual Prototype.
##
##   Godot --path . --scene res://scenes/dev/screenshot_proto.tscn --resolution 1280x720 \
##       -- --out=/abs/shot.png --scenario=overview [--frames=N] [--record=/abs/dir --count=70]
##
## Scenarios stage a state, wait a frame count, and capture. --record dumps a
## frame sequence instead, for assembling a GIF of a whole choreography.

var out_path := "/tmp/proto.png"
var scenario := "overview"
var frames := 45
var record_dir := ""
var record_count := 70
var main: Node

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
        elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
        elif arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
        elif arg.begins_with("--record="): record_dir = arg.trim_prefix("--record=")
        elif arg.begins_with("--count="): record_count = int(arg.trim_prefix("--count="))
    main = load("res://scenes/proto/arcana_visual_prototype.tscn").instantiate()
    add_child(main)
    await _settle(30)
    await _run()
    if record_dir != "":
        DirAccess.make_dir_recursive_absolute(record_dir)
        for i in range(record_count):
            await RenderingServer.frame_post_draw
            var img := get_viewport().get_texture().get_image()
            img.save_png("%s/frame_%03d.png" % [record_dir, i])
        print("RECORDED: ", record_dir)
        get_tree().quit(0)
        return
    await _settle(frames)
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    if image.save_png(out_path) != OK:
        push_error("proto screenshot: save failed")
        get_tree().quit(1)
        return
    print("SCREENSHOT SAVED: ", out_path)
    get_tree().quit(0)

func _settle(n: int) -> void:
    for _i in range(n): await get_tree().process_frame

func _run() -> void:
    match scenario:
        "overview":
            pass
        "hover":
            main.hand.simulate_hover(0)
        "select":
            main.call("_on_card_clicked", 0)
        "summon":
            main.call("_on_card_clicked", 0)
            await _settle(2)
            main.selected_card = 0
            main.call("_play_summon")
        "both":
            main.place_instant("player")
            main.place_instant("enemy")
        "attack":
            main.place_instant("player")
            main.place_instant("enemy")
            await _settle(4)
            main.call("_start_attack")
        "enemy_attack":
            main.place_instant("player")
            main.place_instant("enemy")
            await _settle(4)
            main.call("_start_attack_enemy")
        "bloom":
            main.place_instant("player")
            main.place_instant("enemy")
            await _settle(4)
            main.call("_play", "bloom", {}, main.SPELL_DUR)
        "storm":
            main.place_instant("player")
            main.place_instant("enemy")
            await _settle(4)
            main.call("_play_ember_storm")
        "enemy_summon":
            main.place_instant("player")
            await _settle(4)
            main.call("_enemy_summon")
        _:
            push_error("unknown proto scenario: " + scenario)
