pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * LowPan Shells (2026-11-13): destino do efeito de minimizar Achatar2 = o ícone do app na dock.
 * Cada dock (uma por monitor) publica a lista de ícones com as janelas de cada um; aqui ela vira
 * "c:<classe>=x,y,l,a;p:<pid>=x,y,l,a;…" e vai para o kwinrc por scripts/kwin-minimize-targets.py
 * (o efeito relê ao ser reconfigurado). Só no KWin; grava depois de 500 ms parado e só se mudou.
 */
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/kwin-minimize-targets.py")
    property var perScreen: ({})
    property string written: ""

    // targets: [{ x, y, width, height, windowIds: [id do NiriService] }] em coordenadas globais
    function publish(screenName: string, targets: var): void {
        if (!CompositorService.isKWin) return
        const next = Object.assign({}, root.perScreen)
        next[String(screenName)] = targets ?? []
        root.perScreen = next
        debounce.restart()
    }

    function build(): string {
        const byId = {}
        for (const w of NiriService.windows ?? []) byId[w.id] = w
        const out = []
        const seen = {}
        const add = (key, t) => {
            if (seen[key]) return
            seen[key] = true
            out.push(`${key}=${Math.round(t.x)},${Math.round(t.y)},${Math.round(t.width)},${Math.round(t.height)}`)
        }
        for (const name of Object.keys(root.perScreen)) {
            for (const t of root.perScreen[name] ?? []) {
                for (const id of t.windowIds ?? []) {
                    const w = byId[id]
                    if (!w) continue
                    const cls = String(w.resource_class ?? "").toLowerCase().replace(/[=;,\s]/g, "")
                    if (cls.length > 0) add("c:" + cls, t)
                    if (w.pid > 0) add("p:" + w.pid, t)
                }
            }
        }
        return out.join(";")
    }

    Timer {
        id: debounce
        interval: 500
        onTriggered: {
            const value = root.build()
            if (value === root.written) return
            if (writer.running) return // o onExited recalcula
            root.written = value
            writer.command = ["python3", root.script, "set", value]
            writer.running = true
        }
    }

    Process {
        id: writer
        onExited: debounce.restart()
    }
}
