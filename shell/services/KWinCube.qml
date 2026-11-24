pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// LowPan Shells — fundo do efeito "Cubo" do KWin (kdeplasma-addons) a partir de um papel de parede.
// O cubo aceita uma cor ou uma imagem ("SkyBox"). O shell copia a imagem para um lugar fixo (o papel de parede pode
// sumir depois), grava kwinrc [Effect-cube] Background=SkyBox + SkyBox=<arquivo> e recarrega o efeito. Vídeo vira o
// quadro parado dele. Nada disso acontece se o cubo não estiver carregado; o shell nunca liga o efeito.
Singleton {
    id: root

    readonly property bool kwin: CompositorService.isKWin
    property bool available: false            // efeito "cube" carregado no KWin
    property bool usingImage: false           // Background=SkyBox
    property string imagePath: ""             // SkyBox atual (sem file://)
    readonly property bool follows: Config.options?.iris?.wallpaper?.cubeFollows ?? false
    readonly property string store: `${Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")}/lowpan-shells`

    function refresh(): void { if (root.kwin && !probe.running) probe.running = true }
    Component.onCompleted: root.refresh()

    Process {
        id: probe
        command: ["sh", "-c", 'busctl --user call org.kde.KWin /Effects org.kde.kwin.Effects isEffectLoaded s cube 2>/dev/null; '
            + 'echo "bg=$(kreadconfig6 --file kwinrc --group Effect-cube --key Background)"; '
            + 'echo "sky=$(kreadconfig6 --file kwinrc --group Effect-cube --key SkyBox)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text)
                root.available = /^b true/m.test(out)
                root.usingImage = /^bg=SkyBox$/m.test(out)
                root.imagePath = ((/^sky=(.*)$/m.exec(out) ?? [])[1] ?? "").replace(/^file:\/\//, "")
            }
        }
    }

    // Grava a imagem do cubo. `path` pode ser imagem ou vídeo (vira o quadro parado). O panorama é montado por
    // scripts/lowpan-cube-skybox (esticada como o cubo espera, com desfoque leve contra o granulado do zoom de ~3×).
    function setFrom(path: string): void {
        const clean = String(path ?? "").replace(/^file:\/\//, "")
        if (!root.kwin || clean.length === 0) return
        apply.command = ["sh", "-c", root.script, "sh", clean, root.store, Quickshell.shellPath("scripts/lowpan-cube-skybox")]
        apply.running = true
    }
    // Volta à cor sólida padrão do cubo.
    function reset(): void {
        resetProc.running = true
    }

    readonly property string script: 'set -e; mkdir -p "$2"; '
        // um nome novo por troca: o cubo guarda a textura por caminho e não relê o mesmo arquivo
        + 'out="$2/cube-skybox-$(date +%s).jpg"; '
        + '"$3" "$1" "$out"; '
        + '[ -s "$out" ]; '
        + 'find "$2" -maxdepth 1 -name "cube-skybox-*.jpg" ! -path "$out" -delete; '
        + 'kwriteconfig6 --file kwinrc --group Effect-cube --key Background SkyBox; '
        + 'kwriteconfig6 --file kwinrc --group Effect-cube --key SkyBox "file://$out"; '
        + 'busctl --user call org.kde.KWin /Effects org.kde.kwin.Effects reconfigureEffect s cube >/dev/null'

    Process {
        id: apply
        onExited: root.refresh()
    }
    Process {
        id: resetProc
        command: ["sh", "-c", 'kwriteconfig6 --file kwinrc --group Effect-cube --key Background --delete; '
            + 'kwriteconfig6 --file kwinrc --group Effect-cube --key SkyBox --delete; '
            + 'find "$1" -maxdepth 1 -name "cube-skybox-*.jpg" -delete 2>/dev/null; '
            + 'busctl --user call org.kde.KWin /Effects org.kde.kwin.Effects reconfigureEffect s cube >/dev/null', "sh", root.store]
        onExited: root.refresh()
    }

    // "O fundo do cubo acompanha o papel de parede": a cada troca do papel de parede principal.
    readonly property string wallpaper: String(Config.options?.background?.wallpaperPath ?? "")
    onWallpaperChanged: if (root.follows && root.available) followDelay.restart()
    onFollowsChanged: if (root.follows && root.available) followDelay.restart()
    Timer { id: followDelay; interval: 1500; onTriggered: root.setFrom(root.wallpaper) }
}
