#!/usr/bin/env bash
# Build mainline kernel Image + r8q DTB.
# Usage: ./build_kernel.sh [clean]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

cd "$(dirname "$0")/kernel"
export ARCH=arm64 LLVM=1
OUT=../out

[ "${1:-}" = "clean" ] && rm -rf "$OUT"

# Apply the r8q kernel patches (idempotent; skips ones already applied).
# 0002 (zap via dma_alloc) is required for GPU acceleration — see INSTALLATION.md §9.
for p in "$REPO"/patches/*.patch; do
    if patch -p1 -N --dry-run < "$p" > /dev/null 2>&1; then
        echo "Applying $(basename "$p")"
        patch -p1 < "$p"
    else
        echo "Skipping $(basename "$p") (already applied?)"
    fi
done

make O="$OUT" defconfig
../kernel/scripts/kconfig/merge_config.sh -O "$OUT" -m "$OUT/.config" ../r8q_bringup.config
make O="$OUT" olddefconfig

make O="$OUT" -j"$(nproc)" Image.gz dtbs qcom/sm8250-samsung-r8q-simpledrm.dtb
make O="$OUT" -j"$(nproc)" modules

ls -la "$OUT/arch/arm64/boot/Image.gz" "$OUT/arch/arm64/boot/dts/qcom/sm8250-samsung-r8q.dtb"
