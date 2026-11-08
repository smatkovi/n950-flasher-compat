#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
parent_dir=$(dirname -- "$script_dir")
ape_root=${N950_APE_ROOT:-}
output_image=${1:-"$parent_dir/ape-algo-moslo-fs-erase-ack.bin"}
footer_size=16
stock_init_sha=7e4c7c534fe1a9f3726ca3c8a7313b64b4c868ebd4a012106a9fc57bf0d35efc
expected_output_sha=ef7b90e02ba830a918e2daffab503c42e45b79e033a2c290d92b48d700d2e3c1

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

file_sha() {
    sha256sum -- "$1" | awk '{print $1}'
}

[[ -n $ape_root ]] || die "Set N950_APE_ROOT to the extracted stock APE initramfs"
for command_name in clang ld.lld cpio qemu-arm readelf sed grep; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name missing"
done
[[ $(file_sha "$ape_root/init") == "$stock_init_sha" ]] ||
    die "Unexpected original APE /init"
[[ -f $ape_root/lib/libc.so.6 ]] || die "Missing $ape_root/lib/libc.so.6"

work_dir=$(mktemp -d /tmp/n950-erase-ack-ape.XXXXXX)
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/overlay/opt/n950-secure" "$work_dir/verify"

"$parent_dir/build-patched-ape.sh" "$work_dir/base.bin"

clang --target=armv7a-linux-gnueabihf -march=armv7-a -marm \
    -fPIC -ffreestanding -fno-builtin -fno-stack-protector \
    -fvisibility=hidden -Oz -c \
    "$script_dir/liberase-ack.c" -o "$work_dir/liberase-ack.o"
ld.lld -shared --hash-style=both --soname=libsecure-discard.so \
    --allow-shlib-undefined "$work_dir/liberase-ack.o" \
    -o "$work_dir/overlay/opt/n950-secure/libsecure-discard.so"

# Generate the modified init from the user's byte-verified Nokia original.
# This repository does not redistribute that vendor file.
[[ $(grep -cFx '/usr/sbin/softupd -s --allpower &' "$ape_root/init") == 1 ]] ||
    die "Original init does not contain exactly one expected softupd line"
sed 's|^/usr/sbin/softupd -s --allpower &$|LD_PRELOAD=/opt/n950-secure/libsecure-discard.so /usr/sbin/softupd -s --allpower \&|' \
    "$ape_root/init" > "$work_dir/overlay/init"
chmod 0755 "$work_dir/overlay/init"
grep -Fqx 'LD_PRELOAD=/opt/n950-secure/libsecure-discard.so /usr/sbin/softupd -s --allpower &' \
    "$work_dir/overlay/init" || die "Could not inject the preload line"
chmod 0755 "$work_dir/overlay/opt/n950-secure/libsecure-discard.so"

readelf -h "$work_dir/overlay/opt/n950-secure/libsecure-discard.so" |
    grep -q 'Machine:.*ARM' || die "Erase-ack hook is not ARM ELF"
readelf -Ws "$work_dir/overlay/opt/n950-secure/libsecure-discard.so" |
    grep -Eq 'GLOBAL +DEFAULT +[0-9]+ +ioctl$' ||
    die "Erase-ack hook does not export ioctl"
for import_name in __errno_location unsetenv; do
    readelf -Ws "$work_dir/overlay/opt/n950-secure/libsecure-discard.so" |
        grep -Eq "UND +${import_name}$" ||
        die "Expected libc import missing: $import_name"
done

# Exact full-device range succeeds without a syscall; one sector short fails
# with EINVAL; unrelated BLKDISCARD still reaches the real syscall.
clang --target=armv7a-linux-gnueabihf -march=armv7-a -marm \
    -fPIC -ffreestanding -fno-builtin -fno-stack-protector -Oz -c \
    "$script_dir/test_erase_ack_ioctl.c" -o "$work_dir/test_erase_ack_ioctl.o"
ld.lld -dynamic-linker /lib/ld-linux.so.3 -e _start --hash-style=both \
    "$work_dir/test_erase_ack_ioctl.o" "$ape_root/lib/libc.so.6" \
    -o "$work_dir/test_erase_ack_ioctl"
qemu-arm -strace -L "$ape_root" \
    -E LD_PRELOAD="$work_dir/overlay/opt/n950-secure/libsecure-discard.so" \
    "$work_dir/test_erase_ack_ioctl" > "$work_dir/qemu-trace" 2>&1 ||
    die "QEMU erase-ack test failed"
grep -Fq 'ioctl(1,BLKDISCARD' "$work_dir/qemu-trace" ||
    die "QEMU did not see the pass-through control ioctl"
if grep -Fq 'ioctl(1,BLKSECDISCARD' "$work_dir/qemu-trace"; then
    die "BLKSECDISCARD unexpectedly reached the kernel"
fi

find "$work_dir/overlay" -exec touch -h -d '@0' -- {} +
(cd "$work_dir/overlay" && find . -print0 | LC_ALL=C sort -z |
    cpio --null -o --quiet --format=newc --owner=0:0 --reproducible) \
    > "$work_dir/erase-ack-overlay.cpio"

base_size=$(stat -c %s -- "$work_dir/base.bin")
(( base_size > footer_size )) || die "Base APE is too small"
body_size=$((base_size - footer_size))
dd if="$work_dir/base.bin" of="$work_dir/result.bin" \
    iflag=count_bytes count="$body_size" status=none
dd if="$work_dir/erase-ack-overlay.cpio" of="$work_dir/result.bin" \
    oflag=append conv=notrunc status=none
dd if="$work_dir/base.bin" of="$work_dir/result.bin" \
    iflag=skip_bytes,count_bytes skip="$body_size" count="$footer_size" \
    oflag=append conv=notrunc status=none

overlay_size=$(stat -c %s -- "$work_dir/erase-ack-overlay.cpio")
dd if="$work_dir/result.bin" iflag=skip_bytes,count_bytes \
    skip="$body_size" count="$overlay_size" status=none |
    (cd "$work_dir/verify" && cpio -idmu --quiet --no-absolute-filenames)
cmp -s "$work_dir/overlay/init" "$work_dir/verify/init" ||
    die "Patched init roundtrip failed"
cmp -s "$work_dir/overlay/opt/n950-secure/libsecure-discard.so" \
    "$work_dir/verify/opt/n950-secure/libsecure-discard.so" ||
    die "Erase-ack hook roundtrip failed"
cmp -n "$body_size" "$work_dir/base.bin" "$work_dir/result.bin" ||
    die "Base APE changed"
cmp -s <(tail -c "$footer_size" "$work_dir/base.bin") \
    <(tail -c "$footer_size" "$work_dir/result.bin") ||
    die "APE footer changed"

[[ $(file_sha "$work_dir/result.bin") == "$expected_output_sha" ]] ||
    die "Final output is not the hardware-tested deterministic image"
install -m 0644 "$work_dir/result.bin" "$output_image"
printf '\nCreated and verified:\n  %s\n  Size: %s bytes\n  SHA-256: %s\n' \
    "$output_image" "$(stat -c %s -- "$output_image")" \
    "$(file_sha "$output_image")"
