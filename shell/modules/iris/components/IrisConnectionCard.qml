pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.iris.style

// LowPan Shells: the active connection (wired or Wi-Fi), modelled on Plasma's network applet.
// Header with live ↓/↑ rates; expanded it shows "Speed" (a one-minute graph) or "Details" (link speed, MAC,
// device, IPv4/IPv6, gateway, DNS). Data come from nmcli and /sys/class/net, sampled only while shown.
// Takes no keyboard (KWin focus rule: a focused shell surface makes Krohnkite re-tile).
Rectangle {
    id: root

    readonly property real d: IrisStyle.density
    // Sample only while the card is on screen; the Control Center stays resident when closed.
    // Follows the list it sits in, not its own `visible` (that one waits for a device to be found).
    readonly property bool live: Boolean(root.parent?.visible) && (root.Window.window?.visible ?? true)
    // Starts folded (only name and ↓/↑); a tap on the header opens Speed/Details, and it folds again when hidden.
    property bool expanded: false
    property string page: "speed"

    property string device: ""
    property string kind: ""        // "ethernet" | "wifi"
    property string connection: ""
    property var info: ({})
    property real downRate: 0
    property real upRate: 0
    property var downHistory: []
    property var upHistory: []
    readonly property int historyLength: 60
    property real _lastRx: -1
    property real _lastTx: -1
    property double _lastSample: 0

    visible: root.device.length > 0
    implicitHeight: column.implicitHeight + 12 * root.d
    radius: IrisStyle.radiusTile
    color: IrisStyle.fillQuiet

    function formatRate(bytes: real): string {
        const units = ["B/s", "KiB/s", "MiB/s", "GiB/s"]
        let value = Math.max(0, Number(bytes) || 0)
        let unit = 0
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++ }
        const digits = unit > 0 && value < 100 ? 1 : 0
        return Number(value).toLocaleString(Qt.locale(), "f", digits) + " " + units[unit]
    }

    function resetSamples(): void {
        root._lastRx = -1; root._lastTx = -1; root._lastSample = 0
        root.downRate = 0; root.upRate = 0
        root.downHistory = []; root.upHistory = []
    }

    onLiveChanged: {
        if (root.live) { findDevice.running = true }
        else { root.resetSamples(); root.expanded = false }
    }
    Component.onCompleted: if (root.live) findDevice.running = true

    // Which device carries the connection: the first connected ethernet or Wi-Fi NetworkManager manages.
    Process {
        id: findDevice
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                let found = null
                for (const line of text.trim().split("\n")) {
                    const f = line.split(":")
                    if (f.length < 4) continue
                    if ((f[1] === "ethernet" || f[1] === "wifi") && f[2] === "connected") { found = f; break }
                }
                const dev = found ? found[0] : ""
                if (dev !== root.device) root.resetSamples()
                root.device = dev
                root.kind = found ? found[1] : ""
                root.connection = found ? found.slice(3).join(":") : ""
                if (dev) readDetails.running = true
            }
        }
    }
    Timer { interval: 10000; repeat: true; running: root.live; onTriggered: findDevice.running = true }

    Process {
        id: readDetails
        command: ["sh", "-c", 'nmcli -t -f GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,IP6.GATEWAY device show "$1"; printf "SPEED:%s\\n" "$(cat /sys/class/net/$1/speed 2>/dev/null)"', "sh", root.device]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = { ipv4: [], dns: [], ipv6: [] }
                for (const line of text.split("\n")) {
                    const sep = line.indexOf(":")
                    if (sep < 0) continue
                    const key = line.slice(0, sep).replace(/\[\d+\]$/, "")
                    const value = line.slice(sep + 1).replace(/\\:/g, ":").trim()
                    if (!value || value === "--") continue
                    if (key === "GENERAL.HWADDR") out.mac = value
                    else if (key === "IP4.ADDRESS") out.ipv4.push(value.replace(/\/\d+$/, ""))
                    else if (key === "IP4.GATEWAY") out.gateway = value
                    else if (key === "IP4.DNS") out.dns.push(value)
                    else if (key === "IP6.ADDRESS" && !/^fe80/i.test(value)) out.ipv6.push(value.replace(/\/\d+$/, ""))
                    else if (key === "IP6.GATEWAY") out.gateway6 = value
                    else if (key === "SPEED" && Number(value) > 0) out.speed = Number(value)
                }
                root.info = out
            }
        }
    }

    Process {
        id: readCounters
        command: ["cat", "/sys/class/net/" + root.device + "/statistics/rx_bytes", "/sys/class/net/" + root.device + "/statistics/tx_bytes"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(Number)
                if (v.length < 2 || !v.every(Number.isFinite)) return
                const now = Date.now()
                if (root._lastSample > 0 && now > root._lastSample) {
                    const dt = (now - root._lastSample) / 1000
                    root.downRate = Math.max(0, v[0] - root._lastRx) / dt
                    root.upRate = Math.max(0, v[1] - root._lastTx) / dt
                    root.downHistory = root.downHistory.concat([root.downRate]).slice(-root.historyLength)
                    root.upHistory = root.upHistory.concat([root.upRate]).slice(-root.historyLength)
                }
                root._lastRx = v[0]; root._lastTx = v[1]; root._lastSample = now
            }
        }
    }
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.live && root.device.length > 0
        onTriggered: if (!readCounters.running) readCounters.running = true
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6 * root.d
        spacing: 4 * root.d

        IrisButton {
            Layout.fillWidth: true
            quiet: true
            implicitHeight: Math.round(42 * root.d)
            buttonRadius: IrisStyle.radiusTile
            onClicked: root.expanded = !root.expanded
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8 * root.d
                anchors.rightMargin: 8 * root.d
                spacing: 10 * root.d
                MaterialSymbol {
                    text: root.kind === "wifi" ? "wifi" : "lan"
                    iconSize: Math.round(19 * root.d)
                    color: IrisStyle.accent
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2
                    IrisText {
                        Layout.fillWidth: true
                        text: root.connection
                        elide: Text.ElideRight
                    }
                    IrisText {
                        Layout.fillWidth: true
                        text: "↓ " + root.formatRate(root.downRate) + "   ↑ " + root.formatRate(root.upRate)
                        role: IrisText.Meta
                        font.features: ({ "tnum": 1 })
                        elide: Text.ElideRight
                    }
                }
                MaterialSymbol {
                    text: root.expanded ? "expand_less" : "expand_more"
                    iconSize: Math.round(18 * root.d)
                    color: IrisStyle.subtext
                }
            }
        }

        IrisSegmented {
            visible: root.expanded
            Layout.fillWidth: true
            Layout.leftMargin: 4 * root.d
            Layout.rightMargin: 4 * root.d
            options: [
                { value: "speed", label: Translation.tr("Speed") },
                { value: "details", label: Translation.tr("Details") }
            ]
            current: root.page
            onPicked: value => root.page = value
        }

        // Speed: download and upload over the last minute, scaled to the busiest second.
        Item {
            id: graph
            visible: root.expanded && root.page === "speed"
            Layout.fillWidth: true
            Layout.leftMargin: 4 * root.d
            Layout.rightMargin: 4 * root.d
            implicitHeight: Math.round(150 * root.d)
            readonly property real plotHeight: graph.height - 30 * root.d
            readonly property real peak: Math.max(1024, ...root.downHistory, ...root.upHistory)
            // A round ceiling in the unit the labels use (B, KiB, MiB…), so the four grid lines read as even steps.
            readonly property real ceiling: {
                const raw = graph.peak * 1.1
                let unit = 1
                while (raw / unit >= 1000 && unit < Math.pow(1024, 3)) unit *= 1024
                const value = raw / unit
                const p = Math.pow(10, Math.floor(Math.log10(value)))
                for (const m of [1, 2, 4, 5, 8, 10]) if (m * p >= value) return m * p * unit
                return 10 * p * unit
            }
            readonly property real labelWidth: Math.round(70 * root.d)
            readonly property color downColor: IrisStyle.identity.pink
            readonly property color upColor: IrisStyle.identity.teal
            readonly property color gridColor: IrisStyle.subtext

            Repeater {
                model: 5
                IrisText {
                    required property int index
                    x: 0
                    width: graph.labelWidth - 6 * root.d
                    y: graph.plotHeight * index / 4 - height / 2 + 4 * root.d
                    horizontalAlignment: Text.AlignRight
                    text: root.formatRate(graph.ceiling * (4 - index) / 4)
                    role: IrisText.Meta
                    font.features: ({ "tnum": 1 })
                }
            }
            Canvas {
                id: plot
                x: graph.labelWidth
                y: 4 * root.d
                width: graph.width - graph.labelWidth
                height: graph.plotHeight
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = Qt.rgba(graph.gridColor.r, graph.gridColor.g, graph.gridColor.b, 0.25)
                    ctx.lineWidth = 1
                    for (let i = 0; i <= 4; i++) {
                        const y = Math.round(height * i / 4) + 0.5
                        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                    }
                    const series = (values, c) => {
                        if (values.length < 2) return
                        const step = width / (root.historyLength - 1)
                        const x0 = width - (values.length - 1) * step
                        ctx.beginPath()
                        ctx.moveTo(x0, height)
                        values.forEach((v, i) => ctx.lineTo(x0 + i * step, height - Math.min(1, v / graph.ceiling) * height))
                        ctx.lineTo(width, height)
                        ctx.closePath()
                        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.35)
                        ctx.fill()
                        ctx.beginPath()
                        values.forEach((v, i) => {
                            const px = x0 + i * step, py = height - Math.min(1, v / graph.ceiling) * height
                            if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                        })
                        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.95)
                        ctx.lineWidth = 1.5
                        ctx.stroke()
                    }
                    series(root.downHistory, graph.downColor)
                    series(root.upHistory, graph.upColor)
                }
                Connections {
                    target: root
                    function onDownHistoryChanged(): void { if (plot.visible) plot.requestPaint() }
                }
                onVisibleChanged: if (visible) requestPaint()
            }
            RowLayout {
                anchors.bottom: parent.bottom
                x: graph.labelWidth
                spacing: 14 * root.d
                Repeater {
                    model: [
                        { label: Translation.tr("Received"), color: graph.downColor },
                        { label: Translation.tr("Sent"), color: graph.upColor }
                    ]
                    RowLayout {
                        required property var modelData
                        spacing: 5 * root.d
                        Rectangle {
                            implicitWidth: 8 * root.d; implicitHeight: 8 * root.d; radius: 2 * root.d
                            color: parent.modelData.color
                        }
                        IrisText { text: parent.modelData.label; role: IrisText.Meta }
                    }
                }
            }
        }

        // Details: label column right-aligned against the values, as Plasma lays them out.
        ColumnLayout {
            visible: root.expanded && root.page === "details"
            Layout.fillWidth: true
            Layout.leftMargin: 8 * root.d
            Layout.rightMargin: 8 * root.d
            Layout.bottomMargin: 4 * root.d
            spacing: 1
            Repeater {
                model: {
                    const i = root.info
                    const rows = []
                    const add = (label, value) => { if (value) rows.push({ label, value }) }
                    rows.push({ heading: root.kind === "wifi" ? Translation.tr("Wi-Fi") : Translation.tr("Ethernet") })
                    add(Translation.tr("Link speed"), i.speed ? (i.speed >= 1000 ? (i.speed / 1000) + " Gbit/s" : i.speed + " Mbit/s") : "")
                    if (root.kind === "wifi" && Network.active) add(Translation.tr("Signal"), Network.accessPointDetails(Network.active).split(" | ").join(" · "))
                    add(Translation.tr("MAC address"), i.mac)
                    add(Translation.tr("Device"), root.device)
                    if ((i.ipv4 ?? []).length || i.gateway || (i.dns ?? []).length) {
                        rows.push({ heading: "IPv4" })
                        add(Translation.tr("IPv4 address"), (i.ipv4 ?? []).join("\n"))
                        add(Translation.tr("Default gateway"), i.gateway)
                        add(Translation.tr("DNS servers"), (i.dns ?? []).join("\n"))
                    }
                    if ((i.ipv6 ?? []).length) {
                        rows.push({ heading: "IPv6" })
                        add(Translation.tr("IPv6 address"), (i.ipv6 ?? []).join("\n"))
                        add(Translation.tr("Default gateway"), i.gateway6)
                    }
                    return rows
                }
                // A heading centred over the block, or a label/value row.
                delegate: Item {
                    id: cell
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: cell.modelData.heading ? 6 * root.d : 0
                    implicitHeight: cellRow.implicitHeight
                    RowLayout {
                        id: cellRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 10 * root.d
                        IrisText {
                            Layout.preferredWidth: cell.modelData.heading ? -1 : Math.round(150 * root.d)
                            Layout.alignment: Qt.AlignTop
                            Layout.fillWidth: Boolean(cell.modelData.heading)
                            horizontalAlignment: cell.modelData.heading ? Text.AlignHCenter : Text.AlignRight
                            text: cell.modelData.heading ?? cell.modelData.label
                            role: cell.modelData.heading ? IrisText.Body : IrisText.Meta
                            font.weight: cell.modelData.heading ? IrisStyle.weight(Font.DemiBold) : Font.Normal
                            elide: Text.ElideRight
                        }
                        IrisText {
                            visible: !cell.modelData.heading
                            Layout.fillWidth: true
                            text: cell.modelData.value ?? ""
                            font.pixelSize: IrisStyle.typeMeta
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        }
                    }
                }
            }
        }
    }
}
