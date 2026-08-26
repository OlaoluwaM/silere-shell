# shellcheck shell=bash
# Shared by install.sh and uninstall.sh: one set of status lines and one TTY test.

if [ -t 1 ]; then
    R='\033[0m' BOLD='\033[1m'
    GREEN='\033[0;32m' CYAN='\033[0;36m' YELLOW='\033[1;33m' DIM='\033[2m' RED='\033[0;31m'
else
    R='' BOLD='' GREEN='' CYAN='' YELLOW='' DIM='' RED=''
fi

# shellcheck disable=SC2059
_ok()   { printf "    ${GREEN}ok${R}      %s\n" "$*"; }
# shellcheck disable=SC2059
_skip() { printf "    ${DIM}skip${R}    %s\n" "$*"; }
# shellcheck disable=SC2059
_warn() { printf "    ${YELLOW}warn${R}    %s\n" "$*"; }
# shellcheck disable=SC2059
_err()  { printf "    ${RED}error${R}   %s\n" "$*" >&2; }
_die()  { _err "$*"; exit 1; }
# shellcheck disable=SC2059
_info() { printf "  ${CYAN}::${R}  %s\n" "$*"; }
# shellcheck disable=SC2059
_section() { printf "\n${BOLD}==> %s${R}\n" "$1"; }

# -r only stats the device node: it succeeds with no controlling terminal, where
# opening it fails with ENXIO. Open it for real, or every prompt dies on an unset
# reply instead of reporting the missing terminal.
_need_tty() { # $1 = what to tell the user to do instead
    { : </dev/tty; } 2>/dev/null || _die "$1"
}
