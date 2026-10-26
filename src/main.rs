#![cfg_attr(windows, windows_subsystem = "windows")]
mod bridge;
mod convert;
mod settings;
mod trigger;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};

fn main() {
    cxx_qt::init_qml_module!("clementine");
    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut e) = engine.as_mut() {
        e.load(&QUrl::from("qrc:/qt/qml/clementine/qml/Main.qml"));
    }
    if let Some(mut a) = app.as_mut() {
        a.exec();
    }
}
