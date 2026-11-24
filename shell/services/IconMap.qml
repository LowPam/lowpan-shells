pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LowPan Shells (§21.54): ícones pelo tema que está VALENDO no sistema, sem reiniciar o shell.
 * O processo do Quickshell lê o tema de ícones do Qt ao iniciar e não troca de forma confiável depois;
 * então scripts/lowpan-theme-profile grava, a cada troca de perfil (iRiS ↔ Plasma), o mapa
 * nome → arquivo do tema atual (scripts/lowpan-icon-map) em ~/.cache/lowpan-shells/icon-map.json,
 * e aqui ele é lido (e relido quando muda). `path()` tem a mesma assinatura do Quickshell.iconPath:
 * nome fora do mapa (ou caminho absoluto) cai no Quickshell.iconPath como antes.
 */
Singleton {
    id: root

    property var icons: ({})
    property string theme: ""

    function path(name: var, fallback: var): string {
        const n = String(name ?? "")
        if (n.length > 0 && !n.startsWith("/") && n.indexOf(":") < 0) {
            const f = root.icons[n]
            if (f) return "file://" + f
            if (typeof fallback === "string" && fallback.length > 0 && root.icons[fallback]
                    && Quickshell.iconPath(n, true) === "")
                return "file://" + root.icons[fallback]
        }
        return fallback === undefined ? Quickshell.iconPath(n) : Quickshell.iconPath(n, fallback)
    }

    FileView {
        path: `${Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")}/lowpan-shells/icon-map.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.icons = d.icons ?? ({})
                root.theme = d.theme ?? ""
                console.log("[IconMap]", root.theme, Object.keys(root.icons).length, "ícones")
            } catch (e) {
                console.warn("[IconMap] mapa inválido:", e)
            }
        }
        onLoadFailed: root.icons = ({})
    }
}
