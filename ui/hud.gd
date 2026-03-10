extends Control
class_name HUD

signal water_action_selected(action: String)
signal vent_action_selected(action: String)
signal rescue_action_selected(action: String)

@onready var btn_aoe = $WaterPanel/MarginContainer/VBoxContainer/BtnAOE
@onready var btn_def_ext = $WaterPanel/MarginContainer/VBoxContainer/BtnDefExt
@onready var btn_off_int = $WaterPanel/MarginContainer/VBoxContainer/BtnOffInt
@onready var btn_def_in = $WaterPanel/MarginContainer/VBoxContainer/BtnDefIn

@onready var btn_exutorio = $VentPanel/MarginContainer/VBoxContainer/BtnExutorio
@onready var btn_vpp = $VentPanel/MarginContainer/VBoxContainer/BtnVPP

@onready var btn_ladder = $RescuePanel/MarginContainer/VBoxContainer/BtnLadderRescue

@onready var time_label: Label = $TimeLabel


func _ready() -> void:
	btn_aoe.pressed.connect(func(): water_action_selected.emit("AOE"))
	btn_def_ext.pressed.connect(func(): water_action_selected.emit("DEF_EXT"))
	btn_off_int.pressed.connect(func(): water_action_selected.emit("OFF_INT"))
	btn_def_in.pressed.connect(func(): water_action_selected.emit("DEF_INT"))

	btn_exutorio.pressed.connect(func(): vent_action_selected.emit("EXUTORIO"))
	btn_vpp.pressed.connect(func(): vent_action_selected.emit("VPP"))

	btn_ladder.pressed.connect(func(): rescue_action_selected.emit("LADDER"))


func update_state(state: Dictionary) -> void:
	if not state.has("sim_time_s"):
		return

	var t: float = float(state["sim_time_s"])
	var total_seconds: int = int(t)
	var minutes := total_seconds / 60
	var seconds: int = total_seconds % 60

	time_label.text = "TIME %02d:%02d" % [minutes, seconds]
