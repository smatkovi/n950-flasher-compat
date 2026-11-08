#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
main_image=${N950_MAIN_IMAGE:-}
output_root=${1:-"$script_dir/stock-ape-root"}

main_sha=79e4976aee22ba2813ead69f329d9840e6b5659843734aaf6724f36b271b8061
ape_sha=6cc83070624ecb19e8ac349acbe83355a3e13ade8881737351c26c8ae6ef3c5a
stock_init_sha=7e4c7c534fe1a9f3726ca3c8a7313b64b4c868ebd4a012106a9fc57bf0d35efc
stock_libc_sha=af74c7fcd7e9ec797d56833b6aa2b3844f26e86ded7382c05d66e94a44d31e2c
ape_body_size=7266800
cpio_offset=2780656
cpio_size=$((ape_body_size - cpio_offset))

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

file_sha() {
    sha256sum -- "$1" | awk '{print $1}'
}

[[ -n $main_image ]] || die "Set N950_MAIN_IMAGE"
[[ -f $main_image ]] || die "Missing Main image: $main_image"
[[ $(file_sha "$main_image") == "$main_sha" ]] ||
    die "Main image has an unexpected SHA-256"
for command_name in 0xFFFF cpio; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name missing"
done

if [[ -d $output_root ]] && find "$output_root" -mindepth 1 -print -quit |
    grep -q .; then
    die "Output directory is not empty: $output_root"
fi

work_dir=$(mktemp -d /tmp/n950-stock-ape.XXXXXX)
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/unpacked" "$output_root"

0xFFFF -n -M "$main_image" -t ape-algo -u "$work_dir/unpacked"
ape="$work_dir/unpacked/ape-algo"
[[ $(file_sha "$ape") == "$ape_sha" ]] ||
    die "Extracted ape-algo has an unexpected SHA-256"

dd if="$ape" iflag=skip_bytes,count_bytes skip="$cpio_offset" \
    count="$cpio_size" status=none |
    (cd "$output_root" && cpio -idmu --quiet --no-absolute-filenames \
        '*init' '*ld-linux.so.3' '*libc.so.6')

[[ $(file_sha "$output_root/init") == "$stock_init_sha" ]] ||
    die "Extracted /init has an unexpected SHA-256"
[[ $(file_sha "$output_root/lib/libc.so.6") == "$stock_libc_sha" ]] ||
    die "Extracted libc has an unexpected SHA-256"

printf 'Extracted and verified stock APE root: %s\n' "$output_root"
