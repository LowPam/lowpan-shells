pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services

Scope {
    id: root

    function open(action, mode): void {
        GlobalStates.regionSelectorAction = action
        GlobalStates.regionSelectorMode = mode
        GlobalStates.regionSelectorOpen = true
    }
    // Dedicated screenshot calls are always a rectangular capture. The unified
    // menu is the only entry point allowed to restore a previous toolbar choice.
    function screenshot(): void { GlobalStates.openRegionScreenshot() }
    function search(): void {
        open(RegionSelection.SnipAction.Search,
            (Config.options?.search?.imageSearch?.useCircleSelection ?? false)
                ? RegionSelection.SelectionMode.Circle : RegionSelection.SelectionMode.RectCorners)
    }
    function ocr(): void { open(RegionSelection.SnipAction.CharRecognition, RegionSelection.SelectionMode.RectCorners) }
    function record(): void { open(RegionSelection.SnipAction.Record, RegionSelection.SelectionMode.RectCorners) }
    function recordWithSound(): void { open(RegionSelection.SnipAction.RecordWithSound, RegionSelection.SelectionMode.RectCorners) }
    function menu(): void { GlobalStates.openRememberedRegionTool() }

    // LowPan Shells: capturas diretas (sem seletor), usadas pelos atalhos tomados do Spectacle no
    // modo iNiR: tela inteira (Shift+Print), janela ativa (Meta+Print) e gravar a tela (Meta+Alt+R).
    function directShot(kind: string): void {
        if (root.useSpectacle) {
            Quickshell.execDetached(["spectacle", kind === "window" ? "--activewindow" : "--current"])
            return
        }
        if (!CompositorService.isKWin) { root.screenshot(); return }
        const q = s => `'${StringUtils.shellSingleQuoteEscape(s)}'`
        const fmt = Config.options?.regionSelector?.screenshotNameFormat || "ss-%Y%m%d-%H%M%S"
        const copy = q(Quickshell.shellPath("scripts/clipboard-copy.sh"))
        const what = kind === "window" ? "--active-window" : ""
        Quickshell.execDetached(["/usr/bin/bash", "-c",
            `_dir=${q(Directories.screenshotsPath)} && mkdir -p "$_dir" && _ss="$_dir/$(date +${q(fmt)}).png"`
            + ` && ${q(Quickshell.shellPath("scripts/lowpan-kwin-capture"))} ${what} "$_ss"`
            + ` && ${copy} < "$_ss" && printf '%s' "$_ss" | ${copy} --primary`
            + ` && /usr/bin/notify-send "${Translation.tr("Screenshot copied")}" "$_ss" -a "Screenshot" -i camera-photo -t 3000`
            + ` || /usr/bin/notify-send "${Translation.tr("Screenshot failed")}" "KWin ScreenShot2" -a "Screenshot" -i dialog-error -t 4000`])
    }
    function recordScreen(): void {
        if (root.useSpectacle) { Quickshell.execDetached(["spectacle", "--record", "screen"]); return }
        Quickshell.execDetached(["/usr/bin/bash", "-c", `'${StringUtils.shellSingleQuoteEscape(Directories.recordScriptPath)}' --fullscreen`])
        RecorderStatus.scheduleQuickCheck()
    }

    // LowPan Shells: no KWin a captura é exclusiva (lowpan.captureTool). Com "spectacle" (padrão)
    // todo pedido vai para o Spectacle; com "inir" o seletor do iNiR abre (imagem via KWin ScreenShot2).
    readonly property bool useSpectacle: CompositorService.isKWin
        && (Config.options?.lowpan?.captureTool ?? "spectacle") !== "inir"
    Connections {
        target: GlobalStates
        enabled: root.useSpectacle
        function onRegionSelectorOpenChanged(): void {
            if (!GlobalStates.regionSelectorOpen) return
            const a = GlobalStates.regionSelectorAction
            const rec = a === RegionSelection.SnipAction.Record || a === RegionSelection.SnipAction.RecordWithSound
            GlobalStates.regionSelectorOpen = false
            Quickshell.execDetached(rec ? ["spectacle", "--record", "region"] : ["spectacle", "--region"])
        }
    }

    IpcHandler {
        target: "region"
        function screenshot(): void { root.screenshot() }
        function search(): void { root.search() }
        function googleLens(): void { root.search() }
        function ocr(): void { root.ocr() }
        function record(): void { root.record() }
        function recordWithSound(): void { root.recordWithSound() }
        function menu(): void { root.menu() }
        function fullscreen(): void { root.directShot("screen") }
        function window(): void { root.directShot("window") }
        function recordScreen(): void { root.recordScreen() }
        function dismiss(): void { GlobalStates.regionSelectorOpen = false }
        function current(): string {
            return JSON.stringify({
                open: GlobalStates.regionSelectorOpen,
                action: GlobalStates.regionSelectorAction,
                mode: GlobalStates.regionSelectorMode
            })
        }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: Item {
            GlobalShortcut { name: "regionScreenshot"; description: "Takes a screenshot of the selected region"; onPressed: root.screenshot() }
            GlobalShortcut { name: "regionSearch"; description: "Searches the selected region"; onPressed: root.search() }
            GlobalShortcut { name: "regionOcr"; description: "Recognizes text in the selected region"; onPressed: root.ocr() }
            GlobalShortcut { name: "regionRecord"; description: "Records the selected region"; onPressed: root.record() }
            GlobalShortcut { name: "regionRecordWithSound"; description: "Records the selected region with the configured audio profile"; onPressed: root.recordWithSound() }
            GlobalShortcut { name: "regionMenu"; description: "Opens the unified snip menu"; onPressed: root.menu() }
        }
    }
}
