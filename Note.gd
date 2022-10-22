class_name Note
extends Control

const BARHANDLE_SIZE := Vector2.ONE * 32
const ENDHANDLE_SIZE := Vector2.ONE * 24
const TAIL_HEIGHT := 16.0
var bar : float:
	set(value):
		bar = value
		_update()
var length : float:
	set(value):
		length = value
		_update()
var end: float:
	get: return bar + length
var pitch_start : float:
	set(value):
		if value != pitch_start && doot_enabled:
			chart.doot(value)
		pitch_start = value
		_update()
var pitch_delta : float:
	set(value):
		if value != pitch_delta && doot_enabled:
			chart.doot(pitch_start + value)
		pitch_delta = value
		_update()
var end_pitch : float:
	get: return pitch_start + pitch_delta
var higher_pitch : float:
	get: return min(end_height,0)
var scaled_length : float:
	get: return length * chart.bar_spacing
var end_height : float:
	get: return -((pitch_delta / Global.SEMITONE) * chart.key_height)
var visual_height : float:
	get: return abs(end_height)
var is_slide: bool:
	get: return pitch_delta != 0
var dragging := 0
enum {
	DRAG_NONE,
	DRAG_BAR,
	DRAG_PITCH,
	DRAG_END,
	DRAG_INITIAL,
}
var drag_start := Vector2.ZERO
var old_bar : float
var old_pitch : float
var old_end_pitch : float
var touching_notes : Dictionary

var doot_enabled : bool = false


@onready var chart = get_parent()
@onready var bar_handle = $BarHandle
var show_bar_handle := true
@onready var pitch_handle = $PitchHandle
@onready var end_handle = $EndHandle
var show_end_handle := true
@onready var player : AudioStreamPlayer = get_tree().current_scene.find_child("AudioStreamPlayer")

# Called when the node enters the scene tree for the first time.
func _ready():
	bar_handle.size = BARHANDLE_SIZE
	bar_handle.position = -BARHANDLE_SIZE / 2
	
	pitch_handle.size = Vector2.DOWN * TAIL_HEIGHT
	
	end_handle.size = ENDHANDLE_SIZE
	
	update_touching_notes()
	_update()
	doot_enabled = true


func _process(_delta):
	if dragging: _process_drag()


func _on_handle_input(event, which):
	var pitch_handle_position = -1 if Input.is_key_pressed(KEY_SHIFT) else 0
	move_child(pitch_handle, pitch_handle_position)
	
	event = event as InputEventMouseButton
	if event == null: return
	if event.pressed: match event.button_index:
		MOUSE_BUTTON_LEFT:
			old_bar = bar
			old_pitch = pitch_start
			old_end_pitch = end_pitch
			dragging = which
			drag_start = get_local_mouse_position()
			chart.doot(pitch_start if which != DRAG_END else end_pitch)
		MOUSE_BUTTON_MIDDLE:
			queue_free()
			chart.update_note_array()


func _process_drag():
	if !(Input.get_mouse_button_mask() & MOUSE_BUTTON_LEFT):
		_end_drag()
		return
	
	match dragging:
		DRAG_BAR:
			var new_time : float
			if Global.settings.snap_time:
				new_time = chart.to_snapped(chart.get_local_mouse_position()).x
			else: new_time = chart.to_unsnapped(chart.get_local_mouse_position()).x
			if new_time + length >= chart.tmb.endpoint:
				new_time = chart.tmb.endpoint - length
			
			var exclude = [old_bar]
			if !Input.is_key_pressed(KEY_ALT):
				if has_slide_neighbor(Global.END_IS_TOUCHING, end_pitch):
					exclude.append(touching_notes[Global.END_IS_TOUCHING].bar)
				
				if has_slide_neighbor(Global.START_IS_TOUCHING, pitch_start):
					exclude.append(touching_notes[Global.START_IS_TOUCHING].bar)
			
			if chart.stepped_note_overlaps(new_time,length,exclude):
				return
			
			bar = new_time
			_update()
			
		DRAG_PITCH:
			var new_pitch : float
			if Global.settings.snap_pitch:
				new_pitch = chart.to_snapped(
						chart.get_local_mouse_position() - Vector2(0, drag_start.y)
						).y
			else: new_pitch = chart.to_unsnapped(
						chart.get_local_mouse_position() - Vector2(0, drag_start.y)
						).y
			pitch_start = new_pitch
			
		DRAG_END:
			var new_end : Vector2 = chart.to_unsnapped(chart.get_local_mouse_position()) \
							- Vector2(bar, pitch_start)
			
			new_end.x = min(chart.tmb.endpoint,
					new_end.x if !Global.settings.snap_time \
					else snapped(new_end.x, 1.0 / Global.settings.timing_snap)
					)
			
			var exclude = [old_bar]
			if has_slide_neighbor(Global.END_IS_TOUCHING, old_end_pitch) \
					&& !Input.is_key_pressed(KEY_ALT):
				exclude.append(touching_notes[Global.END_IS_TOUCHING].bar)
			
			if chart.stepped_note_overlaps(bar, new_end.x, exclude) \
					|| new_end.x <= 0 \
					|| new_end.x + bar > chart.tmb.endpoint:
				return
			
			new_end.y = new_end.y if !Global.settings.snap_pitch \
					else snapped(new_end.y, Global.SEMITONE / Global.settings.pitch_snap)
			new_end.y = clamp(new_end.y, (-13 * Global.SEMITONE) - pitch_start,
					(13 * Global.SEMITONE) - pitch_start)
			
			
			length = new_end.x
			pitch_delta = new_end.y
		DRAG_INITIAL:
			@warning_ignore(unassigned_variable)
			var new_pos : Vector2
			
			if Global.settings.snap_time: new_pos.x = chart.to_snapped(chart.get_local_mouse_position()).x
			else: new_pos.x = chart.to_unsnapped(chart.get_local_mouse_position()).x
			
			if Global.settings.snap_pitch: new_pos.y = chart.to_snapped(chart.get_local_mouse_position()).y
			else: new_pos.y = chart.to_unsnapped(chart.get_local_mouse_position()).y
			new_pos.y = clamp(new_pos.y, (-13 * Global.SEMITONE), (13 * Global.SEMITONE))
			
			pitch_start = new_pos.y
			
			if chart.stepped_note_overlaps(new_pos.x,length,[old_bar]): return
			bar = new_pos.x
		DRAG_NONE: print("Not actually dragging? How tf was this reached")
		_: print("Drag == %d You fucked up somewhere!!" % dragging)


func _end_drag():
	dragging = DRAG_NONE
	
	_snap_near_pitches()
	if !Input.is_key_pressed(KEY_ALT):
		if has_slide_neighbor(Global.START_IS_TOUCHING, old_pitch):
			touching_notes[Global.START_IS_TOUCHING].receive_slide_propagation(Global.END_IS_TOUCHING)
		
		if has_slide_neighbor(Global.END_IS_TOUCHING, old_end_pitch):
			touching_notes[Global.END_IS_TOUCHING].receive_slide_propagation(Global.START_IS_TOUCHING)
	
	update_touching_notes()
	
	chart.update_note_array()


func _snap_near_pitches():
	var near_pitch_threshold = Global.SEMITONE / 12
	if touching_notes.has(Global.START_IS_TOUCHING):
		var neighbor : Note = touching_notes[Global.START_IS_TOUCHING]
		if abs(pitch_start - neighbor.end_pitch) <= near_pitch_threshold:
			pitch_start = neighbor.end_pitch
	if touching_notes.has(Global.END_IS_TOUCHING):
		var neighbor : Note = touching_notes[Global.END_IS_TOUCHING]
		if abs(end_pitch - neighbor.pitch_start) <= near_pitch_threshold:
			pitch_delta = neighbor.pitch_start - pitch_start


func has_slide_neighbor(direction:int,pitch:float):
	match direction:
		Global.START_IS_TOUCHING:
			return touching_notes.has(direction) && touching_notes[direction].end_pitch == pitch
		Global.END_IS_TOUCHING:
			return touching_notes.has(direction) && touching_notes[direction].pitch_start == pitch
	


func update_touching_notes():
	var old_prev_note = touching_notes.get(Global.START_IS_TOUCHING)
	var old_next_note = touching_notes.get(Global.END_IS_TOUCHING)
	touching_notes = chart.find_touching_notes(self)
	
	var prev_note = touching_notes.get(Global.START_IS_TOUCHING)
	match prev_note:
		null: if old_prev_note != null: old_prev_note.update_touching_notes()
		_:
			prev_note.touching_notes[Global.END_IS_TOUCHING] = self if bar >= 0 else null
			prev_note.update_handle_visibility()
	
	var next_note = touching_notes.get(Global.END_IS_TOUCHING)
	match next_note:
		null: if old_next_note != null: old_next_note.update_touching_notes()
		_: 
			next_note.touching_notes[Global.START_IS_TOUCHING] = self if bar >= 0 else null
			next_note.update_handle_visibility()
	
	update_handle_visibility()


func receive_slide_propagation(from:int):
	doot_enabled = false
	match from:
		Global.START_IS_TOUCHING:
			var neighbor = touching_notes[from]
			var length_change = bar - neighbor.end
			var pitch_change = pitch_start - neighbor.end_pitch
			bar -= length_change
			length += length_change
			pitch_start -= pitch_change
			pitch_delta += pitch_change
		Global.END_IS_TOUCHING: 
			var neighbor = touching_notes[from]
			var length_change = end - neighbor.bar
			var pitch_change = end_pitch - neighbor.pitch_start
			length -= length_change
			pitch_delta -= pitch_change
		_: print("?????")
	if length == 0: queue_free()
	doot_enabled = true



func update_handle_visibility():
	show_bar_handle = !touching_notes.has(Global.START_IS_TOUCHING)
	show_end_handle = !touching_notes.has(Global.END_IS_TOUCHING)
	
	if !show_bar_handle:
		bar_handle.size.x = BARHANDLE_SIZE.x / 2
		bar_handle.position.x = 0
	else: 
		bar_handle.size.x = BARHANDLE_SIZE.x
		bar_handle.position.x = -BARHANDLE_SIZE.x / 2
	
	if !show_end_handle:
		end_handle.size.x = ENDHANDLE_SIZE.x / 2
	else:
		end_handle.size.x = ENDHANDLE_SIZE.x
	
	queue_redraw()


func _update():
	if chart == null: return
	position.x = chart.bar_to_x(bar)
	position.y = chart.pitch_to_height(pitch_start)
	
	end_handle.position = Vector2(scaled_length, end_height) - ENDHANDLE_SIZE / 2
	
	pitch_handle.size = Vector2(scaled_length, visual_height + TAIL_HEIGHT)
	pitch_handle.position = Vector2(0, higher_pitch - (TAIL_HEIGHT / 2) )
	
	size.x = scaled_length
	queue_redraw()


func _draw():
	if chart.draw_targets:
		draw_rect(Rect2(bar_handle.position,bar_handle.size),Color.WHITE,false)
		draw_rect(Rect2(pitch_handle.position,pitch_handle.size),Color.WHITE,false)
		draw_rect(Rect2(end_handle.position,end_handle.size),Color.WHITE,false)
	var fill_color = Color("FF6DB4")
	
	var _draw_bar_handle := func():
		var radius = BARHANDLE_SIZE.x / 2
		draw_circle(Vector2.ZERO, radius - 1.0, fill_color)
		draw_arc(Vector2.ZERO, radius - 3.0, 0.0, TAU, 36, Color.WHITE, 2.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color.BLACK, 1.0,true)
	
	var _draw_end_handle := func():
		var radius = ENDHANDLE_SIZE.x / 2
		var endhandle_position := Vector2(size.x,end_height)
		draw_circle(endhandle_position, radius - 1.0, fill_color)
		draw_arc(endhandle_position, radius - 2.0, 0.0, TAU, 36, Color.WHITE, 2.0, true)
		draw_arc(endhandle_position, radius, 0.0, TAU, 36, Color.BLACK, 1.0,true)
	
	var _draw_tail := func():
		var points = PackedVector2Array()
		var y_array := []
		var num_points = 24
		for i in num_points:
			y_array.insert(i, smoothstep(0, 1, float(i) / (num_points - 1)))
		y_array.push_front(0.0)
		y_array.push_back(1.0)
		for idx in y_array.size():
			points.append(Vector2(
					(scaled_length * (float(idx) / (y_array.size() - 1))),
					end_height * y_array[idx])
			)
		for i in 3: # outline, field, core
			draw_polyline(points,
			Color.BLACK if i == 0 else Color.WHITE if i == 1 else fill_color,
			16 if i == 0 else 12 if i == 1 else 6,
			true)
	
	_draw_tail.call()
	if show_bar_handle: _draw_bar_handle.call()
	if show_end_handle: _draw_end_handle.call()
	


func _exit_tree():
	bar = -69420.0
	update_touching_notes()
