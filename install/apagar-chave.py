#!/usr/bin/env python3
"""apagar-chave.py arquivo grupo chave — tira a linha "chave=…" do [grupo] de um arquivo de config do KDE (chave "*":
o grupo inteiro).

No lugar do `kwriteconfig6 --delete`: quando o valor existe também nos padrões do sistema (kdedefaults do Look and
Feel, /etc/xdg), o --delete grava "chave[$d]", que ESCONDE o padrão (pegadinha já conhecida no projeto; voltou no
teste do desinstalar: kwinrc ficou com library[$d]/theme[$d]). Grupo que fica vazio sai também.
"""
import sys
from pathlib import Path

p, grupo, chave = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
if not p.is_file():
    sys.exit(0)
linhas = p.read_text(encoding="utf-8").splitlines()
saida, atual, blocos = [], None, []
for linha in linhas:
    if linha.startswith("[") and linha.endswith("]"):
        atual = linha[1:-1]
        blocos.append([linha])
        continue
    if not blocos:
        blocos.append([None])
    k = linha.split("=", 1)[0] if "=" in linha else None
    if atual == grupo and k is not None and (chave == "*" or k == chave or k == chave + "[$d]"):
        continue
    blocos[-1].append(linha)
for b in blocos:
    cab, corpo = b[0], b[1:]
    if cab is not None and cab[1:-1] == grupo and not any(l.strip() for l in corpo):
        continue
    if cab is not None:
        saida.append(cab)
    saida.extend(corpo)
while saida and not saida[-1].strip():
    saida.pop()
p.write_text("\n".join(saida) + ("\n" if saida else ""), encoding="utf-8")
