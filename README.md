# NVIDIA Kernel Fix

A small recovery script for Ubuntu 24.04 systems where an Ubuntu kernel upgrade
leaves the installed NVIDIA driver without a matching kernel module. This can
also cause the NVIDIA GPU to stop initializing and, on some ASUS laptops, the
backlight interface to disappear.

## Run

```bash
git clone https://github.com/ YOUR_GITHUB_USERNAME/nvidia-kernel-fix.git
cd nvidia-kernel-fix
chmod +x nvidia-kernel-fix.sh
./nvidia-kernel-fix.sh
```

Replace `YOUR_GITHUB_USERNAME` with your GitHub username. Once the repository
exists, the normal recovery workflow is just:

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/nvidia-kernel-fix.git
cd nvidia-kernel-fix
./nvidia-kernel-fix.sh
```

## What it does

- Verifies Ubuntu 24.04 LTS.
- Detects the installed NVIDIA driver branch and whether it is the `open` or
  proprietary kernel-module flavour.
- Detects the currently running kernel with `uname -r`.
- Installs the matching Ubuntu `linux-modules-nvidia-*` package.
- Refreshes module dependencies and attempts to load `nvidia`.
- Checks `nvidia-smi` and `/sys/class/backlight/`.

It does **not** purge or reinstall the NVIDIA driver, change PRIME settings,
modify GRUB, or reboot automatically. Review the output and reboot when asked.

## Notes

- Run it after booting into the kernel you want to repair.
- The script uses Ubuntu's configured APT repositories. If a third-party
  repository has a signature error, it warns and proceeds only if the required
  NVIDIA package is still available from APT.
- If `modprobe` fails, Secure Boot/module signing may need investigation.
- If the NVIDIA module loads but brightness remains unavailable after reboot,
  the issue may be ASUS WMI/backlight handling rather than a missing NVIDIA
  kernel module.

## Scope

Ubuntu 24.04 LTS (`noble`), generic HWE kernels. Other Ubuntu releases and
custom kernels are intentionally rejected rather than modified blindly.
