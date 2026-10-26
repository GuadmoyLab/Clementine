//! Conversion core. Knows nothing about the UI.
use std::cell::RefCell;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// Per-thread job context: progress sink (0..1) and a cancel flag. Unset = no progress, no cancel.
pub struct Hook {
    pub progress: Box<dyn Fn(f32)>,
    pub cancel: Arc<AtomicBool>,
}

thread_local! { static SCALE: std::cell::Cell<(f32, f32)> = const { std::cell::Cell::new((0.0, 1.0)) }; }

thread_local! { static CFG: RefCell<crate::settings::Settings> = RefCell::new(Default::default()); }

/// The job thread installs the user's settings once; conversions read them from here.
pub fn use_settings(s: crate::settings::Settings) {
    CFG.with(|c| *c.borrow_mut() = s);
}

fn cfg() -> crate::settings::Settings {
    CFG.with(|c| c.borrow().clone())
}

thread_local! { static HOOK: RefCell<Option<Hook>> = const { RefCell::new(None) }; }

pub fn set_hook(h: Option<Hook>) {
    HOOK.with(|c| *c.borrow_mut() = h);
}

pub fn cancelled_now() -> bool {
    cancelled()
}

fn cancelled() -> bool {
    HOOK.with(|c| c.borrow().as_ref().is_some_and(|h| h.cancel.load(Ordering::Relaxed)))
}

fn report(frac: f32) {
    let (off, span) = SCALE.with(|s| s.get()); // lets one action report progress over several FFmpeg runs
    HOOK.with(|c| if let Some(h) = c.borrow().as_ref() { (h.progress)(off + frac.clamp(0.0, 1.0) * span) });
}

/// FFmpeg with live progress (needs the input's duration from ffprobe) and cancellation.
/// `out` is the last argument; a failed or cancelled run leaves no partial file.
fn ffmpeg(args: &[&str], src: &str, out: &str, len: Option<f64>) -> Result<(), String> {
    let dur = len.or_else(|| run("ffprobe", &["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", src])
        .ok()
        .and_then(|d| d.parse::<f64>().ok()))
        .filter(|d| *d > 0.0);
    let mut child = cmd("ffmpeg")
        .args(["-nostats", "-loglevel", "error", "-progress", "pipe:1"])
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("ffmpeg: {e}"))?;
    let stdout = child.stdout.take().unwrap();
    for line in BufReader::new(stdout).lines().map_while(Result::ok) {
        if cancelled() {
            let _ = child.kill();
            let _ = child.wait();
            let _ = std::fs::remove_file(out);
            return Err("cancelled".into());
        }
        if let (Some(us), Some(d)) = (line.strip_prefix("out_time_us=").and_then(|v| v.parse::<f64>().ok()), dur) {
            report((us / 1e6 / d) as f32);
        }
    }
    let r = child.wait_with_output().map_err(|e| e.to_string())?;
    if r.status.success() {
        Ok(())
    } else {
        let _ = std::fs::remove_file(out);
        Err(String::from_utf8_lossy(&r.stderr).trim().to_string())
    }
}

/// Moves `p` into the output folder from the settings (if one is set).
fn redirect(p: PathBuf) -> PathBuf {
    let dir = cfg().output_dir;
    match (dir.is_empty(), p.file_name()) {
        (false, Some(name)) => {
            let _ = std::fs::create_dir_all(&dir);
            Path::new(&dir).join(name)
        }
        _ => p,
    }
}

/// `a.png` -> `a-2.png`, `a-3.png`, ... (`a.tar.gz` -> `a-2.tar.gz`)
fn numbered(p: &Path) -> PathBuf {
    let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("file");
    let dot = [".tar.gz", ".tar.xz", ".tar.bz2"].iter().find(|e| name.ends_with(*e)).map(|e| name.len() - e.len())
        .or_else(|| name.rfind('.').filter(|i| *i > 0))
        .unwrap_or(name.len());
    let (stem, ext) = name.split_at(dot);
    (2..).map(|n| p.with_file_name(format!("{stem}-{n}{ext}"))).find(|c| !c.exists()).unwrap()
}

/// Final path for a result: output folder applied, and an existing file is kept unless "overwrite" is set.
fn place(p: PathBuf) -> PathBuf {
    let p = redirect(p);
    if cfg().conflict == "overwrite" || !p.exists() { p } else { numbered(&p) }
}

/// `name<suffix>.ext` (output folder applied), or `name<suffix>2.ext`, `…3` if taken.
fn unique(p: &Path, suffix: &str) -> PathBuf {
    let p = redirect(p.to_path_buf());
    let stem = p.file_stem().and_then(|n| n.to_str()).unwrap_or("file");
    let ext = p.extension().and_then(|e| e.to_str()).map(|e| format!(".{e}")).unwrap_or_default();
    (1..)
        .map(|n| p.with_file_name(format!("{stem}{suffix}{}{ext}", if n == 1 { String::new() } else { n.to_string() })))
        .find(|c| !c.exists())
        .unwrap()
}

pub const IMAGE_FORMATS: [&str; 7] = ["png", "jpg", "webp", "avif", "heic", "bmp", "tiff"];

pub const DOC_FORMATS: [&str; 16] = [
    "pdf", "docx", "doc", "txt", "rtf", "odt", "html", "xlsx", "xls", "csv", "ods", "pptx", "ppt", "odp", "epub", "fb2",
];

// Per-OS tool names and install locations.
#[cfg(unix)]
mod os {
    pub const TAR: &str = "bsdtar";
    pub const GS: &str = "gs";
    pub const SOFFICE: &[&str] = &["soffice", "libreoffice"];
    pub const ONLYOFFICE: &str = "/opt/onlyoffice/desktopeditors";
    pub const X2T: &str = "/opt/onlyoffice/desktopeditors/converter/x2t";
}
#[cfg(windows)]
mod os {
    pub const TAR: &str = "tar"; // bsdtar ships with Windows 10+
    pub const GS: &str = "gswin64c";
    pub const SOFFICE: &[&str] = &["soffice", r"C:\Program Files\LibreOffice\program\soffice.exe"];
    pub const ONLYOFFICE: &str = r"C:\Program Files\ONLYOFFICE\DesktopEditors";
    pub const X2T: &str = r"C:\Program Files\ONLYOFFICE\DesktopEditors\converter\x2t.exe";
}
use os::X2T;

/// Command that doesn't flash a console window on Windows.
fn cmd(bin: &str) -> Command {
    let mut c = Command::new(bin);
    // Inside an AppImage LD_LIBRARY_PATH points at the bundled Qt libs, which would break host tools like ffmpeg.
    if std::env::var_os("APPIMAGE").is_some() {
        c.env_remove("LD_LIBRARY_PATH");
    }
    #[cfg(windows)]
    std::os::windows::process::CommandExt::creation_flags(&mut c, 0x0800_0000); // CREATE_NO_WINDOW
    c
}

pub const MEDIA_FORMATS: [&str; 12] =
    ["mp4", "mkv", "webm", "mov", "avi", "gif", "mp3", "flac", "wav", "m4a", "ogg", "aac"];

/// ImageMagick with the user's quality for lossy formats.
fn magick(src: &str, out: &str, pre: &[&str]) -> Result<(), String> {
    let q = cfg().quality.to_string();
    let lossy = ["jpg", "jpeg", "webp", "avif", "heic"].contains(&Path::new(out).extension().and_then(|e| e.to_str()).unwrap_or(""));
    let mut a = vec![src];
    a.extend_from_slice(pre);
    if lossy {
        a.extend(["-quality", &q]);
    }
    a.push(out);
    run("magick", &a).map(|_| ())
}

/// Converts `src` to `fmt` next to the source file. Returns the output path.
// ponytail: ImageMagick for images, FFmpeg for audio/video; swap for libvips etc. if speed matters.
pub fn convert(src: &str, fmt: &str) -> Result<String, String> {
    let out = Path::new(src).with_extension(fmt);
    if out == Path::new(src) {
        return Err("source already has this format".into());
    }
    let out = place(out);
    let o = out.display().to_string();
    let sext = Path::new(src).extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
    let is_image = IMAGE_FORMATS.contains(&sext.as_str()) || ["jpeg", "tif", "gif", "heif", "ico", "svg"].contains(&sext.as_str());
    if IMAGE_FORMATS.contains(&fmt) && !is_image {
        ffmpeg(&["-y", "-i", src, "-frames:v", "1", &o], src, &o, None)?; // video -> still frame
    } else if IMAGE_FORMATS.contains(&fmt) || (fmt == "pdf" && is_image) {
        magick(src, &o, &[])?;
    } else if MEDIA_FORMATS.contains(&fmt) || fmt == "opus" {
        ffmpeg(&["-y", "-i", src, &o], src, &o, None)?;
    } else if DOC_FORMATS.contains(&fmt) {
        office(src, &o, fmt)?;
    } else {
        return Err(format!("unsupported format: {fmt}"));
    }
    Ok(o)
}

/// Office documents: LibreOffice and/or OnlyOffice's x2t, per the "office" setting ("auto" tries both).
fn office(src: &str, out: &str, fmt: &str) -> Result<(), String> {
    let pref = cfg().office;
    let mut last = String::from("no office backend found (install LibreOffice or OnlyOffice)");
    if pref != "onlyoffice" {
        // soffice names its result after the source, so convert in a scratch dir and move it to `out`
        let tmp = std::env::temp_dir().join(format!("clementine-office-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&tmp);
        let made = tmp.join(Path::new(src).file_stem().unwrap_or_default()).with_extension(fmt);
        for bin in os::SOFFICE {
            match cmd(bin).args(["--headless", "--convert-to", fmt, "--outdir"]).arg(&tmp).arg(src).output() {
                Ok(r) if r.status.success() && made.exists() => {
                    let moved = std::fs::rename(&made, out).or_else(|_| std::fs::copy(&made, out).map(|_| ()));
                    let _ = std::fs::remove_dir_all(&tmp);
                    return moved.map_err(|e| e.to_string());
                }
                Ok(r) => last = String::from_utf8_lossy(&r.stderr).trim().to_string(),
                Err(_) => {}
            }
        }
        let _ = std::fs::remove_dir_all(&tmp);
    }
    if pref != "libreoffice" && Path::new(X2T).exists() {
        if x2t(src, out).is_ok() {
            return Ok(());
        }
        // x2t only writes OOXML directly for some inputs: hop through docx/xlsx/pptx
        let ext = |p: &str| Path::new(p).extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
        let mid = match ext(src).as_str() {
            "xlsx" | "xls" | "ods" | "csv" => "xlsx",
            "pptx" | "ppt" | "odp" => "pptx",
            _ => "docx",
        };
        if ext(src) != mid && ext(out) != mid {
            let tmp = std::env::temp_dir().join(format!("clementine-{}.{mid}", std::process::id()));
            let tmp_s = tmp.display().to_string();
            let r = x2t(src, &tmp_s).and_then(|_| x2t(&tmp_s, out));
            let _ = std::fs::remove_file(&tmp);
            if r.is_ok() {
                return Ok(());
            }
        }
        return Err(format!("OnlyOffice can't write .{fmt} here; install LibreOffice for it"));
    }
    Err(last)
}

fn x2t(src: &str, out: &str) -> Result<(), String> {
    let fonts = format!("{}/fonts", os::ONLYOFFICE);
    let xml = format!(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><TaskQueueDataConvert><m_sFileFrom>{src}</m_sFileFrom><m_sFileTo>{out}</m_sFileTo><m_sFontDir>{fonts}</m_sFontDir><m_bIsNoBase64>true</m_bIsNoBase64></TaskQueueDataConvert>"
    );
    let cfg = std::env::temp_dir().join(format!("clementine-{}.xml", std::process::id()));
    std::fs::write(&cfg, xml).map_err(|e| e.to_string())?;
    let r = run(X2T, &[cfg.to_str().unwrap()]);
    let _ = std::fs::remove_file(&cfg);
    r.and_then(|_| if Path::new(out).exists() { Ok(()) } else { Err("no output".into()) })
}

/// Puts the file on the clipboard. Linux: URI list via wl-clipboard or xclip. Windows: PowerShell.
fn clip(files: &[std::path::PathBuf]) -> Result<(), String> {
    #[cfg(windows)]
    {
        let list: Vec<String> = files.iter().map(|f| format!("'{}'", f.display().to_string().replace('\'', "''"))).collect();
        let ps = format!("Set-Clipboard -LiteralPath {}", list.join(","));
        return run("powershell", &["-NoProfile", "-Command", &ps]).map(|_| ());
    }
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::process::Stdio;
        let uri: String = files
            .iter()
            .map(|f| format!("file://{}\r\n", f.display().to_string().replace('%', "%25").replace(' ', "%20")))
            .collect();
        let tries: [(&str, &[&str]); 2] = [
            ("wl-copy", &["-t", "text/uri-list"]),
            ("xclip", &["-selection", "clipboard", "-t", "text/uri-list"]),
        ];
        for (bin, args) in tries {
            if let Ok(mut c) = cmd(bin).args(args).stdin(Stdio::piped()).spawn() {
                c.stdin.take().unwrap().write_all(uri.as_bytes()).map_err(|e| e.to_string())?;
                return c.wait().map_err(|e| e.to_string()).and_then(|st| if st.success() { Ok(()) } else { Err(format!("{bin} failed")) });
            }
        }
        Err("install wl-clipboard (Wayland) or xclip (X11) to copy files".into())
    }
}

fn run(bin: &str, args: &[&str]) -> Result<String, String> {
    let r = cmd(bin).args(args).output().map_err(|e| format!("{bin}: {e}"))?;
    if r.status.success() {
        Ok(String::from_utf8_lossy(&r.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&r.stderr).trim().to_string())
    }
}

fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        match (b[i], b.get(i + 1..i + 3).and_then(|h| u8::from_str_radix(std::str::from_utf8(h).ok()?, 16).ok())) {
            (b'%', Some(v)) => { out.push(v); i += 3; }
            (c, _) => { out.push(c); i += 1; }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Files currently on the clipboard (copied in the file manager), existing ones only.
/// Linux: wl-paste, then xclip; Windows: PowerShell.
pub fn clipboard_files() -> Vec<String> {
    #[cfg(windows)]
    let raw = run("powershell", &["-NoProfile", "-Command", "Get-Clipboard -Format FileDropList | ForEach-Object FullName"]).ok();
    #[cfg(unix)]
    let raw = run("wl-paste", &["-t", "text/uri-list"])
        .or_else(|_| run("xclip", &["-selection", "clipboard", "-o", "-t", "text/uri-list"]))
        .ok();
    raw.unwrap_or_default()
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| percent_decode(l.strip_prefix("file://").unwrap_or(l)))
        .filter(|p| Path::new(p).exists())
        .collect()
}

fn duration(src: &str) -> Option<f64> {
    run("ffprobe", &["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", src]).ok()?.parse().ok()
}

/// Cuts `len` seconds (None = to the end) from `start`. Fast mode copies streams, so it starts on a keyframe.
fn cut(src: &str, start: f64, len: Option<f64>, precise: bool, out: &str) -> Result<(), String> {
    let (ss, t) = (start.to_string(), len.map(|l| l.to_string()));
    let mut args = vec!["-y", "-ss", &ss];
    if let Some(t) = &t {
        args.extend(["-t", t]);
    }
    args.extend(["-i", src]);
    if !precise {
        args.extend(["-c", "copy", "-avoid_negative_ts", "make_zero"]);
    }
    args.push(out);
    ffmpeg(&args, src, out, len)
}

/// A clip name as a file name: no path separators or characters Windows forbids, no leading dots.
fn clean_name(n: &str) -> String {
    let n: String = n.chars().filter(|c| !c.is_control() && !"/\\:*?\"<>|".contains(*c)).collect();
    n.trim().trim_start_matches('.').trim().to_string()
}

/// "90", "1:30", "01:02:03.5" -> seconds. Empty = None.
fn parse_time(t: &str) -> Result<Option<f64>, String> {
    let t = t.trim();
    if t.is_empty() {
        return Ok(None);
    }
    let parts: Vec<&str> = t.split(':').collect();
    if parts.len() > 3 {
        return Err("bad time".into());
    }
    parts.iter().try_fold(0.0, |acc, p| p.parse::<f64>().ok().filter(|v| *v >= 0.0 && v.is_finite()).map(|v| acc * 60.0 + v))
        .map(Some)
        .ok_or_else(|| "bad time".into())
}

/// "More actions" menu. Returns a short message for the status line.
pub fn act(src: &str, action: &str) -> Result<String, String> {
    let p = Path::new(src);
    let s = |x: std::path::PathBuf| x.display().to_string();
    match action {
        "hash" => {
            use sha2::{Digest, Sha256};
            use std::io::Read;
            let mut f = std::fs::File::open(p).map_err(|e| e.to_string())?;
            let (mut h, mut buf) = (Sha256::new(), [0u8; 1 << 16]);
            loop {
                match f.read(&mut buf).map_err(|e| e.to_string())? {
                    0 => break,
                    n => h.update(&buf[..n]),
                }
            }
            Ok(h.finalize().iter().map(|b| format!("{b:02x}")).collect())
        }
        "audio" => {
            let out = s(place(p.with_extension("mp3")));
            ffmpeg(&["-y", "-i", src, "-vn", &out], src, &out, None).map(|_| format!("Saved {out}"))
        }
        "archive" => {
            let out = s(place(p.with_extension("zip")));
            let dir = p.parent().map(|d| s(d.to_path_buf())).unwrap_or(".".into());
            let name = p.file_name().and_then(|n| n.to_str()).unwrap_or(src);
            run(os::TAR, &["-a", "-cf", &out, "-C", &dir, name]).map(|_| format!("Saved {out}"))
        }
        "pdf-jpg" | "pdf-png" => {
            let (flag, ext) = if action == "pdf-jpg" { ("-jpeg", "jpg") } else { ("-png", "png") };
            let prefix = s(redirect(p.with_extension("")));
            let jpegopt = format!("quality={}", cfg().quality);
            let mut a = vec![flag, "-r", "150"];
            if ext == "jpg" {
                a.extend(["-jpegopt", &jpegopt]);
            }
            a.extend([src, &prefix]);
            run("pdftoppm", &a).map(|_| format!("Saved {prefix}-*.{ext}"))
        }
        "pdf-txt" => {
            let out = s(place(p.with_extension("txt")));
            run("pdftotext", &[src, &out]).map(|_| format!("Saved {out}"))
        }
        "pdf-split" => {
            let pat = format!("{}-%d.pdf", s(redirect(p.with_extension(""))));
            run("pdfseparate", &[src, &pat]).map(|_| format!("Saved {pat}"))
        }
        "pdf-compress" => {
            let out = s(place(p.with_file_name(format!("{}-small.pdf", p.file_stem().and_then(|n| n.to_str()).unwrap_or("out")))));
            let of = format!("-sOutputFile={out}");
            run(os::GS, &["-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pdfwrite", "-dPDFSETTINGS=/ebook", &of, src])
                .map(|_| format!("Saved {out}"))
        }
        "ar-zip" | "ar-7z" | "ar-tar" | "ar-tgz" | "ar-txz" => {
            let ext = match action {
                "ar-zip" => "zip",
                "ar-7z" => "7z",
                "ar-tar" => "tar",
                "ar-tgz" => "tar.gz",
                _ => "tar.xz",
            };
            // repack: bsdtar reads the entries of `src` via "@src" and writes the new format
            let mut out = place(PathBuf::from(format!("{}.{ext}", s(p.with_extension("")))));
            if out == p {
                out = numbered(&out); // never write over the archive being read
            }
            let out = s(out);
            run(os::TAR, &["-a", "-cf", &out, &format!("@{src}")]).map(|_| format!("Saved {out}"))
        }
        "extract" => {
            let dir = s(place(p.with_extension("")));
            std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
            run(os::TAR, &["-xf", src, "-C", &dir]).map(|_| format!("Extracted to {dir}"))
        }
        "copy-file" => {
            // `src` holds one path per line when several files are selected
            let abs = src.lines().map(std::fs::canonicalize).collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())?;
            clip(&abs).map(|_| "File copied".into())
        }
        "duplicate" => {
            let out = unique(p, "-copy");
            std::fs::copy(p, &out).map(|_| format!("Saved {}", out.display())).map_err(|e| e.to_string())
        }
        a if a.starts_with("resize:") => {
            // "resize:50%" scales; "resize:1920" caps the width (never enlarges)
            let v = &a[7..];
            let (num, pct) = v.strip_suffix('%').map_or((v, false), |n| (n, true));
            let n: u32 = num.parse().map_err(|_| "bad size".to_string())?;
            if !(1..=20000).contains(&n) {
                return Err("bad size".into());
            }
            let (geom, tag) = if pct { (format!("{n}%"), format!("-{n}pct")) } else { (format!("{n}x>"), format!("-{n}px")) };
            let out = unique(p, &tag).display().to_string();
            magick(src, &out, &["-auto-orient", "-resize", &geom]).map(|_| format!("Saved {out}"))
        }
        a if a.starts_with("trim|") => {
            // "trim|start|end|fast" or "...|precise"; times are seconds, m:ss or h:mm:ss, empty end = to the end
            let mut it = a[5..].split('|');
            let (start, end, precise) = (it.next().unwrap_or(""), it.next().unwrap_or(""), it.next() == Some("precise"));
            let start = parse_time(start)?.unwrap_or(0.0);
            let end = parse_time(end)?.or_else(|| duration(src));
            let len = end.map(|e| e - start);
            if len.is_some_and(|l| l <= 0.0) {
                return Err("bad range".into());
            }
            let out = unique(p, "-trim").display().to_string();
            cut(src, start, len, precise, &out).map(|_| format!("Saved {out}"))
        }
        a if a.starts_with("clips|") => {
            // "clips|fast" or "clips|precise", then one "start|end|name" per line; blank lines are skipped
            let (mode, rows) = a[6..].split_once('\n').unwrap_or((&a[6..], ""));
            let total = duration(src);
            let stem = p.file_stem().and_then(|n| n.to_str()).unwrap_or("clip");
            let ext = p.extension().and_then(|e| e.to_str()).unwrap_or("mp4");
            let mut jobs = vec![];
            for (i, row) in rows.lines().enumerate() {
                let mut f = row.splitn(3, '|').map(str::trim);
                let (s0, e0, name) = (f.next().unwrap_or(""), f.next().unwrap_or(""), f.next().unwrap_or(""));
                if s0.is_empty() && e0.is_empty() && name.is_empty() {
                    continue;
                }
                let err = |m: String| format!("clip #{}: {m}", i + 1);
                let start = parse_time(s0).map_err(err)?.unwrap_or(0.0);
                let end = parse_time(e0).map_err(err)?.or(total);
                let len = end.map(|e| e - start);
                if len.is_some_and(|l| l <= 0.0) {
                    return Err(err("bad range".into()));
                }
                let name = clean_name(name);
                jobs.push((start, len, if name.is_empty() { format!("{stem}-clip{}", i + 1) } else { name }));
            }
            if jobs.is_empty() {
                return Err("no clips".into());
            }
            let n = jobs.len();
            let mut dir = String::new();
            for (k, (start, len, name)) in jobs.into_iter().enumerate() {
                if cancelled() {
                    SCALE.with(|s| s.set((0.0, 1.0)));
                    return Err("cancelled".into());
                }
                let out = place(p.with_file_name(format!("{name}.{ext}")));
                dir = out.parent().map(|d| d.display().to_string()).unwrap_or_default();
                SCALE.with(|s| s.set((k as f32 / n as f32, 1.0 / n as f32)));
                let r = cut(src, start, len, mode == "precise", &out.display().to_string());
                SCALE.with(|s| s.set((0.0, 1.0)));
                r?;
            }
            Ok(format!("Saved {n} clips in {dir}"))
        }
        _ => Err("not implemented yet".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_bad_input() {
        assert!(convert("a.png", "exe").is_err());
        assert!(convert("a.png", "png").is_err());
        assert!(convert("/nonexistent.png", "jpg").is_err());
        assert!(act("a.png", "rename").is_err());
    }

    #[test]
    fn media_and_pdf_end_to_end() {
        let d = std::env::temp_dir().join("clementine-test");
        std::fs::create_dir_all(&d).unwrap();
        let (wav, mp4, pdf) = (d.join("s.wav"), d.join("v.mp4"), d.join("p.pdf"));
        run("ffmpeg", &["-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=d=1", wav.to_str().unwrap()]).unwrap();
        run("ffmpeg", &["-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=1:s=64x64", "-f", "lavfi", "-i", "sine=d=1", "-shortest", mp4.to_str().unwrap()]).unwrap();
        run("magick", &["-size", "100x100", "xc:red", pdf.to_str().unwrap()]).unwrap();
        for (src, fmt) in [(&wav, "flac"), (&wav, "opus"), (&mp4, "webm"), (&mp4, "gif"), (&mp4, "mp3"), (&mp4, "png")] {
            assert!(convert(src.to_str().unwrap(), fmt).is_ok(), "{fmt}");
        }
        let png = d.join("i.png");
        run("magick", &["-size", "8x8", "xc:red", png.to_str().unwrap()]).unwrap();
        assert!(convert(png.to_str().unwrap(), "pdf").is_ok(), "png->pdf");
        for a in ["pdf-jpg", "pdf-png", "pdf-txt", "pdf-split", "pdf-compress"] {
            assert!(act(pdf.to_str().unwrap(), a).is_ok(), "{a}");
        }
    }

    #[test]
    fn archives() {
        let d = std::env::temp_dir().join("clementine-test-ar");
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join("a.txt"), "hi").unwrap();
        let zip = d.join("a.zip");
        run(os::TAR, &["-a", "-cf", zip.to_str().unwrap(), "-C", d.to_str().unwrap(), "a.txt"]).unwrap();
        let z = zip.to_str().unwrap();
        for a in ["ar-tar", "ar-tgz", "ar-txz", "ar-7z", "extract"] {
            assert!(act(z, a).is_ok(), "{a}");
        }
        assert!(d.join("a/a.txt").exists() && d.join("a.tar.gz").exists());
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn office_roundtrip() {
        let d = std::env::temp_dir().join("clementine-test-doc");
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join("a.txt"), "hello\n").unwrap();
        let src = d.join("a.txt");
        for fmt in ["docx", "odt", "rtf"] {
            let r = convert(src.to_str().unwrap(), fmt);
            assert!(r.is_ok() && Path::new(&r.unwrap()).exists(), "{fmt}");
        }
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn duplicate_never_overwrites() {
        let d = std::env::temp_dir().join("clementine-test-dup");
        std::fs::create_dir_all(&d).unwrap();
        let f = d.join("a.txt");
        std::fs::write(&f, "x").unwrap();
        act(f.to_str().unwrap(), "duplicate").unwrap();
        act(f.to_str().unwrap(), "duplicate").unwrap();
        assert!(d.join("a-copy.txt").exists() && d.join("a-copy2.txt").exists());
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn progress_cancel_resize() {
        use std::sync::Mutex;
        let d = std::env::temp_dir().join("clementine-test-prog");
        std::fs::create_dir_all(&d).unwrap();
        let mp4 = d.join("v.mp4");
        run("ffmpeg", &["-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=2:s=64x64", mp4.to_str().unwrap()]).unwrap();

        let seen = Arc::new(Mutex::new(Vec::<f32>::new()));
        let cancel = Arc::new(AtomicBool::new(false));
        let s2 = seen.clone();
        set_hook(Some(Hook { progress: Box::new(move |f| s2.lock().unwrap().push(f)), cancel: cancel.clone() }));
        convert(mp4.to_str().unwrap(), "webm").unwrap();
        assert!(seen.lock().unwrap().last().is_some_and(|f| *f > 0.9), "{:?}", seen.lock().unwrap());

        cancel.store(true, Ordering::Relaxed);
        let r = convert(mp4.to_str().unwrap(), "mkv");
        assert_eq!(r, Err("cancelled".into()));
        assert!(!d.join("v.mkv").exists());
        set_hook(None);

        let png = d.join("i.png");
        run("magick", &["-size", "200x100", "xc:red", png.to_str().unwrap()]).unwrap();
        act(png.to_str().unwrap(), "resize:50%").unwrap();
        act(png.to_str().unwrap(), "resize:80").unwrap();
        let dims = |f: &str| run("magick", &["identify", "-format", "%wx%h", d.join(f).to_str().unwrap()]).unwrap();
        assert_eq!(dims("i-50pct.png"), "100x50");
        assert_eq!(dims("i-80px.png"), "80x40");
        act(png.to_str().unwrap(), "resize:5000").unwrap();
        assert_eq!(dims("i-5000px.png"), "200x100"); // never enlarges
        assert!(act(png.to_str().unwrap(), "resize:abc").is_err());
        assert!(act(png.to_str().unwrap(), "resize:0%").is_err());
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn percent_decoding() {
        assert_eq!(percent_decode("/a%20b/%D1%84.txt"), "/a b/ф.txt");
        assert_eq!(percent_decode("100%"), "100%");
    }

    #[test]
    fn times_parse() {
        assert_eq!(parse_time("").unwrap(), None);
        assert_eq!(parse_time("90").unwrap(), Some(90.0));
        assert_eq!(parse_time("1:30").unwrap(), Some(90.0));
        assert_eq!(parse_time("1:02:03.5").unwrap(), Some(3723.5));
        assert!(parse_time("a").is_err() && parse_time("-1").is_err() && parse_time("1:2:3:4").is_err());
    }

    #[test]
    fn trim_and_settings() {
        let d = std::env::temp_dir().join("clementine-test-trim");
        let _ = std::fs::remove_dir_all(&d); // leftovers of a failed run would shift the numbered names
        let out = d.join("out");
        std::fs::create_dir_all(&d).unwrap();
        let mp4 = d.join("v.mp4");
        run("ffmpeg", &["-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=4:s=64x64", "-f", "lavfi", "-i", "sine=d=4", "-g", "25", "-shortest", mp4.to_str().unwrap()]).unwrap();
        let dur = |f: &Path| run("ffprobe", &["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", f.to_str().unwrap()]).unwrap().parse::<f64>().unwrap();

        act(mp4.to_str().unwrap(), "trim|1|3|precise").unwrap();
        assert!((dur(&d.join("v-trim.mp4")) - 2.0).abs() < 0.3);
        act(mp4.to_str().unwrap(), "trim|2||fast").unwrap(); // to the end
        assert!(dur(&d.join("v-trim2.mp4")) < 2.6);
        assert_eq!(act(mp4.to_str().unwrap(), "trim|3|1|fast"), Err("bad range".into()));

        // output folder + keep-both
        use crate::settings::Settings;
        let png = d.join("i.png");
        run("magick", &["-size", "8x8", "xc:red", png.to_str().unwrap()]).unwrap();
        use_settings(Settings { output_dir: out.display().to_string(), ..Default::default() });
        convert(png.to_str().unwrap(), "jpg").unwrap();
        convert(png.to_str().unwrap(), "jpg").unwrap();
        assert!(out.join("i.jpg").exists() && out.join("i-2.jpg").exists() && !d.join("i.jpg").exists());
        use_settings(Settings { output_dir: out.display().to_string(), conflict: "overwrite".into(), ..Default::default() });
        convert(png.to_str().unwrap(), "jpg").unwrap();
        assert!(!out.join("i-3.jpg").exists());
        // quality changes the size of a noisy image
        run("magick", &["-size", "256x256", "plasma:fractal", d.join("n.png").to_str().unwrap()]).unwrap();
        use_settings(Settings { output_dir: out.display().to_string(), quality: 10, ..Default::default() });
        convert(d.join("n.png").to_str().unwrap(), "jpg").unwrap();
        let low = std::fs::metadata(out.join("n.jpg")).unwrap().len();
        use_settings(Settings { output_dir: out.display().to_string(), quality: 100, conflict: "overwrite".into(), ..Default::default() });
        convert(d.join("n.png").to_str().unwrap(), "jpg").unwrap();
        assert!(std::fs::metadata(out.join("n.jpg")).unwrap().len() > low * 2);
        use_settings(Default::default());
        assert!(numbered(Path::new("/x/a.tar.gz")).ends_with("a-2.tar.gz"));
        std::fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn clips() {
        let d = std::env::temp_dir().join("clementine-test-clips");
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        let mp4 = d.join("movie.mp4");
        run("ffmpeg", &["-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=d=6:s=64x64", "-f", "lavfi", "-i", "sine=d=6", "-g", "25", "-shortest", mp4.to_str().unwrap()]).unwrap();
        let src = mp4.to_str().unwrap();
        let dur = |f: &str| duration(d.join(f).to_str().unwrap()).unwrap();

        let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::<f32>::new()));
        let s2 = seen.clone();
        set_hook(Some(Hook { progress: Box::new(move |f| s2.lock().unwrap().push(f)), cancel: Arc::new(AtomicBool::new(false)) }));
        let rows = "clips|precise\n0:00|0:02|intro\n\n 2|5|../we:ird?\n||\n4||";
        let msg = act(src, rows).unwrap();
        set_hook(None);
        assert!(msg.starts_with("Saved 3 clips in "), "{msg}");
        assert!((dur("intro.mp4") - 2.0).abs() < 0.3);
        assert!((dur("weird.mp4") - 3.0).abs() < 0.3); // name cleaned
        assert!((dur("movie-clip5.mp4") - 2.0).abs() < 0.3); // unnamed row 5 (index+1), open end
        let p = seen.lock().unwrap();
        assert!(p.windows(2).all(|w| w[1] >= w[0] - 1e-6) && *p.last().unwrap() > 0.9, "{p:?}");

        act(src, "clips|fast\n1|2|intro").unwrap();
        assert!(d.join("intro-2.mp4").exists()); // name taken -> numbered
        assert_eq!(act(src, "clips|fast\n1|2|a\n5|3|b"), Err("clip #2: bad range".into()));
        assert!(!d.join("a.mp4").exists()); // all rows validated before any file is made
        assert_eq!(act(src, "clips|fast\n x|2|a"), Err("clip #1: bad time".into()));
        assert_eq!(act(src, "clips|fast\n\n|\n"), Err("no clips".into()));
        assert_eq!(clean_name(" ..a/b "), "ab");
        std::fs::remove_dir_all(&d).unwrap();
    }
}
