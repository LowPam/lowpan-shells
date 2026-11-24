// LowPan Shells — login do LowPan (§21.72): uma camada (layer-shell) por tela, formulário só na principal.
// Carregado pelo shell.qml só em produção (no modo de teste fora da tela não há backend de PanelWindow).
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: camadas

    // Preenchido pelo shell.qml (raiz) logo depois de carregar; até lá não cria janela nenhuma.
    property var estado: null

    Variants {
        model: camadas.estado ? Quickshell.screens : []

        PanelWindow {
            id: janela
            required property var modelData
            readonly property bool principal: camadas.estado.ehPrincipal(janela.modelData)
            screen: janela.modelData
            color: "#0b0b0f"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "lowpan-greeter"
            WlrLayershell.keyboardFocus: janela.principal ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }

            Tela {
                anchors.fill: parent
                estado: camadas.estado
                principal: janela.principal
            }
        }
    }
}
