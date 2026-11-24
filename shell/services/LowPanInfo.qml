pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// LowPan Shells — identidade do fork: versão própria (LOWPAN_VERSION) e a versão do iNiR em que se baseia (VERSION).
Singleton {
    id: root
    readonly property string name: "LowPan Shells"
    readonly property string version: versionFile.text().trim()
    readonly property string upstreamName: "iNiR"
    readonly property string upstreamVersion: upstreamFile.text().trim()
    readonly property string upstreamUrl: "https://github.com/snowarch/inir"

    FileView { id: versionFile; path: Quickshell.shellPath("LOWPAN_VERSION") }
    FileView { id: upstreamFile; path: Quickshell.shellPath("VERSION") }
}
