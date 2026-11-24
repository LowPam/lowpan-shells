pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * LowPan Shells: animações das janelas no KWin (espelho do NiriAnimationPresets para a galeria).
 * A verdade é o kwinrc ([Plugins] <id>Enabled, [Effect-<id>] duração), lido e gravado por
 * scripts/kwin-animations.py. Estilos prontos só com efeitos nativos; "" = personalizado.
 * Não toca no kdeglobals (a velocidade global do KDE fica de fora).
 */
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/kwin-animations.py")
    readonly property string kwinrc: FileUtils.trimFileProtocol(`${Directories.config}/kwinrc`)

    property bool wanted: false
    property bool loaded: false
    property bool applying: false
    property string error: ""
    property var presets: []
    property var categories: []
    property bool animating: true
    property string activeId: ""
    property string pendingId: ""
    readonly property string defaultId: "smooth"

    readonly property var activePreset: presets.find(p => p.id === activeId) ?? null

    signal applied(string id)

    function ensure(): void {
        if (!CompositorService.isKWin) return
        wanted = true
        refresh()
    }

    function refresh(): void {
        if (!wanted) return
        if (stateProcess.running) refreshDebounce.restart()
        else stateProcess.running = true
    }

    function category(id: string): var {
        return categories.find(c => c.id === id) ?? null
    }

    function _run(args: var, pending: string): bool {
        if (!CompositorService.isKWin || applying) return false
        error = ""
        pendingId = pending
        applying = true
        writeProcess.command = ["python3", root.script].concat(args)
        writeProcess.running = true
        return true
    }

    function apply(id: string): bool {
        if (loaded && !presets.some(p => p.id === id)) return false
        wanted = true
        return _run(["apply-preset", id], id)
    }
    function setEffect(cat: string, effect: string): bool {
        return _run(["set", cat, String(effect || "none")], "")
    }
    function setDuration(cat: string, ms: int): bool {
        return _run(["duration", cat, String(Math.max(0, Math.round(ms)))], "")
    }

    Process {
        id: stateProcess
        command: ["python3", root.script, "state"]
        stdout: StdioCollector {
            id: stateOutput
            onStreamFinished: {
                try {
                    const data = JSON.parse(stateOutput.text)
                    root.presets = data.presets ?? []
                    root.categories = data.categories ?? []
                    root.activeId = data.active ?? ""
                    root.animating = data.animating ?? true
                    root.loaded = true
                } catch (e) {
                    root.error = "Could not read KWin's animations"
                    console.warn("[KWinAnimations] Bad state:", e)
                }
            }
        }
    }

    Process {
        id: writeProcess
        stdout: StdioCollector {
            id: writeOutput
            onStreamFinished: {
                let result = {}
                try { result = JSON.parse(writeOutput.text) } catch (e) {}
                root.applying = false
                if (result.success) {
                    if (root.pendingId.length > 0) {
                        root.activeId = root.pendingId
                        root.applied(root.pendingId)
                    }
                } else {
                    root.error = result.error ?? "KWin did not take the change"
                    console.warn("[KWinAnimations] Write failed:", root.error)
                }
                root.pendingId = ""
                root.refresh()
            }
        }
    }

    Timer {
        id: refreshDebounce
        interval: 300
        onTriggered: root.refresh()
    }

    // A página Animações do KDE também grava aqui: a galeria acompanha.
    FileView {
        path: root.wanted ? root.kwinrc : ""
        watchChanges: true
        printErrors: false
        onFileChanged: refreshDebounce.restart()
    }

    IpcHandler {
        target: "kwinAnimations"

        function list(): string {
            root.ensure()
            if (!root.loaded) return "loading, ask again"
            return root.presets.map(p => (p.id === root.activeId ? "* " : "  ") + p.id + "  " + p.name).join("\n")
                + "\n" + root.categories.map(c => "  " + c.id + ": " + c.active).join("\n")
        }
        function apply(id: string): string {
            return root.apply(id) ? "applying " + id : "unknown or busy: " + id
        }
    }
}
