#!/usr/bin/env bash
###
# File: start-sunshine.sh  (Wayland variant)
# Project: bin
# Runs Sunshine attached to the labwc/wlroots session so Moonlight clients can
# connect. Capture uses the wlroots screencopy protocol (KMS is unavailable in
# a headless container).
###
set -e
source /usr/bin/common-functions.sh

# CATCH TERM SIGNAL:
_term() {
    kill -INT "$sunshine_pid" 2>/dev/null
    sleep 0.5
    counter=0
    while kill -0 "$sunshine_pid" 2>/dev/null; do
        kill -TERM "$sunshine_pid" 2>/dev/null
        counter=$((counter + 1))
        [ "$counter" -gt 8 ] && break
        sleep 0.5
    done
    counter=0
    while kill -0 "$sunshine_pid" 2>/dev/null; do
        kill -KILL "$sunshine_pid" 2>/dev/null
        counter=$((counter + 1))
        [ "$counter" -gt 4 ] && break
        sleep 0.5
    done
}
trap _term SIGTERM SIGINT


# CONFIGURE:
mkdir -p "${USER_HOME:?}/.config/sunshine"
if [ ! -f "${USER_HOME:?}/.config/sunshine/sunshine.conf" ]; then
    cp -vf /templates/sunshine/sunshine.conf "${USER_HOME:?}/.config/sunshine/sunshine.conf"
fi
if [ ! -f "${USER_HOME:?}/.config/sunshine/apps.json" ]; then
    cp -vf /templates/sunshine/apps.json "${USER_HOME:?}/.config/sunshine/apps.json"
fi
if [ ! -f "${USER_HOME:?}/.config/sunshine/sunshine_state.json" ]; then
    echo "{}" > "${USER_HOME:?}/.config/sunshine/sunshine_state.json"
fi
# Reset credentials if provided
if ([ "X${SUNSHINE_USER:-}" != "X" ] && [ "X${SUNSHINE_PASS:-}" != "X" ]); then
    /usr/bin/sunshine "${USER_HOME:?}/.config/sunshine/sunshine.conf" --creds "${SUNSHINE_USER:?}" "${SUNSHINE_PASS:?}"
fi
if ([ "X${WEBUI_USER:-}" != "X" ] && [ "X${WEBUI_PASS:-}" != "X" ]); then
    /usr/bin/sunshine "${USER_HOME:?}/.config/sunshine/sunshine.conf" --creds "${WEBUI_USER:?}" "${WEBUI_PASS:?}"
fi
if [ -f "${USER_HOME:?}/.config/autostart/Sunshine.desktop" ]; then
    rm -fv "${USER_HOME:?}/.config/autostart/Sunshine.desktop"
fi


# EXECUTE PROCESS:
# Wait for the Wayland desktop session to come up
wait_for_desktop

# Attach to the running session (WAYLAND_DISPLAY / DISPLAY / dbus)
for i in $(seq 1 60); do
    [ -f /tmp/.wayland-session.env ] && break
    sleep 0.5
done
# shellcheck disable=SC1091
source /tmp/.wayland-session.env 2>/dev/null || true
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

# Start the sunshine server
/usr/bin/dumb-init /usr/bin/sunshine "${USER_HOME:?}/.config/sunshine/sunshine.conf" &
sunshine_pid=$!

wait "$sunshine_pid"
