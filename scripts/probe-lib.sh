# shellcheck shell=bash
# Shared by scripts/test-{logic,mutate,surfaces,layout-fit}.sh: one Quickshell
# probe harness instead of four copies that drift apart.

# Qt reports these non-fatally — the object is still created and qs exits 0 — so a
# probe log has to be scanned as well as its sentinel checked. One copy because
# test-logic's had already lost "is not a type".
# shellcheck disable=SC2034
SILERE_PROBE_ERRORS='Unable to assign .*|Cannot assign .*|is not a type|ReferenceError: [^,]*|TypeError: [^,]*|Binding loop detected[^,]*'

# a probe shell reads the real battery and CPU sensors; see SystemAlerts._sandboxed
export SILERE_SANDBOX=1
# probes load fresh temp copies, whose compiled units would pile up in ~/.cache/quickshell/qmlcache forever
export QML_DISABLE_DISK_CACHE=1

_probe_require_qs() {
    if ! command -v qs >/dev/null 2>&1; then
        if [ "${SILERE_REQUIRE_QML_TOOLS:-0}" = "1" ]; then
            echo "FAIL: quickshell (qs) not installed" >&2
            exit 1
        fi
        echo "SKIP: quickshell (qs) not installed" >&2
        exit 0
    fi
    # installed but unable to start must not skip: that would pass CI with no coverage
    local out
    if ! out="$(qs --version 2>&1)"; then
        echo "FAIL: quickshell (qs) will not start: ${out%%$'\n'*}" >&2
        exit 1
    fi
}

# quickshell makes the entry file's directory the project root, so a probe needs
# its own tree with the shell's import roots beside it.
_probe_project() { # $1 = repo root, $2 = probe source, $3 = destination dir
    cp "$2" "$3/${2##*/}"
    ln -s "$1/config" "$3/config"
    ln -s "$1/services" "$3/services"
    ln -s "$1/modules" "$3/modules"
}

# A root-level required property is the one thing a probe cannot supply, so it is
# the filter; a delegate declares its own indented well past this, and PanelWindow
# roots drop out the same way since they all require a screen.
_probe_standalone() { # $1 = directory
    find "$1" -maxdepth 1 -name '*.qml' \
        ! -exec grep -qE '^ {0,4}required property' {} \; -print
}

# Neither Qt.exit() nor Quickshell.exit() ends a Quickshell process, so a probe
# cannot quit itself: wait for its sentinel, then kill the pid it started on.
_probe_wait() { # $1 = log, $2 = pid, $3 = sentinel, $4 = ticks, $5 = seconds per tick
    local waited=0
    while [ "$waited" -lt "$4" ]; do
        grep -q "$3" "$1" 2>/dev/null && return 0
        kill -0 "$2" 2>/dev/null || return 1
        sleep "$5"
        waited=$((waited + 1))
    done
    return 1
}

# grep is line-oriented, so [^\n] here would mean "not backslash or n" and truncate
# "Cannot assign to non-existent..." at the first n. Use .* instead.
_probe_errors() { # $1 = log
    grep -oE "$SILERE_PROBE_ERRORS" "$1" | sort -u | head -10 || true
}

# A probe's children, such as fontconfig's fc-list, must not outlive it and race the
# runner's cleanup, so a probe started with setsid is stopped as a whole group. The
# group is only signalled when the pid leads its own: a pgid that is not the probe's
# would take the runner or the user's shell down with it.
_probe_stop() { # $1 = pid
    # negated, 0 is the caller's own group and 1 every process on the host, and kill reads
    # "01" as 1; only a plain pid above 1 may reach a signal
    case "${1:-}" in
        '' | *[!0-9]* | 0* | 1) return 0 ;;
    esac
    local target="$1" ppid="" pgid=""
    # ps finds nothing once the probe exits between checks; under errexit that must not
    # abort the caller's cleanup
    read -r ppid pgid < <(ps -o ppid=,pgid= -p "$1" 2>/dev/null) || true
    if [ -z "$ppid" ]; then
        if ! kill -0 "$1" 2>/dev/null; then
            # an already reaped leader can leave its group behind, still writing into the
            # runner's temp dirs. POSIX keeps a pid unused while a group carries its number,
            # so a live group here is still the probe's own
            wait "$1" 2>/dev/null || true
            kill -KILL -- "-$1" 2>/dev/null || true
            return 0
        fi
        # ps can fail while the pid lives; the kernel's own record still names the parent
        # and group, so a reused pid is not mistaken for the probe
        local stat=""
        IFS= read -r stat 2>/dev/null < "/proc/$1/stat" || true
        stat=${stat##*) }
        read -r _ ppid pgid _ <<< "$stat" || true
    fi
    if [ -n "$ppid" ]; then
        # a pid that is not this shell's child was reused after the probe exited; signalling
        # it, let alone its group, would hit a stranger
        [ "$ppid" = "$$" ] || [ "$ppid" = "$BASHPID" ] || return 0
        [ "$pgid" = "$1" ] && target="-$1"
    fi
    # a live pid neither ps nor /proc can describe has no known parent or group, so the one
    # pid is the only target that cannot hit a stranger; a guessed group could, and a wait on
    # a pid this shell may not own never returns
    kill -TERM -- "$target" 2>/dev/null || true
    # A broken probe must not wedge the test runner while ignoring TERM. Poll the
    # exact child briefly, then force it down before wait reaps its status.
    local i
    for ((i = 0; i < 20; i++)); do
        kill -0 "$1" 2>/dev/null || {
            wait "$1" 2>/dev/null || true
            # survivors of the leader share its group until they exit
            [ "$target" = "$1" ] || kill -KILL -- "$target" 2>/dev/null || true
            return 0
        }
        sleep 0.05
    done
    kill -KILL -- "$target" 2>/dev/null || true
    wait "$1" 2>/dev/null || true
    [ "$target" = "$1" ] || kill -KILL -- "$target" 2>/dev/null || true
}
