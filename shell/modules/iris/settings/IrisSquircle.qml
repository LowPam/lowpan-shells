pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.iris.style

Rectangle {
    id: root

    property color tint: IrisStyle.identity.gray
    property string glyph: "settings"
    property real glyphShare: 0.64

    // The icon pack: "iris" is the family's tinted squircle. "tile" is the app-icon look,
    // a plate the user can colour, with the glyph in a gradient of its own colour.
    // LowPan Shells: "fluent" = os ícones Fluent da janela de configurações do Windows 11, soltos (sem placa),
    // na cor do texto. Arquivos em assets/icons/fluent-iris/<glifo>.svg; glifo sem arquivo → Material solto.
    readonly property string pack: String(Config.options?.iris?.appearance?.icons?.style ?? "fluent")
    readonly property bool tiled: root.pack === "tile"
    readonly property bool fluent: root.pack === "fluent"
    readonly property string plate: String(Config.options?.iris?.appearance?.icons?.plate ?? "black")
    readonly property color tileTop: root.plate === "white" ? IrisStyle.plateWhiteTop
        : root.plate === "tint" ? IrisStyle.tileTop(root.tint)
        : root.plate === "surface" ? Qt.lighter(IrisStyle.surfaceHighestOpaque, 1.7)
        : IrisStyle.plateBlackTop
    readonly property color tileBase: root.plate === "white" ? IrisStyle.plateWhiteBase
        : root.plate === "tint" ? root.tint
        : root.plate === "surface" ? IrisStyle.surfaceHighestOpaque
        : IrisStyle.plateBlackBase

    radius: IrisStyle.iconRadius(width)
    color: "transparent"
    gradient: root.fluent ? null : plateGradient
    Gradient {
        id: plateGradient
        GradientStop { position: 0; color: root.tiled ? root.tileTop : IrisStyle.tileTop(root.tint) }
        GradientStop { position: 1; color: root.tiled ? root.tileBase : root.tint }
    }
    Kirigami.Icon {
        id: fluentIcon
        anchors.centerIn: parent
        visible: root.fluent && fluentIcon.valid
        width: Math.round(root.width * 0.86)
        height: width
        source: root.fluent && root.glyph !== "" ? `${Directories.assetsPath}/icons/fluent-iris/${root.glyph}.svg` : ""
        fallback: ""
        roundToIconSize: false
        isMask: true
        color: IrisStyle.text
    }
    MaterialSymbol {
        visible: !fluentIcon.visible
        anchors.centerIn: parent
        text: root.glyph
        fill: root.fluent ? 0 : 1
        iconSize: Math.round(root.width * (root.fluent ? 0.8 : root.glyphShare))
        color: root.fluent ? IrisStyle.text : root.tiled && root.plate !== "tint" ? root.tint : IrisStyle.onTint
        glyphGradient: root.tiled
    }
}
