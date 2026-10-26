//! X11 "Shift + drag" trigger: reports the global pointer state so QML can pop the menu up.
//! Polling beats XInput2 here: no event loop or threads, ~30 cheap round-trips per second.
//! Windows: GetCursorPos + GetAsyncKeyState, same polling idea.
// ponytail: Linux covers X11 only (also XWayland, which sees X clients only).

#[cfg(windows)]
pub fn pointer() -> Option<String> {
    use windows_sys::Win32::Foundation::POINT;
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON, VK_SHIFT};
    use windows_sys::Win32::UI::WindowsAndMessaging::GetCursorPos;
    let mut p = POINT { x: 0, y: 0 };
    // SAFETY: plain Win32 calls with a valid out-pointer
    unsafe {
        if GetCursorPos(&mut p) == 0 {
            return None;
        }
        let down = |vk| (GetAsyncKeyState(vk as i32) as u16 & 0x8000 != 0) as u8;
        Some(format!("{},{},{},{}", p.x, p.y, down(VK_SHIFT), down(VK_LBUTTON)))
    }
}

#[cfg(unix)]
use std::sync::OnceLock;
#[cfg(unix)]
use x11rb::{connection::Connection, protocol::xproto::{ConnectionExt, KeyButMask}, rust_connection::RustConnection};

#[cfg(unix)]
static CONN: OnceLock<Option<(RustConnection, u32)>> = OnceLock::new();

/// "x,y,shift,button1" (shift/button as 0/1), or None without an X server.
#[cfg(unix)]
pub fn pointer() -> Option<String> {
    let (conn, root) = CONN
        .get_or_init(|| x11rb::connect(None).ok().map(|(c, n)| { let r = c.setup().roots[n].root; (c, r) }))
        .as_ref()?;
    let p = conn.query_pointer(*root).ok()?.reply().ok()?;
    Some(format!(
        "{},{},{},{}",
        p.root_x,
        p.root_y,
        p.mask.contains(KeyButMask::SHIFT) as u8,
        p.mask.contains(KeyButMask::BUTTON1) as u8
    ))
}

#[cfg(test)]
mod tests {
    #[test]
    fn pointer_format() {
        // without an X server this is None; with one, four comma-separated numbers
        if let Some(s) = super::pointer() {
            assert_eq!(s.split(',').filter(|n| n.parse::<i32>().is_ok()).count(), 4);
        }
    }
}
