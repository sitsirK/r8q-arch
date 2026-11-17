#!/usr/bin/env bash
#
# Embed our kernel-built DTB into Mu-Silicium and build the UEFI boot image.
# The firmware carries a copy of the DTB (with the display fix: dispcc
# protected-clocks + framebuffer MDSS_GDSC power-domain). The kernel itself boots
# from ESP:/r8q.dtb (cmdline `dtb=r8q.dtb`, see scripts/deploy-esp.sh), so later
# DTB changes go to the ESP and do NOT need a re-flash.
#
# Env: MUSIL=<Mu-Silicium checkout>  DTB=<out/.../sm8250-samsung-r8q.dtb>
set -euo pipefail
MUSIL="${MUSIL:?set MUSIL to your Mu-Silicium checkout}"
DTB="${DTB:?set DTB to out/arch/arm64/boot/dts/qcom/sm8250-samsung-r8q.dtb}"
VENV="${VENV:-$MUSIL/../.venv}"   # python venv with Mu-Silicium pip-requirements
PY="$VENV/bin/python"; [ -x "$PY" ] || PY=python3   # setup_env.sh installs them system-wide

mkdir -p "$MUSIL/Platforms/Samsung/r8qPkg/FdtBlob"
cp "$DTB" "$MUSIL/Platforms/Samsung/r8qPkg/FdtBlob/sm8250-samsung-r8q.dtb"
( cd "$MUSIL" && "$PY" build_uefi.py -d r8q )
echo "[+] $MUSIL/Mu-r8q.img built (embeds the display-fix DTB). Flash with scripts/flash.sh"
