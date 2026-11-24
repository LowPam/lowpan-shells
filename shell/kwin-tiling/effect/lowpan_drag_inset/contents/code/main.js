// LowPan Tiling — recuo ao arrastar (PLANEJAMENTO §21.13). Copyright (c) 2026 LowPan Shells. Licença MIT.
//
// Enquanto uma janela é MOVIDA pelo usuário, as outras janelas normais da mesma tela e área de trabalho encolhem
// `Inset` % em volta do centro; ao soltar voltam. Só visual (o compositor escala a imagem): nenhum app é
// redimensionado. A 1ª versão mudava o tamanho de verdade em 8 passos e saía picotada (cada app se redesenhava),
// e o Geometry Change desliga as animações dele durante o arrasto. kwinrc [Effect-lowpan_drag_inset] Inset, Duration.
"use strict";

const dragInset = {
    held: [],
    dragged: null,

    loadConfig() {
        this.inset = Math.max(0, Math.min(30, Number(effect.readConfig("Inset", 10)))) / 100;
        this.duration = animationTime(Number(effect.readConfig("Duration", 180)));
    },

    manage(w) {
        w.windowStartUserMovedResized.connect(this.start.bind(this));
        w.windowFinishUserMovedResized.connect(this.finish.bind(this));
    },

    start(dragged) {
        if (!dragged.move || this.inset <= 0 || this.dragged) return; // só mover (redimensionar não)
        this.dragged = dragged;
        const s = 1 - this.inset;
        const others = [];
        for (const w of effects.stackingOrder) {
            if (w === dragged || !w.normalWindow || w.minimized || !w.visible || !w.onCurrentDesktop) continue;
            if (w.screen !== dragged.screen) continue;
            others.push(w);
        }
        // barras de abas do shell (LowPan, 2026-11-08): encolhem junto com a janela de baixo, em volta do centro
        // DELA — encolhendo em volta do próprio centro abria um vão entre a barra e a janela
        const apps = others.filter((w) => !this.isShell(w));
        for (const w of others) {
            const below = this.isShell(w) ? this.windowBelowBar(w, apps) : null; // arrastando a aba ativa: segue as que ficam
            const fit = below ? this.fitBar(w, below, s) : null;
            const anims = fit
                ? [
                      { type: Effect.Scale, to: { value1: fit.sx, value2: fit.sy } },
                      { type: Effect.Translation, to: { value1: fit.dx, value2: fit.dy } },
                  ]
                : [{ type: Effect.Scale, to: { value1: s, value2: s } }];
            // keepAlive: false — o set() segura a janela viva até o cancel(); a barra de abas que o shell tira no
            // meio do arrasto (aba arrastada para fora) ficava desenhada, recuada, até soltar (bug 2026-11-15)
            const id = set({ window: w, duration: this.duration, curve: QEasingCurve.OutCubic, animations: anims, keepAlive: false });
            this.held.push({ w: w, id: id, fit: fit });
        }
    },

    /** janela fechada no meio do arrasto: solta a animação na hora (não deixa a imagem dela na tela) */
    closed(w) {
        const i = this.held.findIndex((h) => h.w === w);
        if (i < 0) return;
        try { cancel(this.held[i].id); } catch (e) { /* já foi */ }
        this.held.splice(i, 1);
    },

    /** barra encolhida: mesma largura da janela de baixo já encolhida (em volta do centro dela), altura × s,
     *  encostada no topo dela — vale para a aba ativa (encosta na barra) e para as de trás (12 px recolhidas) */
    fitBar(bar, below, s) {
        const b = this.rect(bar), g = this.rect(below);
        const gcx = g.x + g.width / 2, gcy = g.y + g.height / 2;
        const top = gcy - (g.height * s) / 2;
        return {
            sx: (g.width * s) / b.width,
            sy: s,
            dx: gcx - (b.x + b.width / 2),
            dy: top - (b.height * s) / 2 - (b.y + b.height / 2),
        };
    },

    /** a janela do efeito não tem frameGeometry: x/y/width/height (quadro) */
    rect(w) {
        return { x: Number(w.x), y: Number(w.y), width: Number(w.width), height: Number(w.height) };
    },

    isShell(w) {
        return String(w.windowClass).split(" ").includes("quickshell");
    },

    /** barra de abas = superfície do shell baixa e larga com uma janela começando logo embaixo (a ativa da coluna
     *  encosta nela; as de trás ficam 12 px recolhidas — vale a mais próxima) */
    windowBelowBar(bar, apps) {
        const b = this.rect(bar);
        if (b.height > 80 || b.width < 48) return null;
        let best = null, bestGap = 1e9;
        for (const w of apps) {
            const g = this.rect(w);
            const gap = g.y - (b.y + b.height);
            const overlap = Math.min(b.x + b.width, g.x + g.width) - Math.max(b.x, g.x);
            if (gap < -2 || gap > 30 || overlap < b.width * 0.5) continue;
            if (gap < bestGap) { best = w; bestGap = gap; }
        }
        return best;
    },

    finish(dragged) {
        if (dragged !== this.dragged) return;
        this.dragged = null;
        const s = 1 - this.inset;
        // primeiro solta todas (uma janela que sumiu no meio — ex.: a barra de abas que se esconde ao arrastar —
        // não pode interromper o laço e deixar as outras encolhidas para sempre)
        for (const h of this.held) {
            try { cancel(h.id); } catch (e) { /* janela já fechada */ }
        }
        for (const h of this.held) {
            try {
                if (h.w.deleted) continue;
                animate({
                    window: h.w,
                    duration: this.duration,
                    curve: QEasingCurve.OutCubic,
                    animations: h.fit
                        ? [
                              { type: Effect.Scale, from: { value1: h.fit.sx, value2: h.fit.sy }, to: { value1: 1, value2: 1 } },
                              { type: Effect.Translation, from: { value1: h.fit.dx, value2: h.fit.dy }, to: { value1: 0, value2: 0 } },
                          ]
                        : [{ type: Effect.Scale, from: { value1: s, value2: s }, to: { value1: 1, value2: 1 } }],
                });
            } catch (e) { /* janela já fechada */ }
        }
        this.held = [];
    },

    init() {
        this.loadConfig();
        effect.configChanged.connect(this.loadConfig.bind(this));
        effects.windowAdded.connect(this.manage.bind(this));
        effects.windowClosed.connect(this.closed.bind(this));
        effects.stackingOrder.forEach(this.manage.bind(this));
    },
};

dragInset.init();
