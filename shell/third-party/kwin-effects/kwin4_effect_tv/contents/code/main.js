// SPDX-FileCopyrightText: Vlad Zahorodnii <vlad.zahorodnii@kde.org>, Martin Flöser
// <mgraesslin@kde.org>, Simon Schneegans <code@simonschneegans.de>
// SPDX-License-Identifier: GPL-3.0-or-later

'use strict';

const blacklist = [
  // The logout screen has to be animated only by the logout effect.
  'ksmserver ksmserver', 'ksmserver-logout-greeter ksmserver-logout-greeter',

  // KDE Plasma splash screen has to be animated only by the login effect.
  'ksplashqml ksplashqml',

  // All the tooltips of IntelliJ IDEs use the same window class as their main window.
  // This results in many awkward animations, so we have to blacklist them all.
  // See https://github.com/Schneegans/Burn-My-Windows/issues/284 for details.
  'jetbrains-studio jetbrains-studio', 'jetbrains-aqua jetbrains-aqua',
  'jetbrains-clion jetbrains-clion', 'jetbrains-datagrip jetbrains-datagrip',
  'jetbrains-dataspell jetbrains-dataspell', 'jetbrains-goland jetbrains-goland',
  'jetbrains-idea jetbrains-idea', 'jetbrains-idea-ce jetbrains-idea-ce',
  'jetbrains-phpstorm jetbrains-phpstorm', 'jetbrains-pycharm jetbrains-pycharm',
  'jetbrains-pycharm-ce jetbrains-pycharm-ce', 'jetbrains-rider jetbrains-rider',
  'jetbrains-rubymine jetbrains-rubymine', 'jetbrains-webstorm jetbrains-webstorm'
];

class BurnMyWindowsTvEffect {
  constructor() {
    // LowPan (2026-11-26): janelas com animação TV em curso (abertura ou fechamento). Contorno do bug 528239 do
    // KWin 6.8.3: a foto da janela que o KWin tira no animate() sai VAZIA quando este efeito já está animando outra
    // janela (CrossFadeEffect::drawWindow pula o desenho com crossFadeProgress 0) — a janela ficava invisível a
    // animação inteira (Audacity: a janela de carregamento ainda anima quando a principal abre; dois kitty seguidos).
    // Corrigido no KWin 6.8.4 (commit 7b9bdf3fb3); até lá, com outra animação em curso a janela entra/sai sem efeito.
    // Ao atualizar o KWin para >= 6.8.4: apagar this.emAnimacao e o teste em slotWindowAdded/slotWindowClosed.
    this.emAnimacao = new Set();
    effect.configChanged.connect(this.loadConfig.bind(this));
    effect.animationEnded.connect(this.cleanupForcedRoles.bind(this));
    effects.windowAdded.connect(this.slotWindowAdded.bind(this));
    effects.windowClosed.connect(this.slotWindowClosed.bind(this));
    effects.windowDataChanged.connect(this.slotWindowDataChanged.bind(this));

    this.shader = effect.addFragmentShader(Effect.MapTexture, 'tv.frag');

    this.loadConfig();
  }

  // A small helper which can be used to read a hex color string (e.g. #ff3244) from the
  // settings. This method will return an array of four floating point values
  // [r, g, b, a]. If the settings key only refers to an rgb value, the alpha component
  // will be set to 1.0.
  readRGBAConfig(key) {
    const color = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})?([a-f\d]{2})?$/i
                    .exec(effect.readConfig(key, '#ffffff'))
                    .slice(1)
                    .filter(x => x !== undefined)
                    .map(x => parseInt(x, 16) / 255);
    return color.length == 3 ? [color[0], color[1], color[2], 1.0] :
                               [color[1], color[2], color[3], color[0]];
  }

  // A small helper which can be used to read a hex color string (e.g. #ff3244) from the
  // settings. This method will return an array of three floating point values [r, g, b]
  // regardless of whether the settings key actually refers to an argb hex string.
  readRGBConfig(key) {
    const color = this.readRGBAConfig(key);
    color.pop();
    return color;
  }

  // This is called when the effect is loaded and whenever the settings of the effect
  // are changed by the user.
  loadConfig() {
    this.duration = animationTime(effect.readConfig('Duration', 1000));

    // SPDX-FileCopyrightText: Simon Schneegans <code.de>
    // SPDX-License-Identifier: GPL-3.0-or-later

    // This part is automatically included in the effect's source during the build
    // process. The code below is called whenever the user changes something in the
    // configuration of the effect.

    effect.setUniform(this.shader, 'uColor', this.readRGBAConfig('Color'));
  }

  static shouldAnimateWindow(window) {

    // We don't want to animate most of plasmashell's windows, yet, some
    // of them we want to, for example, Task Manager Settings window.
    // The problem is that all those window share single window class.
    // So, the only way to decide whether a window should be animated is
    // to use a heuristic: if a window has decoration, then it's most
    // likely a dialog or a settings window so we have to animate it.
    if (window.windowClass == 'plasmashell plasmashell' ||
        window.windowClass == 'plasmashell org.kde.plasmashell') {
      return window.hasDecoration;
    }

    // This is primarily to avoid animating the AltTab popup.
    // See https://github.com/Schneegans/Burn-My-Windows/issues/384 for details.
    if (!window.hasDecoration && window.onAllDesktops) {
      return false
    }

    if (blacklist.indexOf(window.windowClass) != -1) {
      return false;
    }

    if (window.hasDecoration) {
      return true;
    }

    // Don't animate combobox popups, tooltips, popup menus, etc.
    if (window.popupWindow) {
      return false;
    }

    // Dont't animate the outline and the screenlocker as it looks bad.
    if (window.lockScreen || window.outline) {
      return false;
    }

    // Override-redirect windows are usually used for user interface
    // concepts that are not expected to be animated by this effect.
    if (!window.managed) {
      return false;
    }

    return window.normalWindow || window.dialog;
  }

  // LowPan: o shader só apaga os pixels da janela; com blur/contraste forçados o KWin
  // desenhava o retângulo borrado da moldura inteira antes de abrir e depois de fechar.
  setupForcedRoles(window) {
  }

  cleanupForcedRoles(window) {
    this.emAnimacao.delete(window);
    window.setData(Effect.WindowForceBackgroundContrastRole, null);
    window.setData(Effect.WindowForceBlurRole, null);
  }

  slotWindowAdded(window) {
    if (effects.hasActiveFullScreenEffect) {
      return;
    }
    if (!BurnMyWindowsTvEffect.shouldAnimateWindow(window)) {
      return;
    }
    if (!window.visible) {
      return;
    }
    if (effect.isGrabbed(window, Effect.WindowAddedGrabRole)) {
      return;
    }
    if (this.emAnimacao.size > 0) {
      return;
    }
    this.setupForcedRoles(window);

    const full = window.fullScreen ? 1.0 : 0.0;



    // LowPan (2026-11-26): direção e tela cheia vão em cada animação (valor constante), aplicados janela a janela
    // ao desenhar. Antes eram um setUniform no shader compartilhado: uma janela fechando enquanto outra abria (a
    // tela de abertura do Audacity sumindo junto da janela principal) trocava a direção e a abertura era desenhada
    // como fechamento (faixa cinza encolhendo até um ponto) e a janela só aparecia no fim.
    this.emAnimacao.add(window);
    window.bmwInAnimation = animate({
      window: window,
      curve: QEasingCurve.Linear,
      duration: this.duration,
      animations: [{
        type: Effect.ShaderUniform,
        fragmentShader: this.shader,
        uniform: 'uProgress',
        from: 0.0,
        to: 1.0
      }, {
        type: Effect.ShaderUniform,
        fragmentShader: this.shader,
        uniform: 'uForOpening',
        from: 1.0,
        to: 1.0
      }, {
        type: Effect.ShaderUniform,
        fragmentShader: this.shader,
        uniform: 'uIsFullscreen',
        from: full,
        to: full
      }]
    });
  }

  slotWindowClosed(window) {
    // LowPan (2026-11-26): a abertura em curso é cancelada antes de qualquer saída antecipada (antes, uma janela
    // fechada no meio da abertura sem animação de fechamento deixava a abertura rodando sobre a janela destruída).
    if (window.bmwInAnimation) {
      cancel(window.bmwInAnimation);
      delete window.bmwInAnimation;
      this.cleanupForcedRoles(window);
    }
    if (effects.hasActiveFullScreenEffect) {
      return;
    }
    if (!BurnMyWindowsTvEffect.shouldAnimateWindow(window)) {
      return;
    }
    if (!window.visible || window.skipsCloseAnimation) {
      return;
    }
    if (effect.isGrabbed(window, Effect.WindowClosedGrabRole)) {
      return;
    }
    if (this.emAnimacao.size > 0) {
      return;
    }
    this.setupForcedRoles(window);

    const full = window.fullScreen ? 1.0 : 0.0;



    // LowPan (2026-11-26): direção e tela cheia vão em cada animação (valor constante), aplicados janela a janela
    // ao desenhar. Antes eram um setUniform no shader compartilhado: uma janela fechando enquanto outra abria (a
    // tela de abertura do Audacity sumindo junto da janela principal) trocava a direção e a abertura era desenhada
    // como fechamento (faixa cinza encolhendo até um ponto) e a janela só aparecia no fim.
    this.emAnimacao.add(window);
    window.bmwOutAnimation = animate({
      window: window,
      curve: QEasingCurve.Linear,
      duration: this.duration,
      animations: [{
        type: Effect.ShaderUniform,
        fragmentShader: this.shader,
        uniform: 'uProgress',
        from: 0.0,
        to: 1.0
      }, {
        type: Effect.ShaderUniform,
        fragmentShader: this.shader,
        uniform: 'uForOpening',
        from: 0.0,
        to: 0.0
      }, {
        type: Effect.ShaderUniform,
        fragmentShader: this.shader,
        uniform: 'uIsFullscreen',
        from: full,
        to: full
      }]
    });
  }

  slotWindowDataChanged(window, role) {
    if (role == Effect.WindowAddedGrabRole) {
      if (window.bmwInAnimation && effect.isGrabbed(window, role)) {
        cancel(window.bmwInAnimation);
        delete window.bmwInAnimation;
        this.cleanupForcedRoles(window);
      }
    } else if (role == Effect.WindowClosedGrabRole) {
      if (window.bmwOutAnimation && effect.isGrabbed(window, role)) {
        cancel(window.bmwOutAnimation);
        delete window.bmwOutAnimation;
        this.cleanupForcedRoles(window);
      }
    }
  }
}

new BurnMyWindowsTvEffect();
