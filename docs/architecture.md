# Architecture

How this fork differs from upstream [Steam-Headless](https://github.com/Steam-Headless/docker-steam-headless),
and how the pieces fit together.

## What changed vs. upstream

| Layer           | Upstream (X11)       | This image (Wayland)                                                                                  |
| --------------- | -------------------- | ----------------------------------------------------------------------------------------------------- |
| Base            | Arch / Debian        | `cachyos/cachyos` (x86-64-v3/v4)                                                                        |
| Compositor      | Xorg (dummy) + XFCE  | **labwc** (wlroots, headless backend)                                                                   |
| Browser capture | x11vnc → noVNC       | **wayvnc** → noVNC (same web UI)                                                                        |
| Streaming       | Sunshine (X capture) | Sunshine (wlroots screencopy + NVENC)                                                                   |
| Gaming stack    | manual packages      | **cachyos-gaming-meta** (Proton-CachyOS, gamescope, mangohud, gamemode, wine-cachyos, vulkan, lib32, …) |
| Launchers       | Steam                | **Steam + Heroic + Lutris + ProtonUp-Qt**                                                               |
| X11 apps        | native               | run via **XWayland** automatically                                                                      |

The container reuses the upstream init system (user / dbus / pulseaudio /
GPU-driver / Steam setup). Only the display layer is replaced.

## Runtime layout

```
            ┌──────────── container ────────────┐
 Browser ─▶ │ noVNC ─ wayvnc ─┐                 │
            │                 ├─ labwc (wlroots,│ ─▶ NVIDIA GPU
Moonlight ─▶│ Sunshine ───────┘   headless +    │     (render + NVENC)
            │                     libinput)     │
            │   Steam · Heroic · Lutris · games │
            └───────────────────────────────────┘
```

The compositor renders to a virtual output (`HEADLESS-1`); wayvnc serves it to
the browser and Sunshine streams it to Moonlight. Input from both paths is fed
back into the session via libinput/uinput.

## Repository layout

```
.
├── Dockerfile                # the CachyOS + Wayland image
├── docker-compose.yml        # deployment, fully driven by .env
├── .env.example              # copy to .env and edit
├── overlay/                  # upstream overlay, vendored unchanged (GPL-2.0)
├── overlay-wayland/          # this fork's Wayland layer, copied over overlay/
└── docs/                     # architecture, NVIDIA notes, troubleshooting
```

Both overlays are copied into the image root, `overlay-wayland/` last, so its
files win where names collide:

```dockerfile
COPY overlay /
COPY overlay-wayland /
```

## The Wayland layer

| File                                          | Purpose                                       |
| --------------------------------------------- | --------------------------------------------- |
| `etc/cont-init.d/11-setup_sysctl_values.sh`   | overrides upstream: only reports `vm.max_map_count` - never writes host kernel parameters |
| `etc/cont-init.d/12-configure_wine_cpu_topology.sh` | with a restricted `cpuset`, exports `WINE_CPU_TOPOLOGY` mapped onto the allowed CPUs (Windows thread-affinity masks would name CPUs the container can't use) |
| `etc/cont-init.d/30-configure_udev.sh`        | overrides upstream: always dumb-udev - never `udevadm trigger`, which writes to the host's `/sys` |
| `etc/cont-init.d/60-verify_nvidia_userspace.sh` | adds the toolkit's `/usr/lib/x86_64-linux-gnu` to the loader path and removes packaged NVIDIA libraries that shadow the host driver (ldconfig); never re-runs the installer |
| `etc/cont-init.d/90-link_steam_data.sh` | keeps `~/.steam/steam` a link to `~/.local/share/Steam` so Steam can set up a fresh home |
| `etc/cont-init.d/61-configure_nvidia_gbm.sh`  | NVIDIA GBM/EGL setup for wlroots              |
| `etc/cont-init.d/70-configure_xorg.sh`        | overrides upstream: disables Xorg/Xvfb        |
| `etc/cont-init.d/71-configure_wayvnc.sh`      | enables wayvnc instead of x11vnc              |
| `etc/cont-init.d/91-configure_audiostream.sh` | audio for the noVNC session                   |
| `etc/supervisor.d/desktop.ini`                | runs the labwc session                        |
| `etc/supervisor.d/wayvnc.ini`                 | wayvnc program                                |
| `etc/supervisor.d/vnc.ini`                    | noVNC frontend (without x11vnc)               |
| `etc/supervisor.d/seatd.ini`                  | seat management for libinput                  |
| `etc/supervisor.d/accounts-daemon.ini`        | accounts daemon override for the Wayland session |
| `etc/makepkg.conf.d/10-download-retries.conf` | makepkg download retries on TLS errors (also used at build time) |
| `templates/sunshine/sunshine.conf`            | NVENC defaults, no XFCE prep command          |
| `usr/bin/start-wayland-session.sh`            | launches labwc (+ panel, + Steam)             |
| `usr/bin/start-dumb-udev.sh`                  | overrides upstream: input device nodes for Sunshine, without restarting Xorg (no X server in this image) |
| `usr/bin/host-module-guard`                   | installed as `rmmod` / `modprobe`: the privileged container must never unload host kernel modules (e.g. `nvidia_drm`) |
| `usr/bin/start-wayvnc.sh`                     | wayvnc launcher                               |
| `usr/bin/start-sunshine.sh`                   | Wayland-aware Sunshine launcher               |
| `usr/bin/steam-launch`                        | starts Steam, clearing leftovers of a crashed client |

See [nvidia-wayland.md](nvidia-wayland.md) for why the renderer and driver
settings are what they are.
