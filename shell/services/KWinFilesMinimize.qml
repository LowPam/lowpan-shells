pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * LowPan Shells (2026-11-13): dois cliques no Nautilus num arquivo/app que abre OUTRO programa → o Nautilus
 * minimiza. Pastas abrem dentro dele (não criam janela de outro app), então nada acontece.
 * Como: a cada janela nova de outro app, compara o cgroup do processo dela com o do Nautilus (/proc/<pid>/cgroup).
 * O GLib abre os programas por um processo intermediário que sai logo, então o programa vira filho do systemd e a
 * cadeia de pais NÃO chega ao Nautilus (testado) — mas ele fica no cgroup de quem o abriu; apps da dock ganham um
 * escopo próprio (run-p….scope). Mesmo cgroup = foi o Nautilus → minimiza a janela dele usada por último. Reserva:
 * a cadeia de pais passa pelo Nautilus, ou pelo xdg-desktop-portal
 * (o GTK pode abrir arquivos pelo portal OpenURI), vale só se o Nautilus era a janela focada logo antes.
 * Apps abertos pela dock/lançador não são filhos do Nautilus. Não pega app já aberto que só ganha uma janela nova
 * (o processo não é filho dele) nem app aberto por ativação D-Bus. Só no KWin; opção lowpan.filesMinimizeOnOpen.
 * Só com o Nautilus flutuando (pedido do usuário): tiling desligado, ou a janela dele sem keepBelow e sem estar
 * maximizada. O LowPan Tiling põe as janelas lado a lado na camada de baixo (tiledWindowsLayer = 0, padrão →
 * keepBelow) e as flutuantes na normal; o estado vem do KWin na hora (getWindowInfo), então vale também para o
 * flutuar alternado pelo atalho. (A 1ª versão usava a lista "sempre flutuar", que não enxerga o atalho.)
 * Cada decisão vai para o journal com o prefixo "lowpan-files:".
 */
Singleton {
    id: root

    readonly property bool enabled: CompositorService.isKWin && (Config.options?.lowpan?.filesMinimizeOnOpen ?? true)
    property var known: null          // ids das janelas já vistas (null = ainda não carregou a lista inicial)
    property int lastNautilusId: -1   // janela do Nautilus focada por último
    property bool focusWasNautilus: false // a janela focada no retrato anterior era do Nautilus
    property var queue: []            // [{ pid, nautilusPids }] esperando o teste de parentesco

    function isNautilus(w: var): bool {
        const cls = String(w?.resource_class ?? "").toLowerCase()
        const app = String(w?.app_id ?? "").toLowerCase()
        return cls === "org.gnome.nautilus" || app === "org.gnome.nautilus" || cls === "nautilus"
    }


    function update(): void {
        const windows = NiriService.windows ?? []
        const wasNautilus = root.focusWasNautilus
        const focused = windows.find(w => w.is_focused)
        root.focusWasNautilus = !!focused && root.isNautilus(focused)
        if (root.focusWasNautilus) root.lastNautilusId = focused.id
        const ids = {}
        for (const w of windows) ids[w.id] = true
        if (root.known === null) {
            root.known = ids
            return
        }
        const fresh = windows.filter(w => !root.known[w.id])
        root.known = ids
        if (!root.enabled || fresh.length === 0) return
        const nautilusPids = [...new Set(windows.filter(w => root.isNautilus(w) && w.pid > 0).map(w => w.pid))]
        if (nautilusPids.length === 0) return
        for (const w of fresh) {
            if (root.isNautilus(w) || !(w.pid > 0) || nautilusPids.includes(w.pid)) continue
            const target = windows.find(x => x.id === root.lastNautilusId && root.isNautilus(x))
                ?? windows.find(x => root.isNautilus(x) && !x.is_minimized)
            console.info(`lowpan-files: janela nova ${w.app_id} (pid ${w.pid}); Nautilus ${nautilusPids.join(",")}, `
                + `focado antes: ${wasNautilus}`)
            root.queue = root.queue.concat([{ pid: w.pid, nautilusPids: nautilusPids, wasNautilus: wasNautilus,
                uuid: String(target?.kwin_uuid ?? "") }])
        }
        root.next()
    }

    function next(): void {
        if (check.running || root.queue.length === 0) return
        const job = root.queue[0]
        root.queue = root.queue.slice(1)
        // 1ª linha: "N <pid do Nautilus>" (mesmo cgroup ou pai), "P <pid>" (portal) ou "-".
        // 2ª linha: estado da janela do Nautilus no KWin: "<keepBelow> <maximizeHorizontal> <maximizeVertical>".
        check.command = ["sh", "-c",
            'pp() { sed -n "s/^PPid:[[:space:]]*//p" "/proc/$1/status" 2>/dev/null; }; '
            + 'cg() { cat "/proc/$1/cgroup" 2>/dev/null; }; '
            + 'quem() { c=$(cg "$1"); '
            + '  for t in $2; do [ -n "$c" ] && [ "$c" = "$(cg "$t")" ] && { echo "N $t"; return; }; done; '
            + '  p=$(pp "$1"); n=0; '
            + '  while [ -n "$p" ] && [ "$p" -gt 1 ] && [ $n -lt 32 ]; do '
            + '    for t in $2; do [ "$p" = "$t" ] && { echo "N $p"; return; }; done; '
            + '    case "$(cat "/proc/$p/comm" 2>/dev/null)" in xdg-desktop-por*) echo "P $p"; return;; esac; '
            + '    p=$(pp "$p"); n=$((n + 1)); '
            + '  done; echo "-"; }; '
            + 'quem "$1" "$2"; '
            + 'busctl --user call org.kde.KWin /KWin org.kde.KWin getWindowInfo s "$3" 2>/dev/null | tr \'"\' "\\n" '
            + '| awk \'/^(keepBelow|maximizeHorizontal|maximizeVertical)$/ { getline; printf "%s ", $2 }\'; echo',
            "sh", String(job.pid), job.nautilusPids.join(" "), job.uuid]
        root.current = job
        check.running = true
    }
    property var current: null

    function minimizeNautilus(pid: int): void {
        const windows = NiriService.windows ?? []
        let target = windows.find(w => w.id === root.lastNautilusId && w.pid === pid && !w.is_minimized)
        if (!target) target = windows.find(w => root.isNautilus(w) && w.pid === pid && !w.is_minimized)
        if (target) NiriService.kwinMinimizeWindow(target.id)
    }

    Connections {
        target: NiriService
        function onWindowsChanged(): void { root.update() }
    }

    Process {
        id: check
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(this.text).trim().split("\n")
                const out = String(lines[0] ?? "").trim().split(" ")
                const state = String(lines[1] ?? "").trim().split(" ") // keepBelow maxH maxV
                const job = root.current
                const viaPortal = out[0] === "P"
                const tiling = Config.options?.lowpan?.tiling ?? false
                const floating = !tiling || (state[0] === "false" && !(state[1] === "1" && state[2] === "1"))
                const ok = (out[0] === "N" || (viaPortal && job?.wasNautilus)) && floating
                console.info(`lowpan-files: pid ${job?.pid} → ${out.join(" ")} (N = aberto pelo Nautilus, P = portal); `
                    + `Nautilus keepBelow/maxH/maxV: ${state.join(" ")}, tiling: ${tiling}, flutuando: ${floating}; `
                    + (ok ? "minimiza" : "não minimiza"))
                if (!ok) return
                root.minimizeNautilus(out[0] === "N" ? parseInt(out[1]) : (job?.nautilusPids?.[0] ?? -1))
            }
        }
        onExited: root.next()
    }

    Component.onCompleted: {
        console.info(`lowpan-files: serviço ativo (KWin: ${CompositorService.isKWin})`)
        root.update()
    }
}
