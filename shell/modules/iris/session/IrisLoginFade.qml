// LowPan Shells (§21.72): entrada com fade depois da tela de login do iRiS.
// Sem tela de apresentação (decisão do dono): a tela de login sai com fade para o preto e o iRiS entra com fade a
// partir do preto. Só acontece quando o system/lowpan-sessao-login deixa o aviso $XDG_RUNTIME_DIR/lowpan-entrada
// (login na sessão iRiS); num reinício do shell no meio da sessão não há fade. O aviso é apagado ao usar.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

Scope {
    id: root

    readonly property string aviso: (Quickshell.env("XDG_RUNTIME_DIR") ?? "") + "/lowpan-entrada"
    property bool ativo: false
    property bool sumindo: false

    // Leitura síncrona: o véu precisa existir antes do primeiro quadro do shell.
    FileView {
        id: arquivoAviso
        path: root.aviso
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.ativo = true
            Quickshell.execDetached(["rm", "-f", root.aviso])
        }
    }

    // Some com fade um pouco depois do primeiro quadro (dá tempo do papel de parede e da barra desenharem).
    Connections {
        target: GlobalStates
        enabled: root.ativo
        function onShellEntryReadyChanged(): void {
            if (GlobalStates.shellEntryReady)
                inicioFade.restart()
        }
    }
    Timer { id: inicioFade; interval: 250; onTriggered: root.sumindo = true }
    Timer { interval: 8000; running: root.ativo; onTriggered: root.sumindo = true }   // segurança
    Timer { id: fim; interval: 600; onTriggered: root.ativo = false }

    LazyLoader {
        active: root.ativo

        Variants {
            model: Quickshell.screens

            PanelWindow {
                id: veu
                required property var modelData
                screen: veu.modelData
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                // Tipo OSD no KWin: os efeitos de abrir/fechar janela não animam esta superfície.
                WlrLayershell.namespace: "on-screen-display"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // 2 âncoras + tamanho da tela (o KWin 6.8 desloca superfícies com 4 âncoras pela área útil).
                anchors { top: true; left: true }
                implicitWidth: veu.modelData.width
                implicitHeight: veu.modelData.height
                mask: Region {}

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: root.sumindo ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
                    }
                    onOpacityChanged: if (opacity === 0) fim.restart()
                }
            }
        }
    }
}
