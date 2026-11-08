#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
main_image=${N950_MAIN_IMAGE:-}
moslo_image=${N950_MOSLO_IMAGE:-}
stock_root=${N950_STOCK_ROOT:-}
output_image=${1:-"$script_dir/ape-algo-moslo-fs.bin"}

main_sha=79e4976aee22ba2813ead69f329d9840e6b5659843734aaf6724f36b271b8061
moslo_sha=d45fe8a67ba71d3a4b2e6dcaf5dd621ace44031211eaeda32d9ed47f68ea1a9d
ape_sha=6cc83070624ecb19e8ac349acbe83355a3e13ade8881737351c26c8ae6ef3c5a
moslo_uncompressed_sha=c793f86d707b5db41e95acfa42a172298a0e7fdc372001380666b780ada7c9ed
stock_dosfslabel_sha=1bd6984ec1bf45d4a08afe3037dfb6d61930c3687676224b9cd8de7a3ef8c7d2

ape_body_size=7266800
ape_footer_size=16
moslo_cpio_offset=137536
moslo_cpio_size=6240256

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

file_sha() {
    sha256sum -- "$1" | awk '{print $1}'
}

require_sha() {
    local file=$1 expected=$2 actual
    [[ -f $file ]] || die "Missing file: $file"
    actual=$(file_sha "$file")
    [[ $actual == "$expected" ]] ||
        die "Unexpected SHA-256 for $file (got $actual, expected $expected)"
}

copy_checked() {
    local source=$1 destination=$2 expected=$3
    require_sha "$source" "$expected"
    mkdir -p -- "$(dirname -- "$destination")"
    cp -L -- "$source" "$destination"
    chmod 0755 -- "$destination"
}

[[ -n $main_image ]] || die "Set N950_MAIN_IMAGE"
[[ -n $moslo_image ]] || die "Set N950_MOSLO_IMAGE"
[[ -n $stock_root ]] || die "Set N950_STOCK_ROOT"
for command_name in 0xFFFF binwalk cpio; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name missing"
done
require_sha "$main_image" "$main_sha"
require_sha "$moslo_image" "$moslo_sha"
require_sha "$stock_root/sbin/dosfslabel" "$stock_dosfslabel_sha"

work_dir=$(mktemp -d /tmp/n950-ape-tools.XXXXXX)
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/ape" "$work_dir/moslo" "$work_dir/moslo-root" \
    "$work_dir/overlay"

0xFFFF -n -M "$main_image" -t ape-algo -u "$work_dir/ape"
ape="$work_dir/ape/ape-algo"
require_sha "$ape" "$ape_sha"
[[ $(stat -c %s -- "$ape") == $((ape_body_size + ape_footer_size)) ]] ||
    die "Unexpected ape-algo size"

binwalk -e -C "$work_dir/moslo" "$moslo_image"
moslo_uncompressed=$(find "$work_dir/moslo" -type f \
    -path '*/3E4A/decompressed.bin' -print -quit)
[[ -n $moslo_uncompressed ]] || die "Could not unpack MOSLO kernel"
require_sha "$moslo_uncompressed" "$moslo_uncompressed_sha"

dd if="$moslo_uncompressed" iflag=skip_bytes,count_bytes \
    skip="$moslo_cpio_offset" count="$moslo_cpio_size" status=none |
    (cd "$work_dir/moslo-root" && cpio -idmu --quiet --no-absolute-filenames \
        'sbin/mkfs.ext4' \
        'lib/ld-linux.so.3' \
        'lib/libext2fs.so.2' \
        'lib/libcom_err.so.2' \
        'usr/lib/libblkid.so.1' \
        'usr/lib/libuuid.so.1' \
        'lib/libe2p.so.2' \
        'lib/libgcc_s.so.1' \
        'lib/libc.so.6' \
        'lib/libpthread.so.0')

overlay="$work_dir/overlay"
install -D -m 0755 "$script_dir/ape-overlay/sbin/mkfs.ext3" \
    "$overlay/sbin/mkfs.ext3"
install -D -m 0755 "$script_dir/ape-overlay/sbin/dosfslabel" \
    "$overlay/sbin/dosfslabel"
install -D -m 0644 "$script_dir/ape-overlay/etc/ape-algo-fs-tools" \
    "$overlay/etc/ape-algo-fs-tools"

# The hardware-tested reference overlay has one final empty line in these
# three text files.  Keep the tracked sources tidy and reproduce that byte here.
for text_file in \
    "$overlay/sbin/mkfs.ext3" \
    "$overlay/sbin/dosfslabel" \
    "$overlay/etc/ape-algo-fs-tools"; do
    printf '\n' >> "$text_file"
done

copy_checked "$work_dir/moslo-root/sbin/mkfs.ext4" \
    "$overlay/opt/moslo/sbin/mkfs.ext4" \
    80f0349b7cfd623f2dbd134532885b9d628132e4b01f15a70170e6fe85aa16ac
copy_checked "$stock_root/sbin/dosfslabel" \
    "$overlay/opt/moslo/sbin/dosfslabel" "$stock_dosfslabel_sha"
copy_checked "$work_dir/moslo-root/lib/ld-linux.so.3" \
    "$overlay/opt/moslo/lib/ld-linux.so.3" \
    26dc19d78eb44f866e96a9b31ac6664d47607c45d8d510a915faaa904d28baf4
copy_checked "$work_dir/moslo-root/lib/libext2fs.so.2" \
    "$overlay/opt/moslo/lib/libext2fs.so.2" \
    d8e45968bd4340cfeb6ae2602ec6c626139f08fec9ef871510669b6422698f1f
copy_checked "$work_dir/moslo-root/lib/libcom_err.so.2" \
    "$overlay/opt/moslo/lib/libcom_err.so.2" \
    74fb91212aba4c2b701d3f0b2997b9524422586737a297541cb17ba2888efac4
copy_checked "$work_dir/moslo-root/usr/lib/libblkid.so.1" \
    "$overlay/opt/moslo/lib/libblkid.so.1" \
    9cb8a297658dcb4bce56530028151d811d048e96d91ff909cf5c99a91d232bcf
copy_checked "$work_dir/moslo-root/usr/lib/libuuid.so.1" \
    "$overlay/opt/moslo/lib/libuuid.so.1" \
    d9df2f554922f78360c903ccef56bad1d05d45ad641e18bcf852594e7990c433
copy_checked "$work_dir/moslo-root/lib/libe2p.so.2" \
    "$overlay/opt/moslo/lib/libe2p.so.2" \
    44754de5a03063d5284f328d550d0127078ffd29c0414659599e8de88f54dff5
copy_checked "$work_dir/moslo-root/lib/libgcc_s.so.1" \
    "$overlay/opt/moslo/lib/libgcc_s.so.1" \
    5d634917dc1a4f3455d489585be6d6f1508cfec189fd1ef7e05b4fae6f9f5856
copy_checked "$work_dir/moslo-root/lib/libc.so.6" \
    "$overlay/opt/moslo/lib/libc.so.6" \
    1904e0069714e5036cb161ed96931a2735c806cebd68e3adecce90feba90e651
copy_checked "$work_dir/moslo-root/lib/libpthread.so.0" \
    "$overlay/opt/moslo/lib/libpthread.so.0" \
    65e5b8e86a632ea054af8ed7cf41e12e36d8b36e7fac1b334e8e62329dcc1005

find "$overlay" -exec touch -h -d '@0' -- {} +
(cd "$overlay" && find . -print0 | LC_ALL=C sort -z |
    cpio --null -o --quiet --format=newc --owner=0:0 --reproducible) \
    > "$work_dir/overlay.cpio"

dd if="$ape" of="$work_dir/result.bin" iflag=count_bytes \
    count="$ape_body_size" status=none
dd if="$work_dir/overlay.cpio" of="$work_dir/result.bin" \
    oflag=append conv=notrunc status=none
dd if="$ape" of="$work_dir/result.bin" iflag=skip_bytes,count_bytes \
    skip="$ape_body_size" count="$ape_footer_size" \
    oflag=append conv=notrunc status=none

cmp -n "$ape_body_size" -- "$ape" "$work_dir/result.bin" ||
    die "APE prefix changed"
tail -c "$ape_footer_size" "$work_dir/result.bin" > "$work_dir/result.footer"
tail -c "$ape_footer_size" "$ape" > "$work_dir/original.footer"
cmp -s -- "$work_dir/original.footer" "$work_dir/result.footer" ||
    die "APE footer changed"

overlay_offset=$ape_body_size
overlay_size=$(stat -c %s -- "$work_dir/overlay.cpio")
mkdir -p "$work_dir/verify"
dd if="$work_dir/result.bin" iflag=skip_bytes,count_bytes \
    skip="$overlay_offset" count="$overlay_size" status=none |
    (cd "$work_dir/verify" && cpio -idmu --quiet --no-absolute-filenames)
require_sha "$work_dir/verify/opt/moslo/sbin/mkfs.ext4" \
    80f0349b7cfd623f2dbd134532885b9d628132e4b01f15a70170e6fe85aa16ac
require_sha "$work_dir/verify/opt/moslo/sbin/dosfslabel" \
    "$stock_dosfslabel_sha"
cmp -s -- "$overlay/sbin/mkfs.ext3" "$work_dir/verify/sbin/mkfs.ext3" ||
    die "mkfs wrapper roundtrip failed"
cmp -s -- "$overlay/sbin/dosfslabel" "$work_dir/verify/sbin/dosfslabel" ||
    die "dosfslabel wrapper roundtrip failed"

install -m 0644 -- "$work_dir/result.bin" "$output_image"
printf '\nCreated and verified:\n  %s\n  Size: %s bytes\n  SHA-256: %s\n' \
    "$output_image" "$(stat -c %s -- "$output_image")" \
    "$(file_sha "$output_image")"
