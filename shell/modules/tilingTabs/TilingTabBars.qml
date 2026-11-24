pragma ComponentBehavior: Bound

// LowPan Tiling — barra de abas (como as pilhas do Pop!_OS) no alto de cada coluna em abas.
// O motor (shell/kwin-tiling, layout Niri) reserva a altura da barra e publica as colunas pela ponte
// (NiriService.kwinTabColumns). Aqui só se desenha e se pede ações:
//   clique = traz a janela para a frente · × = fecha. Arrastar a aba não faz nada (decisão 2026-11-08): para separar,
//   arrasta-se a janela pela barra de título (motor, §21.13) — a aba fazia o mesmo e ficava redundante.
// No KWin a barra é uma janela comum (namespace qualquer): o Meta+D a esconde junto com as janelas.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.iris.style
import qs.modules.iris.components

Scope {
    id: root

    // só as da área de trabalho atual (o motor publica todas as faixas)
    // arrastando (e logo depois de soltar, até a coluna nova chegar): a aba da janela arrastada some na hora;
    // se sobra uma aba só, a barra some junto (LowPan Shells, 2026-11-08)
    readonly property string dragId: NiriService.kwinTilingDragId
    // fechada pelo × da aba (2026-11-08, vídeo do usuário 13:08): o motor só refaz a coluna depois da animação de
    // fechar (lowpanCloseDelay); até lá a aba dela some daqui, como no arrasto. Sai da lista quando o motor publica
    // as abas sem ela (ou 1,5 s)
    property var closingIds: []
    readonly property var hiddenIds: root.dragId === "" ? root.closingIds : root.closingIds.concat([root.dragId])
    readonly property var columns: (NiriService.kwinTabColumns ?? [])
        .filter(c => !c.desktop || c.desktop === NiriService.kwinCurrentDesktop)
        .map(c => root.hiddenIds.length === 0 ? c : Object.assign({}, c, { tabs: (c.tabs ?? []).filter(t => !root.hiddenIds.includes(String(t.id))) }))
        .filter(c => (c.tabs ?? []).length > 1)
    readonly property real d: IrisStyle.density

    function activate(id: string): void {
        NiriService.kwinSend({ action: "activate", id: id })
    }
    function close(id: string): void {
        if (!root.closingIds.includes(id))
            root.closingIds = root.closingIds.concat([id])
        closingClear.restart()
        NiriService.kwinSend({ action: "close", id: id })
    }
    Timer {
        id: closingClear
        interval: 1500
        onTriggered: root.closingIds = []
    }
    Connections {
        target: NiriService
        function onKwinTabColumnsChanged() {
            if (root.closingIds.length === 0)
                return
            const present = []
            for (const c of (NiriService.kwinTabColumns ?? []))
                for (const t of (c.tabs ?? []))
                    present.push(String(t.id))
            root.closingIds = root.closingIds.filter(id => present.includes(id))
        }
    }
    Variants {
        // a chave é o id fixo da coluna: rolar a faixa só move a barra, não a recria
        model: root.columns.map(c => String(c.uid))

        PanelWindow {
            id: bar
            required property string modelData
            readonly property var col: root.columns.find(c => String(c.uid) === bar.modelData) ?? null
            readonly property var scr: Quickshell.screens.find(s => s.name === bar.col?.output) ?? Quickshell.screens[0]
            // a coluna pode estar em parte fora da tela: a barra mostra só o pedaço visível
            readonly property real x0: Math.max(Number(bar.col?.x ?? 0), bar.scr.x)
            readonly property real x1: Math.min(Number(bar.col?.x ?? 0) + Number(bar.col?.width ?? 0), bar.scr.x + bar.scr.width)

            screen: bar.scr
            visible: bar.col !== null && bar.x1 - bar.x0 > 48 && !NiriService.kwinShowingDesktop
            anchors { top: true; left: true }
            margins {
                left: Math.round(bar.x0 - bar.scr.x)
                top: Math.round(Number(bar.col?.y ?? 0) - bar.scr.y)
            }
            implicitWidth: Math.max(1, Math.round(bar.x1 - bar.x0))
            implicitHeight: Math.max(1, Number(bar.col?.height ?? NiriService.kwinTabBarHeight))
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:lowpan-tabs"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Abas no formato da dock (pedido do usuário): cantos de cima arredondados e um ombro côncavo de cada lado embaixo
            // (raio = metade da altura), fundindo-se no topo da janela. Abas vizinhas ficam encostadas e os ombros entram
            // uma sob a outra: os contornos se cruzam na metade da altura (o "X"). Largura máxima como num navegador; o
            // resto da barra fica vazio. A ativa fica por cima, com a cor do corpo da dock.
            Item {
                id: strip
                anchors.fill: parent
                readonly property real h: height
                /** largura horizontal de cada S (alongado: 1,25 × a altura, como a curva da dock) */
                readonly property real flare: Math.round(strip.h * 1.25)
                /** recuo da primeira aba em relação à borda esquerda da janela (o ombro não encosta no canto arredondado) */
                readonly property real lead: Math.round(10 * root.d)
                readonly property int count: (bar.col?.tabs ?? []).length
                readonly property real tabW: Math.max(Math.round(80 * root.d),
                    Math.min(Math.round(240 * root.d), (strip.width - strip.flare - strip.lead) / Math.max(1, strip.count)))

                Repeater {
                    model: bar.col?.tabs ?? []

                    Item {
                        id: tab
                        required property var modelData
                        required property int index
                        readonly property bool active: !!tab.modelData.active
                        readonly property string winId: String(tab.modelData.id)
                        readonly property string iconName: AppSearch.guessIcon(String(tab.modelData.app ?? ""))
                        // LowPan Shells (2026-11-08): sem vidro — as de segundo plano são opacas, um degrau acima na escada
                        // do tema de cores (surface → surfaceHigh → surfaceHighest); passar o mouse sobe mais um
                        readonly property color fill: tab.active ? IrisStyle.surfaceOpaque
                            : hover.hovered ? IrisStyle.tinted(IrisStyle.surfaceHighestOpaque, 0.2)
                            : IrisStyle.tinted(IrisStyle.surfaceHighOpaque, 0.16)

                        // largura da aba = de um meio de S ao outro (as vizinhas dividem o S)
                        x: strip.lead + strip.flare / 2 + tab.index * strip.tabW
                        width: strip.tabW
                        height: strip.h
                        z: tab.active ? 100 : hover.hovered ? 50 : strip.count - tab.index

                        // a lateral é um S contínuo e deitado, como o da dock (sai arredondado do topo e já se abre no
                        // ombro); o meio do S fica na borda da aba, onde cruza o S da vizinha (o "X" na metade da altura)
                        Shape {
                            id: silhouette
                            x: -strip.flare / 2
                            width: tab.width + strip.flare
                            height: tab.height
                            preferredRendererType: Shape.CurveRenderer
                            readonly property real fl: strip.flare
                            readonly property real flat: Math.max(0, tab.width - strip.flare)
                            readonly property real hh: tab.height

                            ShapePath { // corpo
                                strokeWidth: -1
                                fillColor: tab.fill
                                startX: 0; startY: silhouette.hh
                                PathCubic { x: silhouette.fl; y: 0; control1X: silhouette.fl / 2; control1Y: silhouette.hh; control2X: silhouette.fl / 2; control2Y: 0 }
                                PathLine { x: silhouette.fl + silhouette.flat; y: 0 }
                                PathCubic { x: 2 * silhouette.fl + silhouette.flat; y: silhouette.hh; control1X: silhouette.fl * 1.5 + silhouette.flat; control1Y: 0; control2X: silhouette.fl * 1.5 + silhouette.flat; control2Y: silhouette.hh }
                                PathLine { x: 0; y: silhouette.hh }
                            }
                            // LowPan Shells (2026-11-08): sem contorno (pedido do usuário) — só o corpo
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Math.round(strip.flare / 2)
                            anchors.rightMargin: Math.round(strip.flare / 2 - 6 * root.d)
                            spacing: Math.round(7 * root.d)

                            IconImage {
                                implicitSize: Math.round(16 * root.d)
                                source: Quickshell.iconPath(tab.iconName, "application-x-executable")
                            }
                            IrisText {
                                Layout.fillWidth: true
                                text: String(tab.modelData.title ?? "")
                                elide: Text.ElideRight
                                color: tab.active ? IrisStyle.text : IrisStyle.subtext
                                font.pixelSize: IrisStyle.typeMeta
                                font.weight: tab.active ? IrisStyle.weight(Font.DemiBold) : Font.Normal
                            }
                            Rectangle { // ×
                                implicitWidth: Math.round(20 * root.d)
                                implicitHeight: implicitWidth
                                radius: width / 2
                                color: closeHover.hovered ? IrisStyle.fillHover : "transparent"
                                opacity: tab.active || hover.hovered ? 1 : 0.55
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: Math.round(14 * root.d)
                                    color: IrisStyle.subtext
                                }
                                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                                // MouseArea (exclusivo): o clique no × não chega à aba de baixo
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    onClicked: root.close(tab.winId)
                                }
                            }
                        }

                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                        // clique = ativa (arrastar a aba não faz nada; separar é pela barra de título da janela)
                        MouseArea {
                            z: -1
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: root.activate(tab.winId)
                        }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: String(tab.modelData.title ?? "")
                    }
                }
            }
        }
    }
}
