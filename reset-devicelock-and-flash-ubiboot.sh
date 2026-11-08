#!/usr/bin/env bash
set -Eeuo pipefail
umask 022
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
config_file=${N950_CONFIG:-"$script_dir/n950-local.conf"}

die() {
    printf 'ABORT: %s\n' "$*" >&2
    exit 1
}

[[ -r $config_file ]] ||
    die "Missing configuration: copy n950-local.conf.example to n950-local.conf"
# This is an intentionally shell-compatible local configuration.  Only source
# a file you trust, especially because the destructive run executes as root.
# shellcheck source=/dev/null
source "$config_file"

device_id=${N950_DEVICE_ID:-}
stock_flasher=${N950_STOCK_FLASHER:-/usr/bin/flasher}
long_flasher=${N950_LONG_FLASHER:-"$script_dir/flasher-3.12.1-erase240m"}
ape_image=${N950_ACK_APE:-"$script_dir/ape-algo-moslo-fs-erase-ack.bin"}
main_image=${N950_MAIN_IMAGE:-}
emmc_image=${N950_EMMC_IMAGE:-}
ubiboot_image=${N950_UBIBOOT_IMAGE:-}

stock_flasher_sha=${N950_STOCK_FLASHER_SHA256:-b920f52af030bc53e5020185d1ca62e5f84528d08a2a978f2b1e65379a69c578}
long_flasher_sha=${N950_LONG_FLASHER_SHA256:-b961720d131df7e04502350313f2a9bcec460399df2c01a5028b2cf8f33c0a16}
ape_sha=${N950_ACK_APE_SHA256:-ef7b90e02ba830a918e2daffab503c42e45b79e033a2c290d92b48d700d2e3c1}
main_sha=${N950_MAIN_SHA256:-79e4976aee22ba2813ead69f329d9840e6b5659843734aaf6724f36b271b8061}
emmc_sha=${N950_EMMC_SHA256:-de60a8801f4c44daa4f8fee3198be0667555270e98729faf761cab41a2e5d399}
ubiboot_sha=${N950_UBIBOOT_SHA256:-5b3a93bc75b26356ae981c4a02d7d91598b616257cf03255be2f5a32a9547e13}
expected_device="Device identifier: $device_id (SN: N/A)"

log_dir="$script_dir/logs"
run_stamp=$(date '+%Y%m%d-%H%M%S')-$$
run_log="$log_dir/ack-erased-reset-ubiboot-$run_stamp.log"
launch_log="$script_dir/ack-erased-reset-ubiboot-launch.log"

file_sha() {
    sha256sum -- "$1" | awk '{print $1}'
}

require_sha() {
    local file=$1 expected=$2 actual
    [[ -f $file ]] || die "Missing file: $file"
    actual=$(file_sha "$file")
    [[ $actual == "$expected" ]] ||
        die "SHA-256 mismatch for $file (got $actual, expected $expected)"
}

flasher_running() {
    pgrep -f '(^|/)(flasher|flasher-[^[:space:]/]+)([[:space:]]|$)' \
        >/dev/null 2>&1
}

preflight() {
    local command_name
    [[ $device_id =~ ^[0-9]{15}$ ]] ||
        die "N950_DEVICE_ID must contain exactly 15 decimal digits"
    [[ -n $main_image ]] || die "Set N950_MAIN_IMAGE in $config_file"
    [[ -n $emmc_image ]] || die "Set N950_EMMC_IMAGE in $config_file"
    [[ -n $ubiboot_image ]] || die "Set N950_UBIBOOT_IMAGE in $config_file"

    for command_name in \
        sha256sum awk timeout tee grep sed date sleep flock pgrep mkdir touch \
        nohup rm setsid systemd-inhibit mktemp; do
        command -v "$command_name" >/dev/null 2>&1 ||
            die "Missing program: $command_name"
    done

    require_sha "$stock_flasher" "$stock_flasher_sha"
    require_sha "$long_flasher" "$long_flasher_sha"
    require_sha "$ape_image" "$ape_sha"
    require_sha "$main_image" "$main_sha"
    require_sha "$emmc_image" "$emmc_sha"
    require_sha "$ubiboot_image" "$ubiboot_sha"
    [[ -x $stock_flasher ]] || die "Not executable: $stock_flasher"
    [[ -x $long_flasher ]] || die "Not executable: $long_flasher"
}

run_stage() {
    local stage=$1 stage_log="$log_dir/$1-$run_stamp.log" rc tee_rc
    local -a statuses
    shift
    printf '\n===== %s =====\n' "$stage"
    set +e
    "$@" 2>&1 | tee "$stage_log"
    statuses=("${PIPESTATUS[@]}")
    rc=${statuses[0]}
    tee_rc=${statuses[1]}
    set -e
    (( tee_rc == 0 )) || die "$stage could not write its control log"
    (( rc == 0 )) || die "$stage exited with status $rc; stopping"
    grep -aFq 'Success' "$stage_log" ||
        die "$stage did not report Success; stopping"
    grep -aFq "$expected_device" "$stage_log" ||
        die "$stage did not report the configured device identifier"
    if grep -aEq 'ERROR:|Security failure|Devicelock ON|Failed to flash' \
        "$stage_log"; then
        die "$stage logged an error/security marker despite its exit status"
    fi
}

identify_target() {
    local probe_log="$log_dir/ack-erased-identify-$run_stamp.log" rc tee_rc
    local -a statuses

    printf '\n===== read-only target check =====\n'
    set +e
    timeout -k 5s 45s "$stock_flasher" \
        --suppress-warranty-warning -i 2>&1 | tee "$probe_log"
    statuses=("${PIPESTATUS[@]}")
    rc=${statuses[0]}
    tee_rc=${statuses[1]}
    set -e
    (( tee_rc == 0 )) || die "Target check could not write its log"
    (( rc == 0 )) || die "Target check exited with status $rc"
    grep -aFq "$expected_device" "$probe_log" ||
        die "Target check did not find the configured device identifier"
    grep -aFq 'Found device RM-680' "$probe_log" ||
        die "Target is not freshly in the RM-680 bootloader (NOLO)"
    grep -aFq 'NOLO version' "$probe_log" ||
        die "Target check found no NOLO bootloader"
    grep -aFq 'Success' "$probe_log" ||
        die "Target check did not report Success"
}

print_semantic_warning() {
    printf '%s\n' \
        'WARNING: this run does not perform a new secure eMMC erase.' \
        'It acknowledges only the exact complete RM-680 user area' \
        '(offset 0, length 15,896,412,160 bytes) as already erased.' \
        'A genuine Nokia DeviceLock reset and destructive signed full flash' \
        'follow; UbiBoot is attempted only if those stages succeed.'
}

run_sequence() {
    (( EUID == 0 )) || die "Run the destructive mode through sudo"
    [[ ${N950_ACK_ERASED_CONFIRMED:-} == I_UNDERSTAND_NO_NEW_SECURE_ERASE ]] ||
        die "Internal run is missing the exact ack-erased confirmation"
    preflight
    exec 9>/run/lock/n950-flasher-compat.lock
    flock -n 9 || die "Another N950 compatibility run is active"
    flasher_running && die "Another flasher process is active"

    mkdir -p -- "$log_dir"
    touch -- "$run_log"
    exec > >(tee -a "$run_log") 2>&1

    printf 'N950 ack-erased recovery started: %s\n' "$(date --iso-8601=seconds)"
    printf 'Log: %s\n' "$run_log"
    print_semantic_warning
    if [[ -n ${N950_READY_FILE:-} ]]; then
        printf '%d\n' "$$" >"$N950_READY_FILE"
    fi

    identify_target
    preflight
    flasher_running && die "Another flasher appeared before full flash"

    # The hook acknowledges only the exact RM-680 full-device secure-discard
    # range.  Unmodified softupd then performs bb5_devlock_reset/save_secs and
    # the signed Main+eMMC update.  Do not reboot before the UbiBoot gate test.
    run_stage ack-erased-devicelock-reset-and-signed-fullflash-no-reboot \
        "$long_flasher" \
        -a "$ape_image" \
        -F "$main_image" \
        -F "$emmc_image" \
        --erase-user-data=secure \
        -f

    preflight
    flasher_running && die "Another flasher appeared before UbiBoot"

    # DeviceLock ON rejects this unsigned kernel.  Success is both the
    # practical security-gate test and the requested persistent mtd2 write.
    run_stage persistent-ubiboot-flash-after-ack-erased-reset \
        "$long_flasher" \
        -a "$ape_image" \
        -k "$ubiboot_image" \
        --flash-only=kernel \
        -f -R

    printf '\nDONE: UbiBoot was flashed persistently and reboot requested.\n'
    printf 'The intended final state is Open/Untrusted with UbiBoot.\n'
}

case ${1:-} in
    --check)
        preflight
        print_semantic_warning
        printf 'Check OK. No device access; nothing erased or flashed.\n'
        ;;
    --run-internal)
        run_sequence
        ;;
    --arm-acknowledge-already-erased)
        (( EUID == 0 )) || die "Run this mode with sudo"
        preflight
        flasher_running && die "Another flasher process is active"
        print_semantic_warning
        ready_file=$(mktemp -p /run/lock n950-ack-erased-ready.XXXXXX)
        N950_CONFIG="$config_file" \
        N950_READY_FILE="$ready_file" \
        N950_ACK_ERASED_CONFIRMED=I_UNDERSTAND_NO_NEW_SECURE_ERASE \
        nohup setsid systemd-inhibit \
            --what=sleep:shutdown:idle \
            --who=n950-flasher-compat \
            --why='N950 DeviceLock reset, signed full flash, and UbiBoot must not be interrupted' \
            --mode=block \
            "$script_dir/reset-devicelock-and-flash-ubiboot.sh" \
            --run-internal \
            </dev/null >"$launch_log" 2>&1 &
        child_pid=$!
        ready=0
        for _ in {1..480}; do
            if [[ -s $ready_file ]]; then
                ready=1
                break
            fi
            kill -0 "$child_pid" 2>/dev/null || break
            sleep 0.25
        done
        if (( ready == 0 )); then
            kill -TERM -- "-$child_pid" 2>/dev/null ||
                kill "$child_pid" 2>/dev/null || true
            wait "$child_pid" 2>/dev/null || true
            [[ -r $launch_log ]] && sed -n '1,160p' "$launch_log" >&2
            rm -f -- "$ready_file"
            die "Detached child stopped before readiness"
        fi
        rm -f -- "$ready_file"
        printf 'Automatic recovery started, PID %d.\n' "$child_pid"
        printf 'Launch/error log: %s\n' "$launch_log"
        printf 'Detailed logs: %s\n' "$log_dir"
        ;;
    *)
        die "Usage: $0 --check|--arm-acknowledge-already-erased"
        ;;
esac
