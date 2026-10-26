use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("clementine").qml_file("qml/Main.qml"))
        .qt_module("Quick")
        .file("src/bridge.rs")
        .build();
}
