pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * LowPan Shells: o efeito de abrir/fechar janelas escolhido no KWin (Configurações › Janelas ›
 * Efeitos › Abrir e fechar), para as janelas do próprio shell (Spotlight, galeria de papel de
 * parede, Configurações), que o KWin não anima porque não são janelas para ele.
 * scripts/kwin-open-effect.py descobre o efeito no kwinrc e, se for do Burn-My-Windows, converte o
 * shader para o Qt Quick. kind: "shader" | "scale" | "fade" | "glide" | "kinetic" | "none".
 * "none" (efeito Nenhum ou desconhecido) = o shell usa a animação própria do iRiS.
 */
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/kwin-open-effect.py")
    readonly property string kwinrc: FileUtils.trimFileProtocol(`${Directories.config}/kwinrc`)

    property string kind: "none"
    property string effectId: ""
    property int duration: 0
    property string shaderQml: ""
    readonly property bool active: CompositorService.isKWin && root.kind !== "none" && root.duration > 0
        && (root.kind !== "shader" || root.shaderQml.length > 0)

    // Superfícies do shell que seguem o efeito (motionSurface do IrisMorphSurface).
    readonly property var surfaces: ["spotlight", "gallery", "settings"]
    function follows(surface: string): bool {
        return root.active && root.surfaces.includes(surface)
    }

    function refresh(): void {
        if (!CompositorService.isKWin) return
        if (probe.running) debounce.restart()
        else probe.running = true
    }

    Component.onCompleted: root.refresh()

    Process {
        id: probe
        command: ["python3", root.script]
        stdout: StdioCollector {
            id: probeOutput
            onStreamFinished: {
                try {
                    const data = JSON.parse(probeOutput.text)
                    if (data.error) console.warn("[KWinOpenEffect]", data.error)
                    root.shaderQml = data.qml ?? ""
                    root.duration = Number(data.duration ?? 0)
                    root.effectId = data.id ?? ""
                    root.kind = data.kind ?? "none"
                } catch (e) {
                    console.warn("[KWinOpenEffect] Bad output:", e)
                    root.kind = "none"
                }
            }
        }
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.refresh()
    }

    // Trocar o efeito ou a duração (aqui ou na página Animações do KDE) grava no kwinrc.
    FileView {
        path: CompositorService.isKWin ? root.kwinrc : ""
        watchChanges: true
        printErrors: false
        onFileChanged: debounce.restart()
    }

    IpcHandler {
        target: "kwinOpenEffect"
        function status(): string {
            return root.kind + " " + root.effectId + " " + root.duration + "ms " + root.shaderQml
        }
    }
}
