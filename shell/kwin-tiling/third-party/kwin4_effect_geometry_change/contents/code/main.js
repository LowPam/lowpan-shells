"use strict";

class GeometryChangeEffect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.restoreForceBlurState.bind(this));

        const manageFn = this.manage.bind(this);
        effects.windowAdded.connect(manageFn);
        effects.stackingOrder.forEach(manageFn);

        this.loadConfig();
    }

    loadConfig() {
        const duration = effect.readConfig("Duration", 250);
        this.duration = animationTime(duration);
        this.excludedWindowClasses = effect.readConfig("ExcludedWindowClasses", "krunner,yakuake").split(",");
        // LowPan (2026-11-26): carência das janelas novas. No Wayland o tiling só encaixa a janela depois do 1º quadro
        // (dezenas de ms, não os 10 ms do original): o encaixe era animado como um deslizar por cima da abertura TV
        // (visto no Audacity, só sem gravar a tela — gravando, o ritmo muda e a janela já estava no lugar).
        this.newWindowGraceMs = effect.readConfig("NewWindowGraceMs", 500);
    }

    manage(window) {
        window.geometryChangeData = {
            createdTime: Date.now(),
            animationInstances: 0,
            maximizedStateAboutToChange: false,
        };
        window.windowFrameGeometryChanged.connect(
            this.onWindowFrameGeometryChanged.bind(this),
        );
        window.windowMaximizedStateAboutToChange.connect(
            this.onWindowMaximizedStateAboutToChange.bind(this),
        );
        window.windowStartUserMovedResized.connect(
            this.onWindowStartUserMovedResized.bind(this),
        );
        window.windowFinishUserMovedResized.connect(
            this.onWindowFinishUserMovedResized.bind(this),
        );
    }

    restoreForceBlurState(window) {
        window.geometryChangeData.animationInstances--;
        if (window.geometryChangeData.animationInstances === 0) {
            window.setData(Effect.WindowForceBlurRole, null);
        }
    }

    isWindowClassExluded(windowClass) {
        return windowClass.split(" ").some(part => this.excludedWindowClasses.includes(part));
    }

    onWindowFrameGeometryChanged(window, oldGeometry) {
        const windowTypeSupportsAnimation = window.normalWindow || window.dialog || window.modal;
        const isUserMoveResize = window.move || window.resize || this.userResizing;
        const maximizationChange = window.geometryChangeData.maximizedStateAboutToChange;
        window.geometryChangeData.maximizedStateAboutToChange = false;
        if (
            !window.managed ||
            !window.visible ||
            !window.onCurrentDesktop ||
            window.minimized ||
            !windowTypeSupportsAnimation ||
            isUserMoveResize && !maximizationChange ||
            this.isWindowClassExluded(window.windowClass)
        ) {
            return;
        }

        const windowAgeMs = Date.now() - window.geometryChangeData.createdTime;
        if (windowAgeMs < 0) {
            // May happen after time zone change. Let's fix the created time, so it's not in the future.
            window.geometryChangeData.createdTime = Date.now();
        } else if(windowAgeMs < this.newWindowGraceMs) {
            // Some windows are moved or resized immediately after being created. We don't want to animate that.
            // (LowPan: era 10 ms; o encaixe do tiling numa janela nova fica para o efeito de abrir.)
            return;
        }

        const newGeometry = window.geometry;
        const xDelta = newGeometry.x - oldGeometry.x;
        const yDelta = newGeometry.y - oldGeometry.y;
        const widthDelta = newGeometry.width - oldGeometry.width;
        const heightDelta = newGeometry.height - oldGeometry.height;
        const widthRatio = oldGeometry.width / newGeometry.width;
        const heightRatio = oldGeometry.height / newGeometry.height;

        const animations = [
            {
                type: Effect.Translation,
                from: {
                    value1: -xDelta - widthDelta / 2,
                    value2: -yDelta - heightDelta / 2,
                },
                to: {
                    value1: 0,
                    value2: 0,
                },
            },
            {
                type: Effect.Scale,
                from: {
                    value1: widthRatio,
                    value2: heightRatio,
                },
                to: {
                    value1: 1,
                    value2: 1,
                },
            },
        ];

        window.geometryChangeData.animationInstances += animations.length;
        window.setData(Effect.WindowForceBlurRole, true);

        animate({
            window: window,
            duration: this.duration,
            curve: QEasingCurve.OutExpo,
            animations: animations,
        });
    }

    onWindowMaximizedStateAboutToChange(window, horizontal, vertical) {
        window.geometryChangeData.maximizedStateAboutToChange = true;
    }

    onWindowStartUserMovedResized(window) {
        this.userResizing = true;
    }

    onWindowFinishUserMovedResized(window) {
        this.userResizing = false;
    }
}

new GeometryChangeEffect();
