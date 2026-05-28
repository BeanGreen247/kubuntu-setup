# Changelog

All notable changes to kubuntu-setup are documented here.
Format: newest entry first, grouped by day.

---
## 2026-05-28

- **infra-connections.py**: add `_check_zerotier_via_iface()` fallback — when the ZeroTier auth token is unreadable and `sudo -n` fails, scan for `zt*` network interfaces via `ip -br addr show`; correctly reports ONLINE instead of "no auth (run as root)" on standard non-root desktop sessions
- **setup-kubuntu.sh**: copy `/var/lib/zerotier-one/authtoken.secret` to `~/.config/zerotier-one/authtoken.secret` after ZeroTier install so `infra-connections` can use the full REST API (node ID, network names, assigned IPs) without root; token is created at daemon first-start, no network join required

---
## 2026-05-28

- **setup-kubuntu.sh**: `_fix_dpkg()` helper added — force-removes half-configured packages and runs `apt -f install`; called at the start of every section via `hdr()` and explicitly after `deb-get` install in step 2; eliminates broken postinst scripts poisoning all subsequent apt calls (root cause of 16 failures on Resolute)
- **setup-kubuntu.sh**: `deb-get` installed as a plain executable to `/usr/local/bin` instead of via its apt repo — the apt package (0.4.x) fails its postinst on unrecognised codenames; standalone script has no postinst and always re-downloads so upstream codename fixes land automatically
- **setup-kubuntu.sh**: `mise`, `uv`, `ruff` now installed as direct precompiled binary downloads from GitHub releases (same pattern as eza/lazygit/k9s) — replaces curl-to-bash installer scripts that fail on new codenames; binary downloads detect only CPU architecture and work on any Linux release
- **setup-kubuntu.sh**: explicit firmware block added — `linux-firmware`, `intel-microcode`, `amd64-microcode`, `firmware-sof-signed`, `fwupd`; `fwupdmgr refresh && fwupdmgr update` run on every pass so the system is never left without current microcode or signed firmware
- **setup-kubuntu.sh**: Bluetooth architecture fix — Wine multiarch installs `bluez:i386` which hijacks `/usr/sbin/bluetoothd`, leaving a 32-bit BT daemon on an amd64 system; script now ensures `bluez:amd64` first, then purges `bluez:i386`, `blueman`, and `bluez-cups`
- **setup-kubuntu.sh**: i2c udev rule added — creates `i2c` group and `/etc/udev/rules.d/45-i2c-ddc.rules` so KDE powerdevil can access `/dev/i2c-*` for DDC/CI brightness control without `EACCES` errors at login
- **setup-kubuntu.sh**: `preload` unit file always overwritten on re-runs; `Type=forking` changed to `Type=simple` (this version of preload runs in the foreground and never forks, causing systemd to time out); `PIDFile` directive removed
- **setup-kubuntu.sh**: `whoopsie.path` added to masking loop alongside `whoopsie.service` — path unit was still logging a failed-to-start error on every boot
- **post-login-setup.py**: Next → / done-tile pattern added (matching `setup-installer.py`) — running page gets a bottom bar with progress label, progress bar, and a disabled Next → that enables on finish; Done tile activates with passed/warned counts and per-step icon summary; Next → navigates to done page without auto-transition so the user can review the log first
- **setup-kubuntu.sh / post-login-setup.py**: SSH askpass three-layer fix — overwrite the Plasma env file (`/etc/X11/Xsession.d/…`) to unset `SSH_ASKPASS` and `SSH_ASKPASS_REQUIRE` at source; keep `/etc/profile.d/99-ssh-terminal-askpass.sh` for login shells; add the same unset to `~/.bashrc` for non-login interactive shells (Konsole default) — prevents "cannot exec ksshaskpass" on every git push in Konsole

---
## 2026-05-23

- **setup-kubuntu.sh**: global `commit-msg` hook installed to `~/.config/git/hooks/commit-msg` — strips `Co-Authored-By` trailers from all major AI coding tools (Claude/Anthropic, Copilot, Cursor, Aider, Cody, Devin, Gemini, Amazon Q, Codeium, Tabnine)
- **setup-kubuntu.sh**: `prepare-commit-msg` hook added as an earlier defence layer — strips AI trailers before the editor opens, not just after commit
- **setup-kubuntu.sh**: commit-msg hook regex strengthened with GNU sed `I` flag for true case-insensitive `Co-Author` matching
- **.claude/CLAUDE.md**: project-level no-co-author rule added so `dotfile-sync` overwriting `~/.claude/CLAUDE.md` cannot re-enable AI attribution
- **setup-kubuntu.sh**: `ksshaskpass` purged if installed; `/etc/profile.d/99-ssh-terminal-askpass.sh` sets `SSH_ASKPASS_REQUIRE=never` and unsets `SSH_ASKPASS` — prevents git HTTPS auth falling back to any GUI askpass helper in terminal sessions

---
## 2026-05-21

- **setup-kubuntu.sh**: VS Code replaced with **Pulsar** as the primary editor — VS Code repo, install block, and dotfile-sync entry removed; Microsoft GPG key retained for Azure CLI; Pulsar covers all editing needs with `claude-chat` and `git-plus`
- **dotfile-sync.py**: fixed `E121: Undefined variable: g:colors_name` error
- **dotfile-sync.py / dotfile-sync-tray.py**: fixed not fetching latest files after a tool update; added custom git instances support
- **README.md**: dotfile-sync toolset documentation expanded
- **setup-kubuntu.sh**: VMware and VirtualBox installation updated for Kubuntu 26.04+ Wayland-only systems — `xserver-xorg-video-vmware` and `virtualbox-guest-x11` are Xorg-only; both wrapped in `2>/dev/null || true` fallback installs; VirtualBox 7.1+ handles clipboard/resize via `virtualbox-guest-utils` alone

---
## 2026-05-15

- **setup-kubuntu.sh (hybrid GPU)**: `KWIN_DRM_DEVICES=/dev/dri/card2` env var written — pins KWin to the AMD iGPU on PRIME on-demand laptops; prevents XWayland falling back to llvmpipe when the NVIDIA render node cannot be opened before first use
- **setup-kubuntu.sh**: Steam compat dir ownership fixed — `chown` now covers `~/.local/share/Steam` parent dir too (created root-owned by `mkdir` when script runs as root, preventing steam-installer from writing its bootstrap files)
- **setup-kubuntu.sh**: end-of-run summary updated with separate NVIDIA PRIME offload Steam launch option (`__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia MANGOHUD=1 gamemoderun %command%`)
- **setup-kubuntu.sh (GRUB)**: `pcie_aspm.policy=performance` added — prevents PCIe L1 link re-training hangs on Ryzen + NVMe (complements existing `nvme_core.ps_max=0`)
- **setup-kubuntu.sh**: NVMe udev rule adds `poll_queues=4` and `io_poll=1` via modprobe — CPU polls for NVMe completions instead of waiting for IRQ; cuts latency 30–60% after reboot
- **setup-kubuntu.sh**: NVMe udev `wbt_lat_usec=0` — disables write-back throttling (unnecessary overhead on NVMe with deep hardware queues)
- **setup-kubuntu.sh**: NTFS `fstab` entries switched to `ntfs3` in-kernel driver instead of `ntfs-3g` FUSE — 2–5× faster sequential I/O; `big_writes` dropped (not applicable to ntfs3)
- **setup-kubuntu.sh**: ext4 root fstab gets `noatime,commit=60` — makes `noatime` explicit and reduces journal commits from every 5 s to every 60 s
- **setup-kubuntu.sh (sysctl)**: `vm.min_free_kbytes=65536` — kernel keeps 64 MB always free, preventing `GFP_ATOMIC` failures that manifest as hard hangs
- **setup-kubuntu.sh**: earlyoom check interval changed 60 s → 5 s — reacts to OOM within seconds instead of letting the system thrash for up to a minute
- **setup-kubuntu.sh (sysctl/net)**: TCP socket buffers raised 128 → 256 MB; ECN enabled; autocorking disabled; RPS flow table sized; UDP socket floor set to 8 kB
- **setup-kubuntu.sh (udev/net)**: `kubuntu-set-rps` rule spreads NIC softirq across all cores on attach; `kubuntu-set-coalesce` rule disables adaptive IRQ coalescing (20–50 µs latency gain on supported NICs)
- **setup-kubuntu.sh**: `steam_dev.cfg` writes `@nClientDownloadEnableHTTP2PlatformLinux 0` — disables HTTP/2 on Linux (Steam throttle bug fix)
- **setup-kubuntu.sh (Wine)**: `winbind` + Kerberos installed for NTLM auth; `winetricks` adds `certs`, `vcrun2015`, `d3dcompiler_43`; registry tweaks disable IPv6 in prefix, disable P2P downloader, set `winhttp`/`wininet` to native-first — fixes WoW WotLK + custom server launchers
- **dotfile-sync**: `vscode/settings.json` and `claude/CLAUDE.md` added to sync list — fresh installs get VS Code and Claude Code pre-configured without manual sign-in

---
## 2026-05-14

- **setup-kubuntu.sh**: `software-properties-qt` added to explicit base packages list — ensures the Additional Drivers tool is present on fresh installs
- **setup-kubuntu.sh**: KDE Additional Drivers desktop entry created at `/usr/share/applications/software-properties-drivers-kde.desktop` — the shipped `software-properties-drivers-lxqt.desktop` has `OnlyShowIn=LXQt;` and is invisible in KDE Plasma; new entry has no `OnlyShowIn` restriction and uses `preferences-devices-cpu` (Breeze circuit-board icon); `Icon=jockey` (the old removed package) is not used
- **setup-kubuntu.sh**: VS Code repo guard extended — `vscode.sources` with `Enabled: no` (written by the Ubuntu 25.10→26.04 upgrade migration tool) is now detected and rewritten; previously the guard only checked `command -v code` so an already-installed VS Code would leave the disabled repo unfixed
- **setup-kubuntu.sh**: Docker and Kubernetes repo guards changed from `command -v <tool>` to `[[ ! -f <repo>.list ]]` — the upgrade migration renames `.list` files to `.list.disabled` (with entries commented out) regardless of whether the tool is installed; the old guard never re-added the repo if the binary was present; stale `.disabled` files are removed before writing the fresh `.list`
- **setup-kubuntu.sh**: Trivy repo setup separated from install step — repo is now added whenever `trivy.list` is missing (not only when `trivy` is not installed); `.disabled` cleanup included
- **setup-kubuntu.sh**: Tailscale block restructured — repo is restored whenever `tailscale.list` is missing even if `tailscale` is already installed; codename probe + key download run in both cases; install step remains gated on `command -v tailscale`; "repo restored" confirmation printed when only the repo was missing
- **setup-kubuntu.sh**: ZeroTier `zerotier.list.disabled` cleaned up unconditionally — ZeroTier uses `curl | bash` which manages its own repo; the `.disabled` remnant from the OS upgrade is removed on every run
- **README.md**: repositories section updated — full third-party repo list enumerated; upgrade-migration healing behaviour documented
- **README.md**: base packages updated to include `software-properties-qt`
- **README.md**: NVIDIA/NVK GPU rows updated — "Kubuntu Driver Manager" replaced with "Additional Drivers" and the correct launch path documented
- **setup-kubuntu.sh**: added `apt --fix-broken install -y` before the initial `apt-get upgrade` and before the final upgrade/cleanup pass — resolves partially-upgraded package states (e.g. `libpython3.13-stdlib` version mismatches after a mid-run failure) so subsequent installs do not fail with "Unmet dependencies"
- **setup-kubuntu.sh**: fixed `git config` calls failing with `fatal: error reading '/root/.git'` — when the script runs from a directory containing `.git`, the `GIT_DIR` env var leaks into `sudo -u $USER_NAME` and redirects git to root's repo; wrapped all five `git config --global` calls in a helper that runs `env -u GIT_DIR HOME=$USER_HOME` to clear the stale variable
- **setup-kubuntu.sh**: completion banner and file header updated from "KUBUNTU 25.10" → "KUBUNTU 26.04"
- **setup-kubuntu.sh**: GPU type validation fixed — validation block only accepted `vm` and `none`, silently replacing all other types with `vm`; now accepts all six: `nvidia amd intel hybrid vm none`; interactive default changed `vm` → `none` (safer on bare metal)
- **setup-kubuntu.sh (section 6 — AMD)**: `mesa-va-drivers` and `mesa-vdpau-drivers` no longer exist on resolute — VA-API and VDPAU are now integrated into `mesa-libgallium`; script installs `mesa-libgallium` as primary and retries old names with `2>/dev/null || true` for pre-26.04 compatibility
- **setup-kubuntu.sh (section 6 — Intel)**: `intel-media-va-driver-non-free` no longer exists on resolute (merged into the free driver); primary install now uses `intel-media-va-driver`; still attempts the non-free variant as a silent fallback for older Ubuntu
- **setup-kubuntu.sh**: GPU type selection restored — all six branches (nvidia / amd / intel / hybrid / vm / none) back in sections 6 and 7; **no driver auto-install on any path** (Driver Manager remains the intentional install path post-reboot)
  - `nvidia`: Vulkan loader + Mesa fallback ICD + 32-bit libs; explicit Driver Manager instruction
  - `amd`: Mesa + RADV Vulkan + VA-API/VDPAU + radeontop + 32-bit libs
  - `intel`: Mesa + ANV Vulkan + `intel-media-va-driver` + `intel-gpu-tools`
  - `hybrid`: AMD Mesa stack + `switcheroo-control` enabled; `prime-run` written; NVIDIA Driver Manager warning preserved
- **setup-kubuntu.sh (section 7)**: GPU env/udev branches fleshed out:
  - `amd`/`hybrid`: `AMD_VULKAN_ICD=RADV` via `/etc/environment.d/60-amd-vulkan.conf`; udev rule sets `power_dpm_force_performance_level=auto` at boot
  - `nvidia`/`hybrid`: `__GL_THREADED_OPTIMIZATIONS=1` + `__GL_SHADER_DISK_CACHE=1` via `/etc/environment.d/61-nvidia-gl.conf`
  - `intel`: `VK_ICD_FILENAMES` pointed at ANV ICDs via `/etc/environment.d/60-intel-vulkan.conf`
  - `hybrid`: `/usr/local/bin/prime-run` wrapper written (sets `DRI_PRIME=1` + NVIDIA offload env vars)
- **setup-kubuntu.sh**: `TESTED_CODENAME` updated `questing` → `resolute`; compatibility notice updated to reference Kubuntu 26.04 LTS "Resolute Raccoon", kernel 7.0.0
- **setup-kubuntu.sh**: Azure CLI repo probe simplified — try exact current codename, fall back directly to `noble`; removed unnecessary intermediate non-LTS hops
- **setup-kubuntu.sh**: Tailscale repo probe simplified the same way
- **setup-kubuntu.sh**: `sudo pwfeedback` enabled via `/etc/sudoers.d/pwfeedback` drop-in — shows `*` per keystroke when typing sudo password in terminal
- **setup-kubuntu.sh**: Spotify signing key moved from deprecated `/etc/apt/trusted.gpg.d/` to `/etc/apt/keyrings/spotify.gpg`; idempotency check re-runs migration on existing installs with the old path
- **setup-kubuntu.sh**: `apt-get download kubuntu-settings-desktop -t questing` hardcode replaced with `-t "${UBUNTU_CODENAME}"`
- **setup-kubuntu.sh**: `libfuse2t64` separated from its install block with `|| apt-get install -y libfuse2` fallback — safe on Ubuntu 22.04/24.04
- **setup-kubuntu.sh (GRUB)**: `skew_tick=1` added (jitters per-CPU timer tick start to reduce lock contention on multi-core), `random.trust_cpu=on` added (seeds kernel RNG from RDRAND, eliminates early-boot entropy stalls)
- **setup-kubuntu.sh (GRUB AMD)**: `amd_pstate=active` added — EPP-based P-State driver (better burst performance + idle power vs `acpi-cpufreq`); requires CPPC (Zen 3+)
- **README.md**: compatibility section updated to list both Kubuntu 26.04 LTS "Resolute Raccoon" and 25.10 "Questing Quetzal" as tested targets; fallback table updated to reference both codenames
- **README.md**: section count corrected from 13 → 15 in three places (files table, GUI usage paragraph, setup-installer.py section)
- **README.md**: install profiles table updated — section ranges corrected for 15-section layout; footnotes clarified

---

## 2026-05-13

- **setup-kubuntu.sh (GRUB)**: param injection fixed — both `GRUB_CMDLINE_LINUX_DEFAULT` and `GRUB_CMDLINE_LINUX` sed patterns only matched double-quoted values; Kubuntu 25.10 ships single-quoted values, so every param was silently skipped; fixed with a second sed pass for single-quote variant inside the same `|| { … }` block — no-op if the first pass already matched
- **setup-kubuntu.sh (GRUB AMD)**: added `processor.max_cstate=5` — fixes the Cezanne CC6 deep-sleep wakeup freeze (the same fix Linux Mint ships by default for this CPU family); `amd_iommu=on iommu=pt` — IOMMU passthrough mode, prevents ACPI power event hangs on hybrid AMD iGPU + NVIDIA dGPU laptops
- **setup-kubuntu.sh (GRUB)**: added `nvme_core.default_ps_max_latency_us=0` to general params (all CPUs) — prevents NVMe drives from entering PS3/PS4 deep power states that fail to resume on Ryzen mobile
- **setup-installer.py**: `SECTION_RE` was still matching `/14` after sections were renumbered to `/15` — no header lines matched, sidebar never updated and output was never segmented; fixed to `/15`
- **setup-installer.py**: `INSTALL_GROUPS` was missing the "7  GPU tweaks" entry — 14 entries for 15 sections caused every sidebar item from section 7 onward to show the wrong label; entry added, labels 8–15 renumbered
- **setup-installer.py**: "All 14 sections finished successfully." updated to 15 in both done-screen locations
- **setup-kubuntu.sh**: section 7/15 empty `else` block removed — bash requires at least one command in an `else`; caused a syntax error aborting the script at line 2485; `|| [[ "$GPU_TYPE" == "none" ]]` also removed from section 7's skip condition (only section 6 needs the `none` guard)
- **setup-kubuntu.sh**: GPU options reduced to `vm` / `none` in this session, then restored to all six types — see 2026-05-14 entry for the restored state
- **gpu-switch.py**: removed from the repo — hybrid GPU mode switcher caused a complete system lockup on launch; see `gpu-setup-commands.txt` for manual `envycontrol` / `prime-select` commands
- **gpu-setup-commands.txt**: new reference file — full manual command set for NVIDIA driver install, envycontrol hybrid switching, prime-select fallback, AMD/Intel setup, GPU monitoring
- **setup-kubuntu.sh**: added `export NEEDRESTART_MODE=a` alongside `DEBIAN_FRONTEND=noninteractive` — `needrestart` prompts interactively during every `apt-get install` if absent, hanging the script indefinitely
- **setup-kubuntu.sh (section 9/15)**: added Wayland support packages — `xwayland`, `xdg-desktop-portal-kde`, `libdecor-0-plugin-1-cairo`
- **setup-kubuntu.sh (section 12/15)**: added `PROTON_ENABLE_WAYLAND=1`
- **setup-kubuntu.sh**: new **section 14/15 — Python tooling** added between Dotfiles and Services + cleanup: `mise` (polyglot version manager), `uv` (fast Python package/venv tool), `ruff` (Python linter/formatter), `pipx`
- **setup-kubuntu.sh**: `mise` and `uv` removed from section 4 Tier-2 GitHub releases
- **setup-kubuntu.sh (NVIDIA/NVK)**: removed `##DRIVER_MANAGER_NEEDED##` sentinel and blocking `read` — replaced with a plain `info` message; all NVIDIA config steps now run unconditionally without waiting
- **setup-kubuntu.sh**: all section markers renumbered from X/14 → X/15
- **setup-installer.py**: `##DRIVER_MANAGER_NEEDED##` handler and `_open_driver_manager_mid_install` method removed; `SECTION_RE` updated; new Python tooling `INSTALL_GROUPS` entry added
- **redeploy-tools.sh**: `gpu-switch` removed from managed tools list

---

## 2026-05-12

- **setup-kubuntu.sh (NVIDIA)**: removed automatic driver installation — replaced with launch of Kubuntu Driver Manager (`software-properties-qt --open-tab 4`) opened as the logged-in user; env vars, gpu-mode switcher, mpv config, browser flags, and modprobe performance options still written and active after reboot
- **setup-kubuntu.sh (NVK)**: Driver Manager launch added before Mesa userspace install — user confirms open-source driver selection; Mesa stack and all env/config steps unchanged
- **setup-kubuntu.sh**: fixed `nvk` GPU type silently rejected by validation guard and defaulted to `vm`
- **setup-installer.py**: removed "Open Driver Manager" pre-run button; added `_open_driver_manager_mid_install()` — when script emits `##DRIVER_MANAGER_NEEDED##`, GUI opens Driver Manager via pkexec with a blocking dialog
- **setup-kubuntu.sh / setup-installer.py**: fixed wrong binary name `software-properties-kde` → `software-properties-qt`; fixed `--open-tab=4` → `--open-tab 4`; fixed `pkexec` requiring absolute path + `DISPLAY`/`WAYLAND_DISPLAY` passthrough via `env`
- **setup-kubuntu.sh (NVIDIA)**: removed `vdpauinfo`, `vaapi` (not a real package), and `nvidia-vaapi-driver` (depends on kernel driver, was silently failing)
- **setup-kubuntu.sh (NVK)**: removed redundant Mesa NVK apt install block (all packages already present on base Kubuntu)
- **setup-kubuntu.sh**: added end-of-script `╔═══╗` boxed panel for NVIDIA and NVK summarising what was skipped, what is configured, and exact Driver Manager steps

---

## 2026-05-08

- **gpu-switch.py** (new tool): PyQt6 GUI + system-tray tool for switching between Integrated / Hybrid / Dedicated GPU modes on hybrid laptops
  - Integrated — iGPU only, dGPU fully power-gated
  - Hybrid (PRIME Offload) — iGPU renders desktop, dGPU available per-app via `prime-run` / `DRI_PRIME=1`
  - Dedicated — dGPU renders everything (NVIDIA only via envycontrol; AMD/Intel Arc shown as unavailable)
  - Single-GPU machines show an info panel only
  - GPU vendor detection fixed: Intel checked first, `\bati\b` word-boundary regex for ATI/AMD
  - System tray icon (coloured circle); autostarted on login
- **setup-kubuntu.sh**: `envycontrol` installed via pip, `/usr/local/bin/gpu-switch-apply` polkit helper written, polkit action `io.github.beangreen247.gpu-switch` registered
- **setup-kubuntu.sh**: MangoHud Steam launch option fixed — `MANGOHUD=1 gamemoderun %command%` → `mangohud --dlsym gamemoderun %command%` (`--dlsym` required for OpenGL + Steam Linux Runtime container)
- **setup-kubuntu.sh**: MangoHud config updated — added `gpu_stats`, `gpu_core_clock`, `gpu_mem_clock`, `cpu_mhz`
- **setup-kubuntu.sh (Intel)**: `setcap cap_perfmon=eip` on `intel_gpu_top` after install — kernel 5.8+ requires `CAP_PERFMON` to run without sudo
- **setup-kubuntu.sh (NVIDIA/AMD)**: added 32-bit gaming runtime packages: `libvulkan1:i386`, `mesa-vulkan-drivers:i386`, `libgl1-mesa-dri:i386`, `libgbm1:i386` and for AMD: `libdrm2:i386`, `libegl1:i386`, `mesa-va-drivers:i386`
- **setup-kubuntu.sh (NVIDIA/AMD/Intel)**: fixed browser VA-API flags files being written 3× on re-runs — replaced flawed append-with-dedup logic with clean unconditional overwrite
- **redeploy-tools.sh**: `gpu-switch` added as a managed tool

---

## 2026-05-05

- **setup-kubuntu.sh**: `plasma-systemmonitor` config fully automated — 3 pages (Overview, Disks, Processes) written; History and Applications pages hidden; sidebar collapsed to icon-only; disk UUID and NIC sensor colours extracted from existing config before rewriting for portability
  - **Overview**: CPU (blue) | GPU (purple) linecharts; CPU per-core full-width; combined RAM linechart (App RAM + Page Cache + Swap); Network full-width
  - **Disks**: partition space bars + read/write throughput
- **setup-kubuntu.sh**: added `/etc/profile.d/kubuntu-mem.sh` — installs a `mem` shell function for a clean per-terminal RAM breakdown (apps / page cache / available / total in MiB)
- **setup-kubuntu.sh**: `vm.swappiness` computed dynamically from installed RAM: `≥32 GB → 1`, `≥16 GB → 3`, `≥8 GB → 7`, `<8 GB → 10`; written to `/etc/sysctl.d/99-kubuntu-perf-ram.conf`
- **setup-kubuntu.sh**: `cups-browsed.service` masked — LAN printer scan daemon; `cups.service` kept; saves ~20 MB RSS
- **setup-kubuntu.sh**: `seatd.service` disabled — redundant with `systemd-logind` on KDE Plasma; saves ~2 MB RSS
- **setup-kubuntu.sh**: `apport.service` + `whoopsie.service` masked — crash reporter and telemetry disabled; saves ~15 MB RSS combined
- **setup-kubuntu.sh**: `DefaultDeviceTimeoutSec=10s` removed from `99-kubuntu-timeouts.conf` — overrode systemd default of `infinity`, causing block devices (NTFS, slow HDD) that took >10 s to appear to fail their `.device` unit and drop to emergency mode

---

## 2026-05-04

- **setup-kubuntu.sh**: ClamAV switched from persistent daemon to on-demand scanning — `clamav-daemon` replaced with `clamav-freshclam`; `clamav-daemon.service` and `.socket` masked; recovers ~1 GB RAM; use `clamscan` manually
- **post-login-setup.py**: widened window from 800 → 960 px and step list column from 196 → 280 px
- **setup-kubuntu.sh**: audited all ~354 apt package names against Ubuntu 25.10; fixed 8 broken names:
  - `dnsutils` → `bind9-dnsutils`
  - `libfuse2` → `libfuse2t64`
  - `amd-microcode` → `amd64-microcode`
  - `libgnutls30:i386`, `libxml2:i386`, `libglib2.0-0:i386` — `_t64_pkg()` helper selects `t64`-suffixed name on 25.04+, falls back to legacy name
  - `vkd3d` bare unversioned package removed; `libvkd3d1`/`libvkd3d1:i386` already present
  - `qemu-kvm` removed — virtual metapackage gone in 25.10; `qemu-system-x86` covers it
  - `libnvidia-gl` bare fallback replaced with `warn` — dynamic versioned path already handles it
  - `sops` moved out of apt block (not in Ubuntu repos); downloaded as `.deb` from GitHub releases with `|| warn` fallback
- **README.md**: GPU driver table, gaming stack section, and virtualisation section updated to reflect corrected package names; `sops` added to CLI tooling description

---

## 2026-05-03

- **setup-kubuntu.sh**: added 6 install profiles — `full`, `full-no-infra`, `full-no-dotfiles`, `full-no-infra-no-dotfiles`, `infra`, `dotfiles`; 4 boolean skip flags derived; all sections gated accordingly
- **setup-kubuntu.sh**: `kernel.hung_task_timeout_secs` changed from `0` to `300` — prevents false-positive "task blocked" dmesg noise while still logging genuinely deadlocked processes
- **setup-installer.py**: **Profile** dropdown added; passes `--profile=VALUE` to script
- **setup-installer.py**: **Help** button added to title bar — renders `README.md` via `QTextEdit.setMarkdown()` in a `1000×700` frameless dialog; image lines stripped before rendering
- **setup-installer.py**: fixed `_toggle_maximize` method lost during Help button insertion — caused `AttributeError` on window construction, silently breaking the Continue button on the changelog splash
- **setup-installer.py**: **Done tile** added at the bottom of the step panel — shows pass/warn counts, total elapsed time, reboot reminder; auto-selects on finish and replays the full section 15 summary log
- **setup-kubuntu.sh (section 3)**: `oxygen-sounds` removed from Oxygen theme purge list — hard `Depends` of `plasma-desktop`; purging it cascade-removed all panel plasmoids; safety guard added to install `kubuntu-desktop --no-install-recommends`
- **setup-kubuntu.sh (post-login)**: launcher plugin sed fixed — target changed from `org.kde.plasma.kickerdash` to `org.kde.plasma.kicker`
- **setup-kubuntu.sh (post-login)**: plasmashell restart race condition fixed — `systemctl --user restart plasma-plasmashell.service` as primary path; manual kill+kstart only if service unit is unavailable
- **setup-kubuntu.sh (post-login)**: automated extraction of `start-here-kubuntu.svg` from `kubuntu-settings-desktop` deb without installing the full package; installed into all icon sizes of both `breeze` and `breeze-dark` themes
- **setup-kubuntu.sh (section 3)**: theme + boot cleanup block added — purges Oxygen theme packages and extra wallpaper packs; SDDM switched to Breeze with solid black background; Plymouth branded themes purged, theme set to `text`; Breeze Dark cursor set system-wide
- **setup-kubuntu.sh**: fixed `apt autoremove` cascade — `apt-mark manual $(apt-mark showauto)` now runs at script start to prevent cascade orphan removal
- **setup-kubuntu.sh (section 8)**: gaming tools added — `gamescope`, `vkbasalt`, `dxvk`, `input-remapper`, `switcheroo-control`, `s-tui`, `libadwaita`, `libayatana-appindicator3-1`, ProtonUp-Qt (Flathub), Flatseal (Flathub)
- **setup-kubuntu.sh (section 6)**: `usermod -aG video,render` added at start of GPU section
- **setup-kubuntu.sh (panel cleanup)**: `_find_applet_ids()` awk helper rewritten with `index()`/`substr()` (no regex in `sub()`, no gawk extensions) — all three cleanup loops now actually execute on mawk
- **setup-kubuntu.sh (panel cleanup)**: JS `evaluateScript`-based `writeConfig` replaced with `kwriteconfig6` direct file writes — JS writes only update in-memory state and do not persist across plasmashell restart
- **setup-kubuntu.sh**: `plasma-browser-integration` removal hardened with three layers — `apt-get remove --purge`, apt pin to `-1`, and native messaging host manifest removal
- **setup-installer.py**: NVK option added to GPU dropdown; dropdown arrow CSS fixed with `image: url(...)`; `Qt.WindowType.Tool` removed from all windows (was hiding them from Alt+Tab)
- **setup-kubuntu.sh**: `nvk` GPU branch added; `gvfs-smb` → `gvfs-backends` (renamed in 25.10)
- **post-login-setup.py**: 30-second auto-reboot countdown added on Done page
- **setup-installer.py**: title labels decoupled from release name — "Kubuntu Setup Installer" / "Kubuntu Setup — Changelog"
- **CHANGELOG.md**: created; README `## Changelog` section now points here
- **redeploy-tools.sh**: new script — clean-redeploy tooling without re-running full installer

---

## 2026-05-02

- **setup-kubuntu.sh**: UFW firewall — default-deny inbound, SSH open globally, KDE Connect on LAN, Tailscale and ZeroTier interfaces fully trusted
- **setup-kubuntu.sh**: fail2ban — `sshd` and `xrdp` jails with 4-retry / 2-hour ban policy and custom xrdp filter
- **dotfile-sync-tray / infra-connections**: GitHub repo link added to title bar
- **infra-connections**: removed unused `subprocess` import
- **.gitignore**: added to exclude `__pycache__` and compiled Python bytecode
- **README.md**: updated to document UFW rules, fail2ban jails, title bar GitHub links

---

## 2026-05-01

- **infra-connections**: new KDE system-tray tool — monitors Tailscale and ZeroTier state, colour-coded tray icon (green/yellow/red), per-hour background check, optional ping-host verification
- **dotfile-sync-tray**: fixed executable path; improved close button behaviour; added retry mechanism for tray icon registration (waits for KDE StatusNotifier host)
- **post-login-setup**: prevented re-showing wizard on subsequent logins
- **setup-installer**: added Git global config options (name, email, default branch) to the installer GUI

---

## 2026-04-07

- **setup-kubuntu.sh**: removed KWin gaming-performance script installation from main script (handled separately)
- **setup-kubuntu.sh**: ensure deployed scripts are always updated to the latest repo version on re-run
- **post-login-setup**: improved KWin script registration and notification handling; added reboot prompt
- General code cleanup and dead code removal

---

## 2026-04-06

- **post-login-setup**: sentinel file added to prevent repeated execution on subsequent logins
- **update-checker / install.sh**: self-update mechanism and daily KDE notification for new upstream commits
- **setup-kubuntu.sh / setup-installer.py**: `--yes` and `--gpu=TYPE` flags added for fully non-interactive installs
- **launch-installer.sh**: thin shell wrapper added for double-click launching from Dolphin

---

## 2026-04-05

- **post-login-setup**: new PyQt6 GUI — Wine prefix init, KWin activation, power profile selection
- **setup-kubuntu.sh**: improved zram and swapfile sizing logic for NVMe longevity

---

## 2026-04-04

- **setup-kubuntu.sh**: system performance hardening — sysctl BBR/swappiness/dirty tuning, `schedutil` CPU governor service, zram swap (zstd, priority 100), swapfile (priority 10), `limits.conf` tuning
- **dotfile-sync**: refactored sync interval to 12 hours; added `--force` flag bypassing SHA check
- **dotfile-sync-tray**: added Force Sync button and 12 h interval support
- **setup-kubuntu.sh**: Spotify repo — auto-discover current pubkey URL with fallback to known key
- **setup-kubuntu.sh**: Azure CLI / Tailscale repo fallback chains added
- **setup-kubuntu.sh**: removed Helm, Jellyfin, emulation, and 1Password from install list
- **setup-kubuntu.sh**: added KDE dark mode, disabled splash screen, removed all KWin effects on install
- **setup-kubuntu.sh**: apt lock handling; enhanced logging and per-step error handling throughout

---

## 2026-04-03

- Initial commit — `setup-kubuntu.sh`, `setup-installer.py`, `dotfile-sync.py`, `dotfile-sync-tray.py`, `apt-key-refresh.sh`, `update-checker.sh`, `install.sh`
