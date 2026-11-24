// Copyright (c) 2018-2019 Eon S. Jeon <esjeon@hyunmu.am>
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

class KWinConfig implements IConfig {
  // Dock parameters
  public dockOrder: [number, number, number, number];
  public dockHHeight: number;
  public dockHWide: number;
  public dockHGap: number;
  public dockHEdgeGap: number;
  public dockHAlignment: number;
  public dockHEdgeAlignment: number;
  public dockVHeight: number;
  public dockVWide: number;
  public dockVGap: number;
  public dockVEdgeGap: number;
  public dockVAlignment: number;
  public dockVEdgeAlignment: number;
  public dockSurfacesConfig: string[];
  public dockWindowClassConfig: string[];

  //#region Layout
  public layoutOrder: string[];
  public layoutFactories: { [key: string]: () => ILayout };
  public soleWindowWidth: number;
  public soleWindowHeight: number;
  public soleWindowNoBorders: boolean;
  public soleWindowNoGaps: boolean;
  public tileLayoutInitialAngle: string;
  public quarterLayoutReset: boolean;
  public columnsLayoutInitialAngle: string;
  public columnsBalanced: boolean;
  public columnsLayerConf: string[];
  public tiledWindowsLayer: number;
  public floatedWindowsLayer: number;
  public monocleMaximize: boolean;
  public monocleMinimizeRest: boolean;
  public stairReverse: boolean; // kwin.specific
  //#endregion

  //#region Features
  public adjustLayout: boolean;
  public adjustLayoutLive: boolean;
  public keepTilingOnDrag: boolean;
  public notificationDuration: number;
  public noTileBorder: boolean;
  public limitTileWidthRatio: number;
  //#endregion

  //#region Gap
  public screenGapBottom: number;
  public screenGapLeft: number;
  public screenGapRight: number;
  public screenGapTop: number;
  public screenGapBetween: number;
  public gapsOverrideConfig: string[];
  //#endregion

  //#region Behavior
  public directionalKeyMode: "dwm" | "focus";
  public newWindowPosition: number;
  //#endregion

  //#region kwin.specific
  public layoutPerActivity: boolean;
  public layoutPerDesktop: boolean;
  public preventMinimize: boolean;
  public preventProtrusion: boolean;
  public floatSkipPager: boolean;
  //#endregion

  //#region kwin.specific Rules
  public floatUtility: boolean;

  public floatingClass: string[];
  public floatingTitle: string[];
  public ignoreClass: string[];
  public ignoreTitle: string[];
  public ignoreRole: string[];

  public ignoreActivity: string[];
  public ignoreScreen: string[];
  public ignoreVDesktop: string[];

  public screenDefaultLayout: string[];

  public tileNothing: boolean;
  public tilingClass: string[];
  //#endregion

  constructor() {
    function separate(str: string, separator: string): string[] {
      if (!str || typeof str !== "string") return [];
      return str
        .split(separator)
        .map((part) => part.trim())
        .filter((part) => part != "");
    }

    if (KWIN.readConfig("logging", false)) {
      let logParts: [LogPartition, string[]][] = [];
      let newWindowSubmodules: string[] = [];
      if (KWIN.readConfig("logNewWindows", false))
        newWindowSubmodules.push("1");
      if (KWIN.readConfig("logFilteredWindows", false))
        newWindowSubmodules.push("2");
      if (KWIN.readConfig("logUnmanagedWindows", false))
        newWindowSubmodules.push("3");
      if (newWindowSubmodules.length > 0)
        logParts.push([LogPartitions.newWindow, newWindowSubmodules]);

      if (KWIN.readConfig("logWorkspaceSignals", false)) {
        let workspaceSignalsSubmodules = separate(
          KWIN.readConfig("logWorkspaceSignalsSubmodules", ""),
          ","
        );
        logParts.push([
          LogPartitions.workspaceSignals,
          workspaceSignalsSubmodules,
        ]);
      }
      if (KWIN.readConfig("logWindowSignals", false)) {
        let windowSignalsSubmodules = separate(
          KWIN.readConfig("logWindowSignalsSubmodules", ""),
          ","
        );
        logParts.push([LogPartitions.windowSignals, windowSignalsSubmodules]);
      }
      if (KWIN.readConfig("logOther", false)) {
        let otherSubmodules = separate(
          KWIN.readConfig("logOtherSubmodules", ""),
          ","
        );
        logParts.push([LogPartitions.other, otherSubmodules]);
      }
      const logFilters = KWIN.readConfig("logFilter", false)
        ? separate(KWIN.readConfig("logFilterStr", ""), ",")
        : [];
      LOG = new Logging(logParts, logFilters);
    } else LOG = undefined;

    interface ISortedLayouts {
      order: number;
      layoutClass: ILayoutClass;
    }
    let sortedLayouts: ISortedLayouts[] = [];

    this.layoutFactories = {};
    (
      [
        ["tileLayoutOrder", 0, TileLayout],
        ["monocleLayoutOrder", 0, MonocleLayout],
        ["threeColumnLayoutOrder", 0, ThreeColumnLayout],
        ["spiralLayoutOrder", 0, SpiralLayout],
        ["quarterLayoutOrder", 0, QuarterLayout],
        ["stackedLayoutOrder", 0, StackedLayout],
        ["columnsLayoutOrder", 0, ColumnsLayout],
        ["spreadLayoutOrder", 0, SpreadLayout],
        ["floatingLayoutOrder", 2, FloatingLayout],
        ["stairLayoutOrder", 0, StairLayout],
        ["binaryTreeLayoutOrder", 0, BTreeLayout],
        ["cascadeLayoutOrder", 0, CascadeLayout],
        ["niriLayoutOrder", 1, NiriLayout], // LowPan Tiling
      ] as Array<[string, number, ILayoutClass]>
    ).forEach(([configKey, defaultValue, layoutClass]) => {
      let order = validateNumber(
        KWIN.readConfig(configKey, defaultValue),
        0,
        13
      );
      if (order instanceof Err) {
        order = defaultValue;
        warning(
          `kwinconfig: layout order for ${layoutClass.id} is invalid, using default value ${order}`
        );
      }
      if (order === 0) return;
      sortedLayouts.push({ order: order, layoutClass: layoutClass });
    });
    sortedLayouts.sort((a, b) => a.order - b.order);
    if (sortedLayouts.length === 0) {
      sortedLayouts.push({ order: 1, layoutClass: TileLayout });
    }
    this.layoutOrder = [];
    sortedLayouts.forEach(({ layoutClass }) => {
      this.layoutOrder.push(layoutClass.id);
      this.layoutFactories[layoutClass.id] = () => new layoutClass();
    });

    this.dockOrder = [
      KWIN.readConfig("dockOrderLeft", 1),
      KWIN.readConfig("dockOrderTop", 2),
      KWIN.readConfig("dockOrderRight", 3),
      KWIN.readConfig("dockOrderBottom", 4),
    ];
    this.dockHHeight = KWIN.readConfig("dockHHeight", 15);
    this.dockHWide = KWIN.readConfig("dockHWide", 100);
    this.dockHGap = KWIN.readConfig("dockHGap", 0);
    this.dockHEdgeGap = KWIN.readConfig("dockHEdgeGap", 0);
    this.dockHAlignment = KWIN.readConfig("dockHAlignment", 0);
    this.dockHEdgeAlignment = KWIN.readConfig("dockHEdgeAlignment", 0);
    this.dockVHeight = KWIN.readConfig("dockVHeight", 100);
    this.dockVWide = KWIN.readConfig("dockVWide", 15);
    this.dockVEdgeGap = KWIN.readConfig("dockVEdgeGap", 0);
    this.dockVGap = KWIN.readConfig("dockVGap", 0);
    this.dockVAlignment = KWIN.readConfig("dockVAlignment", 0);
    this.dockVEdgeAlignment = KWIN.readConfig("dockVEdgeAlignment", 0);
    this.dockSurfacesConfig = separate(
      KWIN.readConfig("dockSurfacesConfig", ""),
      "\n"
    );
    this.dockWindowClassConfig = separate(
      KWIN.readConfig("dockWindowClassConfig", ""),
      "\n"
    );

    this.soleWindowWidth = KWIN.readConfig("soleWindowWidth", 100);
    this.soleWindowHeight = KWIN.readConfig("soleWindowHeight", 100);
    this.soleWindowNoBorders = KWIN.readConfig("soleWindowNoBorders", false);
    this.soleWindowNoGaps = KWIN.readConfig("soleWindowNoGaps", false);
    this.tileLayoutInitialAngle = KWIN.readConfig(
      "tileLayoutInitialRotationAngle",
      "0"
    );
    this.columnsLayoutInitialAngle = KWIN.readConfig(
      "columnsLayoutInitialRotationAngle",
      "0"
    );
    this.columnsBalanced = KWIN.readConfig("columnsBalanced", false);
    this.columnsLayerConf = separate(
      KWIN.readConfig("columnsLayerConf", ""),
      ","
    );
    this.tiledWindowsLayer = getWindowLayer(
      KWIN.readConfig("tiledWindowsLayer", 0)
    );
    this.floatedWindowsLayer = getWindowLayer(
      KWIN.readConfig("floatedWindowsLayer", 1)
    );
    this.quarterLayoutReset = KWIN.readConfig("quarterLayoutReset", false);
    this.monocleMaximize = KWIN.readConfig("monocleMaximize", true);
    this.monocleMinimizeRest = KWIN.readConfig("monocleMinimizeRest", false);
    this.stairReverse = KWIN.readConfig("stairReverse", false);

    this.adjustLayout = KWIN.readConfig("adjustLayout", true);
    this.adjustLayoutLive = KWIN.readConfig("adjustLayoutLive", true);
    this.keepTilingOnDrag = KWIN.readConfig("keepTilingOnDrag", true);
    this.noTileBorder = KWIN.readConfig("noTileBorder", false);

    this.limitTileWidthRatio = 0;
    if (KWIN.readConfig("limitTileWidth", false))
      this.limitTileWidthRatio = KWIN.readConfig("limitTileWidthRatio", 1.6);

    this.screenGapBottom = KWIN.readConfig("screenGapBottom", 25);
    this.screenGapLeft = KWIN.readConfig("screenGapLeft", 25);
    this.screenGapRight = KWIN.readConfig("screenGapRight", 25);
    this.screenGapTop = KWIN.readConfig("screenGapTop", 25);
    this.screenGapBetween = KWIN.readConfig("screenGapBetween", 25);
    this.gapsOverrideConfig = separate(
      KWIN.readConfig("gapsOverrideConfig", ""),
      "\n"
    );

    const directionalKeyDwm = KWIN.readConfig("directionalKeyDwm", false);
    const directionalKeyFocus = KWIN.readConfig("directionalKeyFocus", true);
    this.directionalKeyMode = directionalKeyDwm ? "dwm" : "focus";
    this.newWindowPosition = KWIN.readConfig("newWindowPosition", 0);

    this.layoutPerActivity = KWIN.readConfig("layoutPerActivity", true);
    this.layoutPerDesktop = KWIN.readConfig("layoutPerDesktop", true);
    this.floatUtility = KWIN.readConfig("floatUtility", true);
    this.preventMinimize = KWIN.readConfig("preventMinimize", false);
    this.preventProtrusion = KWIN.readConfig("preventProtrusion", false) /* LowPan Tiling: a faixa põe colunas fora da tela */;
    this.notificationDuration = KWIN.readConfig("notificationDuration", 1000);
    this.floatSkipPager = KWIN.readConfig("floatSkipPagerWindows", false);

    this.floatingClass = separate(KWIN.readConfig("floatingClass", ""), ",");
    this.floatingTitle = separate(KWIN.readConfig("floatingTitle", ""), ",");
    this.ignoreActivity = separate(KWIN.readConfig("ignoreActivity", ""), ",");
    this.ignoreClass = separate(
      KWIN.readConfig(
        "ignoreClass",
        "krunner,yakuake,spectacle,kded5,xwaylandvideobridge,plasmashell,ksplashqml,org.kde.plasmashell,org.kde.polkit-kde-authentication-agent-1,org.kde.kruler,kruler,kwin_wayland,ksmserver-logout-greeter,quickshell"
      ),
      ","
    );
    this.ignoreRole = separate(KWIN.readConfig("ignoreRole", "quake"), ",");

    this.ignoreScreen = separate(KWIN.readConfig("ignoreScreen", ""), ",");
    this.ignoreVDesktop = separate(KWIN.readConfig("ignoreVDesktop", ""), ",");
    this.ignoreTitle = separate(KWIN.readConfig("ignoreTitle", ""), ",");

    this.screenDefaultLayout = separate(
      KWIN.readConfig("screenDefaultLayout", ""),
      ","
    );

    this.tilingClass = separate(KWIN.readConfig("tilingClass", ""), ",");
    this.tileNothing = KWIN.readConfig("tileNothing", false);

    if (this.preventMinimize && this.monocleMinimizeRest) {
      this.preventMinimize = false;
    }
  }

  public toString(): string {
    return "Config(" + JSON.stringify(this, undefined, 2) + ")";
  }
}

// /* HACK: save casting */
var KWINCONFIG: KWinConfig;
