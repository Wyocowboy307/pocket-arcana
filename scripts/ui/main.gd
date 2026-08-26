extends Control

var db := ContentDatabase.new()
var engine := MatchEngine.new()
var board_grid: GridContainer
var hand_box: HBoxContainer
var status_label: Label
var detail_label: Label
var log_label: Label
var pass_button: Button
var command_button: Button
var element_box: HBoxContainer
var board_buttons: Dictionary = {}
var selected_card_id := ""
var selected_unit_pos := Vector2i(-1,-1)
var shape_element := ""
var commander_mode := false
var ai_busy := false

func _ready() -> void:
    _build_ui()
    if not db.load_all():
        status_label.text = "Content failed to load. Check the Godot error panel."
        return
    add_child(engine)
    engine.state_changed.connect(_refresh)
    engine.event_emitted.connect(_on_event)
    engine.match_finished.connect(_on_match_finished)
    engine.setup(db,"starter_life","starter_fire")
    _refresh()

func _build_ui() -> void:
    var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",18); margin.add_theme_constant_override("margin_right",18); margin.add_theme_constant_override("margin_top",14); margin.add_theme_constant_override("margin_bottom",14); add_child(margin)
    var root := VBoxContainer.new(); root.add_theme_constant_override("separation",10); margin.add_child(root)
    var title := Label.new(); title.text="POCKET ARCANA — living-board graybox"; title.add_theme_font_size_override("font_size",24); root.add_child(title)
    status_label=Label.new(); status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; root.add_child(status_label)
    var mid:=HBoxContainer.new(); mid.size_flags_vertical=Control.SIZE_EXPAND_FILL; mid.add_theme_constant_override("separation",14); root.add_child(mid)
    board_grid=GridContainer.new(); board_grid.columns=7; board_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL; board_grid.size_flags_vertical=Control.SIZE_EXPAND_FILL; mid.add_child(board_grid)
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var p:=Vector2i(x,y); var b:=Button.new(); b.custom_minimum_size=Vector2(118,82); b.text=""; b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; b.pressed.connect(_on_tile_pressed.bind(p)); board_grid.add_child(b); board_buttons[p]=b
    var side:=VBoxContainer.new(); side.custom_minimum_size=Vector2(300,0); mid.add_child(side)
    detail_label=Label.new(); detail_label.text="Pick a card or creature."; detail_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; detail_label.size_flags_vertical=Control.SIZE_EXPAND_FILL; side.add_child(detail_label)
    log_label=Label.new(); log_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; log_label.custom_minimum_size=Vector2(290,180); side.add_child(log_label)
    element_box=HBoxContainer.new(); root.add_child(element_box)
    var element_label:=Label.new(); element_label.text="Shape:"; element_box.add_child(element_label)
    for el in ["frost","lightning","life","fire","water","earth","wind","death"]:
        var b:=Button.new(); b.text=String({"frost":"❄","lightning":"⚡","life":"🌿","fire":"🔥","water":"💧","earth":"🪨","wind":"🌪","death":"💀"}[el]); b.tooltip_text=el.capitalize(); b.pressed.connect(_choose_shape.bind(el)); element_box.add_child(b)
    command_button=Button.new(); command_button.text="COMMAND"; command_button.pressed.connect(_choose_command); element_box.add_child(command_button)
    pass_button=Button.new(); pass_button.text="PASS CHAPTER"; pass_button.pressed.connect(_pass); element_box.add_child(pass_button)
    var hand_scroll:=ScrollContainer.new(); hand_scroll.custom_minimum_size=Vector2(0,126); root.add_child(hand_scroll)
    hand_box=HBoxContainer.new(); hand_box.add_theme_constant_override("separation",8); hand_scroll.add_child(hand_box)

func _refresh() -> void:
    if engine.players.is_empty(): return
    var p0:Dictionary=engine.players[0]; var p1:Dictionary=engine.players[1]
    status_label.text="Chapter %d/3   Your Heart %d  Seals %d  Wonder %d/10  Aether %d/%d   |   Rival Heart %d  Seals %d  Wonder %d/10   |   %s" % [engine.chapter,p0["heart"],p0["seals"],p0["wonder"],p0["aether"],p0["max_aether"],p1["heart"],p1["seals"],p1["wonder"],"YOUR TURN" if engine.current_player==0 and not engine.match_over else "RIVAL TURN" if not engine.match_over else "MATCH OVER"]
    for pos in board_buttons:
        var tile:=engine.board.get_tile(pos); var b:Button=board_buttons[pos]
        b.text=_tile_text(tile)
        b.disabled=engine.match_over
        if _is_legal_highlight(pos): b.modulate=Color(1.15,1.15,1.15,1) else: b.modulate=Color.WHITE
    for child in hand_box.get_children(): child.queue_free()
    for card_id in p0["hand"]:
        var card:=db.get_card(String(card_id)); var b:=Button.new(); b.custom_minimum_size=Vector2(150,104); b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
        b.text="%s\n%d Aether\n%s" % [card.get("name",card_id),card.get("cost",0),_short_rules(String(card.get("rules","")))]
        b.tooltip_text="%s\n%s" % [card.get("name",""),card.get("rules","")]
        b.disabled=engine.current_player!=0 or engine.match_over
        b.pressed.connect(_select_card.bind(String(card_id))); hand_box.add_child(b)
    command_button.disabled=engine.current_player!=0 or bool(p0["commander_used"]) or engine.match_over
    pass_button.disabled=engine.current_player!=0 or engine.match_over
    var lines:Array=[]
    var start=max(0,engine.event_log.size()-8)
    for i in range(start,engine.event_log.size()): lines.append(engine.event_log[i])
    log_label.text="Recent events:\n"+"\n".join(PackedStringArray(lines))
    if engine.current_player==1 and not engine.match_over and not ai_busy: call_deferred("_run_ai")

func _tile_text(tile:Dictionary) -> String:
    var owner=int(tile.get("owner",-1)); var own="·" if owner<0 else ("YOU" if owner==0 else "RIVAL")
    var terrain=String(tile.get("terrain","neutral")).replace("_"," ").capitalize()
    var states:Array=tile.get("states",[]); var state_text="" if states.is_empty() else "\n["+", ".join(PackedStringArray(states))+"]"
    var unit=tile.get("creature"); var unit_text=""
    if unit!=null: unit_text="\n%s %d/%d" % [unit.get("name","Unit"),unit.get("power",0),unit.get("health",0)]
    var lm=tile.get("landmark"); var lm_text="" if lm==null else "\n⌂ "+String(lm.get("name","Landmark"))
    var sanc="\n♥ Sanctuary" if int(tile.get("sanctuary_owner",-1))>=0 else ""
    return "%s · %s%s%s%s%s" % [own,terrain,state_text,unit_text,lm_text,sanc]

func _select_card(card_id:String) -> void:
    selected_card_id=card_id; selected_unit_pos=Vector2i(-1,-1); shape_element=""; commander_mode=false
    var card:=db.get_card(card_id); detail_label.text="%s — %s\nCost %d\n%s\n\nClick a glowing board tile." % [card.get("name",""),String(card.get("type","")).capitalize(),card.get("cost",0),card.get("rules","")]; _refresh()

func _choose_shape(el:String) -> void:
    selected_card_id=""; selected_unit_pos=Vector2i(-1,-1); commander_mode=false; shape_element=el
    detail_label.text="Shape %s: choose a tile touching your realm. Shaping is your action for the turn." % el.capitalize(); _refresh()

func _choose_command() -> void:
    selected_card_id=""; selected_unit_pos=Vector2i(-1,-1); shape_element=""; commander_mode=true
    var cmd:=db.get_commander(String(engine.players[0]["commander_id"])); detail_label.text="%s\n%s\n\n%s\nChoose a tile." % [cmd.get("name","Commander"),cmd.get("passive_text",""),cmd.get("command_text","")]; _refresh()

func _on_tile_pressed(pos:Vector2i) -> void:
    if engine.current_player!=0 or engine.match_over:return
    var result:Dictionary
    if selected_card_id!="": result=engine.play_card(0,selected_card_id,pos)
    elif shape_element!="": result=engine.shape(0,shape_element,pos)
    elif commander_mode: result=engine.use_commander(0,pos)
    elif selected_unit_pos.x>=0:
        result=engine.move_or_attack(0,selected_unit_pos,pos)
    else:
        var tile:=engine.board.get_tile(pos); var unit=tile.get("creature")
        if unit!=null and int(unit.get("owner",-1))==0:
            selected_unit_pos=pos; detail_label.text="%s %d/%d — choose an adjacent tile to move or fight." % [unit.get("name","Unit"),unit.get("power",0),unit.get("health",0)]; _refresh(); return
        detail_label.text="Select a card, Shape element, Command, or one of your creatures."; return
    if not bool(result.get("ok",false)): detail_label.text="Can't do that: "+String(result.get("reason","Unknown reason"))
    else: selected_card_id=""; selected_unit_pos=Vector2i(-1,-1); shape_element=""; commander_mode=false
    _refresh()

func _pass() -> void:
    var r:=engine.pass_chapter(0); if not bool(r.get("ok",false)): detail_label.text=String(r.get("reason","")); _refresh()

func _run_ai() -> void:
    ai_busy=true; await get_tree().create_timer(0.35).timeout
    if engine.match_over or engine.current_player!=1: ai_busy=false; return
    var action:=engine.ai.choose_action(engine,1); var kind=String(action.get("kind","pass"))
    if kind=="play_card": engine.play_card(1,String(action["card_id"]),action["pos"])
    elif kind=="shape": engine.shape(1,String(action["element"]),action["pos"])
    else: engine.pass_chapter(1)
    ai_busy=false; _refresh()

func _on_event(event:Dictionary) -> void:
    if String(event.get("type",""))=="recipe": detail_label.text="DISCOVERY! %s\nThe world changed because two magics met." % event.get("name","New Terrain")

func _on_match_finished(winner:int) -> void:
    detail_label.text="%s\nStart/reload the scene for another graybox match." % ("YOU WIN!" if winner==0 else "RIVAL WINS")

func _is_legal_highlight(pos:Vector2i) -> bool:
    if engine.current_player!=0:return false
    if selected_card_id!="":return engine.legal_targets_for_card(0,selected_card_id).has(pos)
    if shape_element!="":return engine.board.can_shape(0,pos)
    if commander_mode:return true
    if selected_unit_pos.x>=0:return engine.board.neighbors(selected_unit_pos).has(pos)
    return false

func _short_rules(text:String) -> String:
    return text if text.length()<=52 else text.substr(0,49)+"..."
