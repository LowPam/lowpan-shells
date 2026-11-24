pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * LowPan Shells: cantos arredondados das janelas no KWin (nosso Rounded Corners, kwin4_effect_lowpancorners).
 * É o equivalente ao geometry-corner-radius/clip-to-geometry que o iNiR põe na config do Niri.
 * A verdade é o kwinrc [LowPan-Round-Corners], lido e gravado por scripts/kwin-corners.py; a janela do KDE grava o mesmo
 * e a página acompanha (FileView). As cores podem seguir o destaque/realce do shell (Config lowpan.cornerColors):
 * follow() mantém isso vivo com as Configurações fechadas (modules/lowpan/KWinCornersFollow.qml, carregado pelo shell.qml
 * só no KWin, liga e entrega as cores do IrisStyle).
 */
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/kwin-corners.py")
    readonly property string kwinrc: FileUtils.trimFileProtocol(`${Directories.config}/kwinrc`)

    property bool wanted: false
    property bool loaded: false
    property bool installed: false
    property bool enabled: false
    property var values: ({})
    property string error: ""

    // Cada cor: a chave da cor e, quando o efeito aceita paleta do KDE, as chaves da paleta (papel 11 = sombra,
    // 12 = destaque, como os padrões do efeito). Os segundos tons do degradê só aceitam cor própria.
    readonly property var slots: ({
        shadow: { color: "ShadowColor", usePalette: "ActiveShadowUsePalette", useCustom: "ActiveShadowUseCustom", palette: "ActiveShadowPalette", role: 11 },
        inactiveShadow: { color: "InactiveShadowColor", usePalette: "InactiveShadowUsePalette", useCustom: "InactiveShadowUseCustom", palette: "InactiveShadowPalette", role: 11 },
        outline: { color: "OutlineColor", usePalette: "ActiveOutlineUsePalette", useCustom: "ActiveOutlineUseCustom", palette: "ActiveOutlinePalette", role: 12 },
        inactiveOutline: { color: "InactiveOutlineColor", usePalette: "InactiveOutlineUsePalette", useCustom: "InactiveOutlineUseCustom", palette: "InactiveOutlinePalette", role: 12 },
        secondOutline: { color: "SecondOutlineColor", usePalette: "ActiveSecondOutlineUsePalette", useCustom: "ActiveSecondOutlineUseCustom", palette: "ActiveSecondOutlinePalette", role: 12 },
        inactiveSecondOutline: { color: "InactiveSecondOutlineColor", usePalette: "InactiveSecondOutlineUsePalette", useCustom: "InactiveSecondOutlineUseCustom", palette: "InactiveSecondOutlinePalette", role: 12 },
        outerOutline: { color: "OuterOutlineColor", usePalette: "ActiveOuterOutlineUsePalette", useCustom: "ActiveOuterOutlineUseCustom", palette: "ActiveOuterOutlinePalette", role: 12 },
        inactiveOuterOutline: { color: "InactiveOuterOutlineColor", usePalette: "InactiveOuterOutlineUsePalette", useCustom: "InactiveOuterOutlineUseCustom", palette: "InactiveOuterOutlinePalette", role: 12 },
        outline2: { color: "OutlineColor2" },
        inactiveOutline2: { color: "InactiveOutlineColor2" },
        secondOutline2: { color: "SecondOutlineColor2" },
        inactiveSecondOutline2: { color: "InactiveSecondOutlineColor2" },
        outerOutline2: { color: "OuterOutlineColor2" },
        inactiveOuterOutline2: { color: "InactiveOuterOutlineColor2" }
    })

    // A paleta do KDE que o efeito usa (o shell roda com o tema de plataforma do KDE): só para as amostras.
    SystemPalette { id: kdeActive; colorGroup: SystemPalette.Active }
    SystemPalette { id: kdeInactive; colorGroup: SystemPalette.Inactive }
    function kdeColour(slot: string): color {
        const pal = slot.startsWith("inactive") ? kdeInactive : kdeActive
        return (root.slots[slot]?.role ?? 12) === 11 ? pal.shadow : pal.highlight
    }

    function ensure(): void {
        if (!CompositorService.isKWin) return
        wanted = true
        refresh()
    }
    // Com o shell aberto (não só as Configurações): as cores que seguem o destaque acompanham o tema.
    // Destaque e realce do shell, entregues por modules/lowpan/KWinCornersFollow.qml (o serviço não importa o IrisStyle).
    property color accent: "#a8c7fa"
    property color highlight: "#ff9f0a"
    // "Cena" (origem "wallpaper"): a luz do papel de parede, a mesma cor da borda das superfícies do shell
    // (Aparência › Bordas › Cor da borda › Cena, IrisStyle.glassEdgeColour).
    property color scene: "#d0d8e8"
    // "Linha do shell" (origem "rim"): a linha de contorno das superfícies do shell (IrisStyle.rim) como ela aparece
    // sobre a superfície; nas janelas inativas o mesmo tom com metade da força.
    property color rim: "#5a7398"
    property color rimInactive: "#3a4556"
    function rimFor(slot: string): color { return slot.startsWith("inactive") ? root.rimInactive : root.rim }
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
        root.values = shown  // a linha mostra na hora; o refresh depois confirma
        root.queued = queued
        if (!writeProcess.running) root.flush()
    }
    function flush(): void {
        const keys = Object.keys(root.queued)
        if (keys.length === 0) return
        const args = []
        for (const key of keys) {
            const v = root.queued[key]
            args.push(key, Array.isArray(v) ? v.join(",") : String(v))
        }
        root.queued = ({})
        error = ""
        writeProcess.command = ["python3", root.script, "set"].concat(args)
        writeProcess.running = true
    }
    function setEnabled(on: bool): void {
        root.enabled = on
        enableProcess.command = ["python3", root.script, "enable", on ? "on" : "off"]
        enableProcess.running = true
    }

    // ---------- cores ----------
    function hex(c: color): string {
        const h = v => ("0" + Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    // A origem guardada; sem ela, a que o kwinrc mostra (paleta, preto, branco ou uma cor própria).
    function source(slot: string): string {
        Config.revision
        const saved = String(Config.options?.lowpan?.cornerColors?.[slot] ?? "")
        if (saved.length > 0) return saved.startsWith("custom:") ? "custom" : saved
        const s = root.slots[slot]
        if (!s) return ""
        if (s.usePalette && root.value(s.usePalette, false)) return "kde"
        const now = String(root.value(s.color, "#000000")).toLowerCase()
        return now === "#000000" || now === "#ffffff" ? now : "custom"
    }
    function customColour(slot: string): string {
        Config.revision
        const saved = String(Config.options?.lowpan?.cornerColors?.[slot] ?? "")
        if (saved.startsWith("custom:")) return saved.slice(7)
        return String(root.value(root.slots[slot]?.color ?? "", "#000000"))
    }
    function resolved(slot: string): color {
        const src = root.source(slot)
        if (src === "accent") return root.accent
        if (src === "highlight") return root.highlight
        if (src === "wallpaper") return root.scene
        if (src === "rim") return root.rimFor(slot)
        if (src === "kde") return root.kdeColour(slot)
        if (src === "custom") return root.customColour(slot)
        return src.startsWith("#") ? src : "#000000"
    }
    function pairsFor(slot: string, src: string, custom: string): var {
        const s = root.slots[slot]
        const pairs = {}
        if (!s) return pairs
        if (src === "kde" && s.usePalette) {
            pairs[s.usePalette] = true
            pairs[s.useCustom] = false
            pairs[s.palette] = s.role
            return pairs
        }
        const c = src === "accent" ? root.hex(root.accent)
            : src === "highlight" ? root.hex(root.highlight)
            : src === "wallpaper" ? root.hex(root.scene)
            : src === "rim" ? root.hex(root.rimFor(slot))
            : src === "custom" ? custom : src
        if (s.usePalette) {
            pairs[s.usePalette] = false
            pairs[s.useCustom] = true
        }
        pairs[s.color] = c
        return pairs
    }
    function setSource(slot: string, src: string): void {
        const keep = src === "custom" ? "custom:" + root.customColour(slot) : src
        Config.setNestedValue("lowpan.cornerColors." + slot, keep)
        root.setMany(root.pairsFor(slot, src, root.customColour(slot)))
    }
    function setCustom(slot: string, c: string): void {
        Config.setNestedValue("lowpan.cornerColors." + slot, "custom:" + c)
        root.setMany(root.pairsFor(slot, "custom", c))
    }
    // Regrava só as cores que seguem o destaque/realce e que mudaram de verdade.
    function syncAccent(): void {
        if (!root.loaded || !root.installed) return
        const pairs = {}
        for (const slot of Object.keys(root.slots)) {
            const src = String(Config.options?.lowpan?.cornerColors?.[slot] ?? "")
            if (src !== "accent" && src !== "highlight" && src !== "wallpaper" && src !== "rim") continue
            const want = root.hex(src === "accent" ? root.accent : src === "wallpaper" ? root.scene
                : src === "rim" ? root.rimFor(slot) : root.highlight)
            if (String(root.value(root.slots[slot].color, "")).toLowerCase() !== want) pairs[root.slots[slot].color] = want
        }
        if (Object.keys(pairs).length > 0) root.setMany(pairs)
    }
    readonly property string accentKey: root.following ? String(root.accent) + String(root.highlight) + String(root.scene) + String(root.rim) + String(root.rimInactive) : ""
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
                    root.installed = data.installed ?? false
                    root.enabled = data.enabled ?? false
                    const merged = data.values ?? {}
                    for (const key of Object.keys(root.queued)) merged[key] = root.queued[key]
                    root.values = merged
                    const first = !root.loaded
                    root.loaded = true
                    if (first && root.following) accentDebounce.restart()
                } catch (e) {
                    root.error = "Could not read the Rounded Corners settings"
                    console.warn("[KWinCorners] Bad state:", e)
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
                    console.warn("[KWinCorners] Write failed:", root.error)
                }
                if (Object.keys(root.queued).length > 0) root.flush()
                else refreshDebounce.restart()
            }
        }
    }

    Process {
        id: enableProcess
        onExited: refreshDebounce.restart()
    }

    Timer {
        id: refreshDebounce
        interval: 300
        onTriggered: root.refresh()
    }

    // A janela do KDE (e o lowpan-shells-tiling) também gravam aqui: a página acompanha.
    FileView {
        path: root.wanted ? root.kwinrc : ""
        watchChanges: true
        printErrors: false
        onFileChanged: if (!writeProcess.running) refreshDebounce.restart()
    }

    IpcHandler {
        target: "kwinCorners"

        function get(key: string): string {
            root.ensure()
            return root.loaded ? JSON.stringify(root.values[key]) : "loading, ask again"
        }
        function set(key: string, value: string): string {
            root.set(key, value)
            return "ok"
        }
        function status(): string {
            return JSON.stringify({ loaded: root.loaded, installed: root.installed, enabled: root.enabled,
                following: root.following, accent: String(root.accent), highlight: String(root.highlight) })
        }
        // origem de uma cor: accent | highlight | kde | #rrggbb | custom:#rrggbb
        function colour(slot: string, src: string): string {
            if (!root.slots[slot]) return "unknown slot: " + slot
            if (src.startsWith("custom:")) root.setCustom(slot, src.slice(7))
            else root.setSource(slot, src)
            return "ok"
        }
    }
}
