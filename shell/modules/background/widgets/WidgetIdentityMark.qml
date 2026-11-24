pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common.widgets
import qs.modules.iris.style

// A widget's mark at the head of its quick controls. iRiS: the category-tint squircle with a white
// glyph (its identity grammar); the ii family: the Global Style's tonal container.
Rectangle {
    id: root

    property string glyph: "widgets"
    property color tint: IrisStyle.accent

    readonly property real d: IrisStyle.density

    implicitWidth: Math.round(28 * root.d)
    implicitHeight: implicitWidth
    radius: IrisStyle.iconRadius(width)
    color: root.tint
    gradient: tintGradient

    Gradient {
        id: tintGradient
        GradientStop { position: 0; color: Qt.lighter(root.tint, 1.18) }
        GradientStop { position: 1; color: root.tint }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.glyph
        fill: 1
        iconSize: Math.round(17 * root.d)
        color: IrisStyle.onTint
    }
}
