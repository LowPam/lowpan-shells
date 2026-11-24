pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.iris.frame
import qs.modules.iris.style
import qs.modules.iris.field as Field

Item {
    id: root

    property bool open: false
    property bool contentReady: true
    property string motionSurface: ""
    property var origin: null
    property Item originItem: null
    property real originItemRadius: 0
    property real radius: IrisStyle.radius
    property color color: IrisStyle.surface
    property color light: "transparent"
    property string lightFrom: "top"
    property real contentScaleFrom: 0.965
    property real contentFadeStart: IrisStyle.contentRise
    property real contentFadeSpan: IrisStyle.contentSpan
    property int animationDuration: 0
    property bool contentTravels: false
    property real originShare: IrisStyle.absorbShare
    property bool fieldBacked: false
    // A surface in a window of its own draws its silhouette with a field of its own: the SDF edge
    // every other body has, instead of a ClippingRectangle's harder one. Compositor blur keeps its pane.
    property bool ownField: false
    // LowPan Shells: durante o efeito do KWin o corpo é desenhado aqui (o shader precisa dele na mesma textura).
    readonly property bool drawsOwnField: (root.ownField && !root.fieldBacked || root.fxLive) && (!IrisStyle.glassCompositor || root.compositorBlurred)

    // LowPan Shells: o efeito de abrir/fechar janelas do KWin (KWinOpenEffect) no lugar do morph do iRiS.
    // Aberto, o corpo fica no lugar (presentation 1) e o efeito anima a textura de corpo + conteúdo,
    // sem desfoque do compositor (como as janelas animadas pelo Burn-My-Windows); ao terminar, tudo volta
    // ao desenho normal. Efeito "Nenhum" = o morph de sempre.
    property bool followsKWinEffect: true
    readonly property bool kwinFx: root.followsKWinEffect && KWinOpenEffect.follows(root.motionSurface)
    readonly property bool fxShown: root.armed && root.launched
    property bool fxVisible: false
    property bool fxOpening: true
    property real fxProgress: 0
    readonly property bool fxLive: root.kwinFx && fxAnim.running
    onFxShownChanged: {
        if (!root.kwinFx) return
        if (root.fxShown) {
            root.fxVisible = true
            root.fxOpening = true
            fxAnim.restart()
        } else if (root.fxVisible) {
            root.fxOpening = false
            fxAnim.restart()
        }
    }
    onKwinFxChanged: { fxAnim.stop(); root.fxVisible = root.fxShown }
    NumberAnimation {
        id: fxAnim
        target: root
        property: "fxProgress"
        from: 0
        to: 1
        duration: Math.max(1, KWinOpenEffect.duration)
        onFinished: if (!root.fxShown) root.fxVisible = false
    }
    function fxEase(t: real, back: bool): real {
        const p = Math.max(0, Math.min(1, t))
        if (back) { const c = 1.4, q = p - 1; return 1 + (c + 1) * q * q * q + c * q * q }
        return 1 - Math.pow(1 - p, 3)
    }
    // Escalonar / Esmaecer / Planar / Kinetic: no próprio corpo, sem shader.
    readonly property real fxShow: {
        const back = KWinOpenEffect.kind === "kinetic"
        return root.fxOpening ? root.fxEase(root.fxProgress, back) : 1 - root.fxEase(root.fxProgress, false)
    }
    // A Place that meets the frame hands its body to the chassis of its output (`fieldBacked`): the frame's
    // field draws it with the join, the shadow and the blur, and this window only carries the content.
    // `chassisJoin` adds what the body joins ({ id, joins, fuse }), an `edge` body to join past the screen
    // edge, and `grow` ("top", "left"…) to extend the body under that edge by its radius.
    property string chassisKey: ""
    property var chassisJoin: ({})
    readonly property var chassisBodies: {
        if (!root.visible || root.opacity <= 0 || !root.fieldBacked || root.fxLive || root.chassisKey.length === 0 || !(root.armed || root.presentation > 0)) return []
        void (root.x + root.y + chassis.x + chassis.y + chassis.width + chassis.height + chassis.radius + (root.parent?.x ?? 0) + (root.parent?.y ?? 0))
        const at = chassis.mapToItem(null, 0, 0)
        const join = root.chassisJoin ?? {}
        const r = chassis.radius
        const body = { x: at.x + root.windowOffset.x, y: at.y + root.windowOffset.y, width: chassis.width, height: chassis.height, radius: r,
            id: join.id ?? root.chassisKey, joins: join.joins ?? "", fuse: join.fuse ?? 0, paints: true,
            glass: root.glass ? IrisStyle.surfaceGlass(root.motionSurface) : "solid" }
        if (join.grow === "top") { body.y -= r; body.height += r }
        else if (join.grow === "bottom") body.height += r
        else if (join.grow === "left") { body.x -= r; body.width += r }
        else if (join.grow === "right") body.width += r
        return join.edge ? [join.edge, body] : [body]
    }
    onChassisBodiesChanged: IrisFrame.publishPlace(root.chassisKey, root.QsWindow.window?.screen?.name ?? "", root.chassisBodies)
    Component.onDestruction: IrisFrame.publishPlace(root.chassisKey, "", [])
    property bool compositorBlurred: false
    property bool glass: true
    readonly property string surfaceMaterial: IrisStyle.surfaceMaterial(root.motionSurface)
    readonly property string material: root.fieldBacked || root.drawsOwnField ? "field"
        : !root.glass || root.surfaceMaterial === "solid" || (!IrisStyle.glassy && root.surfaceMaterial !== "glass") ? "solid"
        : IrisStyle.glassCompositor && root.compositorBlurred ? "compositor" : "wallpaper"
    default property alias content: contentHost.data
    readonly property real progress: root.presentation
    readonly property var bodyRect: {
        void (chassis.x + chassis.y + chassis.width + chassis.height + chassis.radius + root.x + root.y)
        return { x: root.x + chassis.x, y: root.y + chassis.y,
            width: chassis.width, height: chassis.height, radius: chassis.radius }
    }
    readonly property bool settled: root.presentation >= 1
    // In a window above its origin a body cannot pass under it, so it fades out as it reaches it instead of covering it.
    property bool behindOrigin: !root.fieldBacked && !root.settlesNow && (root.originItem !== null || root.origin !== null || root.originScene !== null)
    property real emergenceSpan: 0.24
    readonly property real emergence: root.behindOrigin ? IrisStyle.ramp(root.presentation, 0, root.emergenceSpan) : 1
    readonly property bool blurs: !root.fieldBacked && IrisStyle.glassCompositor && root.compositorBlurred && root.glass
        && root.surfaceMaterial !== "solid" && (IrisStyle.glassy || root.surfaceMaterial === "glass")
    // A menu gives its blur up as it starts to go: the region trails the shrinking body by a frame, and when
    // the action it ran keeps the main thread busy the untinted blur showed around it.
    property bool blurWhileReceding: true
    readonly property var blurShapes: {
        if (!root.visible || root.opacity <= 0 || !root.blurs || root.fxLive || !(root.armed || root.presentation > 0) || root.emergence < 0.999) return []
        if (!root.blurWhileReceding && !root.open) return []
        void (root.x + root.y + chassis.x + chassis.y + chassis.width + chassis.height + chassis.radius + (root.parent?.x ?? 0) + (root.parent?.y ?? 0))
        const at = chassis.mapToItem(null, 0, 0)
        return [{ x: at.x, y: at.y, width: chassis.width, height: chassis.height, radius: chassis.radius }]
    }
    signal closed()
    // Settles in place: it arrives at 95 % of itself on its own centre, never from its origin, and
    // leaves at 97 %, so a blurred body only ever changes size, never fades.
    property bool settles: false
    // LowPan Shells (2026-11-12): abre no lugar (`settles`), mas ao fechar volta para a origem (ilha ou peça que a
    // abriu) como o morph normal do iRiS, em vez de ser cortada no lugar. O corpo de quem fica no campo da ilha
    // não esmaece; encolhendo para a origem ele some junto com o conteúdo. Usado pela Central de controle.
    property bool leavesToOrigin: false
    readonly property bool settlesNow: root.settles && !(root.leavesToOrigin && !root.open && !root.armed)
    readonly property real settleShare: 0.95
    readonly property real settleCut: 0.4

    property var originScene: null
    property string originOwner: ""
    property point windowOffset: Qt.point(0, 0)
    property real fromRadius: root.radius
    readonly property rect from: root.settlesNow
        ? Qt.rect(root.width * (1 - root.settleShare) / 2, root.height * (1 - root.settleShare) / 2,
            root.width * root.settleShare, root.height * root.settleShare)
        : root.originItem ? root.itemRect()
        : root.origin ? Qt.rect(root.origin.x - root.x, root.origin.y - root.y, root.origin.width, root.origin.height)
        : root.originScene ? root.sceneRect(root.originScene)
        : Qt.rect(root.width * 0.04, root.height * 0.04, root.width * 0.92, root.height * 0.92)
    readonly property bool absorbs: IrisStyle.revealDrops && !root.contentTravels && !root.settlesNow
        && (root.originItem !== null || root.origin !== null || root.originScene !== null)
    readonly property rect start: {
        if (!root.absorbs) return root.from
        const k = root.originShare
        return Qt.rect(root.from.x + root.from.width * (1 - k) / 2, root.from.y + root.from.height * (1 - k) / 2,
            root.from.width * k, root.from.height * k)
    }
    function sceneRect(r: var): rect {
        void (root.x + root.y + (root.parent?.x ?? 0) + (root.parent?.y ?? 0))
        const p = root.mapFromItem(null, r.x - root.windowOffset.x, r.y - root.windowOffset.y)
        return Qt.rect(p.x, p.y, r.width, r.height)
    }
    function itemRect(): rect {
        void (root.x + root.y + root.width + root.height + (root.Window.window?.height ?? 0))
        const item = root.originItem
        const p = item.mapToItem(root, 0, 0)
        return Qt.rect(p.x, p.y, item.width * item.scale, item.height * item.scale)
    }
    property bool armed: false
    property bool launched: false
    // The first frame a body's content is drawn in builds its whole scene (text, grids, images): measured
    // at 47 ms on the gallery, and the morph jumped from 0 to a fifth, faded in at 80 %, in one frame.
    // Between arming and launching it is drawn barely above the threshold where Qt stops drawing a
    // subtree (0.001 combined), so that frame is spent before the motion starts.
    readonly property bool warming: root.armed && !root.launched && root.presentation <= 0
    readonly property real warmth: 0.04
    property int launchFrames: 0
    Connections {
        target: root.Window.window
        enabled: root.armed && !root.launched
        // One frame is enough: it is the warm frame that built the content. A still window draws no second
        // one, so waiting for two always fell through to the timer (90 ms of nothing).
        function onFrameSwapped(): void { if (++root.launchFrames >= 1) root.launched = true }
    }
    Timer { interval: 90; running: root.armed && !root.launched; onTriggered: root.launched = true }
    onLaunchedChanged: if (root.launched && IrisMotionMeter.watching(root.motionSurface)) IrisMotionMeter.mark("launched")
    readonly property real presentation: root.kwinFx ? (root.fxVisible ? 1 : 0) : presentationSpring.value
    IrisSpring {
        id: presentationSpring
        surface: root.motionSurface
        to: root.armed && root.launched ? 1 : 0
        intent: root.animationDuration > 0 ? "move" : "auto"
        minimum: 0
        recedeScale: root.recedeScale
    }
    // LowPan Shells (2026-11-12): saída mais lenta só nesta tela (a Central usa 1,6); a entrada não muda.
    property real recedeScale: 1
    // Saindo em `settles`: o conteúdo esmaece de 1 a 0 entre o começo da saída e o corte (settleCut). Antes ele
    // seguia a rampa da entrada (no Direto, só abaixo de 0,36) e o corte em 0,4 levava o painel ainda inteiro.
    readonly property bool settleLeaving: root.settlesNow && !root.open && !root.armed && !root.kwinFx
    readonly property bool settleCutDue: root.settlesNow && !root.open && !root.armed && root.presentation > 0 && root.presentation <= root.settleCut
    onPresentationChanged: {
        // LowPan Shells (2026-11-12): o corte vai para o próximo ciclo (settleCutLater). Chamado aqui dentro, o
        // jump() mudava a mola no meio da atualização da própria `presentation` → "Binding loop detected" e o
        // valor ficava parado em ~0,4 até outra coisa recalcular: a Central travava antes de sumir.
        if (root.settleCutDue) return settleCutLater.restart()
        if (root.presentation <= 0 && !root.open) root.closed()
    }
    // jump() volta ao onPresentationChanged em 0 e ele mesmo emite `closed`.
    Timer { id: settleCutLater; interval: 0; onTriggered: if (root.settleCutDue) presentationSpring.jump() }
    Timer {
        interval: 3000
        running: !root.open && !root.armed && root.presentation > 0
        onTriggered: console.warn("iRiS: " + root.motionSurface + " closed but still drawn at " + root.presentation.toFixed(4)
            + " (" + (root.chassisKey || "own window") + ")")
    }
    // After every animation of the tick has run, so a sample is the frame that is drawn, not the one before it.
    Connections {
        target: root.Window.window
        enabled: IrisMotionMeter.watching(root.motionSurface) && (root.open || root.armed || root.presentation > 0)
        function onAfterAnimating(): void {
            const screen = root.QsWindow.window?.screen?.name ?? ""
            const at = chassis.mapToItem(null, 0, 0)
            const own = root.QsWindow.window
            const chassisWindow = IrisMotionMeter.chassisOf(screen)
            const bodyWindow = root.fieldBacked ? chassisWindow : own
            const wantsBlur = IrisStyle.glassCompositor && root.glass && root.surfaceMaterial !== "solid"
                && (IrisStyle.glassy || root.surfaceMaterial === "glass")
            IrisMotionMeter.sample({
                source: root,
                presentation: root.presentation,
                rect: { x: at.x + root.windowOffset.x, y: at.y + root.windowOffset.y, width: chassis.width, height: chassis.height },
                opacity: !(root.armed || root.presentation > 0) ? 0 : root.fieldBacked ? 1 : root.drawsOwnField ? root.emergence * fieldStrip.opacity : chassis.opacity,
                wantsBlur: wantsBlur,
                blurred: root.fieldBacked ? wantsBlur && root.chassisBodies.length > 0 : root.blurs && root.blurShapes.length > 0,
                published: root.chassisBodies.length > 0,
                sameWindow: bodyWindow === own,
                above: !root.fieldBacked && own !== chassisWindow,
                island: GlobalStates.irisIslandGeometry?.[screen] ?? null
            })
        }
    }

    readonly property bool fromIsland: !root.originItem && !root.origin && root.originScene !== null

    function captureOrigin(): void {
        if (root.settlesNow) { root.originOwner = ""; root.originScene = null; root.fromRadius = root.radius; return }
        if (root.originItem) { root.originOwner = ""; root.fromRadius = root.originItemRadius; return }
        if (root.origin) { root.originOwner = ""; root.fromRadius = root.origin.radius ?? root.radius; return }
        const origin = root.origin ?? GlobalStates.irisMorphOrigin
        const screenName = root.origin ? "" : (GlobalStates.focusedScreen?.name ?? "")
        if (origin && origin.width > 0 && (!origin.screen || origin.screen === screenName)) {
            root.originOwner = GlobalStates.irisMorphOwner
            root.originScene = Qt.rect(origin.x, origin.y, origin.width, origin.height)
            root.fromRadius = origin.radius ?? origin.height / 2
        } else {
            root.originOwner = ""
            const island = GlobalStates.irisIslandGeometry?.[screenName] ?? null
            root.originScene = island && island.width > 0 ? Qt.rect(island.x, island.y, island.width, island.height) : null
            root.fromRadius = island ? island.height / 2 : root.radius
        }
    }
    readonly property bool canArm: root.open && root.contentReady && root.width > 0 && root.height > 0
    function arm(): void {
        if (!root.canArm || root.armed) return
        if (root.presentation <= 0) {
            root.captureOrigin()
            root.launched = false
            root.launchFrames = 0
        }
        root.armed = true
        if (IrisMotionMeter.watching(root.motionSurface)) IrisMotionMeter.mark("armed")
    }
    // Timers, not Qt.callLater: a Place unloads with its loader and a queued call would outlive it.
    Timer { id: armLater; interval: 0; onTriggered: root.arm() }
    Timer { id: captureLater; interval: 0; onTriggered: root.captureOrigin() }
    onCanArmChanged: if (root.canArm) armLater.restart()
    // LowPan Shells (§21.85): recria a camada do recorte (chassisClip) logo após abrir, ainda no começo da animação.
    Timer { id: relayerLater; interval: 60; onTriggered: { chassisClip.relayerOff = true; relayerBack.restart() } }
    Timer { id: relayerBack; interval: 0; onTriggered: chassisClip.relayerOff = false }
    onOpenChanged: {
        if (root.open) relayerLater.restart()
        if (!root.open) {
            root.armed = false
            if (root.settlesNow) return
            // Saindo para a origem: a entrada no lugar não guardou nenhuma.
            if (root.settles) { root.captureOrigin(); return }
            if (root.fromIsland && root.originOwner.length === 0) captureLater.restart()
        } else {
            armLater.restart()
        }
    }
    Component.onCompleted: { armLater.restart(); if (root.open) relayerLater.restart() }

    function lerp(a: real, b: real): real { return a + (b - a) * Math.min(1, root.presentation) }
    readonly property bool pullsAcross: Math.abs(root.width / 2 - root.start.x - root.start.width / 2)
        >= Math.abs(root.height / 2 - root.start.y - root.start.height / 2)
    readonly property real lagging: {
        const p = Math.min(1, Math.max(0, root.presentation))
        return root.absorbs ? Math.pow(p, IrisStyle.pullLag) : p
    }
    readonly property real progressX: root.absorbs && !root.pullsAcross ? root.lagging : Math.min(1, root.presentation)
    readonly property real progressY: root.absorbs && root.pullsAcross ? root.lagging : Math.min(1, root.presentation)
    function lerpX(a: real, b: real): real { return a + (b - a) * root.progressX }
    function lerpY(a: real, b: real): real { return a + (b - a) * root.progressY }

    readonly property real swell: Math.max(0, root.presentation - 1)
    readonly property real anchorX: Math.max(0, Math.min(root.width, root.from.x + root.from.width / 2))
    readonly property real anchorY: Math.max(0, Math.min(root.height, root.from.y + root.from.height / 2))
    readonly property real swellX: Math.max(0, root.width - root.start.width) * root.swell
    readonly property real swellY: Math.max(0, root.height - root.start.height) * root.swell

    readonly property real restX: root.lerpX(root.start.x, 0)
    readonly property real restY: root.lerpY(root.start.y, 0)
    readonly property real restWidth: root.lerpX(root.start.width, root.width)
    readonly property real restHeight: root.lerpY(root.start.height, root.height)
    readonly property bool originBefore: root.pullsAcross
        ? root.start.x + root.start.width / 2 < root.width / 2
        : root.start.y + root.start.height / 2 < root.height / 2
    readonly property real rideX: !root.absorbs ? 0 : root.pullsAcross
        ? (root.originBefore ? root.restX + root.restWidth - root.width : root.restX)
        : root.restX + (root.restWidth - root.width) / 2
    readonly property real rideY: !root.absorbs ? 0 : root.pullsAcross
        ? root.restY + (root.restHeight - root.height) / 2
        : (root.originBefore ? root.restY + root.restHeight - root.height : root.restY)

    readonly property bool drops: IrisStyle.revealDrops && !root.contentTravels
    readonly property bool dropping: root.drops && root.presentation < 1
    readonly property real snapX: Math.round(root.x) - root.x
    readonly property real snapY: Math.round(root.y) - root.y

    // LowPan Shells: corpo + conteúdo num item só, para o efeito do KWin poder pegar os dois numa textura.
    Item {
        id: fxBody
        width: root.width
        height: root.height
        readonly property string fxKind: root.fxLive ? KWinOpenEffect.kind : ""
        // Burn-My-Windows: o shader convertido (scripts/kwin-open-effect.py) como efeito da camada, só durante a animação.
        // Não usar ShaderEffectSource com hideSource: ao desligar, a galeria ficava desenhada em preto (2026-11-08).
        layer.enabled: fxBody.fxKind === "shader"
        layer.effect: Item {
            id: fxEffect
            property var source
            Loader {
                id: fxShader
                anchors.fill: parent
                source: KWinOpenEffect.shaderQml
            }
            Binding { target: fxShader.item; property: "source"; value: fxEffect.source; when: fxShader.status === Loader.Ready }
            Binding { target: fxShader.item; property: "uProgress"; value: root.fxProgress; when: fxShader.status === Loader.Ready }
            Binding { target: fxShader.item; property: "uForOpeningF"; value: root.fxOpening ? 1 : 0; when: fxShader.status === Loader.Ready }
        }
        opacity: fxBody.fxKind === "fade" || fxBody.fxKind === "scale" || fxBody.fxKind === "kinetic" || fxBody.fxKind === "glide"
            ? Math.max(0, Math.min(1, root.fxShow)) : 1
        scale: fxBody.fxKind === "scale" || fxBody.fxKind === "kinetic" ? 0.8 + 0.2 * root.fxShow
            : fxBody.fxKind === "glide" ? 0.92 + 0.08 * root.fxShow : 1
        transform: Rotation {
            origin.x: fxBody.width / 2
            origin.y: 0
            axis { x: 1; y: 0; z: 0 }
            angle: fxBody.fxKind === "glide" ? -30 * (1 - Math.max(0, Math.min(1, root.fxShow))) : 0
        }

        Item {
            id: fieldStrip
            opacity: root.emergence
            visible: root.drawsOwnField
            x: -root.x
            y: -root.y
            width: root.parent ? root.parent.width : 0
            height: root.parent ? root.parent.height : 0

            Field.IrisField {
                anchors.fill: parent
                framed: false
                compositorAllowed: root.blurs && !root.fxLive
                sceneOrigin: {
                    void (root.x + root.y + (root.parent?.x ?? 0) + (root.parent?.y ?? 0))
                    const at = root.parent ? root.parent.mapToItem(null, 0, 0) : Qt.point(0, 0)
                    return Qt.point(root.windowOffset.x + at.x, root.windowOffset.y + at.y)
                }
                sceneSize: Qt.size(root.QsWindow.window?.screen?.width ?? 0, root.QsWindow.window?.screen?.height ?? 0)
                // From arming, with its blur: waiting for its content it drew its first rect unblurred.
                shapes: root.drawsOwnField && (root.armed || root.presentation > 0)
                    ? [Object.assign({ paints: true, fuse: 0, id: "place", glass: root.glass ? IrisStyle.surfaceGlass(root.motionSurface) : "solid" }, root.bodyRect)]
                    : []
            }
        }

        // LowPan Shells (2026-11-15, §21.83): recorte arredondado próprio no lugar do ClippingRectangle do Quickshell.
        // Ele desenha os filhos por um ShaderEffectSource com hideSource, cuja textura às vezes trava vazia: o
        // spotlight abria só com o corpo preto, sem conteúdo, até o shell reiniciar (estado do QML todo normal).
        // Aqui o conteúdo vai para a camada do próprio item, com o mesmo shader de cantos do Quickshell.
        Item {
            id: chassis
            x: Math.round(root.x + root.lerpX(root.start.x, 0)
                - root.swellX * root.anchorX / Math.max(1, root.width)) - root.x
            y: Math.round(root.y + root.lerpY(root.start.y, 0)
                - root.swellY * root.anchorY / Math.max(1, root.height)) - root.y
            width: Math.round(root.lerpX(root.start.width, root.width) + root.swellX)
            height: Math.round(root.lerpY(root.start.height, root.height) + root.swellY)
            property real radius: Math.min(width / 2, height / 2, root.absorbs
                ? root.lerp(Math.min(Math.min(root.start.width, root.start.height) / 2, root.fromRadius * root.originShare), root.radius)
                : root.lerp(root.fromRadius, root.radius))
            property color color: root.material === "field" ? IrisStyle.bodyClip
                : root.material === "compositor" ? IrisStyle.placeSurface : root.color
            // Visible from the request: forceActiveFocus() is ignored on invisible subtrees.
            visible: root.open || root.presentation > 0
            opacity: root.warming ? root.warmth : root.armed || root.presentation > 0 ? root.emergence : 0

            Rectangle {
                id: chassisShape
                anchors.fill: parent
                radius: chassis.radius
                antialiasing: chassis.radius > 0
                color: "#ffff0000"
                border.width: 0
                layer.enabled: true
                visible: false
            }

            Item {
                id: chassisClip
                anchors.fill: parent
                // LowPan Shells (§21.85): numa janela recém-criada a camada às vezes nasce com a textura vazia e não se
                // atualiza mais (corpo todo preto, sem conteúdo). Recriá-la logo depois de abrir resolve; ver relayerLater.
                property bool relayerOff: false
                layer.enabled: !chassisClip.relayerOff
                layer.samplerName: "content"
                layer.effect: ShaderEffect {
                    fragmentShader: "qrc:/Quickshell/Widgets/shaders/cliprect.frag.qsb"
                    property Item rect: chassisShape
                    property color backgroundColor: chassis.color
                    property color borderColor: "transparent"
                }

                Loader {
                    anchors.fill: parent
                    active: root.material === "wallpaper"
                    sourceComponent: IrisGlassPane {
                        sceneOffset: {
                            void (root.x + root.y + chassis.x + chassis.y + (root.parent?.x ?? 0) + (root.parent?.y ?? 0))
                            return chassis.mapToItem(null, 0, 0)
                        }
                        windowOffset: root.windowOffset
                        live: root.presentation > 0
                    }
                }

                IrisLightWash {
                    anchors.fill: parent
                    shapeRadius: chassis.radius
                    light: root.light
                    from: root.lightFrom
                    presence: Math.max(0, Math.min(1, root.presentation))
                }

                Item {
                    id: contentHost
                    // LowPan Shells: o contorno (rim) é pintado pelo IrisField POR DENTRO da borda e por baixo
                    // deste conteúdo; conteúdo opaco que rolava até a borda (ex.: cartões das Configurações)
                    // cobria a linha. Recuar o conteúdo pela largura do contorno mantém a linha sempre à vista.
                    readonly property int rimInset: IrisStyle.rim.a > 0 ? IrisStyle.rimWidth : 0
                    x: (root.contentTravels ? 0 : Math.round(root.x + root.rideX) - root.x - chassis.x) + rimInset
                    y: (root.contentTravels ? 0 : Math.round(root.y + root.rideY) - root.y - chassis.y) + rimInset
                    width: root.width - 2 * rimInset
                    height: root.height - 2 * rimInset
                    opacity: root.warming ? root.warmth
                        : root.settleLeaving ? IrisStyle.ramp(root.presentation, root.settleCut, 1 - root.settleCut)
                        : root.drops
                        ? IrisStyle.ramp(root.lagging, IrisStyle.dropRise, IrisStyle.dropSpan)
                        : IrisStyle.ramp(root.presentation, root.contentFadeStart, root.contentFadeSpan)
                    scale: {
                        if (root.presentation >= 1) return 1
                        if (root.drops) return 0.96 + 0.04 * root.lagging
                        if (IrisStyle.revealFades) return 1
                        if (IrisStyle.revealInflates)
                            return Math.max(0.35, Math.min(1, chassis.height / Math.max(1, root.height)))
                        return root.contentScaleFrom + (1 - root.contentScaleFrom) * root.presentation
                    }
                    // LowPan Shells (2026-11-12): continua ativo durante a saída. Com `enabled: root.open`, ao fechar
                    // todo o conteúdo virava "desativado" (botões a 40 % e sem fundo) e a Central ficava apagada até o
                    // corte; quem barra o clique na saída é o `exitShield` abaixo.
                    enabled: root.open || root.presentation > 0
                }

                // Barra clique, rolagem e passagem do mouse enquanto o corpo fecha (o conteúdo segue ativo para não
                // mudar de cara no meio da animação).
                MouseArea {
                    id: exitShield
                    anchors.fill: contentHost
                    visible: !root.open && root.presentation > 0
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons
                    onWheel: wheel => wheel.accepted = true
                }
            }
        }
    }
}
