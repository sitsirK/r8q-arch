# Device tree

The r8q device tree is **upstream** since Linux 6.18 (`sm8250-samsung-r8q.dts` +
`sm8250-samsung-common.dtsi`). These are the complete source files with our
additions: drop them into a mainline kernel tree at `arch/arm64/boot/dts/qcom/`
and build the DTB. The kernel loads `r8q.dtb` from the ESP (INSTALLATION §5) —
not the copy embedded in Mu-Silicium (`scripts/build-uefi.sh`), and there is no
fallback to it.

## Display

**`sm8250-samsung-r8q.dts` — mainline msm-drm (the display block at the end).**
Enables `mdss`, DSI0 and its 7nm PHY with the S6E3FC3 panel at `panel@0`
(reset tlmm 82, TE on tlmm 66 as `mdp_vsync`, vdd3 from a tlmm 93 switched
fixed regulator), and deletes the two `simpledrm` workarounds below, because
`msm` needs the display clocks and `MDSS_GDSC` itself. Needs `patches/0010`–`0012`
and three modules; see INSTALLATION §13, including how to check which of the
r8q's three panels you have.

**`sm8250-samsung-common.dtsi` — the `simpledrm` setup** (still what the
common file describes, and what you keep on a panel without a driver). It keeps
the firmware-lit framebuffer alive:

1. `&dispcc { protected-clocks = <0 … 57>; }` — dispcc stays **enabled** (so it
   probes and `fw_devlink` is satisfied; disabling the node hangs boot) but
   never touches the clocks Samsung's bootloader left driving the DSI scanout.
2. `framebuffer@9c000000 { power-domains = <&dispcc MDSS_GDSC>; }` — makes
   `simpledrm` a consumer of the MDSS GDSC so genpd never powers it off
   (`pd_ignore_unused` does *not* cover it; the panel freezes ~13 s in
   otherwise). **No `clocks` in this node** — adding them hangs boot.

Either way, boot with `simpledrm` enabled and the cmdline in
[`../config/cmdline.txt`](../config/cmdline.txt) (`clk_ignore_unused
pd_ignore_unused arm-smmu.disable_bypass=0`).
