pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string killDialogQmlPath: FileUtils.trimFileProtocol(Quickshell.shellPath("killDialog.qml"))

    function load() {
        // dummy to force init
    }

    // Defer conflict checks to avoid process spawns during the critical shell startup window
    Timer {
        id: conflictCheckDelay
        interval: 1500
        repeat: false
        onTriggered: {
            pidofTraysProc.running = true
            pidofNotifsProc.running = true
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                conflictCheckDelay.restart()
            }
        }
    }

    Component.onCompleted: {
        if (Config.ready) {
            conflictCheckDelay.restart()
        }
    }

    // LowPan Shells: no Plasma o kded6 é essencial (rede, BT, teclado, bandeja SNI, powerdevil...).
    // Nunca matar nada nem abrir o diálogo de "conflito" numa sessão KDE.
    readonly property bool _isKde: (Quickshell.env("XDG_CURRENT_DESKTOP") ?? "").toUpperCase().indexOf("KDE") >= 0

    function _maybeHandleConflicts(): void {
        if (root._isKde)
            return
        if (pidofTraysProc.running || pidofNotifsProc.running)
            return

        const conflictingTrays = root._traysConflict
        const conflictingNotifications = root._notifsConflict

        var openDialog = false;
        if (conflictingTrays) {
            if (!(Config.options?.conflictKiller?.autoKillTrays ?? false)) openDialog = true;
            else Quickshell.execDetached(["/usr/bin/killall", "kded6"])
        }
        if (conflictingNotifications) {
            if (!(Config.options?.conflictKiller?.autoKillNotificationDaemons ?? false)) openDialog = true;
            else Quickshell.execDetached(["/usr/bin/killall", "mako", "dunst"])
        }
        if (openDialog) {
            Quickshell.execDetached(["/usr/bin/qs", "-p", root.killDialogQmlPath])
        }
    }

    property bool _traysConflict: false
    property bool _notifsConflict: false

    Process {
        id: pidofTraysProc
        command: ["/usr/bin/pidof", "kded6"]
        onExited: (exitCode, exitStatus) => {
            root._traysConflict = (exitCode === 0)
            root._maybeHandleConflicts()
        }
    }

    Process {
        id: pidofNotifsProc
        command: ["/usr/bin/pidof", "mako", "dunst"]
        onExited: (exitCode, exitStatus) => {
            root._notifsConflict = (exitCode === 0)
            root._maybeHandleConflicts()
        }
    }
}
