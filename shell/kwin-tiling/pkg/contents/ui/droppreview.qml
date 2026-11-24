// LowPan Tiling — prévia do destino do arrasto (PLANEJAMENTO §21.13).
// Copyright (c) 2026 LowPan Shells. Licença MIT, como o Krohnkite em que se baseia.
//
// Desenho: o mesmo quadro da prévia de encaixe do KDE (KSvg "widgets/translucentbackground", como em
// /usr/share/kwin/outline/plasma/outline.qml), com ícone e texto no centro, dentro de um OSD do Plasma sem fundo próprio.
// Histórico: (1) janela própria → ficava atrás das janelas; (2) Workspace.showOutline → o KWin o esconde a cada passo do
// arrasto (confere as zonas de encaixe dele, que estão desligadas) e ele só piscava. O OSD fica por cima e ninguém o esconde.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

Item {
    id: root

    property string kind: ""

    function show(x, y, width, height, text, kind) {
        root.kind = kind;
        label.text = text;
        root.px = Math.round(x);
        root.py = Math.round(y);
        body.width = Math.max(1, Math.round(width));
        body.height = Math.max(1, Math.round(height));
        body.opacity = 1;
        osd.opacity = 1;
        // o Dialog recentraliza toda vez que aparece: depois da 1ª vez ele fica aberto (vazio, 1×1 px, transparente ao
        // mouse) e "esconder" só esvazia — assim não há o pulo do centro da tela para o lugar
        if (!osd.visible) osd.visible = true;
        root.place();
        Qt.callLater(root.place);
    }

    function hide() {
        // opacidade 0 na janela: com 1×1 px sem fundo o KWin desenhava o xadrez rosa/preto de "textura faltando" (+ sombra)
        osd.opacity = 0;
        body.opacity = 0;
        body.width = 1;
        body.height = 1;
    }

    property int px: 0
    property int py: 0
    function place() {
        if (osd.x !== root.px) osd.x = root.px;
        if (osd.y !== root.py) osd.y = root.py;
    }

    PlasmaCore.Dialog {
        id: osd
        type: PlasmaCore.Dialog.OnScreenDisplay
        flags: Qt.WindowStaysOnTopHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
        location: PlasmaCore.Types.Floating
        backgroundHints: PlasmaCore.Dialog.NoBackground
        outputOnly: true
        visible: false
        onWidthChanged: root.place()
        onHeightChanged: root.place()
        onVisibleChanged: if (visible) root.place()
        onXChanged: if (visible && x !== root.px) Qt.callLater(root.place)
        onYChanged: if (visible && y !== root.py) Qt.callLater(root.place)

        mainItem: Item {
            id: body
            width: 1
            height: 1
            opacity: 0

            KSvg.FrameSvgItem {
                anchors.fill: parent
                imagePath: "widgets/translucentbackground"
                opacity: root.kind === "deny" ? 0.75 : 1
            }

            RowLayout {
                anchors.centerIn: parent
                visible: label.text.length > 0 && body.width > 160 && body.height >= 50
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: implicitWidth
                    source: root.kind === "tab" ? "tab-new" : root.kind === "stack" ? "view-split-top-bottom" : "dialog-cancel"
                }
                Kirigami.Heading {
                    id: label
                    level: 3
                }
            }
        }
    }
}
