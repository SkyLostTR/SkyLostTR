extends "res://scripts/gold_miner.gd"

func _start_level(target_level: int) -> void:
	# Prevent the result-navigation guard from reopening the result card while a new level boots.
	phase = "starting"
	super._start_level(target_level)

func _close_all_panels() -> void:
	super._close_all_panels()
	# A player who backs out of post-level workshop/rank/help should never get stranded in a non-playing state.
	if phase == "result" and result_panel:
		result_panel.visible = true
		paused_for_panel = true
