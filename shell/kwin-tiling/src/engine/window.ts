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

enum WindowState {
  /* initial value */
  Unmanaged,

  /* script-external state - overrides internal state */
  NativeFullscreen,
  NativeMaximized,

  /* script-internal state */
  Floating,
  Maximized,
  Tiled,
  TiledAfloat,
  Undecided,
  Dragging,
  Docked,
}

class WindowClass {
  public static isTileableState(state: WindowState): boolean {
    return (
      state === WindowState.Dragging ||
      state === WindowState.Tiled ||
      state === WindowState.Maximized ||
      state === WindowState.TiledAfloat
    );
  }

  public static isTiledState(state: WindowState): boolean {
    return state === WindowState.Tiled || state === WindowState.Maximized;
  }

  public static isFloatingState(state: WindowState): boolean {
    return state === WindowState.Floating || state === WindowState.TiledAfloat;
  }

  public readonly id: string;
  public readonly window: IDriverWindow;

  public get actualGeometry(): Readonly<Rect> {
    return this.window.geometry;
  }
  public get shouldFloat(): boolean {
    return this.window.shouldFloat;
  }
  /** LowPan Tiling: o tamanho flutuante deste app é lembrado (fora da lista, ou janela principal de um app da lista) */
  public get lpRememberFloat(): boolean {
    return !this.window.shouldFloat || this.window.lpRememberFloat;
  }
  public get shouldIgnore(): boolean {
    return this.window.shouldIgnore;
  }

  /** If this window ***can be*** tiled by layout. */
  public get tileable(): boolean {
    return WindowClass.isTileableState(this.state);
  }
  /** If this window is ***already*** tiled, thus a part of the current layout. */
  public get tiled(): boolean {
    return WindowClass.isTiledState(this.state);
  }
  /** If this window is floating, thus its geometry is not tightly managed. */
  public get floating(): boolean {
    return WindowClass.isFloatingState(this.state);
  }

  public get geometryDelta(): RectDelta | null {
    if (this.geometry === this.actualGeometry) return null;

    return RectDelta.fromRects(this.geometry, this.actualGeometry);
  }
  public floatGeometry: Rect;
  public geometry: Rect;
  public timestamp: number;

  /**
   * The current state of the window.
   *
   * This value affects what and how properties gets commited to the backend.
   *
   * Avoid comparing this value directly, and use `tileable`, `tiled`,
   * `floating` as much as possible.
   */
  public get state(): WindowState {
    /* external states override the internal state. */
    if (this.window.fullScreen) return WindowState.NativeFullscreen;
    if (this.window.maximized) return WindowState.NativeMaximized;

    return this.internalState;
  }

  public set state(value: WindowState) {
    const state = this.state;
    if (state !== value) lpDebug(
      "estado " + lpWin(this) + " -> " + value +
        (state === WindowState.Dragging ? " (ignorado: arrastando)" : "") +
        " | " + String(new Error().stack).split("\n").slice(1, 4).join(" < ")
    );

    /* cannot transit to the current state */
    if (state === value || state === WindowState.Dragging) return;

    if (
      (state === WindowState.Unmanaged || WindowClass.isTileableState(state)) &&
      WindowClass.isFloatingState(value)
    ) {
      this.shouldCommitFloat = true;
      // LowPan Tiling: saiu da faixa (Meta+F, arrastar) → o tamanho que o app tinha flutuando, centralizado
      if (WindowClass.isTileableState(state) && !this.shouldFloat) {
        const remembered = FloatMemory.restore(this);
        if (remembered) this.floatGeometry = remembered;
      }
    } else if (
      WindowClass.isFloatingState(state) &&
      WindowClass.isTileableState(value)
    ) {
      /* save the current geometry before leaving floating state */
      this.floatGeometry = this.actualGeometry;
      if (this.lpRememberFloat) FloatMemory.remember(this, this.actualGeometry); // LowPan Tiling
    }

    // LowPan Tiling: app da lista "sempre flutuar" → abre (ou sai da faixa) com o último tamanho usado, centralizado
    if (
      WindowClass.isFloatingState(value) &&
      !WindowClass.isFloatingState(state) &&
      this.window.lpRememberFloat
    ) {
      const remembered = FloatMemory.restore(this);
      if (remembered) {
        this.floatGeometry = remembered;
        this.shouldCommitFloat = true;
      }
    }

    // LowPan Tiling: saiu da faixa e o tamanho flutuante é praticamente o da coluna (janela que abriu já na faixa,
    // sem tamanho lembrado) → parecia que o Meta+F não tinha feito nada (2026-11-21). Encolhe para 85 %, centralizada
    // no mesmo ponto, respeitando o tamanho mínimo do app.
    if (
      WindowClass.isTileableState(state) &&
      WindowClass.isFloatingState(value) &&
      WindowClass.lpQuaseIgual(this.floatGeometry, this.actualGeometry)
    ) {
      const g = this.actualGeometry;
      const w = Math.max(Math.round(g.width * 0.85), this._minSize?.width ?? 0);
      const h = Math.max(Math.round(g.height * 0.85), this._minSize?.height ?? 0);
      if (w < g.width || h < g.height) {
        const [cx, cy] = g.center;
        this.floatGeometry = new Rect(cx - Math.floor(w / 2), cy - Math.floor(h / 2), w, h);
        this.shouldCommitFloat = true;
      }
    }

    this.internalState = value;
  }
  /** LowPan Tiling: dois retângulos a menos de 24 px um do outro em cada borda */
  private static lpQuaseIgual(a: Readonly<Rect> | null | undefined, b: Readonly<Rect>): boolean {
    if (!a) return true;
    const d = 24;
    return Math.abs(a.x - b.x) < d && Math.abs(a.y - b.y) < d &&
      Math.abs(a.width - b.width) < d && Math.abs(a.height - b.height) < d;
  }
  public setDraggingState() {
    this.internalState = WindowState.Dragging;
  }
  public setState(value: WindowState) {
    this.internalState = value;
  }

  public get surface(): ISurface {
    return this.window.surface;
  }

  public set surface(srf: ISurface) {
    this.window.surface = srf;
  }

  public get weight(): number {
    const srfID = this.window.surface.id;
    const weight: number | undefined = this.weightMap[srfID];
    if (weight === undefined) {
      this.weightMap[srfID] = 1.0;
      return 1.0;
    }
    return weight;
  }

  public set weight(value: number) {
    const srfID = this.window.surface.id;
    this.weightMap[srfID] = value;
  }

  public get windowClassName(): string {
    return this.window.windowClassName;
  }

  public dock: Dock | null;

  private internalState: WindowState;
  private shouldCommitFloat: boolean;
  private weightMap: { [key: string]: number };
  private _minSize: ISize;
  private _maxSize: ISize;

  constructor(window: IDriverWindow) {
    this.id = window.id;
    this.window = window;

    this.floatGeometry = window.geometry;
    this.geometry = window.geometry;
    this.timestamp = 0;

    this.internalState = WindowState.Unmanaged;
    this.shouldCommitFloat = this.shouldFloat;
    this.weightMap = {};
    this.dock = null;

    this._minSize = window.minSize;
    this._maxSize = window.maxSize;
  }

  public get minSize() {
    return this._minSize;
  }
  public get maxSize() {
    return this._maxSize;
  }

  public commit(noBorders?: boolean) {
    const state = this.state;
    LOG?.send(LogModules.window, "commit", `state: ${WindowState[state]}`);
    switch (state) {
      case WindowState.Dragging:
        break;
      case WindowState.NativeMaximized:
        this.window.commit(undefined, undefined, undefined);
        break;

      case WindowState.NativeFullscreen:
        this.window.commit(undefined, undefined, WindowLayer.Normal);
        break;

      case WindowState.Floating:
        if (!this.shouldCommitFloat) break;
        this.window.commit(
          this.floatGeometry,
          false,
          CONFIG.floatedWindowsLayer
        );
        this.shouldCommitFloat = false;
        break;

      case WindowState.Maximized:
        this.window.commit(this.geometry, true, WindowLayer.Normal);
        break;

      case WindowState.Tiled:
        this.window.commit(
          this.geometry,
          CONFIG.noTileBorder || Boolean(noBorders),
          CONFIG.tiledWindowsLayer
        );
        break;

      case WindowState.TiledAfloat:
        if (!this.shouldCommitFloat) break;
        this.window.commit(
          this.floatGeometry,
          false,
          CONFIG.floatedWindowsLayer
        );
        this.shouldCommitFloat = false;
        break;
      case WindowState.Floating:
        this.window.commit(
          this.geometry,
          CONFIG.noTileBorder || Boolean(noBorders),
          CONFIG.floatedWindowsLayer
        );
        break;
      case WindowState.Docked:
        this.window.commit(
          this.geometry,
          CONFIG.noTileBorder,
          CONFIG.tiledWindowsLayer
        );
        break;
    }
  }

  /**
   * Force apply the geometry *immediately*.
   *
   * This method is a quick hack created for engine#resizeFloat, thus should
   * not be used in other places.
   */
  public forceSetGeometry(geometry: Rect) {
    this.window.commit(geometry);
  }

  public visible(srf: ISurface): boolean {
    return this.window.visible(srf);
  }
  public get minimized(): boolean {
    return this.window.minimized;
  }

  public toString(): string {
    return "Window(" + String(this.window) + ")";
  }
}
