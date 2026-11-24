import QtQuick
import Quickshell
import qs.modules.iris.style

// LowPan Shells (2026-11-23): o logo do LowPan — o avatar redondo da mascote (assets/images/lowpan/logo.png, recorte
// da ilustração assets/images/lowpan/mascote.png). O desenho original deste componente era o logo do iRiS (anel, ponto
// e satélite), que o NOTICE do iNiR não licencia para derivados (GPL-3 §7(e)); o nome do componente ficou (interno).
// Mesma interface de antes: implicitSize vale; color e orbiting ficam por compatibilidade (o avatar tem as cores dele).
Item {
    id: root
    property real implicitSize: 22 * IrisStyle.density
    property color color: IrisStyle.accent
    property bool orbiting: false
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    Image {
        anchors.fill: parent
        source: Quickshell.shellPath("assets/images/lowpan/logo.png")
        sourceSize.width: Math.ceil(root.implicitSize * 2)
        sourceSize.height: Math.ceil(root.implicitSize * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: false
    }
}
