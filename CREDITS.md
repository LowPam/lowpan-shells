# Créditos e licenças · Credits and licenses

O LowPan Shells é distribuído sob a **GPL-3.0** (veja `LICENSE`). Ele reúne trabalho de outras pessoas, listado
abaixo com a licença de cada parte. Partes modificadas por nós dizem o que mudou.

LowPan Shells is distributed under the **GPL-3.0** (see `LICENSE`). It builds on other people's work, listed below
with each part's license. Parts we modified say what changed.

| Parte · Part | Origem · Source | Licença · License | No projeto · In this project |
|---|---|---|---|
| Shell (Quickshell) | [iNiR](https://github.com/snowarch/inir) — snowarch, a partir de/forked from [illogical-impulse](https://github.com/end-4/dots-hyprland) (end-4) | GPL-3.0 | `shell/` — adaptado para Plasma/KWin (ambiente LowPan), muitas mudanças · adapted to Plasma/KWin (LowPan environment), many changes |
| LowPan Tiling | [Krohnkite](https://github.com/anametologin/krohnkite) — Eon S. Jeon, Vjatcheslav V. Kolchkov e colaboradores · and contributors | MIT (`shell/kwin-tiling/LICENSE`) | `shell/kwin-tiling/` — fork com layout estilo Niri, abas, perfis por ambiente · fork with a Niri-style layout, tabs, per-environment profiles |
| Geometry Change (efeito KWin · KWin effect) | Peter Fajdiga | GPL-3.0 (`LICENSE` na pasta · in its folder) | `shell/kwin-tiling/third-party/kwin4_effect_geometry_change/` — sem mudanças · unchanged |
| TV Effect (efeito KWin · KWin effect) | [Burn-My-Windows](https://github.com/Schneegans/Burn-My-Windows) — Simon Schneegans, Martin Flöser, Vlad Zahorodnii | GPL-3.0-or-later | `shell/third-party/kwin-effects/kwin4_effect_tv/` — shaders para o KWin 6.8 e sem blur forçado (detalhes no `README.md` da pasta) · shaders fixed for KWin 6.8, no forced blur (details in the folder's `README.md`) |
| Achatar2 / Squash2 (minimizar · minimize) | Leo_sk (KDE Store) | GPL-2.0-or-later (`extras/GPL-2.0.txt`) | `extras/squash2-*` — sinais por janela do KWin 6 e minimizar até o ícone na dock (aviso no arquivo) · KWin 6 per-window signals, minimize to the dock icon (notice in the file) |
| Rounded Corners | [KDE-Rounded-Corners](https://github.com/matinlotfali/KDE-Rounded-Corners) — Matin Lotfaliei | GPL-3.0 | `extras/lowpan-kwin-rounded-corners/` — só a receita (PKGBUILD); o código é baixado do original e recebe nomes próprios para conviver com a versão do usuário · recipe only (PKGBUILD); the code is downloaded from upstream and renamed to coexist with the user's own copy |
| Magic Lamp (minimizar, opcional · minimize, optional) | [kwin-effects-yet-another-magic-lamp-reloaded](https://github.com/koryboc/kwin-effects-yet-another-magic-lamp-reloaded) — koryboc | GPL-2.0 (`extras/GPL-2.0.txt`) | `extras/magic-lamp-reloaded/` — receita + patch para funcionar sem o painel do Plasma · recipe + patch to work without the Plasma panel |
| Ícones · Icons `icons-lowpan` | baseado em · based on McMojave-circle ([vinceliuice](https://github.com/vinceliuice/McMojave-circle)) | GPL-3.0 (`system/icons/icons-lowpan/COPYING`) | `system/icons/icons-lowpan/` |
| Tema do Nautilus · Nautilus theme | variação do · variation of MacTahoeLiquidKde-Dark, de · from [macos-tahoe-liquid-kde](https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde) — lestercorderomurillo | GPL-3.0 | `system/nautilus/tema/` — só os nossos arquivos; o tema original é baixado do autor (commit fixo, v0.67.0) na instalação · our files only; the original theme is downloaded from its author (pinned commit, v0.67.0) at install time |
| Mascote e logo · Mascot and logo | criada para o LowPan Shells com IA (ChatGPT), personagem original · made for LowPan Shells with AI (ChatGPT), original character | GPL-3.0, como o projeto · like the project | `shell/assets/images/lowpan/` (`mascote.png` e o recorte redondo `logo.png`) |
| Tux (nos fones e na camiseta da mascote · on the mascot's headphones and shirt) | Larry Ewing (lewing@isc.tamu.edu), feito com o · made with The GIMP | uso livre com crédito · free to use with credit | `shell/assets/images/lowpan/mascote.png` |
| Fontes do LowPan · LowPan fonts | Roboto Flex, Readex Pro, Gabarito, Space Grotesk, Oxanium | SIL OFL 1.1 (`OFL.txt` em cada pasta · in each folder) | `system/fonts/` |
| Fontes da tela de login · Login screen fonts | Inter, Montserrat, Rubik (do iNiR · from iNiR) | SIL OFL 1.1 | `shell/assets/fonts/` |

Obrigado a todas essas pessoas. · Thanks to all of these people.
