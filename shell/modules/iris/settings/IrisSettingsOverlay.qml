pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.iris.frame
import qs.modules.iris.components
import qs.modules.iris.field as Field

PanelWindow {
    id: root
    visible: GlobalStates.settingsOverlayOpen || body.frame.progress > 0
    IrisOutputHold {
        id: outputHold
        wanted: GlobalStates.focusedScreen
        live: root.visible
    }
    screen: outputHold.output
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    margins {
        left: IrisFrame.band
        right: IrisFrame.band
        top: IrisFrame.band
        bottom: IrisFrame.band
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:iris-settings"
    // LowPan Shells: no KWin a camada Overlay fica acima da tela de captura do Spectacle (só aparecia
    // depois de um clique, que fechava as Configurações). Top fica abaixo das janelas de tela cheia.
    WlrLayershell.layer: GlobalStates.settingsNativeDialogOpen ? WlrLayer.Bottom
        : CompositorService.isKWin ? WlrLayer.Top : WlrLayer.Overlay
    // LowPan Shells: com foco Exclusive o KWin torna esta superfície a "janela ativa"; ao fechar, ele
    // reativa outra janela e o Krohnkite reorganiza os tiles (as janelas trocam de lugar e voltam).
    WlrLayershell.keyboardFocus: GlobalStates.settingsNativeDialogOpen ? WlrKeyboardFocus.None
        : CompositorService.isKWin ? (GlobalStates.irisSettingsWantsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
        : WlrKeyboardFocus.Exclusive
    mask: GlobalStates.settingsOverlayOpen && body.frame.armed ? null : frameRegion
    Region { id: frameRegion; item: body.frame }
    Field.IrisBlurRegion {
        window: root
        shapes: body.frame.blurShapes
        windowWidth: root.width
        windowHeight: root.height
    }

    IrisSettings {
        id: body
        anchors.fill: parent
    }
}
