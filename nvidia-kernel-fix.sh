#!/usr/bin/env bash
#
# nvidia-kernel-fix
# Install the NVIDIA kernel module matching the currently running Ubuntu kernel.
#
# Supported target: Ubuntu 24.04 LTS (generic HWE kernels).
# This does not purge/reinstall the NVIDIA driver, change PRIME mode, or edit GRUB.

set -Eeuo pipefail

readonly SCRIPT_NAME="nvidia-kernel-fix"
readonly UBUNTU_CODENAME="noble"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo is required. Run as root."
    exec sudo -- "$0" "$@"
fi

[[ -r /etc/os-release ]] || die "Cannot identify operating system."
# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" && "${VERSION_CODENAME:-}" == "$UBUNTU_CODENAME" ]] \
    || die "This script targets Ubuntu 24.04 LTS (noble). Detected: ${PRETTY_NAME:-unknown}."

command -v apt-get >/dev/null 2>&1 || die "apt-get was not found."
command -v dpkg-query >/dev/null 2>&1 || die "dpkg-query was not found."

KERNEL="$(uname -r)"
log "Running kernel: $KERNEL"

# Identify the installed NVIDIA driver branch and kernel-module flavour.
DRIVER_PACKAGE="$(
    dpkg-query -W -f='${binary:Package}\n' 'nvidia-driver-[0-9]*' 2>/dev/null \
    | grep -E '^nvidia-driver-[0-9]+(-open)?(:[^ ]+)?$' \
    | head -n1 || true
)"
[[ -n "$DRIVER_PACKAGE" ]] || die "No installed nvidia-driver package found. Install your NVIDIA driver first."

if [[ "$DRIVER_PACKAGE" =~ ^nvidia-driver-([0-9]+)-open ]]; then
    BRANCH="${BASH_REMATCH[1]}"
    FLAVOUR="open"
    DRIVER_LABEL="${BRANCH}-open"
elif [[ "$DRIVER_PACKAGE" =~ ^nvidia-driver-([0-9]+) ]]; then
    BRANCH="${BASH_REMATCH[1]}"
    FLAVOUR="proprietary"
    DRIVER_LABEL="$BRANCH"
else
    die "Could not parse installed driver package: $DRIVER_PACKAGE"
fi

if [[ "$FLAVOUR" == "open" ]]; then
    MODULE_PACKAGE="linux-modules-nvidia-${BRANCH}-open-${KERNEL}"
    META_PACKAGE="linux-modules-nvidia-${BRANCH}-open-generic-hwe-24.04"
else
    MODULE_PACKAGE="linux-modules-nvidia-${BRANCH}-${KERNEL}"
    META_PACKAGE="linux-modules-nvidia-${BRANCH}-generic-hwe-24.04"
fi

log "Detected NVIDIA driver: $DRIVER_LABEL"
log "Required kernel module package: $MODULE_PACKAGE"

# Refresh package indexes. A third-party repository may fail while Ubuntu's
# package indexes are still usable; do not blindly abort if the exact package
# is already available from the configured Ubuntu repositories.
log "Refreshing APT package indexes..."
if ! apt-get update; then
    warn "apt-get update reported an error. Continuing only if the required Ubuntu package has a candidate."
fi

candidate_for() {
    apt-cache policy "$1" 2>/dev/null \
        | awk '/Candidate:/ { print $2; exit }'
}

CANDIDATE="$(candidate_for "$MODULE_PACKAGE")"

if [[ -z "$CANDIDATE" || "$CANDIDATE" == "(none)" ]]; then
    warn "No candidate for the exact running-kernel package."
    log "Checking HWE meta-package: $META_PACKAGE"
    META_CANDIDATE="$(candidate_for "$META_PACKAGE")"

    if [[ -n "$META_CANDIDATE" && "$META_CANDIDATE" != "(none)" ]]; then
        log "Installing HWE meta-package to pull in matching kernel modules..."
        apt-get install -y "$META_PACKAGE"
    fi

    CANDIDATE="$(candidate_for "$MODULE_PACKAGE")"
fi

[[ -n "$CANDIDATE" && "$CANDIDATE" != "(none)" ]] || die \
    "No APT candidate exists for $MODULE_PACKAGE. Check Ubuntu repositories and kernel/driver compatibility."

log "Installing $MODULE_PACKAGE ($CANDIDATE)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y "$MODULE_PACKAGE"

log "Refreshing module dependencies..."
depmod -a "$KERNEL"

log "Loading NVIDIA kernel module..."
if ! modprobe nvidia; then
    warn "modprobe failed. Check Secure Boot and kernel module build/signing status."
    command -v mokutil >/dev/null 2>&1 && mokutil --sb-state || true
    die "NVIDIA module could not be loaded for kernel $KERNEL."
fi

log "Checking NVIDIA driver communication..."
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi || warn "The module loaded, but nvidia-smi still cannot communicate with the driver."
else
    warn "nvidia-smi is not installed or not in PATH."
fi

log "Checking backlight interfaces..."
if compgen -G '/sys/class/backlight/*' >/dev/null; then
    ls -la /sys/class/backlight/
    log "A backlight interface is present."
else
    warn "No backlight interface is currently exposed."
    warn "If this persists after a reboot, collect: journalctl -b -k | grep -Ei 'nvidia|asus|backlight|wmi'"
fi

printf '\n'
log "Completed. If the NVIDIA module was just installed for this kernel, reboot before testing brightness:"
printf '  sudo reboot\n'
