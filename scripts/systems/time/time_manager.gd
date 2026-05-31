extends Node

signal time_changed(day: int, hour: int, minute: int)
signal day_changed(day: int)
signal day_period_changed(day_period: String)
signal pause_changed(is_paused: bool)

const MINUTES_PER_DAY := 1440
const DAY_START_MINUTE := 6 * 60
const NIGHT_START_MINUTE := 18 * 60
const PERIOD_DAY := "day"
const PERIOD_NIGHT := "night"

var day: int = 1
var hour: int = 6
var minute: int = 0
var minutes_per_real_second: float = 10.0
var is_paused: bool = true
var day_period: String = PERIOD_DAY

var _minute_accumulator: float = 0.0


func _process(delta: float) -> void:
	if is_paused:
		return

	_minute_accumulator += delta * minutes_per_real_second
	while _minute_accumulator >= 1.0:
		_minute_accumulator -= 1.0
		advance_minutes(1)


func reset(start_day: int = 1, start_hour: int = 6, start_minute: int = 0) -> void:
	day = max(start_day, 1)
	hour = clampi(start_hour, 0, 23)
	minute = clampi(start_minute, 0, 59)
	_minute_accumulator = 0.0
	_update_day_period(true)
	time_changed.emit(day, hour, minute)


func set_paused(value: bool) -> void:
	if is_paused == value:
		return

	is_paused = value
	pause_changed.emit(is_paused)


func advance_minutes(amount: int) -> void:
	if amount <= 0:
		return

	var previous_day: int = day
	var absolute_minutes: int = get_absolute_minutes() + amount
	day = int(absolute_minutes / MINUTES_PER_DAY) + 1

	var minutes_today: int = absolute_minutes % MINUTES_PER_DAY
	hour = int(minutes_today / 60)
	minute = minutes_today % 60

	if day != previous_day:
		day_changed.emit(day)

	_update_day_period(false)
	time_changed.emit(day, hour, minute)


func get_time_label() -> String:
	return "第 %d 天 %02d:%02d" % [day, hour, minute]


func get_absolute_minutes() -> int:
	return (day - 1) * MINUTES_PER_DAY + hour * 60 + minute


func get_minutes_of_day() -> int:
	return hour * 60 + minute


func is_daytime() -> bool:
	var minutes_of_day: int = get_minutes_of_day()
	return minutes_of_day >= DAY_START_MINUTE and minutes_of_day < NIGHT_START_MINUTE


func get_day_period_label() -> String:
	match day_period:
		PERIOD_DAY:
			return "白天"
		PERIOD_NIGHT:
			return "夜晚"
		_:
			return day_period


func get_save_state() -> Dictionary:
	return {
		"day": day,
		"hour": hour,
		"minute": minute,
		"minutes_per_real_second": minutes_per_real_second,
		"is_paused": is_paused,
		"day_period": day_period,
	}


func apply_save_state(state: Dictionary) -> void:
	day = max(1, int(state.get("day", day)))
	hour = clampi(int(state.get("hour", hour)), 0, 23)
	minute = clampi(int(state.get("minute", minute)), 0, 59)
	minutes_per_real_second = max(0.0, float(state.get("minutes_per_real_second", minutes_per_real_second)))
	is_paused = bool(state.get("is_paused", is_paused))
	_minute_accumulator = 0.0
	_update_day_period(true)
	time_changed.emit(day, hour, minute)
	pause_changed.emit(is_paused)


func parse_time_to_minute(value: String) -> int:
	var parts: PackedStringArray = value.split(":")
	if parts.size() != 2:
		return -1

	var parsed_hour: int = clampi(int(parts[0]), 0, 23)
	var parsed_minute: int = clampi(int(parts[1]), 0, 59)
	return parsed_hour * 60 + parsed_minute


func _update_day_period(force_emit: bool) -> void:
	var next_period: String = PERIOD_DAY if is_daytime() else PERIOD_NIGHT
	if not force_emit and next_period == day_period:
		return

	day_period = next_period
	day_period_changed.emit(day_period)
