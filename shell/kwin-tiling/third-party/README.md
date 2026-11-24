# Terceiros distribuídos com o LowPan Tiling

## kwin4_effect_geometry_change (Geometry Change 1.5)
- Autor: Peter Fajdiga — https://github.com/peterfajdiga/kwin4_effect_geometry_change
- Licença: GPLv3 (texto em `kwin4_effect_geometry_change/LICENSE`; é a mesma GPL-3.0 do LowPan Shells). Vai como pacote
  separado, sem mistura com o código do motor (que segue MIT).
- Sem modificações. Copiado da instalação da KDE Store em 2026-11-06.
- Por quê: anima as mudanças de posição/tamanho feitas por scripts; sem ele as colunas do tiling "pulam".
  O liga/desliga do tiling (`system/lowpan-shells-tiling`) instala em `~/.local/share/kwin/effects/` se faltar
  e liga o efeito; ao desligar devolve o estado anterior (só remove se foi ele quem instalou).
