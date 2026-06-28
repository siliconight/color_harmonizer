@tool
extends EditorDebuggerPlugin

# Forwards runtime color reports to the dock. The game sends them via:
#   EngineDebugger.send_message("color_harmonizer:report", [report_dict])
signal report_received(data: Dictionary)


func _has_capture(prefix: String) -> bool:
	return prefix == "color_harmonizer"


func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message == "color_harmonizer:report":
		if data.size() > 0 and data[0] is Dictionary:
			report_received.emit(data[0])
		return true
	return false
