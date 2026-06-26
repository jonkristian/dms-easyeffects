#!/usr/bin/env bash
#
# Deploy this plugin into the local DankMaterialShell plugins directory and
# hot-reload it, with a backup so you can always get back to the original.
#
#   ./deploy.sh            Back up the deployed copy (once), copy files, reload DMS
#   ./deploy.sh --restore  Restore the backed-up original and reload DMS
#   ./deploy.sh --clean    Remove the deployed plugin and reload DMS
#   ./deploy.sh --help     Show this help
#
set -euo pipefail

PLUGIN_ID="easyEffects"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins"
DEST_DIR="$DEST_ROOT/$PLUGIN_ID"
# Kept outside the plugins dir so DMS doesn't load it as a second plugin.
BACKUP_DIR="$SRC_DIR/.deploy-backup"

# Files that make up the plugin (everything else, e.g. .git, is ignored).
FILES=(
    "plugin.json"
    "EasyEffectsWidget.qml"
    "EasyEffectsSettings.qml"
    "README.md"
    "LICENSE"
    "screenshot.png"
)

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

reload_dms() {
    if command -v dms >/dev/null 2>&1; then
        if dms ipc plugins reload "$PLUGIN_ID" >/dev/null 2>&1; then
            echo "Reloaded '$PLUGIN_ID' in DankMaterialShell."
        else
            echo "Could not reload via DMS (is the shell running?). Toggle the plugin in DMS settings."
        fi
    fi
}

# Snapshot the currently deployed copy once, so --restore can bring it back.
backup_once() {
    if [[ ! -e "$BACKUP_DIR" && -d "$DEST_DIR" ]]; then
        cp -r "$DEST_DIR" "$BACKUP_DIR"
        echo "Backed up current deployed copy to $BACKUP_DIR"
    fi
}

deploy() {
    backup_once
    mkdir -p "$DEST_DIR"
    for f in "${FILES[@]}"; do
        if [[ -e "$SRC_DIR/$f" ]]; then
            cp -f "$SRC_DIR/$f" "$DEST_DIR/$f"
            echo "  + $f"
        fi
    done
    echo "Deployed to $DEST_DIR"
    reload_dms
}

restore() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backup found at $BACKUP_DIR" >&2
        exit 1
    fi
    rm -rf "$DEST_DIR"
    cp -r "$BACKUP_DIR" "$DEST_DIR"
    echo "Restored original from $BACKUP_DIR"
    reload_dms
}

clean() {
    if [[ -d "$DEST_DIR" ]]; then
        rm -rf "$DEST_DIR"
        echo "Removed $DEST_DIR"
    else
        echo "Nothing to remove ($DEST_DIR does not exist)"
    fi
    reload_dms
}

case "${1:-}" in
    -r|--restore)
        restore
        ;;
    -c|--clean)
        clean
        ;;
    -h|--help)
        usage
        ;;
    "")
        deploy
        ;;
    *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
esac
