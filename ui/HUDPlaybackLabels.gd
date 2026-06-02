extends RefCounted
class_name HUDPlaybackLabels

const UILocalizationScript = preload("res://ui/UILocalization.gd")


static func time_text(sim_time_s: float) -> String:
	var total_seconds: int = int(sim_time_s)
	var minutes: int = int(float(total_seconds) / 60.0)
	var seconds: int = int(total_seconds % 60)
	return UILocalizationScript.fmt("hud.time", "TIEMPO %02d:%02d", [minutes, seconds])


static func view_mode_label(is_3d_enabled: bool, is_first_person_enabled: bool) -> String:
	if is_first_person_enabled:
		return "FP"
	if is_3d_enabled:
		return "3D"
	return "2D"


static func playback_label(playback_paused: bool, simulation_finished: bool) -> String:
	if simulation_finished:
		return UILocalizationScript.t("hud.stopped", "DETENIDA")
	if playback_paused:
		return UILocalizationScript.t("hud.pause", "PAUSA")
	return UILocalizationScript.t("hud.play", "REANUDAR")


static func play_button_text(playback_paused: bool) -> String:
	return UILocalizationScript.t("hud.play", "REANUDAR") if playback_paused else UILocalizationScript.t("hud.pause", "PAUSA")


static func playback_status_text(view_mode: String, playback_paused: bool, simulation_finished: bool) -> String:
	return "%s %s" % [view_mode, playback_label(playback_paused, simulation_finished)]


static func time_scale_text(time_scale: float) -> String:
	var snapped_scale: float = snappedf(maxf(0.0, time_scale), 0.01)
	if absf(snapped_scale - round(snapped_scale)) < 0.001:
		return "x%d" % int(round(snapped_scale))
	if absf(snapped_scale * 10.0 - round(snapped_scale * 10.0)) < 0.001:
		return "x%.1f" % snapped_scale
	return "x%.2f" % snapped_scale


static func key_label(keycode: Key) -> String:
	match keycode:
		KEY_LEFT:
			return "Izq"
		KEY_RIGHT:
			return "Der"
		KEY_UP:
			return "Arriba"
		KEY_DOWN:
			return "Abajo"
		KEY_SPACE:
			return "Espacio"
		KEY_END:
			return "Fin"
		_:
			return str(int(keycode))


static func shortcut_help_text(
	key_time_back: Key,
	key_time_forward: Key,
	key_rooms_scroll_up: Key,
	key_rooms_scroll_down: Key,
	key_play_pause: Key,
	key_stop_and_generate: Key
) -> String:
	return UILocalizationScript.fmt("hud.shortcut_help", "%s/%s tiempo | %s/%s salas | %s reanudar/pausa | %s graficas", [
		key_label(key_time_back),
		key_label(key_time_forward),
		key_label(key_rooms_scroll_up),
		key_label(key_rooms_scroll_down),
		key_label(key_play_pause),
		key_label(key_stop_and_generate)
	])


static func matches_shortcut(event: InputEventKey, keycode: Key) -> bool:
	return event.keycode == keycode or event.physical_keycode == keycode
