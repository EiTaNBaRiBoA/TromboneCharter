extends Control

@onready var cfg = ConfigFile.new()
@onready var saveload : SaveLoad = $SaveLoad
@onready var settings : Settings = %Settings
@onready var save_check : SaveCheck = $SaveCheck
@onready var ffmpeg_worker : FFmpegWorker = Global.ffmpeg_worker
@warning_ignore("unused_signal")
signal chart_loaded
var tmb : TMBInfo:
	get: return Global.working_tmb
	set(value): Global.working_tmb = value
var popup_location : Vector2i:
	get: return DisplayServer.window_get_position(0) + (Vector2i.ONE * 100)

enum ClipboardType {
	NOTES
}
# TODO move this somewhere else for the love of babi

func _ready():
	get_tree().set_auto_accept_quit(false)
	save_check.confirm_new.connect(_on_new_chart_confirmed)
	save_check.confirm_load.connect(show_popup.bind($LoadDialog))
	
	DisplayServer.window_set_min_size(Vector2(1280,600))
	if OS.get_environment("SteamDeck") == "1":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		var window = get_viewport()
		window.gui_embed_subwindows = true
	$Instructions.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$ErrorPopup.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var err = cfg.load("user://config.cfg")
	if err:
		print("Couldn't load config: %s" % error_string(err))
		show_popup($Instructions) # probably first load
	
	var argv : PackedStringArray = OS.get_cmdline_args()
	if !argv.is_empty() && argv[0].ends_with(".tmb"):
		var path = argv[0]
		var dir = argv[0].substr(0,argv[0].rfind("/"))
		if dir == path: dir = argv[0].substr(0,argv[0].rfind("\\"))
		print("%s passed in as tmb" % path)
		$LoadDialog.current_dir = dir
		_on_load_dialog_file_selected(path)
		return
	$LoadDialog.current_dir = cfg.get_value("Config","saved_dir") if !err else "."
	
	var errs = saveload.try_load_cfg_values()
	for e in errs: print(error_string(e))
	
	_on_new_chart_confirmed()


func _input(event):
	event = event as InputEventKey
	if event == null: return
	if event.is_action_pressed("save_chart_as",false,true): do_save()
	if event.is_action_pressed("save_chart"): do_save(true)
	# If editing text, ignore shortcuts besides Ctrl+(Shift)+S
	# note that, even typing into numerical SpinBoxes, you're using its own child LineEdit
	if ((get_viewport().gui_get_focus_owner() is TextEdit)
	||  (get_viewport().gui_get_focus_owner() is LineEdit)):
		return
	if Input.is_action_pressed("hold_drag_playhead") && !%PlayheadHandle.dragging:
		%Chart.show_preview = true
		%Chart.queue_redraw()
	elif Input.is_action_just_released("hold_drag_playhead"):
		%Chart.show_preview = false
		%Chart.queue_redraw()
	
	if event.is_action_pressed("new_chart"):  _on_new_chart_pressed()
	if event.is_action_pressed("load_chart"): _on_load_chart_pressed()
	if event.is_action_pressed("ui_copy"):  _on_copy()
	if event.is_action_pressed("ui_paste"): _on_paste()
	if event.is_action_pressed("toggle_playback"): %PreviewController._do_preview()
	if event.is_action("select_mode",true) && !Input.get_mouse_button_mask():
		%Chart.mouse_mode = %Chart.SELECT_MODE
		$Alert.alert("Switched mouse to Select Mode", Vector2(%ChartView.global_position.x, 10),
			Alert.LV_SUCCESS)
	
	if event.is_action("edit_mode",true) && !Input.get_mouse_button_mask():
		%Chart.mouse_mode = %Chart.EDIT_MODE
		$Alert.alert("Switched mouse to Edit Mode", Vector2(%ChartView.global_position.x, 10),
			Alert.LV_SUCCESS)


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if !save_check.unsaved_changes:
			get_tree().quit()
			return # otherwise we see the save warning try to pop up lol
		save_check.risky_action = SaveCheck.RISKY_QUIT
		
		show_popup(save_check)


func _on_description_text_changed(): tmb.description = %Description.text
func _on_refresh_button_pressed(): chart_loaded.emit()
func _on_help_button_pressed(): show_popup($Instructions)
func _on_ffmpeg_help_pressed(): show_popup($FFmpegInstructions)


func show_popup(window:Window,rel_pos:=Vector2i.ZERO):
	window.current_screen = get_window().current_screen
	window.position = popup_location if rel_pos==Vector2i.ZERO \
			else DisplayServer.window_get_position(0) + rel_pos
	window.current_screen = get_window().current_screen
	window.popup()
	window.current_screen = get_window().current_screen


func _on_new_chart_pressed():
	if save_check.unsaved_changes:
		save_check.risky_action = SaveCheck.RISKY_NEW
		show_popup(save_check)
	else: _on_new_chart_confirmed()
func _on_new_chart_confirmed():
	tmb = TMBInfo.new()
	%Settings.use_custom_colors = false
	%TrackPlayer.stream = null
	print("new tmb")
	Global.clear_future_edits(true)
	chart_loaded.emit()
	%Chart.chart_updated.emit()


func _on_load_chart_pressed():
	if save_check.unsaved_changes:
		save_check.risky_action = SaveCheck.RISKY_LOAD
		show_popup(save_check)
	else: show_popup($LoadDialog)
func _on_load_dialog_file_selected(path:String) -> void:
	%WavePreview.clear_wave_preview()
	var dir = saveload.on_load_dialog_file_selected(path)
	%TrackPlayer.stream = null
	chart_loaded.emit()
	var err = try_to_load_stream(dir)
	if err: print("No stream loaded -- %s" % error_string(err))
	if %BuildWaveform.button_pressed: %WavePreview.build_wave_preview()
	%Chart.chart_updated.emit()


func _on_save_chart_pressed(): do_save(Input.is_key_pressed(KEY_SHIFT))
func do_save(bypass_dialog:=false):
	tmb.lyrics = %LyricsEditor.package_lyrics()
	if bypass_dialog: _on_save_dialog_file_selected($SaveDialog.current_path)
	else: show_popup($SaveDialog)


func _on_save_dialog_file_selected(path:String) -> void:
	if OS.get_name() == "Windows": path = saveload.validate_win_path(path)

	var err = saveload.save_tmb_to_file(path)
	if err == OK:
		$Alert.alert("chart saved!", Vector2(12, %ViewSwitcher.global_position.y + 38),
			Alert.LV_SUCCESS)
	else:
		$Alert.alert("couldn't save to %s! %s" % [path, error_string(err)],
			%Settings.global_position + Vector2(%Chart.global_position.x,-13),
			Alert.LV_ERROR, 2.5)
		return
	
	var dir = path.substr(0,path.rfind("/"))
	cfg.set_value("Config", "saved_dir", dir)
	try_cfg_save()
	
	err = try_to_load_stream(dir)
	if err: print("No stream loaded — %s" % error_string(err))
	if %BuildWaveform.button_pressed: %WavePreview.build_wave_preview()
	Global.save_point = Global.revision
	settings.update_save_button()

#region AudioLoading
# TODO should we perhaps give the TrackPlayer a script and give it these?
func try_to_load_ogg(path:String) -> int:
	print("Try load ogg from %s" % path)
	var f = FileAccess.open(path,FileAccess.READ)
	if f == null: return FileAccess.get_open_error()

	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null || stream.packet_sequence.packet_data.is_empty():
		print("Ogg load: stream null/no data?")
		return ERR_FILE_CANT_READ

	%TrackPlayer.stream = stream
	return OK


func try_to_load_stream(dir) -> int:
	var err := try_to_load_ogg(dir + "/song.ogg")
	if err: print("Failed to load song.ogg: %s"
		% error_string(err))
	return err
#endregion


func try_cfg_save(): saveload.try_cfg_save()

func _on_copy():
	var start = Global.settings.section_start
	var length = Global.settings.section_length

	var notes = tmb.find_all_notes_in_section(start,length)
	if notes.is_empty():
		print("copy section empy")
		return
	var data = {
		"trombone_charter_data_type": ClipboardType.NOTES,
		"length": length,
		"notes": notes
	}
	DisplayServer.clipboard_set(JSON.stringify(data))
	$Alert.alert("Copied %s notes to clipboard" % notes.size(),
			Vector2(%ChartView.global_position.x, 10), Alert.LV_SUCCESS)

func _on_paste():
	var clipboard = DisplayServer.clipboard_get()
	if !clipboard: return
	var j = JSON.new()
	var err = j.parse(clipboard)
	if err: return

	var data = j.data
	if typeof(data) != TYPE_DICTIONARY: return
	if !data.has('trombone_charter_data_type'): return
	match int(data.trombone_charter_data_type):
		ClipboardType.NOTES:
			if %PlayheadPos.value + data.length > tmb.endpoint:
				$Alert.alert("Can't paste -- would run past the chart endpoint!",
					Vector2(%ChartView.global_position.x, 10), Alert.LV_ERROR)
				return
			Global.copy_data = data.notes #Dew: grab copied notes for use in copy_confirm
			var copy_target = Global.settings.playhead_pos

			$CopyConfirm.set_values(copy_target, data)
			show_popup($CopyConfirm)
		_: assert(false, "Clipboard has magic key, but of wrong value. How did we get here?\n%s"
			% [ data ])

func _on_rich_text_label_meta_clicked(meta):
	var data = JSON.parse_string(meta)
	if not data:
		OS.shell_open(str(meta))
	elif data.has('note'): %Chart.jump_to_note(data['note'], true)
	# DisplayServer is a bit of a weird place to have this but it's the window management ig
	elif data.has('hash'): DisplayServer.clipboard_set(data['hash'])
	else: print("meta clicked and idk what to do, here's the data: %s" % data)

# For some reason I have to manually handle resizing the window contents to fit the window size.
func _on_diff_calc_about_to_popup(): $DiffCalc/PanelContainer.set_size($DiffCalc.size)
func _on_diff_calc_win_size_changed(): $DiffCalc/PanelContainer.set_size($DiffCalc.size)
func _on_diff_calc_win_close_requested(): $DiffCalc.visible = false
func _on_diff_ok_button_pressed(): $DiffCalc.visible = false


func _on_opts_button_pressed() -> void: show_popup(%EditorOpts,Vector2.ONE*48)
func _on_opts_dialog_close_requested() -> void: %EditorOpts.visible = false
