#!/usr/bin/env bash
###
# File: start-wayvnc.sh
# Project: bin
# Serves the labwc/wlroots output as a VNC server for the noVNC web frontend.
###
set -e

# CATCH TERM SIGNAL:
_term() {
    kill -TERM "$wayvnc_pid" 2>/dev/null
}
trap _term SIGTERM SIGINT

# Wait for the Wayland session to publish its environment
for i in $(seq 1 120); do
    [ -f /tmp/.wayland-session.env ] && break
    sleep 0.5
done
# shellcheck disable=SC1091
source /tmp/.wayland-session.env 2>/dev/null || true

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

# Wait until the compositor socket is actually live
for i in $(seq 1 120); do
    [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ] && break
    sleep 0.5
done

PORT_VNC="${PORT_VNC:-5900}"
echo "**** Starting wayvnc on 127.0.0.1:${PORT_VNC} (WAYLAND_DISPLAY=${WAYLAND_DISPLAY}) ****"

# No auth here: the noVNC frontend / web UI is the access gate.
#
# --disable-resizing: noVNC defaults to "remote resizing" and would otherwise
# resize the headless output to every browser window that connects (e.g.
# 1118x701). That overrides DISPLAY_SIZEW/H for the whole session, including
# Moonlight streams. Keep the configured resolution; noVNC scales locally.
/usr/bin/wayvnc --disable-resizing 127.0.0.1 "${PORT_VNC}" &
wayvnc_pid=$!

wait "$wayvnc_pid"
