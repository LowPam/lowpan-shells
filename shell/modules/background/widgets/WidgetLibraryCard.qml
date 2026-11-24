pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.iris.style

Rectangle {
    id: root

    required property string widgetKey
    required property string title
    required property string symbol
    property bool active: false
    property bool selected: false

    signal addRequested()
    signal editRequested()

    readonly property real cardRadius: Math.round(14 * IrisStyle.density)

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 20
    radius: cardRadius
    color: root.selected ? ColorUtils.applyAlpha(IrisStyle.accent, 0.16)
        : root.active ? ColorUtils.applyAlpha(IrisStyle.text, 0.055) : "transparent"
    border.width: 0
    border.color: "transparent"

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 88
            radius: root.cardRadius
            color: root.active ? ColorUtils.applyAlpha(IrisStyle.accent, 0.12) : IrisStyle.surfaceHigh

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !["clock", "dateBadge", "editorial", "shape", "visualizer"].includes(root.widgetKey)
                text: root.symbol
                iconSize: 38
                color: root.active ? IrisStyle.accent : IrisStyle.subtext
                opacity: root.active ? 1 : 0.62
            }

            StyledText {
                anchors.centerIn: parent
                visible: ["clock", "dateBadge", "editorial"].includes(root.widgetKey)
                text: root.widgetKey === "clock" ? "12:48"
                    : root.widgetKey === "dateBadge" ? "MON  09" : "Aa."
                font.pixelSize: root.widgetKey === "editorial" ? 40 : 27
                font.family: Appearance.font.family.main
                font.weight: Font.DemiBold
                color: root.active ? IrisStyle.accent : IrisStyle.text
                opacity: root.active ? 1 : 0.72
            }

            MaterialShape {
                anchors.centerIn: parent
                visible: root.widgetKey === "shape"
                implicitSize: 54
                shape: MaterialShape.Shape.Flower
                color: root.active ? IrisStyle.accent : IrisStyle.subtext
                opacity: root.active ? 1 : 0.68
            }

            Row {
                anchors.centerIn: parent
                visible: root.widgetKey === "visualizer"
                spacing: 4
                Repeater {
                    model: [14, 28, 42, 30, 52, 36, 20, 32, 16]
                    Rectangle {
                        required property int modelData
                        width: 5
                        height: modelData
                        y: (52 - height) / 2
                        radius: Math.min(2, width / 2)
                        color: root.active ? IrisStyle.accent : IrisStyle.subtext
                        opacity: root.active ? 1 : 0.68
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: IrisStyle.text
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.active ? Translation.tr("On desktop") : Translation.tr("Ready to add")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.active ? IrisStyle.accent : IrisStyle.muted
                    elide: Text.ElideRight
                }
            }

            WidgetEditAction {
                compact: true
                iconName: root.active ? "tune" : "add"
                toggled: root.active
                tooltip: root.active ? Translation.tr("Edit widget") : Translation.tr("Add widget")
                onClicked: root.active ? root.editRequested() : root.addRequested()
            }
        }
    }
}
