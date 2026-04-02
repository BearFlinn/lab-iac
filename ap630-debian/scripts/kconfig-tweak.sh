#!/bin/bash
# Quick kernel config tweaker with dependency resolution.
#
# Usage:
#   kconfig-tweak.sh enable  CONFIG_NET CONFIG_TTY
#   kconfig-tweak.sh disable CONFIG_DRM CONFIG_SOUND
#   kconfig-tweak.sh module  CONFIG_BCM4908_ENET
#   kconfig-tweak.sh check   CONFIG_NET CONFIG_TTY
#   kconfig-tweak.sh size
#   kconfig-tweak.sh diff
#   kconfig-tweak.sh search  PATTERN
#
# Environment:
#   KDIR — kernel source dir (default: /tmp/ap630-debian/linux-6.12)

set -euo pipefail

KDIR="${KDIR:-/tmp/ap630-debian/linux-6.12}"
ARCH=arm64
CROSS=aarch64-linux-gnu-
MAX_SIZE=$((16 * 1024 * 1024))

[[ -d "$KDIR" ]] || { echo "No kernel source at $KDIR" >&2; exit 1; }
cd "$KDIR"

norm() { [[ "$1" =~ ^CONFIG_ ]] && echo "$1" || echo "CONFIG_$1"; }

show_size() {
    if [[ -f "arch/$ARCH/boot/Image" ]]; then
        local sz=$(stat -c%s "arch/$ARCH/boot/Image")
        local h=$(( (MAX_SIZE - sz) / 1024 ))
        [[ $sz -gt $MAX_SIZE ]] && echo "Image: $(numfmt --to=iec $sz) — OVER by $(( (sz - MAX_SIZE) / 1024 ))K" \
                                 || echo "Image: $(numfmt --to=iec $sz)/16M (${h}K free)"
    fi
    [[ -f .config ]] && echo "Config: $(grep -c '=y$' .config) built-in, $(grep -c '=m$' .config) modules"
}

check_opts() {
    for opt in "$@"; do
        local o=$(norm "$opt")
        local s=$(grep "^${o}[= ]" .config 2>/dev/null || grep "^# ${o} " .config 2>/dev/null || echo "not found")
        printf "  %-40s %s\n" "$o" "$s"
    done
}

apply() {
    cp .config .config.pre_tweak
    make ARCH=$ARCH CROSS_COMPILE=$CROSS olddefconfig > /dev/null 2>&1
    local changes=$(diff .config.pre_tweak .config | grep '^[<>]' | grep -v '^[<>] #' | head -15)
    [[ -n "$changes" ]] && echo "Deps:" && echo "$changes" | sed 's/^< /  -/; s/^> /  +/'
    rm -f .config.pre_tweak
}

case "${1:-help}" in
    enable)  shift; for o in "$@"; do scripts/config --enable "$(norm "$o")"; done; apply; check_opts "$@"; show_size ;;
    disable) shift; for o in "$@"; do scripts/config --disable "$(norm "$o")"; done; apply; check_opts "$@"; show_size ;;
    module)  shift; for o in "$@"; do scripts/config --module "$(norm "$o")"; done; apply; check_opts "$@"; show_size ;;
    check)   shift; check_opts "$@" ;;
    size)    show_size ;;
    diff)    [[ -f .config.old ]] && diff .config.old .config | grep '^[<>]' | grep -v '^[<>] #' | head -30 || echo "No .config.old" ;;
    search)  shift; grep -rn "config ${1:?pattern}" Kconfig* arch/$ARCH/Kconfig* 2>/dev/null | head -10; grep -i "$1" .config 2>/dev/null | head -10 ;;
    *)       echo "Commands: enable, disable, module, check, size, diff, search" ;;
esac
