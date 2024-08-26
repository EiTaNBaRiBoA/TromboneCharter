class_name Settings
extends PanelContainer
# this should really be named something like EditDash, and have a Settings class
# separately that knows about things from this and the new OptsDialog
@onready var opts_dialog : EditorOpts = %EditorOpts

var tmb : TMBInfo:
	get: return Global.working_tmb
	set(_v): assert(false,"I don't own that!")
@onready var title      = %SongInfo.get_node("Title")
@onready var short_name = %SongInfo.get_node("ShortTitle")
@onready var author     = %SongInfo.get_node("Author")
@onready var genre      = %SongInfo.get_node("Genre")
@onready var track_ref  = %SongInfo.get_node("TrackRef")
@onready var desc       = %SongInfo.get_node("Description")
@onready var length  :NumField= %SongInfo2.get_node("Length")
@onready var tempo   :NumField= %SongInfo2.get_node("Tempo")
@onready var timesig :NumField= %SongInfo2.get_node("TimeSig")
@onready var year    :NumField= %SongInfo2.get_node("Year")
@onready var diff    :NumField= %SongInfo2.get_node("Diff")
@onready var notespc :NumField= %SongInfo2.get_node("NoteSpacing")
var tween : Tween

var values : Array:
	get: return [
		title,short_name,author,genre,desc,track_ref,
		length,tempo,timesig,year,diff,notespc
	]

enum {
	VIEW_CHART_INFO,
	VIEW_EDIT_SETTINGS,
}

var current_view : int = VIEW_CHART_INFO
var zoom := 1.0
var propagate_slide_changes : bool:
	get: return %PropagateChanges.button_pressed != Input.is_action_pressed("hold_slide_prop")
	set(value): %PropagateChanges.button_pressed = value


var use_custom_colors : bool:
	get: return %UseColors.button_pressed
	set(value): %UseColors.button_pressed = value
var start_color : Color:
	get: return %StartColor.color
	set(value): %StartColor.color = value
var end_color : Color:
	get: return %EndColor.color
	set(value): %EndColor.color = value
var default_start_color = Color("#FF3600")
var default_end_color = Color("#FDCA4B")
# TODO remove magic hidden load-bearing spinboxes
var section_start : float:
	get: return %SectionStart.value
	set(with):  %SectionStart.value = with
var section_length : float:
	get: return %SectionLength.value
	set(with):  %SectionLength.value = with
var playhead_pos : float:
	get: return %PlayheadPos.value
	set(with):  %PlayheadPos.value = with
@onready var sect_start_handle = %SectStartHandle
var note_tooltips : bool:
	get: return %NoteTooltips.button_pressed
	set(value): %NoteTooltips.button_pressed = value
var return_playhead : bool:
	get: return %PlaybackEndBehavior.button_pressed
	set(value): %PlaybackEndBehavior.button_pressed = value
enum { PASTE_REJECT, PASTE_EXTEND }
var paste_behavior : int:
	get: return %PasteBehaviorOption.selected
	set(value):
		if !(value == PASTE_REJECT || value == PASTE_EXTEND): assert(false)
		%PasteBehaviorOption.select(value)

var pitch_snap : int:
	get: return %PitchSnap.value
var snap_pitch : bool:
	get: return %PitchSnapChk.button_pressed != Input.is_action_pressed("hold_snap_pitch")
	set(value): %PitchSnapChk.button_pressed = value

var timing_snap : int:
	get: return %TimingSnap.value
var snap_time : bool:
	get: return %TimeSnapChk.button_pressed != Input.is_action_pressed("hold_snap_time")
	set(value): %TimeSnapChk.button_pressed = value

var tap_notes : bool:
	get: return %InsertTapNotes.button_pressed || Input.is_action_pressed("hold_insert_taps")


func _ready() -> void:
	start_color = default_start_color
	end_color = default_end_color
	
	var panel : StyleBoxFlat = get_theme_stylebox("panel")
	panel.corner_radius_top_left     = 0
	panel.corner_radius_top_right    = 0
	panel.corner_radius_bottom_left  = 0
	panel.corner_radius_bottom_right = 0
	# i think these are redundant anyway. nevertheless,
	_on_preview_volume_changed(0.0)
	_on_toot_volume_changed(0.0)
	
	Global.settings = self
	get_tree().get_current_scene().chart_loaded.connect(_update_values)
	%Chart.chart_updated.connect(update_save_button)
	_update_view()
	_on_timing_snap_value_changed(timing_snap)
	_toggle_ffmpeg_features()

func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey # i want my type hints
	if key_event == null: return
	
	if key_event.is_action_pressed("toggle_slide_prop"):
		%PropagateChanges.button_pressed = !%PropagateChanges.button_pressed
	elif key_event.is_action_pressed("toggle_snap_pitch"):
		%PitchSnapChk.button_pressed = !%PitchSnapChk.button_pressed 
	elif key_event.is_action_pressed("toggle_snap_time"):
		%TimeSnapChk.button_pressed = !%TimeSnapChk.button_pressed


func _toggle_ffmpeg_features() -> void:
	var disable = !Global.ffmpeg_worker.ffmpeg_exists
	%BuildWaveform.disabled = disable
	%HiResWave.disabled = disable
	%FFmpegHelp.visible = disable
	%PreviewType.disabled = disable


func _update_values() -> void:
	title.value = tmb.title
	short_name.value = tmb.shortName
	author.value = tmb.author
	genre.value = tmb.genre
	desc.text = tmb.description
	track_ref.value = tmb.trackRef
	
	length.value = tmb.endpoint
	length.min_value = 2
	tempo.value = tmb.tempo
	timesig.value = tmb.timesig
	year.value = tmb.year
	diff.value = tmb.difficulty
	notespc.value = tmb.savednotespacing
	%PlayheadPos.max_value = tmb.endpoint
	_update_handles()
	
	if !use_custom_colors:
		start_color = default_start_color
		end_color = default_end_color


func _on_view_switcher_pressed() -> void:
	current_view ^= 1 # check out this fun ligature in JetBrains Mono (Godot's code editor font)
	_update_view()


func _update_view() -> void:
	match current_view:
		VIEW_CHART_INFO: 
			%LyricsTools.hide()
			%EditSettings.hide()
			%SectionSelection.hide()
			%ChartInfo.show()
			%ViewSwitcher.text = "Edit View"
		VIEW_EDIT_SETTINGS:
			%ChartInfo.hide()
			%LyricsTools.show()
			%EditSettings.show()
			%SectionSelection.show()
			%ViewSwitcher.text = "Chart Info"
		_: assert(false, "Somehow tried to set Settings pane view to a wrong value (%d)"
					% current_view)


func _on_zoom_reset_pressed() -> void: %ZoomLevel.value = 1
# _on_zoom_level_changed is called automatically when reset is pressed
func _on_zoom_level_changed(value:float) -> void:
	%ZoomLevel.tooltip_text = str(value)
	var zoom_change = value / zoom
	%ChartView.scroll_horizontal *= zoom_change
	%Chart._on_tmb_updated()
	await(get_tree().process_frame)
	%Chart._on_scroll_change()
	zoom = value


func _update_handles() -> void:
		%SectStartHandle.update_pos(section_start)
		%SectEndHandle.update_pos(min(section_length + section_start,tmb.endpoint))
		%PlayheadHandle.update_pos(playhead_pos)


func _force_decimals(box:SpinBox) -> void:
	var lineedit = box.get_line_edit()
	if box.value == int(box.value):
		lineedit.text = str(box.value)
		box.tooltip_text = lineedit.text
	else:
		box.tooltip_text = str(box.value)
		lineedit.text = ("%.4f" % box.value).rstrip('0.')


func ensure_valid_endpoint() -> void:
	length.min_value = max(2,ceilf(tmb.get_last_note_off()))

#region Sections
const SECT_HANDLE_RADIUS = 3.0

func section_handle_dragged(value:float,which:Node) -> void:
	if which == %SectStartHandle:  _on_section_start_value_changed(value)
	elif which == %SectEndHandle:  _on_section_length_value_changed(value - section_start)
	elif which == %PlayheadHandle: _on_copy_target_value_changed(value)


func update_save_button() -> void:
	const default_button_bg := Color("1a1a1a99")
	const save_hl := Color("26261a99")
	var style : StyleBoxFlat = %SaveChart.get_theme_stylebox("normal")
	# tween waits until finished to start a new tween. we can use this to our advantage
	if SaveCheck.unsaved_changes && style.bg_color != save_hl:
		tween = create_tween()
		tween.tween_property(style,"bg_color",save_hl,0.5)
		tween.parallel().tween_property(%SaveChart,"theme_override_colors/font_color",Color.ANTIQUE_WHITE,0.5)
	elif !SaveCheck.unsaved_changes && style.bg_color != default_button_bg:
		tween = create_tween()
		tween.tween_property(style,"bg_color",default_button_bg,0.5)
		tween.parallel().tween_property(%SaveChart,"theme_override_colors/font_color",Color.WHITE,0.5)


func _on_section_start_value_changed(value) -> void:
	section_start = value
	%SectionLength.max_value = tmb.endpoint - value
	_force_decimals(%SectionStart)
	%SectStartHandle.position.x = %Chart.bar_to_x(section_start) - SECT_HANDLE_RADIUS
	%SectEndHandle.position.x = %Chart.bar_to_x(section_start + section_length) - SECT_HANDLE_RADIUS
	%Chart.queue_redraw()

func _on_section_length_value_changed(value) -> void:
	section_length = value
	_force_decimals(%SectionLength)
	%SectEndHandle.position.x = %Chart.bar_to_x(section_start + section_length) - SECT_HANDLE_RADIUS
	%Chart.queue_redraw()

func _on_copy_target_value_changed(value) -> void:
	playhead_pos = value
	_force_decimals(%PlayheadPos)
	%PlayheadHandle.position.x = %Chart.bar_to_x(playhead_pos) - SECT_HANDLE_RADIUS
	%Chart.queue_redraw()

#endregion

# the second gets called from the former iff volume wasn't already 0
func _on_preview_vol_reset_pressed() -> void: %TrackVolSlider.value = 0
func _on_preview_volume_changed(value: float) -> void:
	%TrackVolSlider.tooltip_text = str(value)
	%TrackPlayer.volume_db = value

func _on_toot_vol_reset_pressed() -> void: %TootVolSlider.value = 0
func _on_toot_volume_changed(value: float) -> void:
	%TootVolSlider.tooltip_text = str(value)
	%TrombPlayer.volume_db = value


func _on_timing_snap_value_changed(_value) -> void:
	if !snap_time: return
	var snap = 1.0 / timing_snap
	%SectionStart.step = snap
	%SectionLength.step = snap


func _on_time_snap_toggled(_button_pressed) -> void:
	var snap = 1.0 / timing_snap
	match snap_time:
		true: 
			%SectionStart.step	= snap
			%SectionLength.step = snap
		false:
			%SectionStart.step = 0.0001
			%SectionLength.step = 0.0001


func _on_length_gui_input(_e) -> void: ensure_valid_endpoint()
