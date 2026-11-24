/*
 LowPan Shells — seletor do Alt+Tab do KWin no estilo da família estilo macOS (Etapa 6c, PLANEJAMENTO §21.47).
 Fileira de ícones grandes num painel escuro arredondado no centro da tela; o escolhido ganha um fundo claro e o
 título da janela aparece embaixo dele. Mouse: clique escolhe, clique no já escolhido (ou duplo) ativa.
 Feito a partir do "big_icons" do KWin (Martin Gräßlin, GPL-2.0-or-later).

 SPDX-License-Identifier: GPL-2.0-or-later
 */
import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWin

KWin.TabBoxSwitcher {
    id: tabBox

    currentIndex: (instantiator.object as MacSwitcher)?.currentIndex ?? currentIndex

    Instantiator {
        id: instantiator
        active: tabBox.visible
        delegate: MacSwitcher { }
    }

    component MacSwitcher: PlasmaCore.Dialog {
        id: dialog
        property alias currentIndex: icons.currentIndex
        location: PlasmaCore.Types.Floating
        visible: tabBox.visible
        backgroundHints: PlasmaCore.Dialog.NoBackground
        flags: Qt.ToolTip | Qt.X11BypassWindowManagerHint
        x: tabBox.screenGeometry.x + Math.round((tabBox.screenGeometry.width - panel.width) / 2)
        y: tabBox.screenGeometry.y + Math.round((tabBox.screenGeometry.height - panel.height) / 2)

        // WhiteSur escuro (o mesmo cinza da família no shell)
        readonly property color panelColor: "#EB2A2A2A"
        readonly property color borderColor: "#24FFFFFF"
        readonly property color textColor: "#DEDEDE"

        mainItem: Item {
            id: panel

            readonly property int iconSize: Math.round(Kirigami.Units.iconSizes.enormous * 0.75) // ~96 px
            readonly property int cell: iconSize + 20
            readonly property int pad: 14
            readonly property int perRow: Math.max(1, Math.floor(tabBox.screenGeometry.width * 0.9 / cell))
            readonly property int rows: Math.max(1, Math.ceil(icons.count / perRow))

            width: Math.max(cell * 3, Math.min(icons.count, perRow) * cell) + pad * 2
            height: rows * cell + pad * 2 + caption.height + 6

            Rectangle {
                anchors.fill: parent
                radius: 26
                color: dialog.panelColor
                border.width: 1
                border.color: dialog.borderColor
            }

            GridView {
                id: icons
                x: panel.pad + Math.max(0, (panel.width - panel.pad * 2 - Math.min(count, panel.perRow) * panel.cell) / 2)
                y: panel.pad
                width: Math.min(count, panel.perRow) * panel.cell
                height: panel.rows * panel.cell
                cellWidth: panel.cell
                cellHeight: panel.cell
                interactive: false
                flow: GridView.FlowLeftToRight
                keyNavigationWraps: true
                highlightMoveDuration: 0
                currentIndex: tabBox.currentIndex
                focus: true
                model: tabBox.model

                highlight: Rectangle {
                    width: panel.cell
                    height: panel.cell
                    radius: 18
                    color: "#2EFFFFFF"
                }

                delegate: Item {
                    required property int index
                    required property string caption
                    required property var icon
                    readonly property string title: caption
                    width: panel.cell
                    height: panel.cell

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: panel.iconSize
                        height: panel.iconSize
                        source: parent.icon
                    }

                    TapHandler {
                        onSingleTapped: {
                            if (parent.index === icons.currentIndex) {
                                icons.model.activate(parent.index)
                                return
                            }
                            icons.currentIndex = parent.index
                        }
                        onDoubleTapped: icons.model.activate(parent.index)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: icons.count === 0
                    text: i18ndc("kwin", "@info:placeholder no entries in the task switcher", "No open windows")
                    color: dialog.textColor
                }
            }

            // título da janela escolhida, embaixo da fileira e alinhado ao ícone dela (preso às bordas do painel)
            Text {
                id: caption
                readonly property real centerX: icons.currentItem
                    ? icons.x + icons.currentItem.x + icons.currentItem.width / 2 : panel.width / 2
                width: Math.min(implicitWidth, panel.width - panel.pad * 2)
                x: Math.max(panel.pad, Math.min(panel.width - panel.pad - width, centerX - width / 2))
                y: icons.y + icons.height + 4
                text: icons.currentItem ? icons.currentItem.title : ""
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: dialog.textColor
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Connections {
                target: tabBox
                function onCurrentIndexChanged() { icons.currentIndex = tabBox.currentIndex }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Up) icons.moveCurrentIndexUp()
                else if (event.key === Qt.Key_Down) icons.moveCurrentIndexDown()
                else if (event.key === Qt.Key_Left) icons.moveCurrentIndexLeft()
                else if (event.key === Qt.Key_Right) icons.moveCurrentIndexRight()
            }
        }

        onSceneGraphError: () => {
            // vazio de propósito (como no big_icons): evita qFatal num reset da placa de vídeo
        }
    }
}
