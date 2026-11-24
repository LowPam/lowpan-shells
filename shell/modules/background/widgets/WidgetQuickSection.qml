pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common.widgets
import qs.modules.iris.style

// A titled group inside a widget's quick controls: one quiet caption, then its controls.
ColumnLayout {
    id: root

    property string title: ""
    property string detail: ""
    default property alias content: body.data

    readonly property real d: IrisStyle.density

    Layout.fillWidth: true
    spacing: Math.round(7 * root.d)

    RowLayout {
        visible: root.title.length > 0
        Layout.fillWidth: true
        spacing: Math.round(6 * root.d)

        StyledText {
            Layout.fillWidth: true
            text: root.title
            elide: Text.ElideRight
            color: IrisStyle.textSecondary
            font.family: IrisStyle.fontMain
            font.pixelSize: IrisStyle.typeMeta
            font.weight: IrisStyle.weight(Font.DemiBold)
            font.capitalization: Font.MixedCase
            font.letterSpacing: 0
        }
        StyledText {
            visible: root.detail.length > 0
            text: root.detail
            color: IrisStyle.textTertiary
            font.family: IrisStyle.fontNumbers
            font.features: ({ "tnum": 1 })
            font.pixelSize: IrisStyle.typeMeta
        }
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: Math.round(4 * root.d)
    }
}
