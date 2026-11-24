// LowPan Tiling — memória do tamanho flutuante por app (Copyright (c) 2026 LowPan Shells, MIT).
//
// Quando uma janela que estava na faixa flutua (Meta+F, arrastar para fora), ela abre com o tamanho que o app
// tinha da última vez que flutuou, centralizada na tela. O tamanho é gravado quando a janela volta para a faixa,
// quando é redimensionada flutuando e quando fecha flutuando. Diálogos e janelas que nascem flutuantes ficam de
// fora (compartilham o app com a janela principal).
//
// Um script KWin não grava arquivos: quem guarda é o helper da ponte do shell (org.lowpan.Shells.Bridge,
// métodos FloatAll/FloatSet, arquivo ~/.local/state/lowpan-shells/float-geometry.json). Sem o shell rodando, a
// memória vale só enquanto o KWin estiver aberto.

/** chama um método do helper da ponte do shell (org.lowpan.Shells.Bridge) pelo DBusCall do QML do KWin */
function lpBridge(method: string, args: any[], done?: (ret: any[]) => void) {
  FloatMemory.call(method, args, done);
}

class FloatMemory {
  private static cache: { [app: string]: { w: number; h: number } } = {};

  public static call(method: string, args: any[], done?: (ret: any[]) => void) {
    if (!LOWPAN_ROOT) return;
    try {
      const c: any = Qt.createQmlObject(
        'import org.kde.kwin; DBusCall { service: "org.lowpan.Shells.Bridge"; path: "/Bridge"; dbusInterface: "org.lowpan.Shells.Bridge" }',
        LOWPAN_ROOT as object
      );
      c.method = method;
      c.arguments = args;
      c.finished.connect((ret: any[]) => {
        try {
          if (done) done(ret);
        } finally {
          c.destroy();
        }
      });
      c.failed.connect(() => {
        lpDebug("memória flutuante: " + method + " falhou (a ponte do shell está rodando?)");
        c.destroy();
      });
      c.call();
    } catch (e) {
      lpDebug("memória flutuante: " + e);
    }
  }

  /** carrega tudo uma vez, ao iniciar */
  public static load() {
    FloatMemory.call("FloatAll", [], (ret) => {
      try {
        const data = JSON.parse(String(ret[0]));
        if (data && typeof data === "object") FloatMemory.cache = data;
        lpDebug("memória flutuante: " + Object.keys(FloatMemory.cache).length + " app(s)");
      } catch (e) {
        /* arquivo vazio ou inválido */
      }
    });
  }

  public static appOf(window: WindowClass): string {
    const c = (window.window as any).window;
    const app = c && c.resourceClass ? String(c.resourceClass) : "";
    // jogos da Steam (steam_app_<id>) escolhem a própria resolução: sem memória, senão abrem com o tamanho
    // de uma coluna gravado quando ainda iam para a faixa (§21.103)
    return /^steam_app_/i.test(app) ? "" : app;
  }

  public static sizeOf(window: WindowClass): { w: number; h: number } | null {
    const app = FloatMemory.appOf(window);
    return app ? FloatMemory.cache[app] ?? null : null;
  }

  public static remember(window: WindowClass, rect: Readonly<Rect>) {
    const app = FloatMemory.appOf(window);
    if (!app || rect.width < 50 || rect.height < 50) return;
    const w = Math.round(rect.width);
    const h = Math.round(rect.height);
    const old = FloatMemory.cache[app];
    if (old && old.w === w && old.h === h) return;
    FloatMemory.cache[app] = { w: w, h: h };
    lpDebug("memória flutuante: " + app + " = " + w + "x" + h);
    FloatMemory.call("FloatSet", [app, w, h]);
  }

  /** a geometria flutuante com o tamanho lembrado, centralizada na área útil (null = não há lembrança) */
  public static restore(window: WindowClass): Rect | null {
    const size = FloatMemory.sizeOf(window);
    if (!size) return null;
    const area = window.surface.workingArea;
    const w = Math.min(size.w, area.width);
    const h = Math.min(size.h, area.height);
    return new Rect(
      Math.round(area.x + (area.width - w) / 2),
      Math.round(area.y + (area.height - h) / 2),
      w,
      h
    );
  }
}
