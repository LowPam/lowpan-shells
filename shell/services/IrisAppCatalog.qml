pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs

import qs.modules.common

// LowPan Shells — catálogo do Spotlight: categorias (freedesktop + Waydroid) e favoritos, como o Kickoff do Plasma.
// Os favoritos vivem em iris.palette.favorites (ids de .desktop, na ordem) e, na primeira vez, vêm do Kickoff.
Singleton {
    id: root

    readonly property var options: Config.options?.iris?.palette ?? ({})

    // Ordem e regras das categorias. "match" são categorias do .desktop; a primeira que casar vence, como os
    // submenus do Plasma (um app com "System;Settings" fica em Configurações).
    readonly property var definitions: [
        { key: "development", label: "Development", glyph: "code", match: ["Development"] },
        { key: "education", label: "Education", glyph: "school", match: ["Education"] },
        { key: "office", label: "Office", glyph: "edit_document", match: ["Office"] },
        { key: "graphics", label: "Graphics", glyph: "palette", match: ["Graphics"] },
        { key: "internet", label: "Internet", glyph: "cloud", match: ["Network"] },
        { key: "games", label: "Games", glyph: "sports_esports", match: ["Game"] },
        { key: "multimedia", label: "Multimedia", glyph: "music_video", match: ["AudioVideo", "Audio", "Video"] },
        { key: "science", label: "Science", glyph: "science", match: ["Science"] },
        { key: "settings", label: "Settings", glyph: "tune", match: ["Settings"] },
        { key: "system", label: "System", glyph: "settings", match: ["System"] },
        { key: "utilities", label: "Utilities", glyph: "build", match: ["Utility"] },
        { key: "help", label: "Help", glyph: "help", match: ["Documentation", "Help"] },
        { key: "waydroid", label: "Waydroid", glyph: "android", match: ["X-WayDroid-App"] },
        { key: "other", label: "Others", glyph: "apps", match: [] }
    ]
    readonly property var priority: ["waydroid", "games", "development", "settings", "graphics", "multimedia", "internet",
        "office", "education", "science", "system", "utilities", "help"]

    // Apps visíveis, em ordem alfabética, sem repetir nome (Flatpak + sistema), cada um com a sua categoria.
    readonly property var apps: {
        const seen = new Set()
        const out = []
        for (const entry of AppSearch.list) {
            if (!entry || entry.noDisplay) continue
            const name = String(entry.name ?? "").trim()
            if (name.length === 0 || seen.has(name.toLowerCase())) continue
            seen.add(name.toLowerCase())
            out.push({ entry: entry, id: String(entry.id ?? ""), name: name, category: root.categoryOf(entry) })
        }
        return out
    }
    function categoryOf(entry: var): string {
        const cats = Array.from(entry?.categories ?? []).map(c => String(c))
        for (const key of root.priority) {
            const def = root.definitions.find(d => d.key === key)
            if (def.match.some(m => cats.includes(m))) return key
        }
        return "other"
    }

    function enabled(key: string): bool {
        const value = root.options?.categories?.[key]
        return value === undefined ? key !== "help" : Boolean(value)
    }
    // Barra: Favoritos, Todos e as categorias ligadas que têm algum app.
    readonly property var categories: {
        const used = new Set(root.apps.map(app => app.category))
        return [{ key: "favorites", label: "Favorites", glyph: "bookmark" }, { key: "all", label: "All applications", glyph: "apps" }]
            .concat(root.definitions.filter(d => used.has(d.key) && root.enabled(d.key)))
    }
    // Para as Configurações: todas as que existem nesta máquina (ligadas ou não).
    readonly property var presentCategories: {
        const used = new Set(root.apps.map(app => app.category))
        return root.definitions.filter(d => used.has(d.key))
    }

    readonly property var favoriteIds: Array.from(root.options?.favorites ?? []).map(id => String(id))
    function isFavorite(id: string): bool { return root.favoriteIds.includes(id) }
    function setFavorites(ids: var): void { Config.setNestedValue("iris.palette.favorites", ids) }
    function toggleFavorite(id: string): void {
        if (id.length === 0) return
        const ids = root.favoriteIds
        root.setFavorites(ids.includes(id) ? ids.filter(x => x !== id) : ids.concat([id]))
    }
    function moveFavorite(id: string, step: int): void {
        const ids = root.favoriteIds.slice()
        const at = ids.indexOf(id), to = at + step
        if (at < 0 || to < 0 || to >= ids.length) return
        ids.splice(at, 1)
        ids.splice(to, 0, id)
        root.setFavorites(ids)
    }

    function appsIn(key: string): var {
        if (key === "favorites") {
            const byId = ({})
            for (const app of root.apps) byId[app.id] = app
            return root.favoriteIds.map(id => byId[id] ?? root.lookup(id)).filter(Boolean)
        }
        if (key === "all") return root.apps
        return root.apps.filter(app => app.category === key)
    }
    // Um favorito pode ser um app escondido da lista (NoDisplay) ou com outro id: procura direto.
    function lookup(id: string): var {
        const entry = AppSearch.lookupDesktopEntry(id)
        return entry ? { entry: entry, id: String(entry.id ?? id), name: String(entry.name ?? id), category: root.categoryOf(entry) } : null
    }

    // Importa os favoritos do Kickoff uma vez (ou quando pedido nas Configurações).
    function importFromPlasma(): void { importer.running = true }
    Process {
        id: importer
        command: [Quickshell.shellPath("scripts/lowpan-plasma-favorites")]
        stdout: StdioCollector {
            onStreamFinished: {
                let ids = []
                try { ids = JSON.parse(this.text) } catch (e) { return }
                if (!Array.isArray(ids)) return
                const merged = root.favoriteIds.concat(ids.filter(id => !root.favoriteIds.includes(id)))
                Config.setNestedValues({ "iris.palette.favorites": merged, "iris.palette.favoritesImported": true })
            }
        }
    }
    // Espera o Config carregar: antes disso o "ainda não importado" vale sempre.
    readonly property bool wantsImport: Config.ready && !(root.options?.favoritesImported ?? false)
    onWantsImportChanged: if (root.wantsImport) root.importFromPlasma()
    Component.onCompleted: if (root.wantsImport) root.importFromPlasma()
}
