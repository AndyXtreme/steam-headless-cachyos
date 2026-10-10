# Steam Headless (CachyOS / Wayland)
# -------------------------------------------------------------------
# A CachyOS based variant of steam-headless with a Wayland session
# (labwc / wlroots) instead of the X11 + XFCE stack.
#
#   * Desktop ......... labwc (wlroots) + waybar  (headless backend)
#   * Browser access .. wayvnc -> noVNC/websockify (same web frontend as upstream)
#   * Streaming ....... Sunshine -> Moonlight (wlroots screen capture)
#   * Gaming .......... cachyos-gaming-meta (Steam, Proton-CachyOS, gamescope,
#                       mangohud, gamemode, wine-cachyos, vulkan, lib32, ...)
#
# Build (on the TrueNAS host / a Linux box with docker buildx):
#   docker build -t andyxtreme/steam-headless-cachyos:latest .
#
FROM cachyos/cachyos:latest
LABEL maintainer="Steam-Headless CachyOS variant"

# ------------------------------------------------------------------ #
#  Base system / pacman configuration
# ------------------------------------------------------------------ #
RUN \
    echo "**** Configure pacman ****" \
        && sed -i 's/^NoProgressBar/#NoProgressBar/g' /etc/pacman.conf \
        && sed -i 's/^#Color/Color/' /etc/pacman.conf \
        && sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf \
        # pacman 7.1 runs hooks and install scriptlets in a network-isolated
        # sandbox, which `docker build` does not permit. Every hook then fails
        # silently: no GSettings schemas (xdg-desktop-portal aborts, waybar exits),
        # no icon/MIME/font/pixbuf caches, no sysusers accounts such as polkitd.
        && sed -i '/^\[options\]/a DisableSandboxNetwork' /etc/pacman.conf \
        && grep -q '^DisableSandboxNetwork' /etc/pacman.conf \
    && \
    echo "**** Ensure [multilib] is enabled (required for 32-bit Steam/Proton) ****" \
        && if ! grep -q '^\[multilib\]' /etc/pacman.conf; then \
               printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf; \
           fi \
    && \
    echo "**** Refresh keyrings & full system update ****" \
        && pacman -Sy --noconfirm --needed archlinux-keyring cachyos-keyring \
        && pacman-key --populate \
        && pacman -Syu --noconfirm \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr /var/lib/pacman/sync/* /var/cache/pacman/pkg/* \
    && \
    echo

# Update locale
RUN \
    echo "**** Configure locale ****" \
        && echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen \
        && locale-gen \
    && \
    echo
ENV \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# ------------------------------------------------------------------ #
#  Core tooling
# ------------------------------------------------------------------ #
RUN \
    echo "**** Install core tools ****" \
        && pacman -Syu --noconfirm --needed \
            base-devel \
            bash \
            bash-completion \
            ca-certificates \
            curl \
            fakeroot \
            git \
            htop \
            jq \
            less \
            nano \
            net-tools \
            p7zip \
            patch \
            pciutils \
            pkg-config \
            procps-ng \
            psmisc \
            rsync \
            screen \
            sudo \
            unzip \
            vim \
            wget \
            xmlstarlet \
            xz \
            imagemagick \
            tcpdump \
            xprintidle \
    && \
    echo "**** Install python ****" \
        && pacman -Syu --noconfirm --needed \
            python \
            python-pip \
            python-setuptools \
    && \
    echo "**** Install supervisor ****" \
        && pacman -Syu --noconfirm --needed supervisor \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr /var/lib/pacman/sync/* /var/cache/pacman/pkg/* \
    && \
    echo

# ------------------------------------------------------------------ #
#  Default user (matches upstream behaviour, PUID/PGID set at runtime)
# ------------------------------------------------------------------ #
ENV \
    PUID=99 \
    PGID=100 \
    UMASK=000 \
    USER="default" \
    USER_PASSWORD="password" \
    USER_HOME="/home/default" \
    TZ="Europe/Berlin" \
    USER_LOCALES="en_US.UTF-8 UTF-8"
# makepkg (AUR builds via yay) downloads with curl: retry TLS/connection errors
# too - GitHub's release-asset CDN drops handshakes intermittently.
COPY overlay-wayland/etc/makepkg.conf.d/ /etc/makepkg.conf.d/
RUN \
    echo "**** Configure default user '${USER}' ****" \
        && mkdir -p ${USER_HOME} \
        && useradd -d ${USER_HOME} -s /bin/bash ${USER} \
        && chown -R ${USER} ${USER_HOME} \
        && echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    && \
    echo "**** Install yay (AUR helper) ****" \
        && su - ${USER} -c 'git clone https://aur.archlinux.org/yay-bin.git /tmp/yay && cd /tmp/yay && makepkg --noconfirm --syncdeps --install' \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr ${USER_HOME}/.cache/yay /var/lib/pacman/sync/* /var/cache/pacman/pkg/* /tmp/yay* \
    && \
    echo

# ------------------------------------------------------------------ #
#  Audio (PulseAudio - shared socket like upstream)
# ------------------------------------------------------------------ #
ENV \
    PULSE_SOCKET_DIR="/tmp/pulse" \
    PULSE_SERVER="unix:/tmp/pulse/pulse-socket"
RUN \
    echo "**** Install audio stack ****" \
        && pacman -Syu --noconfirm --needed \
            alsa-utils \
            pavucontrol \
            pulseaudio \
            pulseaudio-alsa \
            gst-libav \
            gst-plugins-bad \
            gst-plugins-base \
            gst-plugins-good \
            gst-plugins-ugly \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr /var/lib/pacman/sync/* /var/cache/pacman/pkg/* \
    && \
    echo

# ------------------------------------------------------------------ #
#  Wayland session stack (labwc / wlroots) + browser remote (wayvnc)
# ------------------------------------------------------------------ #
ENV \
    XORG_SOCKET_DIR="/tmp/.X11-unix" \
    XDG_SESSION_TYPE="wayland"
RUN \
    echo "**** Install Wayland compositor + desktop bits ****" \
        && pacman -Syu --noconfirm --needed \
            labwc \
            waybar \
            wayvnc \
            swaybg \
            swayidle \
            foot \
            fuzzel \
            mako \
            wlr-randr \
            wl-clipboard \
            grim \
            slurp \
            wmenu \
            seatd \
            xorg-xwayland \
            xorg-xhost \
            xorg-xrandr \
            xorg-xauth \
            xorg-xdpyinfo \
            qt5-wayland \
            qt6-wayland \
            egl-wayland \
            xdg-desktop-portal \
            xdg-desktop-portal-wlr \
            xdg-desktop-portal-gtk \
            xdg-user-dirs \
            xdg-utils \
            polkit \
            lxqt-policykit \
            accountsservice \
            dbus \
            avahi \
            fuse2 \
            ttf-liberation \
            noto-fonts \
            noto-fonts-emoji \
            thunar \
            gnome-system-monitor \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr /var/lib/pacman/sync/* /var/cache/pacman/pkg/* \
    && \
    echo

# ------------------------------------------------------------------ #
#  Pin the CURRENT NVIDIA userspace driver FIRST.
#  cachyos-gaming-meta depends on the virtual `nvidia-utils`; in --noconfirm
#  mode pacman would otherwise auto-select the ancient `nvidia-390xx-utils`
#  legacy package (390.157), which supports neither the RTX 40/50 series nor
#  Wayland and conflicts with the host-injected driver. Installing the real
#  package first makes it satisfy the dependency.
#  (At runtime the matching host driver is still injected / installed by
#   60-configure_gpu_driver.sh; these are just sane defaults + the Vulkan ICD.)
#
#  The pair comes from Arch ([extra]/[multilib]): [cachyos] is searched first
#  but does not always rebuild both together (e.g. nvidia-utils 615.71.09 next
#  to a stale lib32-nvidia-utils 610.57.04 that requires nvidia-utils=610.57.04
#  -> "could not satisfy dependencies").
#
#  Freeze them right away: later `pacman -Syu` build steps then can't move
#  nvidia-utils ahead of lib32-nvidia-utils again, and a `pacman -Syu` inside a
#  running container skips them (an explicit `pacman -S nvidia-utils` still
#  reinstalls them). At runtime these packaged libraries would shadow the host
#  driver's userspace via ldconfig; 60-verify_nvidia_userspace.sh removes them.
# ------------------------------------------------------------------ #
RUN \
    echo "**** Pin current NVIDIA userspace driver ****" \
        && pacman -Syu --noconfirm --needed \
            extra/nvidia-utils \
            multilib/lib32-nvidia-utils \
            libva-nvidia-driver \
    && \
    echo "**** Freeze NVIDIA userspace packages ****" \
        && sed -i '/^\[options\]/a IgnorePkg = nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia nvidia-settings' /etc/pacman.conf \
        && grep -q '^IgnorePkg = nvidia-utils' /etc/pacman.conf \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr /var/lib/pacman/sync/* /var/cache/pacman/pkg/* \
    && \
    echo

# ------------------------------------------------------------------ #
#  CachyOS gaming meta packages (Steam, Proton, gamescope, vulkan ...)
# ------------------------------------------------------------------ #
RUN \
    echo "**** Install CachyOS gaming stack ****" \
        && pacman -Syu --noconfirm --needed \
            cachyos-gaming-meta \
            cachyos-gaming-applications \
    && \
    echo "**** Ensure vulkan loaders + mangohud + gamescope present ****" \
        && pacman -Syu --noconfirm --needed \
            vulkan-icd-loader \
            lib32-vulkan-icd-loader \
            vulkan-tools \
            gamescope \
            gamemode \
            lib32-gamemode \
            mangohud \
            lib32-mangohud \
            libva-utils \
            vdpauinfo \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr /var/lib/pacman/sync/* /var/cache/pacman/pkg/* \
    && \
    echo

# ------------------------------------------------------------------ #
#  Game launchers (explicit, so they don't depend on the meta package
#  contents): Heroic (Epic/GOG/Amazon), Lutris, ProtonUp-Qt
# ------------------------------------------------------------------ #
RUN \
    echo "**** Install game launchers ****" \
        && pacman -Syu --noconfirm --needed lutris || true \
        && ( pacman -Syu --noconfirm --needed heroic-games-launcher \
             || su - ${USER} -c "yay -Syu --noconfirm --needed heroic-games-launcher-bin" ) \
        && ( pacman -Syu --noconfirm --needed protonup-qt \
             || su - ${USER} -c "yay -Sy --noconfirm --needed --overwrite '/usr/bin/normalizer' protonup-qt" ) \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr ${USER_HOME}/.cache/yay /var/lib/pacman/sync/* /var/cache/pacman/pkg/* /tmp/yay* \
    && \
    echo

# ------------------------------------------------------------------ #
#  Firefox + Flatpak support
# ------------------------------------------------------------------ #
ENV \
    XDG_DATA_DIRS="/home/default/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share/:/usr/share/"
RUN \
    echo "**** Install Firefox + flatpak ****" \
        && pacman -Syu --noconfirm --needed \
            firefox \
            flatpak \
    && \
    echo "**** Configure flatpak ****" \
        && chmod u-s /usr/bin/bwrap || true \
        && flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
        && su - ${USER} -c "flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo" \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr /var/lib/pacman/sync/* /var/cache/pacman/pkg/* \
    && \
    echo

# ------------------------------------------------------------------ #
#  Sunshine (Moonlight host)
# ------------------------------------------------------------------ #
# Pinned to a pre-CUDA-13 Sunshine build. The latest Sunshine (repo/AUR/AppImage)
# is compiled against CUDA 13 and needs NVIDIA driver >= ~580 for NVENC; builds
# before ~Sep 2025 use CUDA 12 and do NVENC on driver 570 (the TrueNAS host
# version). v2025.628.4510 = full nvenc (h264/hevc/av1) on a 4060 Ti + driver 570.
# Don't bump this unless the host driver is >= 580.
ARG SUNSHINE_VERSION=v2025.628.4510
RUN \
    echo "**** Install Sunshine ${SUNSHINE_VERSION} (CUDA 12 build, NVENC on driver <580) ****" \
        && mkdir -p /opt/sunshine \
        && curl -fL --retry 5 --retry-all-errors --retry-delay 5 -o /opt/sunshine/sunshine.AppImage \
            https://github.com/LizardByte/Sunshine/releases/download/${SUNSHINE_VERSION}/sunshine.AppImage \
        && chmod +x /opt/sunshine/sunshine.AppImage \
        && ( cd /opt/sunshine && ./sunshine.AppImage --appimage-extract >/dev/null ) \
        && rm -f /opt/sunshine/sunshine.AppImage \
        && printf '#!/bin/sh\nexec /opt/sunshine/squashfs-root/AppRun "$@"\n' > /usr/bin/sunshine \
        && chmod +x /usr/bin/sunshine \
    && \
    echo

# ------------------------------------------------------------------ #
#  noVNC web frontend + websockify (same UI as upstream)
# ------------------------------------------------------------------ #
ARG FRONTEND_VERSION=a8eb92f
RUN \
    echo "**** Fetch Web Frontend ****" \
        && mkdir -p /opt \
        && rm -rf /opt/frontend \
        && git clone https://github.com/Steam-Headless/frontend.git --branch master /opt/frontend \
        && cd /opt/frontend \
        && git checkout ${FRONTEND_VERSION} 2> /dev/null \
        && git submodule init \
        && git submodule update --depth 1 --recursive \
        && rm -rf /opt/frontend/.git \
    && \
    echo "**** Configure Web Frontend ****" \
        && echo '<!DOCTYPE html>' > /opt/frontend/index.html \
        && echo '<html><head><meta http-equiv="refresh" content="0;url=./web/"></head><body><p>If you are not redirected, <a href="./web/">click here</a>.</p></body></html>' >> /opt/frontend/index.html \
        && chmod -R 755 /opt/frontend \
    && \
    echo

ARG WEBSOCKETIFY_VERSION=0.11.0
RUN \
    echo "**** Install Websockify ****" \
        && cd /tmp \
        && curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o /tmp/websockify.tar.gz https://github.com/novnc/websockify/archive/v${WEBSOCKETIFY_VERSION}.tar.gz \
        && tar -xf /tmp/websockify.tar.gz \
        && cd /tmp/websockify-${WEBSOCKETIFY_VERSION} \
        && ( python3 ./setup.py install 2>/dev/null || pip install --break-system-packages . ) \
        && mkdir -p /opt/noVNC/utils \
        && mv -v /tmp/websockify-${WEBSOCKETIFY_VERSION} /opt/noVNC/utils/websockify \
    && \
    echo "**** Section cleanup ****" \
        && rm -rf /tmp/websockify-* /tmp/websockify.tar.gz \
    && \
    echo

# ------------------------------------------------------------------ #
#  dumb-init + dumb-udev (input hotplug, identical to upstream)
# ------------------------------------------------------------------ #
ARG DUMB_INIT_VERSION=1.2.5
ARG DUMB_UDEV_VERSION=64d1427
RUN \
    echo "**** Install dumb-init ****" \
        && curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
            -o /usr/bin/dumb-init \
            https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_x86_64 \
        && chmod +x /usr/bin/dumb-init \
    && \
    echo "**** Install dumb-udev ****" \
        && python3 -m pip install --break-system-packages --pre --upgrade --no-cache-dir \
            git+https://github.com/Steam-Headless/dumb-udev.git@${DUMB_UDEV_VERSION} \
    && \
    echo

# ------------------------------------------------------------------ #
#  ucspi-tcp - provides `tcpserver`, used by the noVNC browser audio
#  stream (the "audiostream" supervisor program). Not in the Arch repos,
#  so it's built from the AUR.
# ------------------------------------------------------------------ #
RUN \
    echo "**** Install ucspi-tcp-re (browser audio transport, provides tcpserver) ****" \
        && ( su - ${USER} -c "yay -Syu --noconfirm --needed ucspi-tcp-re" \
             || echo "WARN: ucspi-tcp-re unavailable; browser audio will be auto-disabled at runtime" ) \
    && \
    echo "**** Section cleanup ****" \
        && pacman -Scc --noconfirm \
        && rm -fr ${USER_HOME}/.cache/yay /var/lib/pacman/sync/* /var/cache/pacman/pkg/* /tmp/yay* \
    && \
    echo

# ------------------------------------------------------------------ #
#  Filesystem overlays
#    1. The upstream overlay (user/dbus/pulse/gpu/steam/sunshine init)
#    2. Our Wayland overlay (overrides the display layer)
# ------------------------------------------------------------------ #
COPY overlay /
COPY overlay-wayland /

# Neutralise upstream X-only helpers that don't exist on this image, and
# normalise the overlay scripts.
#
# The chmod/sed below are not cosmetic: the build context may come from a
# checkout on a non-POSIX host (Git on Windows drops the executable bit and can
# introduce CRLF line endings). Supervisor launches several of these scripts
# directly, so a missing +x makes the container fail at start-up with
# "Permission denied".
RUN \
    echo "**** Wayland tweaks ****" \
        && sed -i d /usr/bin/install_firefox.sh 2>/dev/null || true \
        && sed -i d /usr/bin/install_protonup.sh 2>/dev/null || true \
        # Flushes the page cache of the whole host; nothing calls it.
        && rm -f /usr/bin/drop_caches.sh \
        # No X server programs: Xorg would start on a VT and the GPU of the host.
        && rm -f /etc/supervisor.d/xorg.ini /etc/supervisor.d/xvfb.ini \
    && \
    echo "**** Normalise overlay scripts (exec bit + line endings) ****" \
        && chmod +x \
            /entrypoint.sh \
            /etc/cont-init.d/*.sh \
            /usr/bin/common-functions.sh \
            /usr/bin/install_*.sh \
            /usr/bin/set-custom-res.sh \
            /usr/bin/start-*.sh \
            /usr/bin/steam-headless-wol-power-manager \
            /usr/bin/steam-launch \
            /usr/bin/sunshine-run \
            /usr/bin/sunshine-stop \
            /usr/bin/xfce4-close-all-windows \
            /usr/bin/xfce4-minimise-all-windows \
            /usr/bin/host-module-guard \
        && sed -i 's/\r$//' \
            /entrypoint.sh \
            /etc/cont-init.d/*.sh \
            /usr/bin/common-functions.sh \
            /usr/bin/start-*.sh \
            /usr/bin/steam-headless-wol-power-manager \
            /usr/bin/steam-launch \
            /usr/bin/sunshine-run \
            /usr/bin/sunshine-stop \
            /usr/bin/host-module-guard \
    && \
    echo "**** Guard host kernel modules ****" \
        # The container is privileged: rmmod / modprobe -r here unload modules
        # on the host, and nothing in here can load them back.
        && ln -sf host-module-guard /usr/bin/rmmod \
        && ln -sf host-module-guard /usr/bin/modprobe \
        && rmmod nvidia_drm 2>&1 | grep -q refusing \
        && modprobe --version | grep -q '^kmod version' \
    && \
    echo

# ------------------------------------------------------------------ #
#  Display / session environment
# ------------------------------------------------------------------ #
ENV \
    DISPLAY_CDEPTH="24" \
    DISPLAY_REFRESH="60" \
    DISPLAY_SIZEH="1080" \
    DISPLAY_SIZEW="1920" \
    WAYLAND_DISPLAY="wayland-1" \
    XDG_SESSION_TYPE="wayland" \
    XDG_CURRENT_DESKTOP="labwc:wlroots" \
    # Referenced by supervisor program definitions; the real per-session value
    # is set at runtime in start-wayland-session.sh (/tmp/runtime-<uid>).
    XDG_RUNTIME_DIR="/tmp/.X11-unix/run" \
    # XWayland display that labwc will create for X11 clients (Steam, Sunshine X capture)
    DISPLAY=":0"

# wlroots / NVIDIA headless rendering hints (overridable at runtime)
ENV \
    WLR_BACKENDS="headless,libinput" \
    LIBSEAT_BACKEND="seatd" \
    WLR_HEADLESS_OUTPUTS="1" \
    # gles2 (not vulkan): NVIDIA's Vulkan lacks VK_EXT_external_memory_dma_buf
    # which the wlroots vulkan renderer requires.
    WLR_RENDERER="gles2" \
    WLR_RENDERER_ALLOW_SOFTWARE="1" \
    WLR_NO_HARDWARE_CURSORS="1" \
    GBM_BACKEND="nvidia-drm" \
    __GLX_VENDOR_LIBRARY_NAME="nvidia" \
    NVIDIA_DRIVER_CAPABILITIES="all" \
    NVIDIA_VISIBLE_DEVICES="all"

# Container behaviour
ENV \
    MODE="primary" \
    WEB_UI_MODE="vnc" \
    ENABLE_VNC_AUDIO="true" \
    ENABLE_STEAM="true" \
    STEAM_ARGS="-silent" \
    ENABLE_SUNSHINE="true" \
    ENABLE_EVDEV_INPUTS="true" \
    ENABLE_WOL_POWER_MANAGER="false"

# Ports
ENV \
    PORT_NOVNC_WEB="8083"
EXPOSE 8083

# Entrypoint (unchanged from upstream)
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
