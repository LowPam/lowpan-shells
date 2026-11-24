import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    settingsPageIndex: 5
    settingsPageName: Translation.tr("Panels")

    property string activeSection: "control"

    function activateSettingsSearchSection(section: string): bool {
        const label = String(section || "").toLowerCase().trim()
        const sections = {
            "floating tools (super+g)": "tools",
            "visual effects": "tools",
            "alt-tab switcher (material ii)": "tools",
            "notifications": "notifications",
            "control panel": "control",
            "widgets": "widgets",
            "overview": "overview"
        }
        const target = sections[label] ?? ""
        if (!target)
            return false
        root.activeSection = target
        return true
    }

    SettingsTaskNavigator {
        icon: "bottom_app_bar"
        title: Translation.tr("Panels")
        description: Translation.tr("Configure each shell surface in context instead of mixing control-panel, overview, notification and floating-tool options in one stack.")
        summary: Translation.tr("Control panel · overview · notifications · widgets · tools")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Control"), icon: "tune", value: "control" },
            { displayName: Translation.tr("Overview"), icon: "overview_key", value: "overview" },
            { displayName: Translation.tr("Notifications"), icon: "notifications", value: "notifications" },
            { displayName: Translation.tr("Widgets"), icon: "widgets", value: "widgets" },
            { displayName: Translation.tr("Tools"), icon: "dashboard_customize", value: "tools" }
        ]
    }

    function floatingToolsEnabled(): bool {
        return (Config.options?.enabledPanels ?? []).includes("iiOverlay")
    }

    function setFloatingToolsEnabled(enabled: bool): void {
        const panels = [...(Config.options?.enabledPanels ?? [])]
        const index = panels.indexOf("iiOverlay")
        if (enabled && index === -1)
            panels.push("iiOverlay")
        else if (!enabled && index !== -1)
            panels.splice(index, 1)
        Config.setNestedValue("enabledPanels", panels)
    }

    function openFloatingTools(): void {
        GlobalStates.settingsOverlayOpen = false
        GlobalStates.overlayOpen = true
    }

    function gamePerformanceBackgroundOpacity(): real {
        const localValue = Number(Config.options?.overlay?.gamePerformance?.backgroundOpacity ?? -1)
        const globalValue = Number(Config.options?.overlay?.backgroundOpacity ?? 0.9)
        const value = isFinite(localValue) && localValue >= 0 ? localValue : globalValue
        return Math.max(0, Math.min(1, isFinite(value) ? value : 0.9))
    }

    SettingsTaskLoader {
        requested: root.activeSection === "tools"
        sourceComponent: Component {
    SettingsCardSection {
        settingsTaskSection: "tools"
        expanded: true
        icon: "keyboard_tab"
        title: Translation.tr("Alt+Tab")

        SettingsGroup {
            ConfigSelectionArray {
                options: [
                    { displayName: Translation.tr("Niri's Recent Windows"), icon: "view_carousel", value: "niri" },
                    { displayName: Translation.tr("LowPan switcher"), icon: "keyboard_tab", value: "inir" }
                ]
                currentValue: NiriKeybinds.altTabSource
                onSelected: newValue => NiriKeybinds.setAltTabSource(newValue)
            }
            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: NiriKeybinds.altTabSource === "custom"
                    ? Translation.tr("Alt+Tab is bound in your own Niri binds. Choosing here takes it over; your line stays as it is.")
                    : Translation.tr("Which window switcher Alt+Tab opens. Niri's shows live previews of every window; LowPan's follows your panel style.")
            }
        }
    }
        }
    }

    SettingsTaskLoader {
        requested: root.activeSection === "tools"
        sourceComponent: Component {
    SettingsCardSection {
        settingsTaskSection: "tools"
        expanded: true
        icon: "dashboard_customize"
        title: Translation.tr("Floating tools (Super+G)")

        SettingsGroup {
            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("Floating image and widgets panel (Super+G)")
            }

            SettingsSwitch {
                buttonIcon: "dashboard_customize"
                text: Translation.tr("Enable")
                checked: root.floatingToolsEnabled()
                onCheckedChanged: root.setFloatingToolsEnabled(checked)
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: root.floatingToolsEnabled()
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open")
                onClicked: root.openFloatingTools()
            }

            ContentSubsection {
                title: Translation.tr("Background & dim")

                SettingsSwitch {
                    buttonIcon: "water"
                    text: Translation.tr("Darken screen behind overlay")
                    checked: Config.options?.overlay?.darkenScreen ?? false
                    onCheckedChanged: Config.setNestedValue("overlay.darkenScreen", checked)
                    StyledToolTip {
                        text: Translation.tr("Add a dark scrim behind overlay panels for better visibility")
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Overlay scrim dim (%)")
                    value: Config.options?.overlay?.scrimDim ?? 30
                    from: 0
                    to: 100
                    stepSize: 5
                    enabled: Config.options?.overlay?.darkenScreen ?? false
                    onValueChanged: Config.setNestedValue("overlay.scrimDim", value)
                    StyledToolTip {
                        text: Translation.tr("How dark the background scrim should be")
                    }
                }

                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Overlay background opacity (%)")
                    value: Math.round((Config.options?.overlay?.backgroundOpacity ?? 0.9) * 100)
                    from: 20
                    to: 100
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("overlay.backgroundOpacity", value / 100)
                    StyledToolTip {
                        text: Translation.tr("Opacity of the overlay panel background")
                    }
                }

                ConfigSpinBox {
                    icon: "monitor_heart"
                    text: Translation.tr("Game Performance background opacity (%)")
                    value: Math.round(root.gamePerformanceBackgroundOpacity() * 100)
                    from: 0
                    to: 100
                    stepSize: 5
                    enabled: !(Config.options?.overlay?.gamePerformance?.transparentBackground ?? false)
                    onValueChanged: Config.setNestedValue(
                        "overlay.gamePerformance.backgroundOpacity", value / 100)
                    StyledToolTip {
                        text: Translation.tr("Opacity of the Game Performance panel; set 0 for a transparent readout")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "opacity"
                    text: Translation.tr("Transparent Game Performance background")
                    checked: Config.options?.overlay?.gamePerformance?.transparentBackground ?? false
                    onCheckedChanged: Config.setNestedValue(
                        "overlay.gamePerformance.transparentBackground", checked)
                    StyledToolTip {
                        text: Translation.tr("Set panel opacity to 0%; metrics remain visible")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Animations")

                SettingsSwitch {
                    buttonIcon: "movie"
                    text: Translation.tr("Enable opening zoom animation")
                    checked: Config.options?.overlay?.openingZoomAnimation ?? true
                    onCheckedChanged: Config.setNestedValue("overlay.openingZoomAnimation", checked)
                    StyledToolTip {
                        text: Translation.tr("Animate overlay panels with a zoom effect when opening")
                    }
                }

                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Overlay animation duration (ms)")
                    value: Config.options?.overlay?.animationDurationMs ?? 180
                    from: 0
                    to: 1000
                    stepSize: 20
                    onValueChanged: Config.setNestedValue("overlay.animationDurationMs", value)
                    StyledToolTip {
                        text: Translation.tr("Duration of overlay open/close animations")
                    }
                }

                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Background dim animation (ms)")
                    value: Config.options?.overlay?.scrimAnimationDurationMs ?? 140
                    from: 0
                    to: 1000
                    stepSize: 20
                    onValueChanged: Config.setNestedValue("overlay.scrimAnimationDurationMs", value)
                    StyledToolTip {
                        text: Translation.tr("Duration of the background scrim fade animation")
                    }
                }
            }
        }
    }
        }
    }

    // ── Shell Desaturation Effect ───────────────────────────────────────
    SettingsTaskLoader {
        requested: root.activeSection === "tools"
        sourceComponent: Component {
    SettingsCardSection {
        settingsTaskSection: "tools"
        expanded: false
        icon: "filter_b_and_w"
        title: Translation.tr("Visual Effects")

        readonly property var _desat: Config.options?.appearance?.desaturation ?? ({})
        function _setDesat(key: string, val): void {
            Config.setNestedValue("appearance.desaturation." + key, val)
        }

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "filter_b_and_w"
                text: Translation.tr("Desaturation effect")
                checked: Boolean(Config.options?.appearance?.desaturation?.enable)
                onCheckedChanged: Config.setNestedValue("appearance.desaturation.enable", checked)
                StyledToolTip {
                    text: Translation.tr("Apply a grayscale/dimmed effect to shell components")
                }
            }

            SettingsDivider {}

            ConfigRow {
                enabled: Boolean(Config.options?.appearance?.desaturation?.enable)
                uniform: true
                ConfigSpinBox {
                    icon: "invert_colors"
                    text: Translation.tr("Saturation %")
                    value: Math.round((Config.options?.appearance?.desaturation?.saturation ?? -0.7) * -100)
                    from: 0
                    to: 100
                    stepSize: 10
                    onValueChanged: Config.setNestedValue("appearance.desaturation.saturation", -value / 100)
                    StyledToolTip {
                        text: Translation.tr("Amount of color to remove (0 = normal, 100 = grayscale)")
                    }
                }
                ConfigSpinBox {
                    icon: "brightness_6"
                    text: Translation.tr("Dim %")
                    value: Math.round((Config.options?.appearance?.desaturation?.brightness ?? -0.15) * -100)
                    from: 0
                    to: 50
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("appearance.desaturation.brightness", -value / 100)
                    StyledToolTip {
                        text: Translation.tr("Amount of brightness reduction (0 = normal)")
                    }
                }
            }

            SettingsDivider {}

            // Scope selector
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 8

                StyledText {
                    text: Translation.tr("Apply to")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Boolean(Config.options?.appearance?.desaturation?.enable)
                        ? Appearance.colors.colOnSurface
                        : Appearance.colors.colSubtext
                }

                ButtonGroup {
                    enabled: Boolean(Config.options?.appearance?.desaturation?.enable)
                    uniformCellSizes: true
                    spacing: 0

                    SelectionGroupButton {
                        leftmost: true
                        buttonText: Translation.tr("All")
                        toggled: (Config.options?.appearance?.desaturation?.scope ?? "all") === "all"
                        onClicked: Config.setNestedValue("appearance.desaturation.scope", "all")
                    }
                    SelectionGroupButton {
                        buttonText: Translation.tr("Panels only")
                        toggled: (Config.options?.appearance?.desaturation?.scope ?? "all") === "panels"
                        onClicked: Config.setNestedValue("appearance.desaturation.scope", "panels")
                    }
                    SelectionGroupButton {
                        rightmost: true
                        buttonText: Translation.tr("Custom")
                        toggled: (Config.options?.appearance?.desaturation?.scope ?? "all") === "custom"
                        onClicked: Config.setNestedValue("appearance.desaturation.scope", "custom")
                    }
                }
            }

            // Custom scope toggles
            ColumnLayout {
                visible: (Config.options?.appearance?.desaturation?.scope ?? "all") === "custom"
                enabled: Boolean(Config.options?.appearance?.desaturation?.enable)
                Layout.fillWidth: true
                spacing: 0

                SettingsSwitch {
                    buttonIcon: "toolbar"
                    text: Translation.tr("Bar")
                    checked: Config.options?.appearance?.desaturation?.bar ?? true
                    onCheckedChanged: Config.setNestedValue("appearance.desaturation.bar", checked)
                }
                SettingsSwitch {
                    buttonIcon: "dock_to_bottom"
                    text: Translation.tr("Dock")
                    checked: Config.options?.appearance?.desaturation?.dock ?? true
                    onCheckedChanged: Config.setNestedValue("appearance.desaturation.dock", checked)
                }
                SettingsSwitch {
                    buttonIcon: "view_sidebar"
                    text: Translation.tr("Sidebars")
                    checked: Config.options?.appearance?.desaturation?.sidebars ?? true
                    onCheckedChanged: Config.setNestedValue("appearance.desaturation.sidebars", checked)
                }
                SettingsSwitch {
                    buttonIcon: "layers"
                    text: Translation.tr("Overlays")
                    checked: Config.options?.appearance?.desaturation?.overlays ?? true
                    onCheckedChanged: Config.setNestedValue("appearance.desaturation.overlays", checked)
                }
                SettingsSwitch {
                    buttonIcon: "picture_in_picture"
                    text: Translation.tr("Popups")
                    checked: Config.options?.appearance?.desaturation?.popups ?? true
                    onCheckedChanged: Config.setNestedValue("appearance.desaturation.popups", checked)
                }
            }
        }
    }
        }
    }

}
