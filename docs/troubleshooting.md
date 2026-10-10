# Troubleshooting

## Where the logs are

Service logs live under the mounted home directory
(`<DATA_DIR>/home/.cache/log/`):

```
desktop.err.log     # labwc / Wayland session
wayvnc.err.log      # VNC server
novnc.err.log       # browser frontend
sunshine.err.log    # Moonlight host
steam.err.log       # Steam
```

Root-level services: `docker logs <container>` and `/var/log/supervisor/`.

## Common symptoms

| Symptom                                         | Cause / fix                                                                                       |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Black screen, `wayvnc: No output found`         | `nvidia-drm.modeset=1` not set on the host — see [nvidia-wayland.md](nvidia-wayland.md)             |
| noVNC: *Failed to connect to downstream server*, `desktop.err.log`: `Failed to open '/dev/dri/renderD128': No such device`, and `/sys/module/nvidia_drm` is missing on the host | `nvidia_drm` was unloaded on the host (`dmesg`: *nvidia-drm … Unloading driver*). The privileged container can do that but can't load it back. Reload on the host with `modprobe nvidia_drm modeset=1`, then `docker exec <container> supervisorctl restart desktop wayvnc`. Current images refuse `rmmod` / `modprobe -r` inside the container (`host-module-guard`) |
| `unable to create renderer` in `desktop.err.log`| Vulkan renderer selected; keep `WLR_RENDERER=gles2`                                                 |
| `gbm_bo_create failed: Permission denied`       | host modeset off, or the render node isn't passed through (`/dev/dri`)                              |
| Boot stalls at the GPU/driver step              | `NVIDIA_DRIVER_VERSION` isn't published by NVIDIA — pick the closest available version              |
| Steam never opens / segfaults right after launch, `desktop.err.log` shows `EGL setup failed, disabling glamor` | NVIDIA userspace doesn't match the host driver: the packaged NVIDIA libraries in the image are newer, so `ldconfig` links them instead of the host driver's (`nvidia_gpu_install.log` warns about it). Images without the pruning in `60-verify_nvidia_userspace.sh` hit this on every start - recreating the container doesn't help. Use a current image; it removes the shadowing libraries at start - also on Debian-based hosts such as TrueNAS, where the host driver's 64-bit libraries sit in `/usr/lib/x86_64-linux-gnu` (image 1.0 missed those) |
| First start on an empty home shows *Couldn't set up Steam data - please contact technical support* | `90-configure_steam.sh` pre-seeds `~/.steam/steam/config` and `steamapps`, which turns `~/.steam/steam` into a directory where Steam's launcher expects a link. Current images replace it with the link at start (`90-link_steam_data.sh`) |
| Top bar (waybar) missing, `xdg-desktop-portal` aborts with *No GSettings schemas are installed*, polkit/accounts-daemon in FATAL state | Image built while pacman 7.1's hook sandbox failed under `docker build`, so no post-install hooks ran (schemas, caches, system users). Rebuild with the current Dockerfile (`DisableSandboxNetwork`) |
| Clicking "Steam" in the menu does nothing | a crashed client left `steam -child-update-ui` holding `~/.steam/steam.pipe`, so new launches hand over to it and exit. The menu now starts Steam via `steam-launch`, which clears such leftovers |
| A game launcher (e.g. DOAXVV) stays a grey window with no input, although it works on Windows; the compose sets `cpuset` | The launcher pins a thread to a CPU outside the container's `cpuset`; `SetThreadAffinityMask` fails and it waits forever. Since 1.3 the image exports `WINE_CPU_TOPOLOGY` from the allowed CPUs at every start (`12-configure_wine_cpu_topology.sh`, see `docker logs`). On older images add `WINE_CPU_TOPOLOGY=<count>:<cpu,cpu,...> %command%` as launch option |
| Moonlight shows the image but no mouse/keyboard | the libinput/seatd input path is missing — rebuild from the current `Dockerfile`                    |
| Stream blurry when looking around               | software encoder instead of NVENC — see the [CUDA-13 trap](nvidia-wayland.md#nvenc-and-the-cuda-13-trap) |
| Desktop / Moonlight resolution jumps to odd sizes (e.g. `1118x701`) | noVNC "remote resizing" resized the headless output to the browser window. Current image starts wayvnc with `--disable-resizing`; on older images reset it with `wlr-randr --output HEADLESS-1 --custom-mode ${DISPLAY_SIZEW}x${DISPLAY_SIZEH}@${DISPLAY_REFRESH}` |
| Steam doesn't start                             | `ENABLE_STEAM=false` in `.env`, or check `steam.err.log`                                            |

## Moonlight pairing fails with "check the PIN"

Sunshine's CSRF protection can block the web UI when it is reached by IP. Pair
from the host instead, which bypasses CSRF:

```bash
CID=$(docker ps --format '{{.Names}}' | grep steam-headless)
docker exec -it "$CID" bash -c "curl -sk -u 'admin:YOUR_SUNSHINE_PASS' -H 'Content-Type: application/json' -d '{\"pin\":\"1234\",\"name\":\"moonlight\"}' https://localhost:47990/api/pin"
```

Replace `1234` with the PIN shown by Moonlight and `YOUR_SUNSHINE_PASS` with
`SUNSHINE_PASS` from your `.env`. It returns `{"status":true}` on success.

## Tuning

* **Resolution / refresh:** `DISPLAY_SIZEW` / `DISPLAY_SIZEH` / `DISPLAY_REFRESH`
  in `.env`. Match them to the resolution requested in Moonlight for the
  sharpest image.
* **Big Picture on boot:** `STEAM_ARGS=-gamepadui`.
* **Disable Steam autostart:** `ENABLE_STEAM=false`.
* **Encoder:** Sunshine uses `nvenc` by default (see
  `<DATA_DIR>/home/.config/sunshine/sunshine.conf`); set `encoder = software`
  to compare against CPU encoding.
* **CPU pinning:** uncomment `cpuset` in [docker-compose.yml](../docker-compose.yml).
