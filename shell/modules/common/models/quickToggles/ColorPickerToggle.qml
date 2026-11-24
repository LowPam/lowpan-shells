import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Color picker")
    hasStatusText: false
    toggled: false
    icon: "colorize"

    mainAction: () => {
        GlobalStates.sidebarRightOpen = false;
        delayedActionTimer.start();
    }
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: {
            // LowPan Shells (§21.86): `inir colorpicker` usa a mira do KWin no Plasma (§21.84) e o hyprpicker fora dele.
            Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "colorpicker"]);
        }
    }

    tooltipText: Translation.tr("Color picker")
}
