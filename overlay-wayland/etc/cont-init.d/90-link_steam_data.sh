#!/usr/bin/env bash
###
# Keep ~/.steam/steam a symlink to the Steam data directory.
#
# 90-configure_steam.sh pre-seeds ~/.steam/steam/config/config.vdf and
# ~/.steam/steam/steamapps/libraryfolders.vdf. On a fresh home that creates
# ~/.steam/steam as a real directory before Steam ever ran. Arch's launcher
# (/usr/lib/steam/bin_steam.sh) expects ~/.steam/steam to be a link to
# ~/.local/share/Steam; with a directory in its place the first start fails with
# "Couldn't set up Steam data - please contact technical support".
#
# Move the pre-seeded files into ~/.local/share/Steam (without overwriting
# anything Steam already wrote there) and put the link in place of the
# directory. Homes where ~/.steam/steam already is a link are left untouched.
#
# Runs right after 90-configure_steam.sh. cont-init scripts are sourced by
# entrypoint.sh - never `exit` here.
###

link_steam_data() {
    local link="${USER_HOME:?}/.steam/steam"
    local data="${USER_HOME:?}/.local/share/Steam"

    [ -d "${link}" ] && [ ! -L "${link}" ] || return 0

    print_step_header "Replacing directory ${link} with a link to ${data}"
    mkdir -p "${data}"
    # A failed first start leaves a stray link inside the directory
    [ -L "${link}/Steam" ] && rm -f "${link}/Steam"
    cp -a --update=none "${link}/." "${data}/"
    rm -rf "${link}"
    ln -s "${data}" "${link}"
    chown -h "${USER:?}:${USER:?}" "${link}"
    chown -R "${USER:?}:${USER:?}" "${data}"
}

print_header "Link Steam data directory"
link_steam_data
