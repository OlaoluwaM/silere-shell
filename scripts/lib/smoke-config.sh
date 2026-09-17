#!/usr/bin/env bash
# shellcheck shell=bash
# Private configuration preparation for check.sh's startup dwell.

_silere_prepare_smoke_config() { # $1 = resolved XDG config home, $2 = private XDG config home
    local source_home="$1" private_home="$2"
    local source="$source_home/silere-shell" private="$private_home/silere-shell"

    if [ -z "$source_home" ]; then
        printf 'Silere configuration home could not be resolved\n' >&2
        return 1
    fi
    mkdir -p "$private" || return 1
    if [ ! -e "$source" ] && [ ! -L "$source" ]; then
        return 0
    fi
    if [ ! -d "$source" ]; then
        printf 'Silere configuration is not a directory: %s\n' "$source" >&2
        return 1
    fi

    # Follow every source link. The probe may write its configuration files, so retaining
    # even one link could send that write back into the maintainer's live config.
    cp -aL "$source/." "$private/" || return 1
    if find "$private" -type l -print -quit | grep -q .; then
        printf 'private Silere configuration still contains a symlink: %s\n' "$private" >&2
        return 1
    fi
}

_silere_cleanup_smoke_config() { # $1 = private XDG config home
    [ -z "${1:-}" ] || rm -rf "$1"
}

_silere_run_smoke_probe() { # $1 = resolved config home, $2 = private config home, $3 = log
    # shellcheck disable=SC2034 # check.sh reads this result after the launcher returns
    SILERE_SMOKE_CONFIG_READY=0
    _silere_prepare_smoke_config "$1" "$2" || return 1
    # shellcheck disable=SC2034 # check.sh reads this result after the launcher returns
    SILERE_SMOKE_CONFIG_READY=1
    _run_shell_probe "$3" "XDG_CONFIG_HOME=$2"
}
