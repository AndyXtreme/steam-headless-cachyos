#!/usr/bin/env bash
###
# File: start-wayland-session.sh
# Project: bin
# Starts a headless labwc (wlroots) Wayland session for steam-headless.
# Exposes:
#   - WAYLAND_DISPLAY ......... for wayvnc + Wayland-native apps
#   - DISPLAY (XWayland) ...... for X11 apps (Steam, Sunshine X capture)
# and writes /tmp/.wayland-session.env so sibling services can attach.
###
set -e
source /usr/bin/common-functions.sh

# CATCH TERM SIGNAL:
_term() {
    kill -TERM "$labwc_pid" 2>/dev/null
}
trap _term SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Session environment
# ---------------------------------------------------------------------------
rm -f /tmp/.started-desktop /tmp/.wayland-session.env

export USER_HOME="${USER_HOME:-/home/${USER:?}}"
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

export XDG_CACHE_HOME="${USER_HOME}/.cache"
export XDG_CONFIG_HOME="${USER_HOME}/.config"
export XDG_DATA_HOME="${USER_HOME}/.local/share"
export XDG_SESSION_TYPE="wayland"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-labwc:wlroots}"
# wlroots auto-assigns the socket name (wayland-0, wayland-1, ...); we detect
# the real one after launch rather than forcing it here.
unset WAYLAND_DISPLAY

# wlroots headless rendering (NVIDIA friendly defaults; overridable via env)
# headless,libinput: the headless backend gives the virtual output; libinput
# reads the uinput devices Sunshine creates so Moonlight input works. libinput
# needs a seat -> seatd (see seatd.ini) + LIBSEAT_BACKEND=seatd.
export WLR_BACKENDS="${WLR_BACKENDS:-headless,libinput}"
export LIBSEAT_BACKEND="${LIBSEAT_BACKEND:-seatd}"
# Wait for seatd's socket before starting the compositor (libinput needs it).
for i in $(seq 1 30); do
    [ -S /run/seatd.sock ] && break
    sleep 0.5
done
export WLR_RENDERER="${WLR_RENDERER:-gles2}"
export WLR_RENDERER_ALLOW_SOFTWARE="${WLR_RENDERER_ALLOW_SOFTWARE:-1}"
export WLR_NO_HARDWARE_CURSORS="${WLR_NO_HARDWARE_CURSORS:-1}"
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
export GBM_BACKEND="${GBM_BACKEND:-nvidia-drm}"
# Create one virtual output on the headless backend.
# (The headless backend opens no DRM/input devices, so no seat/libseat or
#  logind session is required.)
export WLR_HEADLESS_OUTPUTS="${WLR_HEADLESS_OUTPUTS:-1}"
# Don't refuse to start if a libinput backend gets pulled in with no devices.
export WLR_LIBINPUT_NO_DEVICES="${WLR_LIBINPUT_NO_DEVICES:-1}"

# Desired virtual output geometry
export DISPLAY_SIZEW="${DISPLAY_SIZEW:-1920}"
export DISPLAY_SIZEH="${DISPLAY_SIZEH:-1080}"
export DISPLAY_REFRESH="${DISPLAY_REFRESH:-60}"

# Start a session dbus instance (reused by sunshine via the upstream env file)
rm -fv /tmp/.dbus-desktop-session.env
export_desktop_dbus_session

# ---------------------------------------------------------------------------
# Write labwc configuration (autostart is regenerated every boot so that
# runtime toggles - resolution / Steam - are always honoured)
# ---------------------------------------------------------------------------
LABWC_DIR="${XDG_CONFIG_HOME}/labwc"
mkdir -p "${LABWC_DIR}"

# rc.xml / menu.xml only created if absent (user-customisable)
if [ ! -f "${LABWC_DIR}/rc.xml" ]; then
    cat > "${LABWC_DIR}/rc.xml" <<'EOF'
<?xml version="1.0"?>
<labwc_config>
  <core><gap>0</gap></core>
  <theme>
    <cornerRadius>4</cornerRadius>
    <font place="ActiveWindow"><name>sans</name><size>10</size></font>
  </theme>
  <keyboard>
    <default />
    <keybind key="A-Tab"><action name="NextWindow"/></keybind>
    <keybind key="W-Return"><action name="Execute"><command>foot</command></action></keybind>
    <keybind key="W-d"><action name="Execute"><command>fuzzel</command></action></keybind>
    <keybind key="A-F4"><action name="Close"/></keybind>
  </keyboard>
  <mouse><default /></mouse>
  <libinput>
    <device category="default"><naturalScroll>no</naturalScroll></device>
  </libinput>
</labwc_config>
EOF
fi

if [ ! -f "${LABWC_DIR}/menu.xml" ]; then
    cat > "${LABWC_DIR}/menu.xml" <<'EOF'
<?xml version="1.0"?>
<openbox_menu>
  <menu id="root-menu" label="labwc">
    <item label="Steam"><action name="Execute"><command>steam-launch</command></action></item>
    <item label="Heroic Games Launcher"><action name="Execute"><command>heroic</command></action></item>
    <item label="Lutris"><action name="Execute"><command>lutris</command></action></item>
    <item label="ProtonUp-Qt"><action name="Execute"><command>protonup-qt</command></action></item>
    <separator/>
    <item label="Terminal"><action name="Execute"><command>foot</command></action></item>
    <item label="App Launcher"><action name="Execute"><command>fuzzel</command></action></item>
    <item label="File Manager"><action name="Execute"><command>thunar</command></action></item>
    <item label="Firefox"><action name="Execute"><command>firefox</command></action></item>
    <separator/>
    <item label="Reconfigure"><action name="Reconfigure"/></item>
    <item label="Exit"><action name="Exit"/></item>
  </menu>
</openbox_menu>
EOF
fi

# Menus created by older images launch plain `steam`, which silently does
# nothing after a crashed start (see /usr/bin/steam-launch). Switch that exact
# default entry over; customised entries are left alone.
sed -i 's|<command>steam</command>|<command>steam-launch</command>|' "${LABWC_DIR}/menu.xml"

# environment file for labwc child processes
cat > "${LABWC_DIR}/environment" <<EOF
XDG_CURRENT_DESKTOP=labwc:wlroots
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland;xcb
GDK_BACKEND=wayland,x11
SDL_VIDEODRIVER=wayland
_JAVA_AWT_WM_NONREPARENTING=1
EOF

# autostart - regenerated every boot
cat > "${LABWC_DIR}/autostart" <<EOF
#!/usr/bin/env bash
# Force XWayland to start now (so X11 clients + Sunshine X capture work and the
# parent session can detect DISPLAY) - labwc starts it lazily otherwise.
( for i in \$(seq 1 20); do xhost +local: >/dev/null 2>&1 && break; sleep 0.5; done ) &

# Set the headless output resolution
( for i in \$(seq 1 20); do
    out=\$(wlr-randr --json 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
    if [ -n "\${out}" ] && [ "\${out}" != "null" ]; then
        wlr-randr --output "\${out}" --custom-mode ${DISPLAY_SIZEW}x${DISPLAY_SIZEH}@${DISPLAY_REFRESH} 2>/dev/null && break
    fi
    sleep 0.5
  done ) &

# Wallpaper, panel, notifications, polkit agent
swaybg -c '#1e1e2e' &
waybar &
mako &
lxqt-policykit-agent &

EOF

if [ "${ENABLE_STEAM:-}" = "true" ]; then
    cat >> "${LABWC_DIR}/autostart" <<EOF
# Launch Steam inside the session (inherits WAYLAND_DISPLAY + DISPLAY)
( sleep 3; exec steam-launch ${STEAM_ARGS:-} ) &
EOF
fi
chmod +x "${LABWC_DIR}/autostart"

# ---------------------------------------------------------------------------
# Minimal waybar config (only if the user has none)
# ---------------------------------------------------------------------------
WAYBAR_DIR="${XDG_CONFIG_HOME}/waybar"
mkdir -p "${WAYBAR_DIR}"
if [ ! -f "${WAYBAR_DIR}/config" ] && [ ! -f "${WAYBAR_DIR}/config.jsonc" ]; then
    cat > "${WAYBAR_DIR}/config" <<'EOF'
{
  "layer": "top",
  "position": "top",
  "height": 28,
  "modules-left": ["custom/menu"],
  "modules-center": ["clock"],
  "modules-right": ["cpu", "memory", "tray"],
  "custom/menu": { "format": "  Apps", "on-click": "fuzzel" },
  "clock": { "format": "{:%a %d %b  %H:%M}" },
  "cpu": { "format": "CPU {usage}%" },
  "memory": { "format": "RAM {percentage}%" },
  "tray": { "spacing": 8 }
}
EOF
    cat > "${WAYBAR_DIR}/style.css" <<'EOF'
* { font-family: sans-serif; font-size: 12px; }
window#waybar { background: #1e1e2e; color: #cdd6f4; }
#custom-menu, #clock, #cpu, #memory, #tray { padding: 0 10px; }
EOF
fi

# ---------------------------------------------------------------------------
# Launch the compositor
# ---------------------------------------------------------------------------
# Note: the session dbus bus is already exported above (export_desktop_dbus_session)
# and is inherited by labwc + its children, so we do NOT wrap in dbus-run-session
# (that would create a second, mismatched bus that sunshine couldn't share).
echo "**** Starting labwc (Wayland / wlroots, headless) ****"
labwc &
labwc_pid=$!

# Wait for the Wayland socket to appear and capture its real name
export WAYLAND_DISPLAY=""
for i in $(seq 1 60); do
    sock="$(ls "${XDG_RUNTIME_DIR}"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -n1)"
    if [ -n "${sock}" ]; then
        export WAYLAND_DISPLAY="$(basename "${sock}")"
        break
    fi
    sleep 0.5
done
echo "**** WAYLAND_DISPLAY = ${WAYLAND_DISPLAY:-<none>} ****"

# Detect the XWayland DISPLAY labwc created (lowest X socket present)
detected_display=""
for i in $(seq 1 40); do
    for sock in /tmp/.X11-unix/X*; do
        [ -S "${sock}" ] || continue
        detected_display=":${sock##*/X}"
        break
    done
    [ -n "${detected_display}" ] && break
    sleep 0.5
done
export DISPLAY="${detected_display:-:0}"
echo "**** XWayland DISPLAY = ${DISPLAY} ****"

# Allow local X clients (Sunshine, etc.) to connect
xhost +local: >/dev/null 2>&1 || true

# Publish the session environment for sibling services (wayvnc, sunshine)
cat > /tmp/.wayland-session.env <<EOF
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY}"
export DISPLAY="${DISPLAY}"
export XDG_SESSION_TYPE="wayland"
$(cat /tmp/.dbus-desktop-session.env 2>/dev/null | sed 's/^/export /')
EOF
chmod 0644 /tmp/.wayland-session.env

# Signal that the desktop session is up (upstream services wait on this)
touch /tmp/.started-desktop

# WAIT FOR CHILD PROCESS:
wait "$labwc_pid"
