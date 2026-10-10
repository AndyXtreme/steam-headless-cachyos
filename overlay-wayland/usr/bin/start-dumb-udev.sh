#!/usr/bin/env bash
###
# Replaces upstream start-dumb-udev.sh without its X11 part: upstream ran
# `supervisorctl restart xorg` as soon as Sunshine's input devices appeared.
# This image has no Xorg desktop, and Xorg would start on a VT and the GPU of
# the host - the container is privileged.
###
set -e

_term() {
    kill -TERM "${sync_pid:-}" 2>/dev/null
    kill -TERM "${dumb_udev_pid:-}" 2>/dev/null
    kill -TERM "${udevd_pid:-}" 2>/dev/null
}
trap _term SIGTERM SIGINT

# Device nodes for input devices that appear after the container started
# (Sunshine's virtual keyboard, mouse and pads) - in the container's /dev only.
sync_input_nodes() {
    mkdir -p /dev/input
    for sys in /sys/class/input/*/dev; do
        [[ -f "${sys}" ]] || continue
        node=$(basename "$(dirname "${sys}")")
        path="/dev/input/${node}"
        [[ -e "${path}" ]] && continue
        IFS=: read -r major minor < "${sys}"
        mknod "${path}" c "${major}" "${minor}" 2>/dev/null || continue
        chmod 0660 "${path}" 2>/dev/null || true
        chgrp input "${path}" 2>/dev/null || true
    done
}

# udevd in its own network namespace, as upstream.
if command -v udevd &>/dev/null; then
    unshare --net udevd --daemon &>/dev/null || true
else
    unshare --net /lib/systemd/systemd-udevd --daemon &>/dev/null || true
fi
if pgrep -x systemd-udevd >/dev/null 2>&1; then
    udevd_pid=$(pgrep -xo systemd-udevd || true)
fi

dumb-udev &
dumb_udev_pid=$!

while true; do
    sync_input_nodes
    sleep 1
done &
sync_pid=$!

wait "$dumb_udev_pid"
