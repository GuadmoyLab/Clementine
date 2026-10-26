#![cfg_attr(windows, windows_subsystem = "windows")]
mod bridge;
mod convert;
mod settings;
mod trigger;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};
use std::sync::{Mutex, OnceLock};

static PENDING_MENU: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn pending_menu() -> &'static Mutex<Option<String>> {
    PENDING_MENU.get_or_init(|| Mutex::new(None))
}

/// Returns a pending quick-wheel request. A leading `!` also represents an empty file list.
pub(crate) fn take_menu_request() -> String {
    pending_menu().lock().ok().and_then(|mut request| request.take()).unwrap_or_default()
}

#[cfg(unix)]
fn menu_socket() -> Option<std::path::PathBuf> {
    let base = std::env::var_os("XDG_RUNTIME_DIR")
        .or_else(|| std::env::var_os("XDG_CACHE_HOME"))
        .or_else(|| std::env::var_os("HOME").map(|home| std::path::PathBuf::from(home).join(".cache").into_os_string()))?;
    Some(std::path::PathBuf::from(base).join("clementine").join("menu.sock"))
}

#[cfg(unix)]
fn send_menu_request(files: &[String]) -> bool {
    use std::io::Write;
    use std::os::unix::net::UnixStream;
    let Some(path) = menu_socket() else { return false };
    UnixStream::connect(path)
        .and_then(|mut stream| stream.write_all(files.join("\n").as_bytes()))
        .is_ok()
}

#[cfg(not(unix))]
fn send_menu_request(_files: &[String]) -> bool { false }

#[cfg(unix)]
fn start_menu_server() -> bool {
    use std::io::Read;
    use std::os::unix::net::UnixListener;
    let Some(path) = menu_socket() else { return false };
    if let Some(parent) = path.parent() {
        if std::fs::create_dir_all(parent).is_err() { return false; }
    }
    if path.exists() {
        // A live daemon owns the socket. A stale one can safely be replaced.
        if std::os::unix::net::UnixStream::connect(&path).is_ok() { return false; }
        let _ = std::fs::remove_file(&path);
    }
    let Ok(listener) = UnixListener::bind(&path) else { return false };
    std::thread::spawn(move || {
        for mut stream in listener.incoming().flatten() {
            let mut files = String::new();
            if stream.read_to_string(&mut files).is_ok() {
                if let Ok(mut request) = pending_menu().lock() {
                    *request = Some(format!("!{files}"));
                }
            }
        }
    });
    true
}

#[cfg(not(unix))]
fn start_menu_server() -> bool { true }

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let daemon = args.iter().any(|arg| arg == "--daemon");
    let menu = args.iter().any(|arg| arg == "--menu");
    let files: Vec<String> = args.iter().filter(|arg| !["--daemon", "--menu", "--app"].contains(&arg.as_str())).cloned().collect();
    if menu && send_menu_request(&files) {
        return;
    }
    if daemon && !start_menu_server() {
        return;
    }
    cxx_qt::init_qml_module!("clementine");
    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();
    if let Some(e) = engine.as_mut() {
        e.load(&QUrl::from("qrc:/qt/qml/clementine/qml/Main.qml"));
    }
    if let Some(a) = app.as_mut() {
        a.exec();
    }
}
