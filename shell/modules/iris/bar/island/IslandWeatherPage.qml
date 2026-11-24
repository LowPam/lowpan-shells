pragma ComponentBehavior: Bound

// LowPan Shells: página de clima da ilha — meteograma e próximos dias.
// Adaptado da ideia do Weather Widget 3 (Kate Buckley, GPL-2.0-or-later,
// https://github.com/blackadderkate/weather-widget-2): curva de temperatura, linha de pressão,
// barras de chuva, setas de vento e a tabela 3h/9h/15h/21h. Redesenhado do zero no estilo do iRiS,
// com dados do Open-Meteo (Weather.meteogram), sem chave de API.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.iris.style
import qs.modules.iris.components

ColumnLayout {
    id: page
    required property Item island
    readonly property real d: IrisStyle.density
    readonly property bool current: page.island.effectivePage === "weather"
    spacing: Math.round(14 * page.d)

    readonly property bool ready: Weather.enabled && !String(Weather.data?.temp ?? "--").startsWith("--")
    readonly property var series: Array.from(Weather.meteogram?.hours ?? [])
    readonly property int span: 48
    readonly property string fontFamily: IrisStyle.fontNumbers.length > 0 ? IrisStyle.fontNumbers : Qt.application.font.family

    // Janela do gráfico: da hora cheia atual até span horas depois.
    readonly property var points: {
        const start = new Date()
        start.setMinutes(0, 0, 0)
        return page.series.filter(h => h.t >= start.getTime()).slice(0, page.span + 1)
    }

    // Próximos dias: períodos de 3h, 9h, 15h e 21h, como no Weather Widget 3.
    readonly property var periods: [3, 9, 15, 21]
    readonly property var days: {
        const out = []
        const now = Date.now() - 3600000
        for (const h of page.series) {
            const t = new Date(h.t)
            const key = t.toDateString()
            let day = out.length > 0 && out[out.length - 1].key === key ? out[out.length - 1] : null
            if (!day) {
                day = { key: key, t: h.t, slots: {} }
                out.push(day)
            }
            if (page.periods.includes(t.getHours()) && h.t >= now) day.slots[t.getHours()] = h
        }
        return out.filter(day => Object.keys(day.slots).length > 0).slice(0, 7)
    }

    function glyphOf(h): string { return Icons.getWeatherIcon(h.code, h.isNight) ?? "cloud" }
    // Nomes de dia no idioma do shell; decimais no formato numérico do sistema (como em Translation.locale).
    function dateText(date, format: string): string { return Translation.locale.toString(date, format).replace(/\.$/, "") }
    function decimal(v: real, digits: int): string { return Number(v).toFixed(digits).replace(".", Qt.locale().decimalPoint) }
    function degrees(v): string { return isNaN(v) ? "--" : Math.round(v) + "°" }

    // ── Agora ────────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Math.round(12 * page.d)

        Glyph {
            id: nowGlyph
            text: Icons.getWeatherIcon(Weather.data?.wCode, Weather.isNightNow()) ?? "cloud"
            iconSize: Math.round(40 * page.d)
            color: IrisStyle.skyLight(nowGlyph.text)
        }
        Tabular {
            text: page.ready ? String(Weather.data?.temp ?? "").replace(/[CF]$/, "") : "--"
            font.pixelSize: Math.round(34 * IrisStyle.typeScale)
            font.weight: IrisStyle.weight(Font.DemiBold)
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Math.round(1 * page.d)
            IrisText {
                Layout.fillWidth: true
                text: String(Weather.data?.description ?? "")
                elide: Text.ElideRight
                font.pixelSize: IrisStyle.typeHeadline
                font.weight: IrisStyle.weight(Font.Medium)
            }
            IrisText {
                Layout.fillWidth: true
                visible: Weather.showVisibleCity
                text: Weather.visibleCity
                elide: Text.ElideRight
                color: IrisStyle.textTertiary
                font.pixelSize: IrisStyle.typeMeta
            }
        }
        GridLayout {
            columns: 2
            columnSpacing: Math.round(10 * page.d)
            rowSpacing: Math.round(2 * page.d)
            Repeater {
                model: [
                    { label: Translation.tr("Feels like"), value: String(Weather.data?.tempFeelsLike ?? "").replace(/[CF]$/, "") },
                    { label: Translation.tr("Humidity"), value: String(Weather.data?.humidity ?? "") },
                    { label: Translation.tr("Wind"), value: String(Weather.data?.wind ?? "") + " " + String(Weather.data?.windDir ?? "") },
                    { label: Translation.tr("Pressure"), value: String(Weather.data?.press ?? "") }
                ]
                RowLayout {
                    id: metric
                    required property var modelData
                    spacing: Math.round(5 * page.d)
                    IrisText {
                        text: metric.modelData.label
                        color: IrisStyle.textTertiary
                        font.pixelSize: IrisStyle.typeFootnote
                    }
                    Tabular {
                        text: metric.modelData.value
                        font.pixelSize: IrisStyle.typeMeta
                        font.weight: IrisStyle.weight(Font.Medium)
                    }
                }
            }
        }
    }

    // ── Meteograma ───────────────────────────────────────────────────────────
    Rectangle {
        id: graph
        Layout.fillWidth: true
        implicitHeight: Math.round(236 * page.d)
        radius: IrisStyle.radiusTile
        color: IrisStyle.fillQuiet

        readonly property var pts: page.points
        readonly property int n: graph.pts.length
        readonly property real padLeft: Math.round(34 * page.d)
        readonly property real padRight: Math.round(44 * page.d)
        readonly property real padTop: Math.round(44 * page.d)
        readonly property real padBottom: Math.round(42 * page.d)
        readonly property real plotW: Math.max(1, graph.width - graph.padLeft - graph.padRight)
        readonly property real plotH: Math.max(1, graph.height - graph.padTop - graph.padBottom)
        readonly property real hourW: graph.plotW / Math.max(1, graph.n - 1)
        readonly property int labelStep: graph.hourW * 2 >= 24 * page.d ? 2 : 3

        function xAt(i: real): real { return graph.padLeft + i * graph.hourW }

        // Escala de temperatura em passos redondos; a pressão usa as mesmas linhas da grade.
        readonly property var tempScale: {
            const temps = graph.pts.map(h => h.temp).filter(v => !isNaN(v))
            if (temps.length === 0) return { lo: 0, hi: 1, step: 1, lines: 1 }
            const min = Math.min(...temps), max = Math.max(...temps)
            for (const step of [1, 2, 3, 4, 5, 10, 20]) {
                const lo = Math.floor(min / step) * step
                let hi = Math.ceil(max / step) * step
                if (hi <= lo) hi = lo + step
                const lines = Math.round((hi - lo) / step)
                if (lines <= 6) return { lo: lo, hi: hi, step: step, lines: lines }
            }
            return { lo: min, hi: max + 1, step: max + 1 - min, lines: 1 }
        }
        readonly property var pressScale: {
            const values = graph.pts.map(h => h.press).filter(v => !isNaN(v))
            const lines = graph.tempScale.lines
            if (values.length === 0) return { lo: 0, step: 1, lines: lines, valid: false }
            const min = Math.min(...values), max = Math.max(...values)
            const steps = Weather.useUSCS ? [0.05, 0.1, 0.2, 0.5, 1] : [1, 2, 5, 10, 20, 50]
            for (const step of steps) {
                const lo = Math.floor(min / step) * step
                if (lo + step * lines >= max) return { lo: lo, step: step, lines: lines, valid: true }
            }
            return { lo: min, step: (max - min) / lines || 1, lines: lines, valid: true }
        }
        readonly property real precipTop: Math.max(Weather.useUSCS ? 0.1 : 2, ...graph.pts.map(h => h.precip || 0))

        function yTemp(v: real): real {
            const s = graph.tempScale
            return graph.padTop + graph.plotH * (1 - (v - s.lo) / Math.max(0.001, s.hi - s.lo))
        }
        function yPress(v: real): real {
            const s = graph.pressScale
            return graph.padTop + graph.plotH * (1 - (v - s.lo) / Math.max(0.001, s.step * s.lines))
        }

        readonly property var paintKey: [graph.pts, graph.width, graph.height, IrisStyle.text, IrisStyle.textTertiary,
            IrisStyle.hairline, IrisStyle.accent, IrisStyle.identity.red, IrisStyle.identity.green, IrisStyle.identity.blue]
        onPaintKeyChanged: canvas.requestPaint()

        IrisText {
            anchors.centerIn: parent
            visible: graph.n < 2
            text: page.ready ? Translation.tr("Loading forecast…") : Translation.tr("No forecast yet")
            color: IrisStyle.textTertiary
            font.pixelSize: IrisStyle.typeMeta
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            visible: graph.n >= 2
            antialiasing: true
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                if (graph.n < 2) return
                const pts = graph.pts
                const left = graph.padLeft, right = graph.padLeft + graph.plotW
                const top = graph.padTop, bottom = graph.padTop + graph.plotH
                const small = Math.round(10 * page.d)
                const tiny = Math.round(9 * page.d)
                const ts = graph.tempScale, ps = graph.pressScale

                // Grade horizontal + eixos (temperatura à esquerda, pressão à direita).
                ctx.lineWidth = 1
                ctx.font = small + "px '" + page.fontFamily + "'"
                ctx.textBaseline = "middle"
                for (let k = 0; k <= ts.lines; k++) {
                    const y = Math.round(bottom - k * graph.plotH / ts.lines) + 0.5
                    ctx.strokeStyle = IrisStyle.hairline
                    ctx.globalAlpha = 1
                    ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(right, y); ctx.stroke()
                    ctx.fillStyle = IrisStyle.textTertiary
                    ctx.textAlign = "right"
                    ctx.fillText(Math.round(ts.lo + k * ts.step) + "°", left - 6 * page.d, y)
                    if (ps.valid) {
                        const p = ps.lo + k * ps.step
                        ctx.fillStyle = IrisStyle.identity.green
                        ctx.globalAlpha = 0.85
                        ctx.textAlign = "left"
                        ctx.fillText(Weather.useUSCS ? page.decimal(p, 2) : String(Math.round(p)), right + 6 * page.d, y)
                    }
                }
                ctx.globalAlpha = 1

                // Linhas verticais: horas (fracas) e meia-noite (fortes, com o dia da semana).
                ctx.textBaseline = "alphabetic"
                for (let i = 0; i < graph.n; i++) {
                    const t = new Date(pts[i].t)
                    const x = Math.round(graph.xAt(i)) + 0.5
                    const midnight = t.getHours() === 0
                    if (midnight || t.getHours() % graph.labelStep === 0) {
                        ctx.strokeStyle = midnight ? IrisStyle.textTertiary : IrisStyle.hairline
                        ctx.globalAlpha = midnight ? 0.7 : 0.5
                        ctx.beginPath(); ctx.moveTo(x, midnight ? 6 * page.d : top); ctx.lineTo(x, bottom); ctx.stroke()
                        ctx.globalAlpha = 1
                    }
                    if (midnight && i < graph.n - 4) {
                        ctx.fillStyle = IrisStyle.text
                        ctx.textAlign = "left"
                        ctx.font = "600 " + small + "px '" + page.fontFamily + "'"
                        ctx.fillText(page.dateText(t, "dddd"), x + 5 * page.d, 15 * page.d)
                        ctx.font = small + "px '" + page.fontFamily + "'"
                    }
                    if (t.getHours() % graph.labelStep === 0) {
                        ctx.fillStyle = IrisStyle.textTertiary
                        ctx.textAlign = "center"
                        ctx.fillText(String(t.getHours()).padStart(2, "0"), x, bottom + 14 * page.d)
                    }
                }

                // Chuva: barras azuis a partir da base, até 45% da altura.
                const barW = Math.max(2, graph.hourW - 1)
                ctx.font = tiny + "px '" + page.fontFamily + "'"
                ctx.textAlign = "center"
                for (let i = 0; i < graph.n - 1; i++) {
                    const p = pts[i].precip || 0
                    if (p <= 0) continue
                    const h = Math.max(1.5, p / graph.precipTop * graph.plotH * 0.45)
                    const x = graph.xAt(i) + 0.5
                    ctx.fillStyle = IrisStyle.identity.blue
                    ctx.globalAlpha = 0.55
                    ctx.fillRect(x, bottom - h, barW, h)
                    const prev = i > 0 ? (pts[i - 1].precip || 0) : -1
                    if (p >= 0.1 && p !== prev) {
                        ctx.globalAlpha = 1
                        ctx.fillStyle = IrisStyle.identity.blue
                        ctx.fillText(p >= 10 ? String(Math.round(p)) : page.decimal(p, 1), x + barW / 2, bottom - h - 3 * page.d)
                    }
                }
                ctx.globalAlpha = 1

                // Pressão: linha verde fina.
                if (ps.valid) {
                    ctx.strokeStyle = IrisStyle.identity.green
                    ctx.globalAlpha = 0.75
                    ctx.lineWidth = Math.max(1, 1.3 * page.d)
                    ctx.beginPath()
                    for (let i = 0; i < graph.n; i++) {
                        const x = graph.xAt(i), y = graph.yPress(pts[i].press)
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                    ctx.globalAlpha = 1
                }

                // Temperatura: curva suave (Catmull-Rom) com preenchimento esmaecido.
                const xs = [], ys = []
                for (let i = 0; i < graph.n; i++) { xs.push(graph.xAt(i)); ys.push(graph.yTemp(pts[i].temp)) }
                function trace() {
                    ctx.moveTo(xs[0], ys[0])
                    for (let i = 0; i < graph.n - 1; i++) {
                        const x0 = xs[Math.max(0, i - 1)], y0 = ys[Math.max(0, i - 1)]
                        const x3 = xs[Math.min(graph.n - 1, i + 2)], y3 = ys[Math.min(graph.n - 1, i + 2)]
                        ctx.bezierCurveTo(xs[i] + (xs[i + 1] - x0) / 6, ys[i] + (ys[i + 1] - y0) / 6,
                            xs[i + 1] - (x3 - xs[i]) / 6, ys[i + 1] - (y3 - ys[i]) / 6, xs[i + 1], ys[i + 1])
                    }
                }
                const fill = ctx.createLinearGradient(0, top, 0, bottom)
                fill.addColorStop(0, ColorUtils.applyAlpha(IrisStyle.identity.red, 0.22))
                fill.addColorStop(1, ColorUtils.applyAlpha(IrisStyle.identity.red, 0))
                ctx.beginPath()
                trace()
                ctx.lineTo(xs[graph.n - 1], bottom)
                ctx.lineTo(xs[0], bottom)
                ctx.closePath()
                ctx.fillStyle = fill
                ctx.fill()
                ctx.beginPath()
                trace()
                ctx.strokeStyle = IrisStyle.identity.red
                ctx.lineWidth = Math.max(1.5, 2.2 * page.d)
                ctx.lineJoin = "round"
                ctx.stroke()

                // Agora: traço na cor de destaque.
                const nowX = graph.xAt((Date.now() - pts[0].t) / 3600000)
                if (nowX >= left && nowX <= right) {
                    ctx.strokeStyle = IrisStyle.accent
                    ctx.lineWidth = Math.max(1, 1.5 * page.d)
                    ctx.beginPath(); ctx.moveTo(nowX, top); ctx.lineTo(nowX, bottom); ctx.stroke()
                    ctx.fillStyle = IrisStyle.accent
                    ctx.beginPath()
                    ctx.arc(nowX, graph.yTemp(pts[0].temp + (pts[1].temp - pts[0].temp) * (Date.now() - pts[0].t) / 3600000),
                        3.5 * page.d, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }

        // Ícones do tempo a cada 3 horas, acima da curva.
        Repeater {
            model: graph.n >= 2 ? graph.pts.length : 0
            Glyph {
                id: sky
                required property int index
                readonly property var hour: graph.pts[sky.index]
                visible: sky.index % 3 === 1 && sky.index < graph.n - 1
                text: page.glyphOf(sky.hour)
                iconSize: Math.round(18 * page.d)
                color: IrisStyle.skyLight(sky.text)
                x: Math.round(graph.xAt(sky.index) - width / 2)
                y: Math.round(Math.max(20 * page.d, Math.min(graph.padTop + graph.plotH - height,
                    graph.yTemp(sky.hour.temp) - height - 6 * page.d)))
            }
        }

        // Setas de vento (para onde o vento sopra), alinhadas às horas marcadas.
        Repeater {
            model: graph.n >= 2 ? graph.pts.length : 0
            Glyph {
                id: wind
                required property int index
                readonly property var hour: graph.pts[wind.index]
                visible: new Date(wind.hour.t).getHours() % graph.labelStep === 0
                text: "navigation"
                iconSize: Math.round(13 * page.d)
                color: IrisStyle.textTertiary
                rotation: (wind.hour.windDir ?? 0) + 180
                x: Math.round(graph.xAt(wind.index) - width / 2)
                y: Math.round(graph.height - 20 * page.d)
                HoverHandler { id: windHover }
                ToolTip.visible: windHover.hovered
                ToolTip.text: Math.round(wind.hour.wind) + " " + String(Weather.meteogram?.windUnit ?? "")
            }
        }
    }

    // ── Próximos dias ────────────────────────────────────────────────────────
    GridLayout {
        id: table
        Layout.fillWidth: true
        visible: page.days.length > 0
        columns: page.days.length + 1
        columnSpacing: 0
        rowSpacing: Math.round(6 * page.d)

        Item { implicitWidth: Math.round(34 * page.d); implicitHeight: 1 }
        Repeater {
            model: page.days
            ColumnLayout {
                id: head
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 0
                IrisText {
                    Layout.alignment: Qt.AlignHCenter
                    text: head.index === 0 && new Date(head.modelData.t).toDateString() === new Date().toDateString()
                        ? Translation.tr("Today") : page.dateText(new Date(head.modelData.t), "ddd")
                    font.pixelSize: IrisStyle.typeMeta
                    font.weight: IrisStyle.weight(Font.DemiBold)
                }
                Tabular {
                    Layout.alignment: Qt.AlignHCenter
                    text: page.dateText(new Date(head.modelData.t), "dd/MM")
                    color: IrisStyle.textTertiary
                    font.pixelSize: IrisStyle.typeFootnote
                }
            }
        }

        Repeater {
            model: page.periods.length * (page.days.length + 1)
            Item {
                id: cell
                required property int index
                readonly property int row: Math.floor(cell.index / (page.days.length + 1))
                readonly property int col: cell.index % (page.days.length + 1)
                readonly property int period: page.periods[cell.row]
                readonly property var hour: cell.col > 0 ? (page.days[cell.col - 1]?.slots?.[cell.period] ?? null) : null
                Layout.fillWidth: cell.col > 0
                Layout.preferredWidth: cell.col > 0 ? 1 : Math.round(34 * page.d)
                implicitHeight: Math.round(22 * page.d)

                IrisText {
                    visible: cell.col === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: cell.period + "h"
                    color: IrisStyle.textTertiary
                    font.pixelSize: IrisStyle.typeFootnote
                }
                RowLayout {
                    visible: cell.hour !== null
                    anchors.centerIn: parent
                    spacing: Math.round(4 * page.d)
                    Tabular {
                        text: cell.hour ? page.degrees(cell.hour.temp) : ""
                        font.pixelSize: IrisStyle.typeLabel
                        font.weight: IrisStyle.weight(Font.Medium)
                    }
                    Glyph {
                        id: cellGlyph
                        text: cell.hour ? page.glyphOf(cell.hour) : "cloud"
                        iconSize: Math.round(16 * page.d)
                        color: IrisStyle.skyLight(cellGlyph.text)
                    }
                }
            }
        }
    }

    // ── Rodapé ───────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Math.round(8 * page.d)
        Glyph {
            text: "refresh"
            iconSize: Math.round(14 * page.d)
            color: refreshArea.containsMouse ? IrisStyle.text : IrisStyle.textTertiary
            MouseArea {
                id: refreshArea
                anchors.fill: parent
                anchors.margins: -4 * page.d
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Weather.getData()
            }
        }
        IrisText {
            text: Translation.tr("Updated at %1").arg(String(Weather.data?.lastRefresh ?? "--:--"))
            color: IrisStyle.textTertiary
            font.pixelSize: IrisStyle.typeFootnote
        }
        Item { Layout.fillWidth: true }
        IrisText {
            text: Translation.tr("Forecast: Open-Meteo")
            color: IrisStyle.textTertiary
            font.pixelSize: IrisStyle.typeFootnote
        }
    }
}
