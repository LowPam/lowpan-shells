# org.lowpan.shells — tela de bloqueio do LowPan

No Plasma 6 a tela de bloqueio (`kscreenlocker_greet`) vem da pasta `lockscreen/` do **pacote de shell** indicado por
`PLASMA_DEFAULT_SHELL` no ambiente do KWin. Este pacote tem só essa pasta, no visual da tela de login do LowPan
(`greeter/Tela.qml`): fundo desfocado, relógio com os dois-pontos laranja, avatar redondo, senha em pílula e botões
redondos.

- `contents/lockscreen/`: `LockScreenUi.qml` reescrito sobre o do `org.kde.plasma.desktop` (Plasma 6.8,
  GPL-2.0-or-later; a lógica de autenticação é a do KDE). `LockScreen.qml`, `LockOsd.qml`, `PasswordSync.qml`,
  `config.qml`/`config.xml` e `qmldir` são cópias do KDE sem mudanças (autores nos cabeçalhos).
- `contents/fonts` → `shell/assets/fonts` (Inter e Rubik, SIL OFL 1.1).
- Instalação (`install/modulos/80-login.sh`): link em `~/.local/share/plasma/shells/org.lowpan.shells` e o drop-in
  `system/plasma-kwin_wayland-lowpan-bloqueio.conf` em `~/.config/systemd/user/plasma-kwin_wayland.service.d/`.
  Vale no próximo login.
- Testar sem bloquear: `/usr/lib/kscreenlocker_greet --testing --shell org.lowpan.shells` (se o QML quebrar, aparece o
  bloqueio reserva azul do KDE; os erros saem no `journalctl --user`).

---

**English:** LowPan lock screen (Plasma 6 shell package with only `lockscreen/`), styled after the LowPan login
screen. Enabled by `PLASMA_DEFAULT_SHELL=org.lowpan.shells` in the KWin service environment.
