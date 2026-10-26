use cxx_qt_lib::QString;

#[cxx_qt::bridge]
mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type Converter = super::ConverterRust;

        /// Starts a background job over newline-separated `files`; `kind` is "fmt" or "act".
        /// Reports through `progress` and `finished`; ignored while a job is running.
        #[qinvokable]
        fn run(self: Pin<&mut Converter>, files: &QString, kind: &QString, arg: &QString);

        /// Stops the running job after the current step (kills FFmpeg right away).
        #[qinvokable]
        fn cancel(self: &Converter);

        /// Reads a setting ("output_dir", "conflict", "quality", "office", "language").
        #[qinvokable]
        fn setting(self: &Converter, key: &QString) -> QString;

        /// Validates and saves a setting. Returns "" on success, the error otherwise.
        #[qinvokable]
        fn set_setting(self: &Converter, key: &QString, value: &QString) -> QString;

        /// Existing files on the clipboard, one path per line ("" if none).
        #[qinvokable]
        fn clipboard_files(self: &Converter) -> QString;

        /// Available external converters as `name=0|1` lines.
        #[qinvokable]
        fn available_tools(self: &Converter) -> QString;

        /// Global pointer state "x,y,shift,button1", "" when unavailable.
        #[qinvokable]
        fn pointer(self: &Converter) -> QString;

        /// Overall progress 0..100, or -1 while the current step has no measurable progress.
        #[qsignal]
        fn progress(self: Pin<&mut Converter>, percent: i32);

        /// File currently being processed, followed by its individual result.
        #[qsignal]
        fn current_file(self: Pin<&mut Converter>, file: QString);

        #[qsignal]
        fn file_finished(self: Pin<&mut Converter>, file: QString, message: QString);

        /// Status-line text with a leading "✓ " or "✗ ".
        #[qsignal]
        fn finished(self: Pin<&mut Converter>, message: QString);
    }

    impl cxx_qt::Threading for Converter {}
}

use core::pin::Pin;
use cxx_qt::Threading;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;

#[derive(Default)]
pub struct ConverterRust {
    cancel: Arc<AtomicBool>,
    busy: Arc<AtomicBool>,
}

// Core messages stay English; the UI language is applied here, once, on the way out.
const RU: [(&str, &str); 17] = [
    ("clip #", "фрагмент №"),
    ("no clips", "нет фрагментов"),
    (" clips in ", " фрагм. в "),
    ("bad range", "неверный диапазон"),
    ("bad time", "неверное время"),
    ("cancelled", "отменено"),
    ("Saved ", "Сохранено: "),
    ("Extracted to ", "Распаковано в "),
    ("File copied", "Файл скопирован"),
    ("not implemented yet", "пока не реализовано"),
    ("unsupported format", "формат не поддерживается"),
    ("source already has this format", "файл уже в этом формате"),
    ("no office backend found (install LibreOffice or OnlyOffice)", "офисный пакет не найден (установите LibreOffice или OnlyOffice)"),
    ("OnlyOffice can't write .", "OnlyOffice не умеет сохранять в ."),
    (" here; install LibreOffice for it", " — установите LibreOffice"),
    ("install wl-clipboard (Wayland) or xclip (X11) to copy files", "для копирования файлов установите wl-clipboard (Wayland) или xclip (X11)"),
    ("OnlyOffice produced no output", "OnlyOffice не создал файл"),
];

#[cfg(unix)]
fn locale() -> String {
    ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .find_map(|k| std::env::var(k).ok().filter(|v| !v.is_empty()))
        .unwrap_or_default()
}

#[cfg(windows)]
fn locale() -> String {
    let mut b = [0u16; 85];
    let n = unsafe { windows_sys::Win32::Globalization::GetUserDefaultLocaleName(b.as_mut_ptr(), 85) };
    String::from_utf16_lossy(&b[..(n.max(1) - 1) as usize])
}

fn russian() -> bool {
    match crate::settings::Settings::load().language.as_str() {
        "ru" => true,
        "en" => false,
        _ => locale().starts_with("ru"),
    }
}

fn localize(s: String, ru: bool) -> String {
    if !ru {
        return s;
    }
    RU.iter().fold(s, |s, (en, ru)| s.replace(en, ru))
}

/// Status text with a leading "✓ " / "✗ " so the UI can tell success from failure.
fn mark(r: &Result<String, String>) -> String {
    let (m, t) = match r {
        Ok(o) => ("✓ ", o),
        Err(e) => ("✗ ", e),
    };
    format!("{m}{}", localize(t.clone(), russian()))
}

fn local(p: &str) -> String {
    let p = p.strip_prefix("file://").unwrap_or(p);
    // Windows URLs look like file:///C:/dir/x
    if cfg!(windows) && p.as_bytes().get(2) == Some(&b':') { &p[1..] } else { p }.to_string()
}

/// The whole job, on the worker thread. `done` counts finished files; `emit` gets progress 0..100 (-1 = unknown).
fn job(
    files: &[String], kind: &str, arg: &str, done: &AtomicUsize, emit: &dyn Fn(i32),
    emit_current: &dyn Fn(&str), emit_result: &dyn Fn(&str, String),
) -> String {
    let total = files.len();
    let (mut ok, mut last, mut first_err) = (0, Err("no files".to_string()), None);
    for (i, f) in files.iter().enumerate() {
        if crate::convert::cancelled_now() {
            last = Err("cancelled".into());
            first_err.get_or_insert(mark(&last));
            break;
        }
        done.store(i, Ordering::Relaxed);
        emit(-1);
        emit_current(f);
        last = if kind == "fmt" { crate::convert::convert(&local(f), arg).map(|o| format!("Saved {o}")) }
               else { crate::convert::act(&local(f), arg) };
        emit_result(f, mark(&last));
        if last.is_ok() { ok += 1 } else { first_err.get_or_insert(mark(&last)); }
        done.store(i + 1, Ordering::Relaxed);
        emit(((i + 1) * 100 / total) as i32);
    }
    if total == 1 {
        mark(&last)
    } else {
        let e = first_err.map(|e| format!("   {e}")).unwrap_or_default();
        format!("{} {ok} / {total}{e}", if ok == total { "✓" } else { "✗" })
    }
}

impl qobject::Converter {
    fn run(self: Pin<&mut Self>, files: &QString, kind: &QString, arg: &QString) {
        if self.busy.swap(true, Ordering::SeqCst) {
            return;
        }
        let files: Vec<String> = files.to_string().lines().map(String::from).collect();
        let (kind, arg) = (kind.to_string(), arg.to_string());
        let (cancel, busy) = (self.cancel.clone(), self.busy.clone());
        cancel.store(false, Ordering::SeqCst);
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let q = qt.clone();
            let n = files.len().max(1) as f32;
            let done = Arc::new(AtomicUsize::new(0));
            let (d2, q2) = (done.clone(), qt.clone());
            // FFmpeg's per-file fraction is folded into the overall bar
            crate::convert::use_settings(crate::settings::Settings::load());
            crate::convert::set_hook(Some(crate::convert::Hook {
                progress: Box::new(move |f| {
                    let p = ((d2.load(Ordering::Relaxed) as f32 + f) / n * 100.0) as i32;
                    let _ = q2.queue(move |mut o| o.as_mut().progress(p));
                }),
                cancel,
            }));
            let emit = |p: i32| {
                let _ = q.queue(move |mut o| o.as_mut().progress(p));
            };
            let current_q = qt.clone();
            let emit_current = move |file: &str| {
                let file = file.to_owned();
                let _ = current_q.queue(move |mut o| o.as_mut().current_file(QString::from(file.as_str())));
            };
            let result_q = qt.clone();
            let emit_result = move |file: &str, message: String| {
                let file = file.to_owned();
                let _ = result_q.queue(move |mut o| o.as_mut().file_finished(QString::from(file.as_str()), QString::from(message.as_str())));
            };
            let msg = job(&files, &kind, &arg, &done, &emit, &emit_current, &emit_result);
            crate::convert::set_hook(None);
            busy.store(false, Ordering::SeqCst);
            let _ = qt.queue(move |mut o| o.as_mut().finished(QString::from(msg.as_str())));
        });
    }

    fn cancel(&self) {
        self.cancel.store(true, Ordering::SeqCst);
    }

    fn setting(&self, key: &QString) -> QString {
        QString::from(crate::settings::Settings::load().get(&key.to_string()).as_str())
    }

    fn set_setting(&self, key: &QString, value: &QString) -> QString {
        let mut s = crate::settings::Settings::load();
        let r = s.set(&key.to_string(), &value.to_string()).and_then(|_| s.save());
        QString::from(r.err().unwrap_or_default().as_str())
    }

    fn clipboard_files(&self) -> QString {
        QString::from(crate::convert::clipboard_files().join("\n").as_str())
    }

    fn available_tools(&self) -> QString {
        let bins = ["magick", "ffmpeg", "ffprobe", "pdftoppm", "pdftotext", "pdfseparate", "gs", "bsdtar", "soffice", "x2t"];
        let path = std::env::var_os("PATH").unwrap_or_default();
        let report = bins.iter().map(|bin| {
            let found = std::env::split_paths(&path).any(|dir| {
                let plain = dir.join(bin);
                let exe = dir.join(format!("{bin}.exe"));
                plain.is_file() || exe.is_file()
            });
            format!("{bin}={}", found as u8)
        }).collect::<Vec<_>>().join("\n");
        QString::from(report.as_str())
    }

    fn pointer(&self) -> QString {
        QString::from(crate::trigger::pointer().unwrap_or_default().as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn localizes_only_for_ru() {
        assert_eq!(localize("Saved /a.png".into(), false), "Saved /a.png");
        assert_eq!(localize("Saved /a.png".into(), true), "Сохранено: /a.png");
        assert_eq!(localize("unsupported format: exe".into(), true), "формат не поддерживается: exe");
        assert_eq!(localize("ffmpeg: boom".into(), true), "ffmpeg: boom");
    }

    #[test]
    fn job_batches_and_reports() {
        let d = std::env::temp_dir().join("clementine-test-job");
        std::fs::create_dir_all(&d).unwrap();
        let (a, b) = (d.join("a.png"), d.join("b.png"));
        for f in [&a, &b] {
            std::process::Command::new("magick").args(["-size", "8x8", "xc:red", f.to_str().unwrap()]).status().unwrap();
        }
        let files = vec![a.display().to_string(), b.display().to_string(), d.join("missing.png").display().to_string()];
        let seen = std::cell::RefCell::new(vec![]);
        let done = AtomicUsize::new(0);
        let msg = job(&files, "fmt", "webp", &done, &|p| seen.borrow_mut().push(p), &|_| {}, &|_, _| {});
        assert!(msg.starts_with("✗ 2 / 3"), "{msg}");
        assert_eq!(seen.borrow().last(), Some(&100));
        assert!(d.join("a.webp").exists() && d.join("b.webp").exists());
        let one = job(&files[..1], "fmt", "jpg", &done, &|_| {}, &|_| {}, &|_, _| {});
        assert!(one.starts_with("✓ ") && one.ends_with("a.jpg"), "{one}");
        std::fs::remove_dir_all(&d).unwrap();
    }
}
