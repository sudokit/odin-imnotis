# odin-imnotis
A notification lib for dear imgui <br />
Example:
```odin
package main

import notis "shared:odin-imnotis"

main :: proc() {
	// ...all the imgui init code

	some_data := f32(2)

	for {
		if some_cond {
			notis.add(
				content = "Some notification",
				title = "Some title", // can be left empty, will just use the type as the title so Warning, Error, Info, etc.
				type = .Success,
			)
		}

		if some_other_cond {
			notis.add(
				content = "Press this to do something",
				type = .Info,
				clicked_proc = do_something,
				clicked_proc_udata = &some_data,
			)
		}

		// ... im new frame
		notis.render()
		// ... im draw
	}
}

do_something :: proc(n: notis.Notification, udata: rawptr) -> bool {
	val := transmute(^f32)(udata)
	return true // return true to dismiss
}
```
