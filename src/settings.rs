//! User settings, stored as TOML (~/.config/clementine/config.toml, %APPDATA%\Clementine\config.toml).
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct Settings {
    /// Empty = next to the original file.
    pub output_dir: String,
    /// "keep" (numbered copy) or "overwrite".
    pub conflict: String,
    /// JPEG/WebP/AVIF/HEIC quality, 10..=100.
    pub quality: u8,
    /// "auto", "libreoffice" or "onlyoffice".
    pub office: String,
    /// "auto", "en" or "ru".
    pub language: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self { output_dir: String::new(), conflict: "keep".into(), quality: 90, office: "auto".into(), language: "auto".into() }
    }
}

fn path() -> Option<PathBuf> {
    #[cfg(windows)]
    let base = std::env::var_os("APPDATA").map(PathBuf::from)?.join("Clementine");
    #[cfg(unix)]
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?
        .join("clementine");
    Some(base.join("config.toml"))
}

impl Settings {
    /// Missing or unreadable file means defaults; a broken file never blocks conversions.
    pub fn load() -> Self {
        path().and_then(|p| std::fs::read_to_string(p).ok()).and_then(|t| toml::from_str(&t).ok()).unwrap_or_default()
    }

    pub fn save(&self) -> Result<(), String> {
        let p = path().ok_or("no config directory")?;
        std::fs::create_dir_all(p.parent().unwrap()).map_err(|e| e.to_string())?;
        std::fs::write(p, toml::to_string_pretty(self).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
    }

    pub fn get(&self, key: &str) -> String {
        match key {
            "output_dir" => self.output_dir.clone(),
            "conflict" => self.conflict.clone(),
            "quality" => self.quality.to_string(),
            "office" => self.office.clone(),
            "language" => self.language.clone(),
            _ => String::new(),
        }
    }

    pub fn set(&mut self, key: &str, v: &str) -> Result<(), String> {
        let one_of = |opts: &[&str]| if opts.contains(&v) { Ok(v.to_string()) } else { Err(format!("bad value for {key}")) };
        match key {
            "output_dir" => self.output_dir = v.trim().to_string(),
            "conflict" => self.conflict = one_of(&["keep", "overwrite"])?,
            "quality" => {
                self.quality = v.parse().ok().filter(|q| (10..=100).contains(q)).ok_or("bad value for quality")?;
            }
            "office" => self.office = one_of(&["auto", "libreoffice", "onlyoffice"])?,
            "language" => self.language = one_of(&["auto", "en", "ru"])?,
            _ => return Err(format!("unknown setting: {key}")),
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_and_roundtrips() {
        let mut s = Settings::default();
        assert!(s.set("quality", "75").is_ok() && s.quality == 75);
        assert!(s.set("quality", "5").is_err() && s.set("quality", "abc").is_err());
        assert!(s.set("conflict", "maybe").is_err() && s.set("nope", "1").is_err());
        s.set("office", "onlyoffice").unwrap();
        s.set("output_dir", "  /tmp/out ").unwrap();
        let back: Settings = toml::from_str(&toml::to_string_pretty(&s).unwrap()).unwrap();
        assert_eq!(back, s);
        assert_eq!(back.get("output_dir"), "/tmp/out");
        // partial / old files fall back to defaults field by field
        let partial: Settings = toml::from_str("quality = 60").unwrap();
        assert_eq!(partial.conflict, "keep");
    }
}
