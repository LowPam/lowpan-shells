pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

/**
 * LowPan Shells: tema do sistema por perfil de ambiente no KWin (§21.54, §21.64). Ao subir, o shell
 * pede o perfil "own" (iRiS) de volta — o script guarda o perfil que sai (com o que o usuário mudou)
 * e escreve o que entra; pedido repetido não faz nada. Ao voltar ao Plasma, quem troca é o
 * system/lowpan-shells-switch (perfil "plasma").
 */
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/lowpan-theme-profile")
    readonly property bool wanted: CompositorService.isKWin
        && (Config.options?.lowpan?.themeProfile ?? true)
    readonly property var command: ["switch", "own"]
    property var _running: []

    function sync(): void {
        if (!Config.ready) return
        debounce.restart()
    }

    onCommandChanged: sync()
    Component.onCompleted: sync()
    Connections {
        target: Config
        function onReadyChanged() { root.sync() }
    }

    Timer {
        id: debounce
        interval: 600
        onTriggered: {
            if (!root.wanted) return
            if (proc.running) { restart(); return }
            root._running = root.command
            proc.command = [root.script].concat(root.command)
            proc.running = true
        }
    }

    Process {
        id: proc
        stderr: StdioCollector { id: err }
        onExited: (code) => {
            if (code !== 0) console.warn("[ThemeProfile]", root._running.join(" "), "saiu com", code, err.text)
            if (JSON.stringify(root._running) !== JSON.stringify(root.command)) debounce.restart()
            // Sem reiniciar o shell: os ícones do próprio shell seguem o mapa que o script regrava a cada
            // troca (services/IconMap.qml). O reinício deixava ~3 s sem fundo/barra/Dock.
        }
    }
}
