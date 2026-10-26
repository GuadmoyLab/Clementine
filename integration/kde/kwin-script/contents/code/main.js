// Wayland clients can't position themselves, so KWin does it: centre the wheel under the cursor.
// WHEEL_* must match cx/cy in qml/Main.qml.
const WHEEL_X = 540, WHEEL_Y = 320;

function isClementine(w) {
    return w.resourceClass === "clementine" || w.desktopFileName === "clementine";
}

function place(w) {
    if (!isClementine(w)) return;
    const p = workspace.cursorPos;
    const area = workspace.clientArea(KWin.PlacementArea, workspace.activeScreen, workspace.currentDesktop);
    const g = w.frameGeometry;
    // keep the whole window on screen; the wheel then may sit off-cursor near edges
    g.x = Math.max(area.x, Math.min(p.x - WHEEL_X, area.x + area.width - g.width));
    g.y = Math.max(area.y, Math.min(p.y - WHEEL_Y, area.y + area.height - g.height));
    w.frameGeometry = g;
    w.noBorder = true;
    w.keepAbove = true;
    w.skipTaskbar = true;
    w.skipPager = true;
    w.skipSwitcher = true;
    console.info("clementine-placer: placed at " + g.x + "," + g.y);
}

workspace.windowAdded.connect(place);
