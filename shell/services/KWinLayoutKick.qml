pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * LowPan Shells — contorno do bug de posicionamento do KWin 6.8.
 *
 * Na primeira vez que uma layer surface aparece, o KWin a encaixa na área útil (descontando as
 * zonas reservadas de painéis/reservas). Uma superfície de tela cheia com exclusive_zone -1
 * acaba deslocada (ex.: 0,-46 ou -10,-56). Qualquer novo layout das layer surfaces da saída
 * corrige todas de uma vez.
 *
 * Aqui uma superfície invisível de 1×1 por tela alterna a própria margem (0 → 1 → 0). Isso força o
 * KWin a refazer o layout da saída sem mudar a área útil (o Krohnkite não reorganiza nada).
 * Quem chama: NiriService (modo KWin), quando o KWin Script avisa que surgiu uma superfície
 * do quickshell, e também na troca de telas.
 */
Singleton {
    id: root

    readonly property bool enabled: CompositorService.isKWin
    property int _nudge: 0

    function kick(): void {
        if (!root.enabled) return
        debounce.restart()
        settle.restart() // segunda passada: superfícies que mudam de tamanho logo após mapear
    }

    Timer { id: debounce; interval: 16; onTriggered: root._pulse() } // ~1 quadro: a superfície nasce deslocada e isto a corrige quase de imediato
    Timer { id: settle; interval: 700; onTriggered: root._pulse() }

    function _pulse(): void {
        root._nudge = 1
        Qt.callLater(() => root._nudge = 0)
    }

    Variants {
        model: root.enabled ? Quickshell.screens : []
        delegate: Component {
            PanelWindow {
                required property var modelData
                screen: modelData
                anchors { top: true; left: true }
                margins.left: root._nudge
                implicitWidth: 1
                implicitHeight: 1
                exclusiveZone: 0
                color: "transparent"
                mask: Region {}
                WlrLayershell.layer: WlrLayer.Background
                WlrLayershell.namespace: "lowpan-layout-kick"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            }
        }
    }

    // Garantia no boot, antes do primeiro aviso da ponte
    Timer { running: root.enabled; interval: 1200; onTriggered: root.kick() }
    Connections {
        target: Quickshell
        enabled: root.enabled
        function onScreensChanged(): void { root.kick() }
    }
}
