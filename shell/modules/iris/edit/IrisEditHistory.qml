pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.iris.settings

// Undo and redo for everything Customize can change, and the one line it says back.
Singleton {
    id: root

    readonly property var trackedPaths: {
        const set = {}
        set["iris.appearance.preset"] = true
        set["iris.appearance.themeId"] = true
        for (const entry of IrisThemes.paths) set[entry.path] = true
        for (const spec of IrisOptions.studio) if (String(spec.path).startsWith("iris.")) set[spec.path] = true
        for (const spec of IrisOptions.behaviour) if (String(spec.path ?? "").startsWith("iris.")) set[spec.path] = true
        return Object.keys(set)
    }
    function fallbackOf(path: string): var {
        const owned = IrisThemes.paths.find(entry => entry.path === path)
        if (owned) return owned.fallback
        return IrisOptions.studio.find(spec => spec.path === path)?.fallback
    }
    function snapshot(): var {
        const values = {}
        for (const path of root.trackedPaths) values[path] = IrisOptions.plain(Config.getNestedValue(path, root.fallbackOf(path)))
        return values
    }

    property var undoStack: []
    property var redoStack: []
    property var lastSnapshot: null
    property string lastKey: ""
    property bool restoring: false
    property string notice: ""

    function say(text: string): void { root.notice = text; noticeTimer.restart() }
    function reset(): void {
        root.lastSnapshot = root.snapshot()
        root.lastKey = JSON.stringify(root.lastSnapshot)
        root.undoStack = []
        root.redoStack = []
    }
    function record(): void {
        const snap = root.snapshot()
        const key = JSON.stringify(snap)
        if (key === root.lastKey) return
        if (root.lastSnapshot && !root.restoring) {
            root.undoStack = root.undoStack.concat([root.lastSnapshot]).slice(-60)
            root.redoStack = []
        }
        root.restoring = false
        root.lastSnapshot = snap
        root.lastKey = key
    }
    function undo(): void {
        if (root.undoStack.length === 0) return
        const previous = root.undoStack[root.undoStack.length - 1]
        root.undoStack = root.undoStack.slice(0, -1)
        root.redoStack = root.redoStack.concat([root.snapshot()])
        root.restoring = true
        Config.setNestedValues(previous)
        root.say(Translation.tr("Undone"))
    }
    function redo(): void {
        if (root.redoStack.length === 0) return
        const next = root.redoStack[root.redoStack.length - 1]
        root.redoStack = root.redoStack.slice(0, -1)
        root.undoStack = root.undoStack.concat([root.snapshot()])
        root.restoring = true
        Config.setNestedValues(next)
        root.say(Translation.tr("Redone"))
    }
    // A theme picked while the look carries tweaks no theme holds (IrisThemes.modified) waits here, so the
    // Themes sheet can offer to save them first instead of overwriting them (LowPan, §21.109).
    property var pendingTheme: null
    function applyTheme(theme: var): void {
        if (IrisThemes.modified) { root.pendingTheme = theme; return }
        root.applyNow(theme)
    }
    function savePending(): void {
        const theme = root.pendingTheme
        root.pendingTheme = null
        if (!theme) return
        IrisThemes.save(Translation.tr("My theme %1").arg(IrisThemes.user.length + 1), "")
        root.applyNow(theme)
    }
    function discardPending(): void {
        const theme = root.pendingTheme
        root.pendingTheme = null
        if (theme) root.applyNow(theme)
    }
    function applyNow(theme: var): void {
        IrisThemes.choose(theme)
        root.say(IrisThemes.coloursOnly ? Translation.tr("Took the colours of %1").arg(theme.name) : Translation.tr("Applied %1").arg(theme.name))
    }

    Timer { id: noticeTimer; interval: 2400; onTriggered: root.notice = "" }
    Timer { id: recordTimer; interval: 320; onTriggered: root.record() }
    Connections {
        target: Config
        enabled: GlobalStates.irisEdit || GlobalStates.irisStudioOpen
        function onRevisionChanged(): void { recordTimer.restart() }
    }
    Connections {
        target: GlobalStates
        function onIrisEditChanged(): void { root.pendingTheme = null; if (GlobalStates.irisEdit) root.reset() }
        function onIrisStudioOpenChanged(): void { if (GlobalStates.irisStudioOpen) root.reset() }
    }
}
