
# ---------------------------------------------------------------------------
# The noVNC browser audio stream ("audiostream" program) relies on `tcpserver`
# (from ucspi-tcp-re). If that binary is missing, disable the program so it
# doesn't sit in a FATAL restart loop. Moonlight audio is unaffected (Sunshine
# handles its own audio path). Runs after 90-configure_vnc.sh.
# ---------------------------------------------------------------------------

print_header "Configure browser audio stream"

if command -v tcpserver >/dev/null 2>&1; then
    print_step_header "tcpserver present - browser audio available"
else
    print_step_header "tcpserver missing - disabling browser audio stream"
    if [ -f /etc/supervisor.d/vnc-audio.ini ]; then
        sed -i 's|^autostart.*=.*$|autostart=false|' /etc/supervisor.d/vnc-audio.ini
    fi
fi

echo -e "\e[34mDONE\e[0m"
