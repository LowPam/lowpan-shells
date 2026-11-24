import QtQuick
import Quickshell
import qs.services
import qs.modules.iris.style

/**
 * LowPan Shells: as cores dos cantos arredondados que seguem o destaque/realce do shell acompanham o tema com as
 * Configurações fechadas. Carregado pelo shell.qml só no KWin. Ver services/KWinCorners.qml.
 */
Scope {
    Binding { target: KWinCorners; property: "accent"; value: IrisStyle.accent }
    Binding { target: KWinCorners; property: "highlight"; value: IrisStyle.secondaryAccent }
    // A mesma fórmula da "Cena" das bordas do shell (IrisStyle.glassEdgeColour): a luz do papel de parede, clareada (§21.25).
    Binding {
        target: KWinCorners
        property: "scene"
        value: Qt.rgba(IrisStyle.wallpaperLight.r * 0.45 + 0.55, IrisStyle.wallpaperLight.g * 0.45 + 0.55,
            IrisStyle.wallpaperLight.b * 0.45 + 0.55, 1)
    }
    // A linha de contorno do shell (Aparência › Bordas) como aparece na tela: o rim misturado à superfície.
    // Sem linha (bordas Iluminado/Nenhum), o destaque a 45 %. Inativas: metade da força.
    readonly property color rimTone: IrisStyle.rim.a > 0 ? IrisStyle.rim : Qt.rgba(IrisStyle.accent.r, IrisStyle.accent.g, IrisStyle.accent.b, 0.45)
    function over(t: real): color {
        const b = IrisStyle.surfaceOpaque, c = rimTone
        return Qt.rgba(b.r + (c.r - b.r) * t, b.g + (c.g - b.g) * t, b.b + (c.b - b.b) * t, 1)
    }
    Binding { target: KWinCorners; property: "rim"; value: over(rimTone.a) }
    Binding { target: KWinCorners; property: "rimInactive"; value: over(rimTone.a * 0.5) }
    Component.onCompleted: {
        KWinCorners.follow()
        KWinDecoration.follow()  // a sombra da decoração usa as mesmas cores (§21.29)
    }
}
