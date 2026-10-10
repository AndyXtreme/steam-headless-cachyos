#!/usr/bin/env bash
###
# Replaces upstream 30-configure_udev.sh: always run dumb-udev, never udevd.
#
# Upstream runs `udevadm trigger` to find out whether the container may run its
# own udevd, and start-udev.sh runs it again. From a privileged container that
# writes to the host's /sys, so the host re-applies its udev rules to every
# device. Upstream only skipped this while /run/udev was missing - and dumb-udev
# creates /run/udev on the first start, so every container restart took the
# udevd path. dumb-udev listens to kernel events and creates the input device
# nodes inside the container.
###

print_header "Configure udev (dumb-udev)"

sed -i 's|^command.*=.*$|command=start-dumb-udev.sh|' /etc/supervisor.d/udev.ini
sed -i 's|^autostart.*=.*$|autostart=true|' /etc/supervisor.d/udev.ini
print_step_header "Enable dumb-udev service"

if [[ -e /dev/uinput ]]; then
    print_step_header "Ensure the default user has permission to r/w on input devices"
    chmod 0666 /dev/uinput
fi

echo -e "\e[34mDONE\e[0m"
