#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/silere-portability-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    [ "$actual" = "$expected" ] || fail "$label (expected '$expected', got '$actual')"
}

# kill -0 succeeds on a zombie, and an orphan killed under a PID 1 that never reaps
# stays one — which is every container job, GitHub Actions included
_pid_running() { # $1 = pid
    local line
    # the redirect is what fails for a reaped pid, and it reports before a trailing
    # 2>/dev/null would apply, so silence stderr first
    IFS= read -r line 2>/dev/null < "/proc/$1/stat" || return 1
    line=${line##*) }
    [ "${line%% *}" != Z ]
}

test_xdg_paths() (
    local home="$TMP/xdg-home" actual
    mkdir -p "$home"

    actual="$(HOME="$home" bash -c 'source "$1"; _silere_xdg_home relative/config .config' \
        _ "$ROOT/scripts/lib/xdg.sh")"
    assert_eq "$home/.config" "$actual" "relative XDG config fallback"

    actual="$(HOME="$home" bash -c 'source "$1"; _silere_xdg_home /absolute/config .config' \
        _ "$ROOT/scripts/lib/xdg.sh")"
    assert_eq "/absolute/config" "$actual" "absolute XDG config"

    actual="$(HOME="$home" bash -c 'source "$1"; _silere_xdg_home relative/data .local/share' \
        _ "$ROOT/scripts/lib/xdg.sh")"
    assert_eq "$home/.local/share" "$actual" "relative XDG data fallback"

    if HOME=relative bash -c 'source "$1"; _silere_xdg_home "" .config' \
            _ "$ROOT/scripts/lib/xdg.sh" >/dev/null 2>&1; then
        fail "a relative HOME produced an XDG path"
    fi
)

test_qml_module_lookup() (
    local imports="$TMP/qml-imports"
    mkdir -p "$imports/Silere/TestModule"
    printf 'module Silere.TestModule\n' > "$imports/Silere/TestModule/qmldir"

    # Import roots are resolved once at source time (not per call), so the
    # fake root must be in place before the QML-modules lib is sourced.
    export QML2_IMPORT_PATH="$imports"
    export QML_IMPORT_PATH=""
    source "$ROOT/scripts/lib/qml-modules.sh"

    _qml_module_available Silere.TestModule \
        || fail "QML module in temporary import root was not found"
    if _qml_module_available Silere.AbsentModule; then
        fail "absent QML module was reported as available"
    fi
)

test_quickshell_version_after_qt_warning() (
    local stub="$TMP/qs-version-stub"
    mkdir -p "$stub"
    printf '#!/bin/sh\n%s\n%s\n' \
        'echo "Detected locale \"C\" with character encoding \"ANSI_X3.4-1968\", which is not UTF-8." >&2' \
        'echo "Quickshell 0.3.1 (revision , distributed by Arch Linux)"' > "$stub/qs"
    chmod +x "$stub/qs"
    PATH="$stub:$PATH"
    source "$ROOT/scripts/lib/qml-modules.sh"
    assert_eq 0.3.1 "$(_silere_quickshell_version)" "the Quickshell version is read past Qt's locale warning"
)

test_headless_qml_import_roots() (
    local stubs="$TMP/qml-tool-stubs"
    local first="$TMP/qml-import-first"
    local second="$TMP/qml-import-second"
    local lint_help="--import --unused-imports --alias-cycle --assignment-in-condition --deprecated --duplicate-enum-entries --duplicate-inline-component --duplicate-property-binding --duplicated-name --eval --inheritance-cycle --invalid-lint-directive --missing-enum-entry --property-override --read-only-property --required --unreachable-code --unresolved-alias --missing-type --non-list-property --unterminated-case --unintentional-empty-block --access-singleton-via-object --comma --component-children-count --confusing-expression-statement --duplicate-import --enum-entry-matches-enum --equality-type-coercion --literal-constructor --multiline-strings --non-root-enum --prefer-non-var-properties --redundant-optional-chaining --stale-property-read --top-level-component --var-used-before-declaration --with"

    mkdir -p "$stubs" "$first" "$second"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "${1:-}" = --version ]; then echo "fixture 6.0.0"; exit 0; fi' \
        'if [ "${1:-}" = --help ]; then printf "%s\n" "$SILERE_QMLLINT_HELP"; exit 0; fi' \
        'found=0' \
        'previous=' \
        'for argument do' \
        '    if [ "$previous" = -I ] && [ "$argument" = "$SILERE_EXPECTED_IMPORT_ROOT" ]; then found=1; fi' \
        '    previous=$argument' \
        'done' \
        '[ "$found" = 1 ] || { echo "missing secondary QML import root" >&2; exit 2; }' \
        'exit 0' > "$stubs/qmlcachegen"
    cp "$stubs/qmlcachegen" "$stubs/qmllint"
    chmod +x "$stubs/qmlcachegen" "$stubs/qmllint"

    if ! PATH="$stubs:$PATH" QML2_IMPORT_PATH="$first:$second" QML_IMPORT_PATH="" \
            SILERE_EXPECTED_IMPORT_ROOT="$second" SILERE_REQUIRE_QML_TOOLS=1 \
            SILERE_QMLLINT_HELP="$lint_help" \
            bash "$ROOT/scripts/test-qml-headless.sh" >/dev/null; then
        fail "headless QML tools did not receive every configured import root"
    fi
)

# timeout stops watching when its direct command exits, so the inner shell must stay
# until every ordinary background child has left the timeout-owned process group.
test_hook_timeout_contains_tree() (
    command -v timeout >/dev/null 2>&1 || {
        printf 'SKIP: hook containment (timeout unavailable)\n'
        return 0
    }
    local dir hook child
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' RETURN
    hook="$dir/hook"
    cat > "$hook" <<EOF
#!/bin/sh
sh -c 'echo \$\$ > "$dir/child.pid"; exec sleep 600' &
exit 0
EOF
    chmod +x "$hook"

    # the same monitor Hooks.qml places between timeout and the hook
    local monitor='"$@"; code=$?; '
    monitor+='IFS= read -r own < /proc/self/stat || exit "$code"; '
    monitor+='self=${own%% *}; rest=${own##*) }; set -- $rest; group=$3; outer=$PPID; '
    monitor+='while :; do alive=false; for stat in /proc/[0-9]*/stat; do '
    monitor+='[ -r "$stat" ] || continue; IFS= read -r line < "$stat" || continue; '
    monitor+='pid=${line%% *}; rest=${line##*) }; set -- $rest; '
    monitor+='[ "${1:-}" != Z ] && [ "${3:-}" = "$group" ] '
    monitor+='&& [ "$pid" != "$self" ] && [ "$pid" != "$outer" ] '
    monitor+='&& { alive=true; break; }; done; $alive || exit "$code"; sleep 0.1; done'
    timeout --kill-after=1 1 bash -c "$monitor" silere-hook "$hook" >/dev/null 2>&1 &
    local wrapper=$!
    local waited=0
    while [ ! -s "$dir/child.pid" ] && [ "$waited" -lt 50 ]; do
        sleep 0.1
        waited=$((waited + 1))
    done
    child="$(cat "$dir/child.pid" 2>/dev/null || true)"
    [ -n "$child" ] || fail "hook containment: the test hook never reported its child"
    wait "$wrapper" 2>/dev/null || true
    sleep 1

    if _pid_running "$child"; then
        kill -KILL "$child" 2>/dev/null || true
        fail "a hook's background child outlived the hook's runtime bound"
    fi
)

test_internal_type_boundaries() (
    command -v python3 >/dev/null 2>&1 || return 0
    local fixture="$TMP/internal-types"
    mkdir -p "$fixture/owner" "$fixture/consumer" "$fixture/scripts"
    printf 'internal PrivateCard PrivateCard.qml\n' > "$fixture/owner/qmldir"
    printf 'Item {}\n' > "$fixture/owner/PrivateCard.qml"
    printf 'PrivateCard {}\n' > "$fixture/owner/Local.qml"
    printf 'PrivateCard {}\n' > "$fixture/scripts/Probe.qml"
    printf 'Item { /* PrivateCard */ property string path: "PrivateCard.qml" }\n' \
        > "$fixture/consumer/Legal.qml"
    python3 "$ROOT/scripts/check-internal-types.py" "$fixture" \
        || fail "internal type lint rejected module-local use, text, or a relocated probe"
    local use
    for use in 'PrivateCard {}' 'Owner.PrivateCard {}' 'Item { property PrivateCard card }'; do
        printf '%s\n' "$use" > "$fixture/consumer/Illegal.qml"
        if python3 "$ROOT/scripts/check-internal-types.py" "$fixture" >/dev/null; then
            fail "internal type lint accepted an external reference: $use"
        fi
    done
)

test_internal_type_boundaries
test_xdg_paths
test_qml_module_lookup
test_quickshell_version_after_qt_warning
test_headless_qml_import_roots
test_hook_timeout_contains_tree

printf 'tooling regression tests passed\n'
