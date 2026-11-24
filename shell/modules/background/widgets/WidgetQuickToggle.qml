pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common.widgets
import qs.modules.iris.style
import qs.modules.iris.components

// An on/off option in a widget's quick controls: a row with its glyph, its name and a switch. The
// whole row toggles. A choice between values is WidgetQuickChoices, never a lit capsule.
Rectangle {
    id: root

    property string iconName: ""
    property string label: ""
    property bool checked: false
    signal toggled()

    readonly property real d: IrisStyle.density

    opacity: root.enabled ? 1 : 0.45
    implicitWidth: Math.round(200 * root.d)
    implicitHeight: Math.round(38 * root.d)
    radius: IrisStyle.radiusRow
    color: hover.hovered ? IrisStyle.fillHover : IrisStyle.fillQuiet
    Behavior on color {
        enabled: IrisStyle.motionEnabled
        ColorAnimation { duration: IrisStyle.feedbackDuration }
    }

    MaterialSymbol {
        id: glyph
        visible: root.iconName.length > 0
        anchors.left: parent.left
        anchors.leftMargin: Math.round(11 * root.d)
        anchors.verticalCenter: parent.verticalCenter
        text: root.iconName
        fill: root.checked ? 1 : 0
        iconSize: Math.round(17 * root.d)
        color: root.checked ? IrisStyle.text : IrisStyle.textSecondary
    }
    StyledText {
        anchors.left: glyph.visible ? glyph.right : parent.left
        anchors.leftMargin: Math.round((glyph.visible ? 9 : 12) * root.d)
        anchors.right: switchSlot.left
        anchors.rightMargin: Math.round(8 * root.d)
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        elide: Text.ElideRight
        color: IrisStyle.text
        font.family: IrisStyle.fontMain
        font.pixelSize: IrisStyle.typeLabel
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    Item {
        anchors.left: parent.left
        anchors.right: switchSlot.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: answer.restart() }
    }

    Item {
        id: switchSlot
        anchors.right: parent.right
        anchors.rightMargin: Math.round(9 * root.d)
        anchors.verticalCenter: parent.verticalCenter
        width: irisSwitch.width
        height: irisSwitch.height

        IrisSwitch {
            id: irisSwitch
            anchors.centerIn: parent
            on: root.checked
            name: root.label
            onToggled: answer.restart()
        }
    }

    // Answered after the tap returns, so a row rebuilt by its own change never dies inside the click.
    Timer { id: answer; interval: 0; onTriggered: root.toggled() }

    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.checked: root.checked
}
