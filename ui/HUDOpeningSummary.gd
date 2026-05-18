extends RefCounted
class_name HUDOpeningSummary

const SimuFireThemeScript = preload("res://ui/SimuFireTheme.gd")


static func compact_label(summary: Dictionary) -> String:
	if summary.is_empty():
		return "Apertura"
	var label: String = String(summary.get("label", "Apertura"))
	var open_pct: int = int(round(float(summary.get("open_fraction", 0.0)) * 100.0))
	var state_short: String = "AB" if open_pct >= 95 else ("CE" if open_pct <= 5 else "%d%%" % open_pct)
	var prefix: String = label.substr(0, min(label.length(), 3))
	var exterior: String = " E" if bool(summary.get("is_exterior", false)) else ""
	return "%s %s%s" % [prefix, state_short, exterior]


static func compact_signature(items: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item in items:
		if item is Dictionary:
			var summary := Dictionary(item)
			parts.append("%s:%.2f:%s" % [
				String(summary.get("label", "")),
				float(summary.get("open_fraction", 0.0)),
				str(bool(summary.get("is_exterior", false)))
			])
		else:
			parts.append(String(item))
	return "|".join(parts)


static func compact_color(summary: Dictionary) -> Color:
	if summary.is_empty():
		return SimuFireThemeScript.MUTED
	var open_fraction: float = clampf(float(summary.get("open_fraction", 0.0)), 0.0, 1.0)
	if open_fraction <= 0.05:
		return Color(0.58, 0.64, 0.68, 0.92)
	if open_fraction >= 0.95:
		return SimuFireThemeScript.GREEN
	return SimuFireThemeScript.YELLOW.lerp(SimuFireThemeScript.ORANGE, open_fraction)
