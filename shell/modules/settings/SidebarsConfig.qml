import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    settingsPageIndex: 23
    settingsPageName: Translation.tr("Sidebars")


    property string activeSection: "general"
    property string pendingProfileAvatarPath: ""

    function activateSettingsSearchSection(section: string): bool {
        const normalized = String(section ?? "").trim().toLowerCase()
        const aliases = ({
            general: "general",
            left: "left",
            right: "right",
            media: "media",
            open: "open",
            opening: "open"
        })
        const target = aliases[normalized]
        if (!target)
            return false
        root.activeSection = target
        return true
    }

    function openAccountSettings(): void {
        AppLauncher.launch("manageUser")
    }

    Process {
        id: setProfileAvatarProcess
        command: [Quickshell.shellPath("scripts/accounts/set-avatar.sh"), root.pendingProfileAvatarPath]
        onExited: exitCode => {
            if (exitCode === 0)
                Directories.userAvatarRevision++
            root.pendingProfileAvatarPath = ""
        }
    }

    SettingsTaskNavigator {
        icon: "side_navigation"
        title: Translation.tr("Sidebars")
        description: Translation.tr("Configure the sidebars in focused views: layout, widgets, media panels and edge opening behavior.")
        summary: Translation.tr("General \u00b7 Left \u00b7 Right \u00b7 Media \u00b7 Opening")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("General"), icon: "tune", value: "general" },
            { displayName: Translation.tr("Left sidebar"), icon: "first_page", value: "left" },
            { displayName: Translation.tr("Right sidebar"), icon: "last_page", value: "right" },
            { displayName: Translation.tr("Media & content"), icon: "music_note", value: "media" },
            { displayName: Translation.tr("Opening"), icon: "swipe", value: "open" }
        ]
    }

}
