#!/usr/bin/env python3
"""LowPan Shells — guarda e devolve EXATAMENTE as chaves do efeito de abrir/fechar do kwinrc (PLANEJAMENTO §22.11).

  efeito-abrir.py guardar ARQUIVO   grava em ARQUIVO (JSON) o valor de cada [Plugins] <efeito>Enabled da categoria
                                    abrir/fechar — null quando a chave não existe
  efeito-abrir.py devolver ARQUIVO  grava de volta os valores e APAGA as chaves que não existiam

Por quê (8ª rodada da VM, 2026-11-24): o 40-kwin guardava só o nome do efeito ativo e a remoção devolvia com
`kwin-animations.py set open <efeito>`, que grava todas as chaves da categoria (scale=true, fade/glide=false) — o
comportamento voltava igual, mas o kwinrc ficava com chaves que antes não existiam.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

PROJETO = Path(__file__).resolve().parent.parent
KWINRC = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "kwinrc"
RESERVA = ["scale", "fade", "glide", "kwin4_effect_tv"]   # se o kwin-animations.py não responder


def chaves():
    ids = list(RESERVA)
    try:
        r = subprocess.run([sys.executable, "-I", str(PROJETO / "shell" / "scripts" / "kwin-animations.py"), "state"],
                           capture_output=True, text=True, timeout=20)
        for c in json.loads(r.stdout).get("categories", []):
            if c.get("id") == "open":
                ids += [str(e["id"]) for e in c.get("choices", []) if e.get("id")]
    except Exception:
        pass
    return sorted({i + "Enabled" for i in ids})


def ler_plugins():
    """valores crus do [Plugins] do arquivo do usuário (sem os padrões do sistema)"""
    valores, grupo = {}, None
    if KWINRC.is_file():
        for linha in KWINRC.read_text(encoding="utf-8").splitlines():
            if linha.startswith("[") and linha.endswith("]"):
                grupo = linha[1:-1]
            elif grupo == "Plugins" and "=" in linha:
                k, v = linha.split("=", 1)
                valores[k.strip()] = v.strip()
    return valores


def guardar(arq):
    atuais = ler_plugins()
    Path(arq).parent.mkdir(parents=True, exist_ok=True)
    Path(arq).write_text(json.dumps({k: atuais.get(k) for k in chaves()}, indent=1), encoding="utf-8")


def devolver(arq):
    dados = json.loads(Path(arq).read_text(encoding="utf-8"))
    for k, v in dados.items():
        if v is None:
            subprocess.run([sys.executable, "-I", str(PROJETO / "install" / "apagar-chave.py"), str(KWINRC), "Plugins", k],
                           check=True)
        else:
            subprocess.run(["kwriteconfig6", "--file", str(KWINRC), "--group", "Plugins", "--key", k, v], check=True)
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("guardar", "devolver"):
        sys.exit(__doc__)
    (guardar if sys.argv[1] == "guardar" else devolver)(sys.argv[2])
