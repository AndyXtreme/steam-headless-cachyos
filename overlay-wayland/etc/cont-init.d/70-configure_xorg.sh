
# ---------------------------------------------------------------------------
# Wayland variant: this image runs a wlroots (labwc) session, NOT Xorg.
# This file replaces the upstream X11 configuration script and simply makes
# sure none of the X-server supervisor programs auto-start. XWayland is started
# on demand by labwc for X11 clients (Steam, Sunshine X capture, etc.).
# ---------------------------------------------------------------------------

print_header "Configure display backend (Wayland / labwc)"

# Disable the X11 server programs - they are not used on this image.
for _ini in xorg xvfb; do
    if [ -f "/etc/supervisor.d/${_ini}.ini" ]; then
        sed -i 's|^autostart.*=.*$|autostart=false|' "/etc/supervisor.d/${_ini}.ini"
        print_step_header "Disabled X11 program '${_ini}'"
    fi
done

# Disable the X11 vnc capture program if it still exists (replaced by wayvnc).
if [ -f /etc/supervisor.d/x11vnc.ini ]; then
    sed -i 's|^autostart.*=.*$|autostart=false|' /etc/supervisor.d/x11vnc.ini
fi

# Ensure the shared X11 socket dir exists for XWayland.
mkdir -p "${XORG_SOCKET_DIR:-/tmp/.X11-unix}"
chmod 1777 "${XORG_SOCKET_DIR:-/tmp/.X11-unix}" 2>/dev/null || true
mkdir -p /tmp/.ICE-unix
chmod 1777 /tmp/.ICE-unix 2>/dev/null || true

echo -e "\e[34mDONE\e[0m"
