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

/**
 * LowPan Tiling: regras de janela do iNiR (defaults/niri/config.d/30-window-rules.kdl), fixas no motor (§21.17):
 *  - "pip": Picture-in-Picture do Firefox/Zen abre flutuando;
 *  - "toast": notificações do Steam flutuam no canto de baixo à direita, sem roubar o foco.
 * (Cantos arredondados e opacidade das inativas são só visuais: ficam fora do tiling.)
 */
function lpInirRule(win: any): "pip" | "toast" | null {
  const cls = String(win.resourceClass || "").toLowerCase();
  const app = String(win.desktopFileName || "").toLowerCase();
  const title = String(win.caption || "");
  // Firefox/Zen (iNiR) + família Chromium: no Edge o PiP tem classe "msedge" (a janela principal é "microsoft-edge")
  // e título "Picture-in-picture" (visto em 2026-11-06)
  const browser = /(firefox|zen)$/.test(cls) || /(firefox|zen)$/.test(app) || cls === "zen-browser" ||
    /^(msedge|microsoft-edge.*|chrome|google-chrome.*|chromium.*|brave.*|vivaldi.*|opera.*)$/.test(cls);
  if (browser && /^(picture.in.picture|imagem em imagem|imagem sobre imagem)$/i.test(title)) return "pip";
  if ((cls === "steam" || app === "steam") && /^notificationtoasts_\d+_desktop$/.test(title)) return "toast";
  return null;
}

/** WezTerm escolhe a largura da própria coluna (default-column-width {} no iNiR) */
function lpOwnWidth(win: any): boolean {
  const cls = String(win.resourceClass || "").toLowerCase();
  const app = String(win.desktopFileName || "").toLowerCase();
  return cls === "org.wezfurlong.wezterm" || app === "org.wezfurlong.wezterm";
}

class KWinWindow implements IDriverWindow {
  public static generateID(w: Window) {
    return w.internalId.toString();
  }

  private readonly workspace: Workspace;
  private readonly isFloatByTitle: boolean;
  private readonly isIgnoredByConfig: boolean;
  public readonly window: Window;
  public readonly id: string;

  public get fullScreen(): boolean {
    return this.window.fullScreen;
  }

  public get geometry(): Rect {
    return toRect(this.window.frameGeometry);
  }

  public get windowClassName(): string {
    return this.window.resourceClass;
  }

  public get shouldIgnore(): boolean {
    if (this.window.deleted) return true;
    return (
      this.window.specialWindow ||
      this.window.resourceClass === "plasmashell" ||
      this.isIgnoredByConfig
    );
  }

  /**
   * LowPan Tiling: o app está na lista "sempre flutuar" (kwinrc floatingClass, Configurações › Janelas › Tiling).
   * Lida a cada consulta: o motor relê a lista a cada segundo e a mudança vale para as janelas já abertas.
   */
  public get lpFloatApp(): boolean {
    return KWinWindow.lpInList(KWINCONFIG.floatingClass, this.window);
  }

  public static lpInList(list: string[], window: Window): boolean {
    return (
      KWinWindow.isContain(list, String(window.resourceClass || "")) ||
      KWinWindow.isContain(list, String(window.resourceName || ""))
    );
  }

  /**
   * LowPan Tiling: janela principal de um app da lista — abre com o último tamanho usado (memória flutuante).
   * Diálogos e janelas de apoio do mesmo app ficam de fora (dividem a classe com a principal).
   */
  public get lpRememberFloat(): boolean {
    const w = this.window;
    return (
      this.lpFloatApp &&
      !w.modal &&
      !w.transient &&
      w.resizeable &&
      !w.dialog &&
      !w.splash &&
      !w.utility &&
      !w.skipPager
    );
  }

  public get shouldFloat(): boolean {
    return (
      this.lpFloatApp ||
      this.isFloatByTitle ||
      lpInirRule(this.window) !== null ||
      (CONFIG.floatSkipPager && this.window.skipPager) ||
      this.window.modal ||
      this.window.transient ||
      !this.window.resizeable ||
      (KWINCONFIG.floatUtility &&
        (this.window.dialog || this.window.splash || this.window.utility))
    );
  }

  public maximized: boolean;
  public get minimized(): boolean {
    return this.window.minimized;
  }

  public get surface(): ISurface {
    let activity;
    let desktop;
    if (this.window.activities.length === 0)
      activity = this.workspace.currentActivity;
    else if (
      this.window.activities.indexOf(this.workspace.currentActivity) >= 0
    )
      activity = this.workspace.currentActivity;
    else activity = this.window.activities[0];

    if (this.window.desktops.length === 1) {
      desktop = this.window.desktops[0];
    } else if (this.window.desktops.length === 0) {
      desktop = this.workspace.currentDesktop;
    } else {
      if (this.window.desktops.indexOf(this.workspace.currentDesktop) >= 0)
        desktop = this.workspace.currentDesktop;
      else desktop = this.window.desktops[0];
    }

    // const desktop = this.window.desktops[0];

    return new KWinSurface(
      this.window.output,
      activity,
      desktop,
      this.workspace
    );
  }

  public set surface(srf: ISurface) {
    const ksrf = srf as KWinSurface;

    // TODO: setting activity?
    // TODO: setting screen = move to the screen
    if (this.window.desktops[0] !== ksrf.desktop)
      this.window.desktops = [ksrf.desktop];
    if (this.window.activities[0] !== ksrf.activity)
      this.window.activities = [ksrf.activity];
  }

  public get minSize(): ISize {
    return {
      width: this.window.minSize.width,
      height: this.window.minSize.height,
    };
  }
  public get maxSize(): ISize {
    return {
      width: this.window.maxSize.width,
      height: this.window.maxSize.height,
    };
  }

  private noBorderManaged: boolean;
  private noBorderOriginal: boolean;

  constructor(window: Window, workspace: Workspace) {
    this.workspace = workspace;
    this.window = window;
    this.id = KWinWindow.generateID(window);
    this.maximized = false;
    this.noBorderManaged = false;
    this.noBorderOriginal = window.noBorder;
    this.isIgnoredByConfig =
      KWinWindow.isContain(KWINCONFIG.ignoreClass, window.resourceClass) ||
      KWinWindow.isContain(KWINCONFIG.ignoreClass, window.resourceName) ||
      matchWords(this.window.caption, KWINCONFIG.ignoreTitle) >= 0 ||
      KWinWindow.isContain(KWINCONFIG.ignoreRole, window.windowRole) ||
      (KWINCONFIG.tileNothing &&
        KWinWindow.isContain(KWINCONFIG.tilingClass, window.resourceClass)) ||
      // LowPan Tiling (2026-11-13): apps do Waydroid em modo multi-janela (app_id "waydroid.<pacote>") — o Android
      // decide o tamanho da própria janela e recria a superfície quando o motor redimensiona/move, o que virava um
      // ciclo (janela pulando, conteúdo cortado). O motor não toca nelas: ficam com o KWin, como no Plasma.
      // Também a janela "Waydroid" que a sessão abre ao iniciar: em meia coluna, o Waydroid adotava o tamanho dela
      // como tela do Android (1692×1300) e as janelas dos apps cortavam ao arrastar.
      /^waydroid(\.|$)/.test(String(window.resourceClass || "").toLowerCase());
    // LowPan Tiling: a lista de classes (floatingClass) é consultada ao vivo em lpFloatApp
    this.isFloatByTitle = matchWords(this.window.caption, KWINCONFIG.floatingTitle) >= 0;
  }

  public commit(
    geometry?: Rect,
    noBorder?: boolean,
    windowLayer?: WindowLayer,
    force?: boolean
  ) {
    // LowPan Tiling: desligado pelo liga/desliga, o motor não mexe em janela nenhuma — ponto único por onde passam
    // a disposição, o enforceSize ("geometria por fora"), arrastar e redimensionar. Sem isto, desligado ele brigava
    // com o Krohnkite religado (tela tremendo). Só a devolução das bordas ao desligar passa (force).
    if (!force && !lpActive()) return;
    LOG?.send(
      LogModules.window,
      "KwinWindow#commit",
      `geometry:${geometry}, noBorder:${noBorder}, windowLayer:${windowLayer}`
    );
    if (this.window.move || this.window.resize) return;

    if (noBorder !== undefined) {
      if (!this.noBorderManaged && noBorder)
        /* Backup border state when transitioning from unmanaged to managed */
        this.noBorderOriginal = this.window.noBorder;
      else if (this.noBorderManaged && !this.window.noBorder)
        /* If border is enabled while in managed mode, remember it.
         * Note that there's no way to know if border is re-disabled in managed mode. */
        this.noBorderOriginal = false;

      if (noBorder)
        /* (Re)entering managed mode: remove border. */
        this.window.noBorder = true;
      else if (this.noBorderManaged)
        /* Exiting managed mode: restore original value. */
        this.window.noBorder = this.noBorderOriginal;

      /* update mode */
      this.noBorderManaged = noBorder;
    }

    if (windowLayer !== undefined) {
      if (windowLayer === WindowLayer.Above) this.window.keepAbove = true;
      else if (windowLayer === WindowLayer.Below) this.window.keepBelow = true;
      else if (windowLayer === WindowLayer.Normal) {
        this.window.keepAbove = false;
        this.window.keepBelow = false;
      }
    }

    if (geometry !== undefined) {
      geometry = this.adjustGeometry(geometry);
      if (KWINCONFIG.preventProtrusion) {
        const area = toRect(
          this.workspace.clientArea(
            ClientAreaOption.PlacementArea,
            this.window.output,
            this.workspace.currentDesktop
          )
        );
        if (!area.includes(geometry)) {
          /* assume windows will extrude only through right and bottom edges */
          const x = geometry.x + Math.min(area.maxX - geometry.maxX, 0);
          const y = geometry.y + Math.min(area.maxY - geometry.maxY, 0);
          geometry = new Rect(x, y, geometry.width, geometry.height);
          geometry = this.adjustGeometry(geometry);
        }
      }
      if (this.window.deleted) return;
      this.window.frameGeometry = toQRect(geometry);
    }
  }

  public toString(): string {
    /* using a shorthand name to keep debug message tidy */
    return (
      "KWin(" +
      this.window.internalId.toString() +
      "." +
      this.window.resourceClass +
      ")"
    );
  }

  public visible(srf: ISurface): boolean {
    const ksrf = srf as KWinSurface;
    return (
      !this.window.deleted &&
      !this.window.minimized &&
      (this.window.onAllDesktops ||
        this.window.desktops.indexOf(ksrf.desktop) !== -1) &&
      (this.window.activities.length === 0 /* on all activities */ ||
        this.window.activities.indexOf(ksrf.activity) !== -1) &&
      this.window.output === ksrf.output
    );
  }

  //#region Private Methods
  public static isContain(filterList: string[], s: string): boolean {
    for (let filterWord of filterList) {
      if (filterWord[0] === "[" && filterWord[filterWord.length - 1] === "]") {
        if (
          s
            .toLowerCase()
            .includes(filterWord.toLowerCase().slice(1, filterWord.length - 1))
        )
          return true;
      } else if (s.toLowerCase() === filterWord.toLowerCase()) return true;
    }
    return false;
  }
  /** apply various resize hints to the given geometry */
  private adjustGeometry(geometry: Rect): Rect {
    let width = geometry.width;
    let height = geometry.height;

    /* do not resize fixed-size windows */
    if (!this.window.resizeable) {
      width = this.window.width;
      height = this.window.height;
    } else {
      /* respect resize increment */
      // if (
      //   !(
      //     this.window.basicUnit.width === 1 &&
      //     this.window.basicUnit.height === 1
      //   )
      // )
      //   /* NOT free-size */
      //   [width, height] = this.applyResizeIncrement(geometry);

      /* respect min/max size limit */
      width = clip(width, this.window.minSize.width, this.window.maxSize.width);
      height = clip(
        height,
        this.window.minSize.height,
        this.window.maxSize.height
      );
    }

    return new Rect(geometry.x, geometry.y, width, height);
  }

  // private applyResizeIncrement(geom: Rect): [number, number] {
  //   const unit = this.window.basicUnit;
  //   const base = this.window.minSize;
  //
  //   const padWidth = this.window.geometry.width - this.window.clientSize.width;
  //   const padHeight =
  //     this.window.geometry.height - this.window.clientSize.height;
  //
  //   const quotWidth = Math.floor(
  //     (geom.width - base.width - padWidth) / unit.width
  //   );
  //   const quotHeight = Math.floor(
  //     (geom.height - base.height - padHeight) / unit.height
  //   );
  //
  //   const newWidth = base.width + unit.width * quotWidth + padWidth;
  //   const newHeight = base.height + unit.height * quotHeight + padHeight;
  //
  //   // debugObj(() => ["applyResizeIncrement", {
  //   //     // tslint:disable-next-line:object-literal-sort-keys
  //   //     unit, base, geom,
  //   //     pad: [padWidth, padHeight].join("x"),
  //   //     size: [newWidth, newHeight].join("x"),
  //   // }]);
  //
  //   return [newWidth, newHeight];
  // }

  //#endregion
}
