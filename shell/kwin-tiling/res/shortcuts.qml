import QtQuick;
import org.kde.kwin;

Item {
    // LowPan Tiling: nome do atalho no idioma do sistema (inglês por padrão; português em sistema pt), como o shell em "auto"
    function lpName(en, pt) {
        return "LowPan Tiling: " + (String(Qt.locale().name).toLowerCase().indexOf("pt") === 0 ? pt : en);
    }

    id: dbus;
    function getToggleDock() {
        return toggleDock;
    }
    ShortcutHandler {
        id: toggleDock;

        name: "LowPanTilingtoggleDock";
        text: "LowPan Tiling: Toggle Dock";
        sequence: "";
    }

    function getFocusNext() {
        return focusNext;
    }
    ShortcutHandler {
        id: focusNext;

        name: "LowPanTilingFocusNext";
        text: "LowPan Tiling: Focus Next";
        sequence: "";
    }
    function getFocusPrev() {
        return focusPrev;
    }
    ShortcutHandler {
        id: focusPrev;

        name: "LowPanTilingFocusPrev";
        text: "LowPan Tiling: Focus Previous";
        sequence: "";
    }

    function getFocusDown() {
        return focusDown;
    }
    ShortcutHandler {
        id: focusDown;

        name: "LowPanTilingFocusDown";
        text: "LowPan Tiling: Focus Down";
        sequence: "";
    }
    function getFocusUp() {
        return focusUp;
    }
    ShortcutHandler {
        id: focusUp;

        name: "LowPanTilingFocusUp";
        text: "LowPan Tiling: Focus Up";
        sequence: "";
    }
    function getFocusLeft() {
        return focusLeft;
    }
    ShortcutHandler {
        id: focusLeft;

        name: "LowPanTilingFocusLeft";
        text: "LowPan Tiling: Focus Left";
        sequence: "";
    }
    function getFocusRight() {
        return focusRight;
    }
    ShortcutHandler {
        id: focusRight;

        name: "LowPanTilingFocusRight";
        text: "LowPan Tiling: Focus Right";
        sequence: "";
    }
    function getShiftDown() {
        return shiftDown;
    }
    ShortcutHandler {
        id: shiftDown;

        name: "LowPanTilingShiftDown";
        text: "LowPan Tiling: Move Down/Next";
        sequence: "";
    }
    function getShiftUp() {
        return shiftUp;
    }
    ShortcutHandler {
        id: shiftUp;

        name: "LowPanTilingShiftUp";
        text: "LowPan Tiling: Move Up/Prev";
        sequence: "";
    }
    function getShiftLeft() {
        return shiftLeft;
    }
    ShortcutHandler {
        id: shiftLeft;

        name: "LowPanTilingShiftLeft";
        text: "LowPan Tiling: Move Left";
        sequence: "";
    }
    function getShiftRight() {
        return shiftRight;
    }
    ShortcutHandler {
        id: shiftRight;

        name: "LowPanTilingShiftRight";
        text: "LowPan Tiling: Move Right";
        sequence: "";
    }
    function getGrowHeight() {
        return growHeight;
    }
    ShortcutHandler {
        id: growHeight;

        name: "LowPanTilingGrowHeight";
        text: "LowPan Tiling: Grow Height";
        sequence: "";
    }
    function getShrinkHeight() {
        return shrinkHeight;
    }
    ShortcutHandler {
        id: shrinkHeight;

        name: "LowPanTilingShrinkHeight";
        text: "LowPan Tiling: Shrink Height";
        sequence: "";
    }
    function getShrinkWidth() {
        return shrinkWidth;
    }
    ShortcutHandler {
        id: shrinkWidth;

        name: "LowPanTilingShrinkWidth";
        text: "LowPan Tiling: Shrink Width";
        sequence: "";
    }
    function getGrowWidth() {
        return growWidth;
    }
    ShortcutHandler {
        id: growWidth;

        name: "LowPanTilinggrowWidth";
        text: "LowPan Tiling: Grow Width";
        sequence: "";
    }
    function getIncrease() {
        return increase;
    }
    ShortcutHandler {
        id: increase;

        name: "LowPanTilingIncrease";
        text: "LowPan Tiling: Increase";
        sequence: "";
    }
    function getDecrease() {
        return decrease;
    }
    ShortcutHandler {
        id: decrease;

        name: "LowPanTilingDecrease";
        text: "LowPan Tiling: Decrease";
        sequence: "";
    }
    function getToggleFloat() {
        return toggleFloat;
    }
    ShortcutHandler {
        id: toggleFloat;

        name: "LowPanTilingToggleFloat";
        text: "LowPan Tiling: Toggle Float";
        sequence: "";
    }
    function getFloatAll() {
        return floatAll;
    }
    ShortcutHandler {
        id: floatAll;

        name: "LowPanTilingFloatAll";
        text: "LowPan Tiling: Toggle Float All";
        sequence: "";
    }
    function getNextLayout() {
        return nextLayout;
    }
    ShortcutHandler {
        id: nextLayout;

        name: "LowPanTilingNextLayout";
        text: "LowPan Tiling: Next Layout";
        sequence: "";
    }
    function getPreviousLayout() {
        return previousLayout;
    }
    ShortcutHandler {
        id: previousLayout;

        name: "LowPanTilingPreviousLayout";
        text: "LowPan Tiling: Previous Layout";
        sequence: "";
    }
    function getRotate() {
        return rotate;
    }
    ShortcutHandler {
        id: rotate;

        name: "LowPanTilingRotate";
        text: "LowPan Tiling: Rotate";
        sequence: "";
    }
    function getRotatePart() {
        return rotatePart;
    }
    ShortcutHandler {
        id: rotatePart;

        name: "LowPanTilingRotatePart";
        text: "LowPan Tiling: Rotate Part";
        sequence: "";
    }
    function getSetMaster() {
        return setMaster;
    }
    ShortcutHandler {
        id: setMaster;

        name: "LowPanTilingSetMaster";
        text: "LowPan Tiling: Set master";
        sequence: "";
    }
    function getTileLayout() {
        return tileLayout;
    }
    ShortcutHandler {
        id: tileLayout;

        name: "LowPanTilingTileLayout";
        text: "LowPan Tiling: Tile Layout";
        sequence: "";
    }
    function getMonocleLayout() {
        return monocleLayout;
    }
    ShortcutHandler {
        id: monocleLayout;

        name: "LowPanTilingMonocleLayout";
        text: "LowPan Tiling: Monocle Layout";
        sequence: "";
    }
    function getThreeColumnLayout() {
        return treeColumnLayout;
    }
    ShortcutHandler {
        id: treeColumnLayout;

        name: "LowPanTilingTreeColumnLayout";
        text: "LowPan Tiling: Three Column Layout";
        sequence: "";
    }
    function getSpreadLayout() {
        return spreadLayout;
    }
    ShortcutHandler {
        id: spreadLayout;

        name: "LowPanTilingSpreadLayout";
        text: "LowPan Tiling: Spread Layout";
        sequence: "";
    }
    function getStairLayout() {
        return stairLayout;
    }
    ShortcutHandler {
        id: stairLayout;

        name: "LowPanTilingStairLayout";
        text: "LowPan Tiling: Stair Layout";
        sequence: "";
    }
    function getFloatingLayout() {
        return floatingLayout;
    }
    ShortcutHandler {
        id: floatingLayout;

        name: "LowPanTilingFloatingLayout";
        text: "LowPan Tiling: Floating Layout";
        sequence: "";
    }
    function getQuarterLayout() {
        return quarterLayout;
    }
    ShortcutHandler {
        id: quarterLayout;

        name: "LowPanTilingQuarterLayout";
        text: "LowPan Tiling: Quarter Layout";
        sequence: "";
    }
    function getStackedLayout() {
        return stackedLayout;
    }
    ShortcutHandler {
        id: stackedLayout;

        name: "LowPanTilingStackedLayout";
        text: "LowPan Tiling: Stacked Layout";
        sequence: "";
    }
    function getBTreeLayout() {
        return bTreeLayout;
    }
    ShortcutHandler {
        id: bTreeLayout;

        name: "LowPanTilingBTreeLayout";
        text: "LowPan Tiling: BTree Layout";
        sequence: "";
    }
    function getSpiralLayout() {
        return spiralLayout;
    }
    ShortcutHandler {
        id: spiralLayout;

        name: "LowPanTilingSpiralLayout";
        text: "LowPan Tiling: Spiral Layout";
        sequence: "";
    }
    function getColumnsLayout() {
        return columnsLayout;
    }
    ShortcutHandler {
        id: columnsLayout;

        name: "LowPanTilingColumnsLayout";
        text: "LowPan Tiling: Columns Layout";
        sequence: "";
    }

    // LowPan Tiling: ações do Niri (sem tecla padrão; o liga/desliga do tiling atribui)
    function getNiriConsumeLeft() { return niriConsumeLeft; }
    ShortcutHandler { id: niriConsumeLeft; name: "LowPanTilingNiriConsumeLeft"; text: lpName("Consume or expel window (left)", "Juntar ou separar janela (esquerda)"); sequence: ""; }
    function getNiriConsumeRight() { return niriConsumeRight; }
    ShortcutHandler { id: niriConsumeRight; name: "LowPanTilingNiriConsumeRight"; text: lpName("Consume or expel window (right)", "Juntar ou separar janela (direita)"); sequence: ""; }
    function getNiriCycleWidth() { return niriCycleWidth; }
    ShortcutHandler { id: niriCycleWidth; name: "LowPanTilingNiriCycleWidth"; text: lpName("Cycle column width (1/3, 1/2, 2/3)", "Alternar largura da coluna (1/3, 1/2, 2/3)"); sequence: ""; }
    function getNiriMaximizeColumn() { return niriMaximizeColumn; }
    ShortcutHandler { id: niriMaximizeColumn; name: "LowPanTilingNiriMaximizeColumn"; text: lpName("Full-width column", "Coluna na largura toda"); sequence: ""; }
    function getNiriCenterColumn() { return niriCenterColumn; }
    ShortcutHandler { id: niriCenterColumn; name: "LowPanTilingNiriCenterColumn"; text: lpName("Center the column", "Centralizar a coluna"); sequence: ""; }
    function getNiriToggleTabbed() { return niriToggleTabbed; }
    ShortcutHandler { id: niriToggleTabbed; name: "LowPanTilingNiriToggleTabbed"; text: lpName("Tabbed column (on/off)", "Coluna em abas (ligar/desligar)"); sequence: ""; }
    function getNiriResetHeight() { return niriResetHeight; }
    ShortcutHandler { id: niriResetHeight; name: "LowPanTilingNiriResetHeight"; text: lpName("Reset heights in the column", "Altura automática na coluna"); sequence: ""; }
    function getNiriFocusFirst() { return niriFocusFirst; }
    ShortcutHandler { id: niriFocusFirst; name: "LowPanTilingNiriFocusFirst"; text: lpName("Focus the first column", "Focar a primeira coluna"); sequence: ""; }
    function getNiriFocusLast() { return niriFocusLast; }
    ShortcutHandler { id: niriFocusLast; name: "LowPanTilingNiriFocusLast"; text: lpName("Focus the last column", "Focar a última coluna"); sequence: ""; }
    function getNiriMoveToFirst() { return niriMoveToFirst; }
    ShortcutHandler { id: niriMoveToFirst; name: "LowPanTilingNiriMoveToFirst"; text: lpName("Move the column to the start", "Levar a coluna ao começo"); sequence: ""; }
    function getNiriMoveToLast() { return niriMoveToLast; }
    ShortcutHandler { id: niriMoveToLast; name: "LowPanTilingNiriMoveToLast"; text: lpName("Move the column to the end", "Levar a coluna ao fim"); sequence: ""; }
    function getNiriFocusFloating() { return niriFocusFloating; }
    ShortcutHandler { id: niriFocusFloating; name: "LowPanTilingNiriFocusFloating"; text: lpName("Switch focus between floating and tiled", "Alternar foco entre flutuantes e lado a lado"); sequence: ""; }
    function getNiriExpandColumn() { return niriExpandColumn; }
    ShortcutHandler { id: niriExpandColumn; name: "LowPanTilingNiriExpandColumn"; text: lpName("Expand the column into the free space", "Expandir a coluna até o espaço livre"); sequence: ""; }
    function getNiriPresetOff() { return niriPresetOff; }
    ShortcutHandler { id: niriPresetOff; name: "LowPanTilingNiriPresetOff"; text: lpName("Layout: off (one column per window)", "Layout: desligado (uma coluna por janela)"); sequence: ""; }
    function getNiriPresetMasterLeft() { return niriPresetMasterLeft; }
    ShortcutHandler { id: niriPresetMasterLeft; name: "LowPanTilingNiriPresetMasterLeft"; text: lpName("Layout: master on the left", "Layout: mestre à esquerda"); sequence: ""; }
    function getNiriPresetMasterRight() { return niriPresetMasterRight; }
    ShortcutHandler { id: niriPresetMasterRight; name: "LowPanTilingNiriPresetMasterRight"; text: lpName("Layout: master on the right", "Layout: mestre à direita"); sequence: ""; }
    function getNiriPresetColumns() { return niriPresetColumns; }
    ShortcutHandler { id: niriPresetColumns; name: "LowPanTilingNiriPresetColumns"; text: lpName("Layout: equal columns", "Layout: colunas iguais"); sequence: ""; }
    function getNiriPresetMonocle() { return niriPresetMonocle; }
    ShortcutHandler { id: niriPresetMonocle; name: "LowPanTilingNiriPresetMonocle"; text: lpName("Layout: monocle (one tabbed column)", "Layout: monocle (uma coluna em abas)"); sequence: ""; }
    function getNiriPresetCycle() { return niriPresetCycle; }
    ShortcutHandler { id: niriPresetCycle; name: "LowPanTilingNiriPresetCycle"; text: lpName("Layout: next", "Layout: próximo"); sequence: ""; }
    function getNiriPresetPromote() { return niriPresetPromote; }
    ShortcutHandler { id: niriPresetPromote; name: "LowPanTilingNiriPresetPromote"; text: lpName("Layout: promote the window to master", "Layout: promover a janela a mestre"); sequence: ""; }
    // LowPan Tiling: vários monitores
    function getNiriFocusMonitorLeft() { return niriFocusMonitorLeft; }
    ShortcutHandler { id: niriFocusMonitorLeft; name: "LowPanTilingNiriFocusMonitorLeft"; text: lpName("Focus the monitor on the left", "Focar o monitor à esquerda"); sequence: ""; }
    function getNiriFocusMonitorRight() { return niriFocusMonitorRight; }
    ShortcutHandler { id: niriFocusMonitorRight; name: "LowPanTilingNiriFocusMonitorRight"; text: lpName("Focus the monitor on the right", "Focar o monitor à direita"); sequence: ""; }
    function getNiriMoveColumnToMonitorLeft() { return niriMoveColumnToMonitorLeft; }
    ShortcutHandler { id: niriMoveColumnToMonitorLeft; name: "LowPanTilingNiriMoveColumnToMonitorLeft"; text: lpName("Move the column to the monitor on the left", "Levar a coluna ao monitor à esquerda"); sequence: ""; }
    function getNiriMoveColumnToMonitorRight() { return niriMoveColumnToMonitorRight; }
    ShortcutHandler { id: niriMoveColumnToMonitorRight; name: "LowPanTilingNiriMoveColumnToMonitorRight"; text: lpName("Move the column to the monitor on the right", "Levar a coluna ao monitor à direita"); sequence: ""; }
}
