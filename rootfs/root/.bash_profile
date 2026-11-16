[ -f ~/.bashrc ] && . ~/.bashrc
# Auto-start sway on the tty1 autologin VT (guarded so ssh sessions are unaffected).
# r8q-gpu.service loads msm after multi-user, so wait briefly for the render node;
# if it never appears, stay at a shell (an instantly-dying exec sway crash-loops getty).
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    for i in $(seq 1 30); do
        [ -e /dev/dri/renderD128 ] && ls -l /sys/class/drm/card*/device/driver 2>/dev/null |
            grep -q msm_dpu && break
        sleep 1
    done
    if [ -e /dev/dri/renderD128 ]; then
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
        # Render on Adreno 650 (turnip), scan out on the msm display (DSI panel).
        # Card numbers vary (simpledrm comes and goes), so find it by driver.
        for c in /sys/class/drm/card[0-9]*; do
            [ "$(basename "$(readlink -f "$c/device/driver")")" = msm_dpu ] &&
                export WLR_DRM_DEVICES=/dev/dri/${c##*/}
        done
        export WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128
        export WLR_RENDERER=${R8Q_WLR_RENDERER:-vulkan}
        export XKB_DEFAULT_LAYOUT=us
        exec sway -d > /tmp/sway.log 2>&1
    fi
fi
