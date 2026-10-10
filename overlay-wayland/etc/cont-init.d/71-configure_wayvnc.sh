
# ---------------------------------------------------------------------------
# Enable / disable the wayvnc capture program (Wayland replacement for x11vnc).
# The noVNC web frontend itself is still toggled by 90-configure_vnc.sh.
# PORT_VNC is exported by 90-configure_vnc.sh and resolved by supervisord at
# launch time, so here we only need to flip the autostart flag.
# ---------------------------------------------------------------------------

print_header "Configure wayvnc"

if ([ "${MODE}" != "s" ] && [ "${MODE}" != "secondary" ]) && [ "${WEB_UI_MODE:-vnc}" = "vnc" ]; then
    print_step_header "Enable wayvnc server"
    sed -i 's|^autostart.*=.*$|autostart=true|' /etc/supervisor.d/wayvnc.ini
else
    print_step_header "Disable wayvnc server"
    sed -i 's|^autostart.*=.*$|autostart=false|' /etc/supervisor.d/wayvnc.ini
fi

echo -e "\e[34mDONE\e[0m"
