# Efeitos do KWin de terceiros distribuídos com o LowPan Shells

## kwin4_effect_tv (TV Effect, do Burn-My-Windows)
- Autores: Simon Schneegans, Martin Flöser, Vlad Zahorodnii — https://github.com/Schneegans/Burn-My-Windows
- Licença: GPL-3.0-or-later (cabeçalhos SPDX nos arquivos; texto em `kwin4_effect_tv/LICENSE`). Compatível com a
  GPL-3.0 do LowPan Shells.
- Origem: pacote KWin da KDE Store (Burn-My-Windows para KDE), copiado da instalação local em 2026-11-07.
- **Modificado pelo LowPan Shells** (GPL-3.0 §5a):
  1. 2026-11-05 — `contents/shaders/*.frag`: no KWin 6.8 os shaders viram GLSL ES 3.00 e as globais
     `vec2 uSize = vec2(textureWidth, textureHeight);` / `vec2 iTexCoord = …;` não compilam ("initializer … must be a
     constant expression"); trocadas por `#define uSize …` / `#define iTexCoord …`.
  2. 2026-11-07 — `contents/code/main.js`: `setupForcedRoles` esvaziado. Ele forçava blur e contraste do KWin na
     janela inteira durante a animação; como o shader só apaga os pixels da janela, o retângulo borrado da moldura
     aparecia antes de a janela abrir e depois de ela fechar.
- Instalar à mão: copiar `kwin4_effect_tv/` para `~/.local/share/kwin/effects/` e ligar em
  Configurações do sistema › Efeitos da área de trabalho (ou `kwriteconfig6 --file kwinrc --group Plugins
  --key kwin4_effect_tvEnabled true` + `qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect kwin4_effect_tv`).
