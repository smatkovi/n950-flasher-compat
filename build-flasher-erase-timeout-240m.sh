#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_flasher=${N950_STOCK_FLASHER:-/usr/bin/flasher}
output_flasher=${1:-"$script_dir/flasher-3.12.1-erase240m"}

source_sha=b920f52af030bc53e5020185d1ca62e5f84528d08a2a978f2b1e65379a69c578
target_sha=b961720d131df7e04502350313f2a9bcec460399df2c01a5028b2cf8f33c0a16
timeout_offset=$((0x13bb3))
old_timeout_hex=40771b00       # 1,800,000 ms = 30 minutes, little endian
new_timeout_hex=00badb00       # 14,400,000 ms = 240 minutes, little endian

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

file_sha() {
    sha256sum -- "$1" | awk '{print $1}'
}

[[ -f $source_flasher ]] || die "Original flasher missing: $source_flasher"
[[ $(file_sha "$source_flasher") == "$source_sha" ]] ||
    die "Original flasher has an unexpected SHA-256"

actual_old=$(od -An -v -tx1 -j "$timeout_offset" -N 4 "$source_flasher" |
    tr -d ' \n')
[[ $actual_old == "$old_timeout_hex" ]] ||
    die "Unexpected bytes at timeout offset: $actual_old"

work_file=$(mktemp /tmp/n950-flasher-timeout-240m.XXXXXX)
cleanup() {
    rm -f -- "$work_file"
}
trap cleanup EXIT

cp -- "$source_flasher" "$work_file"
printf '\x00\xba\xdb\x00' |
    dd of="$work_file" bs=1 seek="$timeout_offset" conv=notrunc status=none
chmod 0755 "$work_file"

actual_new=$(od -An -v -tx1 -j "$timeout_offset" -N 4 "$work_file" |
    tr -d ' \n')
[[ $actual_new == "$new_timeout_hex" ]] ||
    die "Timeout patch verification failed: $actual_new"

differences=$(cmp -l "$source_flasher" "$work_file" | wc -l)
[[ $differences == 3 ]] ||
    die "Patch changed $differences bytes instead of exactly 3"
[[ $(file_sha "$work_file") == "$target_sha" ]] ||
    die "Patched flasher has an unexpected SHA-256"

install -m 0755 -- "$work_file" "$output_flasher"
printf 'Created: %s\n' "$output_flasher"
printf 'Erase response timeout: 240 minutes\n'
printf 'SHA-256: %s\n' "$target_sha"
