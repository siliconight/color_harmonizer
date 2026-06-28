@tool
extends EditorPlugin

const Dock := preload("res://addons/color_harmonizer/dock/harmonizer_dock.gd")
const DebuggerPlugin := preload("res://addons/color_harmonizer/debugger_plugin.gd")

const AUTOLOAD_NAME := "ColorHarmonizerAnalyzer"
const AUTOLOAD_PATH := "res://addons/color_harmonizer/color_analyzer.gd"

var _dock: Control
var _dbg: EditorDebuggerPlugin


func _enter_tree() -> void:
	# Receive runtime reports from the running game over the debugger channel.
	_dbg = DebuggerPlugin.new()
	add_debugger_plugin(_dbg)

	# Diagnostic dock.
	_dock = Dock.new()
	_dbg.report_received.connect(_dock.update_report)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	# In-game analyzer runs automatically when the project plays (F5).
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _dbg:
		remove_debugger_plugin(_dbg)
		_dbg = null
