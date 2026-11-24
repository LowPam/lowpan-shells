// LowPan Shells — ponte KWin.
// Publica janelas / áreas de trabalho para o helper (org.lowpan.Shells.Bridge) e executa os comandos
// que ele devolve por long-poll. Carregado e descarregado pelo helper; não precisa ficar habilitado no kwinrc.

const SERVICE = "org.lowpan.Shells.Bridge";
const PATH = "/Bridge";
const IFACE = "org.lowpan.Shells.Bridge";

function log(msg) { console.info("lowpan-bridge: " + msg); }

function isTask(w) {
    return w && w.normalWindow && !w.skipTaskbar && !w.deleted;
}

function appIdOf(w) {
    return String(w.desktopFileName || w.resourceClass || w.resourceName || "");
}

function serialize(w) {
    return {
        id: String(w.internalId),
        caption: String(w.caption || ""),
        appId: appIdOf(w),
        resourceClass: String(w.resourceClass || ""),
        pid: w.pid,
        minimized: !!w.minimized,
        active: workspace.activeWindow === w,
        fullScreen: !!w.fullScreen,
        demandsAttention: !!w.demandsAttention,
        onAllDesktops: !!w.onAllDesktops,
        desktops: (w.desktops || []).map(d => String(d.id)),
        output: w.output ? String(w.output.name) : "",
        geometry: { x: Math.round(w.frameGeometry.x), y: Math.round(w.frameGeometry.y),
                    width: Math.round(w.frameGeometry.width), height: Math.round(w.frameGeometry.height) },
        maximized: w.maximizeMode === 3,
        keepAbove: !!w.keepAbove,
    };
}

function snapshot(reason) {
    const windows = [];
    for (const w of workspace.stackingOrder) if (isTask(w)) windows.push(serialize(w));
    const desktops = (workspace.desktops || []).map(d => ({ id: String(d.id), name: String(d.name), x11: d.x11DesktopNumber }));
    return {
        type: "snapshot",
        reason: reason,
        windows: windows,
        activeId: workspace.activeWindow ? String(workspace.activeWindow.internalId) : "",
        desktops: desktops,
        currentDesktop: workspace.currentDesktop ? String(workspace.currentDesktop.id) : "",
        showingDesktop: !!workspace.showingDesktop,
    };
}

function send(reason) {
    kick();
    callDBus(SERVICE, PATH, IFACE, "Event", JSON.stringify(snapshot(reason)));
}

// LowPan Shells: área útil por tela (sem zonas exclusivas), para o StrutManager do helper
function sendAreas() {
    const areas = {};
    for (const o of workspace.screens || []) {
        const r = workspace.clientArea(KWin.MaximizeArea, o, workspace.currentDesktop);
        areas[String(o.name)] = { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
    }
    callDBus(SERVICE, PATH, IFACE, "Event", JSON.stringify({ type: "areas", areas: areas }));
}

function findWindow(id) {
    for (const w of workspace.windowList()) if (String(w.internalId) === id) return w;
    return null;
}

function handle(raw) {
    if (!raw) return;
    let cmd;
    try { cmd = JSON.parse(raw); } catch (e) { log("comando inválido: " + raw); return; }
    const w = cmd.id ? findWindow(cmd.id) : null;
    switch (cmd.action) {
    case "activate":
        if (w) { if (w.minimized) w.minimized = false; workspace.activeWindow = w; }
        break;
    case "toggle": // clique na dock: ativa; se já ativa, minimiza
        if (w) {
            if (workspace.activeWindow === w && !w.minimized) w.minimized = true;
            else { w.minimized = false; workspace.activeWindow = w; }
        }
        break;
    case "minimize": if (w) w.minimized = true; break;
    case "moveToDesktop": {
        const d = (workspace.desktops || []).find(x => String(x.id) === cmd.desktop);
        if (w && d) { w.desktops = [d]; if (cmd.focus) { workspace.currentDesktop = d; workspace.activeWindow = w; } }
        break;
    }
    case "maximize": // alterna maximizar (janela informada ou a ativa)
        { const t = w || workspace.activeWindow; if (t) t.setMaximize(t.maximizeMode !== 3, t.maximizeMode !== 3); }
        break;
    case "desktopNext": case "desktopPrev": {
        const ds = workspace.desktops || []; const i = ds.indexOf(workspace.currentDesktop);
        if (ds.length > 1 && i >= 0) workspace.currentDesktop = ds[(i + (cmd.action === "desktopNext" ? 1 : ds.length - 1)) % ds.length];
        break;
    }
    case "close": if (w) w.closeWindow(); break;
    // LowPan Shells (barra de menu estilo macOS, §21.33): menu "Janela"
    case "fullscreen": { const t = w || workspace.activeWindow; if (t) t.fullScreen = !t.fullScreen; break; }
    case "keepAbove": { const t = w || workspace.activeWindow; if (t) t.keepAbove = !t.keepAbove; break; }
    case "setDesktop": {
        const d = (workspace.desktops || []).find(x => String(x.id) === cmd.desktop);
        if (d) workspace.currentDesktop = d;
        break;
    }
    case "showDesktop": workspace.showingDesktop = !workspace.showingDesktop; break;
    case "refresh": send("refresh"); break;
    case "areas": sendAreas(); break;
    default: log("ação desconhecida: " + cmd.action);
    }
}

// LowPan Shells §21.42: se a chamada "Next" falhar (ajudante ocupado além do limite do callDBus), o KWin não chama
// o retorno e a fila morria para sempre — o dock e os menus paravam de agir. `pollAt` marca a espera em curso;
// qualquer evento de janela com a espera parada há mais de 30 s recomeça o ciclo (`kick`).
let pollAt = 0;
function poll() {
    pollAt = Date.now();
    callDBus(SERVICE, PATH, IFACE, "Next", function (reply) {
        pollAt = 0;
        try { handle(String(reply || "")); }
        catch (e) { log("erro ao executar comando: " + e); }
        poll();
    });
}
function kick() {
    if (pollAt > 0 && Date.now() - pollAt > 30000) {
        log("fila de comandos parada; recomeçando");
        poll();
    }
}

function watch(w) {
    if (!w || !w.normalWindow) return;
    w.captionChanged.connect(() => send("caption"));
    w.minimizedChanged.connect(() => send("minimized"));
    w.desktopsChanged.connect(() => send("desktops"));
    w.demandsAttentionChanged.connect(() => send("attention"));
    w.fullScreenChanged.connect(() => send("fullscreen"));
    w.maximizedChanged && w.maximizedChanged.connect(() => send("maximized"));
    w.interactiveMoveResizeFinished && w.interactiveMoveResizeFinished.connect(() => send("geometry"));
    w.outputChanged && w.outputChanged.connect(() => send("output"));
}

for (const w of workspace.windowList()) watch(w);
// Bug do KWin 6.8: a layer surface nova nasce encaixada na área útil e pode ficar FORA da tela
// (ex.: -10,-67) até o shell forçar um relayout. Enquanto estiver fora, fica invisível: assim o
// usuário nunca vê o salto (papel de parede, Configurações, menus...).
function misplaced(w) {
    const o = w.output ? w.output.geometry : null, g = w.frameGeometry;
    if (!o) return false;
    return g.x < o.x - 0.5 || g.y < o.y - 0.5 || g.x + g.width > o.x + o.width + 0.5 || g.y + g.height > o.y + o.height + 0.5;
}
function hideUntilPlaced(w) {
    // Acompanha a vida toda da superfície: o deslocamento acontece logo DEPOIS de mapear e pode
    // voltar quando outro cliente mexe no layout. O sinal é síncrono, então o quadro deslocado
    // não chega a ser pintado.
    const update = () => {
        const off = misplaced(w);
        if (off && w.opacity !== 0) w.opacity = 0;
        else if (!off && w.opacity === 0) w.opacity = 1;
    };
    w.frameGeometryChanged.connect(update);
    update();
}

workspace.windowAdded.connect(w => {
    // superfícies do próprio shell: esconde enquanto estiver deslocada e avisa o shell para corrigir
    if (w && String(w.resourceClass) === "quickshell") {
        hideUntilPlaced(w);
        callDBus(SERVICE, PATH, IFACE, "Event", JSON.stringify({ type: "layerAdded" }));
        sendAreas();
        return;
    }
    watch(w); send("added");
});
workspace.windowRemoved.connect(w => { if (w && String(w.resourceClass) === "quickshell") sendAreas(); else send("removed"); });
if (workspace.screensChanged) workspace.screensChanged.connect(sendAreas);
workspace.windowActivated.connect(() => send("activated"));
workspace.currentDesktopChanged.connect(() => send("desktop"));
workspace.desktopsChanged.connect(() => send("desktops"));
if (workspace.showingDesktopChanged) workspace.showingDesktopChanged.connect(() => send("showingDesktop"));

log("carregado");
send("start");
sendAreas();
poll();
