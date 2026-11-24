import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.dashboard

ContentPage {
    id: root
    settingsPageIndex: 16
    settingsPageName: Translation.tr("Dashboard")

    property string activeSection: "general"

    SettingsCardSection {
        expanded: true
        icon: "info"
        title: Translation.tr("Not Active")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("The dashboard only applies when using the Material (ii) panel style. Go to Modules → Panel Style to switch.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
    }

}
