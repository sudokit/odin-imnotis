package notis

import sa "core:container/small_array"
import "core:fmt"
import me "core:math/ease"
import "core:reflect"
import "core:strings"
import "core:time"

import im "shared:odin-imgui"

Type :: enum {
	None,
	Success,
	Info,
	Warning,
	Error,
}

@(private)
Phase :: enum {
	New,
	Fade_In,
	Fade_Out,
	Wait,
}

Notification_Clicked_Proc :: #type proc(_: Notification, udata: rawptr) -> bool

Notification :: struct {
	content:          cstring,
	title:            cstring,
	type:             Type,
	click_proc:       Notification_Clicked_Proc,
	dismiss_duration: time.Duration,
	phase:            Phase,
	udata:            rawptr,
	_window_name:     cstring,
	_time:            time.Tick,
	_cached_width:    f32,
	_start:           time.Tick,
	_id:              u64,
	_y:               f32,
	_hovered:         bool,
}

MAX_NOTIFICATIONS :: 1 << 6

@(private)
FADE_DURATION :: 150 * time.Millisecond

@(private)
PADDING_BETWEEN :: 10

@(private)
PADDING :: [2]f32{20, 20}

@(private)
notifications: sa.Small_Array(MAX_NOTIFICATIONS, Notification)

@(private)
current_id: u64

get :: proc() -> []Notification {return sa.slice(&notifications)}

add :: proc(
	content: string,
	title := "",
	type: Type = .None,
	dismiss_duration: time.Duration = 3 * time.Second,
	clicked_proc: Notification_Clicked_Proc = nil,
	clicked_proc_udata: rawptr = nil,
) -> bool {
	if sa.len(notifications) >= sa.cap(notifications) do return false
	defer current_id += 1
	return sa.append(
		&notifications,
		Notification {
			phase = .New,
			title = strings.clone_to_cstring(reflect.enum_string(type) if title == "" else title),
			content = strings.clone_to_cstring(content),
			type = type,
			dismiss_duration = dismiss_duration,
			click_proc = clicked_proc,
			udata = clicked_proc_udata,
			_window_name = fmt.caprintf("##NOTI%d", current_id),
			_start = time.tick_now(),
			_id = current_id,
		},
	)
}

render :: proc() {
	// update phases
	#reverse for &n, i in get() {
		#partial switch n.phase {
		case .Fade_In:
			if time.tick_since(n._time) >= FADE_DURATION {
				n._time = time.tick_now()
				n.phase = .Wait
			}
		case .Fade_Out:
			if time.tick_since(n._time) >= FADE_DURATION {
				delete(n.content)
				delete(n.title)
				delete(n._window_name)
				sa.ordered_remove(&notifications, i)
			}
		case .Wait:
			if time.tick_since(n._time) >= n.dismiss_duration {
				n._time = time.tick_now()
				n.phase = .Fade_Out
			}
		}
	}

	im.PushStyleVar(.WindowBorderSize, 0); defer im.PopStyleVar()


	vp := im.GetMainViewport()
	io := im.GetIO()

	curr_y := f32(0)
	for &n in get() {
		if n.phase == .New {
			n.phase = .Fade_In
			n._time = time.tick_now()
			n._y = curr_y
			continue
		}

		alpha := get_alpha(n)
		accent := get_color(n.type)
		clickable := n.click_proc != nil && (n.phase != .Fade_In || n.phase != .Fade_Out)

		n._y += (curr_y - n._y) * min(1, io.DeltaTime * 15)

		window_flags: im.WindowFlags =
			im.WindowFlags_NoNav +
			im.WindowFlags_NoDecoration +
			im.WindowFlags_NoInputs +
			{
					.AlwaysAutoResize,
					.NoBringToFrontOnFocus,
					.NoFocusOnAppearing,
					.NoSavedSettings,
					.NoMove,
				}
		if clickable do window_flags -= {.NoMouseInputs}

		im.PushStyleVar(.Alpha, alpha); defer im.PopStyleVar()

		im.SetNextWindowPos(vp.Pos + vp.Size - PADDING - {0, n._y} - get_offset(n), .Always, 1)

		if im.Begin(n._window_name, flags = window_flags) {
			defer im.End()
			im.BringWindowToDisplayFront(im.GetCurrentWindow())

			n._hovered = im.IsItemHovered()
			if n.click_proc != nil && n._hovered {
				if im.IsMouseClicked(.Left) && n.click_proc(n, n.udata) {
					n._time = time.tick_now()
					n.phase = .Fade_Out
				}
			}

			im.PushTextWrapPos(vp.Size.x / 3)

			im.TextColored(accent, n.title)

			if n.content != "" {
				im.Separator()
				im.Text("%s", n.content)
			}
			im.PopTextWrapPos()

			current_pct: f32
			#partial switch n.phase {
			case .Fade_In:
				current_pct = 1
			case .Wait:
				current_pct =
					1 - clamp(f32(time.tick_since(n._time)) / f32(n.dismiss_duration), 0, 1)
			case .Fade_Out:
				current_pct = 0
			}

			// draw progress bar
			bar_height := f32(2)
			im.Dummy({0, bar_height})

			style := im.GetStyle()

			size := [2]f32 {
				im.GetContentRegionAvail().x + style.ItemSpacing.x * 2,
				bar_height - style.ItemSpacing.y,
			}
			start := im.GetCursorScreenPos() - [2]f32{style.ItemSpacing.x, bar_height}
			end := start + size + {0, style.ItemSpacing.y}

			width := end.x - start.x
			progress_x := start.x + (current_pct * width)

			draw_list := im.GetWindowDrawList()

			progress_color := get_progress_color(current_pct)

			im.DrawList_AddRectFilled(
				draw_list,
				start,
				[2]f32{progress_x, end.y},
				im.ColorConvertFloat4ToU32(progress_color * {1, 1, 1, alpha}),
			)

			curr_y += im.GetWindowHeight() + PADDING_BETWEEN
			w := im.GetWindowWidth()
			n._cached_width = w
		}
	}
}

@(private)
get_offset :: proc(n: Notification) -> im.Vec2 {
	if n._cached_width == 0 || n.phase == .Wait do return 0

	elapsed := time.tick_since(n._time)

	progress := f32(time.duration_seconds(elapsed) / time.duration_seconds(FADE_DURATION))
	progress = clamp(progress, 0.0, 1.0)

	distance := n._cached_width + PADDING.x

	offset_x: f32 = 0
	#partial switch n.phase {
	case .Fade_In:
		t := f32(me.exponential_out(progress))
		offset_x = (1.0 - t) * distance
	case .Fade_Out:
		t := f32(me.exponential_in(progress))
		offset_x = -t * distance
	}

	return {offset_x, 0}
}

@(private)
get_alpha :: proc(n: Notification) -> f32 {
	#partial switch n.phase {
	case .Fade_In:
		return clamp(f32(time.tick_since(n._time)) / f32(FADE_DURATION), 0, 1)
	case .Fade_Out:
		return 1 - clamp(f32(time.tick_since(n._time)) / f32(FADE_DURATION), 0, 1)
	}
	return 1
}

@(private)
get_color :: proc(type: Type) -> im.Vec4 {
	#partial switch type {
	case .Info:
		return {0.20, 0.60, 1.00, 1.00}
	case .Warning:
		return {1.00, 0.75, 0.00, 1.00}
	case .Error:
		return {1.00, 0.20, 0.20, 1.00}
	case .Success:
		return {0.20, 0.80, 0.40, 1.00}
	}
	return 1
}

@(private)
get_progress_color :: proc(progress: f32) -> im.Vec4 {
	t := clamp(progress, 0.0, 1.0)

	start := im.Vec4{1.0, 0.2, 0.2, 1.0}
	end := im.Vec4{0.2, 0.8, 0.4, 1.0}

	return start + (end - start) * t

}
