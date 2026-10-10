## Support

If this edition helps you, I'd appreciate a small donation – thank you! ☕

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20me-FF5E5B?logo=kofi&logoColor=white)](https://ko-fi.com/andyxtreme)


# Steam-Headless – CachyOS + Wayland Edition

A cloud-gaming desktop in a container: games run on the **NVIDIA GPU of a
headless server**, and you play them in the **browser** (noVNC) or with
**Moonlight** (Sunshine, NVENC). No monitor, no dummy plug, no client to install
for the browser path.

This is a Wayland variant of
[Steam-Headless](https://github.com/Steam-Headless/docker-steam-headless) by
josh5. Same init system and the same web frontend, but a different base and
display stack: **CachyOS** instead of Arch/Debian, and a **labwc** (wlroots)
session instead of Xorg + XFCE.

Self-hosted, no cloud, no account – except the Steam account you log in with.
amd64 only.

---

## What's different from the original image

| Area | Original | This image |
|---|---|---|
| Base image | Arch / Debian | **`cachyos/cachyos`** (x86-64-v3/v4 optimized packages) |
| Desktop | Xorg (dummy driver) + XFCE | **labwc** (wlroots, headless backend) + waybar |
| Browser capture | x11vnc → noVNC | **wayvnc** → noVNC (same web UI) |
| Moonlight capture | Sunshine, X11 capture | Sunshine, **wlroots screencopy** + NVENC |
| Gaming stack | individual packages | **`cachyos-gaming-meta`**: Proton-CachyOS, wine-cachyos, gamescope, MangoHud, GameMode, Vulkan + 32-bit libs |
| Launchers | Steam | **Steam, Heroic, Lutris, ProtonUp-Qt** |
| X11 apps | native | via **Xwayland**, started on demand |

The upstream init scripts are carried over unchanged; only the display layer is
replaced.

---

## ⚠️ Requirements

- **Linux host with an NVIDIA GPU** – developed and run on **TrueNAS Scale 25.10**.
- **NVIDIA Container Toolkit**, so `nvidia-smi` works inside containers.
- **`nvidia-drm.modeset=1` on the host.** Wayland on NVIDIA does not work
  without it. Check:

  ```bash
  cat /sys/module/nvidia_drm/parameters/modeset   # must print: Y
  ```

  If it prints `N`, the result is a **black screen** (`wayvnc: No output found`,
  `gbm_bo_create failed: Permission denied`). On TrueNAS Scale a `modprobe.d`
  file is too late. Add an init script instead under
  **System → Advanced Settings → Init/Shutdown Scripts → Add**
  (TrueNAS 24.04 and older: System Settings → Advanced):

  - **Type:** *Command*
  - **When:** *Post Init*
  - **Command:**

    ```
    modprobe -r nvidia_drm 2>/dev/null; modprobe nvidia_drm modeset=1
    ```

  Reboot the host and run the check again. If it still prints `N`, the app
  already held the GPU when the script ran (`modprobe -r` fails with *Module
  nvidia_drm is in use*; the script hides that message). Then stop the app
  from starting on boot and let the script start it after the reload:

  ```
  modprobe -r nvidia_drm 2>/dev/null; modprobe nvidia_drm modeset=1; midclt call app.start <app-name>
  ```

  The original X11 image does not need this – it's the price of Wayland on
  NVIDIA.

**Docker Desktop / WSL2 is not a target.** It passes no `/dev/dri` and no
`/dev/uinput` into containers: the desktop comes up with software rendering, but
there is no NVENC and no Moonlight input.

---

## Quick start

Example values for a **TrueNAS Scale** server – there, paste the file into
**Apps → Custom App → Install via YAML**. On other hosts save it as
`docker-compose.yml` and run `docker compose up -d`. Adjust every line marked
`# ←`; the rest works as it is.

```yaml
services:
  steam-headless:
    image: andyxtreme/steam-headless-cachyos:latest
    container_name: steam-headless
    restart: unless-stopped
    hostname: steam-headless
    extra_hosts:
      admin: 127.0.0.1

    # Host networking: Moonlight discovery and low latency need it.
    network_mode: host
    ipc: host

    privileged: true
    security_opt:
      - apparmor=unconfined
      - seccomp=unconfined
    cap_add: [AUDIT_WRITE, CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, MKNOD,
              NET_ADMIN, SETGID, SETUID, SYS_ADMIN, SYS_NICE, SYS_RESOURCE]
    cap_drop: [ALL]

    shm_size: 4096M
    device_cgroup_rules:
      - c 13:* rwm
    devices:
      - /dev/fuse:/dev/fuse
      - /dev/uinput:/dev/uinput     # Moonlight keyboard, mouse, controller
      - /dev/dri:/dev/dri           # render node for the compositor

    deploy:
      resources:
        limits:
          memory: 16G
        reservations:
          memory: 4G
          devices:
            - driver: nvidia
              capabilities: [gpu]
              device_ids: ["GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]   # ← nvidia-smi -L

    environment:
      TZ: Europe/Berlin
      USER_PASSWORD: change-me                  # ← desktop user / noVNC
      # 568 = the "apps" user and group on TrueNAS Scale
      PUID: '568'
      PGID: '568'
      UID: '568'
      GID: '568'
      USER_ID: '568'
      GROUP_ID: '568'
      UMASK: '002'
      UMASK_SET: '002'

      MODE: primary
      WEB_UI_MODE: vnc
      PORT_NOVNC_WEB: '31100'

      DISPLAY: ':0'
      # Match the resolution you request in Moonlight for the sharpest image.
      DISPLAY_SIZEW: '2560'
      DISPLAY_SIZEH: '1440'
      DISPLAY_REFRESH: '60'
      XKB_DEFAULT_LAYOUT: de
      XKB_DEFAULT_VARIANT: ''

      # Pin the render node – otherwise wlroots may pick card0, which needs
      # DRM master, and no output appears.
      WLR_RENDER_DRM_DEVICE: /dev/dri/renderD128
      NVIDIA_VISIBLE_DEVICES: GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   # ← same UUID as above
      NVIDIA_DRIVER_CAPABILITIES: all
      NVIDIA_DRIVER_VERSION: '580.173.02'       # ← nvidia-smi on the host, exactly

      ENABLE_STEAM: 'true'
      STEAM_ARGS: -silent
      ENABLE_SUNSHINE: 'true'
      ENABLE_EVDEV_INPUTS: 'true'
      ENABLE_VNC_AUDIO: 'true'
      # D-Bus inside the container - 'true' would give it root access to the
      # host's system bus.
      HOST_DBUS: 'false'
      SUNSHINE_USER: admin
      SUNSHINE_PASS: change-me                  # ← Sunshine web UI / Moonlight pairing

    group_add:
      - '44'              # video
      - '107'             # render
      - '568'             # apps

    volumes:
      # ← "tank" is the pool name – replace it with yours.
      - /mnt/tank/apps/steam-headless/home:/home/default
      - /mnt/tank/apps/steam-headless/games:/mnt/games
      - /mnt/tank/apps/steam-headless/x11:/tmp/.X11-unix
      - /mnt/tank/apps/steam-headless/pulse:/tmp/pulse

    healthcheck:
      test: ["CMD", "curl", "-fsS", "-o", "/dev/null",
             "http://127.0.0.1:31100/"]   # same port as PORT_NOVNC_WEB
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
```

The group IDs `44` (video) and `107` (render) must match the host's groups –
check with `getent group video render`.

Then:

- **Browser:** `http://<HOST-IP>:31100/` – the desktop appears and Steam starts
  on its own. Right-click the wallpaper for the app menu.
- **Moonlight:** add the host **by its IP** (auto-discovery would need the host's
  D-Bus, see `HOST_DBUS`), start pairing, and enter the PIN in the Sunshine
  web UI at `https://<HOST-IP>:47990/` (login `SUNSHINE_USER` / `SUNSHINE_PASS`).

> **Give the first start a few minutes.** The container downloads and installs
> the NVIDIA userspace driver matching `NVIDIA_DRIVER_VERSION`, then bootstraps
> Steam into the empty home directory.

---

## Interfaces

| | |
|---|---|
| Network | **host networking** – nothing to map, but the host firewall must allow the ports below |
| `PORT_NOVNC_WEB` | noVNC web UI (HTTP). Image default `8083`, `31100` in the example above. |
| `47990` | Sunshine web UI (HTTPS) – pairing, apps, encoder settings |
| `47984`–`48010` | Sunshine / Moonlight streaming, TCP and UDP (Sunshine defaults) |
| `/home/default` | The user's home: Steam client, logins, settings, Proton prefixes, Sunshine pairing. **Must persist.** |
| `/mnt/games` | Game library – pre-registered as a Steam library folder on the first start |
| `/tmp/.X11-unix`, `/tmp/pulse` | X11 and PulseAudio sockets, shared with other containers if you want |
| Devices | `/dev/dri` (render node), `/dev/uinput` (Moonlight input), `/dev/fuse` (AppImage / Flatpak), GPU via the NVIDIA Container Toolkit |
| Healthcheck | not built into the image – the compose example checks the noVNC page |

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `USER_PASSWORD` | `password` | Password of the desktop user – **set it** |
| `SUNSHINE_USER` / `SUNSHINE_PASS` | – | Sunshine web UI login, (re)set at every start when both are given. Left empty, the stored login stays; on a fresh home the web UI asks for one. |
| `NVIDIA_DRIVER_VERSION` | – | Host driver version. Must be published on [download.nvidia.com](https://download.nvidia.com/XFree86/Linux-x86_64/), otherwise the start stalls at the GPU step |
| `NVIDIA_VISIBLE_DEVICES` | `all` | GPU UUID from `nvidia-smi -L` |
| `PUID` / `PGID` | `99` / `100` | Owner of the files in `/home/default` and `/mnt/games` |
| `TZ` | `Europe/Berlin` | Time zone |
| `DISPLAY_SIZEW` / `DISPLAY_SIZEH` / `DISPLAY_REFRESH` | `1920` / `1080` / `60` | Resolution of the virtual output – match it to Moonlight for the sharpest image |
| `XKB_DEFAULT_LAYOUT` / `XKB_DEFAULT_VARIANT` | `us` / – | Keyboard layout, e.g. `de`; variant `nodeadkeys` makes `^`, `´` and `` ` `` print directly |
| `PORT_NOVNC_WEB` | `8083` | Port of the noVNC web UI |
| `ENABLE_STEAM` | `true` | `false` stops Steam from starting with the session. On a fresh home it also skips the one-time Steam setup – start once with `true`. |
| `STEAM_ARGS` | `-silent` | Arguments for the auto-started Steam client |
| `ENABLE_SUNSHINE` | `true` | Moonlight streaming on/off |
| `WLR_RENDERER` | `gles2` | Compositor renderer. **Not** `vulkan`: NVIDIA's Vulkan lacks `VK_EXT_external_memory_dma_buf` |
| `WLR_RENDER_DRM_DEVICE` | – | Render node for the compositor, usually `/dev/dri/renderD128` (`ls /dev/dri/`) |
| `WINE_CPU_TOPOLOGY` | automatic | Set at every start when a `cpuset` limits the container, mapping Wine's CPUs onto the allowed ones – otherwise launchers that pin threads (e.g. DOAXVV) hang on a grey window. Set it yourself only to override |

---

## ⚠️ Notes on the NVIDIA driver

None of these is a bug of this image, but each one costs an evening if you don't
know about it.

### The driver version has to match exactly

The container installs the NVIDIA **userspace** for `NVIDIA_DRIVER_VERSION` at
start – the kernel module comes from the host. After a driver update on
the host (a TrueNAS update, for example), update the variable and recreate the
container.

### Packaged NVIDIA libraries would shadow the host driver

The image has to keep `nvidia-utils` installed, and it ships the same library
names as the host driver. `ldconfig` always picks the **highest** version, so a
newer packaged driver silently wins over the host driver: the compositor falls
back to CPU rendering and the 32-bit Steam client can segfault. At every start,
the image therefore removes each packaged NVIDIA library that has a host-driver
counterpart. The log shows it:

```bash
docker logs steam-headless 2>&1 | grep -E "NVIDIA libraries|match host driver"
```

**Don't run `pacman -Syu` inside the container.** The NVIDIA packages are on
`IgnorePkg`, but everything else still drifts away from the tested state – pull
a newer image instead.

### NVENC needs driver ≥ 580 for current Sunshine

Current Sunshine releases are built against CUDA 13, which needs driver **580**
or newer. On an older driver NVENC fails and Sunshine falls back to **software
encoding** – the stream looks blurry as soon as the picture moves. This image
pins Sunshine to `v2025.628.4510`, the last CUDA-12 build, so NVENC works on
driver 570 as well.

---

## What's in it

- **Wayland desktop** – labwc with waybar, mako notifications and a right-click
  app menu, on a virtual output at the configured resolution.
- **Two ways in** – noVNC in any browser, and Sunshine for Moonlight with NVENC,
  audio, keyboard, mouse and controllers.
- **Gaming stack** from CachyOS – Steam, Heroic, Lutris, ProtonUp-Qt,
  Proton-CachyOS, wine-cachyos, gamescope, MangoHud, GameMode, Vulkan and the
  32-bit libraries.
- **Firefox and Flatpak** (Flathub pre-configured).
- **Self-repair at start** – NVIDIA libraries are checked against the host
  driver, and a Steam data layout the launcher can't use is fixed before Steam
  starts.
- **Reliable Steam menu entry** – the menu and autostart go through
  `steam-launch`, which clears a crashed client's leftover process first.
  Without it, clicking "Steam" hands over to that leftover and nothing opens.

## What it isn't

Not a public service. The web UI is plain HTTP and the container runs
**privileged with host networking** – keep it in your LAN or behind a VPN, never
expose it to the internet directly. Not a way around game DRM or anti-cheat: what
refuses to run under Proton refuses here too.

---

## Tags

| Tag | |
|---|---|
| `latest` | current state |
| `1.3` | fixed version – `WINE_CPU_TOPOLOGY` derived from the container's `cpuset`, so launchers that pin threads no longer hang |
| `1.2` | fixed version – no `udevadm trigger` against the host on container restarts, no Xorg on a host VT when Moonlight connects |
| `1.1` | fixed version – NVIDIA libraries on Debian-based hosts (TrueNAS), no module unloads, no sysctl writes, no host D-Bus |
| `1.0` | fixed version – first release; on TrueNAS use `1.3` instead |

Full documentation – architecture, NVIDIA/Wayland details, troubleshooting with
a symptom table, Moonlight pairing problems – lives in the source repository:
<https://github.com/andyxtreme/steam-headless-cachyos> (`README.md` and `docs/`).

## Credits & License

Based on **Steam-Headless** by josh5 and contributors –
<https://github.com/Steam-Headless/docker-steam-headless>, GPL-2.0. The init
system and entrypoint come from there unchanged; this edition is licensed under
**GPL-2.0** as well.

Thanks to [CachyOS](https://cachyos.org/),
[LizardByte / Sunshine](https://github.com/LizardByte/Sunshine),
[Moonlight](https://moonlight-stream.org/), [labwc](https://github.com/labwc/labwc),
[wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) and
[wayvnc](https://github.com/any1/wayvnc).

Not affiliated with, or endorsed by, Valve Corporation or NVIDIA Corporation.
