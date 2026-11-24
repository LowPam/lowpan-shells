pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.iris.style
import qs.modules.iris.components

ColumnLayout {
    id: root

    required property var picker
    readonly property real d: IrisStyle.density

    spacing: Math.round(8 * root.d)

    // LowPan Shells: a lista rolável (Flickable) intercepta a roda dos filhos e usa a rolagem lenta dela; o captador
    // da roda fica ao lado da lista, por cima (MouseArea sem botões: cliques e hover passam), e move a lista direto.
    component Strip: Item {
        id: strip
        default property alias items: stripRow.data
        property real rowHeight: Math.round(30 * root.d)
        Layout.fillWidth: true
        implicitHeight: strip.rowHeight
        Flickable {
            id: stripFlick
            anchors.fill: parent
            contentWidth: stripRow.implicitWidth
            contentHeight: strip.rowHeight
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Behavior on contentX {
                enabled: stripWheel.animating
                NumberAnimation { duration: IrisStyle.duration(180); easing.type: IrisStyle.feedbackEasing }
            }
            Row {
                id: stripRow
                height: strip.rowHeight
                spacing: Math.round(6 * root.d)
            }
        }
        MouseArea {
            id: stripWheel
            property bool animating: false
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: event => {
                event.accepted = true
                // ~um cartão de pasta por clique da roda; touchpad 1,5×. O KWin manda nos cliques da roda os dois valores
                // (ângulo 120 e pixel 15): ângulo em múltiplos de 120 = roda de mouse (o pixel deixava em 15 px por clique)
                const angle = event.angleDelta.y || event.angleDelta.x
                const touch = !(angle !== 0 && angle % 120 === 0) && (event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0)
                stripWheel.animating = !touch
                const delta = touch ? (event.pixelDelta.x || event.pixelDelta.y) * 1.5
                    : angle / 120 * Math.round(220 * root.d)
                stripFlick.contentX = Math.max(0, Math.min(Math.max(0, stripFlick.contentWidth - stripFlick.width), stripFlick.contentX - delta))
            }
        }
    }

    Strip {
        rowHeight: Math.round((root.picker.libraryFolders.length > 0 ? 44 : 30) * root.d)
        // LowPan Shells: primeiro as subpastas da pasta aberta, depois os atalhos fixos (pedido do usuário, 2026-11-07)
        Repeater {
            model: root.picker.libraryFolders
            MouseArea {
                id: folder
                required property var modelData
                readonly property var info: root.picker.folderInfo[folder.modelData.path] ?? null
                readonly property string cover: String(folder.info?.cover ?? "")
                readonly property real inset: Math.round(6 * root.d)
                width: folderRow.implicitWidth + folder.inset + Math.round(14 * root.d)
                height: Math.round(44 * root.d)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                Accessible.role: Accessible.Button
                Accessible.name: folder.modelData.name
                onClicked: root.picker.openFolder(folder.modelData.path)
                Rectangle {
                    anchors.fill: parent
                    radius: IrisStyle.radiusTile
                    color: folder.pressed ? IrisStyle.fillActive : folder.containsMouse ? IrisStyle.fillHover : IrisStyle.fillQuiet
                    scale: folder.pressed ? IrisStyle.pressScale(0.97) : 1
                    Behavior on color { ColorAnimation { duration: IrisStyle.duration(110); easing.type: IrisStyle.feedbackEasing } }
                    Behavior on scale { NumberAnimation { duration: IrisStyle.duration(110); easing.type: IrisStyle.feedbackEasing } }
                }
                Row {
                    id: folderRow
                    anchors.left: parent.left
                    anchors.leftMargin: folder.inset
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.round(9 * root.d)
                    ClippingRectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: folder.height - 2 * folder.inset
                        height: width
                        radius: Math.max(IrisStyle.radiusMicro, IrisStyle.radiusTile - folder.inset)
                        color: IrisStyle.fill
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: folder.cover.length === 0
                            text: "folder"
                            fill: 1
                            iconSize: Math.round(17 * root.d)
                            color: IrisStyle.accent
                        }
                        Loader {
                            anchors.fill: parent
                            active: folder.cover.length > 0
                            sourceComponent: ThumbnailImage {
                                generateThumbnail: true
                                cleanVideoStill: true
                                sourcePath: folder.cover
                                thumbnailSizeName: "normal"
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: Math.round(width * 2)
                                mipmap: true
                                sourceSize.height: Math.round(height * 2)
                            }
                        }
                    }
                    IrisText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: folder.modelData.name
                        width: Math.min(implicitWidth, Math.round(200 * root.d))
                        elide: Text.ElideRight
                        font.pixelSize: IrisStyle.typeLabel
                        font.weight: IrisStyle.weight(Font.Medium)
                    }
                    IrisText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (folder.info?.count ?? 0) > 0
                        text: String(folder.info?.count ?? "")
                        color: IrisStyle.secondaryAccent
                        font.family: IrisStyle.fontNumbers
                        font.features: ({ "tnum": 1 })
                        font.pixelSize: IrisStyle.typeMeta
                        font.weight: IrisStyle.weight(Font.Bold)
                    }
                }
            }
        }
        Rectangle {
            visible: root.picker.libraryFolders.length > 0 && root.picker.places.length > 0
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Math.round(20 * root.d)
            color: IrisStyle.hairline
        }
        Repeater {
            model: root.picker.places
            IrisChip {
                id: place
                required property var modelData
                y: Math.round(((parent?.height ?? height) - height) / 2)
                glyph: place.modelData.glyph
                // LowPan Shells: com subpastas na linha, os atalhos fixos ficam só com o ícone (o nome vai na dica)
                readonly property bool compact: root.picker.libraryFolders.length > 0
                label: place.compact ? "" : place.modelData.label
                Accessible.name: place.modelData.label
                StyledToolTip {
                    text: place.modelData.label
                    extraVisibleCondition: place.compact && place.hovered
                }
                selected: root.picker.folderPath === place.modelData.path
                onClicked: root.picker.openFolder(place.modelData.path)
            }
        }
    }
}
