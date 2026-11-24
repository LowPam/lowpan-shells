pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.iris.style

// LowPan Shells: the Control Center's audio expansion, modelled on Plasma's volume applet.
// "Devices" lists every output and input with its own level and mute (a tap on the name makes it the
// default); "Apps" gives each playing stream its own level and mute. Nothing here takes the keyboard:
// a focused shell surface becomes KWin's active window and Krohnkite re-tiles when it closes.
ColumnLayout {
    id: root

    property bool outputs: true
    property bool inputs: true
    // false keeps the plain picker (the Stage volume card already has its own level above it).
    property bool mixer: true
    readonly property bool headings: root.outputs && root.inputs
    readonly property real d: IrisStyle.density
    property string page: "devices"
    spacing: 2 * root.d

    // Device volumes are only live while their nodes are bound; Audio binds just the defaults.
    PwObjectTracker {
        objects: !root.mixer ? [] : (root.outputs ? Audio.outputDevices : []).concat(root.inputs ? Audio.inputDevices : [])
    }

    function setLevel(node, value: real, isSink: bool): void {
        if (!node?.audio) return
        const v = Math.max(0, Math.min(1, value))
        // The default sink goes through Audio so volume protection and the wpctl route fallback still apply.
        if (isSink && node.id === Audio.defaultSink?.id) Audio.setSinkVolume(v)
        else node.audio.volume = v
    }
    function toggleMute(node): void {
        if (node?.audio) node.audio.muted = !node.audio.muted
    }

    IrisSegmented {
        visible: root.mixer && root.outputs
        Layout.fillWidth: true
        Layout.leftMargin: 6 * root.d
        Layout.rightMargin: 6 * root.d
        Layout.bottomMargin: 4 * root.d
        options: [
            { value: "devices", label: Translation.tr("Devices") },
            { value: "apps", label: Translation.tr("Apps") }
        ]
        current: root.page
        onPicked: value => root.page = value
    }

    // One level line: mute glyph, slider, percentage.
    component LevelLine: RowLayout {
        id: line
        property var node: null
        property bool isSink: true
        property string glyph: "volume_up"
        property string mutedGlyph: "volume_off"
        readonly property bool muted: Boolean(line.node?.audio?.muted)
        readonly property real volume: Number(line.node?.audio?.volume ?? 0)
        Layout.fillWidth: true
        spacing: 6 * root.d
        IrisIconButton {
            materialIcon: line.muted ? line.mutedGlyph : line.glyph
            iconSize: Math.round(16 * root.d)
            implicitWidth: Math.round(28 * root.d)
            selected: line.muted
            onClicked: root.toggleMute(line.node)
        }
        IrisSlider {
            Layout.fillWidth: true
            enabled: Boolean(line.node?.audio)
            opacity: line.muted ? 0.5 : 1
            value: Math.max(0, Math.min(1, line.volume))
            onMoved: next => root.setLevel(line.node, next, line.isSink)
        }
        IrisText {
            Layout.minimumWidth: Math.round(38 * root.d)
            horizontalAlignment: Text.AlignRight
            text: Math.round(line.volume * 100) + "%"
            opacity: line.muted ? 0.5 : 1
            role: IrisText.Meta
            font.features: ({ "tnum": 1 })
        }
    }

    // Devices page
    Repeater {
        model: root.page === "devices" || !root.outputs || !root.mixer ? [
            { input: false, title: Translation.tr("Output"), devices: Audio.outputDevices },
            { input: true, title: Translation.tr("Input"), devices: Audio.inputDevices }
        ].filter(group => group.input ? root.inputs : root.outputs) : []
        ColumnLayout {
            id: deviceGroup
            required property var modelData
            Layout.fillWidth: true
            spacing: 2 * root.d
            IrisText {
                visible: root.headings
                Layout.leftMargin: 10 * root.d
                Layout.topMargin: 4 * root.d
                text: deviceGroup.modelData.title
                role: IrisText.Meta
                font.weight: IrisStyle.weight(Font.DemiBold)
            }
            Repeater {
                model: deviceGroup.modelData.devices
                ColumnLayout {
                    id: deviceRow
                    required property var modelData
                    readonly property bool input: deviceGroup.modelData.input
                    readonly property bool current: (deviceRow.input ? Audio.source?.id : Audio.defaultSink?.id) === modelData.id
                    readonly property bool headset: /head|bluez|airpod|buds/i.test(String(deviceRow.modelData.name ?? "") + String(deviceRow.modelData.description ?? ""))
                    readonly property var btDevice: BluetoothStatus.deviceForNode(deviceRow.modelData)
                    /** carga 0–1 do aparelho Bluetooth; -1 = sem bateria informada */
                    readonly property real battery: deviceRow.btDevice?.batteryAvailable ? deviceRow.btDevice.battery : -1
                    Layout.fillWidth: true
                    Layout.bottomMargin: 2 * root.d
                    spacing: 0
                    IrisButton {
                        Layout.fillWidth: true
                        quiet: true
                        implicitHeight: Math.round(34 * root.d)
                        buttonRadius: IrisStyle.radiusTile
                        onClicked: {
                            if (deviceRow.input) Audio.setDefaultSource(deviceRow.modelData)
                            else Audio.setDefaultSink(deviceRow.modelData)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10 * root.d
                            anchors.rightMargin: 10 * root.d
                            spacing: 10 * root.d
                            MaterialSymbol {
                                text: deviceRow.input ? "mic" : deviceRow.headset ? "headphones" : "speaker"
                                iconSize: Math.round(18 * root.d)
                                color: deviceRow.current ? IrisStyle.accent : IrisStyle.subtext
                            }
                            IrisText {
                                Layout.fillWidth: true
                                text: Audio.friendlyDeviceName(deviceRow.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: IrisStyle.typeLabel
                                font.weight: deviceRow.current ? IrisStyle.weight(Font.DemiBold) : Font.Normal
                            }
                            // carga do fone Bluetooth, como o applet do Plasma (LowPan Shells, 2026-11-15)
                            MaterialSymbol {
                                visible: deviceRow.battery >= 0
                                text: BluetoothStatus.batteryGlyph(deviceRow.battery)
                                iconSize: Math.round(16 * root.d)
                                color: deviceRow.battery < 0.2 ? IrisStyle.danger : IrisStyle.subtext
                            }
                            IrisText {
                                visible: deviceRow.battery >= 0
                                text: Math.round(deviceRow.battery * 100) + "%"
                                role: IrisText.Meta
                                font.features: ({ "tnum": 1 })
                            }
                            MaterialSymbol {
                                visible: deviceRow.current
                                text: "check"
                                iconSize: Math.round(18 * root.d)
                                color: IrisStyle.accent
                            }
                        }
                    }
                    LevelLine {
                        visible: root.mixer
                        Layout.leftMargin: 6 * root.d
                        Layout.rightMargin: 10 * root.d
                        node: deviceRow.modelData
                        isSink: !deviceRow.input
                        glyph: deviceRow.input ? "mic" : "volume_up"
                        mutedGlyph: deviceRow.input ? "mic_off" : "volume_off"
                    }
                }
            }
        }
    }

    // Apps page: one line per playing stream, like Plasma (not merged per app, so each tab can differ).
    Repeater {
        model: root.mixer && root.page === "apps" && root.outputs ? Audio.outputAppNodes : []
        RowLayout {
            id: appRow
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: 10 * root.d
            Layout.rightMargin: 10 * root.d
            Layout.bottomMargin: 4 * root.d
            spacing: 10 * root.d
            Image {
                Layout.preferredWidth: Math.round(26 * root.d)
                Layout.preferredHeight: Math.round(26 * root.d)
                sourceSize.width: width
                sourceSize.height: height
                source: IconMap.path(MprisController.streamIconName(appRow.modelData), "application-x-executable")
                opacity: appRow.modelData?.audio?.muted ? 0.45 : 1
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                IrisText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4 * root.d
                    text: {
                        const app = Audio.appNodeDisplayName(appRow.modelData)
                        const media = String(appRow.modelData?.properties?.["media.name"] ?? "")
                        return media && media !== app ? app + " · " + media : app
                    }
                    elide: Text.ElideRight
                    font.pixelSize: IrisStyle.typeLabel
                }
                LevelLine {
                    Layout.leftMargin: -4 * root.d
                    node: appRow.modelData
                    isSink: false // streams are written directly, never through the default-sink path
                }
            }
        }
    }
    IrisText {
        visible: root.mixer && root.page === "apps" && root.outputs && Audio.outputAppNodes.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 10 * root.d
        Layout.bottomMargin: 10 * root.d
        horizontalAlignment: Text.AlignHCenter
        text: Translation.tr("No apps playing audio")
        role: IrisText.Meta
    }
}
