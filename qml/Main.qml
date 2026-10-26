import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtQuick.Dialogs
import clementine

Window {
    id: win
    width: standardMode ? 1000 : 1080
    height: standardMode ? 720 : 640
    minimumWidth: standardMode ? 760 : 1080
    minimumHeight: standardMode ? 560 : 640
    // `--menu` is the radial quick-action mode; `--app` always opens the regular workspace.
    readonly property var args: Qt.application.arguments.slice(1)
    readonly property bool menuMode: args.indexOf("--menu") >= 0
    readonly property bool appMode: args.indexOf("--app") >= 0
    readonly property bool residentMode: args.indexOf("--daemon") >= 0
    // Daemon mode: no file argument on X11 -> stay hidden, pop up at the cursor on Shift + drag.
    // Elsewhere (Wayland, file given) the window is just shown, centred by the compositor.
    readonly property bool daemon: residentMode || (!appMode && (Qt.platform.pluginName === "xcb" || Qt.platform.pluginName === "windows") && args.length === 0
                                   && converter.pointer() !== "")
    // The radial menu is fast while dragging; a regular window is easier to understand for normal launches.
    property bool wheelMode: menuMode
    readonly property bool standardMode: !daemon && !wheelMode
    visible: !daemon
    color: standardMode ? "#16181e" : "transparent"
    flags: standardMode ? Qt.Window : Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | (daemon ? Qt.Tool | (overlay === "" && !ipcShown ? Qt.WindowDoesNotAcceptFocus : 0) : 0)
    title: "Clementine"

    readonly property real cx: standardMode ? width / 2 : 540   // radial-menu values match integration/kde/kwin-script
    readonly property real cy: standardMode ? height / 2 : 320
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
            if (k === "other") return []
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
        "Not implemented yet": "Пока не реализовано", "Copied": "Скопировано",
        "Your files": "Ваши файлы", "Add files": "Добавить файлы", "Paste from clipboard": "Вставить из буфера",
        "Clear": "Очистить", "Drop files here": "Перетащите файлы сюда", "or choose them with the button": "или выберите кнопкой",
        "Choose an action": "Выберите действие", "Pick a file first": "Сначала добавьте файл", "Convert to": "Конвертировать в",
        "More formats": "Больше форматов", "Fewer formats": "Скрыть форматы", "Other actions": "Другие действия",
        "Results": "Результат", "Ready to convert": "Готово к конвертации", "No files were found in the clipboard": "В буфере обмена нет файлов",
        "Save results": "Сохранять результаты", "Advanced settings": "Дополнительные настройки", "Next to each original file": "Рядом с каждым исходным файлом",
        "Processing": "Обработка", "Choose files": "Выберите файлы", "Paste": "Вставить", "Quick wheel": "Быстрое колесо",
        "Open folder": "Открыть папку", "Copy location": "Копировать путь", "Current file": "Текущий файл",
        "Queue": "Очередь", "Recent operations": "Недавние операции", "Repeat": "Повторить",
        "Will be saved to": "Будет сохранён в", "Required tools are missing": "Не хватает нужных программ",
        "Install": "Установите", "to use this action": "для этого действия", "Remove": "Удалить"
    })
    function t(s) { return ru && ruText[s] !== undefined ? ruText[s] : s }

    function localPath(url) {
        var path = decodeURIComponent(url.toString().replace(/^file:\/\//, ""))
        return Qt.platform.os === "windows" && /^\/[A-Za-z]:/.test(path) ? path.slice(1) : path
    }

    // every selected file gets the action; `file` (the first) drives the menu contents
    property var files: args.filter(a => a !== "--menu" && a !== "--app" && a !== "--daemon")
    readonly property string file: files.length > 0 ? files[0] : ""
    property int hovered: -1
    property int menuOf: -1          // which sector's list is shown; kept while the pointer travels to it
    property string status: ""
    property bool busy: false
    property bool showAllFormats: false
    property bool appendFiles: false
    property var plannedEntry: null
    property var queue: []
    property var history: []
    property var toolStatus: ({})
    property string currentFile: ""
    property int clipRows: 4
    property string overlay: ""         // "", "settings" or "trim": a form on top of the wheel
    property string lang: "auto"        // language setting
    property int percent: -1            // -1 = running, progress unknown
    property bool open: false
    property bool dragShown: false      // popped up by a drag that has not been released yet
    property bool ipcShown: false       // request from the resident process: needs keyboard focus
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

    function resultFolder() {
        var configured = converter.setting("output_dir")
        if (configured) return configured
        var slash = Math.max(file.lastIndexOf("/"), file.lastIndexOf("\\"))
        return slash >= 0 ? file.slice(0, slash) : "."
    }
    function resultUrl(path) { return "file://" + (path.startsWith("/") ? "" : "/") + encodeURI(path) }
    function openResultFolder() { if (resultFolder()) Qt.openUrlExternally(resultUrl(resultFolder())) }
    function copyResultFolder() { clipboard.text = resultFolder(); clipboard.selectAll(); clipboard.copy(); status = t("Copied") }
    function previewFor(entry) {
        if (!entry || !file) return ""
        if (entry.kind === "fmt") {
            var name = file.split(/[\\/]/).pop().replace(/\.[^.]*$/, "." + entry.arg)
            return resultFolder() + "/" + name
        }
        return resultFolder()
    }
    function requirementsFor(entry) {
        if (!entry) return []
        if (entry.kind === "fmt") {
            if (kind === "image") return ["magick"]
            if (kind === "video" || kind === "audio") return ["ffmpeg"]
            if (kind === "pdf") return entry.arg === "txt" ? ["pdftotext"] : ["pdftoppm"]
            if (kind === "doc") return ["soffice", "x2t"]
        }
        if (entry.arg && (entry.arg.indexOf("resize") === 0 || entry.arg === "pdf")) return ["magick"]
        if (entry.arg && (entry.arg.indexOf("trim") === 0 || entry.arg.indexOf("clips") === 0 || entry.arg === "audio")) return ["ffmpeg"]
        if (entry.arg && (entry.arg.indexOf("ar-") === 0 || entry.arg === "archive" || entry.arg === "extract")) return ["bsdtar"]
        if (entry.arg && entry.arg.indexOf("pdf-") === 0) return ["pdftoppm"]
        return []
    }
    function missingTools(entry) {
        var required = requirementsFor(entry)
        if (kind === "doc" && required.length === 2) return required.every(name => toolStatus[name] === false) ? required : []
        return required.filter(name => toolStatus[name] === false)
    }
    function removeFile(index) {
        if (busy) return
        files = files.filter((_, i) => i !== index)
        showAllFormats = false
    }
    function updateQueue(path, state, message) {
        queue = queue.map(item => item.file === path ? ({ file: item.file, state: state, message: message || "" }) : item)
    }
    function remember(entry, list) {
        if (entry.kind === "dialog" || entry.kind === "text") return
        history = [{ label: entry.label || entry.arg, kind: entry.kind, arg: entry.arg, files: list.slice(), result: "" }].concat(history).slice(0, 4)
    }
    function repeat(entry) {
        if (busy) return
        files = entry.files.slice()
        pick({ label: entry.label, kind: entry.kind, arg: entry.arg })
    }

    onHoveredChanged: {
        if (hovered >= 0) { closeTimer.stop(); menuOf = vis[hovered].id }
        else closeTimer.restart()
    }
    onMenuOfChanged: if (menuOf >= 0) { panel.idx = vis.findIndex(v => v.id === menuOf); panel.entries = menuItems(menuOf) }
    onFilesChanged: {
        if (menuOf >= 0) panel.entries = menuItems(menuOf)
        plannedEntry = files.length ? (menuItems(0)[0] || menuItems(8)[0]) : null
    }
    Timer { id: closeTimer; interval: 220; onTriggered: if (!panelHover.hovered) win.menuOf = -1 }

    function poll() {
        var request = converter.take_menu_request()
        if (request !== "") {
            files = request.slice(1).split("\n").filter(path => path !== "")
            if (files.length === 0) files = converter.clipboard_files().split("\n").filter(path => path !== "")
            status = ""; menuOf = -1; hovered = -1
            ipcShown = true; dragShown = false; pressing = false
            open = false; visible = true; openTimer.restart(); requestActivate()
            return
        }
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
        if (wheelMode && !menuMode) { wheelMode = false; return }
        if (!daemon) { Qt.quit(); return }
        open = false; visible = false
        files = []; status = ""; menuOf = -1; hovered = -1
        ipcShown = false
        hideTimer.stop(); doneTimer.stop()
        needRelease = true
    }

    Timer { interval: 30; repeat: true; running: win.daemon; onTriggered: win.poll() }
    Timer { id: openTimer; interval: 16; onTriggered: win.open = true }       // lets the pop animation start from the closed state
    Timer { id: hideTimer; interval: 900; onTriggered: win.dismiss() }         // drag released without dropping on us
    Timer { id: doneTimer; interval: 2000; onTriggered: win.dismiss() }        // action finished
    Component.onCompleted: {
        lang = converter.setting("language")
        var tools = converter.available_tools().split("\n")
        var status = ({})
        for (var i = 0; i < tools.length; i++) {
            var pair = tools[i].split("=")
            if (pair.length === 2) status[pair[0]] = pair[1] === "1"
        }
        toolStatus = status
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
        var missing = missingTools(e)
        if (missing.length) { status = t("Required tools are missing") + ": " + missing.join(", "); return }
        doneTimer.stop()
        if (e.kind === "dialog") { openOverlay(e.arg); return }
        if (e.kind === "text") { clipboard.text = e.arg; clipboard.selectAll(); clipboard.copy(); status = t("Copied"); if (daemon) doneTimer.restart(); return }
        // Copy file takes the whole list as one job
        var list = e.arg === "copy-file" ? [files.join("\n")] : files
        queue = list.map(f => ({ file: f, state: "queued", message: "" }))
        currentFile = ""
        remember(e, list)
        busy = true; percent = -1; status = ""
        converter.run(list.join("\n"), e.kind, e.arg)
    }

    Connections {
        target: converter
        function onProgress(p) { win.percent = p }
        function onCurrentFile(path) { win.currentFile = path; win.updateQueue(path, "running", "") }
        function onFileFinished(path, message) { win.updateQueue(path, message.indexOf("✓") === 0 ? "done" : "failed", message) }
        function onFinished(message) {
            win.busy = false; win.status = message
            if (win.history.length) {
                var newest = win.history[0]
                newest.result = message
                win.history = [newest].concat(win.history.slice(1))
            }
            if (win.daemon) doneTimer.restart()
        }
    }

    FileDialog {
        id: fileDialog
        title: win.t("Choose files")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            var selected = selectedFiles.map(win.localPath)
            win.files = win.appendFiles ? win.files.concat(selected) : selected
            win.appendFiles = false
            win.status = ""
        }
    }

    DropArea {
        anchors.fill: parent
        onDropped: (d) => { if (d.hasUrls) { win.files = d.urls.map(win.localPath); win.status = ""; hideTimer.stop() } }
    }

    component AppButton: Rectangle {
        property string label: ""
        property bool primary: false
        property bool compact: false
        signal triggered
        signal highlighted
        height: compact ? 34 : 42
        implicitWidth: textItem.implicitWidth + (compact ? 24 : 32)
        radius: 9
        color: !enabled ? "#252831" : (primary ? "#e08a35" : (hit.containsMouse ? "#363a45" : "#282b34"))
        border.width: activeFocus ? 2 : 1
        border.color: activeFocus ? "#f3b46f" : (primary ? "#e08a35" : "#454a57")
        activeFocusOnTab: enabled
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: textItem
            anchors.centerIn: parent
            text: parent.label
            color: parent.enabled ? "#f5f6f8" : "#858994"
            font.pixelSize: parent.compact ? 14 : 15
            font.weight: parent.primary ? Font.DemiBold : Font.Normal
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.enabled
            cursorShape: Qt.PointingHandCursor
            onEntered: parent.highlighted()
            onClicked: { parent.forceActiveFocus(); parent.triggered() }
        }
        Keys.onReturnPressed: triggered()
        Keys.onSpacePressed: triggered()
    }

    Item {
        id: workspace
        anchors.fill: parent
        anchors.margins: 28
        visible: win.standardMode

        Item {
            id: header
            width: parent.width; height: 52
            Text { text: "Clementine"; color: "#f7f7f8"; font.pixelSize: 27; font.weight: Font.DemiBold }
            Text { anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: 34
                   text: win.t("File conversion without the fuss"); color: "#aeb3bd"; font.pixelSize: 14 }
            AppButton {
                id: settingsButton
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                label: "⚙  " + win.t("Settings"); compact: true
                onTriggered: win.openOverlay("settings")
            }
            AppButton {
                anchors.right: settingsButton.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                label: "◉  " + win.t("Quick wheel"); compact: true
                onTriggered: { win.overlay = ""; win.wheelMode = true; win.open = true }
            }
        }

        Row {
            anchors.top: header.bottom; anchors.topMargin: 24
            width: parent.width; height: parent.height - header.height - 24
            spacing: 20

            Rectangle {
                width: Math.min(330, parent.width * 0.36); height: parent.height; radius: 14
                color: "#20232b"; border.color: "#343945"
                Text { x: 20; y: 20; text: win.t("Your files"); color: "#f4f5f7"; font.pixelSize: 18; font.weight: Font.DemiBold }
                Text {
                    x: 20; y: 48; width: parent.width - 40
                    text: win.files.length === 0 ? win.t("Drop files here") : win.files.length + " " + win.t("files")
                    color: "#aeb3bd"; font.pixelSize: 14
                }

                Rectangle {
                    id: sourceCard
                    x: 20; y: 82; width: parent.width - 40; height: Math.min(250, parent.height - 196); radius: 11
                    color: sourceMouse.containsMouse ? "#292d37" : "#252832"
                    border.width: 1; border.color: sourceMouse.containsMouse ? "#e08a35" : "#414756"
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    Text {
                        visible: win.files.length === 0
                        anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -12
                        text: "＋"; color: "#e9a45e"; font.pixelSize: 34
                    }
                    Text {
                        visible: win.files.length === 0
                        anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 28
                        text: win.t("Drop files here") + "\n" + win.t("or choose them with the button")
                        horizontalAlignment: Text.AlignHCenter; color: "#b9bec8"; font.pixelSize: 14; lineHeight: 1.35
                    }
                    Column {
                        visible: win.files.length > 0
                        x: 14; y: 14; width: parent.width - 28; spacing: 8
                        Repeater {
                            model: Math.min(win.files.length, 5)
                            Rectangle {
                                width: parent.width; height: 33; radius: 7; color: "#1c1f26"
                                Text {
                                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: removeButton.left; anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideMiddle
                                    text: win.files[index].split(/[\\/]/).pop(); color: "#e2e5ea"; font.pixelSize: 14
                                }
                                AppButton {
                                    id: removeButton; anchors.right: parent.right; anchors.rightMargin: 3; anchors.verticalCenter: parent.verticalCenter
                                    label: "×"; compact: true; width: 28; height: 27; enabled: !win.busy
                                    onTriggered: win.removeFile(index)
                                }
                            }
                        }
                        Text {
                            visible: win.files.length > 5; text: "+" + (win.files.length - 5) + " " + win.t("files")
                            color: "#aeb3bd"; font.pixelSize: 13
                        }
                    }
                    MouseArea { id: sourceMouse; anchors.fill: parent; hoverEnabled: true; visible: win.files.length === 0; onClicked: { win.appendFiles = false; fileDialog.open() } }
                }

                Row {
                    x: 20; y: sourceCard.y + sourceCard.height + 16; width: parent.width - 40; spacing: 8
                    AppButton { label: win.t("Add files"); primary: true; width: parent.width * 0.48; onTriggered: { win.appendFiles = win.files.length > 0; fileDialog.open() } }
                    AppButton {
                        label: "⌘ " + win.t("Paste"); width: parent.width * 0.30; enabled: !win.busy
                        onTriggered: {
                            var fromClipboard = converter.clipboard_files().split("\n").filter(l => l !== "")
                            win.files = fromClipboard
                            win.status = fromClipboard.length ? "" : win.t("No files were found in the clipboard")
                        }
                    }
                    AppButton {
                        visible: win.files.length > 0; label: "×"; width: parent.width - x - width; enabled: !win.busy
                        onTriggered: { win.files = []; win.status = ""; win.showAllFormats = false }
                    }
                }
                Item {
                    visible: (win.busy && win.queue.length) || (!win.busy && win.history.length)
                    x: 20; y: sourceCard.y + sourceCard.height + 68; width: parent.width - 40; height: parent.height - y - 12
                    Text {
                        text: win.t(win.busy ? "Queue" : "Recent operations")
                        color: "#c9ced8"; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Column {
                        y: 24; width: parent.width; spacing: 5
                        Repeater {
                            model: win.busy ? win.queue.slice(0, 3) : win.history.slice(0, 3)
                            Rectangle {
                                width: parent.width; height: 29; radius: 6; color: "#1c1f26"
                                readonly property bool queueRow: win.busy
                                Text {
                                    x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - (queueRow ? 16 : 62)
                                    elide: Text.ElideMiddle; font.pixelSize: 12
                                    text: queueRow ? modelData.file.split(/[\\/]/).pop() : modelData.label
                                    color: queueRow && modelData.state === "failed" ? "#ff9c91" : "#d9dde4"
                                }
                                Text {
                                    visible: queueRow; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.state === "running" ? "…" : (modelData.state === "done" ? "✓" : (modelData.state === "failed" ? "!" : "○"))
                                    color: modelData.state === "failed" ? "#ff9c91" : "#e9a45e"; font.pixelSize: 14
                                }
                                AppButton {
                                    visible: !queueRow; anchors.right: parent.right; anchors.rightMargin: 3; anchors.verticalCenter: parent.verticalCenter
                                    label: win.t("Repeat"); compact: true; width: 54; height: 25
                                    onTriggered: win.repeat(modelData)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width - x; height: parent.height; radius: 14
                color: "#20232b"; border.color: "#343945"
                Text { x: 24; y: 20; text: win.t("Choose an action"); color: "#f4f5f7"; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text {
                    x: 24; y: 50; width: parent.width - 48
                    text: win.files.length === 0 ? win.t("Pick a file first") : win.t("Convert to") + " " + (win.files.length > 1 ? win.files.length + " " + win.t("files") : win.file.split(/[\\/]/).pop())
                    color: "#aeb3bd"; elide: Text.ElideMiddle; font.pixelSize: 14
                }

                Item {
                    visible: win.files.length > 0; x: 24; y: 92; width: parent.width - 48; height: parent.height - 206
                    Text { text: win.t("Convert to"); color: "#dce0e6"; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Flow {
                        x: 0; y: 30; width: parent.width; spacing: 8
                        Repeater {
                            model: win.showAllFormats ? win.menuItems(0) : win.menuItems(0).slice(0, 5)
                            AppButton {
                                label: win.t(modelData.label); enabled: !!modelData.kind && !win.busy
                                onHighlighted: win.plannedEntry = modelData
                                onTriggered: win.pick(modelData)
                            }
                        }
                        AppButton {
                            visible: win.menuItems(0).length > 5; compact: true
                            label: win.t(win.showAllFormats ? "Fewer formats" : "More formats")
                            enabled: !win.busy
                            onTriggered: win.showAllFormats = !win.showAllFormats
                        }
                    }
                    Text { y: win.showAllFormats ? 136 : 92; text: win.t("Other actions"); color: "#dce0e6"; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Flow {
                        y: win.showAllFormats ? 166 : 122; width: parent.width; spacing: 8
                        Repeater {
                            model: win.menuItems(8).slice(0, 4)
                            AppButton {
                                label: win.t(modelData.label); compact: true; enabled: !win.busy
                                onHighlighted: win.plannedEntry = modelData
                                onTriggered: win.pick(modelData)
                            }
                        }
                    }
                }

                Text {
                    visible: !!win.plannedEntry && win.files.length > 0
                    x: 24; y: parent.height - 174; width: parent.width - 48; elide: Text.ElideMiddle
                    text: win.t("Will be saved to") + ": " + win.previewFor(win.plannedEntry)
                    color: "#9fa5b0"; font.pixelSize: 13
                }
                Text {
                    readonly property var missing: win.missingTools(win.plannedEntry)
                    visible: missing.length > 0
                    x: 24; y: parent.height - 154; width: parent.width - 48; elide: Text.ElideMiddle
                    text: win.t("Required tools are missing") + ": " + missing.join(", ")
                    color: "#ffb0a7"; font.pixelSize: 13
                }
                Rectangle {
                    x: 24; y: parent.height - 96; width: parent.width - 48; height: 72; radius: 10
                    color: win.busy ? "#292d37" : "#1c1f26"; border.color: "#363b46"
                    Text {
                        x: 14; y: 12; width: parent.width - 150; elide: Text.ElideMiddle
                        text: win.busy ? win.t("Processing") : (win.status || win.t("Ready to convert"))
                        color: win.status.indexOf("✗") === 0 ? "#ff9c91" : "#e0e4ea"; font.pixelSize: 14
                    }
                    Rectangle {
                        visible: win.busy; x: 14; y: 43; width: parent.width - 122; height: 7; radius: 4; color: "#3b404c"; clip: true
                        Rectangle { height: parent.height; radius: parent.radius; color: "#e08a35"; width: win.percent < 0 ? parent.width * 0.35 : parent.width * win.percent / 100 }
                    }
                    Text { visible: win.busy && win.percent >= 0; anchors.right: cancelButton.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: win.percent + "%"; color: "#dce0e6"; font.pixelSize: 14 }
                    AppButton { id: cancelButton; visible: win.busy; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; label: win.t("Cancel"); compact: true; onTriggered: converter.cancel() }
                    AppButton { visible: !win.busy && win.status.indexOf("✓") === 0; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; label: win.t("Open folder"); compact: true; onTriggered: win.openResultFolder() }
                }
                AppButton {
                    x: 24; y: parent.height - 138; label: win.t("Advanced settings"); compact: true; enabled: !win.busy
                    onTriggered: win.openOverlay("settings")
                }
                Text { x: 176; y: parent.height - 128; text: win.t("Save results") + ": " + (converter.setting("output_dir") || win.t("Next to each original file")); color: "#9fa5b0"; font.pixelSize: 13; elide: Text.ElideMiddle; width: parent.width - 200 }
                AppButton {
                    visible: !win.busy && win.status.indexOf("✓") === 0
                    x: 24; y: parent.height - 180; label: win.t("Copy location"); compact: true
                    onTriggered: win.copyResultFolder()
                }
            }
        }
    }

    // wheel: opens with a springy zoom
    Item {
        id: wheel
        visible: !win.standardMode
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
        visible: !win.standardMode && opacity > 0
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
        visible: !win.standardMode
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
        visible: !win.standardMode && !win.busy && win.overlay === ""
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
