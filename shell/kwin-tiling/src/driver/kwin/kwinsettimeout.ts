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

/** LowPan Tiling: pai dos Timer; o KWinDriver recebe do main.qml (api.root) */
var LOWPAN_ROOT: object | null = null;

/** LowPan Tiling: o workspace do KWin (o KWinDriver guarda ao nascer) — a faixa do Niri precisa de todas as saídas */
var LOWPAN_WS: any = null;

/**
 * LowPan Tiling: textos mostrados ao usuário — base em inglês, português quando o sistema estiver em português
 * (o mesmo critério do shell com o idioma em "auto"). Chave = o texto em inglês.
 */
const LP_PT: { [en: string]: string } = {
  "Tab %1 of %2": "Aba %1 de %2",
  "Can't make tabs: a window in this column doesn't accept the column's size":
    "Não dá para pôr em abas: uma janela desta coluna não aceita o tamanho da coluna",
  "Tabbed column": "Coluna em abas",
  "Stacked column": "Coluna empilhada",
  "This window doesn't fit in tabs": "Esta janela não cabe em abas",
  "Join as a tab": "Aderir à aba",
  "Join the stack": "Aderir à pilha",
  "Monocle stacked: a window doesn't accept the whole column": "Monocle empilhado: uma janela não aceita a coluna inteira",
  "This window doesn't accept the tabbed column's size": "Esta janela não aceita o tamanho da coluna em abas",
};
let LP_LANG_PT: boolean | null = null;
function lpTr(en: string, ...args: (string | number)[]): string {
  if (LP_LANG_PT === null) {
    try {
      LP_LANG_PT = String((Qt as any).locale().name).toLowerCase().startsWith("pt");
    } catch (e) {
      LP_LANG_PT = false;
    }
  }
  let text = LP_LANG_PT && LP_PT[en] ? LP_PT[en] : en;
  args.forEach((a, i) => (text = text.replace("%" + (i + 1), String(a))));
  return text;
}

/** retângulos de todas as saídas conectadas (coordenadas lógicas) */
function lpOutputRects(): Rect[] {
  const out: Rect[] = [];
  try {
    for (const s of LOWPAN_WS ? LOWPAN_WS.screens : []) {
      const g = s.geometry;
      out.push(new Rect(g.x, g.y, g.width, g.height));
    }
  } catch (e) {
    /* sem workspace ainda */
  }
  return out;
}

/** a saída vizinha na horizontal (-1 = à esquerda, 1 = à direita): a mais perto daquele lado, preferindo a que divide altura */
function lpNeighbourOutput(from: any, dir: -1 | 1): any {
  if (!LOWPAN_WS || !from) return null;
  const f = from.geometry;
  const fc = f.x + f.width / 2;
  let best: any = null;
  let bestScore = 0;
  for (const s of LOWPAN_WS.screens) {
    if (s === from || s.name === from.name) continue;
    const g = s.geometry;
    const c = g.x + g.width / 2;
    if ((c - fc) * dir <= 0) continue;
    const gapX = dir > 0 ? Math.max(0, g.x - (f.x + f.width)) : Math.max(0, f.x - (g.x + g.width));
    const overlap = Math.min(f.y + f.height, g.y + g.height) - Math.max(f.y, g.y);
    const score = gapX + (overlap > 0 ? 0 : 100000) + Math.abs(c - fc) / 1000;
    if (best === null || score < bestScore) {
      best = s;
      bestScore = score;
    }
  }
  return best;
}

/** a saída que o KWin dá a um ponto (Workspace::outputAt: a mais próxima; empate = a primeira) */
function lpNearestOutput(rects: Rect[], px: number, py: number): number {
  let best = -1;
  let bestD = 0;
  rects.forEach((g, i) => {
    const cx = Math.max(g.x, Math.min(px, g.maxX - 1));
    const cy = Math.max(g.y, Math.min(py, g.maxY - 1));
    const d = (cx - px) * (cx - px) + (cy - py) * (cy - py);
    if (best < 0 || d < bestD) {
      best = i;
      bestD = d;
    }
  });
  return best;
}

/** LowPan Tiling: registro de depuração; liga com kwinrc [Script-lowpan-tiling] lowpanDebug=true + reconfigure (sem login) */
function lpDebug(msg: string) {
  try {
    if (KWIN && KWIN.readConfig("lowpanDebug", false)) print("LOWPANDBG " + msg);
  } catch (e) {
    /* KWIN ainda não existe */
  }
}
/**
 * LowPan Tiling: interruptor sem login (kwinrc [Script-lowpan-tiling] lowpanActive, relido a cada chamada).
 * Desligar um script KWin não o para até o próximo login (§21.6), então o liga/desliga do shell
 * (system/lowpan-shells-tiling) usa esta chave: desligado, o motor não dispõe, não atende atalhos
 * nem intercepta o maximizar; só continua anotando as janelas que abrem e fecham.
 */
function lpActive(): boolean {
  try {
    return !KWIN || !!KWIN.readConfig("lowpanActive", true);
  } catch (e) {
    return true;
  }
}
/**
 * LowPan Tiling: espera (ms) antes de reorganizar ao fechar/minimizar, para a animação do KWin terminar antes de as
 * vizinhas andarem. kwinrc [Script-lowpan-tiling] lowpanCloseDelay / lowpanMinimizeDelay, relidas a cada evento;
 * gravadas pelo shell (scripts/kwin-animations.py tiling-delays) a partir do efeito escolhido.
 */
/** até quando nenhuma disposição roda (animação de fechar/minimizar em curso); só a espera agendada passa */
var LP_HOLD_UNTIL = 0;
function lpDelay(key: string): number {
  try {
    const v = Number(KWIN.readConfig(key, 0));
    return v > 0 ? Math.min(v, 3000) : 0;
  } catch (e) {
    return 0;
  }
}
function lpWin(w: WindowClass | null): string {
  if (!w) return "(nenhuma)";
  const c = (w.window as any).window;
  return '"' + String(c && c.caption ? c.caption : w.id).slice(0, 24) + '" estado=' + w.state;
}

class KWinTimerPool {
  public static readonly instance = new KWinTimerPool();

  public timers: QTimer[];
  public numTimers: number;

  constructor() {
    this.timers = [];
    this.numTimers = 0;
  }

  public setTimeout(func: () => void, timeout: number) {
    if (this.timers.length === 0) {
      this.numTimers++;
      LOG?.send(
        LogModules.setTimeout,
        "setTimeout/newTimer",
        `numTimers: ${this.numTimers}`
      );
    }

    const timer: QTimer =
      this.timers.pop() ||
      // LowPan Tiling: `scriptRoot` (id do main.qml) não existe aqui ("Missing parent object")
      Qt.createQmlObject("import QtQuick 2.0; Timer {}", LOWPAN_ROOT as object);

    const callback = () => {
      try {
        timer.triggered.disconnect(callback);
      } catch (e) {
        /* ignore */
      }
      try {
        func();
      } catch (e) {
        /* ignore */
      }
      this.timers.push(timer);
    };

    timer.interval = timeout;
    timer.repeat = false;
    timer.triggered.connect(callback);
    timer.start();
  }
}

function KWinSetTimeout(func: () => void, timeout: number) {
  KWinTimerPool.instance.setTimeout(func, timeout);
}
