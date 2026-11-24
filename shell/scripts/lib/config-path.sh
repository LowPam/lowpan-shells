#!/usr/bin/env bash

# Library file: intended to be sourced by other scripts.
# Do not set shell options here; callers own execution mode.

# Canonical iNiR config directory is ~/.config/inir.
# Legacy installs used ~/.config/illogical-impulse.
#
# Compatibility policy:
# - If legacy dir exists as a real directory, keep using it.
# - If legacy is a symlink and new dir exists, use new dir.
# - If only one exists, use that one.
# - If none exists, default to new dir.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

INIR_CONFIG_DIR_NEW="${XDG_CONFIG_HOME}/inir"
INIR_CONFIG_DIR_OLD="${XDG_CONFIG_HOME}/illogical-impulse"

inir_config_dir() {
    # Legacy symlink -> new (post-migration steady state)
    if [[ -L "$INIR_CONFIG_DIR_OLD" && -d "$INIR_CONFIG_DIR_NEW" ]]; then
        printf '%s\n' "$INIR_CONFIG_DIR_NEW"
        return
    fi

    # Legacy real directory wins for backwards compatibility.
    if [[ -d "$INIR_CONFIG_DIR_OLD" ]]; then
        printf '%s\n' "$INIR_CONFIG_DIR_OLD"
        return
    fi

    # New path when legacy is absent.
    if [[ -d "$INIR_CONFIG_DIR_NEW" ]]; then
        printf '%s\n' "$INIR_CONFIG_DIR_NEW"
        return
    fi

    # Fresh install default.
    printf '%s\n' "$INIR_CONFIG_DIR_NEW"
}

# LowPan Shells: trava geral de integração com o sistema.
# Nada fora do próprio shell (GTK, KDE/kdeglobals, gsettings, terminais, editores, navegadores,
# Spotify, SDDM, Steam, fontes, ícones...) é alterado, a não ser que o config.json tenha
#   "lowpan": { "allowAppTheming": true }
# Uso: lowpan_app_theming_allowed || exit 0
lowpan_app_theming_allowed() {
    local cfg
    cfg="$(inir_config_file)"
    [[ -f "$cfg" ]] || return 1
    [[ "$(jq -r '.lowpan.allowAppTheming // false' "$cfg" 2>/dev/null)" == "true" ]]
}

inir_config_file() {
    printf '%s/config.json\n' "$(inir_config_dir)"
}

inir_version_file() {
    printf '%s/version.json\n' "$(inir_config_dir)"
}

inir_installed_marker_file() {
    printf '%s/installed_true\n' "$(inir_config_dir)"
}

inir_migrations_state_file() {
    printf '%s/migrations.json\n' "$(inir_config_dir)"
}
