import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    settingsPageIndex: 2
    settingsPageName: Translation.tr("Bar")

    property string activeSection: "appearance"
    property int _taskLoadingCount: 0

    function activateSettingsSearchSection(section: string): bool {
        const parts = String(section || "").toLowerCase().split(/[·›]/)
        const label = parts[parts.length - 1].trim()
        const sections = {
            "appearance & layout": "appearance",
            "sizing & surface": "appearance",
            "m3 bar": "m3",
            "islands options": "islands",
            "audio spectrum": "spectrum",
            "behavior & clock": "behavior",
            "modules": "modules",
            "bar module layout": "modules",
            "resources": "modules",
            "media": "modules",
            "workspaces": "modules",
            "system tray": "modules",
            "utility buttons": "modules",
            "notifications": "modules"
        }
        const target = sections[label] ?? ""
        if (!target)
            return false
        root.activeSection = target
        return true
    }

    component LazySection: Loader {
        id: sectionLoader
        property bool requested: false
        property bool resident: false
        property bool _countedLoading: false

        Layout.fillWidth: true
        asynchronous: false
        active: resident
        visible: requested && status !== Loader.Null
        enabled: requested && status === Loader.Ready && opacity > 0.99
        opacity: requested && status === Loader.Ready ? 1 : 0
        Layout.preferredHeight: requested && status === Loader.Ready && item ? item.implicitHeight : 0

        transform: Translate {
            y: sectionLoader.requested && sectionLoader.status === Loader.Ready ? 0 : 4
            Behavior on y {
                enabled: Appearance.animationsEnabled && !SettingsMaterialPreset.unified
                NumberAnimation {
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        Behavior on opacity {
            enabled: Appearance.animationsEnabled && !SettingsMaterialPreset.unified
            NumberAnimation {
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }

        function syncLoadingState(): void {
            const shouldCount = requested && status === Loader.Loading
            if (shouldCount === _countedLoading)
                return
            root._taskLoadingCount = Math.max(0, root._taskLoadingCount + (shouldCount ? 1 : -1))
            _countedLoading = shouldCount
        }

        onRequestedChanged: {
            if (requested) {
                unloadDelay.stop()
                resident = true
            } else if (SettingsMaterialPreset.unified) {
                unloadDelay.stop()
            } else if (status === Loader.Ready) {
                unloadDelay.restart()
            } else {
                unloadDelay.stop()
                resident = false
            }
            syncLoadingState()
        }
        onStatusChanged: syncLoadingState()
        Component.onCompleted: {
            if (requested)
                resident = true
            syncLoadingState()
        }
        Component.onDestruction: {
            if (_countedLoading)
                root._taskLoadingCount = Math.max(0, root._taskLoadingCount - 1)
        }

        Timer {
            id: unloadDelay
            interval: 600
            repeat: false
            onTriggered: parent.resident = false
        }
    }

    SettingsTaskNavigator {
        icon: "toolbar"
        title: Translation.tr("Bar")
        description: Translation.tr("Position and sizing, the bar surface styles, and the widgets and modules that live in the bar.")
        summary: Translation.tr("Shape · M3 · Islands · Spectrum · Behavior · Modules")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Shape & position"), icon: "style", value: "appearance" },
            { displayName: Translation.tr("M3 bar"), icon: "category", value: "m3",
              dimmed: (Config.options?.bar?.appearanceStyle ?? "classic") !== "m3" },
            { displayName: Translation.tr("Islands"), icon: "linear_scale", value: "islands",
              dimmed: (Config.options?.bar?.appearanceStyle ?? "classic") !== "islands" },
            { displayName: Translation.tr("Audio spectrum"), icon: "graphic_eq", value: "spectrum" },
            { displayName: Translation.tr("Behavior & clock"), icon: "visibility", value: "behavior" },
            { displayName: Translation.tr("Modules"), icon: "widgets", value: "modules" }
        ]
    }

    SettingsTaskLoadingState {
        loading: root._taskLoadingCount > 0
        text: Translation.tr("Loading section…")
    }
    property bool m3ControlsReady: false
    property bool spectrumControlsReady: false
    Component.onCompleted: Qt.callLater(() => {
        root.m3ControlsReady = true
        root.spectrumControlsReady = true
    })

    function setM3Value(path, value): void {
        if (root.m3ControlsReady)
            Config.setNestedValue(path, value)
    }

    function setM3Values(values): void {
        if (root.m3ControlsReady)
            Config.setNestedValues(values)
    }

    // Conflict detection helpers
    readonly property bool isCardStyle: Config.options?.bar?.cornerStyle === 3
    readonly property bool isHugStyle: Config.options?.bar?.cornerStyle === 0
    readonly property bool isFloatStyle: Config.options?.bar?.cornerStyle === 1
    readonly property bool isRectStyle: Config.options?.bar?.cornerStyle === 2
    readonly property bool isGlobalCards: Config.options?.dock?.cardStyle && Config.options?.sidebar?.cardStyle && isCardStyle
    readonly property bool hasVignette: Config.options?.bar?.vignette?.enabled ?? false
    readonly property bool isAutoHide: Config.options?.bar?.autoHide?.enable ?? false
    readonly property bool isBorderless: Config.options?.bar?.borderless ?? false
    readonly property bool showBackground: Config.options?.bar?.showBackground ?? true
    readonly property string barAppearance: Config.options?.bar?.appearanceStyle ?? "classic"
    readonly property bool spectrumEnabled: root.barAppearance === "pill"
        ? (Config.options?.bar?.pill?.musicViz ?? false)
        : (Config.options?.bar?.visualizer?.enable ?? false)
    readonly property color workspaceThemeIndicatorColor: Appearance.zzzEverywhere ? Appearance.zzz.accentSoft
        : Appearance.angelEverywhere ? Appearance.angel.colPrimary : Appearance.colors.colPrimary
    readonly property color workspaceIndicatorPreviewColor: {
        const saved = Config.options?.bar?.workspaces?.indicatorColor ?? ""
        if (saved.length === 0)
            return root.workspaceThemeIndicatorColor
        const parsed = Qt.color(saved)
        return parsed.valid ? parsed : root.workspaceThemeIndicatorColor
    }

    ColorDialog {
        id: workspaceIndicatorColorDialog
        selectedColor: root.workspaceIndicatorPreviewColor
        onAccepted: Config.setNestedValue("bar.workspaces.indicatorColor", selectedColor.toString())
    }

    SettingsNativeDialogGuard {
        dialog: workspaceIndicatorColorDialog
        dialogKey: "bar-workspace-indicator-color"
    }

    function setSpectrumEnabled(enabled): void {
        if (!root.spectrumControlsReady)
            return
        Config.setNestedValue(root.barAppearance === "pill"
            ? "bar.pill.musicViz" : "bar.visualizer.enable", enabled)
    }

    function setSpectrumValue(path, value): void {
        if (root.spectrumControlsReady)
            Config.setNestedValue(path, value)
    }

    function resetSpectrumDefaults(): void {
        if (!root.spectrumControlsReady)
            return
        Config.setNestedValues({
            "bar.visualizer.enable": false,
            "bar.visualizer.multiMonitorMode": "primary",
            "bar.visualizer.type": "bars",
            "bar.visualizer.height": 0.6,
            "bar.visualizer.opacity": 0.35,
            "bar.visualizer.barsOrigin": "bottom",
            "bar.visualizer.density": 12,
            "bar.visualizer.gap": 2,
            "bar.visualizer.smoothing": 2,
            "bar.visualizer.waveMode": "fill",
            "bar.visualizer.lineWidth": 2,
            "bar.visualizer.edgeInset": 6,
            "bar.visualizer.edgeSoftness": 36,
            "bar.visualizer.frequencyProfile": "flat",
            "bar.visualizer.accentStrength": 70,
            "bar.visualizer.organicFit": "auto",
            "bar.visualizer.organicSensitivity": 42,
            "bar.visualizer.organicPulse": 55,
            "bar.visualizer.organicMotionSpeed": 80,
            "bar.visualizer.organicIdleMotion": 0,
            "bar.visualizer.organicGlow": 25,
            "bar.visualizer.organicBaseRadius": 36,
            "bar.visualizer.pillWingMode": "bounded",
            "bar.visualizer.pillWingLength": 180,
            "bar.visualizer.pillWingGap": 12,
            "bar.visualizer.pillScreenPadding": 24,
            "bar.visualizer.pillUnderlap": 28,
            "bar.visualizer.pillEdgeFade": 92,
            "bar.pill.musicViz": false,
        })
    }

    // Global style detection
    readonly property string currentGlobalStyle: Config.options?.appearance?.globalStyle ?? "material"
    readonly property bool isAurora: currentGlobalStyle === "aurora"
    readonly property bool isInir: currentGlobalStyle === "inir"
    readonly property bool isCards: currentGlobalStyle === "cards"
    readonly property bool isMaterial: currentGlobalStyle === "material"
    readonly property bool isAngel: currentGlobalStyle === "angel"

    // Corner style only shapes the classic bar surface; the other appearances draw
    // their own (islands capsules, scenic scrim, frame outline, pill).
    readonly property bool cornerStyleApplies: (Config.options?.bar?.appearanceStyle ?? "classic") === "classic"
    readonly property bool stockHorizontalLayoutActive: !(Config.options?.bar?.vertical ?? false)
        && !["m3", "pill"].includes(Config.options?.bar?.appearanceStyle ?? "classic")
    readonly property bool taskbarModeSupported: (Config.options?.bar?.vertical ?? false)
        || root.stockHorizontalLayoutActive

    function detectM3LayoutPreset(): string {
        const left = JSON.stringify(Config.options?.bar?.m3?.layouts?.leftLayout ?? [])
        const middle = JSON.stringify(Config.options?.bar?.m3?.layouts?.middleLayout ?? [])
        const right = JSON.stringify(Config.options?.bar?.m3?.layouts?.rightLayout ?? [])
        if (left === JSON.stringify(["leftSidebarButton", "media", "workspaces"])
                && middle === JSON.stringify(["docktoPanel"])
                && right === JSON.stringify(["utilButtons", "weatherBar", "clockWidget", "systemIcons", "rightSidebarButton"]))
            return "compact"
        if (left === JSON.stringify(["media", "workspaces"])
                && middle === JSON.stringify(["visualizer", "docktoPanel", "visualizer"])
                && right === JSON.stringify(["utilButtons", "systemIcons", "weatherBar", "clockWidget"]))
            return "showcase"
        if (left === JSON.stringify(["leftSidebarButton", "workspaces", "activeWindow"])
                && middle === JSON.stringify(["docktoPanel"])
                && right === JSON.stringify(["resources", "networkSpeed", "updatesCount", "clockWidget", "powerButton"]))
            return "information"
        return "custom"
    }

    readonly property string m3LayoutPreset: {
        const stored = Config.options?.bar?.m3?.layoutMode ?? "auto"
        if (stored === "custom")
            return "custom"
        const detected = root.detectM3LayoutPreset()
        if (["compact", "showcase", "information"].includes(stored))
            return detected === stored ? stored : detected
        return detected
    }

    function currentM3Layouts(): var {
        return {
            left: Array.from(Config.options?.bar?.m3?.layouts?.leftLayout ?? []),
            middle: Array.from(Config.options?.bar?.m3?.layouts?.middleLayout ?? []),
            right: Array.from(Config.options?.bar?.m3?.layouts?.rightLayout ?? [])
        }
    }

    function moveM3Widget(sourceSection, sourceIndex, id, targetSection, targetIndex): bool {
        const layouts = root.currentM3Layouts()
        if (!layouts[sourceSection] || !layouts[targetSection])
            return false

        const source = layouts[sourceSection].slice()
        if (sourceIndex < 0 || sourceIndex >= source.length)
            return false
        const moved = source.splice(sourceIndex, 1)[0]
        const target = sourceSection === targetSection ? source : layouts[targetSection].slice()
        let insertAt = targetIndex
        if (sourceSection === targetSection && insertAt > sourceIndex)
            insertAt--
        insertAt = Math.max(0, Math.min(insertAt, target.length))
        target.splice(insertAt, 0, moved)
        layouts[sourceSection] = sourceSection === targetSection ? target : source
        layouts[targetSection] = target

        root.setM3Values({
            "bar.m3.layoutMode": "custom",
            "bar.m3.customLayoutSaved": true,
            "bar.m3.layouts.leftLayout": layouts.left,
            "bar.m3.layouts.middleLayout": layouts.middle,
            "bar.m3.layouts.rightLayout": layouts.right,
            "bar.m3.customLayouts.leftLayout": layouts.left,
            "bar.m3.customLayouts.middleLayout": layouts.middle,
            "bar.m3.customLayouts.rightLayout": layouts.right
        })
        return true
    }

    function updateM3CustomLayout(side, list): void {
        if (!root.m3ControlsReady) return
        const next = Array.from(list ?? [])
        const activePath = "bar.m3.layouts." + side + "Layout"
        const customPath = "bar.m3.customLayouts." + side + "Layout"
        root.setM3Values({
            "bar.m3.layoutMode": "custom",
            "bar.m3.customLayoutSaved": true,
            [activePath]: next,
            [customPath]: next
        })
    }

    function applyM3LayoutPreset(value): void {
        if (!root.m3ControlsReady) return

        if (value === "custom") {
            const saved = Config.options?.bar?.m3?.customLayoutSaved ?? false
            if (saved) {
                root.setM3Values({
                    "bar.m3.layoutMode": "custom",
                    "bar.m3.layouts.leftLayout": Array.from(Config.options?.bar?.m3?.customLayouts?.leftLayout ?? []),
                    "bar.m3.layouts.middleLayout": Array.from(Config.options?.bar?.m3?.customLayouts?.middleLayout ?? []),
                    "bar.m3.layouts.rightLayout": Array.from(Config.options?.bar?.m3?.customLayouts?.rightLayout ?? [])
                })
            } else {
                const current = root.currentM3Layouts()
                root.setM3Values({
                    "bar.m3.layoutMode": "custom",
                    "bar.m3.customLayoutSaved": true,
                    "bar.m3.customLayouts.leftLayout": current.left,
                    "bar.m3.customLayouts.middleLayout": current.middle,
                    "bar.m3.customLayouts.rightLayout": current.right
                })
            }
            return
        }

        const updates = ({ "bar.m3.layoutMode": value })
        if (root.m3LayoutPreset === "custom" || root.detectM3LayoutPreset() === "custom") {
            const current = root.currentM3Layouts()
            updates["bar.m3.customLayoutSaved"] = true
            updates["bar.m3.customLayouts.leftLayout"] = current.left
            updates["bar.m3.customLayouts.middleLayout"] = current.middle
            updates["bar.m3.customLayouts.rightLayout"] = current.right
        }

        if (value === "compact") {
            updates["bar.m3.layouts.leftLayout"] = ["leftSidebarButton", "media", "workspaces"]
            updates["bar.m3.layouts.middleLayout"] = ["docktoPanel"]
            updates["bar.m3.layouts.rightLayout"] = ["utilButtons", "weatherBar", "clockWidget", "systemIcons", "rightSidebarButton"]
        } else if (value === "showcase") {
            updates["bar.m3.layouts.leftLayout"] = ["media", "workspaces"]
            updates["bar.m3.layouts.middleLayout"] = ["visualizer", "docktoPanel", "visualizer"]
            updates["bar.m3.layouts.rightLayout"] = ["utilButtons", "systemIcons", "weatherBar", "clockWidget"]
        } else if (value === "information") {
            updates["bar.m3.layouts.leftLayout"] = ["leftSidebarButton", "workspaces", "activeWindow"]
            updates["bar.m3.layouts.middleLayout"] = ["docktoPanel"]
            updates["bar.m3.layouts.rightLayout"] = ["resources", "networkSpeed", "updatesCount", "clockWidget", "powerButton"]
        }
        root.setM3Values(updates)
    }

    readonly property var m3Widgets: [
        { id: "leftSidebarButton", name: Translation.tr("Left Sidebar Button"), icon: "left_panel_open",
            description: Translation.tr("Click: Left Sidebar") },
        { id: "rightSidebarButton", name: Translation.tr("Right Sidebar Button"), icon: "right_panel_open",
            description: Translation.tr("Click: Right Sidebar") },
        { id: "workspaces", name: Translation.tr("Workspaces"), icon: "steppers" },
        { id: "weatherBar", name: Translation.tr("Weather"), icon: "flare" },
        { id: "media", name: Translation.tr("Media"), icon: "music_note" },
        { id: "resources", name: Translation.tr("Resources"), icon: "monitoring" },
        { id: "systemIcons", name: Translation.tr("System Icons"), icon: "info" },
        { id: "networkSpeed", name: Translation.tr("Network Speed"), icon: "network_check" },
        { id: "clockWidget", name: Translation.tr("Clock"), icon: "schedule" },
        { id: "utilButtons", name: Translation.tr("Utility Buttons"), icon: "toggle_on" },
        { id: "sysTray", name: Translation.tr("Tray"), icon: "inbox" },
        { id: "batteryIndicator", name: Translation.tr("Battery"), icon: "battery_android_frame_full" },
        { id: "activeWindow", name: Translation.tr("Active Window"), icon: "subtitles" },
        { id: "powerButton", name: Translation.tr("Power Button"), icon: "power_settings_new" },
        { id: "updatesCount", name: Translation.tr("Updates"), icon: "deployed_code_update" },
        { id: "docktoPanel", name: Translation.tr("Dock to Panel"), icon: "apps" },
        { id: "visualizer", name: Translation.tr("Visualizer"), icon: "graphic_eq" },
        { id: "hyprlandXkbIndicator", name: Translation.tr("Keyboard Layout"), icon: "keyboard" },
        { id: "divisor", name: Translation.tr("Divider"), icon: "horizontal_distribute" },
        { id: "notificationUnreadCount", name: Translation.tr("Unread Notifications"), icon: "notifications",
            description: Translation.tr("Click: Right Sidebar") }
    ]

    function m3WidgetName(id): string {
        return root.m3Widgets.find(widget => widget.id === id)?.name ?? id
    }

    function m3WidgetDescription(id): string {
        return root.m3Widgets.find(widget => widget.id === id)?.description ?? ""
    }

    function m3WidgetIcon(id): string {
        return root.m3Widgets.find(widget => widget.id === id)?.icon ?? "widgets"
    }

    function m3WidgetHint(id): string {
        return Translation.tr("Add %1 to the Left, Center or Right layout below to enable these controls.")
            .arg(root.m3WidgetName(id))
    }

    readonly property var activeM3Widgets: [
        ...(Config.options?.bar?.m3?.layouts?.leftLayout ?? []),
        ...(Config.options?.bar?.m3?.layouts?.middleLayout ?? []),
        ...(Config.options?.bar?.m3?.layouts?.rightLayout ?? [])
    ]

    function m3HasWidget(id): bool {
        return root.activeM3Widgets.includes(id)
    }

    function availableM3Widgets(): var {
        const multipleAllowed = ["visualizer", "divisor"]
        return root.m3Widgets.filter(widget =>
            !root.activeM3Widgets.includes(widget.id) || multipleAllowed.includes(widget.id))
    }

    // Corner style compatibility per global style
    readonly property bool hugNeedsBackground: isHugStyle && !showBackground
    readonly property bool hugOnAurora: isHugStyle && isAurora
    readonly property bool cardOnNonCards: isCardStyle && !isCards

    SettingsCardSection {
        expanded: true
        icon: "info"
        title: Translation.tr("Not Active")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("These settings only apply when using the Material (ii) panel style. Go to Modules → Panel Style to switch.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
    }

}
