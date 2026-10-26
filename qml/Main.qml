import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import clementine

Window {
    id: win
    width: 1080; height: 640   // wide enough for the list on either side of the wheel
    // `--menu` (global hotkey): show right away at the cursor; with no file arguments use the clipboard's files
    readonly property var args: Qt.application.arguments.slice(1)
    readonly property bool menuMode: args.indexOf("--menu") >= 0
    // Daemon mode: no file argument on X11 -> stay hidden, pop up at the cursor on Shift + drag.
    // Elsewhere (Wayland, file given) the window is just shown, centred by the compositor.
    readonly property bool daemon: (Qt.platform.pluginName === "xcb" || Qt.platform.pluginName === "windows") && args.length === 0
                                   && converter.pointer() !== ""
    visible: !daemon
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | (daemon ? Qt.Tool | (overlay === "" ? Qt.WindowDoesNotAcceptFocus : 0) : 0)
    title: "Clementine"

    readonly property real cx: 540   // keep in sync with WHEEL_X/Y in integration/kde/kwin-script
    readonly property real cy: 320
    readonly property real rIn: 108
    readonly property real rOut: 252
    readonly property color accent: "#e08a35"
    readonly property color accentDark: "#b9631f"
    readonly property var allItems: [
        { id: 0, name: "Convert", icon: "⟳" }, { id: 1, name: "Copy", icon: "⎘" }, { id: 2, name: "Image", icon: "▣" },
        { id: 3, name: "Video", icon: "▶" }, { id: 4, name: "Audio", icon: "♫" }, { id: 5, name: "Document", icon: "≡" },
        { id: 6, name: "Archive", icon: "▤" }, { id: 7, name: "PDF", icon: "⬒" }, { id: 8, name: "More", icon: "•••" }]

    // What the clicked file is decides which sectors exist; "" = nothing dropped yet, show all.
    readonly property var kindExt: ({
        image: ["png", "jpg", "jpeg", "webp", "avif", "heic", "heif", "bmp", "tif", "tiff", "gif", "ico", "svg"],
        video: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg"],
        audio: ["mp3", "flac", "wav", "m4a", "ogg", "aac", "opus", "wma"],
        pdf: ["pdf"],
        doc: ["doc", "docx", "odt", "rtf", "txt", "html", "htm", "epub", "fb2", "md",
              "xls", "xlsx", "ods", "csv", "ppt", "pptx", "odp"],
        archive: ["zip", "7z", "tar", "gz", "tgz", "xz", "txz", "bz2", "zst", "rar"]
    })
    readonly property var sectorIds: ({ "": [0, 1, 2, 3, 4, 5, 6, 7, 8], image: [0, 1, 7, 8], video: [0, 1, 2, 4, 8],
        audio: [0, 1, 8], pdf: [0, 1, 7, 8], doc: [0, 1, 8], archive: [0, 1, 8], other: [1, 8] })

    function extOf(f) { return f.split(".").pop().toLowerCase() }
    function kindOf(f) {
        var e = extOf(f)
        for (var k in kindExt) if (kindExt[k].indexOf(e) >= 0) return k
        return "other"
    }
    function computeKind() {
        if (files.length === 0) return ""
        var k = kindOf(files[0])
        for (var i = 1; i < files.length; i++) if (kindOf(files[i]) !== k) return "other"
        return k
    }
    readonly property string kind: computeKind()
    readonly property var vis: sectorIds[kind].map(i => allItems[i])
    readonly property real segDeg: 360 / vis.length

    function fmts(list) {   // format names -> convert entries, minus the file's own format
        var own = extOf(file).replace("jpeg", "jpg").replace("tif", "tiff")
        return list.filter(f => f.toLowerCase() !== own).map(f => ({ label: f, kind: "fmt", arg: f.toLowerCase() }))
    }
    readonly property var imgFormats: ["JPG", "PNG", "WebP", "AVIF", "HEIC", "BMP", "TIFF"]
    readonly property var vidFormats: ["MP4", "MKV", "WebM", "MOV", "AVI", "GIF"]
    readonly property var audFormats: ["MP3", "FLAC", "WAV", "M4A", "OGG", "AAC", "OPUS"]
    readonly property var arActions: [{ label: "ZIP", kind: "act", arg: "ar-zip" }, { label: "7Z", kind: "act", arg: "ar-7z" },
        { label: "TAR", kind: "act", arg: "ar-tar" }, { label: "TAR.GZ", kind: "act", arg: "ar-tgz" },
        { label: "TAR.XZ", kind: "act", arg: "ar-txz" }, { label: "Extract here", kind: "act", arg: "extract" }]
    readonly property var pdfToOther: [{ label: "Images (JPG)", kind: "act", arg: "pdf-jpg" },
        { label: "Images (PNG)", kind: "act", arg: "pdf-png" }, { label: "To Text (TXT)", kind: "act", arg: "pdf-txt" },
        { label: "To Word (DOCX)" }]
    readonly property var pdfTools: [{ label: "Split PDF", kind: "act", arg: "pdf-split" }, { label: "Merge PDFs" },
        { label: "Compress", kind: "act", arg: "pdf-compress" }]

    function menuItems(id) {
        var k = kind
        if (id === 0) {
            if (k === "video") return fmts(vidFormats)
            if (k === "audio") return fmts(audFormats)
            if (k === "pdf") return pdfToOther
            if (k === "doc") return fmts(docFormats())
            if (k === "archive") return arActions
            return fmts(imgFormats)
        }
        if (id === 1) return [{ label: "Copy file", kind: "act", arg: "copy-file" },
            { label: "Copy path", kind: "text", arg: files.join("\n") },
            { label: "Copy file name", kind: "text", arg: files.map(f => f.split(/[\\/]/).pop()).join("\n") },
            { label: "Copy folder path", kind: "text", arg: files.map(f => f.split(/[\\/]/).slice(0, -1).join("/")).join("\n") },
            { label: "Duplicate", kind: "act", arg: "duplicate" }]
        if (id === 2) return fmts(["PNG", "JPG", "WebP"])
        if (id === 3) return fmts(vidFormats)
        if (id === 4) return fmts(audFormats)
        if (id === 5) return fmts(docFormats())
        if (id === 6) return arActions
        if (id === 7) return k === "image" ? [{ label: "To PDF", kind: "fmt", arg: "pdf" }]
                           : (k === "" ? pdfToOther.concat(pdfTools) : pdfTools)
        var more = []
        if (k === "image" || k === "") more.push(
            { label: "Resize 75%", kind: "act", arg: "resize:75%" }, { label: "Resize 50%", kind: "act", arg: "resize:50%" },
            { label: "Resize 25%", kind: "act", arg: "resize:25%" }, { label: "Width 1920 px", kind: "act", arg: "resize:1920" },
            { label: "Width 1280 px", kind: "act", arg: "resize:1280" }, { label: "Width 800 px", kind: "act", arg: "resize:800" })
        if (k === "video" || k === "") more.push({ label: "Trim video…", kind: "dialog", arg: "trim" }, { label: "Split into clips…", kind: "dialog", arg: "clips" }, { label: "Extract audio…", kind: "act", arg: "audio" })
        more.push({ label: "Create archive…", kind: "act", arg: "archive" }, { label: "Hash (SHA256)…", kind: "act", arg: "hash" })
        return more
    }

    // Document menu follows the source: Word-like, Excel-like or PowerPoint-like
    function docFormats() {
        var ext = file.split(".").pop().toLowerCase()
        if (["xlsx", "xls", "ods", "csv"].indexOf(ext) >= 0) return ["PDF", "XLSX", "XLS", "CSV", "ODS", "HTML"]
        if (["pptx", "ppt", "odp"].indexOf(ext) >= 0) return ["PDF", "PPTX", "PPT", "ODP"]
        return ["PDF", "DOCX", "DOC", "TXT", "RTF", "ODT", "HTML", "EPUB"]
    }

    // UI language follows the system locale; English strings are the keys
    readonly property bool ru: lang === "ru" || (lang === "auto" && Qt.locale().name.substring(0, 2) === "ru")
    readonly property var ruText: ({
        "Convert": "Конвертировать", "Copy": "Копировать", "Image": "Изображение", "Video": "Видео",
        "Audio": "Аудио", "Document": "Документ", "Archive": "Архив", "More": "Ещё",
        "Resize 75%": "Размер 75%", "Resize 50%": "Размер 50%", "Resize 25%": "Размер 25%",
        "Width 1920 px": "Ширина 1920 px", "Width 1280 px": "Ширина 1280 px", "Width 800 px": "Ширина 800 px",
        "Cancel": "Отмена", "Settings": "Настройки", "Output folder": "Папка результата",
        "Next to the original file": "Рядом с исходным файлом", "If the file exists": "Если файл уже есть",
        "Keep both": "Оставить оба", "Overwrite": "Перезаписать", "Image quality": "Качество изображений",
        "Office suite": "Офисный пакет", "Auto": "Авто", "Language": "Язык", "Done": "Готово",
        "Start": "Начало", "Split into clips…": "Нарезка на фрагменты…", "From": "С", "To": "По",
        "Name (optional)": "Название (необязательно)", "Add clip": "Добавить фрагмент", "Split": "Нарезать", "End": "Конец", "to the end": "до конца", "Trim": "Обрезать",
        "Fast (no re-encode)": "Быстро (без перекодирования)", "Precise (re-encode)": "Точно (с перекодированием)", "Trim video…": "Обрезать видео…",
        "Extract audio…": "Извлечь аудио…", "Convert to…": "Конвертировать в…",
        "Create archive…": "Создать архив…", "Hash (SHA256)…": "Хеш (SHA256)…",
        "Copy file": "Копировать файл", "Copy path": "Копировать путь", "Copy file name": "Копировать имя файла",
        "Copy folder path": "Копировать путь к папке", "Duplicate": "Дублировать",
        "Images (JPG)": "Изображения (JPG)", "Images (PNG)": "Изображения (PNG)", "Split PDF": "Разделить PDF",
        "Merge PDFs": "Объединить PDF", "Compress": "Сжать", "To Word (DOCX)": "В Word (DOCX)",
        "To Text (TXT)": "В текст (TXT)", "MP3 (audio)": "MP3 (аудио)", "Extract here": "Распаковать здесь",
        "To PDF": "В PDF", "files": "файлов", "Drop a file": "Перетащите файл", "Drop a file first": "Сначала перетащите файл",
        "Not implemented yet": "Пока не реализовано", "Copied": "Скопировано"
    })
    function t(s) { return ru && ruText[s] !== undefined ? ruText[s] : s }

    // every selected file gets the action; `file` (the first) drives the menu contents
    property var files: args.filter(a => a !== "--menu")
    readonly property string file: files.length > 0 ? files[0] : ""
    property int hovered: -1
    property int menuOf: -1          // which sector's list is shown; kept while the pointer travels to it
    property string status: ""
    property bool busy: false
    property int clipRows: 4
    property string overlay: ""         // "", "settings" or "trim": a form on top of the wheel
    property string lang: "auto"        // language setting
    property int percent: -1            // -1 = running, progress unknown
    property bool open: false
    property bool dragShown: false      // popped up by a drag that has not been released yet
    property bool pressing: false
    property bool needRelease: false    // after dismiss, ignore the still-held button
    property real px0: 0
    property real py0: 0

    Converter { id: converter }
    TextEdit { id: clipboard; visible: false }   // Qt's only clipboard API in QML

    function sector(x, y) {
        var dx = x - cx, dy = y - cy, d = Math.hypot(dx, dy)
        if (d < rIn || d > rOut) return -1
        var a = Math.atan2(dy, dx) * 180 / Math.PI + 90 + segDeg / 2   // first sector (Convert/Copy) is centred at the top
        return Math.floor(((a % 360) + 360) % 360 / segDeg)
    }

    onHoveredChanged: {
        if (hovered >= 0) { closeTimer.stop(); menuOf = vis[hovered].id }
        else closeTimer.restart()
    }
    onMenuOfChanged: if (menuOf >= 0) { panel.idx = vis.findIndex(v => v.id === menuOf); panel.entries = menuItems(menuOf) }
    onFilesChanged: if (menuOf >= 0) panel.entries = menuItems(menuOf)
    Timer { id: closeTimer; interval: 220; onTriggered: if (!panelHover.hovered) win.menuOf = -1 }

    function poll() {
        var s = converter.pointer().split(",").map(Number)
        var down = s[2] === 1 && s[3] === 1
        if (visible) {
            if (!down && dragShown) { dragShown = false; if (!file) hideTimer.restart() }
            return
        }
        if (!down) { pressing = false; needRelease = false; return }
        if (needRelease) return
        if (!pressing) { pressing = true; px0 = s[0]; py0 = s[1]; return }
        if (Math.hypot(s[0] - px0, s[1] - py0) > 12) popup(s[0], s[1])
    }

    function popup(x, y) {
        var r = Screen.devicePixelRatio     // pointer is in device pixels, windows in logical ones
        win.x = x / r - cx; win.y = y / r - cy
        open = false; visible = true; dragShown = true; pressing = false
        openTimer.restart()
    }

    function dismiss() {
        if (busy) return
        if (!daemon) { Qt.quit(); return }
        open = false; visible = false
        files = []; status = ""; menuOf = -1; hovered = -1
        hideTimer.stop(); doneTimer.stop()
        needRelease = true
    }

    Timer { interval: 30; repeat: true; running: win.daemon; onTriggered: win.poll() }
    Timer { id: openTimer; interval: 16; onTriggered: win.open = true }       // lets the pop animation start from the closed state
    Timer { id: hideTimer; interval: 900; onTriggered: win.dismiss() }         // drag released without dropping on us
    Timer { id: doneTimer; interval: 2000; onTriggered: win.dismiss() }        // action finished
    Component.onCompleted: {
        lang = converter.setting("language")
        if (menuMode && files.length === 0) files = converter.clipboard_files().split("\n").filter(l => l !== "")
        if (menuMode && (Qt.platform.pluginName === "xcb" || Qt.platform.pluginName === "windows")) {
            var s = converter.pointer().split(","), r = Screen.devicePixelRatio   // Wayland: the KWin script places us
            if (s.length === 4) { x = s[0] / r - cx; y = s[1] / r - cy }
        }
        if (!daemon) open = true
    }

    function openOverlay(name) {
        overlay = name
        requestActivate()
if (name === "trim") trimStart.input.forceActiveFocus()
        else if (name === "clips") clipRep.itemAt(0).from.input.forceActiveFocus()
        else outDir.input.forceActiveFocus()
    }

    function applyTrim() {
        var mode = precise.on ? "precise" : "fast"
        overlay = ""
        pick({ kind: "act", arg: "trim|" + trimStart.text + "|" + trimEnd.text + "|" + mode })
    }

    // One "start|end|name" line per row; the core makes every clip in one job
    function applyClips() {
        var rows = []
        for (var i = 0; i < clipRows; i++) {
            var r = clipRep.itemAt(i)
            rows.push(r.from.text.trim() + "|" + r.to.text.trim() + "|" + r.label.text.replace(/[\r\n]/g, " ").trim())
        }
        overlay = ""
        pick({ kind: "act", arg: "clips|" + (clipPrecise.on ? "precise" : "fast") + "\n" + rows.join("\n") })
    }

    // Everything but the clipboard text runs on a worker thread; progress/finished come back as signals.
    function pick(e) {
        if (busy) return
        if (!e.kind) { status = t("Not implemented yet"); return }
        if (!file) { status = t("Drop a file first"); return }
        doneTimer.stop()
        if (e.kind === "dialog") { openOverlay(e.arg); return }
        if (e.kind === "text") { clipboard.text = e.arg; clipboard.selectAll(); clipboard.copy(); status = t("Copied"); if (daemon) doneTimer.restart(); return }
        // Copy file takes the whole list as one job
        var list = e.arg === "copy-file" ? [files.join("\n")] : files
        busy = true; percent = -1; status = ""
        converter.run(list.join("\n"), e.kind, e.arg)
    }

    Connections {
        target: converter
        function onProgress(p) { win.percent = p }
        function onFinished(message) {
            win.busy = false; win.status = message
            if (win.daemon) doneTimer.restart()
        }
    }

    DropArea {
        anchors.fill: parent
        onDropped: (d) => { if (d.hasUrls) { win.files = d.urls.map(u => decodeURIComponent(u.toString())); win.status = ""; hideTimer.stop() } }
    }

    // wheel: opens with a springy zoom
    Item {
        id: wheel
        x: 0; y: 0; width: win.width; height: win.height
        transformOrigin: Item.Center
        scale: win.open ? 1 : 0.5; opacity: win.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        Behavior on opacity { NumberAnimation { duration: 220 } }

        Rectangle {   // backdrop disc
            x: win.cx - 266; y: win.cy - 266; width: 532; height: 532; radius: 266
            color: "#cc14161b"; border.color: "#33ffffff"; border.width: 1
        }

        Repeater {
            model: win.vis
            Item {
                id: seg
                readonly property bool hot: index === win.hovered
                readonly property real a0: index * win.segDeg - 90 - win.segDeg / 2   // sector start, degrees
                readonly property real mid: (a0 + win.segDeg / 2) * Math.PI / 180
                readonly property bool primary: modelData.id === 0
                x: hot ? 7 * Math.cos(mid) : 0
                y: hot ? 7 * Math.sin(mid) : 0
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                Shape {
                    layer.enabled: true; layer.samples: 4
                    ShapePath {
                        strokeColor: "#18ffffff"; strokeWidth: 1
                        fillGradient: LinearGradient {
                            x1: win.cx + 250 * Math.cos(seg.mid); y1: win.cy + 250 * Math.sin(seg.mid)
                            x2: win.cx + 100 * Math.cos(seg.mid); y2: win.cy + 100 * Math.sin(seg.mid)
                            GradientStop { position: 0; color: seg.hot ? "#f0a050" : (primary ? "#d37a2a" : "#3a3d45") }
                            GradientStop { position: 1; color: seg.hot ? win.accentDark : (primary ? "#9c5519" : "#25272d") }
                        }
                        startX: win.cx + win.rOut * Math.cos((seg.a0 + 1.5) * Math.PI / 180)
                        startY: win.cy + win.rOut * Math.sin((seg.a0 + 1.5) * Math.PI / 180)
                        PathAngleArc {
                            centerX: win.cx; centerY: win.cy; radiusX: win.rOut; radiusY: win.rOut
                            startAngle: seg.a0 + 1.5; sweepAngle: win.segDeg - 3
                        }
                        PathAngleArc {
                            moveToStart: false
                            centerX: win.cx; centerY: win.cy; radiusX: win.rIn; radiusY: win.rIn
                            startAngle: seg.a0 + win.segDeg - 1.5; sweepAngle: -(win.segDeg - 3)
                        }
                    }
                }
                Column {
                    x: win.cx + 180 * Math.cos(seg.mid) - width / 2
                    y: win.cy + 180 * Math.sin(seg.mid) - height / 2
                    spacing: 2
                    scale: seg.hot ? 1.15 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; font.pixelSize: 26
                           color: seg.hot || seg.primary ? "white" : "#f2b378" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: win.t(modelData.name); font.pixelSize: 15
                           color: "white"; opacity: seg.hot || seg.primary ? 1 : 0.75 }
                }
            }
        }

        Rectangle {   // centre disc
            x: win.cx - 96; y: win.cy - 96; width: 192; height: 192; radius: 96
            color: "#e6101216"; border.color: "#44ffffff"
            Column {
                anchors.centerIn: parent; spacing: 8; width: parent.width - 30
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "🗎"; font.pixelSize: 54; color: "#dfe6f2" }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle; color: "white"; font.pixelSize: 17
                    text: win.files.length > 1 ? win.files.length + " " + win.t("files")
                          : (win.file ? win.file.split(/[\\/]/).pop() : win.t("Drop a file"))
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: (m) => win.hovered = win.sector(m.x, m.y)
            onExited: win.hovered = -1
            onClicked: (m) => { if (Math.hypot(m.x - win.cx, m.y - win.cy) > 270) win.dismiss() }
        }
    }

    // format / actions list: opens beside the hovered sector, on whichever side it is on
    Rectangle {
        id: panel
        property int idx: 0
        property var entries: []
        readonly property bool shown: win.menuOf >= 0
        readonly property real mid: (idx * win.segDeg - 90) * Math.PI / 180
        readonly property bool atRight: Math.cos(mid) >= -0.001
        readonly property real topY: Math.max(8, Math.min(win.height - 8 - height, win.cy + 215 * Math.sin(mid) - height / 2))
        // keep clear of the wheel: half-width of the circle across the rows the list occupies
        readonly property real gap: (topY <= win.cy && topY + height >= win.cy) ? 0
                                    : Math.min(Math.abs(topY - win.cy), Math.abs(topY + height - win.cy))
        readonly property real reach: Math.sqrt(Math.max(0, Math.pow(win.rOut + 14, 2) - gap * gap))
        x: (atRight ? win.cx + reach : win.cx - reach - width) + (shown ? 0 : (atRight ? -20 : 20))
        y: topY
        width: 230; height: col.height + 20; radius: 14
        color: "#f0181a20"; border.color: "#33ffffff"
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        HoverHandler { id: panelHover; onHoveredChanged: if (hovered) closeTimer.stop(); else closeTimer.restart() }

        Column {
            id: col
            x: 10; y: 10; spacing: 3
            Repeater {
                model: panel.entries
                Rectangle {
                    width: 210; height: 40; radius: 9
                    color: hit.containsMouse ? win.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }
                    Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: win.t(modelData.label)
                           color: "white"; font.pixelSize: 16; opacity: modelData.kind ? 1 : 0.55 }
                    MouseArea { id: hit; anchors.fill: parent; hoverEnabled: true; onClicked: win.pick(modelData) }
                }
            }
        }
    }

    Item {   // progress bar while a job runs, result text afterwards
        x: win.cx - 280; y: win.cy + win.rOut + 14; width: 560; height: 40
        Rectangle {
            id: bar
            visible: win.busy
            x: 40; y: 8; width: 440; height: 8; radius: 4; color: "#44ffffff"; clip: true
            Rectangle {
                id: fill
                height: parent.height; radius: 4; color: win.accent
                width: win.percent >= 0 ? parent.width * win.percent / 100 : parent.width * 0.3
                Behavior on width { enabled: win.percent >= 0; NumberAnimation { duration: 180 } }
                SequentialAnimation on x {   // sweeps back and forth while the progress is unknown
                    running: win.busy && win.percent < 0; loops: Animation.Infinite
                    NumberAnimation { from: 0; to: bar.width * 0.7; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: bar.width * 0.7; to: 0; duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }
        Text {   // cancel
            visible: win.busy
            x: 490; y: 0; text: "✕ " + win.t("Cancel"); color: "white"; font.pixelSize: 14
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: converter.cancel() }
        }
        Text {
            visible: win.busy && win.percent >= 0
            x: 0; y: 0; width: 36; text: win.percent + "%"; color: "white"; font.pixelSize: 12
        }
        Text {
            visible: !win.busy
            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle
            color: "white"; font.pixelSize: 15; text: win.status
        }
    }


    // ---- gear: opens the settings form
    Rectangle {
        visible: !win.busy && win.overlay === ""
        x: win.cx + 205 - width / 2; y: win.cy + 205 - height / 2; width: 34; height: 34; radius: 17
        color: gear.containsMouse ? win.accent : "#cc14161b"; border.color: "#44ffffff"
        opacity: win.open ? 1 : 0
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: "⚙"; color: "white"; font.pixelSize: 18 }
        MouseArea { id: gear; anchors.fill: parent; hoverEnabled: true; onClicked: win.openOverlay("settings") }
    }

    // ---- overlay forms
    component Chip: Rectangle {   // click-to-cycle value / button
        property alias text: lbl.text
        property bool primary: false
        signal clicked
        implicitWidth: lbl.implicitWidth + 28; height: 34; radius: 8
        color: primary || ma.containsMouse ? win.accent : "#33ffffff"
        Behavior on color { ColorAnimation { duration: 110 } }
        Text { id: lbl; anchors.centerIn: parent; color: "white"; font.pixelSize: 15 }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
    }
    component Field: Rectangle {  // single-line text input with a placeholder
        property alias text: input.text
        property string hint: ""
        property alias input: input
        signal accepted
        height: 34; radius: 8; color: "#22ffffff"; border.color: input.activeFocus ? win.accent : "#33ffffff"
        TextInput {
            id: input
            anchors.fill: parent; anchors.margins: 8; verticalAlignment: TextInput.AlignVCenter
            color: "white"; font.pixelSize: 15; clip: true; selectByMouse: true
            onAccepted: parent.accepted()
        }
        Text { x: 8; anchors.verticalCenter: parent.verticalCenter; visible: input.text === ""; text: parent.hint
               color: "#88ffffff"; font.pixelSize: 15 }
    }

    Rectangle {   // dim + click-away
        anchors.fill: parent
        visible: win.overlay !== ""
        color: "#88000000"
        MouseArea { anchors.fill: parent; onClicked: win.overlay = "" }
    }

    Rectangle {   // settings
        id: settingsCard
        visible: win.overlay === "settings"
        x: win.cx - width / 2; y: win.cy - height / 2; width: 600; height: 430; radius: 16
        color: "#f2181a20"; border.color: "#44ffffff"
        MouseArea { anchors.fill: parent }
        onVisibleChanged: if (visible) {
            outDir.text = converter.setting("output_dir")
            conflictChip.value = converter.setting("conflict")
            qualityChip.value = parseInt(converter.setting("quality"))
            officeChip.value = converter.setting("office")
            langChip.value = converter.setting("language")
        } else if (outDir.text !== converter.setting("output_dir")) converter.set_setting("output_dir", outDir.text)

        Text { x: 28; y: 22; text: win.t("Settings"); color: "white"; font.pixelSize: 22; font.bold: true }
        Column {
            x: 28; y: 70; width: parent.width - 56; spacing: 14
            Item {
                width: parent.width; height: 34
                Text { text: win.t("Output folder"); color: "white"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                Field {
                    id: outDir
                    x: 200; width: parent.width - 200
                    hint: win.t("Next to the original file")
                    onAccepted: converter.set_setting("output_dir", text)
                }
            }
            Item {
                width: parent.width; height: 34
                Text { text: win.t("If the file exists"); color: "white"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                Chip {
                    id: conflictChip
                    property string value: "keep"
                    x: 200; text: win.t(value === "keep" ? "Keep both" : "Overwrite")
                    onClicked: { value = value === "keep" ? "overwrite" : "keep"; converter.set_setting("conflict", value) }
                }
            }
            Item {
                width: parent.width; height: 34
                Text { text: win.t("Image quality"); color: "white"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    x: 200; spacing: 8
                    Chip { text: "−"; onClicked: qualityChip.set(qualityChip.value - 5) }
                    Chip {
                        id: qualityChip
                        property int value: 90
                        function set(v) { value = Math.max(10, Math.min(100, v)); converter.set_setting("quality", String(value)) }
                        text: value; width: 64
                    }
                    Chip { text: "+"; onClicked: qualityChip.set(qualityChip.value + 5) }
                }
            }
            Item {
                width: parent.width; height: 34
                Text { text: win.t("Office suite"); color: "white"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                Chip {
                    id: officeChip
                    property string value: "auto"
                    readonly property var order: ["auto", "libreoffice", "onlyoffice"]
                    x: 200; text: value === "auto" ? win.t("Auto") : (value === "libreoffice" ? "LibreOffice" : "OnlyOffice")
                    onClicked: { value = order[(order.indexOf(value) + 1) % 3]; converter.set_setting("office", value) }
                }
            }
            Item {
                width: parent.width; height: 34
                Text { text: win.t("Language"); color: "white"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                Chip {
                    id: langChip
                    property string value: "auto"
                    readonly property var order: ["auto", "en", "ru"]
                    x: 200; text: value === "auto" ? win.t("Auto") : (value === "en" ? "English" : "Русский")
                    onClicked: { value = order[(order.indexOf(value) + 1) % 3]; converter.set_setting("language", value); win.lang = value }
                }
            }
        }
        Chip { primary: true; x: parent.width - width - 28; y: parent.height - height - 24; text: win.t("Done"); onClicked: win.overlay = "" }
    }

    Rectangle {   // trim video
        visible: win.overlay === "trim"
        x: win.cx - width / 2; y: win.cy - height / 2; width: 520; height: 330; radius: 16
        color: "#f2181a20"; border.color: "#44ffffff"
        MouseArea { anchors.fill: parent }
        Text { x: 28; y: 22; text: win.t("Trim video…").replace("…", ""); color: "white"; font.pixelSize: 22; font.bold: true }
        Column {
            x: 28; y: 70; width: parent.width - 56; spacing: 14
            Item {
                width: parent.width; height: 34
                Text { text: win.t("Start"); color: "white"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                Field { id: trimStart; x: 150; width: 180; hint: "0:00"; onAccepted: trimEnd.input.forceActiveFocus() }
            }
            Item {
                width: parent.width; height: 34
                Text { text: win.t("End"); color: "white"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
                Field { id: trimEnd; x: 150; width: 180; hint: win.t("to the end"); onAccepted: win.applyTrim() }
            }
            Item {
                width: parent.width; height: 34
                Chip {
                    id: precise
                    property bool on: false
                    text: win.t(on ? "Precise (re-encode)" : "Fast (no re-encode)")
                    onClicked: on = !on
                }
            }
            Text { text: "90  ·  1:30  ·  0:01:30.5"; color: "#88ffffff"; font.pixelSize: 13 }
        }
        Row {
            x: parent.width - width - 28; y: parent.height - 58; spacing: 10
            Chip { text: win.t("Cancel"); onClicked: win.overlay = "" }
            Chip { primary: true; text: win.t("Trim"); onClicked: win.applyTrim() }
        }
    }

    Rectangle {   // split into clips: several "from - to - name" rows at once
        visible: win.overlay === "clips"
        x: win.cx - width / 2; y: win.cy - height / 2; width: 640; height: 196 + win.clipRows * 44; radius: 16
        color: "#f2181a20"; border.color: "#44ffffff"
        MouseArea { anchors.fill: parent }
        Text { x: 28; y: 22; text: win.t("Split into clips…").replace("…", ""); color: "white"; font.pixelSize: 22; font.bold: true }
        Row {
            x: 56; y: 64; spacing: 10
            Text { width: 110; text: win.t("From"); color: "#aaffffff"; font.pixelSize: 13 }
            Text { width: 110; text: win.t("To"); color: "#aaffffff"; font.pixelSize: 13 }
            Text { text: win.t("Name (optional)"); color: "#aaffffff"; font.pixelSize: 13 }
        }
        Column {
            x: 28; y: 88; width: parent.width - 56; spacing: 10
            Repeater {
                id: clipRep
                model: win.clipRows
                Item {
                    id: crow
                    width: parent.width; height: 34
                    property alias from: cf1
                    property alias to: cf2
                    property alias label: cf3
                    Text { width: 22; anchors.verticalCenter: parent.verticalCenter; text: index + 1; color: "#88ffffff"; font.pixelSize: 14 }
                    Field { id: cf1; x: 28; width: 110; hint: "0:00"; onAccepted: cf2.input.forceActiveFocus() }
                    Field { id: cf2; x: 148; width: 110; hint: win.t("to the end"); onAccepted: cf3.input.forceActiveFocus() }
                    Field {
                        id: cf3; x: 268; width: parent.width - 268; hint: win.t("Name (optional)")
                        onAccepted: { var n = clipRep.itemAt(index + 1); if (n) n.from.input.forceActiveFocus(); else win.applyClips() }
                    }
                }
            }
        }
        Row {
            x: 28; y: parent.height - 58; spacing: 10
            Chip { text: "+ " + win.t("Add clip"); visible: win.clipRows < 8; onClicked: win.clipRows++ }
            Chip {
                id: clipPrecise
                property bool on: false
                text: win.t(on ? "Precise (re-encode)" : "Fast (no re-encode)")
                onClicked: on = !on
            }
        }
        Row {
            x: parent.width - width - 28; y: parent.height - 58; spacing: 10
            Chip { text: win.t("Cancel"); onClicked: win.overlay = "" }
            Chip { primary: true; text: win.t("Split"); onClicked: win.applyClips() }
        }
    }

    // Popup behaviour when launched with a file: closes when it loses focus
    property bool wasActive: false
    onActiveChanged: { if (active) wasActive = true; else if (wasActive && !daemon) dismiss() }

    Shortcut { sequence: "Escape"; onActivated: win.overlay !== "" ? win.overlay = "" : (win.busy ? converter.cancel() : win.dismiss()) }
}
