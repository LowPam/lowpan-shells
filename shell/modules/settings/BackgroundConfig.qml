import qs
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "root:modules/common/functions/parallax.js" as ParallaxMath

ContentPage {
    id: root
    settingsPageIndex: 3
    settingsPageName: Translation.tr("Background")

    property string activeSection: "source"

    readonly property var iiParallax: Config.options?.background?.parallax ?? {}
    readonly property string iiParallaxPreset: ParallaxMath.detectPreset(
        iiParallax.zoom ?? iiParallax.workspaceZoom ?? 1.0,
        iiParallax.workspaceShift ?? 1,
        iiParallax.panelShift ?? iiParallax.sidebarShift ?? 0.15,
        iiParallax.widgetDepth ?? iiParallax.widgetsFactor ?? 1.2
    )

    function setIiParallaxAxis(value: string): void {
        Config.setNestedValue("background.parallax.axis", value)
        Config.setNestedValue("background.parallax.autoVertical", value === "auto")
        Config.setNestedValue("background.parallax.vertical", value === "vertical")
    }

    function applyIiParallaxPreset(presetId: string): void {
        const preset = ParallaxMath.preset(presetId)
        Config.setNestedValue("background.parallax.enable", true)
        Config.setNestedValue("background.parallax.zoom", preset.zoom)
        Config.setNestedValue("background.parallax.workspaceZoom", preset.zoom)
        Config.setNestedValue("background.parallax.workspaceShift", preset.workspaceShift)
        Config.setNestedValue("background.parallax.panelShift", preset.panelShift)
        Config.setNestedValue("background.parallax.widgetDepth", preset.widgetDepth)
        Config.setNestedValue("background.parallax.widgetsFactor", preset.widgetDepth)
    }

    SettingsTaskLoader {
        requested: true
        sourceComponent: Component {
    SettingsCardSection {
        settingsTaskSection: "source"
        expanded: true
        icon: "wallpaper"
        title: Translation.tr("Wallpaper renderer")

        SettingsGroup {
            ConfigSelectionArray {
                currentValue: Config.options?.background?.backend?.provider ?? "awww"
                options: [
                    { displayName: Translation.tr("Standard"), icon: "image", value: "awww" },
                    { displayName: Translation.tr("Interactive web"), icon: "language", value: "web" }
                ]
                onSelected: newValue => Config.setNestedValue("background.backend.provider", newValue)
            }

            StyledText {
                Layout.fillWidth: true
                visible: (Config.options?.background?.backend?.provider ?? "awww") === "awww"
                // LowPan Shells: no KWin o shell desenha o papel de parede sozinho; sem awww não é erro
                readonly property bool kwinNoAwww: CompositorService.isKWin && !AwwwBackend.available
                text: kwinNoAwww
                    ? Translation.tr("On KDE the shell draws the wallpaper itself, with its own transitions: awww is not needed here.")
                    : AwwwBackend.available
                    ? (AwwwBackend.isInternalShaderTransitionType(
                            Config.options?.background?.transition?.type ?? "crossfade")
                        ? Translation.tr("awww remains the static wallpaper renderer. The selected shader runs briefly in-shell during each change, then hands the final image back to awww.")
                        : Translation.tr("awww is active. Static wallpapers are rendered externally with awww-native transitions, while GIF/video and backdrop layers use the internal fallback renderer automatically."))
                    : Translation.tr("awww is the default backend, but the `awww` / `awww-daemon` binaries were not found in PATH. Install them to enable hardware-accelerated wallpaper rendering and transitions. The internal renderer is used as fallback until then.")
                color: !AwwwBackend.available && !kwinNoAwww
                    ? Appearance.colors.colError
                    : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
                opacity: 0.9
            }

            ConfigSpinBox {
                visible: (Config.options?.background?.backend?.provider ?? "awww") === "awww" && AwwwBackend.available
                icon: "speed"
                text: Translation.tr("awww transition FPS")
                value: Config.options?.background?.backend?.awww?.transitionFps ?? 60
                from: 10
                to: 240
                stepSize: 5
                onValueChanged: Config.setNestedValue("background.backend.awww.transitionFps", value)
            }

            ConfigRow {
                visible: (Config.options?.background?.backend?.provider ?? "awww") === "awww" && AwwwBackend.available
                uniform: true

                ConfigSpinBox {
                    icon: "blur_on"
                    text: Translation.tr("Simple step")
                    value: Config.options?.background?.backend?.awww?.simpleStep ?? 5
                    from: 1
                    to: 64
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("background.backend.awww.simpleStep", value)
                }

                ConfigSpinBox {
                    icon: "swipe"
                    text: Translation.tr("Spatial step")
                    value: Config.options?.background?.backend?.awww?.spatialStep ?? 30
                    from: 1
                    to: 128
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("background.backend.awww.spatialStep", value)
                }
            }

            StyledText {
                visible: (Config.options?.background?.backend?.provider ?? "awww") === "web" && !WebWallpaper.available
                Layout.fillWidth: true
                text: WebWallpaper.lastError.length > 0
                    ? Translation.tr("Interactive web wallpapers need Qt 6 WebEngine, LayerShellQt and the Qt QML runner. The standard wallpaper stays available until the web renderer is ready.") + "\n" + WebWallpaper.lastError
                    : Translation.tr("Checking interactive web wallpaper support…")
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }

            ContentSubsection {
                visible: (Config.options?.background?.backend?.provider ?? "awww") === "web"
                title: Translation.tr("Web wallpaper")
                tooltip: Translation.tr("Load a local HTML file or a web URL with JavaScript, WebGL and browser media support")

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: "/path/to/index.html  ·  https://example.com"
                    text: Config.options?.background?.backend?.web?.source ?? ""
                    onEditingFinished: Config.setNestedValue("background.backend.web.source", text.trim())
                }
            }

            SettingsSwitch {
                visible: (Config.options?.background?.backend?.provider ?? "awww") === "web"
                buttonIcon: "sports_esports"
                text: Translation.tr("Interactive mode")
                checked: Config.options?.background?.backend?.web?.interactive ?? false
                onCheckedChanged: Config.setNestedValue("background.backend.web.interactive", checked)
                StyledToolTip {
                    text: Translation.tr("When enabled, the web wallpaper moves to the desktop input layer so games and interactive pages can receive pointer and keyboard input")
                }
            }

            StyledText {
                visible: (Config.options?.background?.backend?.provider ?? "awww") === "web"
                Layout.fillWidth: true
                text: Translation.tr("Passive mode stays behind desktop widgets. Interactive mode takes over the desktop surface while the bar and dock remain above it. The normal wallpaper remains available as a fallback for lock screen, overview and theme colors.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
    }
        }
    }

    SettingsTaskLoader {
        requested: true
        sourceComponent: Component {
    SettingsCardSection {
        settingsTaskSection: "source"
        expanded: false
        icon: "folder"
        title: Translation.tr("Wallpapers folder")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Custom wallpapers directory")
                tooltip: Translation.tr("Leave empty for default ~/Pictures/Wallpapers")

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: "~/Pictures/Wallpapers"
                    text: Config.options?.wallpapers?.directory ?? ""
                    onEditingFinished: Config.setNestedValue("wallpapers.directory", text)
                }
            }
        }
    }
        }
    }

    SettingsTaskLoader {
        requested: true
        sourceComponent: Component {
    SettingsCardSection {
        settingsTaskSection: "source"
        expanded: false
        icon: "shuffle"
        title: Translation.tr("Shuffle wallpapers")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "autorenew"
                text: Translation.tr("Shuffle wallpapers automatically")
                checked: Config.options?.background?.autoWallpaper?.enable ?? false
                onCheckedChanged: Config.setNestedValue("background.autoWallpaper.enable", checked)
                StyledToolTip {
                    text: Translation.tr("Pick a random wallpaper from the folder every few minutes")
                }
            }

            ConfigSpinBox {
                enabled: Config.options?.background?.autoWallpaper?.enable ?? false
                icon: "timer"
                text: Translation.tr("Change every") + ` (${value} ${value === 1 ? Translation.tr("minute") : Translation.tr("minutes")})`
                value: Config.options?.background?.autoWallpaper?.intervalMinutes ?? 30
                from: 1
                to: 1440
                stepSize: 1
                onValueChanged: Config.setNestedValue("background.autoWallpaper.intervalMinutes", value)
                StyledToolTip {
                    text: Translation.tr("How often to pick a new random wallpaper")
                }
            }

            SettingsSwitch {
                enabled: Config.options?.background?.autoWallpaper?.enable ?? false
                buttonIcon: "palette"
                text: Translation.tr("Regenerate theme colors on shuffle")
                checked: Config.options?.background?.autoWallpaper?.generateColors ?? true
                onCheckedChanged: Config.setNestedValue("background.autoWallpaper.generateColors", checked)
                StyledToolTip {
                    text: Translation.tr("When enabled, theme colors are recomputed from the new wallpaper (slower). Disable to only swap the image.")
                }
            }

            ContentSubsection {
                title: Translation.tr("Shuffle folder (optional)")
                tooltip: Translation.tr("Leave empty to shuffle within the current wallpapers folder")

                MaterialTextField {
                    Layout.fillWidth: true
                    enabled: Config.options?.background?.autoWallpaper?.enable ?? false
                    placeholderText: Translation.tr("Use current wallpapers folder")
                    text: Config.options?.background?.autoWallpaper?.folder ?? ""
                    onEditingFinished: Config.setNestedValue("background.autoWallpaper.folder", text)
                }
            }
        }
    }
        }
    }

    // Desktop widget settings moved to DesktopWidgetsConfig.qml (settingsPageIndex: 14)

    SettingsTaskLoader {
        requested: true
        sourceComponent: Component {
    SettingsCardSection {
        settingsTaskSection: "notifications"
        expanded: true
        icon: "notifications"
        title: Translation.tr("Notifications")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "hide_image"
                text: Translation.tr("Hide wallpaper upscale notification")
                checked: Config.options?.background?.hideUpscaleNotification ?? false
                onCheckedChanged: Config.setNestedValue("background.hideUpscaleNotification", checked)
                StyledToolTip {
                    text: Translation.tr("Suppress the notification that appears when a wallpaper has lower resolution than your monitor")
                }
            }
        }
    }
        }
    }
}
