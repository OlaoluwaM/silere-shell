# shellcheck shell=bash
# Shared by install.sh, check.sh, and CI: one module list, one import-root
# lookup, one version floor, instead of three diverging copies. Quickshell
# packages may split service plugins even when the `qs` binary exists, so check
# actual QML import paths rather than assuming one distro layout.

# The floor the README and the AUR PKGBUILD both promise. Lint keeps those two in
# step with this value; check.sh compares it against the Quickshell actually installed.
# shellcheck disable=SC2034
SILERE_MIN_QUICKSHELL="0.3.1"

# Reads the version out of `qs --version`, e.g. "Quickshell 0.3.1 (revision ...)".
# Prints nothing when the binary is missing or the format is one we don't know.
_silere_quickshell_version() {
    command -v qs >/dev/null 2>&1 || return 1
    qs --version 2>&1 | sed -n '1s/.*[Qq]uickshell[[:space:]]\+v\?\([0-9]\+\(\.[0-9]\+\)*\).*/\1/p'
}

# 0 when $1 is at least $2, comparing dot-separated numbers left to right.
_silere_version_at_least() {
    [ "$1" = "$2" ] && return 0
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$2" ]
}

# The array is consumed by the scripts that source this library; checking this
# file by itself cannot see those references.
# shellcheck disable=SC2034
SILERE_REQUIRED_QML_MODULES=(
    QtQuick
    QtQuick.Effects
    QtQuick.Shapes
    QtQuick.Window
    Quickshell
    Quickshell.Bluetooth
    Quickshell.Hyprland
    Quickshell.Io
    Quickshell.Networking
    Quickshell.Services.Mpris
    Quickshell.Services.Notifications
    Quickshell.Services.Pipewire
    Quickshell.Services.SystemTray
    Quickshell.Services.UPower
    Quickshell.Wayland
    Quickshell.Widgets
)

_silere_qml_import_roots=()
if [ -n "${QML2_IMPORT_PATH:-}" ]; then
    IFS=: read -r -a _silere_qml_import_roots <<< "$QML2_IMPORT_PATH"
fi
if [ -n "${QML_IMPORT_PATH:-}" ]; then
    _silere_qml_extra_roots=()
    IFS=: read -r -a _silere_qml_extra_roots <<< "$QML_IMPORT_PATH"
    _silere_qml_import_roots+=("${_silere_qml_extra_roots[@]}")
    unset _silere_qml_extra_roots
fi
for _silere_qtpaths in qtpaths6 qtpaths; do
    if command -v "$_silere_qtpaths" >/dev/null 2>&1; then
        _silere_qml_qt_root="$("$_silere_qtpaths" --query QT_INSTALL_QML 2>/dev/null || true)"
        [ -n "$_silere_qml_qt_root" ] && _silere_qml_import_roots+=("$_silere_qml_qt_root")
        unset _silere_qml_qt_root
        break
    fi
done
unset _silere_qtpaths
_silere_qml_import_roots+=(/usr/lib/qt6/qml /usr/lib64/qt6/qml /usr/local/lib/qt6/qml)
# debian hides qml under a multiarch triplet and ships qtpaths6 in a dev package
for _silere_qml_multiarch in /usr/lib/*-linux-gnu*/qt6/qml; do
    [ -d "$_silere_qml_multiarch" ] && _silere_qml_import_roots+=("$_silere_qml_multiarch")
done
unset _silere_qml_multiarch

_qml_module_available() {
    local module_path="${1//./\/}" root
    for root in "${_silere_qml_import_roots[@]}"; do
        [ -n "$root" ] || continue
        [ -r "$root/$module_path/qmldir" ] && return 0
    done
    return 1
}
