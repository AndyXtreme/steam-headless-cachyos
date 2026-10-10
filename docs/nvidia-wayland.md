# NVIDIA + headless Wayland

Headless wlroots on NVIDIA is the fiddly part of this image. This page explains
the defaults and the two host-side requirements.

## ⚠️ Host prerequisite: `nvidia-drm.modeset=1` (required)

NVIDIA Wayland/GBM does not work without kernel mode-setting on the **host**.
Check it:

```bash
cat /sys/module/nvidia_drm/parameters/modeset   # must print: Y
```

If it prints `N`, labwc fails with `gbm_bo_create failed: Permission denied` /
`DRM_IOCTL_MODE_CREATE_DUMB failed`, the headless output stays `Enabled: no`,
and wayvnc reports `No output found` — i.e. a black screen.

On **TrueNAS Scale** the module loads before "Pre Init" scripts run, so a
`modprobe.d` file written there is too late. The reliable method is an init
script under **System → Advanced Settings → Init/Shutdown Scripts → Add**
(TrueNAS 24.04 and older: System Settings → Advanced):

- **Type:** *Command*
- **When:** *Post Init*
- **Command:**

  ```
  modprobe -r nvidia_drm 2>/dev/null; modprobe nvidia_drm modeset=1
  ```

Reboot and re-check that it prints `Y`. If it still prints `N`, the app
already held the GPU when the script ran (`modprobe -r` fails with *Module
nvidia_drm is in use*; the script hides that message). Then stop the app from
starting on boot and let the script start it after the reload:

```
modprobe -r nvidia_drm 2>/dev/null; modprobe nvidia_drm modeset=1; midclt call app.start <app-name>
```

> ⚠️ The container runs **privileged**, so a `modprobe -r nvidia_drm` inside it
> unloads the module on the host — and it can't load it back (no modules for the
> host kernel in the image). `/sys/module/nvidia_drm` disappears, labwc fails
> with `Failed to open '/dev/dri/renderD128': No such device`, and noVNC reports
> *Failed to connect to downstream server*. The image therefore replaces `rmmod`
> and `modprobe` with `host-module-guard`, which refuses every unload. To
> recover, run `modprobe nvidia_drm modeset=1` on the host, then
> `docker exec <container> supervisorctl restart desktop wayvnc`.

> The original X11 steam-headless does **not** need modeset — that is the main
> trade-off of going Wayland on NVIDIA.

## Renderer defaults baked into the image

```
WLR_BACKENDS=headless,libinput
WLR_RENDERER=gles2              # NOT vulkan: NVIDIA's Vulkan lacks
                                # VK_EXT_external_memory_dma_buf, which the
                                # wlroots vulkan renderer requires -> labwc
                                # fails with "unable to create renderer".
WLR_RENDERER_ALLOW_SOFTWARE=1   # compositor falls back to CPU if GPU EGL fails;
                                # games still use the GPU via Vulkan/Proton
WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128
WLR_NO_HARDWARE_CURSORS=1
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
LIBSEAT_BACKEND=seatd
```

`WLR_RENDER_DRM_DEVICE` is pinned to the render node on purpose: without it
wlroots may pick `card0`, which needs DRM master, and `gbm_bo_create` then fails
with "Permission denied" and no output appears. Find your node with
`ls /dev/dri/`.

## Driver version

The matching NVIDIA userspace driver is installed **at container start** to
mirror the host driver (upstream `60-configure_gpu_driver.sh`). Make sure the
NVIDIA container toolkit is enabled on the host so `nvidia-smi` works inside the
container.

At boot the container downloads `NVIDIA-Linux-x86_64-<version>.run` for
`NVIDIA_DRIVER_VERSION`. If that exact version is not on NVIDIA's public
servers, boot stalls at the GPU step — set `NVIDIA_DRIVER_VERSION` to the
closest published version, see
<https://download.nvidia.com/XFree86/Linux-x86_64/>.

> **Note on the build:** the image pins the *current* `nvidia-utils`. This is
> deliberate — `cachyos-gaming-meta` only requires the virtual `nvidia-utils`,
> and in unattended mode pacman would otherwise pull the ancient
> `nvidia-390xx-utils` legacy driver, which supports neither RTX 40/50 nor
> Wayland. Don't remove that pin. The pair is taken from `[extra]`/`[multilib]`
> on purpose: `[cachyos]` is searched first but occasionally ships
> `lib32-nvidia-utils` out of step with `nvidia-utils`, which breaks the build
> with *could not satisfy dependencies*.

> ⚠️ **Packaged NVIDIA libraries shadow the host driver.** The image has to keep
> `nvidia-utils` / `lib32-nvidia-utils` installed, and both they and the host
> driver's userspace ship the same sonames (`libGLX_nvidia.so.0`,
> `libEGL_nvidia.so.0`, …). `ldconfig` links each soname to the *highest*
> version present, so whenever the packaged driver is newer than the host
> driver, every NVIDIA library resolves to the packaged version — the compositor
> falls back to CPU rendering (`EGL setup failed, disabling glamor`) and the
> 32-bit Steam client can segfault. `nvidia_gpu_install.log` warns about it.
> `60-verify_nvidia_userspace.sh` therefore deletes, at every start, each
> versioned library whose host-driver counterpart is installed and re-runs
> `ldconfig`. On Debian-based hosts such as TrueNAS Scale the toolkit mounts the
> host driver into `/usr/lib/x86_64-linux-gnu`, and nvidia-installer puts its
> 64-bit libraries there as well; the script adds that directory to the loader
> path and accepts a counterpart there too. Files the toolkit mounts stay.
>
> The NVIDIA packages are also in `IgnorePkg`, so a `pacman -Syu` inside the
> container skips them. Still, don't install or upgrade packages in the running
> container: extend the Dockerfile and rebuild.

## NVENC and the CUDA-13 trap

The latest Sunshine is built against **CUDA 13**, which needs NVIDIA driver
**≥ 580**. If the host driver is older (TrueNAS Scale currently ships **570**),
NVENC fails with `cudaErrorInsufficientDriver` and Sunshine silently falls back
to **software encoding** — which looks blurry in motion.

This image therefore pins Sunshine to `v2025.628.4510`, the last CUDA-12 build,
so NVENC works on driver 570.

⚠️ **Do not upgrade Sunshine while the host driver is < 580.** Once the host has
driver ≥ 580 you can bump `SUNSHINE_VERSION` in the [Dockerfile](../Dockerfile)
and keep `encoder = nvenc`.
