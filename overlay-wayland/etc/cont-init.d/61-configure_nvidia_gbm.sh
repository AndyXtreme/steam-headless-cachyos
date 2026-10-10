
# ---------------------------------------------------------------------------
# Repair the NVIDIA GBM backend symlink.
#
# The image ships /usr/lib/gbm/nvidia-drm_gbm.so as a symlink to the build-time
# nvidia-utils version (e.g. libnvidia-allocator.so.<build-ver>). At runtime the
# real driver is provided by the nvidia-container-toolkit (host libs under
# /usr/lib/x86_64-linux-gnu) and/or the matching .run install, with a DIFFERENT
# version - leaving the build-time symlink dangling. Mesa's GBM loader only
# searches /usr/lib/gbm, so the broken link means:
#   "MESA-LOADER: failed to open nvidia-drm: .../nvidia-drm_gbm.so"
# -> the gles2/EGL allocator can't create the headless output
# -> labwc has no output ("invalid output set for view")
# -> wayvnc fails with "No output found".
#
# This runs after 60-configure_gpu_driver.sh and points the GBM backend at the
# actual allocator library (auto-detected, so it survives driver updates).
# ---------------------------------------------------------------------------

print_header "Configure NVIDIA GBM backend"

fix_gbm_link() {
    local gbmdir="${1}" libdir="${2}"
    local link="${gbmdir}/nvidia-drm_gbm.so"
    local target=""

    # Already resolves to an existing file? Nothing to do.
    if [ -e "${link}" ]; then
        print_step_header "${link} OK"
        return 0
    fi

    # Newest real allocator library in the runtime lib dir.
    target="$(ls -1v "${libdir}"/libnvidia-allocator.so.* 2>/dev/null | tail -n1)"
    # Fallback: an injected gbm backend shipped alongside the runtime libs.
    if [ -z "${target}" ] && [ -e "${libdir}/gbm/nvidia-drm_gbm.so" ]; then
        target="${libdir}/gbm/nvidia-drm_gbm.so"
    fi

    if [ -n "${target}" ] && [ -e "${target}" ]; then
        mkdir -p "${gbmdir}"
        ln -sf "${target}" "${link}"
        print_step_header "Relinked ${link} -> ${target}"
    else
        print_warning "No NVIDIA allocator found in ${libdir}; leaving ${link} as-is"
    fi
}

# Only relevant when an NVIDIA GPU is present.
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    fix_gbm_link /usr/lib/gbm   /usr/lib/x86_64-linux-gnu
    fix_gbm_link /usr/lib32/gbm /usr/lib32
else
    print_step_header "No NVIDIA GPU detected; skipping"
fi

echo -e "\e[34mDONE\e[0m"
