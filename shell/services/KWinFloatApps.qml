pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * LowPan Shells: apps que sempre flutuam no LowPan Tiling (Configurações › Janelas › Tiling, 2026-11-12).
 * A verdade é o kwinrc [Script-lowpan-tiling] floatingClass (resourceClass separados por vírgula), lido e gravado por
 * scripts/kwin-float-apps.py. O motor relê a lista a cada segundo: vale na hora, também para as janelas abertas.
 * pick() põe o cursor em mira (KWin queryWindowInfo) e acrescenta o app da janela clicada.
 */
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/kwin-float-apps.py")
    readonly property string kwinrc: FileUtils.trimFileProtocol(`${Directories.config}/kwinrc`)

    property bool wanted: false
    property var apps: []
    property bool picking: false

    function ensure(): void {
        if (!CompositorService.isKWin) return
        if (!root.wanted) {
            root.wanted = true
            getProcess.running = true
        }
    }
    function has(app: string): bool {
        return root.apps.includes(String(app))
    }
    function save(next: var): void {
        root.apps = next
        setProcess.command = ["python3", root.script, "set", next.join(",")]
        setProcess.running = true
    }
    function add(app: string): void {
        const a = String(app ?? "").trim()
        if (a.length === 0 || root.has(a)) return
        root.save(root.apps.concat([a]))
    }
    function remove(app: string): void {
        root.save(root.apps.filter(entry => entry !== String(app)))
    }
    function toggle(app: string): void {
        if (root.has(app)) root.remove(app)
        else root.add(app)
    }
    function pick(): void {
        if (root.picking) return
        root.picking = true
        pickProcess.running = true
    }

    // LowPan Shells (§21.103): padrão do motor (Krohnkite) entre colchetes = "a classe contém"; os jogos da Steam são
    // steam_app_<id>, então "[steam_app_]" faz todos flutuarem em modo janela (tela cheia passa por cima do tiling).
    readonly property string steamGames: "[steam_app_]"
    function covers(app: string): bool {
        const a = String(app).toLowerCase()
        return root.apps.some(entry => entry.length > 2 && entry[0] === "[" && entry[entry.length - 1] === "]"
            && a.includes(entry.slice(1, -1).toLowerCase()))
    }
    // Nome e ícone de um app pela classe (org.gnome.Nautilus → o .desktop dele)
    function entryOf(app: string): var {
        return AppSearch.lookupDesktopEntry(String(app)) ?? DesktopEntries.heuristicLookup(String(app))
    }
    function nameOf(app: string): string {
        if (String(app) === root.steamGames) return Translation.tr("Steam games")
        return root.entryOf(app)?.name || String(app)
    }
    function iconOf(app: string): string {
        if (String(app) === root.steamGames) return IconMap.path(IconThemeService.smartIconName("steam", "steam"), "applications-games")
        const id = String(app)
        const icon = root.entryOf(id)?.icon || AppSearch.guessIcon(id)
        return IconMap.path(IconThemeService.smartIconName(icon, id), "application-x-executable")
    }

    Process {
        id: getProcess
        command: ["python3", root.script, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(this.text)
                    if (Array.isArray(list)) root.apps = list.map(entry => String(entry))
                } catch (e) {
                    console.warn("[KWinFloatApps] leitura:", e)
                }
            }
        }
    }
    Process {
        id: setProcess
        stderr: SplitParser { onRead: line => console.warn("[KWinFloatApps]", line) }
    }
    Process {
        id: pickProcess
        command: ["python3", root.script, "pick"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(this.text)
                    const app = String(info.resourceClass || info.resourceName || "")
                    // as janelas do próprio shell não entram no tiling
                    if (app.length > 0 && app !== "quickshell") root.add(app)
                } catch (e) {
                    console.warn("[KWinFloatApps] mira:", e)
                }
            }
        }
        onExited: root.picking = false
    }

    // A lista também muda por fora (kwinrc editado à mão): relê
    FileView {
        path: root.wanted ? root.kwinrc : ""
        watchChanges: true
        printErrors: false
        onFileChanged: if (!setProcess.running) refreshDebounce.restart()
    }
    Timer {
        id: refreshDebounce
        interval: 300
        onTriggered: if (!getProcess.running) getProcess.running = true
    }
}
