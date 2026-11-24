/*
    This file is not part of the KDE project.

    SPDX-License-Identifier: GPL-2.0-or-later

    Squash2 by Leo_sk (KDE Store). Modified by LowPan Shells (2026-11-05 to 2026-11-13): KWin 6 per-window
    minimize signals (effects.windowMinimized was removed), and minimizing towards the app icon in the shell's dock
    (read from kwinrc [Effect-kwin4_effect_squash2] Targets, since there is no iconGeometry without the Plasma panel).
*/

"use strict";

var squashEffect = {
    duration: animationTime(350),
    targets: {},
    loadConfig: function () {
        squashEffect.duration = animationTime(350);
        // LowPan Shells (2026-11-13): ícone de cada app na dock do shell, gravado por ele no kwinrc
        // ("c:<classe>=x,y,l,a;p:<pid>=x,y,l,a;…"), já que sem o painel do Plasma não há iconGeometry.
        var map = {};
        var raw = String(effect.readConfig("Targets", "") || "");
        raw.split(";").forEach(function (item) {
            var eq = item.lastIndexOf("=");
            if (eq <= 0) {
                return;
            }
            var n = item.slice(eq + 1).split(",").map(Number);
            if (n.length === 4 && n[2] > 0 && n[3] > 0 && n.every(isFinite)) {
                map[item.slice(0, eq)] = { x: n[0], y: n[1], width: n[2], height: n[3] };
            }
        });
        squashEffect.targets = map;
    },
    slotWindowMinimized: function (window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }

        // If the window doesn't have an icon in the task manager,
        // don't animate it.
        var iconRect = squashEffect.iconRect(window);
        if (!iconRect) {
            return;
        }

        if (window.unminimizeAnimation) {
            if (redirect(window.unminimizeAnimation, Effect.Backward)) {
                return;
            }
            cancel(window.unminimizeAnimation);
            delete window.unminimizeAnimation;
        }

        if (window.minimizeAnimation) {
            if (redirect(window.minimizeAnimation, Effect.Forward)) {
                return;
            }
            cancel(window.minimizeAnimation);
        }

        var windowRect = window.geometry;

        window.minimizeAnimation = animate({
            window: window,
            curve: QEasingCurve.OutExpo,
            duration: squashEffect.duration+50,
            animations: [
                {
                    type: Effect.Size,
                    from: {
                        value1: windowRect.width,
                        value2: windowRect.height
                    },
                    to: {
                        value1: iconRect.width,
                        value2: iconRect.height
                    }
                },
                {
                    type: Effect.Translation,
                    from: {
                        value1: 0.0,
                        value2: 0.0
                    },
                    to: {
                        value1: iconRect.x - windowRect.x -
                            (windowRect.width - iconRect.width) / 2,
                        value2: iconRect.y - windowRect.y -
                            (windowRect.height - iconRect.height) / 2,
                    }
                },
                {
                    type: Effect.Opacity,
                    from: 1.0,
                    to: 1.0
                }
            ]
        });
    },
    slotWindowUnminimized: function (window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }

        // If the window doesn't have an icon in the task manager,
        // don't animate it.
        var iconRect = squashEffect.iconRect(window);
        if (!iconRect) {
            return;
        }

        if (window.minimizeAnimation) {
            if (redirect(window.minimizeAnimation, Effect.Backward)) {
                return;
            }
            cancel(window.minimizeAnimation);
            delete window.minimizeAnimation;
        }

        if (window.unminimizeAnimation) {
            if (redirect(window.unminimizeAnimation, Effect.Forward)) {
                return;
            }
            cancel(window.unminimizeAnimation);
        }

        var windowRect = window.geometry;

        window.unminimizeAnimation = animate({
            window: window,
            curve: QEasingCurve.OutExpo,
            duration: squashEffect.duration,
            animations: [
                {
                    type: Effect.Size,
                    from: {
                        value1: iconRect.width,
                        value2: iconRect.height
                    },
                    to: {
                        value1: windowRect.width,
                        value2: windowRect.height
                    }
                },
                {
                    type: Effect.Translation,
                    from: {
                        value1: iconRect.x - windowRect.x -
                            (windowRect.width - iconRect.width) / 2,
                        value2: iconRect.y - windowRect.y -
                            (windowRect.height - iconRect.height) / 2,
                    },
                    to: {
                        value1: 0.0,
                        value2: 0.0
                    }
                },
                {
                    type: Effect.Opacity,
                    from: 1.0,
                    to: 1.0
                }
            ]
        });
    },
    // LowPan Shells: sem o painel do Plasma não há iconGeometry; vai para o ícone do app na dock do shell
    // (pela classe da janela, depois pelo PID) e, sem ele, para o centro da borda de baixo da tela.
    iconRect: function (window) {
        var r = window.iconGeometry;
        if (r.width > 0 && r.height > 0) {
            return r;
        }
        var parts = String(window.windowClass || "").toLowerCase().split(" ").reverse();
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] && squashEffect.targets["c:" + parts[i]]) {
                return squashEffect.targets["c:" + parts[i]];
            }
        }
        if (window.pid > 0 && squashEffect.targets["p:" + window.pid]) {
            return squashEffect.targets["p:" + window.pid];
        }
        var scr = window.screen ? window.screen.geometry : null;
        if (!scr) {
            return null;
        }
        var size = 48;
        return { x: scr.x + (scr.width - size) / 2, y: scr.y + scr.height - size - 6,
                 width: size, height: size };
    },
    slotWindowAdded: function (window) {
        window.minimizedChanged.connect(() => {
            if (window.minimized) {
                squashEffect.slotWindowMinimized(window);
            } else {
                squashEffect.slotWindowUnminimized(window);
            }
        });
    },
    init: function () {
        squashEffect.loadConfig();
        effect.configChanged.connect(squashEffect.loadConfig);
        // LowPan: KWin 6 tirou effects.windowMinimized/windowUnminimized; agora é por janela.
        effects.windowAdded.connect(squashEffect.slotWindowAdded);
        for (const window of effects.stackingOrder) {
            squashEffect.slotWindowAdded(window);
        }
    }
};

squashEffect.init();
