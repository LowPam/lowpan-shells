// LowPan Tiling — layout "Niri": faixa horizontal de colunas que rola (tiling com rolagem).
// Copyright (c) 2026 LowPan Shells. Licença MIT, como o Krohnkite em que se baseia
// (Copyright (c) 2018-2019 Eon S. Jeon e colaboradores; ver LICENSE).
//
// Comportamento (PLANEJAMENTO §21):
//  - cada área de trabalho de cada monitor é uma faixa infinita de colunas; abrir uma janela nunca
//    encolhe as outras: ela vira uma coluna nova à direita da focada (largura padrão 1/2);
//  - a visão rola só o necessário para a coluna focada caber inteira; uma coluna sozinha fica centralizada,
//    várias que cabem ficam encostadas na esquerda;
//  - cada coluna empilha janelas na vertical (altura dividida); consumir/expulsar como no Niri;
//  - largura por coluna: predefinições 1/3, 1/2, 2/3, ±10 %, largura toda (maximizar);
//  - arrastar não reorganiza nada durante o movimento: ao soltar, a janela vira coluna no lugar apontado.
//  Colunas fora da visão ficam fora da tela (o KWin aceita). Com vários monitores, a que cairia dentro de outra saída
//  (o KWin a mudaria de faixa: a saída da janela é a mais próxima do centro dela) fica estacionada logo abaixo ou
//  acima da própria saída, num ponto que ainda é dela (niriPark).

const NIRI_DEFAULT_WIDTH = 0.5;
const NIRI_PRESET_WIDTHS = [1 / 3, 1 / 2, 2 / 3];
const NIRI_WIDTH_STEP = 0.1;
/** altura da barra de abas (desenhada pelo shell) no alto de uma coluna em abas */
const NIRI_TAB_BAR = 36;
/** altura: passo de ±10 % da coluna e a menor fatia de uma janela empilhada */
const NIRI_HEIGHT_STEP = 0.1;
const NIRI_MIN_SHARE = 0.1;

/**
 * Envia ao shell (pela ponte) as colunas em abas visíveis de todas as faixas, para ele desenhar as barras.
 * Só envia quando muda. Cada NiriLayout (uma por monitor/área/atividade) entra com a sua chave.
 */
class NiriTabPublisher {
  private static entries: { [key: string]: any[] } = {};
  private static last = "";
  private static nextKey = 1;

  public static newKey(): string {
    return "niri" + NiriTabPublisher.nextKey++;
  }

  /** tiling desligado: some com todas as barras */
  public static clearAll() {
    NiriTabPublisher.entries = {};
    NiriTabPublisher.publish("", []);
  }

  public static publish(key: string, columns: any[]) {
    if (columns.length > 0) NiriTabPublisher.entries[key] = columns;
    else delete NiriTabPublisher.entries[key];
    let all: any[] = [];
    for (const k of Object.keys(NiriTabPublisher.entries)) all = all.concat(NiriTabPublisher.entries[k]);
    const json = JSON.stringify({ type: "tiling", bar: NIRI_TAB_BAR, tabs: all });
    if (json === NiriTabPublisher.last) return;
    NiriTabPublisher.last = json;
    lpDebug("abas → shell: " + json.slice(0, 300));
    lpBridge("Event", [json]);
  }
}

type NiriDropMode = "column" | "tab" | "stack" | "deny";
interface NiriDrop {
  id: string;
  mode: NiriDropMode;
  /** meio: entra como coluna antes desta (null = no fim) */
  before: NiriColumn | null;
  /** aba/pilha: a coluna de destino */
  target: NiriColumn | null;
  /** aba/pilha: entra logo depois desta janela */
  targetId: string | null;
  /** barra de abas: posição entre as abas (-1 = não veio da barra) */
  tabIndex: number;
  preview: Rect | null;
  text: string;
}

/**
 * Vários monitores: onde pôr uma coluna fora da visão para ela não aparecer noutra saída nem mudar de saída.
 * Fica onde está se não toca outra saída; senão, logo abaixo (ou acima) da própria saída, encostada no canto mais
 * longe das outras, conferindo pela mesma regra do KWin (saída mais próxima do centro). null = não há lugar seguro.
 */
/** recuo das abas de trás numa coluna em abas (esconde o canto delas atrás do canto arredondado da da frente) */
const NIRI_TAB_BEHIND_INSET = 12;

function niriPark(rect: Rect, own: Rect, outputs: Rect[]): Rect | null {
  const ownIdx = outputs.findIndex((g) => g.x === own.x && g.y === own.y && g.width === own.width && g.height === own.height);
  const others = outputs.filter((_g, i) => i !== ownIdx);
  if (ownIdx < 0 || others.length === 0) return rect;
  const touches = (r: Rect) => others.some((g) => r.x < g.maxX && r.maxX > g.x && r.y < g.maxY && r.maxY > g.y);
  const ours = (r: Rect) => lpNearestOutput(outputs, r.x + r.width / 2, r.y + r.height / 2) === ownIdx;
  if (!touches(rect) && ours(rect)) return rect;
  const w = rect.width;
  const h = rect.height;
  const xs = [Math.max(own.x, Math.min(rect.x, own.maxX - w)), own.x, own.maxX - w];
  const ys = [own.maxY + 1, own.y - h - 1];
  for (const y of ys)
    for (const x of xs) {
      const r = new Rect(Math.round(x), Math.round(y), w, h);
      if (!touches(r) && ours(r)) return r;
    }
  return null;
}

class NiriColumn {
  private static nextUid = 1;
  /** identificador fixo da coluna (o shell reaproveita a barra de abas dela) */
  public readonly uid: string;
  public readonly stack: ColumnLayout;
  public width: number;
  /** largura antes de maximizar a coluna (null = não maximizada) */
  public widthBeforeFull: number | null;
  /** retângulo da última disposição (para o arrasto) */
  public rect: Rect | null;
  /** coluna em abas (toggle-column-tabbed-display do Niri): uma janela por vez, ocupando a coluna toda */
  public tabbed: boolean;
  /** a aba à frente (id da janela) */
  public activeTab: string | null;
  /** vários monitores: fora da visão e estacionada fora de todas as saídas (sem barra de abas, sem alvo de arrasto) */
  public parked: boolean;
  /** retângulo na faixa, antes de estacionar (ordem das colunas para o arrasto) */
  public lane: Rect | null;

  constructor(width?: number) {
    this.uid = "c" + NiriColumn.nextUid++;
    this.stack = new ColumnLayout();
    this.stack.isHorizontal = false;
    this.width = width ?? NIRI_DEFAULT_WIDTH;
    this.widthBeforeFull = null;
    this.parked = false;
    this.lane = null;
    this.rect = null;
    this.tabbed = false;
    this.activeTab = null;
  }

  public get ids(): Set<string> {
    return this.stack.windowIds;
  }

  public has(id: string): boolean {
    return this.stack.windowIds.has(id);
  }

  /** visível na faixa: tem ao menos uma janela que não está minimizada nem flutuante */
  public isShown(): boolean {
    return !this.stack.isEmpty();
  }

  public idList(): string[] {
    return [...this.stack.windowIds];
  }

  public setIdList(ids: string[]) {
    this.stack.windowIds = new Set(ids);
  }
}

class NiriLayout implements ILayout {
  public static readonly id = "Niri";
  public readonly classID = NiriLayout.id;

  public get description(): string {
    return "Niri";
  }

  private columns: NiriColumn[];
  private offset: number;
  private centerOnce: boolean;
  private drop: NiriDrop | null;
  private lastGap = 0;
  private lastCtx: EngineContext | null = null;
  private lastFocusColumn: number;
  private readonly tabKey: string;
  /** área da última disposição (expandir a coluna precisa saber o que está inteiro na tela) */
  private lastArea: Rect | null = null;
  /** a tela inteira (a prévia de aba vai no vão entre o alto da tela e as janelas, onde fica a ilha) */
  private lastScreen: Rect | null = null;

  /**
   * Vários monitores: a coluna que está sendo levada a outra saída (Mod+Ctrl+Shift+←/→). A faixa de destino junta essas
   * janelas numa coluna só, com a largura e as abas que ela tinha, em vez de uma coluna por janela.
   */
  public static incoming: { ids: string[]; width: number; tabbed: boolean; activeTab: string | null; at: number } | null = null;

  /** a coluna da janela, para levá-la a outra saída (ids na ordem da coluna) */
  public columnFor(id: string): { ids: string[]; width: number; tabbed: boolean; activeTab: string | null; at: number } | null {
    const i = this.columnOf(id);
    if (i < 0) return null;
    const c = this.columns[i];
    return { ids: c.idList(), width: c.widthBeforeFull ?? c.width, tabbed: c.tabbed, activeTab: c.activeTab, at: Date.now() };
  }

  constructor() {
    this.columns = [];
    this.offset = 0;
    this.centerOnce = false;
    this.drop = null;
    this.lastFocusColumn = 0;
    this.tabKey = NiriTabPublisher.newKey();
  }

  // ───────────────────────── janelas ↔ colunas ─────────────────────────

  private columnOf(id: string): number {
    for (let i = 0; i < this.columns.length; i++)
      if (this.columns[i].has(id)) return i;
    return -1;
  }

  private shownColumns(): NiriColumn[] {
    return this.columns.filter((c) => c.isShown());
  }

  /** coluna focada: a da janela ativa, senão a da janela usada por último */
  private focusedColumn(ctx: EngineContext, tileables: WindowClass[]): number {
    const current = ctx.currentWindow;
    if (current !== null) {
      const i = this.columnOf(current.id);
      if (i >= 0 && this.columns[i].isShown()) return i;
    }
    let best = -1;
    let found = -1;
    for (const t of tileables) {
      const i = this.columnOf(t.id);
      if (i >= 0 && t.timestamp > best) {
        best = t.timestamp;
        found = i;
      }
    }
    if (found >= 0) return found;
    return Math.min(this.lastFocusColumn, this.columns.length - 1);
  }

  /** coluna em abas que ficou com uma janela só volta a ser comum (juntar de novo empilha, não vira aba) */
  private untabIfSingle(c: NiriColumn) {
    if (c.tabbed && c.ids.size <= 1) {
      c.tabbed = false;
      c.activeTab = null;
    }
  }

  private sync(ctx: EngineContext, tileables: WindowClass[]) {
    const ids = new Set(tileables.map((t) => t.id));
    // tira o que sumiu (minimizadas e flutuantes ficam guardadas na coluna, como o Krohnkite faz)
    this.columns.forEach((c) => {
      const before = c.ids.size;
      c.stack.actualizeWindowIds(ctx, ids);
      if (c.ids.size < before) this.untabIfSingle(c);
    });
    // a coluna onde a janela nova entra: à direita da focada antes de qualquer remoção
    let at = -1;
    const fresh = tileables.filter((t) => this.columnOf(t.id) < 0);
    if (fresh.length > 0) {
      const known = tileables.filter((t) => this.columnOf(t.id) >= 0);
      let best = -1;
      for (const t of known) {
        const i = this.columnOf(t.id);
        if (t.timestamp > best) {
          best = t.timestamp;
          at = i;
        }
      }
      if (at < 0) at = Math.min(this.lastFocusColumn, this.columns.length - 1);
    }
    // referência à coluna (não ao índice): as vazias saem antes de inserir
    const anchor = at >= 0 ? this.columns[at] : null;
    this.columns = this.columns.filter((c) => c.ids.size > 0);
    let anchorIdx = anchor ? this.columns.indexOf(anchor) : -1;
    if (anchorIdx < 0) anchorIdx = Math.min(at, this.columns.length - 1);
    let insertAt = anchorIdx + 1;
    // vários monitores: a coluna que chega de outra saída entra inteira (largura e abas de antes)
    const inc = NiriLayout.incoming;
    if (inc && Date.now() - inc.at > 5000) NiriLayout.incoming = null;
    // as janelas chegam uma a uma (uma disposição por janela): as seguintes entram na coluna que a primeira abriu
    let incCol: NiriColumn | null = inc ? this.columns.find((c) => c.ids.size > 0 && inc.ids.some((id) => c.has(id))) ?? null : null;
    for (const t of fresh) {
      if (inc && NiriLayout.incoming && inc.ids.indexOf(t.id) >= 0) {
        if (!incCol) {
          incCol = new NiriColumn(inc.width);
          incCol.tabbed = inc.tabbed;
          incCol.activeTab = inc.activeTab;
          this.columns.splice(insertAt, 0, incCol);
          insertAt++;
        }
        incCol.ids.add(t.id);
        continue;
      }
      // regra do iNiR (WezTerm): a coluna nasce com a largura que a janela pediu
      let own: number | undefined;
      if (lpOwnWidth((t.window as any).window) && this.lastArea && this.lastArea.width > 0)
        own = Math.max(0.1, Math.min(1, Math.round((t.actualGeometry.width / this.lastArea.width) * 100) / 100));
      const column = new NiriColumn(own);
      column.ids.add(t.id);
      this.columns.splice(insertAt, 0, column);
      insertAt++;
    }
    if (incCol && inc) {
      incCol.setIdList(inc.ids.filter((id) => incCol!.ids.has(id)));
      if (inc.ids.every((id) => incCol!.ids.has(id))) NiriLayout.incoming = null;
    }
    // recalcula os contadores de ocultas depois de inserir
    this.columns.forEach((c) => c.stack.actualizeWindowIds(ctx, ids));
  }

  // ───────────────────────── disposição ─────────────────────────

  public apply(
    ctx: EngineContext,
    tileables: WindowClass[],
    area: Rect,
    gap: number
  ): void {
    this.sync(ctx, tileables);
    this.lastArea = area;
    const out: any = tileables[0] ? (tileables[0].surface as any).output : null;
    if (out && out.geometry) this.lastScreen = new Rect(out.geometry.x, out.geometry.y, out.geometry.width, out.geometry.height);
    this.lastGap = gap;
    this.lastCtx = ctx;
    tileables.forEach((t) => (t.state = WindowState.Tiled));
    const shown = this.shownColumns();
    if (shown.length === 0) {
      NiriTabPublisher.publish(this.tabKey, []);
      return;
    }

    const A = area.width;
    const widths = shown.map((c) => Math.round((A + gap) * c.width - gap));
    const xs: number[] = [];
    let x = 0;
    widths.forEach((w) => {
      xs.push(x);
      x += w + gap;
    });
    const total = x - gap;

    const focusIdx = this.focusedColumn(ctx, tileables);
    this.lastFocusColumn = Math.max(0, focusIdx);
    let f = focusIdx >= 0 ? shown.indexOf(this.columns[focusIdx]) : 0;
    if (f < 0) f = 0;

    if (shown.length === 1 && total <= A) {
      this.offset = (total - A) / 2; // always-center-single-column
    } else if (total <= A) {
      this.offset = 0; // cabem todas: encostadas na esquerda
    } else if (this.centerOnce) {
      this.offset = xs[f] + widths[f] / 2 - A / 2;
    } else {
      // center-focused-column "never": rola só o necessário
      if (xs[f] < this.offset) this.offset = xs[f];
      if (xs[f] + widths[f] > this.offset + A)
        this.offset = xs[f] + widths[f] - A;
      this.offset = Math.max(0, Math.min(this.offset, total - A));
    }
    this.centerOnce = false;

    lpDebug(
      "faixa foco=" + f + " off=" + Math.round(this.offset) + " | " +
        this.columns
          .map((c) => (c.isShown() ? "" : "(oculta)") + (c.tabbed ? "[abas " + c.activeTab + "]" : "") + Math.round(c.width * 100) + "%:" +
            c.idList().map((id) => lpWin(ctx.getWindowById(id))).join("+"))
          .join("  ") +
        " ← " + String(new Error().stack).split("\n").slice(2, 5).map((l) => l.split("@")[0]).join(" < ")
    );
    const outputs = lpOutputRects();
    const own = this.lastScreen;
    shown.forEach((c, i) => {
      c.rect = new Rect(
        Math.round(area.x + xs[i] - this.offset),
        area.y,
        widths[i],
        area.height
      );
      // vários monitores: a coluna que sai pela borda não pode entrar na outra saída (nem pela metade)
      c.parked = false;
      c.lane = c.rect;
      if (own && outputs.length > 1 && !area.includes(c.rect)) {
        const spot = niriPark(c.rect, own, outputs);
        if (spot && !spot.equals(c.rect)) {
          c.rect = spot;
          c.parked = true;
        }
      }
      // na ordem da coluna (o ColumnLayout desenha na ordem em que recebe; mover na coluna só muda essa ordem)
      const order = c.idList();
      const mine = tileables.filter((t) => c.has(t.id)).sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
      if (c.tabbed && mine.length > 1) this.applyTabs(ctx, c, mine);
      else c.stack.apply(ctx, mine, c.rect, gap);
    });
    this.publishTabs(tileables);
  }

  /** as colunas em abas com 2+ janelas visíveis → barras do shell (retângulo da barra e as abas) */
  private publishTabs(tileables: WindowClass[]) {
    const out: any[] = [];
    const first = tileables[0];
    const srf: any = first ? first.surface : null;
    const output = srf && srf.output ? String(srf.output.name) : "";
    const desktop = srf && srf.desktop ? String(srf.desktop.id) : "";
    for (const c of this.shownColumns()) {
      if (!c.tabbed || !c.rect || c.parked) continue;
      const mine = tileables.filter((t) => c.has(t.id));
      if (mine.length < 2) continue;
      const order = c.idList();
      mine.sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
      const tabs = mine.map((t) => {
        const client = (t.window as any).window;
        return {
          id: client ? String(client.internalId) : t.id,
          title: client ? String(client.caption || "") : "",
          app: client ? String(client.desktopFileName || client.resourceClass || "") : "",
          active: t.id === c.activeTab,
        };
      });
      out.push({ uid: c.uid, output: output, desktop: desktop, x: c.rect.x, y: c.rect.y, width: c.rect.width, height: NIRI_TAB_BAR, tabs: tabs });
    }
    NiriTabPublisher.publish(this.tabKey, out);
  }

  // ───────────────────────── abas ─────────────────────────

  /**
   * Coluna em abas: todas as janelas ficam no retângulo inteiro da coluna, a aba ativa na frente.
   * As outras ficam atrás, no mesmo lugar (sem animação ao trocar; dock e Alt+Tab continuam vendo todas).
   */
  private applyTabs(ctx: EngineContext, c: NiriColumn, mine: WindowClass[]) {
    const current = ctx.currentWindow;
    if (current && c.has(current.id)) c.activeTab = current.id;
    if (c.activeTab === null || !mine.some((t) => t.id === c.activeTab)) {
      let best = mine[0];
      for (const t of mine) if (t.timestamp > best.timestamp) best = t;
      c.activeTab = best.id;
    }
    // a barra de abas do shell ocupa o alto da coluna; as janelas ficam logo abaixo
    const r = c.rect as Rect;
    const below = new Rect(r.x, r.y + NIRI_TAB_BAR, r.width, r.height - NIRI_TAB_BAR);
    // LowPan: as de trás ficam um pouco recolhidas — no mesmo retângulo, o canto delas (o Firefox desenha o seu reto)
    // aparecia em volta da curva do canto arredondado da da frente. 12 px escondem o canto até raio ~40 px.
    const inset = NIRI_TAB_BEHIND_INSET;
    const behind = new Rect(below.x + inset, below.y + inset, below.width - 2 * inset, below.height - 2 * inset);
    for (const t of mine) t.geometry = t.id === c.activeTab ? below : behind;
  }

  /** só cabe em abas quem aceita o tamanho da coluna inteira (tamanho mínimo/máximo do app ou de regra) */
  private canTab(window: WindowClass, rect: Rect | null): boolean {
    if (!rect) return true;
    const client = (window.window as any).window;
    if (!client) return true;
    const min = client.minSize;
    const max = client.maxSize;
    if (min && (min.width > rect.width + 1 || min.height > rect.height + 1)) return false;
    if (max && max.width > 0 && max.height > 0 && (max.width < rect.width - 2 || max.height < rect.height - 2))
      return false;
    return true;
  }

  private tabCaption(ctx: EngineContext, c: NiriColumn, id: string): string {
    const ids = c.idList().filter((x) => {
      const w = ctx.getWindowById(x);
      return w !== null && w.tiled;
    });
    const w = ctx.getWindowById(id);
    const client = w ? (w.window as any).window : null;
    const title = client && client.caption ? " — " + String(client.caption) : "";
    return lpTr("Tab %1 of %2", ids.indexOf(id) + 1, ids.length) + title;
  }

  private toggleTabbed(ctx: EngineContext, window: WindowClass): boolean {
    const i = this.columnOf(window.id);
    if (i < 0) return false;
    const c = this.columns[i];
    if (!c.tabbed) {
      for (const id of c.ids) {
        const w = ctx.getWindowById(id);
        if (w && w.tiled && !this.canTab(w, c.rect)) {
          ctx.showNotification(lpTr("Can't make tabs: a window in this column doesn't accept the column's size"));
          return true;
        }
      }
      c.tabbed = true;
      c.activeTab = window.id;
      ctx.showNotification(c.ids.size > 1 ? lpTr("Tabbed column") + " · " + this.tabCaption(ctx, c, window.id) : lpTr("Tabbed column"));
    } else {
      c.tabbed = false;
      c.activeTab = null;
      ctx.showNotification(lpTr("Stacked column"));
    }
    return true;
  }

  // ───────────────────────── arrastar ─────────────────────────
  // Como no Niri, nada se mexe durante o arrasto; o destino é aplicado ao soltar (commitDrop). Zonas (§21.13):
  //   barra de abas de uma coluna em abas → entra como aba naquela posição;
  //   perto do topo da janela sob o cursor → "Aderir à aba"; perto do rodapé → "Aderir à pilha" (embaixo dela);
  //   meio → vira coluna onde soltar (o que já existia), com uma linha mostrando onde.
  // A prévia (quadro do tema Plasma, droppreview.qml) só aparece depois de ~160 ms na mesma zona; antes disso,
  // soltar faz o comportamento de coluna.

  private dragKey = "";
  /** janela sendo arrastada (as outras recuam) */
  private dragging: string | null = null;
  private dragShownKey = "";

  private dropCandidate(ctx: EngineContext, window: WindowClass, cx: number, cy: number, own: number): NiriDrop {
    const drop: NiriDrop = {
      id: window.id, mode: "column", before: null, target: null, targetId: null, tabIndex: -1, preview: null, text: "",
    };
    // coluna antes da qual entra (meio): a primeira cujo centro fica à direita do cursor
    for (const c of this.shownColumns()) {
      if (this.columns.indexOf(c) === own && c.ids.size === 1) continue;
      const lane = c.lane ?? c.rect;
      if (lane && cx < lane.x + lane.width / 2) {
        drop.before = c;
        break;
      }
    }
    const deny = (c: NiriColumn): NiriDrop => {
      drop.mode = "deny";
      drop.target = c;
      drop.preview = this.band(c, "top");
      drop.text = lpTr("This window doesn't fit in tabs");
      return drop;
    };
    const asTab = (c: NiriColumn, index: number, afterId: string | null): NiriDrop => {
      for (const id of c.ids) {
        const w = ctx.getWindowById(id);
        if (w && id !== window.id && w.tiled && !this.canTab(w, c.rect)) return deny(c);
      }
      if (!this.canTab(window, c.rect)) return deny(c);
      drop.mode = "tab";
      drop.target = c;
      drop.tabIndex = index;
      drop.targetId = afterId;
      drop.preview = this.band(c, "top");
      drop.text = lpTr("Join as a tab");
      return drop;
    };
    for (const c of this.shownColumns()) {
      const r = c.rect;
      if (!r || cx < r.x || cx >= r.x + r.width || cy < r.y || cy >= r.y + r.height) continue;
      const tabs = this.stacked(ctx, c).filter((w) => w.id !== window.id);
      // 1) barra de abas (só existe com 2+ abas)
      if (c.tabbed && this.stacked(ctx, c).length > 1 && cy < r.y + NIRI_TAB_BAR) {
        if (c.has(window.id)) return drop;
        const n = tabs.length;
        const index = Math.max(0, Math.min(n, Math.round(((cx - r.x) / r.width) * n)));
        return asTab(c, index, null);
      }
      // 2) a janela sob o cursor
      if (c.has(window.id) && c.ids.size === 1) return drop; // a própria coluna dela, sozinha
      let target: WindowClass | null = null;
      if (c.tabbed && tabs.length > 0) target = ctx.getWindowById(c.activeTab ?? "") ?? tabs[0];
      else for (const t of tabs) if (t.geometry.includesPoint([cx, cy])) target = t;
      if (!target || target.id === window.id) return drop;
      const g = target.geometry;
      const zone = this.zoneHeight(g.height);
      if (cy < g.y + zone) return asTab(c, -1, target.id);
      // a zona de pilha começa mais alto que a de aba (pedido do usuário: "muito embaixo"): 30 %, entre 90 e 260 px
      const stackZone = Math.round(Math.max(90, Math.min(260, g.height * 0.3)));
      if (cy > g.y + g.height - stackZone) {
        if (c.tabbed) return asTab(c, -1, target.id);
        drop.mode = "stack";
        drop.target = c;
        drop.targetId = target.id;
        drop.preview = this.band(c, "bottom") ?? new Rect(g.x, g.y + g.height - this.zoneHeight(g.height), g.width, this.zoneHeight(g.height));
        drop.text = lpTr("Join the stack");
        return drop;
      }
      return drop;
    }
    return drop;
  }

  /** altura das zonas de aderir (e da prévia): 20 % da janela, entre 60 e 160 px */
  private zoneHeight(h: number): number {
    return Math.round(Math.max(60, Math.min(160, h * 0.2)));
  }

  /**
   * Faixa da prévia de aba: no vão entre o alto da tela e o topo da coluna (ao lado da ilha), com 80 % da altura do vão
   * e centralizada nele (pedido do usuário, 2026-11-06). Sem vão (< 40 px): no alto da coluna, abaixo da barra de abas.
   */
  //  A de pilha espelha a de aba: mesmo tamanho e posição horizontal, colada no rodapé da tela com a mesma folga.
  private band(c: NiriColumn, where: "top" | "bottom"): Rect | null {
    const body = this.columnBody(c);
    const r = c.rect;
    if (!body || !r) return null;
    const scr = this.lastScreen;
    const gap = scr ? r.y - scr.y : 0;
    if (scr && gap >= 40) {
      const h = Math.round(gap * 0.8);
      if (where === "top") {
        const w = Math.round(r.width * 0.7); // 70 % da coluna, centralizada (marcação do usuário no print)
        return new Rect(r.x + Math.round((r.width - w) / 2), scr.y + Math.round((gap - h) / 2), w, h);
      }
      // pilha: posição medida com a régua do usuário (2026-11-06; coluna de 1673 px → x +154, 1059 × 62, fundo no fim
      // da área útil, logo acima da reserva da dock)
      const area = this.lastArea ?? scr;
      // medida numa coluna à esquerda da tela: 63,3 % da coluna, a 9,2 % da borda esquerda dela. Numa coluna à
      // direita da tela é o espelho (a 9,2 % da borda direita) — afasta-se sempre do centro, onde fica a dock
      const w = Math.round(r.width * 0.633);
      const side = Math.round(r.width * 0.092);
      const rightSide = r.x + r.width / 2 > scr.x + scr.width / 2;
      const x = rightSide ? r.x + r.width - side - w : r.x + side;
      return new Rect(x, area.y + area.height - h, w, h);
    }
    if (where === "bottom") return null; // sem vão: o chamador usa o rodapé da janela de destino
    return new Rect(body.x, body.y, body.width, this.zoneHeight(body.height));
  }

  /** a área das janelas de uma coluna (sem a barra de abas) */
  private columnBody(c: NiriColumn): Rect | null {
    const r = c.rect;
    if (!r) return null;
    if (c.tabbed) return new Rect(r.x, r.y + NIRI_TAB_BAR, r.width, r.height - NIRI_TAB_BAR);
    return r;
  }

  public drag(
    ctx: EngineContext,
    draggingRect: Rect,
    window: WindowClass,
    workingArea: Rect
  ): boolean {
    const cursor = ctx.cursorPos || draggingRect.center;
    const own = this.columnOf(window.id);
    // o recuo das outras janelas é o efeito KWin lowpan_drag_inset (só visual; effect/lowpan_drag_inset);
    // o papel de parede desfoca: o shell recebe o começo/fim do arrasto pela ponte
    if (this.dragging !== window.id) {
      // o id que as abas publicam (publishTabs): internalId do KWin
      const client = (window.window as any).window;
      lpBridge("Event", [JSON.stringify({ type: "tilingDrag", dragging: true, id: client ? String(client.internalId) : window.id })]);
    }
    this.dragging = window.id;
    const drop = this.dropCandidate(ctx, window, cursor[0], cursor[1], own);
    // meio (troca de lugar): sem prévia — a linha de onde a coluna entra foi tirada a pedido do usuário
    if (drop.mode === "column") {
      drop.preview = null;
      drop.text = "";
    }
    this.drop = drop;
    // a zona (não o retângulo: o recuo muda as janelas e fazia a prévia piscar)
    const key = [drop.mode, drop.target ? drop.target.uid : "", drop.targetId, drop.tabIndex,
      drop.before ? drop.before.uid : "fim"].join("|");
    if (key === this.dragKey) return false;
    this.dragKey = key;
    const show = () => {
      if (this.dragKey !== key || !this.drop || this.drop.id !== window.id) return;
      this.dragShownKey = key;
      const r = drop.preview;
      if (r) lowpanDropPreview.show(r.x, r.y, r.width, r.height, drop.text, drop.mode);
      else lowpanDropPreview.hide();
      lpDebug("arrasto: " + drop.mode + " " + drop.text);
    };
    // a 1ª prévia espera ~160 ms parado na zona; com uma já na tela, troca na hora (o KDE anima o quadro, sem piscar)
    if (this.dragShownKey !== "") show();
    else ctx.setTimeout(show, 160);
    return false;
  }

  /** soltou: aplica o destino que a prévia mostrava (antes da prévia aparecer, vale o de coluna) */
  public commitDrop(window: WindowClass) {
    const drop = this.drop;
    const shown = this.dragShownKey === this.dragKey;
    if (this.dragging !== null) lpBridge("Event", [JSON.stringify({ type: "tilingDrag", dragging: false })]);
    this.dragging = null;
    this.drop = null;
    this.dragKey = "";
    this.dragShownKey = "";
    lowpanDropPreview.hide();
    if (!drop || drop.id !== window.id) return;
    const from = this.columnOf(window.id);
    if (from < 0) return;
    const source = this.columns[from];
    let mode = drop.mode;
    if (!shown && mode !== "column") mode = "column";
    if (mode === "deny") return; // volta para o lugar dela
    lpDebug("soltou: " + mode);

    const width = source.width;
    source.ids.delete(window.id);
    if (source.activeTab === window.id) source.activeTab = null;
    this.untabIfSingle(source);
    if (source.ids.size === 0 && source !== drop.target) this.columns.splice(this.columns.indexOf(source), 1);

    if (mode === "column") {
      const column = new NiriColumn(width);
      column.ids.add(window.id);
      const at = drop.before ? this.columns.indexOf(drop.before) : -1;
      this.columns.splice(at < 0 ? this.columns.length : at, 0, column);
      return;
    }
    const target = drop.target as NiriColumn;
    const list = target.idList().filter((id) => id !== window.id);
    let at = list.length;
    if (mode === "tab" && drop.tabIndex >= 0) {
      // a posição na barra conta só as abas visíveis
      const visible = list.filter((id) => {
        const w = this.lastCtx ? this.lastCtx.getWindowById(id) : null;
        return w !== null && w.tiled && !w.minimized;
      });
      const ref = visible[drop.tabIndex];
      at = ref !== undefined ? list.indexOf(ref) : list.length;
    } else if (drop.targetId !== null && list.indexOf(drop.targetId) >= 0) {
      at = list.indexOf(drop.targetId) + 1; // logo depois da janela de destino
    }
    list.splice(at, 0, window.id);
    target.setIdList(list);
    if (mode === "tab") {
      target.tabbed = true;
      target.activeTab = window.id;
    }
  }

  // ───────────────────────── maximizar = coluna na largura toda ─────────────────────────

  public toggleFullWidth(window: WindowClass): boolean {
    const i = this.columnOf(window.id);
    if (i < 0) return false;
    const c = this.columns[i];
    if (c.widthBeforeFull !== null) {
      c.width = c.widthBeforeFull;
      c.widthBeforeFull = null;
    } else {
      c.widthBeforeFull = c.width;
      c.width = 1;
    }
    return true;
  }

  // ───────────────────────── altura das empilhadas ─────────────────────────

  /** janelas da coluna que dividem a altura (lado a lado e visíveis), de cima para baixo */
  private stacked(ctx: EngineContext, c: NiriColumn): WindowClass[] {
    const out: WindowClass[] = [];
    for (const id of c.idList()) {
      const w = ctx.getWindowById(id);
      if (w && w.tiled && !w.minimized) out.push(w);
    }
    return out;
  }

  /** set-window-height ±10 % do Niri: a janela ganha/perde 10 % da coluna, as outras dividem o resto na proporção atual */
  private changeHeight(ctx: EngineContext, window: WindowClass, step: number): boolean {
    const i = this.columnOf(window.id);
    if (i < 0) return false;
    const c = this.columns[i];
    if (c.tabbed) return true; // em abas cada janela ocupa a coluna toda
    const ws = this.stacked(ctx, c);
    const k = ws.indexOf(window);
    if (ws.length < 2 || k < 0) return true;
    const total = ws.reduce((a, w) => a + w.weight, 0);
    const shares = ws.map((w) => w.weight / total);
    const maxShare = 1 - NIRI_MIN_SHARE * (ws.length - 1);
    const next = Math.max(NIRI_MIN_SHARE, Math.min(maxShare, shares[k] + step));
    const restBefore = 1 - shares[k];
    const restAfter = 1 - next;
    ws.forEach((w, j) => {
      const share = j === k ? next : restBefore > 0 ? (shares[j] * restAfter) / restBefore : restAfter / (ws.length - 1);
      w.weight = Math.max(NIRI_MIN_SHARE, share) * ws.length;
    });
    return true;
  }

  /** reset-window-height: alturas iguais na coluna */
  private resetHeights(ctx: EngineContext, window: WindowClass): boolean {
    const i = this.columnOf(window.id);
    if (i < 0) return false;
    this.stacked(ctx, this.columns[i]).forEach((w) => (w.weight = 1));
    return true;
  }

  // ───────────────────────── layouts do iNiR (tilingOverlay) ─────────────────────────
  // O iNiR monta estes layouts no Niri com macros (separar tudo, consumir, mudar largura). Aqui o motor arruma as colunas
  // direto. "monocle" usa a coluna em abas (uma janela por vez na largura toda). §21.16.

  private static readonly PRESETS = ["off", "master-left", "master-right", "columns", "monocle"];
  private preset = "off";

  /** janelas lado a lado visíveis, na ordem da faixa (coluna a coluna, de cima para baixo) */
  private stripOrder(ctx: EngineContext): WindowClass[] {
    const out: WindowClass[] = [];
    for (const c of this.columns) for (const w of this.stacked(ctx, c)) out.push(w);
    return out;
  }

  private rebuild(groups: WindowClass[][], widths: number[], tabbed: boolean[]) {
    // colunas só com minimizadas/flutuantes ficam onde estavam (no fim), as outras são refeitas
    const keepIds = new Set<string>();
    groups.forEach((g) => g.forEach((w) => keepIds.add(w.id)));
    const rest = this.columns.filter((c) => {
      for (const id of keepIds) c.ids.delete(id);
      return c.ids.size > 0;
    });
    const built = groups.map((g, i) => {
      const c = new NiriColumn(widths[i]);
      c.setIdList(g.map((w) => w.id));
      c.tabbed = tabbed[i] && g.length > 1;
      c.activeTab = c.tabbed ? g[0].id : null;
      g.forEach((w) => (w.weight = 1));
      return c;
    });
    this.columns = built.concat(rest);
  }

  /** aplica um layout do iNiR às janelas desta faixa */
  public applyPreset(ctx: EngineContext, name: string): boolean {
    const ws = this.stripOrder(ctx);
    const n = ws.length;
    if (NiriLayout.PRESETS.indexOf(name) < 0) return false;
    this.preset = name;
    if (n === 0) return true;
    switch (name) {
      case "master-left":
        if (n >= 2) { this.rebuild([[ws[0]], ws.slice(1)], [0.5, 0.5], [false, false]); break; }
        this.rebuild([ws], [NIRI_DEFAULT_WIDTH], [false]);
        break;
      case "master-right":
        if (n >= 2) { this.rebuild([ws.slice(0, n - 1), [ws[n - 1]]], [0.5, 0.5], [false, false]); break; }
        this.rebuild([ws], [NIRI_DEFAULT_WIDTH], [false]);
        break;
      case "columns":
        this.rebuild(ws.map((w) => [w]), ws.map(() => Math.max(0.1, Math.floor(100 / n) / 100)), ws.map(() => false));
        break;
      case "monocle": {
        const all = ws.every((w) => this.canTab(w, this.lastArea));
        this.rebuild([ws], [1], [all]);
        if (!all) ctx.showNotification(lpTr("Monocle stacked: a window doesn't accept the whole column"));
        break;
      }
      default: // off
        this.rebuild(ws.map((w) => [w]), ws.map(() => NIRI_DEFAULT_WIDTH), ws.map(() => false));
    }
    const focus = ctx.currentWindow;
    if (focus) focus.timestamp = new Date().getTime();
    this.centerOnce = name === "monocle";
    lpBridge("Event", [JSON.stringify({ type: "tilingPreset", layout: name, count: n })]);
    return true;
  }

  /** promote-to-master do iNiR: a janela focada vira a mestre (a antiga vai para o topo da pilha) */
  private promote(ctx: EngineContext, window: WindowClass | null): boolean {
    if (!window || (this.preset !== "master-left" && this.preset !== "master-right")) return true;
    const ws = this.stripOrder(ctx);
    const n = ws.length;
    if (n < 2) return true;
    const masterIdx = this.preset === "master-left" ? 0 : n - 1;
    const k = ws.indexOf(window);
    if (k < 0 || k === masterIdx) return true;
    const oldMaster = ws[masterIdx];
    const others = ws.filter((w) => w !== window && w !== oldMaster);
    const stack = [oldMaster].concat(others);
    if (this.preset === "master-left") this.rebuild([[window], stack], [0.5, 0.5], [false, false]);
    else this.rebuild([stack, [window]], [0.5, 0.5], [false, false]);
    return true;
  }

  // ───────────────────────── atalhos (ações do Niri) ─────────────────────────

  private focusColumn(ctx: EngineContext, column: NiriColumn | undefined): boolean {
    if (!column) return true;
    const target = this.windowToFocus(ctx, column);
    if (target) {
      target.timestamp = new Date().getTime();
      ctx.currentWindow = target;
    }
    return true;
  }

  /** move-column-to-first/last: a coluna vai para a ponta da faixa */
  private moveColumnToEnd(i: number, toFirst: boolean): boolean {
    if (i < 0) return false;
    const [c] = this.columns.splice(i, 1);
    if (toFirst) this.columns.unshift(c);
    else this.columns.push(c);
    return true;
  }

  /**
   * expand-column-to-available-width do Niri: a coluna cresce até ocupar o espaço que as outras colunas inteiramente
   * visíveis deixam livre na tela (com os espaços: n colunas de largura w somando 1 enchem a tela exatamente).
   */
  private expandColumn(i: number): boolean {
    if (i < 0) return false;
    const c = this.columns[i];
    const area = this.lastArea;
    if (!area) return true;
    let others = 0;
    for (const o of this.shownColumns()) {
      if (o === c || !o.rect) continue;
      if (o.rect.x >= area.x - 1 && o.rect.x + o.rect.width <= area.x + area.width + 1) others += o.width;
    }
    const free = Math.round((1 - others) * 100) / 100;
    if (free > c.width + 0.005) {
      c.width = Math.min(1, free);
      c.widthBeforeFull = null;
    }
    return true;
  }

  private windowToFocus(ctx: EngineContext, column: NiriColumn): WindowClass | null {
    let best: WindowClass | null = null;
    for (const id of column.ids) {
      const w = ctx.getWindowById(id);
      if (w && w.tiled && (best === null || w.timestamp > best.timestamp)) best = w;
    }
    return best;
  }

  private neighbourColumn(i: number, step: -1 | 1): number {
    for (let j = i + step; j >= 0 && j < this.columns.length; j += step)
      if (this.columns[j].isShown()) return j;
    return -1;
  }

  private moveIdInColumn(c: NiriColumn, id: string, step: -1 | 1): boolean {
    const list = c.idList();
    const k = list.indexOf(id);
    const t = k + step;
    if (k < 0 || t < 0 || t >= list.length) return false;
    [list[k], list[t]] = [list[t], list[k]];
    c.setIdList(list);
    return true;
  }

  /** consume-or-expel do Niri: sozinha entra na coluna vizinha; empilhada sai para uma coluna nova */
  private consumeOrExpel(ctx: EngineContext, window: WindowClass, step: -1 | 1): boolean {
    const i = this.columnOf(window.id);
    if (i < 0) return false;
    const c = this.columns[i];
    if (c.ids.size > 1) {
      c.ids.delete(window.id);
      if (c.activeTab === window.id) c.activeTab = null;
      this.untabIfSingle(c);
      const column = new NiriColumn(c.width);
      column.ids.add(window.id);
      this.columns.splice(step < 0 ? i : i + 1, 0, column);
      return true;
    }
    const j = this.neighbourColumn(i, step);
    if (j < 0) return false;
    const target = this.columns[j];
    // numa coluna em abas a janela ocupa a coluna inteira: só entra quem aceita esse tamanho
    if (target.tabbed && !this.canTab(window, target.rect)) {
      ctx.showNotification(lpTr("This window doesn't accept the tabbed column's size"));
      return true;
    }
    target.ids.add(window.id);
    if (target.tabbed) {
      target.activeTab = window.id;
      ctx.showNotification(this.tabCaption(ctx, target, window.id));
    }
    this.columns.splice(i, 1);
    return true;
  }

  public handleShortcut(ctx: EngineContext, input: Shortcut, data?: any): boolean {
    const window = ctx.currentWindow;
    const i = window ? this.columnOf(window.id) : -1;
    switch (input) {
      // o modo de teclas "dwm" (padrão do Krohnkite) troca Focus* por DWM*/FocusNext/Prev antes de chegar aqui
      case Shortcut.FocusLeft:
      case Shortcut.FocusRight:
      case Shortcut.DWMLeft:
      case Shortcut.DWMRight: {
        if (i < 0) return false;
        const left = input === Shortcut.FocusLeft || input === Shortcut.DWMLeft;
        const j = this.neighbourColumn(i, left ? -1 : 1);
        if (j < 0) return true; // na ponta: não sai da faixa
        const target = this.windowToFocus(ctx, this.columns[j]);
        if (target) {
          target.timestamp = new Date().getTime();
          ctx.currentWindow = target;
        }
        return true;
      }
      case Shortcut.FocusUp:
      case Shortcut.FocusDown:
      case Shortcut.FocusNext:
      case Shortcut.FocusPrev: {
        if (i < 0 || !window) return false;
        const c = this.columns[i];
        // a ordem da coluna (de cima para baixo; em abas, da primeira à última aba)
        const ids = c.idList().filter((x) => {
          const w = ctx.getWindowById(x);
          return w !== null && w.tiled;
        });
        const k = ids.indexOf(window.id);
        const up = input === Shortcut.FocusUp || input === Shortcut.FocusNext;
        const id = k < 0 ? null : ids[k + (up ? -1 : 1)] ?? null;
        const target = id !== null ? ctx.getWindowById(id) : null;
        if (target) {
          target.timestamp = new Date().getTime();
          if (c.tabbed) {
            c.activeTab = target.id;
            ctx.showNotification(this.tabCaption(ctx, c, target.id));
          }
          ctx.currentWindow = target;
        }
        return true;
      }
      // o modo "dwm" entrega ShiftLeft/…; o modo "focus" troca por SwapLeft/… (mover coluna / mover na coluna)
      case Shortcut.ShiftLeft:
      case Shortcut.ShiftRight:
      case Shortcut.SwapLeft:
      case Shortcut.SwapRight: {
        if (i < 0) return false;
        const toLeft = input === Shortcut.SwapLeft || input === Shortcut.ShiftLeft;
        const j = this.neighbourColumn(i, toLeft ? -1 : 1);
        if (j < 0) return true;
        [this.columns[i], this.columns[j]] = [this.columns[j], this.columns[i]];
        return true;
      }
      case Shortcut.ShiftUp:
      case Shortcut.ShiftDown:
      case Shortcut.SwapUp:
      case Shortcut.SwapDown:
        if (i < 0 || !window) return false;
        this.moveIdInColumn(this.columns[i], window.id, input === Shortcut.SwapUp || input === Shortcut.ShiftUp ? -1 : 1);
        return true;
      case Shortcut.GrowWidth:
      case Shortcut.ShrinkWidth: {
        if (i < 0) return false;
        const c = this.columns[i];
        const step = input === Shortcut.GrowWidth ? NIRI_WIDTH_STEP : -NIRI_WIDTH_STEP;
        c.width = Math.max(0.1, Math.min(1, Math.round((c.width + step) * 100) / 100));
        c.widthBeforeFull = null;
        return true;
      }
      case Shortcut.NiriCycleWidth: {
        if (i < 0) return false;
        const c = this.columns[i];
        const next = NIRI_PRESET_WIDTHS.find((w) => w > c.width + 0.01);
        c.width = next ?? NIRI_PRESET_WIDTHS[0];
        c.widthBeforeFull = null;
        return true;
      }
      case Shortcut.NiriMaximizeColumn:
        return window !== null && this.toggleFullWidth(window);
      case Shortcut.NiriCenterColumn:
        this.centerOnce = true;
        return true;
      case Shortcut.NiriConsumeLeft:
      case Shortcut.NiriConsumeRight:
        return window !== null && this.consumeOrExpel(ctx, window, input === Shortcut.NiriConsumeLeft ? -1 : 1);
      case Shortcut.NiriToggleTabbed:
        return window !== null && this.toggleTabbed(ctx, window);
      case Shortcut.GrowHeight:
      case Shortcut.ShrinkHeight:
        return window !== null && this.changeHeight(ctx, window, input === Shortcut.GrowHeight ? NIRI_HEIGHT_STEP : -NIRI_HEIGHT_STEP);
      case Shortcut.NiriResetHeight:
        return window !== null && this.resetHeights(ctx, window);
      case Shortcut.NiriFocusFirst:
        return this.focusColumn(ctx, this.shownColumns()[0]);
      case Shortcut.NiriFocusLast: {
        const shown = this.shownColumns();
        return this.focusColumn(ctx, shown[shown.length - 1]);
      }
      case Shortcut.NiriMoveToFirst:
      case Shortcut.NiriMoveToLast:
        return this.moveColumnToEnd(i, input === Shortcut.NiriMoveToFirst);
      case Shortcut.NiriExpandColumn:
        return this.expandColumn(i);
      case Shortcut.NiriPresetOff:
        return this.applyPreset(ctx, "off");
      case Shortcut.NiriPresetMasterLeft:
        return this.applyPreset(ctx, "master-left");
      case Shortcut.NiriPresetMasterRight:
        return this.applyPreset(ctx, "master-right");
      case Shortcut.NiriPresetColumns:
        return this.applyPreset(ctx, "columns");
      case Shortcut.NiriPresetMonocle:
        return this.applyPreset(ctx, "monocle");
      case Shortcut.NiriPresetCycle: {
        const k = NiriLayout.PRESETS.indexOf(this.preset);
        return this.applyPreset(ctx, NiriLayout.PRESETS[(k + 1) % NiriLayout.PRESETS.length]);
      }
      case Shortcut.NiriPresetPromote:
        return this.promote(ctx, window);
    }
    return false;
  }

  public toString(): string {
    return "NiriLayout(" + this.columns.length + " colunas)";
  }
}
