#!/usr/bin/env bash
###
# Make the NVIDIA userspace libraries match the host kernel driver.
#
# The image keeps nvidia-utils / lib32-nvidia-utils installed (the gaming meta
# packages depend on them) and 60-configure_gpu_driver.sh installs the host
# driver's userspace next to them. Both ship the same sonames
# (libGLX_nvidia.so.0, libEGL_nvidia.so.0, libnvidia-allocator.so.1, ...) and
# ldconfig links a soname to the highest version present. Whenever the packaged
# driver is newer than the host driver, the NVIDIA libraries therefore resolve
# to the packaged version: userspace/kernel mismatch, no GPU for labwc/Xwayland
# ("EGL setup failed, disabling glamor") and a crashing 32-bit Steam client.
# nvidia-installer warns about exactly this in nvidia_gpu_install.log.
#
# On Debian-based hosts such as TrueNAS Scale the NVIDIA container toolkit
# bind-mounts the host driver's libraries into /usr/lib/x86_64-linux-gnu, and
# nvidia-installer then installs its 64-bit libraries there as well - a
# directory Arch's ldconfig does not search.
#
# Fix: add the Debian multiarch directories to the loader search path, delete
# every versioned library for which the host driver version exists in the same
# or in the matching multiarch directory, drop the links that pointed to it and
# rebuild the cache. Files the toolkit bind-mounts can't be deleted (EBUSY) and
# stay.
#
# Don't re-run nvidia-installer from here: a second run installs into the same
# directories, so it can't change which library the loader picks.
#
# Runs after 60-configure_gpu_driver.sh, which sets nvidia_host_driver_version.
# cont-init scripts are sourced by entrypoint.sh - never `exit` here.
###

register_multiarch_lib_dirs() {
    local conf=/etc/ld.so.conf.d/00-nvidia-host-multiarch.conf dir
    rm -f "${conf}"
    for dir in /usr/lib/x86_64-linux-gnu /usr/lib/i386-linux-gnu; do
        [ -d "${dir}" ] || continue
        echo "${dir}" >>"${conf}"
        print_step_header "Added ${dir} (NVIDIA container toolkit) to the library search path"
    done
}

prune_stale_nvidia_libs() {
    local version="$1" file name same multiarch removed=0 kept=0
    while IFS= read -r file; do
        [ "${file##*.so.}" = "${version}" ] && continue
        same="${file%.so.*}.so.${version}"
        case "${same}" in
            /usr/lib32/*) multiarch="/usr/lib/i386-linux-gnu/${same#/usr/lib32/}" ;;
            *) multiarch="/usr/lib/x86_64-linux-gnu/${same#/usr/lib/}" ;;
        esac
        [ -e "${same}" ] || [ -e "${multiarch}" ] || continue
        if rm -f "${file}" 2>/dev/null; then
            # Its links (libfoo.so.1, libfoo.so -> libfoo.so.1) now dangle;
            # ldconfig recreates the soname link if a matching version is left.
            name="${file##*/}"
            find "${file%/*}" -maxdepth 1 -xtype l -name "${name%%.so.*}.so*" -delete 2>/dev/null
            removed=$((removed + 1))
        else
            kept=$((kept + 1))
        fi
    done < <(find /usr/lib /usr/lib32 -maxdepth 3 -type f -regextype posix-extended -regex '.*/lib[^/]*[.]so[.][0-9]+[.][0-9]+([.][0-9]+)?' 2>/dev/null)
    ldconfig
    print_step_header "Removed ${removed} NVIDIA libraries not matching host driver v${version} (${kept} host-provided kept)"
}

# Checks what the dynamic loader actually opens: every loader-cache entry for
# the GLX and EGL vendor libraries must resolve to the host driver version.
nvidia_lib_mismatches() {
    local version="$1" soname abi path target out="" found=0
    while read -r soname abi path; do
        found=$((found + 1))
        target="$(readlink -f "${path}")"
        [ "${target##*.so.}" = "${version}" ] || out="${out} ${target%.so.*}.so.${target##*.so.}"
    done < <(ldconfig -p | awk '$1 ~ /^lib(GLX|EGL)_nvidia[.]so[.]0$/ { print $1, $2, $NF }')
    [ "${found}" -gt 0 ] || out=" no libGLX_nvidia.so.0 / libEGL_nvidia.so.0 in the loader cache"
    echo "${out}"
}

verify_nvidia_userspace() {
    local version="${nvidia_host_driver_version:-}" mismatch
    [ -n "${version}" ] || return 0
    ((${version%%.*} > 500)) || return 0

    register_multiarch_lib_dirs
    prune_stale_nvidia_libs "${version}"
    mismatch="$(nvidia_lib_mismatches "${version}")"
    if [ -z "${mismatch}" ]; then
        print_step_header "NVIDIA userspace libraries match host driver v${version}"
    else
        print_error "NVIDIA userspace does not match host driver v${version}:${mismatch}"
        print_error "Check ${USER_HOME:?}/Downloads/nvidia_gpu_install.log"
    fi
}

print_header "Verify NVIDIA userspace"
verify_nvidia_userspace
