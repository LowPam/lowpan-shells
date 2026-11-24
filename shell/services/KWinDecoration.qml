pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * LowPan Shells: decoração das janelas no KWin (Breeze) e a sombra dela (Configurações › Janelas › Decoração das
 * janelas). A sombra é a da decoração porque, para o KWin, ela faz parte da janela: acompanha o Wobbly Windows e as
 * animações de abrir/fechar/minimizar. A verdade é o breezerc [Common] e o kwinrc [org.kde.kdecoration2], lidos e
 * gravados por scripts/kwin-decoration.py; a janela do KDE grava o mesmo e a página acompanha (FileView).
 * A cor pode seguir a cena/destaque/realce do shell (Config lowpan.decorationShadowColor), com as cores que o
 * KWinCorners já recebe do IrisStyle (modules/lowpanCorners/KWinCornersFollow.qml). PLANEJAMENTO §21.29.
 */
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/kwin-decoration.py")
    readonly property string kwinrc: FileUtils.trimFileProtocol(`${Directories.config}/kwinrc`)
    readonly property string breezerc: FileUtils.trimFileProtocol(`${Directories.config}/breezerc`)

    property bool wanted: false
    property bool loaded: false
    property bool breeze: false
    property string theme: ""
    property var values: ({})
    property string error: ""

    function ensure(): void {
        if (!CompositorService.isKWin) return
        wanted = true
        refresh()
    }
    property bool following: false
    function follow(): void {
        following = true
        ensure()
    }
    function refresh(): void {
        if (!wanted) return
        if (stateProcess.running) refreshDebounce.restart()
        else stateProcess.running = true
    }
    function value(key: string, fallback: var): var {
        const v = root.values[key]
        return v === undefined ? fallback : v
    }

    // ---------- gravação: pares juntados enquanto o anterior roda ----------
    property var queued: ({})
    function set(key: string, next: var): void {
        const pairs = {}
        pairs[key] = next
        root.setMany(pairs)
    }
    function setMany(pairs: var): void {
        if (!CompositorService.isKWin) return
        const shown = Object.assign({}, root.values)
        const queued = Object.assign({}, root.queued)
        for (const key of Object.keys(pairs)) {
            shown[key] = pairs[key]
            queued[key] = pairs[key]
        }
        root.values = shown
        root.queued = queued
        if (!writeProcess.running) root.flush()
    }
    function flush(): void {
        const keys = Object.keys(root.queued)
        if (keys.length === 0) return
        const args = []
        for (const key of keys) args.push(key, String(root.queued[key]))
        root.queued = ({})
        error = ""
        writeProcess.command = ["python3", root.script, "set"].concat(args)
        writeProcess.running = true
    }
    function useBreeze(): void {
        root.breeze = true
        writeProcess.command = ["python3", root.script, "use-breeze"]
        writeProcess.running = true
    }

    // ---------- cor da sombra ----------
    // Origens: "wallpaper" (cena), "accent", "highlight" (seguem o tema), "#000000"/"#ffffff", "custom" (seletor livre).
    function hex(c: color): string {
        const h = v => ("0" + Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function source(): string {
        Config.revision
        const saved = String(Config.options?.lowpan?.decorationShadowColor ?? "")
        if (saved.length > 0) return saved.startsWith("custom:") ? "custom" : saved
        const now = String(root.value("ShadowColor", "#000000")).toLowerCase()
        return now === "#000000" || now === "#ffffff" ? now : "custom"
    }
    function customColour(): string {
        Config.revision
        const saved = String(Config.options?.lowpan?.decorationShadowColor ?? "")
        if (saved.startsWith("custom:")) return saved.slice(7)
        return String(root.value("ShadowColor", "#000000"))
    }
    function colourOf(src: string): string {
        if (src === "accent") return root.hex(KWinCorners.accent)
        if (src === "highlight") return root.hex(KWinCorners.highlight)
        if (src === "wallpaper") return root.hex(KWinCorners.scene)
        if (src === "custom") return root.customColour()
        return src.startsWith("#") ? src : "#000000"
    }
    function setSource(src: string): void {
        Config.setNestedValue("lowpan.decorationShadowColor", src === "custom" ? "custom:" + root.customColour() : src)
        root.set("ShadowColor", root.colourOf(src))
    }
    function setCustom(c: string): void {
        Config.setNestedValue("lowpan.decorationShadowColor", "custom:" + c)
        root.set("ShadowColor", c)
    }
    // Regrava a cor quando ela segue o tema e mudou de verdade.
    function syncAccent(): void {
        if (!root.loaded || !root.breeze) return
        const src = String(Config.options?.lowpan?.decorationShadowColor ?? "")
        if (src !== "accent" && src !== "highlight" && src !== "wallpaper") return
        const want = root.colourOf(src)
        if (String(root.value("ShadowColor", "")).toLowerCase() !== want) root.set("ShadowColor", want)
    }
    readonly property string accentKey: root.following ? String(KWinCorners.accent) + String(KWinCorners.highlight) + String(KWinCorners.scene) : ""
    onAccentKeyChanged: if (root.following) accentDebounce.restart()
    Timer {
        id: accentDebounce
        interval: 800  // o tema muda em vários passos; uma gravação só no fim
        onTriggered: root.syncAccent()
    }

    Process {
        id: stateProcess
        command: ["python3", root.script, "state"]
        stdout: StdioCollector {
            id: stateOutput
            onStreamFinished: {
                try {
                    const data = JSON.parse(stateOutput.text)
                    root.breeze = data.breeze ?? false
                    root.theme = String(data.theme ?? "")
                    const merged = data.values ?? {}
                    for (const key of Object.keys(root.queued)) merged[key] = root.queued[key]
                    root.values = merged
                    const first = !root.loaded
                    root.loaded = true
                    if (first && root.following) accentDebounce.restart()
                } catch (e) {
                    root.error = "Could not read the window decoration settings"
                    console.warn("[KWinDecoration] Bad state:", e)
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
                if (!result.success) {
                    root.error = result.error ?? "KWin did not take the change"
                    console.warn("[KWinDecoration] Write failed:", root.error)
                }
                if (Object.keys(root.queued).length > 0) root.flush()
                else refreshDebounce.restart()
            }
        }
    }

    Timer {
        id: refreshDebounce
        interval: 300
        onTriggered: root.refresh()
    }

    // A janela do KDE também grava aqui: a página acompanha.
    FileView {
        path: root.wanted ? root.kwinrc : ""
        watchChanges: true
        printErrors: false
        onFileChanged: if (!writeProcess.running) refreshDebounce.restart()
    }
    FileView {
        path: root.wanted ? root.breezerc : ""
        watchChanges: true
        printErrors: false
        onFileChanged: if (!writeProcess.running) refreshDebounce.restart()
    }

    IpcHandler {
        target: "kwinDecoration"

        function status(): string {
            root.ensure()
            return JSON.stringify({ loaded: root.loaded, breeze: root.breeze, theme: root.theme, values: root.values,
                colour: root.source(), following: root.following })
        }
        function set(key: string, value: string): string {
            root.set(key, value)
            return "ok"
        }
        // origem da cor: wallpaper | accent | highlight | #rrggbb | custom:#rrggbb
        function colour(src: string): string {
            if (src.startsWith("custom:")) root.setCustom(src.slice(7))
            else root.setSource(src)
            return "ok"
        }
    }
}
