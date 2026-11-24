// Copyright (c) 2018-2019 Eon S. Jeon <esjeon@hyunmu.am>
// Copyright (c) 2024 Vjatcheslav V. Kolchkov <akl334@protonmail.ch>
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
 * Abstracts KDE implementation specific details.
 *
 * Driver is responsible for initializing the tiling logic, connecting
 * signals(Qt/KDE term for binding events), and providing specific utility
 * functions.
 */
var KWIN: KWin;

class KWinDriver implements IDriverContext {
  public static backendName: string = "kwin";

  // TODO: split context implementation
  //#region implement properties of IDriverContext (except `setTimeout`)
  public get backend(): string {
    return KWinDriver.backendName;
  }

  public get currentSurface(): ISurface {
    return new KWinSurface(
      this.workspace.activeWindow
        ? this.workspace.activeWindow.output
        : this.workspace.activeScreen,
      this.workspace.currentActivity,
      this.workspace.currentDesktop,
      this.workspace
    );
  }

  public set currentSurface(value: ISurface) {
    const ksrf = value as KWinSurface;

    /* NOTE: only supports switching desktops */
    // TODO: fousing window on other screen?
    // TODO: find a way to change activity

    if (this.workspace.currentDesktop.id !== ksrf.desktop.id)
      this.workspace.currentDesktop = ksrf.desktop;
    if (this.workspace.currentActivity !== ksrf.activity)
      this.workspace.currentActivity = ksrf.activity;
  }

  public get currentWindow(): WindowClass | null {
    const client = this.workspace.activeWindow;
    return client ? this.windowMap.get(client) : null;
  }

  public set currentWindow(window: WindowClass | null) {
    if (window !== null) {
      window.timestamp = new Date().getTime();
      this.workspace.activeWindow = (window.window as KWinWindow).window;
    }
  }

  public get screens(): ISurface[] {
    const screens: ISurface[] = [];
    this.workspace.screens.forEach((screen) => {
      screens.push(
        new KWinSurface(
          screen,
          this.workspace.currentActivity,
          this.workspace.currentDesktop,
          this.workspace
        )
      );
    });
    return screens;
  }

  public get cursorPosition(): [number, number] | null {
    const workspacePos = this.workspace.cursorPos;
    return workspacePos !== null ? [workspacePos.x, workspacePos.y] : null;
  }

  //#endregion

  public workspace: Workspace;
  private shortcuts: IShortcuts;
  private engine: TilingEngine;
  private control: TilingController;
  private windowMap: WrapperMap<Window, WindowClass>;
  private entered: boolean;

  constructor(api: Api) {
    KWIN = api.kwin;
    LOWPAN_ROOT = api.root ?? null;
    this.workspace = api.workspace;
    LOWPAN_WS = api.workspace;
    this.shortcuts = api.shortcuts;
    this.engine = new TilingEngine();
    this.control = new TilingController(this.engine);
    this.windowMap = new WrapperMap(
      (client: Window) => KWinWindow.generateID(client),
      (client: Window) =>
        new WindowClass(new KWinWindow(client, this.workspace))
    );
    this.entered = false;
  }

  /*
   * Main
   */

  public main() {
    CONFIG = KWINCONFIG = new KWinConfig();
    LOG?.send(LogModules.printConfig, undefined, `Config: ${CONFIG}`);

    this.bindEvents();
    this.bindShortcut();
    FloatMemory.load(); // LowPan Tiling: tamanho flutuante lembrado por app (helper da ponte do shell)

    const clients: Window[] = this.workspace.stackingOrder;
    for (let i = 0; i < clients.length; i++) {
      this.addWindow(clients[i]);
    }
    this.lpWasActive = lpActive();
    if (!this.lpWasActive) NiriTabPublisher.clearAll();
    this.lpWatchActive();
  }

  /** a última janela ativa que não é notificação do Steam (regra do iNiR: a notificação não rouba o foco) */
  private lpLastActive: any = null;

  /**
   * LowPan Tiling: espaços entre janelas e até as bordas relidos a cada segundo (kwinrc [Script-lowpan-tiling]
   * screenGap*), para ajustar sem novo login (pedido do usuário, 2026-11-07). Mudou → refaz o cache e redispõe.
   */
  private lpWatchGaps() {
    const keys = ["screenGapLeft", "screenGapRight", "screenGapTop", "screenGapBottom", "screenGapBetween"];
    let changed = false;
    for (const k of keys) {
      let v: number;
      try {
        v = Number(KWIN.readConfig(k, 25));
      } catch (e) {
        continue;
      }
      if (!isFinite(v) || v < 0) continue;
      if ((CONFIG as any)[k] !== v) {
        (CONFIG as any)[k] = v;
        changed = true;
      }
    }
    if (!changed) return;
    (DefaultGapsCfg as any)._gapsInstance = undefined;
    (this.engine as any)._defaultGaps = null;
    lpDebug("espaços: " + keys.map((k) => (CONFIG as any)[k]).join("/"));
    if (lpActive()) this.enter(() => this.engine.arrange(this));
  }

  /**
   * LowPan Tiling: área livre de cada tela (sem a ilha, a dock e os painéis) conferida a cada segundo. O KWin não avisa
   * os scripts quando ela muda: no 1º login do iRiS (VM, 2026-11-22) a janela restaurada pela sessão foi disposta antes
   * de o shell reservar o espaço e ficou atrás da ilha e da dock até ser movida. Mudou → redispõe.
   */
  private lpAreaKey: string | null = null;
  private lpWatchArea() {
    let key = "";
    try {
      key = this.workspace.screens
        .map((s: any) => {
          const a = this.workspace.clientArea(ClientAreaOption.PlacementArea, s, this.workspace.currentDesktop);
          return s.name + ":" + a.x + "," + a.y + "," + a.width + "," + a.height;
        })
        .join("|");
    } catch (e) {
      return;
    }
    if (this.lpAreaKey === null || key === this.lpAreaKey) {
      this.lpAreaKey = key;
      return;
    }
    this.lpAreaKey = key;
    lpDebug("área livre: " + key);
    if (lpActive()) this.enter(() => this.engine.arrange(this));
  }

  /** LowPan Tiling: confere o interruptor a cada segundo (o configChanged do KWin não chega aos scripts) */
  private lpWasActive = true;
  private lpWatchActive() {
    KWinSetTimeout(() => {
      const now = lpActive();
      if (now !== this.lpWasActive) {
        this.lpWasActive = now;
        lpDebug("interruptor: " + (now ? "ligado" : "desligado"));
        this.enter(() => {
          if (now) this.engine.arrange(this);
          else this.lpReleaseAll();
        });
      }
      this.lpWatchProfile();
      this.lpWatchGaps();
      this.lpWatchFloatApps();
      this.lpWatchArea();
      this.lpWatchActive();
    }, 1000);
  }

  /**
   * LowPan Tiling: perfil de ajustes por ambiente (2026-11-22). No Plasma de quem usava o Krohnkite, o motor roda com
   * os ajustes e os atalhos dele (o Krohnkite não para ao ser desligado na sessão: não pode carregar); no iRiS, com os
   * do iRiS. O system/lowpan-shells-tiling regrava o grupo [Script-lowpan-tiling] e soma 1 em lowpanProfileGen; aqui
   * a mudança refaz a configuração, os layouts (o LayoutStore lê CONFIG.layoutOrder ao criar cada superfície) e os
   * espaços, e redispõe. Bordas: o commit devolve a borda original quando o noTileBorder novo é false.
   */
  private lpProfileGen: number | null = null;
  private lpWatchProfile() {
    let gen: number;
    try {
      gen = Number(KWIN.readConfig("lowpanProfileGen", 0));
    } catch (e) {
      return;
    }
    if (this.lpProfileGen === null || gen === this.lpProfileGen) {
      this.lpProfileGen = gen;
      return;
    }
    this.lpProfileGen = gen;
    CONFIG = KWINCONFIG = new KWinConfig();
    (DefaultGapsCfg as any)._gapsInstance = undefined;
    (this.engine as any)._defaultGaps = null;
    this.engine.layouts = new LayoutStore();
    this.lpFloatAppsRaw = null;
    NiriTabPublisher.clearAll();
    lpDebug("perfil " + gen + ": layouts " + CONFIG.layoutOrder.join(","));
    if (lpActive()) this.enter(() => this.engine.arrange(this));
  }

  /**
   * LowPan Tiling: lista "sempre flutuar" (kwinrc [Script-lowpan-tiling] floatingClass) relida a cada segundo, para
   * as Configurações do shell valerem sem novo login (2026-11-12). Entrou na lista → as janelas abertas do app saem
   * da faixa com o último tamanho usado; saiu → as que flutuavam por causa dela voltam para a faixa.
   */
  private lpFloatAppsRaw: string | null = null;
  private lpWatchFloatApps() {
    let raw: string;
    try {
      raw = String(KWIN.readConfig("floatingClass", ""));
    } catch (e) {
      return;
    }
    if (this.lpFloatAppsRaw === null) this.lpFloatAppsRaw = KWINCONFIG.floatingClass.join(",");
    if (raw === this.lpFloatAppsRaw) return;
    this.lpFloatAppsRaw = raw;
    const before = KWINCONFIG.floatingClass;
    KWINCONFIG.floatingClass = raw
      .split(",")
      .map((part) => part.trim())
      .filter((part) => part != "");
    lpDebug("sempre flutuar: " + KWINCONFIG.floatingClass.join(", "));
    if (!lpActive()) return;
    this.enter(() => {
      for (const window of this.windowMap.values()) {
        const kw = window.window as KWinWindow;
        const client: any = kw.window;
        if (!client || client.deleted || window.shouldIgnore) continue;
        if (window.state === WindowState.Unmanaged || window.state === WindowState.Docked) continue;
        const was = KWinWindow.lpInList(before, client);
        if (kw.lpFloatApp && !was && window.tileable) window.state = WindowState.Floating;
        else if (was && !kw.lpFloatApp && window.floating && !window.shouldFloat) window.state = WindowState.Tiled;
      }
      this.engine.arrange(this);
    });
  }

  /** desligado: devolve as bordas, traz para a tela as colunas que estavam fora dela e some com as barras de abas */
  private lpReleaseAll() {
    NiriTabPublisher.clearAll();
    for (const window of this.windowMap.values()) {
      const kw = window.window as KWinWindow;
      const client: any = kw.window;
      if (!client || client.deleted) continue;
      try {
        kw.commit(undefined, false, undefined, true);
        if (client.fullScreen || client.minimized) continue;
        const a = this.workspace.clientArea(ClientAreaOption.MaximizeArea, client.output, this.workspace.currentDesktop);
        const g = client.frameGeometry;
        const w = Math.min(g.width, a.width);
        const h = Math.min(g.height, a.height);
        const x = Math.max(a.x, Math.min(g.x, a.x + a.width - w));
        const y = Math.max(a.y, Math.min(g.y, a.y + a.height - h));
        if (x !== g.x || y !== g.y || w !== g.width || h !== g.height)
          client.frameGeometry = toQRect(new Rect(x, y, w, h));
      } catch (e) {
        /* janela sumindo */
      }
    }
  }

  private addWindow(client: Window): WindowClass | null {
    if (
      !client.deleted &&
      client.pid >= 0 &&
      !client.popupWindow &&
      client.normalWindow &&
      !client.hidden &&
      client.width * client.height > 10 &&
      String(client.caption) !== "LowPan Tiling — prévia" &&
      String(client.resourceClass) !== "xembedsniproxy" // regra do iNiR: o proxy da bandeja X11 é invisível
    ) {
      const window = this.windowMap.add(client);
      this.control.onWindowAdded(this, window);
      if (window.state !== WindowState.Unmanaged) {
        this.bindWindowEvents(window, client);
        if (client.maximizeMode > 0) client.setMaximize(false, false);
        LOG?.send(LogModules.newWindowAdded, "", debugWin(client), {
          winClass: [`${client.resourceClass}`],
        });
        return window;
      } else {
        this.windowMap.remove(client);
        LOG?.send(LogModules.newWindowUnmanaged, "", debugWin(client), {
          winClass: [`${client.resourceClass}`],
        });
      }
    } else {
      LOG?.send(LogModules.newWindowFiltered, "", debugWin(client), {
        winClass: [`${client.resourceClass}`],
      });
    }
    return null;
  }

  //#region implement methods of IDriverContext`
  public setTimeout(func: () => void, timeout: number) {
    KWinSetTimeout(() => this.enter(func), timeout);
  }

  public showNotification(text: string) {
    if (CONFIG.notificationDuration > 0)
      popupDialog.show(text, CONFIG.notificationDuration);
  }
  //#endregion

  private bindShortcut() {
    const callbackShortcut = (shortcut: Shortcut) => {
      return () => {
        LOG?.send(
          LogModules.shortcut,
          `Shortcut pressed:`,
          `${ShortcutsKeys[shortcut]}`
        );
        if (!lpActive()) return; // LowPan Tiling: desligado
        this.enter(() => this.control.onShortcut(this, shortcut));
      };
    };
    this.shortcuts
      .getToggleDock()
      .activated.connect(callbackShortcut(Shortcut.ToggleDock));
    // LowPan Tiling: ações do Niri
    this.shortcuts.getNiriConsumeLeft().activated.connect(callbackShortcut(Shortcut.NiriConsumeLeft));
    this.shortcuts.getNiriConsumeRight().activated.connect(callbackShortcut(Shortcut.NiriConsumeRight));
    this.shortcuts.getNiriCycleWidth().activated.connect(callbackShortcut(Shortcut.NiriCycleWidth));
    this.shortcuts.getNiriMaximizeColumn().activated.connect(callbackShortcut(Shortcut.NiriMaximizeColumn));
    this.shortcuts.getNiriCenterColumn().activated.connect(callbackShortcut(Shortcut.NiriCenterColumn));
    this.shortcuts.getNiriToggleTabbed().activated.connect(callbackShortcut(Shortcut.NiriToggleTabbed));
    this.shortcuts.getNiriResetHeight().activated.connect(callbackShortcut(Shortcut.NiriResetHeight));
    this.shortcuts.getNiriFocusFirst().activated.connect(callbackShortcut(Shortcut.NiriFocusFirst));
    this.shortcuts.getNiriFocusLast().activated.connect(callbackShortcut(Shortcut.NiriFocusLast));
    this.shortcuts.getNiriMoveToFirst().activated.connect(callbackShortcut(Shortcut.NiriMoveToFirst));
    this.shortcuts.getNiriMoveToLast().activated.connect(callbackShortcut(Shortcut.NiriMoveToLast));
    this.shortcuts.getNiriFocusFloating().activated.connect(callbackShortcut(Shortcut.NiriFocusFloating));
    this.shortcuts.getNiriExpandColumn().activated.connect(callbackShortcut(Shortcut.NiriExpandColumn));
    this.shortcuts.getNiriPresetOff().activated.connect(callbackShortcut(Shortcut.NiriPresetOff));
    this.shortcuts.getNiriPresetMasterLeft().activated.connect(callbackShortcut(Shortcut.NiriPresetMasterLeft));
    this.shortcuts.getNiriPresetMasterRight().activated.connect(callbackShortcut(Shortcut.NiriPresetMasterRight));
    this.shortcuts.getNiriPresetColumns().activated.connect(callbackShortcut(Shortcut.NiriPresetColumns));
    this.shortcuts.getNiriPresetMonocle().activated.connect(callbackShortcut(Shortcut.NiriPresetMonocle));
    this.shortcuts.getNiriPresetCycle().activated.connect(callbackShortcut(Shortcut.NiriPresetCycle));
    this.shortcuts.getNiriPresetPromote().activated.connect(callbackShortcut(Shortcut.NiriPresetPromote));
    this.shortcuts.getNiriFocusMonitorLeft().activated.connect(callbackShortcut(Shortcut.NiriFocusMonitorLeft));
    this.shortcuts.getNiriFocusMonitorRight().activated.connect(callbackShortcut(Shortcut.NiriFocusMonitorRight));
    this.shortcuts.getNiriMoveColumnToMonitorLeft().activated.connect(callbackShortcut(Shortcut.NiriMoveColumnToMonitorLeft));
    this.shortcuts.getNiriMoveColumnToMonitorRight().activated.connect(callbackShortcut(Shortcut.NiriMoveColumnToMonitorRight));
    this.shortcuts
      .getFocusNext()
      .activated.connect(callbackShortcut(Shortcut.FocusNext));
    this.shortcuts
      .getFocusPrev()
      .activated.connect(callbackShortcut(Shortcut.FocusPrev));
    this.shortcuts
      .getFocusDown()
      .activated.connect(callbackShortcut(Shortcut.FocusDown));
    this.shortcuts
      .getFocusUp()
      .activated.connect(callbackShortcut(Shortcut.FocusUp));
    this.shortcuts
      .getFocusLeft()
      .activated.connect(callbackShortcut(Shortcut.FocusLeft));
    this.shortcuts
      .getFocusRight()
      .activated.connect(callbackShortcut(Shortcut.FocusRight));

    this.shortcuts
      .getShiftDown()
      .activated.connect(callbackShortcut(Shortcut.ShiftDown));
    this.shortcuts
      .getShiftUp()
      .activated.connect(callbackShortcut(Shortcut.ShiftUp));
    this.shortcuts
      .getShiftLeft()
      .activated.connect(callbackShortcut(Shortcut.ShiftLeft));
    this.shortcuts
      .getShiftRight()
      .activated.connect(callbackShortcut(Shortcut.ShiftRight));

    this.shortcuts
      .getGrowHeight()
      .activated.connect(callbackShortcut(Shortcut.GrowHeight));
    this.shortcuts
      .getShrinkHeight()
      .activated.connect(callbackShortcut(Shortcut.ShrinkHeight));
    this.shortcuts
      .getShrinkWidth()
      .activated.connect(callbackShortcut(Shortcut.ShrinkWidth));
    this.shortcuts
      .getGrowWidth()
      .activated.connect(callbackShortcut(Shortcut.GrowWidth));

    this.shortcuts
      .getIncrease()
      .activated.connect(callbackShortcut(Shortcut.Increase));
    this.shortcuts
      .getDecrease()
      .activated.connect(callbackShortcut(Shortcut.Decrease));

    this.shortcuts
      .getToggleFloat()
      .activated.connect(callbackShortcut(Shortcut.ToggleFloat));
    this.shortcuts
      .getFloatAll()
      .activated.connect(callbackShortcut(Shortcut.ToggleFloatAll));
    this.shortcuts
      .getNextLayout()
      .activated.connect(callbackShortcut(Shortcut.NextLayout));
    this.shortcuts
      .getPreviousLayout()
      .activated.connect(callbackShortcut(Shortcut.PreviousLayout));

    this.shortcuts
      .getRotate()
      .activated.connect(callbackShortcut(Shortcut.Rotate));
    this.shortcuts
      .getRotatePart()
      .activated.connect(callbackShortcut(Shortcut.RotatePart));

    this.shortcuts
      .getSetMaster()
      .activated.connect(callbackShortcut(Shortcut.SetMaster));

    const callbackShortcutLayout = (layoutClass: ILayoutClass) => {
      return () => {
        LOG?.send(LogModules.shortcut, "shortcut layout", `${layoutClass.id}`);
        if (!lpActive()) return;
        this.enter(() =>
          this.control.onShortcut(this, Shortcut.SetLayout, layoutClass.id)
        );
      };
    };

    this.shortcuts
      .getTileLayout()
      .activated.connect(callbackShortcutLayout(TileLayout));
    this.shortcuts
      .getMonocleLayout()
      .activated.connect(callbackShortcutLayout(MonocleLayout));
    this.shortcuts
      .getThreeColumnLayout()
      .activated.connect(callbackShortcutLayout(ThreeColumnLayout));
    this.shortcuts
      .getSpreadLayout()
      .activated.connect(callbackShortcutLayout(SpreadLayout));
    this.shortcuts
      .getStairLayout()
      .activated.connect(callbackShortcutLayout(StairLayout));
    this.shortcuts
      .getFloatingLayout()
      .activated.connect(callbackShortcutLayout(FloatingLayout));
    this.shortcuts
      .getQuarterLayout()
      .activated.connect(callbackShortcutLayout(QuarterLayout));
    this.shortcuts
      .getStackedLayout()
      .activated.connect(callbackShortcutLayout(StackedLayout));
    this.shortcuts
      .getColumnsLayout()
      .activated.connect(callbackShortcutLayout(ColumnsLayout));
    this.shortcuts
      .getSpiralLayout()
      .activated.connect(callbackShortcutLayout(SpiralLayout));
    this.shortcuts
      .getBTreeLayout()
      .activated.connect(callbackShortcutLayout(BTreeLayout));
  }

  //#region Helper functions
  /**
   * Binds callback to the signal w/ extra fail-safe measures, like re-entry
   * prevention and auto-disconnect on termination.
   */
  private connect(
    signal: Signal<(...args: any[]) => void>,
    handler: (..._: any[]) => void
  ): () => void {
    const wrapper = (...args: any[]) => {
      /* HACK: `workspace` become undefined when the script is disabled. */
      if (typeof this.workspace === "undefined") signal.disconnect(wrapper);
      else this.enter(() => handler.apply(this, args));
    };
    signal.connect(wrapper);

    return wrapper;
  }

  /**
   * Run the given function in a protected(?) context to prevent nested event
   * handling.
   *
   * KWin emits signals as soons as window states are changed, even when
   * those states are modified by the script. This causes multiple re-entry
   * during event handling, resulting in performance degradation and harder
   * debugging.
   */
  private enter(callback: () => void) {
    if (this.entered) return;

    this.entered = true;
    try {
      callback();
    } catch (e: any) {
      warning(`ProtectFunc: Error raised line: ${e.lineNumber}. Error: ${e}`);
    } finally {
      this.entered = false;
    }
  }
  //#endregion
  private bindEvents() {
    this.connect(this.workspace.screensChanged, () => {
      LOG?.send(LogModules.screensChanged, "eventFired");
      this.control.onSurfaceUpdate(this);
    });

    this.connect(this.workspace.virtualScreenGeometryChanged, () => {
      LOG?.send(LogModules.virtualScreenGeometryChanged, "eventFired");
      this.control.onSurfaceUpdate(this);
    });

    this.connect(
      this.workspace.currentActivityChanged,
      (activityId: string) => {
        LOG?.send(
          LogModules.currentActivityChanged,
          "eventFired",
          `Activity ID:${activityId}`
        );
        this.control.onCurrentActivityChanged(this);
      }
    );

    this.connect(
      this.workspace.currentDesktopChanged,
      (virtualDesktop: VirtualDesktop) => {
        LOG?.send(
          LogModules.currentDesktopChanged,
          "eventFired",
          `Virtual Desktop. name:${virtualDesktop.name}, id:${virtualDesktop.id}`
        );
        this.control.onSurfaceUpdate(this);
      }
    );

    this.connect(this.workspace.windowAdded, (client: Window) => {
      if (!client) return;
      LOG?.send(
        LogModules.windowAdded,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId}`,
        { winClass: [`${client.resourceClass}`] }
      );
      // LowPan Tiling: o Yakuake abre centralizado na área útil (era o center-new-windows, que o tiling desliga por
      // mover todas as janelas novas). Ele recria a janela a cada abertura, então vale toda vez que ele desce.
      if (lpActive() && String(client.resourceName || "").toLowerCase() === "yakuake") {
        try {
          const a = this.workspace.clientArea(ClientAreaOption.MaximizeArea, client.output, this.workspace.currentDesktop);
          const g = client.frameGeometry;
          client.frameGeometry = toQRect(new Rect(Math.round(a.x + (a.width - g.width) / 2), Math.round(a.y + (a.height - g.height) / 2), g.width, g.height));
        } catch (e) {
          /* sumiu */
        }
      }
      const window = this.addWindow(client);
      // regra do iNiR: notificação do Steam no canto de baixo à direita (10 px), sem roubar o foco
      if (window !== null && lpInirRule(client) === "toast") {
        const prev = this.lpLastActive;
        this.setTimeout(() => {
          try {
            const a = this.workspace.clientArea(ClientAreaOption.MaximizeArea, client.output, this.workspace.currentDesktop);
            const g = client.frameGeometry;
            client.frameGeometry = toQRect(new Rect(a.x + a.width - g.width - 10, a.y + a.height - g.height - 10, g.width, g.height));
            if (client.active && prev && !prev.deleted) this.workspace.activeWindow = prev;
          } catch (e) {
            /* sumiu */
          }
        }, 0);
        return;
      }
      if (client.active && window !== null)
        this.control.onWindowFocused(this, window);
    });

    this.connect(this.workspace.windowActivated, (client: Window) => {
      if (!client) return;
      if (lpInirRule(client) !== "toast") this.lpLastActive = client; // para a notificação do Steam devolver o foco
      LOG?.send(
        LogModules.windowActivated,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId}`,
        { winClass: [`${client.resourceClass}`] }
      );
      const window = this.windowMap.get(client);
      if (client.active && window !== null)
        this.control.onWindowFocused(this, window);
    });

    this.connect(this.workspace.windowRemoved, (client: Window) => {
      if (!client) return;
      LOG?.send(
        LogModules.windowRemoved,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId}`,
        { winClass: [`${client.resourceClass}`] }
      );
      const window = this.windowMap.get(client);
      if (window) {
        this.control.onWindowRemoved(this, window);
        this.windowMap.remove(client);
      }
    });

    // TODO: options.configChanged.connect(this.onConfigChanged);
    /* NOTE: How disappointing. This doesn't work at all. Even an official kwin script tries this.
     *       https://github.com/KDE/kwin/blob/master/scripts/minimizeall/contents/code/main.js */
  }

  private bindWindowEvents(window: WindowClass, client: Window) {
    let moving = false;
    let resizing = false;
    this.connect(client.activitiesChanged, () => {
      LOG?.send(
        LogModules.activitiesChanged,
        "eventFired",
        `window: caption:${client.caption} internalID:${
          client.internalId
        }, activities: ${client.activities.join(",")}`,
        { winClass: [`${client.resourceClass}`] }
      );
      this.control.onWindowChanged(
        this,
        window,
        "activity=" + client.activities.join(",")
      );
    });

    this.connect(client.bufferGeometryChanged, () => {
      LOG?.send(
        LogModules.bufferGeometryChanged,
        "eventFired",
        `Window: caption:${client.caption} internalId:${client.internalId}, moving:${moving}, resizing:${resizing}, geometry:${window.geometry}`,
        { winClass: [`${client.resourceClass}`] }
      );
      if (moving) this.control.onWindowMove(window);
      else if (resizing) this.control.onWindowResize(this, window);
      else {
        if (!window.actualGeometry.equals(window.geometry))
          this.control.onWindowGeometryChanged(this, window);
      }
    });

    this.connect(client.desktopsChanged, () => {
      LOG?.send(
        LogModules.desktopsChanged,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId}, desktops: ${client.desktops}`,
        { winClass: [`${client.resourceClass}`] }
      );
      this.control.onWindowChanged(this, window, "Window's desktop changed.");
    });

    this.connect(client.fullScreenChanged, () => {
      LOG?.send(
        LogModules.fullScreenChanged,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId}, fullscreen: ${client.fullScreen}`,
        { winClass: [`${client.resourceClass}`] }
      );
      this.control.onWindowChanged(
        this,
        window,
        "fullscreen=" + client.fullScreen
      );
    });

    this.connect(client.interactiveMoveResizeStepped, (geometry) => {
      LOG?.send(
        LogModules.interactiveMoveResizeStepped,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId},interactiveMoveResizeStepped:${geometry}`,
        { winClass: [`${client.resourceClass}`] }
      );
      if (client.resize) return;
      this.control.onWindowDragging(this, window, geometry);
    });

    this.connect(client.maximizedAboutToChange, (mode: MaximizeMode) => {
      LOG?.send(
        LogModules.maximizedAboutToChange,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId},maximizedAboutToChange:${mode}`,
        { winClass: [`${client.resourceClass}`] }
      );
      // const maximized = mode === MaximizeMode.MaximizeFull;
      // LowPan Tiling: no layout Niri, maximizar = coluna na largura toda (Mod+D do Niri)
      const niri = this.control.niriLayoutOf(window);
      lpDebug("maximizar modo=" + mode + " niri=" + (niri !== null) + " " + lpWin(window));
      if (niri !== null && lpActive() && (mode as number) > 0 && window.tiled) {
        niri.toggleFullWidth(window);
        // this.setTimeout já roda dentro de enter(): um enter() aninhado seria descartado e a faixa não se
        // redesenhava (maximizar de novo mudava a largura só na memória; parecia não restaurar)
        this.setTimeout(() => {
          try { client.setMaximize(false, false); } catch (e) { /* KWin antigo */ }
          this.control.onWindowMaximizeChanged(this, window);
        }, 0);
        return;
      }
      (window.window as KWinWindow).maximized =
        (mode as number) > 0 ? true : false;
      this.control.onWindowMaximizeChanged(this, window);
    });

    this.connect(client.minimizedChanged, () => {
      LOG?.send(
        LogModules.minimizedChanged,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId},minimized:${client.minimized}`,
        { winClass: [`${client.resourceClass}`] }
      );
      if (KWINCONFIG.preventMinimize) {
        client.minimized = false;
        this.workspace.activeWindow = client;
      } else {
        var comment = client.minimized ? "minimized" : "unminimized";
        this.control.onWindowChanged(this, window, comment);
      }
    });

    this.connect(client.moveResizedChanged, () => {
      LOG?.send(
        LogModules.moveResizedChanged,
        "eventFired",
        `Window: caption:${client.caption} internalId:${client.internalId}, moving:${moving}, resizing:${resizing}`,
        { winClass: [`${client.resourceClass}`] }
      );
      if (moving !== client.move) {
        moving = client.move;
        if (moving) {
          this.control.onWindowMoveStart(window);
        } else {
          this.control.onWindowMoveOver(this, window);
        }
      }
      if (resizing !== client.resize) {
        resizing = client.resize;
        if (resizing) this.control.onWindowResizeStart(window);
        else this.control.onWindowResizeOver(this, window);
      }
    });

    this.connect(client.outputChanged, () => {
      LOG?.send(
        LogModules.outputChanged,
        "eventFired",
        `window: caption:${client.caption} internalID:${client.internalId} output: ${client.output.name}`,
        { winClass: [`${client.resourceClass}`] }
      );
      this.control.onWindowChanged(
        this,
        window,
        "screen=" + client.output.name
      );
    });
    if (CONFIG.floatSkipPager) {
      this.connect(client.skipPagerChanged, () => {
        this.control.onWindowSkipPagerChanged(this, window, client.skipPager);
      });
    }
  }

  // TODO: private onConfigChanged = () => {
  //     this.loadConfig();
  //     this.engine.arrange();
  // }
  /* NOTE: check `bindEvents` for details */
}
