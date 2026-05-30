#!/bin/bash
################################################################################
#  KUBUNTU 26.04 SETUP SCRIPT
#  Gaming + Development + IT Infrastructure
#  by BeanGreen247  |  https://github.com/BeanGreen247
#
#  What gets installed:
#    BASE        : build tools, CLI utils, fonts, multimedia codecs, KDE extras
#    DEV         : Pulsar (+ claude-chat + git-plus), Python, Ansible, Docker, kubectl,
#                  Proxmox/infra Python libs, wireshark, man-pages, linux-doc
#    REMOTE ACCESS: xrdp (RDP server, port 3389) + FreeRDP3 + KRDC (RDP/VNC client)
#    SYSADMIN    : net-tools, iperf3, socat, mosh, sysstat, iotop-c, iftop, nethogs,
#                  smartmontools, nvme-cli, lvm2, gparted, lynis, fail2ban, podman
#    GPU         : AMD / NVIDIA / Intel drivers (selected at startup)
#    NTFS        : ntfs3 (in-kernel, fast), ntfs-3g (fallback FUSE), exfatprogs
#    GAMING      : Wine-staging, Steam, Discord, Heroic (Epic/GOG),
#                  Lutris (EA Desktop/Rockstar), MangoHud, GameMode, GOverlay,
#                  gamescope, vkbasalt, DXVK, vkd3d, input-remapper,
#                  switcheroo-control, s-tui, ProtonUp-Qt, Flatseal
#    MEDIA       : mpv, VLC
#    INFRA NET   : Tailscale, ZeroTier
#    VIRT        : virt-manager + QEMU/KVM
#    GAMING ENV  : shader cache dirs + /etc/environment perf vars
#    DOTFILES    : bashrc-linux + vimrc from BeanGreen247/dotfiles
#
#  Usage:
#    sudo bash setup-kubuntu.sh
#
#  Tested target: Kubuntu 25.10 (Questing Quetzal) x86_64
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ──────────────────────────────────────────────────────────────────
_LOG="${PWD}/kubuntu-setup-$(date +%Y%m%d-%H%M%S).log"
_SLOG="${_LOG%.log}.summary"
_T0=$(date +%s)
exec > >(tee -a "$_LOG") 2>&1
: > "$_SLOG"
# ─────────────────────────────────────────────────────────────────────────────

ok()   {
    echo -e "${GREEN}  ✓${NC}  $*"
    printf 'OK\t%s\n' "$*" >> "$_SLOG"
}
info() { echo -e "${BLUE}  →${NC}  $*"; }
warn() {
    echo -e "${YELLOW}  !${NC}  $*"
    printf 'WARN\t%s\n' "$*" >> "$_SLOG"
}
err()  {
    echo -e "${RED}  ✗${NC}  $*"
    printf 'ERR\t%s\n' "$*" >> "$_SLOG"
}

# Force-removes any packages stuck in a half-configured (iF/HF) dpkg state, then
# runs apt -f install to reconcile.  Called at the start of every step and after
# deb-get is installed so a broken postinst never poisons subsequent apt calls.
_fix_dpkg() {
    local broken
    broken=$(dpkg -l 2>/dev/null | awk '/^.[FH]/{print $2}' | tr '\n' ' ')
    [[ -z "${broken// /}" ]] && return 0
    warn "Broken dpkg packages detected — force-removing: ${broken}"
    for _pkg in $broken; do
        dpkg --remove --force-remove-reinstreq "$_pkg" 2>/dev/null || true
    done
    apt-get -f install -y -qq 2>/dev/null || true
    ok "dpkg state repaired"
}

TOTAL_STEPS=13
_draw_progress() {
    local step="$1" desc="$2"
    local pct=$(( step * 100 / TOTAL_STEPS ))
    printf '\033]0;[%d/%d  %d%%]  Kubuntu Setup — %s\007' \
        "$step" "$TOTAL_STEPS" "$pct" "$desc" 2>/dev/null || true
}
_clear_progress() {
    printf '\033]0;Kubuntu Setup — Complete\007' 2>/dev/null || true
}

# ERR trap — fires on any unhandled non-zero exit; captures command + recent log context
_on_err() {
    local lineno="$1" cmd="$2"
    sleep 0.05
    {
        printf 'FAIL\tline %d: %s\n' "$lineno" "$cmd"
        tail -n 12 "$_LOG" 2>/dev/null \
            | sed 's/\x1B\[[0-9;]*[mK]//g' \
            | grep -v '^[[:space:]]*$' \
            | tail -n 6 \
            | sed 's/^/\t  /'
    } >> "$_SLOG"
}
trap '_on_err $LINENO "$BASH_COMMAND"' ERR

_print_summary() {
    local elapsed=$(( $(date +%s) - _T0 ))
    local n_ok=0 n_warn=0 n_fail=0 in_fail=0
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  RUN SUMMARY${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════${NC}"
    while IFS=$'\t' read -r type msg; do
        case "$type" in
            OK)   echo -e "  ${GREEN}✓${NC}  ${msg}"; (( n_ok++ )); in_fail=0 ;;
            WARN) echo -e "  ${YELLOW}!${NC}  ${msg}"; (( n_warn++ )); in_fail=0 ;;
            ERR)  echo -e "  ${RED}✗${NC}  ${msg}"; (( n_fail++ )); in_fail=0 ;;
            FAIL) echo -e "  ${RED}✗  FAILED: ${msg}${NC}"; (( n_fail++ )); in_fail=1 ;;
            *)    [[ "$in_fail" -eq 1 ]] && echo -e "${RED}${type}${msg}${NC}" ;;
        esac
    done < "$_SLOG"
    echo ""
    printf '  Total: %dm %02ds — ' "$(( elapsed/60 ))" "$(( elapsed%60 ))"
    echo -e "${GREEN}${n_ok} passed${NC}  ${YELLOW}${n_warn} warnings${NC}  ${RED}${n_fail} failed${NC}"
    echo -e "  Full log  → ${_LOG}"
    echo -e "  Summary   → ${_SLOG}"
    echo ""
}

hdr() {
    local title="$1"
    local step_num="${title%%/*}"
    step_num="${step_num//[^0-9]/}"
    [[ "$step_num" =~ ^[0-9]+$ && "$step_num" -gt 0 ]] && _draw_progress "$step_num" "$title"
    echo -e "\n${CYAN}${BOLD}════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $*${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}"
    _fix_dpkg
}

if [[ "$1" == "--post-login" ]]; then
    POST_LOGIN_SCRIPT="$(realpath "$0")"

    if command -v wine >/dev/null 2>&1 && command -v winetricks >/dev/null 2>&1; then
        info "Initialising Wine prefix (this takes a few minutes)..."
        export WINEPREFIX="${HOME}/.wine"
        export WINEARCH="win64"
        WINEDLLOVERRIDES="mscoree,mshtml=d" wineboot --init 2>/dev/null
        ok "Wine prefix created: ${WINEPREFIX}"

        info "Installing corefonts + runtimes + D3D compilers + SSL certs via winetricks..."
        WINEDLLOVERRIDES="" winetricks -q \
            corefonts \
            vcrun2015 \
            vcrun2019 \
            d3dcompiler_43 \
            d3dcompiler_47 \
            certs \
        && ok "winetricks components installed" \
        || warn "winetricks completed with warnings — check manually if needed"
        # d3dcompiler_43: WotLK/classic WoW DX9 shader pipeline (older than _47)
        # vcrun2015: custom WoW launchers often require the 2015 CRT specifically
        # certs: installs Mozilla root certificates into the prefix so HTTPS works
        #        in custom launchers without SSL verification failures

        info "Applying Wine registry tweaks for WoW / custom server launchers..."
        # Disable IPv6 inside the Wine prefix — older WoW clients and most private
        # server emulators only speak IPv4; Wine's IPv6 path can cause getaddrinfo
        # failures on dual-stack hosts. (System IPv6 stays enabled for Docker etc.)
        wine reg add \
            "HKLM\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters" \
            /v DisabledComponents /t REG_DWORD /d 255 /f 2>/dev/null || true
        # Disable the WoW background P2P downloader — it reliably crashes under
        # Wine because it opens raw sockets that Wine does not support.
        wine reg add \
            "HKCU\\Software\\Blizzard Entertainment\\Blizzard Downloader" \
            /v "Disable Peer-to-Peer" /t REG_DWORD /d 1 /f 2>/dev/null || true
        # Set DLL load order: try native Windows DLL first, fall back to Wine's
        # builtin. Effective when the user installs a real winhttp/wininet from a
        # Windows source; no-op when no native DLL is present (safe either way).
        wine reg add "HKCU\\Software\\Wine\\DllOverrides" \
            /v winhttp /t REG_SZ /d "native,builtin" /f 2>/dev/null || true
        wine reg add "HKCU\\Software\\Wine\\DllOverrides" \
            /v wininet /t REG_SZ /d "native,builtin" /f 2>/dev/null || true
        ok "Wine registry: IPv6 disabled in prefix, P2P downloader off, winhttp/wininet override set"

        # Shut down the Wine server cleanly so no Wine processes linger at login
        info "Shutting down Wine server..."
        wineserver -k 2>/dev/null || true
        sleep 2
        # Force-kill anything that survived
        pkill -u "$(id -u)" -x wineserver  2>/dev/null || true
        pkill -u "$(id -u)" -x winedevice.exe 2>/dev/null || true
        pkill -u "$(id -u)" -x explorer.exe  2>/dev/null || true
        ok "Wine server stopped"
    else
        warn "wine or winetricks not found — skipping Wine prefix init"
    fi

    if command -v dotfile-sync >/dev/null 2>&1; then
        dotfile-sync --install-timer \
        && { systemctl --user daemon-reload 2>/dev/null; \
             systemctl --user enable --now dotfile-sync.timer 2>/dev/null; } \
        && ok "dotfile-sync timer registered and enabled" \
        || warn "dotfile-sync timer install failed — run: dotfile-sync --install-timer"
    else
        warn "dotfile-sync not found in PATH — skipping timer registration"
    fi

    info "Applying KDE power profile + display timeout settings..."
    # Ensure power-profiles-daemon is running so the profile switch takes immediate effect
    sudo systemctl enable --now power-profiles-daemon 2>/dev/null || true
    # Set AC profile via the D-Bus interface (takes effect instantly, survives reboot)
    if command -v powerprofilesctl >/dev/null 2>&1; then
        powerprofilesctl set balanced 2>/dev/null \
            && ok "Active power profile set to: balanced" \
            || warn "powerprofilesctl set failed — will apply via kwriteconfig only"
    fi
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        # Power profiles
        kwriteconfig6 --file powermanagementprofilesrc --group AC         --key powerProfile balanced
        kwriteconfig6 --file powermanagementprofilesrc --group Battery    --key powerProfile balanced
        kwriteconfig6 --file powermanagementprofilesrc --group LowBattery --key powerProfile power-saver
        # Screen off: never on AC, 20 min on battery
        kwriteconfig6 --file powermanagementprofilesrc --group AC      --group DPMSControl --key idleTime 0
        kwriteconfig6 --file powermanagementprofilesrc --group AC      --group DimDisplay  --key idleTime 0
        kwriteconfig6 --file powermanagementprofilesrc --group AC      --group SuspendSession --key idleTime 0
        kwriteconfig6 --file powermanagementprofilesrc --group Battery --group DPMSControl --key idleTime 1200000
        kwriteconfig6 --file powermanagementprofilesrc --group Battery --group DimDisplay  --key idleTime 900000
        ok "Power profiles: AC=balanced  Battery=balanced  LowBattery=power-saver"
        ok "Screen timeout: AC=never  Battery=off@20min (dim@15min)"

        info "Applying KWin compositor performance tweaks (eye candy kept)..."
        # OpenGL Core Profile — best performance on modern Mesa/NVIDIA
        kwriteconfig6 --file kwinrc --group Compositing --key Backend OpenGL
        kwriteconfig6 --file kwinrc --group Compositing --key GLCore true
        # Don't keep off-screen/minimised windows in VRAM — frees GPU memory
        kwriteconfig6 --file kwinrc --group Compositing --key HiddenPreviews 5
        # Let fullscreen windows bypass compositor for direct rendering (games)
        kwriteconfig6 --file kwinrc --group Compositing --key WindowsBlockCompositing true
        # Adaptive vsync: compositor syncs when possible, skips when overloaded
        kwriteconfig6 --file kwinrc --group Compositing --key VsyncMode Adaptive
        # Lower scheduler latency tolerance for snappier input response
        kwriteconfig6 --file kwinrc --group Compositing --key LatencyPolicy Low
        # Animations fully disabled — zero overhead, instant window response
        kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0
        # Sharper subpixel font rendering (assumes LCD with standard RGB stripe)
        kwriteconfig6 --file kdeglobals --group General --key XftHintStyle hintfull
        kwriteconfig6 --file kdeglobals --group General --key XftSubPixel rgb
        ok "KWin: OpenGL/GLCore, HiddenPreviews=5, adaptive vsync, low latency policy"
        ok "KDE: animations disabled, hintfull + RGB subpixel fonts"

        info "Applying KDE appearance settings (dark mode · no splash · no eye candy)..."
        # ── KDE splash screen ──────────────────────────────────────────────────
        kwriteconfig6 --file ksplashrc --group KSplash --key Engine none
        kwriteconfig6 --file ksplashrc --group KSplash --key Theme  None
        # ── Disable ALL KWin effects: eye-candy, overview, animations ──────────
        for _fx in blur contrast wobblywindows \
                   kwin4_effect_fadingpopups kwin4_effect_login kwin4_effect_logout \
                   kwin4_effect_morphingpopups kwin4_effect_translucency \
                   slide slidingpopups \
                   overview windowview desktopgrid \
                   minimizeanimation magiclamp glide scale fallapart sheet \
                   desktopchangeosd snaphelper dimscreen zoom trackmouse mouseclick; do
            kwriteconfig6 --file kwinrc --group Plugins --key "${_fx}Enabled" false
        done
        # ── Launch feedback: no bouncing icon, no spinning cursor ──────────────
        # BusyCursor  = animated cursor while app loads (spinning/watch)
        # TaskbarButton = bouncing taskbar button — visible on every app launch
        kwriteconfig6 --file klaunchrc --group FeedbackStyle --key BusyCursor   false
        kwriteconfig6 --file klaunchrc --group FeedbackStyle --key TaskbarButton false
        # ── Dark colour scheme ─────────────────────────────────────────────────
        kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark
        kwriteconfig6 --file kdeglobals --group KDE     --key LookAndFeelPackage org.kde.breezedark.desktop
        plasma-apply-colorscheme BreezeDark 2>/dev/null || true
        # ── Icon theme: KDE default Breeze only ────────────────────────────────
        kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze
        # ── Cursor theme: Breeze Dark ──────────────────────────────────────────
        kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme Breeze_Dark
        kwriteconfig6 --file kdeglobals --group KDE    --key cursorTheme  Breeze_Dark
        # ── Hot corners / screen edges: all disabled ───────────────────────────
        for _edge in Bottom BottomLeft BottomRight Left Right Top TopLeft TopRight; do
            kwriteconfig6 --file kwinrc --group ElectricBorders --key "$_edge" None
        done
        # ── Texture filter: bilinear — desktop compositing needs no trilinear ──
        # 0=nearest  1=bilinear  2=trilinear — saves marginal GPU work on every repaint
        kwriteconfig6 --file kwinrc --group Compositing --key GLTextureFilter 1
        # ── Window decoration shadows: none — reduces GPU fill rate + VRAM ─────
        kwriteconfig6 --file breezerc --group Windeco --key ShadowSize             ShadowNone
        kwriteconfig6 --file breezerc --group Windeco --key DrawBackgroundGradient false
        # ── Baloo file indexer: disable — saves CPU, I/O, RAM ─────────────────
        kwriteconfig6 --file baloofilerc --group "Basic Settings" --key "Indexing-Enabled" false
        command -v balooctl6 >/dev/null 2>&1 && balooctl6 disable 2>/dev/null || \
        command -v balooctl  >/dev/null 2>&1 && balooctl  disable 2>/dev/null || true
        # ── KDE Activities: disable background tracking daemon ─────────────────
        # Activities manager runs a background service + journaling even when
        # no virtual Activities are in use — wastes CPU + disk on weak hardware.
        kwriteconfig6 --file kactivitymanagerdrc --group "main" --key "enabled" false
        # ── Recent documents: disable file-open history tracking ───────────────
        # KDE writes every opened file to ~/.local/share/recently-used.xbel;
        # disabling saves small but constant I/O and a kderecentdocuments D-Bus call.
        kwriteconfig6 --file kdeglobals --group "RecentDocuments" --key "UseRecentDocuments" false
        # ── KDE thumbnail generation: limit size + disable remote sources ──────
        # Dolphin generates thumbnails for every image/video it encounters in a
        # directory. On HDD this means a seek + read of every file just to browse.
        # MaximumSize caps which files get thumbnailed (0 = no size limit, but we
        # use a small value so only tiny files are processed).
        # EnableRemoteFolderThumbnail=false stops thumbnail I/O over CIFS/SFTP mounts.
        # MaximumRemoteSize=0 prevents any remote file thumbnailing.
        kwriteconfig6 --file kiorc --group "Thumbnail" --key "MaximumSize"               5242880
        kwriteconfig6 --file kiorc --group "Thumbnail" --key "EnableRemoteFolderThumbnail" false
        kwriteconfig6 --file kiorc --group "Thumbnail" --key "MaximumRemoteSize"          0
        ok "KDE performance: bilinear texture filter, no window shadows, Baloo disabled, activities off, no recent-docs, thumbnail I/O limited"
        # ── Wallpaper: solid black (no image) on every virtual desktop ─────────
        # Calls the live PlasmaShell scripting API — works because plasmashell is
        # already running when the post-login autostart fires.
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            'var ds=desktops();for(var i=0;i<ds.length;i++){var d=ds[i];d.wallpaperPlugin="org.kde.color";d.currentConfigGroup=["Wallpaper","org.kde.color","General"];d.writeConfig("Color","0,0,0");}' \
            2>/dev/null || \
        qdbus  org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            'var ds=desktops();for(var i=0;i<ds.length;i++){var d=ds[i];d.wallpaperPlugin="org.kde.color";d.currentConfigGroup=["Wallpaper","org.kde.color","General"];d.writeConfig("Color","0,0,0");}' \
            2>/dev/null || true
        # ── Panel / system-tray cleanup + clock seconds ───────────────────────
        # kwriteconfig6 writes directly to the on-disk config file so changes
        # are present when plasmashell starts fresh after the restart below.
        # The JS evaluateScript approach only writes to in-memory state and is
        # not reliable across a plasmashell restart — replaced entirely here.
        _PLASMA_CFG="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
        if [[ -f "$_PLASMA_CFG" ]]; then
            # Helper: print "containment_id applet_id" for every applet matching plugin.
            # Uses only index()/substr() — no regex in sub(), no gawk extensions.
            # mawk (Ubuntu default) rejects \[ inside sub() regex and 3-arg match().
            _find_applet_ids() {
                awk -v p="$1" '
                    index($0, "[Containments][") == 1 && index($0, "][Applets][") > 0 { hdr = $0 }
                    $0 == "plugin=" p && hdr != "" {
                        cid = substr(hdr, 16, index(hdr, "][Applets][") - 16)
                        tmp = substr(hdr, index(hdr, "][Applets][") + 11)
                        aid = substr(tmp, 1, length(tmp) - 1)
                        print cid, aid
                    }
                ' "$_PLASMA_CFG"
            }

            # System tray: hide clipboard, media player, browser integration
            _HIDDEN="org.kde.plasma.clipboard,org.kde.plasma.mediacontroller,org.kde.plasma.browser_integration,plasma_browser_integration"
            while read -r _cid _aid; do
                kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
                    --group "Containments" --group "$_cid" \
                    --group "Applets" --group "$_aid" \
                    --group "Configuration" --group "General" \
                    --key "hiddenItems" "$_HIDDEN"
            done < <(_find_applet_ids "org.kde.plasma.systemtray")

            # Icon task manager: strip Settings + Discover from pinned launchers
            while read -r _cid _aid; do
                _cur=$(kreadconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
                    --group "Containments" --group "$_cid" \
                    --group "Applets" --group "$_aid" \
                    --group "Configuration" --group "General" \
                    --key "launchers" 2>/dev/null || true)
                _new=$(printf '%s' "$_cur" \
                    | sed 's|,\?applications:org\.kde\.discover\.desktop||g' \
                    | sed 's|,\?applications:systemsettings\.desktop||g' \
                    | sed 's|,\?applications:org\.kde\.systemsettings\.desktop||g' \
                    | sed 's|,\?org\.kde\.discover\.desktop||g' \
                    | sed 's|^,\+||; s|,\+$||; s|,,\+|,|g')
                kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
                    --group "Containments" --group "$_cid" \
                    --group "Applets" --group "$_aid" \
                    --group "Configuration" --group "General" \
                    --key "launchers" "$_new"
            done < <(_find_applet_ids "org.kde.plasma.icontasks")

            # Digital clock: always show seconds (0=never 1=tooltip 2=always)
            while read -r _cid _aid; do
                kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
                    --group "Containments" --group "$_cid" \
                    --group "Applets" --group "$_aid" \
                    --group "Configuration" --group "Appearance" \
                    --key "showSeconds" "2"
            done < <(_find_applet_ids "org.kde.plasma.digitalclock")

            ok "Panel config written to disk  (taskbar: Settings+Discover removed · tray: clipboard/media/browser-integration hidden · clock: seconds on)"
        else
            warn "Plasma config not found — panel cleanup skipped (re-run --post-login after first login)"
        fi

        # Show Desktop widget: must be removed via live JS API (widget removal
        # cannot be done via config file — it requires plasmashell to be running).
        _showdesktop_rm='var allPanels = panels();
for (var i = 0; i < allPanels.length; i++) {
    var al = allPanels[i].widgets();
    for (var j = al.length - 1; j >= 0; j--) {
        if (al[j].type === "org.kde.plasma.showdesktop") { al[j].remove(); }
    }
}'
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$_showdesktop_rm" 2>/dev/null \
            || qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$_showdesktop_rm" 2>/dev/null \
            || true
        # ── Launcher: Kickoff / kickerdash → classic Application Menu (kicker) ──
        # Edits the live panel config then restarts plasmashell to apply it.
        # _PLASMA_CFG is already defined in the panel cleanup block above.
        # org.kde.plasma.kicker     = classic Win-95-style hierarchical popup (wanted)
        # org.kde.plasma.kickoff    = default Kubuntu launcher (favorites + search)
        # org.kde.plasma.kickerdash = full-screen Application Dashboard (not wanted)
        if [[ -f "$_PLASMA_CFG" ]] && grep -qE 'plugin=org\.kde\.plasma\.(kickoff|kickerdash)$' "$_PLASMA_CFG"; then
            sed -i -E 's/plugin=org\.kde\.plasma\.(kickoff|kickerdash)$/plugin=org.kde.plasma.kicker/g' "$_PLASMA_CFG" \
                && ok "Launcher: → classic Application Menu (kicker)" \
                || warn "Launcher switch (sed) failed"
            # Restart plasmashell to pick up all config changes from this block.
            # Plasma 6 manages plasmashell via systemd --user (plasma-plasmashell.service
            # with Restart=on-failure). Restart through the service so systemd stays in
            # control and avoids the race where a manual kill triggers a systemd restart
            # concurrently with our own kstart attempt (two instances, both crash).
            if systemctl --user restart plasma-plasmashell.service 2>/dev/null; then
                sleep 3
            else
                kquitapp6 plasmashell 2>/dev/null \
                    || pkill -x plasmashell 2>/dev/null || true
                sleep 1
                if   command -v kstart >/dev/null 2>&1; then nohup kstart plasmashell &>/dev/null & disown
                else                                         nohup plasmashell        &>/dev/null & disown
                fi
                sleep 3
            fi
        else
            if [[ -f "$_PLASMA_CFG" ]]; then
                info "Kickoff not found in panel config — launcher already changed or non-default layout"
                # Still restart to pick up panel/clock/tray config changes above.
                # Use systemctl --user as primary on Plasma 6.
                if systemctl --user restart plasma-plasmashell.service 2>/dev/null; then
                    sleep 3
                else
                    kquitapp6 plasmashell 2>/dev/null \
                        || pkill -x plasmashell 2>/dev/null || true
                    sleep 1
                    if   command -v kstart >/dev/null 2>&1; then nohup kstart plasmashell &>/dev/null & disown
                    else                                         nohup plasmashell        &>/dev/null & disown
                    fi
                    sleep 3
                fi
            else
                warn "Plasma panel config not found — panel changes not applied (login and re-run if needed)"
            fi
        fi
        ok "KDE appearance: dark mode, no splash, all effects off, no launch feedback, no shadows, Baloo disabled, activities off, no recent-docs, kicker launcher, panel cleaned, Breeze icons, no hot corners, black wallpaper"

        # ── plasma-systemmonitor: write Overview + Disks pages ───────────────
        # Overview layout (top → bottom):
        #   row-0 : CPU total linechart  |  GPU linechart
        #   row-1 : CPU per-core linechart (full width)
        #   row-2 : RAM combined linechart — App RAM (blue) + Page Cache (orange) + Swap (pink)
        #           Y-axis autoscales to max visible value so changes are always readable
        #   row-3 : Network linechart (full width)
        # Disks page layout:
        #   row-0 : Disk Space horizontal bars (all partitions, full width)
        #   row-1 : Disk Read linechart  |  Disk Write linechart
        # 3 pages: Overview + Disks + Processes. applications.page deleted.
        _PSM_DIR="${HOME}/.local/share/plasma-systemmonitor"
        _PSM_OV="${_PSM_DIR}/overview.page"
        mkdir -p "$_PSM_DIR"

        # Preserve disk UUID color from existing config
        _DISK_COLOR_LINE="disk/(?!all).*/used=61,174,233"
        if [[ -f "$_PSM_OV" ]]; then
            _DISK_SPEC=$(grep -oP 'disk/[a-f0-9-]{8,}/used' "$_PSM_OV" 2>/dev/null | head -1)
            [[ -n "$_DISK_SPEC" ]] && _DISK_COLOR_LINE="${_DISK_SPEC}=61,174,233"
        fi
        # Preserve NIC-specific download/upload colors from existing config
        _NET_DL_COLOR="network/(?!all).*/download=61,174,233"
        _NET_UL_COLOR="network/(?!all).*/upload=206,61,233"
        if [[ -f "$_PSM_OV" ]]; then
            _DL=$(grep -oP 'network/\S+/download=\S+' "$_PSM_OV" 2>/dev/null | head -1)
            _UL=$(grep -oP 'network/\S+/upload=\S+'   "$_PSM_OV" 2>/dev/null | head -1)
            [[ -n "$_DL" ]] && _NET_DL_COLOR="$_DL"
            [[ -n "$_UL" ]] && _NET_UL_COLOR="$_UL"
        fi

        cat > "$_PSM_OV" << OVERVIEW_EOF
[Face-106123380916688][Appearance]
Title=CPU
chartFace=org.kde.ksysguard.linechart

[Face-106123380916688][SensorColors]
cpu/all/usage=61,174,233

[Face-106123380916688][Sensors]
highPrioritySensorIds=["cpu/all/usage"]
totalSensors=["cpu/all/usage"]

[Face-106123406501568][Appearance]
Title=GPU
chartFace=org.kde.ksysguard.linechart

[Face-106123406501568][SensorColors]
gpu/all/usage=161,61,233

[Face-106123406501568][Sensors]
highPrioritySensorIds=["gpu/all/usage"]
totalSensors=["gpu/all/usage"]

[Face-210000000000010][Appearance]
Title=CPU Cores
chartFace=org.kde.ksysguard.linechart

[Face-210000000000010][Sensors]
highPrioritySensorIds=["cpu/(?!all).*/usage"]
totalSensors=["cpu/all/usage"]

[Face-210000000000001][Appearance]
Title=RAM
chartFace=org.kde.ksysguard.linechart

[Face-210000000000001][SensorColors]
memory/physical/application=29,153,243
memory/physical/cache=246,116,0
memory/swap/used=233,61,130

[Face-210000000000001][Sensors]
highPrioritySensorIds=["memory/physical/application","memory/physical/cache","memory/swap/used"]

[Face-210000000000030][Appearance]
Title=Network
chartFace=org.kde.ksysguard.linechart

[Face-210000000000030][SensorColors]
${_NET_DL_COLOR}
${_NET_UL_COLOR}

[Face-210000000000030][Sensors]
highPrioritySensorIds=["network/(?!all).*/download","network/(?!all).*/upload"]

[page]
Title=Overview
actionsFace=
icon=speedometer
loadType=
margin=2
version=1

[page][row-0]
heightMode=balanced
isTitle=false
name=row-0

[page][row-0][column-0]
name=column-0
noMargins=
showBackground=true

[page][row-0][column-0][section-0]
face=Face-106123380916688
isSeparator=false
name=section-0

[page][row-0][column-1]
name=column-1
noMargins=
showBackground=true

[page][row-0][column-1][section-0]
face=Face-106123406501568
isSeparator=false
name=section-0

[page][row-1]
heightMode=balanced
isTitle=false
name=row-1

[page][row-1][column-0]
name=column-0
noMargins=
showBackground=true

[page][row-1][column-0][section-0]
face=Face-210000000000010
isSeparator=false
name=section-0

[page][row-2]
heightMode=balanced
isTitle=false
name=row-2

[page][row-2][column-0]
name=column-0
noMargins=
showBackground=true

[page][row-2][column-0][section-0]
face=Face-210000000000001
isSeparator=false
name=section-0

[page][row-3]
heightMode=balanced
isTitle=false
name=row-3

[page][row-3][column-0]
name=column-0
noMargins=
showBackground=true

[page][row-3][column-0][section-0]
face=Face-210000000000030
isSeparator=false
name=section-0
OVERVIEW_EOF

        # ── disks.page ────────────────────────────────────────────────────────
        _PSM_DISKS="${_PSM_DIR}/disks.page"
        cat > "$_PSM_DISKS" << DISKS_EOF
[Face-310000000000001][Appearance]
Title=Disk Space
chartFace=org.kde.ksysguard.horizontalbars

[Face-310000000000001][SensorColors]
${_DISK_COLOR_LINE}

[Face-310000000000001][Sensors]
highPrioritySensorIds=["disk/(?!all).*/used"]
totalSensors=["disk/(?!all).*/total"]

[Face-310000000000002][Appearance]
Title=Disk Read
chartFace=org.kde.ksysguard.linechart

[Face-310000000000002][SensorColors]
disk/all/read=61,174,233

[Face-310000000000002][Sensors]
highPrioritySensorIds=["disk/all/read"]

[Face-310000000000003][Appearance]
Title=Disk Write
chartFace=org.kde.ksysguard.linechart

[Face-310000000000003][SensorColors]
disk/all/write=233,120,61

[Face-310000000000003][Sensors]
highPrioritySensorIds=["disk/all/write"]

[page]
Title=Disks
actionsFace=
icon=drive-harddisk
loadType=
margin=2
version=1

[page][row-0]
heightMode=balanced
isTitle=false
name=row-0

[page][row-0][column-0]
name=column-0
noMargins=
showBackground=true

[page][row-0][column-0][section-0]
face=Face-310000000000001
isSeparator=false
name=section-0

[page][row-1]
heightMode=balanced
isTitle=false
name=row-1

[page][row-1][column-0]
name=column-0
noMargins=
showBackground=true

[page][row-1][column-0][section-0]
face=Face-310000000000002
isSeparator=false
name=section-0

[page][row-1][column-1]
name=column-1
noMargins=
showBackground=true

[page][row-1][column-1][section-0]
face=Face-310000000000003
isSeparator=false
name=section-0
DISKS_EOF

        # Hide system default pages via hiddenPages config key (checked by PSM's isHidden())
        # and set page order so only Overview → Disks → Processes appear in the sidebar.
        # old-history.page is a kconf_update leftover that also needs suppressing.
        rm -f "${_PSM_DIR}/applications.page" "${_PSM_DIR}/memory-detail.page" \
              "${_PSM_DIR}/old-history.page"
        kwriteconfig6 --file systemmonitorrc --group General \
            --key hiddenPages "history.page,old-history.page,applications.page"
        kwriteconfig6 --file systemmonitorrc --group General \
            --key pageOrder "overview.page,disks.page,processes.page"
        kwriteconfig6 --file systemmonitorrc --group General \
            --key sidebarCollapsed "true"
        ok "plasma-systemmonitor: Overview + Disks pages written; History/Applications hidden; sidebar icon-only; 3 pages: Overview → Disks → Processes"

        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null \
            || qdbus org.kde.KWin /KWin reconfigure 2>/dev/null \
            || true
    else
        warn "kwriteconfig6 not found — KDE power/performance tweaks skipped"
    fi

    # Mark post-login as done — autostart condition checks this file and skips
    # the entry on all subsequent logins even if the script exited non-zero.
    _DONE_DIR="${HOME}/.local/share/kubuntu-setup"
    mkdir -p "${_DONE_DIR}"
    touch "${_DONE_DIR}/.post-login-done"
    rm -f "${HOME}/.config/autostart/kubuntu-post-login.desktop"

    notify-send -u normal -i applications-games \
        "Kubuntu Setup" \
        "Post-login setup complete!\nWine prefix + KWin gaming script are ready." 2>/dev/null || true

    echo ""
    echo -e "  ${GREEN}Wine prefix:${NC}   ~/.wine  (win64)"
    echo -e "  ${GREEN}KWin script:${NC}   gaming-performance (compositing disabled for games)"
    echo -e "  ${GREEN}Next steps:${NC}    See the original setup summary above"
    echo ""
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    err "Run as root:  sudo bash $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a          # suppress needrestart service-restart prompts

# Freeze all currently-installed packages as manually-installed so that
# apt autoremove later in the script cannot cascade-remove them when we
# remove metapackages (kubuntu-desktop, plasma-desktop) that depended on
# the themes/wallpapers we are about to purge.
apt-mark manual $(apt-mark showauto) 2>/dev/null || true

# ── Wait for dpkg/apt lock ────────────────────────────────────────────────────
# Ubuntu's unattended-upgrades daemon often holds the lock on fresh installs.
# Stop it for the duration of setup, wait for any remaining lock holders, then
# re-enable it at the end.
_apt_lock_wait() {
    info "Stopping unattended-upgrades for the duration of setup..."
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
    systemctl kill --kill-who=all apt-daily.service apt-daily-upgrade.service 2>/dev/null || true

    local waited=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
              /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if (( waited == 0 )); then
            warn "dpkg lock held by another process — waiting (max 5 min)..."
        fi
        sleep 5
        (( waited += 5 ))
        if (( waited >= 300 )); then
            warn "dpkg lock wait timed out — removing stale lock files"
            rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
                  /var/cache/apt/archives/lock
            dpkg --configure -a 2>/dev/null || true
            break
        fi
    done
    [[ $waited -gt 0 ]] && ok "dpkg lock released after ${waited}s" || true
}
_apt_lock_wait

# ── CLI argument parsing (used by GUI launcher to skip interactive prompts) ──
_ARG_GPU=""
_ARG_USER=""
_ARG_YES=0
_ARG_PROFILE=""
for _arg in "$@"; do
    case "$_arg" in
        --gpu=*)     _ARG_GPU="${_arg#--gpu=}" ;;
        --user=*)    _ARG_USER="${_arg#--user=}" ;;
        --yes)       _ARG_YES=1 ;;
        --profile=*) _ARG_PROFILE="${_arg#--profile=}" ;;
    esac
done

# ── Install profile ──────────────────────────────────────────────────────────
# full      — everything (default): repos, base, multimedia, dev, remote access,
#             GPU drivers, filesystem, gaming, networking, virtualisation,
#             performance hardening, dotfiles, services + cleanup
# infra     — no gaming stack, no multimedia extras, no gaming-specific GPU flags;
#             installs: repos, base, dev (no gaming libs), remote access, GPU
#             (drivers only), networking, virtualisation, perf, dotfiles, services
# dotfiles  — only dotfile deployment and sync daemon registration; all other
#             sections are skipped; no package installs, no kernel changes
INSTALL_PROFILE="${_ARG_PROFILE,,}"
case "$INSTALL_PROFILE" in
    full|full-no-infra|full-no-dotfiles|full-no-infra-no-dotfiles|infra|dotfiles) ;;
    "")  INSTALL_PROFILE="full" ;;
    *)
        warn "Unknown profile '${INSTALL_PROFILE}' — valid: full, full-no-infra, full-no-dotfiles, full-no-infra-no-dotfiles, infra, dotfiles; defaulting to full"
        INSTALL_PROFILE="full"
        ;;
esac

# ── Section skip flags (derived from INSTALL_PROFILE) ────────────────────────────────
#   _SKIP_INFRA    — 5/15 remote access, 10/15 networking, 11/15 virtualisation
#   _SKIP_GAMING   — 9/15 gaming stack, gaming-env portion of 12/15
#   _SKIP_DOTFILES — 13/15 dotfiles
#   _DOTFILES_ONLY — run only 13/15; skip all other sections
_SKIP_INFRA=0
_SKIP_GAMING=0
_SKIP_DOTFILES=0
_DOTFILES_ONLY=0
case "$INSTALL_PROFILE" in
    full)                      ;;
    full-no-infra)             _SKIP_INFRA=1 ;;
    full-no-dotfiles)          _SKIP_DOTFILES=1 ;;
    full-no-infra-no-dotfiles) _SKIP_INFRA=1; _SKIP_DOTFILES=1 ;;
    infra)                     _SKIP_GAMING=1 ;;
    dotfiles)                  _DOTFILES_ONLY=1 ;;
esac
ok "Install profile: ${INSTALL_PROFILE}"

# Resolve non-root username: CLI arg → SUDO_USER → PKEXEC_UID → logname
if [[ -n "$_ARG_USER" ]]; then
    USER_NAME="$_ARG_USER"
else
    USER_NAME="${SUDO_USER:-}"
    if [[ -z "$USER_NAME" || "$USER_NAME" == "root" ]]; then
        if [[ -n "${PKEXEC_UID:-}" ]]; then
            USER_NAME=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
        fi
    fi
    if [[ -z "$USER_NAME" || "$USER_NAME" == "root" ]]; then
        USER_NAME=$(logname 2>/dev/null || true)
    fi
    if [[ -z "$USER_NAME" || "$USER_NAME" == "root" ]]; then
        read -rp "Enter the non-root username to configure: " USER_NAME
    fi
fi

USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
if [[ -z "$USER_HOME" ]]; then
    err "Cannot determine home directory for '${USER_NAME}'"
    exit 1
fi

# GPU type: CLI arg → interactive prompt
if [[ -n "$_ARG_GPU" ]]; then
    GPU_TYPE="${_ARG_GPU,,}"
else
    echo ""
    echo -e "${CYAN}${BOLD}  GPU Driver Selection${NC}"
    echo "  nvidia  — NVIDIA dGPU (Vulkan loader installed; use Driver Manager after reboot)"
    echo "  amd     — AMD iGPU / dGPU (Mesa + RADV + VA-API)"
    echo "  intel   — Intel iGPU (Mesa + ANV + VA-API)"
    echo "  hybrid  — AMD iGPU + NVIDIA dGPU (switcheroo-control + prime-run)"
    echo "  vm      — virtio-gpu / SPICE + Mesa virgl (QEMU/KVM guests)"
    echo "  none    — skip GPU setup entirely"
    echo ""
    read -rp "  Enter GPU type [nvidia/amd/intel/hybrid/vm/none] (default: none): " GPU_TYPE
    GPU_TYPE="${GPU_TYPE,,}"
fi
if [[ -z "$GPU_TYPE" ]]; then
    GPU_TYPE="none"
fi
if [[ "$GPU_TYPE" != "nvidia" && "$GPU_TYPE" != "amd" && \
      "$GPU_TYPE" != "intel" && "$GPU_TYPE" != "hybrid" && \
      "$GPU_TYPE" != "vm" && "$GPU_TYPE" != "none" ]]; then
    warn "Unknown GPU type '${GPU_TYPE}' — valid: nvidia amd intel hybrid vm none — defaulting to 'none'"
    GPU_TYPE="none"
fi

UBUNTU_CODENAME=$(lsb_release -cs)
UBUNTU_MAJOR=$(lsb_release -sr | cut -d. -f1)   # e.g. 26 for 26.04
HOST_ARCH=$(dpkg --print-architecture)
GE_CACHE="${PWD}/.ge-cache"
mkdir -p "$GE_CACHE"

TESTED_CODENAME="resolute"
if [[ "$UBUNTU_CODENAME" != "$TESTED_CODENAME" ]]; then
    echo ""
    echo -e "${YELLOW}${BOLD}  ⚠  Compatibility notice${NC}"
    echo -e "  This script was written and tested against Kubuntu 26.04 LTS (${TESTED_CODENAME})."
    echo -e "  You are running: $(lsb_release -sd)  (${UBUNTU_CODENAME})"
    echo ""
    echo -e "  Most packages will install fine on other Ubuntu releases."
    echo -e "  Known caveats on older/newer codenames:"
    echo -e "    • deadsnakes PPA skipped on 26.04+ (conflicts with system python3.13-minimal); Python 3.13 is in Ubuntu main"
    echo -e "    • WineHQ and some PPAs are codename-specific — the script falls back gracefully"
    echo ""
    if [[ $_ARG_YES -eq 0 ]]; then
        read -rp "  Continue anyway? [y/N]: " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    else
        echo "  --yes flag set, continuing automatically."
    fi
fi

echo ""
echo -e "${CYAN}${BOLD}  Setup Summary${NC}"
echo "  User          : $USER_NAME  ($USER_HOME)"
echo "  GPU type      : $GPU_TYPE"
echo "  Ubuntu release: $(lsb_release -sd)  ($UBUNTU_CODENAME)"
echo ""
if [[ $_ARG_YES -eq 0 ]]; then
    read -rp "  Continue? [y/N]: " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
else
    echo "  --yes flag set, continuing automatically."
fi

set_env_var() {
    local key="$1" value="$2" line="${1}=${2}"
    if grep -qE "^${key}=" /etc/environment 2>/dev/null; then
        sed -i "s|^${key}=.*|${line//\$/\\$}|" /etc/environment
        info "env updated  : $line"
    else
        echo "$line" >> /etc/environment
        info "env appended : $line"
    fi
}

hdr "1/15  System update + repositories"
if (( _DOTFILES_ONLY )); then
    info "1/15 skipped  (profile: ${INSTALL_PROFILE})"
else
cat > /etc/apt/apt.conf.d/99-kubuntu-setup << 'APTCFG_EOF'
Acquire::Languages "none";
Acquire::http::Pipeline-Depth "5";
APTCFG_EOF

_ensure_component() {
    local comp="$1"
    if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]] && \
       grep -qP "^Components:.*\b${comp}\b" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null; then
        info "  ${comp}: already in ubuntu.sources — skipped (avoids duplicate W: warnings)"
    else
        add-apt-repository -y "$comp" >/dev/null 2>&1 \
            && info "  ${comp}: enabled" \
            || warn "  ${comp}: enabling failed (non-fatal)"
    fi
}
_ensure_component universe
_ensure_component multiverse
_ensure_component restricted

info "Ensuring base Ubuntu repositories are present (full Kubuntu installer set)..."
# Checks that ubuntu.sources has deb-src, all four components, backports, security, and updates.
_ubuntu_sources_complete() {
    local f="/etc/apt/sources.list.d/ubuntu.sources" cn="$1"
    [[ -f "$f" ]]                                                          || return 1
    grep -qP "^Types:.*\bdeb-src\b"                          "$f"          || return 1
    grep -qP "^Suites:.*\b${cn}-backports\b"                 "$f"          || return 1
    grep -qP "^Suites:.*\b${cn}-security\b"                  "$f"          || return 1
    grep -qP "^Suites:.*\b${cn}-updates\b"                   "$f"          || return 1
    grep -qP "^Components:.*\buniverse\b"                    "$f"          || return 1
    grep -qP "^Components:.*\bmultiverse\b"                  "$f"          || return 1
    return 0
}

_UBUNTU_DEB822="/etc/apt/sources.list.d/ubuntu.sources"
_UBUNTU_FALLBACK_SOURCES="/etc/apt/sources.list.d/ubuntu-full.sources"

if _ubuntu_sources_complete "${UBUNTU_CODENAME}"; then
    info "  ubuntu.sources already complete — skipped"

elif [[ -f "${_UBUNTU_DEB822}" ]]; then
    info "  ubuntu.sources exists but is incomplete — patching..."

    # Add deb-src to any Types line that only has "deb"
    sed -i 's/^Types: deb$/Types: deb deb-src/' "${_UBUNTU_DEB822}"

    # Ensure the archive stanza (the one with the release suite) includes updates + backports
    for _suite in "${UBUNTU_CODENAME}-updates" "${UBUNTU_CODENAME}-backports"; do
        if ! grep -qP "^Suites:.*\b${_suite}\b" "${_UBUNTU_DEB822}"; then
            # Append to the Suites line that already contains the base codename
            sed -i "/^Suites:.*\b${UBUNTU_CODENAME}\b/ s/$/ ${_suite}/" "${_UBUNTU_DEB822}"
        fi
    done

    # Ensure security suite is in the security stanza (may be a separate stanza)
    if ! grep -qP "^Suites:.*\b${UBUNTU_CODENAME}-security\b" "${_UBUNTU_DEB822}"; then
        # Append a complete security stanza at the end
        cat >> "${_UBUNTU_DEB822}" << SECREPO_EOF

## Ubuntu security updates (appended by kubuntu-setup)
Types: deb deb-src
URIs: http://security.ubuntu.com/ubuntu/
Suites: ${UBUNTU_CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
SECREPO_EOF
    fi

    # Ensure all four components are present on every Components line
    sed -i 's/^Components: main restricted$/Components: main restricted universe multiverse/' \
        "${_UBUNTU_DEB822}"
    sed -i 's/^Components: main$/Components: main restricted universe multiverse/' \
        "${_UBUNTU_DEB822}"

    ok "  ubuntu.sources patched (deb-src · updates · backports · security · universe · multiverse)"

else
    # No DEB822 file — check for legacy classic-format repos before writing
    _classic_present=0
    grep -rqE "^\s*deb\s+http://(archive|security)\.ubuntu\.com/ubuntu\s+${UBUNTU_CODENAME}" \
        /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null && _classic_present=1

    if [[ "${_classic_present}" -eq 1 ]]; then
        info "  Classic sources.list entries found — writing supplemental DEB822 file for deb-src + backports"
    else
        info "  No Ubuntu base repos found — writing full DEB822 sources file"
    fi

    # Write a complete DEB822 file matching exactly what the Kubuntu 25.10 installer produces
    cat > "${_UBUNTU_FALLBACK_SOURCES}" << BASEREPO_EOF
## Ubuntu distribution repository — written by kubuntu-setup
## Mirrors what the Kubuntu 25.10 installer places in /etc/apt/sources.list.d/ubuntu.sources

Types: deb deb-src
URIs: http://archive.ubuntu.com/ubuntu/
Suites: ${UBUNTU_CODENAME} ${UBUNTU_CODENAME}-updates ${UBUNTU_CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

## Ubuntu security updates
Types: deb deb-src
URIs: http://security.ubuntu.com/ubuntu/
Suites: ${UBUNTU_CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
BASEREPO_EOF
    ok "  Full base repos written → ${_UBUNTU_FALLBACK_SOURCES}"
    ok "  Suites  : ${UBUNTU_CODENAME}  ${UBUNTU_CODENAME}-updates  ${UBUNTU_CODENAME}-backports  ${UBUNTU_CODENAME}-security"
    ok "  Types   : deb  deb-src"
    ok "  Comps   : main  restricted  universe  multiverse"
fi

dpkg --add-architecture i386

info "Checking Canonical Partners repository..."
if curl -fsLm 15 --head \
       "http://archive.canonical.com/ubuntu/dists/${UBUNTU_CODENAME}/Release" \
       >/dev/null 2>&1; then
    add-apt-repository -y \
        "deb http://archive.canonical.com/ubuntu ${UBUNTU_CODENAME} partner" \
        >/dev/null 2>&1 || true
    ok "  Canonical Partners repo enabled"
else
    warn "  Canonical Partners: no Release for ${UBUNTU_CODENAME} — skipped"
fi

_add_ppa() {
    local ppa="$1" desc="${2:-}"
    local ppa_path="${ppa#ppa:}"
    local probe_url="https://ppa.launchpadcontent.net/${ppa_path}/ubuntu/dists/${UBUNTU_CODENAME}/Release"
    if ! curl -fsLm 15 --head "$probe_url" >/dev/null 2>&1; then
        warn "  PPA skipped : $ppa  (no ${UBUNTU_CODENAME} Release — avoids E: errors)"
        return 0
    fi
    add-apt-repository -y --no-update "$ppa" >/dev/null 2>&1 \
        && info "  PPA added   : $ppa  ($desc)" \
        || warn "  PPA skipped : $ppa  (add-apt-repository failed)"
}

info "Adding PPAs for broadest software coverage..."
# deadsnakes conflicts with Ubuntu 26.04+ python3.13-minimal package split
# (overwrite error on /usr/bin/python3.13 and sitecustomize.py); Python 3.13
# ships in Ubuntu 26.04 main so the PPA is not needed there anyway.
# Also actively remove it if a previous script run already added it.
if (( UBUNTU_MAJOR < 26 )); then
    _add_ppa ppa:deadsnakes/ppa "Python 3.9–3.13 (jammy/noble/plucky only — skipped on 26.04+)"
else
    if grep -rl "deadsnakes" /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null | grep -q .; then
        add-apt-repository -r -y ppa:deadsnakes/ppa >/dev/null 2>&1 || \
            find /etc/apt/sources.list.d/ -name "*deadsnakes*" -delete
        warn "  PPA removed : ppa:deadsnakes/ppa  (was present from prior run — conflicts with ${UBUNTU_CODENAME} python3.13-minimal; removed)"
    else
        info "  PPA skipped : ppa:deadsnakes/ppa  (Python 3.13 in ${UBUNTU_CODENAME} main — PPA conflicts with system python3.13-minimal)"
    fi
fi
_add_ppa ppa:git-core/ppa               "Latest git"
_add_ppa ppa:graphics-drivers/ppa       "NVIDIA optional drivers + Mesa updates"
_add_ppa ppa:kubuntu-ppa/backports      "Newer Plasma / KDE packages"
_add_ppa ppa:ubuntu-toolchain-r/test    "GCC 11 / 12 / 13 / 14"
_add_ppa ppa:libreoffice/ppa            "Latest LibreOffice"
_add_ppa ppa:fish-shell/release-3       "Fish shell"
_add_ppa ppa:longsleep/golang-backports "Go language versions"
_add_ppa ppa:ondrej/php                 "PHP 7.4 / 8.0 / 8.1 / 8.2 / 8.3"
_add_ppa ppa:obsproject/obs-studio      "OBS Studio"
_add_ppa ppa:linuxuprising/java         "Oracle Java / OpenJDK installer"
_add_ppa ppa:ansible/ansible            "Latest Ansible"
_add_ppa ppa:danielrichter2007/grub-customizer "Grub Customizer"

if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]]; then
    info "Adding Google Chrome repository..."
    [[ ! -f /usr/share/keyrings/google-chrome.gpg ]] && \
        wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --batch --yes --dearmor | tee /usr/share/keyrings/google-chrome.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
http://dl.google.com/linux/chrome/deb/ stable main" \
        | tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
    ok "  Google Chrome repo added  (apt install google-chrome-stable)"
fi

if [[ ! -f /etc/apt/sources.list.d/signal-xenial.list ]]; then
    info "Adding Signal Desktop repository..."
    [[ ! -f /usr/share/keyrings/signal-desktop-keyring.gpg ]] && \
        wget -qO- https://updates.signal.org/desktop/apt/keys.asc \
        | gpg --batch --yes --dearmor | tee /usr/share/keyrings/signal-desktop-keyring.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] \
https://updates.signal.org/desktop/apt xenial main" \
        | tee /etc/apt/sources.list.d/signal-xenial.list > /dev/null
    ok "  Signal Desktop repo added  (apt install signal-desktop)"
fi

if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
    info "Adding NodeSource repository (Node.js 22 LTS)..."
    [[ ! -f /usr/share/keyrings/nodesource.gpg ]] && \
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --batch --yes --dearmor | tee /usr/share/keyrings/nodesource.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/nodesource.gpg] \
https://deb.nodesource.com/node_22.x nodistro main" \
        | tee /etc/apt/sources.list.d/nodesource.list > /dev/null
    ok "  NodeSource (Node.js 22 LTS) repo added  (apt install nodejs)"
fi

if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
    info "Adding GitHub CLI repository..."
    [[ ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]] && \
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --batch --yes --dearmor \
        | tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    ok "  GitHub CLI repo added  (apt install gh)"
fi

if [[ ! -f /etc/apt/sources.list.d/hashicorp.list ]]; then
    info "Adding HashiCorp repository (Terraform, Vault, Packer, Consul)..."
    [[ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]] && \
        curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --batch --yes --dearmor \
        | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    ok "  HashiCorp repo added  (apt install terraform vault packer consul)"
fi

# Remove Helm repo if it was added by a previous run of this script
if [[ -f /etc/apt/sources.list.d/helm-stable-debian.list ]]; then
    rm -f /etc/apt/sources.list.d/helm-stable-debian.list \
          /usr/share/keyrings/helm.gpg
    ok "  Helm repo removed (no longer used)"
fi

info "Setting up Flatpak + Flathub..."
apt-get install -y flatpak 2>/dev/null && \
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null && \
    ok "  Flatpak installed + Flathub remote added" \
    || warn "  Flatpak setup failed (non-fatal)"

info "Installing KeePassXC (password manager)..."
apt-get install -y keepassxc 2>/dev/null \
    && ok "  KeePassXC installed" \
    || warn "  KeePassXC install failed (non-fatal)"

if [[ ! -f /etc/apt/sources.list.d/spotify.list ]] \
    || ! grep -q 'signed-by' /etc/apt/sources.list.d/spotify.list \
    || grep -q 'trusted.gpg.d' /etc/apt/sources.list.d/spotify.list; then
    info "Adding Spotify repository..."
    # Auto-discover the current pubkey URL from Spotify's repo index (key ID is in the filename)
    _SPOTIFY_KEY_URL=$(curl -sLm 15 https://download.spotify.com/debian/ \
        | grep -oP 'href="\Kpubkey_[A-F0-9]+\.asc(?=")' \
        | tail -1)
    if [[ -n "$_SPOTIFY_KEY_URL" ]]; then
        _SPOTIFY_KEY_URL="https://download.spotify.com/debian/${_SPOTIFY_KEY_URL}"
    else
        warn "  Could not auto-discover Spotify key URL — using known fallback"
        _SPOTIFY_KEY_URL="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc"
    fi
    mkdir -p /etc/apt/keyrings
    curl -sS "${_SPOTIFY_KEY_URL}" \
        | gpg --batch --yes --dearmor -o /etc/apt/keyrings/spotify.gpg
    chmod 644 /etc/apt/keyrings/spotify.gpg
    rm -f /etc/apt/trusted.gpg.d/spotify.gpg
    echo "deb [signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free" \
        | tee /etc/apt/sources.list.d/spotify.list > /dev/null \
    && ok "  Spotify repo added  (apt install spotify-client)" \
    || warn "  Spotify repo failed (non-fatal)"
fi

info "Deploying apt-key-refresh..."
SCRIPT_DIR_AKR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
if [[ -f "${SCRIPT_DIR_AKR}/apt-key-refresh.sh" ]]; then
    install -m 755 "${SCRIPT_DIR_AKR}/apt-key-refresh.sh" /usr/local/sbin/apt-key-refresh
    ok "apt-key-refresh deployed from repo"
else
    wget -q https://raw.githubusercontent.com/BeanGreen247/kubuntu-setup/main/apt-key-refresh.sh \
        -O /usr/local/sbin/apt-key-refresh \
    && chmod +x /usr/local/sbin/apt-key-refresh \
    && ok "apt-key-refresh downloaded from GitHub" \
    || warn "apt-key-refresh download failed — copy apt-key-refresh.sh to /usr/local/sbin/apt-key-refresh manually"
fi

cat > /etc/systemd/system/apt-key-refresh.service << 'AKRSVC_EOF'
[Unit]
Description=Refresh third-party apt repository signing keys
Documentation=https://github.com/BeanGreen247/kubuntu-setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/apt-key-refresh
StandardOutput=journal
StandardError=journal
AKRSVC_EOF

cat > /etc/systemd/system/apt-key-refresh.timer << 'AKRTMR_EOF'
[Unit]
Description=Weekly apt signing-key refresh

[Timer]
# Run 10 min after every boot (catches rotated keys on fresh installs)
OnBootSec=10min
# Then weekly from that point
OnUnitActiveSec=7d
Persistent=true

[Install]
WantedBy=timers.target
AKRTMR_EOF

systemctl daemon-reload
systemctl enable --now apt-key-refresh.timer
ok "apt-key-refresh timer registered (weekly + OnBootSec=10min)"

info "Running apt-key-refresh to validate all signing keys..."
/usr/local/sbin/apt-key-refresh 2>&1 | grep -v '^→' || true

_cleanup_sources_and_keys() {
    info "Running repository health-check..."
    local tmp_out broken=0 dupes=0 fixed_keys=0 failed_keys=0
    tmp_out=$(apt-get update 2>&1 || true)

    info "  Checking for unreachable sources..."
    local repo_url src_file
    while IFS= read -r line; do
        [[ "$line" =~ ^E:\ The\ repository\ \'([^\']+)\'\ does\ not\ have\ a\ Release\ file ]] || continue
        repo_url=$(awk '{print $1}' <<< "${BASH_REMATCH[1]}")
        while IFS= read -r src_file; do
            [[ -z "$src_file" ]] && continue
            warn "  Removed unreachable source: $(basename "$src_file")  [$repo_url]"
            rm -f "$src_file"
            (( broken++ )) || true
        done < <(grep -rl "$repo_url" /etc/apt/sources.list.d/ 2>/dev/null)
    done <<< "$tmp_out"
    [[ $broken -gt 0 ]] \
        && ok "  Removed $broken unreachable source(s)" \
        || info "  All sources reachable"

    info "  Checking for duplicate source entries..."
    local -a to_remove=()
    local rest file1 file2 remove already f
    while IFS= read -r line; do
        [[ "$line" != *"configured multiple times in"* ]] && continue
        rest="${line##*configured multiple times in }"
        file1=$(awk '{print $1}' <<< "$rest" | sed 's/:[0-9]*$//')
        file2=$(awk '{print $3}' <<< "$rest" | sed 's/:[0-9]*$//')
        [[ -f "$file1" && -f "$file2" ]] || continue
        if   [[ "$file1" == *.sources && "$file2" == *.list ]]; then remove="$file2"
        elif [[ "$file2" == *.sources && "$file1" == *.list ]]; then remove="$file1"
        elif [[ "$file1" == *ubuntu.sources ]];                  then remove="$file2"
        else                                                          remove="$file2"
        fi
        already=false
        for f in "${to_remove[@]+"${to_remove[@]}"}"; do
            [[ "$f" == "$remove" ]] && { already=true; break; }
        done
        $already || to_remove+=("$remove")
    done <<< "$tmp_out"
    if [[ ${#to_remove[@]} -gt 0 ]]; then
        for f in "${to_remove[@]}"; do
            [[ -f "$f" ]] || continue
            warn "  Removed duplicate source: $(basename "$f")"
            rm -f "$f"
            (( dupes++ )) || true
        done
        ok "  Removed $dupes duplicate source file(s)"
    else
        info "  No duplicate sources detected"
    fi

    info "  Checking for missing signing keys..."
    local -a keys=()
    local k seen kk ks fetched
    while IFS= read -r line; do
        [[ "$line" =~ NO_PUBKEY\ ([A-F0-9]+) ]] || continue
        k="${BASH_REMATCH[1]}"
        seen=false
        for kk in "${keys[@]+"${keys[@]}"}"; do
            [[ "$kk" == "$k" ]] && { seen=true; break; }
        done
        $seen || keys+=("$k")
    done <<< "$tmp_out"

    if [[ ${#keys[@]} -eq 0 ]]; then
        info "  All repository signing keys present"
    else
        warn "  Missing signing keys: ${keys[*]}"
        local KGD="/etc/apt/trusted.gpg.d"
        mkdir -p "$KGD"
        for k in "${keys[@]}"; do
            info "  Fetching key ${k}..."
            fetched=false
            for ks in \
                "hkps://keyserver.ubuntu.com" \
                "hkp://keyserver.ubuntu.com:80" \
                "hkps://keys.openpgp.org" \
                "hkp://pgp.mit.edu:80"
            do
                if gpg --no-default-keyring \
                       --keyring "gnupg-ring:${KGD}/auto-${k}.gpg" \
                       --keyserver "$ks" \
                       --recv-keys "$k" 2>/dev/null; then
                    chmod 644 "${KGD}/auto-${k}.gpg" 2>/dev/null || true
                    ok "  Key ${k} fetched from ${ks}"
                    fetched=true
                    (( fixed_keys++ )) || true
                    break
                fi
            done
            if ! $fetched; then
                warn "  Key ${k} unavailable on all tried keyservers — repo will produce signature warnings"
                (( failed_keys++ )) || true
            fi
        done
        [[ $fixed_keys  -gt 0 ]] && ok "  Auto-fetched ${fixed_keys} missing signing key(s)"
        [[ $failed_keys -gt 0 ]] && warn "  ${failed_keys} key(s) could not be fetched automatically"
    fi

    ok "Repository health-check complete  (broken: ${broken}  dupes: ${dupes}  keys fixed: ${fixed_keys})"
}
_cleanup_sources_and_keys

info "Running apt-get update..."
if ! apt-get update -qq; then
    warn "apt-get update failed — waiting 30 s then retrying..."
    sleep 30
    apt-get update -qq || warn "apt-get update still has errors — continuing"
fi
dpkg --configure -a 2>/dev/null || true
apt --fix-broken install -y 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true
apt-get dist-upgrade -y -qq

ok "System repositories configured"
fi  # ─── end: 1/15 ───

hdr "2/15  Base system packages"
if (( _DOTFILES_ONLY )); then
    info "2/15 skipped  (profile: ${INSTALL_PROFILE})"
else

apt-get install -y \
    build-essential cmake pkg-config \
    gcc g++ gdb strace ltrace \
    curl wget git git-lfs tig \
    vim nano tmux screen \
    htop btop fastfetch \
    tree bat fd-find ripgrep fzf \
    jq p7zip-full unzip unrar tar xz-utils \
    rsync rclone \
    openssh-server sshfs sshpass \
    nmap ncat netcat-openbsd tcpdump traceroute mtr-tiny \
    lsof pciutils usbutils dmidecode lshw hwinfo inxi \
    bind9-dnsutils bind9-host \
    lm-sensors \
    ca-certificates apt-transport-https gnupg \
    software-properties-common \
    software-properties-qt \
    python3 python3-pip python3-venv python3-dev pipx \
    python3-pyqt6 \
    nodejs \
    zsh \
    libnotify-bin \
    timeshift \
    apt-file \
    command-not-found \
    synaptic
# libfuse2: AppImage support — renamed libfuse2t64 in Ubuntu 25.04+ (t64 ABI transition)
apt-get install -y libfuse2t64 2>/dev/null || apt-get install -y libfuse2 2>/dev/null || true

# The shipped software-properties-drivers-lxqt.desktop has OnlyShowIn=LXQt; so it
# never appears in KDE Plasma's app menu or System Settings. Create a KDE-visible
# equivalent so "Additional Drivers" / "Driver Manager" is reachable without a CLI.
info "Creating KDE Additional Drivers desktop entry..."
cat > /usr/share/applications/software-properties-drivers-kde.desktop << 'EOF'
[Desktop Entry]
Name=Additional Drivers
GenericName=Additional Drivers
Comment=Configure third-party and proprietary drivers
Exec=pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY software-properties-qt --open-tab=4
Icon=preferences-devices-cpu
Terminal=false
Type=Application
Categories=Settings;HardwareSettings;System;
Keywords=Drivers;
X-Ubuntu-Gettext-Domain=software-properties
EOF
ok "KDE Additional Drivers desktop entry created"

info "Installing networking + remote connectivity tools..."
apt-get install -y \
    net-tools \
    ipcalc \
    socat \
    iperf3 \
    arp-scan \
    whois \
    ldnsutils \
    mosh \
    || true
ok "Networking tools installed  (net-tools, socat, iperf3, arp-scan, mosh)"

info "Installing LLVM toolchain + build systems + static analysis..."
apt-get install -y \
    clang \
    lldb \
    meson \
    ninja-build \
    valgrind \
    shellcheck \
    || true
ok "LLVM + build tools installed  (clang, lldb, meson, ninja, valgrind, shellcheck)"

info "Installing modern CLI utilities..."
apt-get install -y \
    xclip xsel \
    pv \
    moreutils \
    parallel \
    entr \
    ncdu \
    duf \
    zoxide \
    aria2 \
    || true
apt-get install -y httpie 2>/dev/null || true
ok "Modern CLI utilities installed"

apt-get install -y grub-customizer 2>/dev/null \
    || warn "grub-customizer not available for ${UBUNTU_CODENAME} — install manually if needed"

info "Building apt-file index (used to find which package provides a file)..."
apt-file update >/dev/null 2>&1 || true
update-command-not-found >/dev/null 2>&1 || true

ln -sf /usr/bin/batcat   /usr/local/bin/bat   2>/dev/null || true
ln -sf /usr/bin/fdfind   /usr/local/bin/fd    2>/dev/null || true

ok "Base packages installed"

# ── Firmware: CPU microcode + SOF audio + fwupd ──────────────────────────────
# Installed explicitly so a fresh install is never left without microcode updates
# or signed firmware even if no recommends are pulled in.
info "Installing firmware packages..."
apt-get install -y \
    linux-firmware \
    intel-microcode \
    amd64-microcode \
    firmware-sof-signed \
    iucode-tool \
    fwupd \
    fwupd-signed 2>/dev/null || true
# Refresh fwupd metadata and silently apply any available firmware updates
if command -v fwupdmgr &>/dev/null; then
    fwupdmgr refresh --force 2>/dev/null || true
    fwupdmgr update --no-reboot-check -y 2>/dev/null || true
fi
ok "Firmware: linux-firmware + intel-microcode + SOF + fwupd installed and up to date"

# ── Bluetooth: ensure amd64 bluez; remove Wine's i386 variant + unused extras ─
# Wine multiarch pulls in bluez:i386 which hijacks /usr/sbin/bluetoothd —
# the system ends up running a 32-bit BT daemon. Install the proper amd64
# package first, then purge the i386 variant.
# blueman   — duplicate GTK-based BT GUI; bluedevil is the KDE-native equivalent.
# bluez-cups — Bluetooth printing; not used on this workstation.
info "Ensuring proper amd64 Bluetooth stack..."
apt-get install -y --no-install-recommends bluez bluetooth 2>/dev/null || true
apt-get purge -y bluez:i386 blueman bluez-cups 2>/dev/null || true
apt-get autoremove -y --purge 2>/dev/null || true
ok "Bluetooth: amd64 bluez ensured; bluez:i386 / blueman / bluez-cups removed"

info "APT discovery: 'apt-file search <file>' — find which pkg provides any file"
info "APT discovery: type unknown command in shell — bash will suggest package"

info "Installing deb-get (standalone script — no apt package, no postinst breakage)..."
# Install deb-get as a plain executable rather than via its apt repo.
# The apt-packaged deb-get (0.4.x) fails its postinst on unrecognised Ubuntu
# codenames, leaving dpkg in a broken state that poisons every subsequent
# apt-get call.  A standalone script has no postinst and works on any release.
# Always re-download so upstream fixes for new codenames land automatically.
_DEBGET_BIN=/usr/local/bin/deb-get
if curl -fsSLm 30 \
        "https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get" \
        -o "${_DEBGET_BIN}.tmp" 2>/dev/null; then
    mv "${_DEBGET_BIN}.tmp" "${_DEBGET_BIN}"
    chmod +x "${_DEBGET_BIN}"
    ok "deb-get installed as standalone script  (${_DEBGET_BIN})"
elif [[ -x "${_DEBGET_BIN}" ]]; then
    ok "deb-get already present  (network unavailable — keeping existing)"
else
    warn "deb-get install failed — will fall back to direct downloads"
fi
unset _DEBGET_BIN
dg_install() {
    local PKG="$1"
    if command -v deb-get &>/dev/null; then
        DEBGET_TOKEN="${DEBGET_TOKEN:-}" deb-get install "${PKG}" 2>/dev/null && return 0
    fi
    return 1
}
_fix_dpkg
fi  # ─── end: 2/15 ───

hdr "3/15  Multimedia codecs, KDE extras, fonts"
if (( _DOTFILES_ONLY )); then
    info "3/15 skipped  (profile: ${INSTALL_PROFILE})"
else

echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
    | debconf-set-selections

apt-get install -y \
    ubuntu-restricted-extras \
    ffmpeg \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-vaapi \
    mpv vlc \
    pavucontrol \

apt-get install -y \
    kdialog \
    plasma-systemmonitor \
    ksystemstats \
    kde-spectacle \
    okular \
    ark \
    || true

# ── KDE core apps — ensure present (removed by calamares minimal install) ─────
# dolphin: file manager — the primary GUI file browser
# kdeconnect: phone/desktop integration (clipboard, files, notifications)
# kimageformat-plugins: adds JPEG-XL, AVIF, HEIC support to all KDE apps
apt-get install -y \
    dolphin \
    kdeconnect \
    kimageformat-plugins \
    || true

apt-get install -y \
    ttf-mscorefonts-installer \
    fonts-liberation fonts-liberation2 \
    fonts-dejavu fonts-dejavu-extra \
    fonts-noto fonts-noto-cjk fonts-noto-extra \
    fonts-font-awesome \
    fonts-firacode \
    fonts-jetbrains-mono \
    fonts-ubuntu fonts-ubuntu-console \
    fonts-roboto \
    fonts-open-sans \
    fonts-hack \
    fonts-powerline \
    fonts-inconsolata \
    fonts-cascadia-code \
    || true

info "Installing Brave Browser (deb-get adds apt repo for auto-updates)..."
if ! dg_install brave-browser; then
    warn "deb-get brave-browser failed — falling back to official apt repo"
    [[ ! -f /usr/share/keyrings/brave-browser-archive-keyring.gpg ]] && \
        curl -fsS https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
        | gpg --batch --yes --dearmor \
        | tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
        | tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
    apt-get update -qq
    apt-get install -y brave-browser \
        || warn "Brave Browser install failed"
fi
ok "Brave Browser installed"

info "Installing OBS Studio..."
apt-get install -y obs-studio 2>/dev/null \
    || { apt-get update -qq; apt-get install -y obs-studio 2>/dev/null || warn "OBS Studio unavailable for ${UBUNTU_CODENAME} — download from https://obsproject.com"; }

ok "Multimedia codecs, KDE extras, and fonts installed"

info "Removing KDE packages that interfere with third-party browsers..."
apt-get remove --purge -y plasma-browser-integration 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
# Prevent apt from silently reinstalling it as a metapackage dependency
cat > /etc/apt/preferences.d/99-block-plasma-browser-integration << 'APTPIN_EOF'
Package: plasma-browser-integration
Pin: release *
Pin-Priority: -1
APTPIN_EOF
# Remove native messaging host manifests so browsers can't re-activate the integration
for _nms in \
    /etc/chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json \
    /usr/lib/chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json \
    /etc/opt/chrome/native-messaging-hosts/org.kde.plasma.browser_integration.json \
    /usr/lib/mozilla/native-messaging-hosts/org.kde.plasma.browser_integration.json; do
    [[ -f "$_nms" ]] && rm -f "$_nms" && info "  Removed native messaging manifest: $_nms"
done
ok "plasma-browser-integration removed + apt-pinned to -1 + native messaging manifests cleared"

# ── snapd: purge + apt-pin ────────────────────────────────────────────────────
# snapd runs a persistent background daemon, mounts each snap as a read-only
# loop device (adds to boot time), and performs automatic background refreshes
# (unexpected HDD I/O + network at any time). On a workstation managing packages
# via apt + Flatpak, snapd is pure overhead. Purge it and pin to -1 so apt
# never reinstalls it as a dependency of something else.
if dpkg -l snapd &>/dev/null 2>&1; then
    # Remove all installed snaps before purging the daemon
    if command -v snap &>/dev/null; then
        snap list 2>/dev/null | awk 'NR>1{print $1}' \
            | xargs -r -I{} snap remove --purge {} 2>/dev/null || true
    fi
    apt-get remove -y --purge snapd gnome-software-plugin-snap 2>/dev/null || true
    rm -rf /snap /var/snap /var/lib/snapd /root/snap "${USER_HOME}/snap" 2>/dev/null || true
    cat > /etc/apt/preferences.d/99-nosnap << 'NOSNAP_EOF'
# kubuntu-setup: block snapd reinstall by any package dependency
Package: snapd
Pin: release a=*
Pin-Priority: -1
NOSNAP_EOF
    ok "snapd purged + apt-pinned to -1  (daemon, loop mounts, auto-refresh eliminated)"
else
    info "snapd not installed — skipped"
fi

# ── Theme + wallpaper cleanup ─────────────────────────────────────────────────
# Keep: Breeze / Breeze Dark only.  Remove Oxygen, extra wallpaper packs,
# GNOME theme data, and anything not needed for the configured appearance.
info "Removing unneeded themes, wallpaper packs, and Oxygen leftovers..."
# NOTE: oxygen-sounds is a hard Depends of plasma-desktop (Kubuntu 25.10).
# Removing it would cascade-remove plasma-desktop and kill the panel/taskbar.
# Leave it installed — it is a tiny package (~1 MB) and the tradeoff is not worth it.
apt-get remove --purge -y \
    plasma-theme-oxygen \
    kwin-decoration-oxygen \
    kde-style-oxygen-qt6 \
    liboxygenstyle6-6 \
    liboxygenstyleconfig6-6 \
    kubuntu-wallpapers \
    plasma-workspace-wallpapers \
    plasma-wallpapers-addons \
    2>/dev/null || true
# NOTE: gnome-themes-extra-data is intentionally kept — it is a hard Depends of
# qt6-gtk-platformtheme which provides GTK theme integration for KDE/Qt apps.
# NOTE: No apt autoremove here — the apt-mark manual at the top of the script
# prevents the cascade that would otherwise remove sddm, bluez, dolphin, etc.
ok "Oxygen theme, extra wallpaper packs removed"

# Safety guard: install kubuntu-desktop core (Depends only, no Recommends) to
# ensure plasma-desktop and all panel/taskbar plasmoids are present.
# --no-install-recommends skips the full app stack (LibreOffice, games, etc.);
# the Depends list alone covers: plasma-desktop, plasma-workspace, plasma-nm,
# plasma-pa, powerdevil, kscreen, systemsettings, sddm, kscreen, milou, etc.
# The removal block below strips the unwanted Depends (kgamma, kmenuedit, etc.)
# immediately after, so the net result is a lean Kubuntu-based desktop.
if ! dpkg -s plasma-desktop >/dev/null 2>&1; then
    info "plasma-desktop missing — installing kubuntu-desktop core (no recommends)..."
    apt-get install -y --no-install-recommends kubuntu-desktop 2>/dev/null \
        && ok "kubuntu-desktop core installed (panel/taskbar restored)" \
        || err "kubuntu-desktop install FAILED — panel will not work until fixed manually"
else
    # Even when plasma-desktop is present, top up with kubuntu-desktop --no-install-recommends
    # to ensure all core Kubuntu Depends (kscreen, powerdevil, sddm, etc.) are present.
    apt-get install -y --no-install-recommends kubuntu-desktop 2>/dev/null \
        && ok "kubuntu-desktop core Depends verified/installed" \
        || warn "kubuntu-desktop top-up failed — some Kubuntu components may be missing"
fi

# ── KDE GUI bloat removal ─────────────────────────────────────────────────────
# Remove KDE system-management GUIs that duplicate CLI tools already in this
# setup, plus branding/config tools and niche hardware daemons:
#   plasma-disks       → use smartctl / nvme-cli (already installed)
#   plasma-firewall    → UFW managed directly by this script
#   plasma-thunderbolt → Thunderbolt GUI (no Thunderbolt use case here)
#   plasma-vault       → encrypted-vault widget (not used)
#   grub-theme-breeze  → GRUB visual theme (plain GRUB is fine)
#   kinfocenter        → System Info GUI (use neofetch / lshw from CLI)
#   kmenuedit          → application menu editor (not needed for power users)
#   kgamma             → gamma calibration GUI
#   kwrited            → wall/write daemon (terminal broadcast messages)
#   kde-config-sddm    → SDDM GUI config (configured via /etc/sddm.conf.d/)
#   kde-config-plymouth→ Plymouth GUI config (configured via /etc/plymouth/)
#   kde-config-gtk-style-preview → GTK style preview widget
#   kio-audiocd        → Audio CD KIO slave
#   ksystemlog         → GUI log viewer (use journalctl)
#   plasma-calendar-addons → calendar plasma applets
#   kubuntu-settings-desktop → Kubuntu branding defaults metapackage
info "Removing KDE GUI bloat (duplicated by CLI tools or unused)..."
apt-get remove -y \
    plasma-disks \
    plasma-firewall \
    plasma-thunderbolt \
    plasma-vault \
    grub-theme-breeze \
    kinfocenter \
    kmenuedit \
    kgamma \
    kwrited \
    kde-config-sddm \
    kde-config-plymouth \
    kde-config-gtk-style-preview \
    kio-audiocd \
    ksystemlog \
    plasma-calendar-addons \
    kubuntu-settings-desktop \
    2>/dev/null || true
ok "KDE GUI bloat removed"

# ── SDDM login screen: Breeze theme, solid colour background, no image ────────
# Switch from the kubuntu SDDM theme to the upstream breeze one, then override
# the background with a solid dark colour so no wallpaper image is ever shown.
info "Configuring SDDM login screen (Breeze theme, no background image)..."
# Ensure sddm and its Breeze theme are present (may have been removed with kubuntu-desktop)
apt-get install -y sddm sddm-theme-breeze 2>/dev/null || true
mkdir -p /etc/sddm.conf.d
# Main theme selection
cat > /etc/sddm.conf.d/00-theme.conf << 'SDDM_THEME_EOF'
[Theme]
Current=breeze
SDDM_THEME_EOF
# Background override: solid dark colour, no image file
# Writes a theme.conf.user next to the theme so the package can be updated
# without clobbering the customisation.
_SDDM_THEME_DIR="/usr/share/sddm/themes/breeze"
if [[ -d "$_SDDM_THEME_DIR" ]]; then
    cat > "${_SDDM_THEME_DIR}/theme.conf.user" << 'SDDM_BG_EOF'
[General]
type=color
color=#000000
background=
SDDM_BG_EOF
    ok "SDDM: Breeze theme selected, background set to solid dark colour"
else
    warn "SDDM breeze theme dir not found — manual SDDM config may be needed"
fi
# Remove the kubuntu_settings.conf that hardcodes a wallpaper path
rm -f /etc/sddm.conf.d/kubuntu_settings.conf
ok "SDDM configured (Breeze · no background image)"

# ── Plymouth boot splash: disable (blank screen during boot) ──────────────────
# Remove the kubuntu/ubuntu branded themes and set plymouth to the minimal
# text theme, then update the initramfs so the change takes effect on next boot.
info "Disabling Plymouth boot splash (removing branded themes)..."
apt-get remove --purge -y \
    plymouth-theme-kubuntu-logo \
    plymouth-theme-kubuntu-text \
    plymouth-theme-ubuntu-text \
    2>/dev/null || true
# Set the default plymouth theme via /etc/plymouth/plymouthd.conf.
# plymouth-set-default-theme is not present on all Ubuntu installs;
# writing the config file directly is the reliable cross-version method.
_PLYMOUTH_THEME="text"
if [[ ! -f "/usr/share/plymouth/themes/${_PLYMOUTH_THEME}/${_PLYMOUTH_THEME}.plymouth" ]]; then
    # 'text' not available — fall back to 'spinner' (always present)
    _PLYMOUTH_THEME="spinner"
fi
mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << PLYMOUTH_EOF
[Daemon]
Theme=${_PLYMOUTH_THEME}
ShowDelay=0
PLYMOUTH_EOF
# Also set via update-alternatives if registered (non-fatal)
_THEME_FILE="/usr/share/plymouth/themes/${_PLYMOUTH_THEME}/${_PLYMOUTH_THEME}.plymouth"
update-alternatives --set default.plymouth "$_THEME_FILE" 2>/dev/null || true
# Rebuild initramfs so the change is embedded for next boot
update-initramfs -u 2>/dev/null \
    && ok "Plymouth: theme set to '${_PLYMOUTH_THEME}', initramfs rebuilt" \
    || warn "update-initramfs failed — plymouth change will apply after next kernel update"
ok "Plymouth boot splash disabled (${_PLYMOUTH_THEME} theme)"
# ── GRUB: performance kernel params ──────────────────────────────────────────
# Source: github.com/BeanGreen247/ArchLinux-KDE-Plasma-setup-script/tweaks.md
# Skipped params (incompatible with this setup):
#   ipv6.disable=1        — breaks Docker overlay networks, Tailscale, ZeroTier
#   intel_pstate=disable  — breaks the schedutil governor installed above
#   resume=UUID=...       — host-specific hibernation UUID, not portable
if [[ -f /etc/default/grub ]]; then
    # Remove 'splash' and 'quiet' — replaced by explicit loglevel=0 below
    sed -i 's/\bsplash\b//g; s/\bquiet\b//g' /etc/default/grub
    # Boot timeout: 25 s (enough to choose an entry on multi-boot machines)
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=25/' /etc/default/grub

    # Detect CPU vendor to apply vendor-specific kernel params.
    # ibt=off disables Intel IBT/CET — not a concept on AMD (no-op, but confusing).
    # processor.max_cstate works on BOTH Intel and AMD — value differs by vendor:
    #   Intel → max_cstate=1  (block all deep C-states; PAT latency spikes)
    #   AMD Ryzen 5000H (Cezanne) → max_cstate=5  (block C6+ only; allows C1-C5)
    #     Cezanne has a documented CC6 wakeup bug where the core fails to come back
    #     from CC6 sleep, causing a hard freeze.  max_cstate=5 is the software fix;
    #     BIOS update (AGESA 1.2.0.7+) is the permanent fix, but most laptops never
    #     get it.  Linux Mint ships this param by default for affected hardware.
    _CPU_VENDOR=$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $3}')
    # Each param is appended to the end of the value (so it wins over 'quiet').
    # grep -qF skips params already present — safe to re-run.
    #
    # nowatchdog              disables NMI + softlockup watchdog kernel threads
    # nosoftlockup            explicit softlockup disable (belt-and-suspenders)
    # transparent_hugepage=madvise  khugepaged off; apps opt-in individually
    # rootflags=noatime       no atime writes on root fs — major HDD win
    # consoleblank=0          no TTY screen-blank timeout
    # split_lock_detect=off   no perf penalty for cross-cache-line locked accesses
    # split_lock_mitigate=0   companion to the above
    # mitigations=off         disables Spectre/Meltdown/MDS mitigations for speed
    #                         ⚠ SECURITY TRADEOFF — matches user's own Arch script
    # nomce                   disables Machine Check Exception handler overhead
    # noirqdebug              disables IRQ debug overhead
    # timer_migration=0       disables cross-CPU timer migration — reduces latency
    # audit=0                 disables Linux audit framework (significant syscall overhead)
    # acpi_enforce_resources=lax  allows sensor drivers (hwmon, lm-sensors) to claim
    #                         ACPI resources marked as reserved
    # sysrq_always_enabled=1  Magic SysRq works regardless of kernel.sysrq sysctl
    # ibt=off           [Intel only] disables Intel IBT (CET) — no-op on AMD/non-IBT CPUs
    # thermal.off=1           disables kernel thermal throttling framework entirely
    #                         ⚠ NO safety net: CPU will not throttle under heat — desktop only
    # loglevel=0              fully silent kernel — no messages to console
    # udev.log_level=0        silent udev log
    # rd.udev.log_level=0     silent initrd udev log
    # processor.max_cstate=1  [Intel only] prevents deep C-states (latency spikes when CPU wakes)
    #                         ⚠ POWER TRADEOFF — idle power ~5-15 W higher; desktop only
    #                         AMD manages C-states via amd_pstate/cpuidle — this param is ignored
    _GRUB_DEFAULT_PARAMS=(
        "nowatchdog"
        "nosoftlockup"
        "transparent_hugepage=always"
        "rootflags=noatime"
        "consoleblank=0"
        "split_lock_detect=off"
        "split_lock_mitigate=0"
        "mitigations=off"
        "nomce"
        "noirqdebug"
        "timer_migration=0"
        "audit=0"
        "acpi_enforce_resources=lax"
        "sysrq_always_enabled=1"
        "thermal.off=1"
        "loglevel=0"
        "udev.log_level=0"
        "rd.udev.log_level=0"
        # NVMe drives can enter deep power states (PS3/PS4) and fail to resume on
        # Ryzen mobile platforms — 0 µs latency budget forces the drive to stay in
        # PS0/PS1 (active), eliminating NVMe-triggered freezes at the cost of ~0.5W.
        "nvme_core.default_ps_max_latency_us=0"
        # Spread timer tick expiry across CPUs by jittering each CPU's first tick.
        # Reduces lock contention from synchronised timer firings on many-core systems.
        "skew_tick=1"
        # Seed kernel RNG from hardware RDRAND (CPU built-in). Speeds up early-boot
        # crypto and eliminates /dev/urandom blocking on headless installs.
        "random.trust_cpu=on"
        # PCIe ASPM policy — host-side link power management. "performance" disables
        # L1 link-state transitions on all PCIe devices. Complementary to
        # nvme_core.default_ps_max_latency_us=0: that prevents NVMe-initiated power
        # state changes; this prevents host-initiated PCIe link re-training which can
        # cause multi-millisecond latency spikes or outright hangs on Ryzen + NVMe.
        "pcie_aspm.policy=performance"
    )
    # Intel-only params — skipped on AMD/other CPUs
    if [[ "$_CPU_VENDOR" == "GenuineIntel" ]]; then
        _GRUB_DEFAULT_PARAMS+=(
            "ibt=off"
            "processor.max_cstate=1"
        )
        info "GRUB: adding Intel-only params: ibt=off processor.max_cstate=1"
    fi
    # AMD-specific params — fixes documented random-freeze bugs on Ryzen 5000 mobile
    if [[ "$_CPU_VENDOR" == "AuthenticAMD" ]]; then
        _GRUB_DEFAULT_PARAMS+=(
            # Ryzen 5000H (Cezanne) CC6 wakeup freeze: the core fails to exit CC6
            # deep sleep, hard-locking the system. max_cstate=5 blocks C6+ while
            # keeping C1-C5, matching the Linux Mint default for this CPU family.
            "processor.max_cstate=5"
            # IOMMU passthrough: on hybrid AMD iGPU + NVIDIA dGPU laptops, ACPI
            # power events between the two GPUs can hang without pt mode enabled.
            "amd_iommu=on"
            "iommu=pt"
            # AMD P-State driver with EPP (Energy Performance Preference) hints.
            # 'active' mode lets the CPU firmware pick the best P-state for each
            # workload — better than acpi-cpufreq for burst performance + idle power.
            # Requires CPPC support (all Zen 3+ mobile CPUs). Kernel 6.3+ default
            # on supported hardware, but setting it explicitly ensures it's not
            # overridden by a distro's cmdline default.
            "amd_pstate=active"
        )
        info "GRUB: adding AMD params: processor.max_cstate=5 amd_iommu=on iommu=pt amd_pstate=active"
    fi
    for _param in "${_GRUB_DEFAULT_PARAMS[@]}"; do
        grep -qF "$_param" /etc/default/grub 2>/dev/null || {
            # Handle both double-quoted and single-quoted values (distros differ)
            sed -i "s|\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"|\1 ${_param}\"|" /etc/default/grub
            sed -i "s|\(GRUB_CMDLINE_LINUX_DEFAULT='[^']*\)'|\1 ${_param}'|" /etc/default/grub
        }
    done

    # ── GRUB_CMDLINE_LINUX — applied to ALL entries (including recovery) ──────
    # preempt=full       full kernel preemption → lowest desktop latency
    # nohz_full=all      tickless mode on all CPUs — eliminates timer interrupts
    #                    on busy CPUs (requires rcu_nocbs=all to function correctly)
    # rcu_nocbs=all      moves RCU callbacks off all CPUs — required partner for nohz_full
    # threadirqs         all IRQ handlers run as kernel threads → better latency
    # ignore_rlimit_data relaxes data-segment rlimit enforcement per process
    _GRUB_LINUX_PARAMS="preempt=full nohz_full=all rcu_nocbs=all threadirqs ignore_rlimit_data"
    if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub 2>/dev/null; then
        for _param in "preempt=full" "nohz_full=all" "rcu_nocbs=all" "threadirqs" "ignore_rlimit_data"; do
            grep -qF "$_param" /etc/default/grub 2>/dev/null || {
                sed -i "s|\(GRUB_CMDLINE_LINUX=\"[^\"]*\)\"|\1 ${_param}\"|" /etc/default/grub
                sed -i "s|\(GRUB_CMDLINE_LINUX='[^']*\)'|\1 ${_param}'|" /etc/default/grub
            }
        done
    else
        echo "GRUB_CMDLINE_LINUX=\"${_GRUB_LINUX_PARAMS}\"" >> /etc/default/grub
    fi

    update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    info "  GRUB_CMDLINE_LINUX_DEFAULT: $(grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub)"
    info "  GRUB_CMDLINE_LINUX:         $(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub)"
fi
ok "GRUB: mitigations=off · thermal.off · THP=always · preempt=full · nohz_full+rcu_nocbs · threadirqs · nvme_core.ps_max=0 · pcie_aspm=perf · skew_tick=1 · AMD: max_cstate=5 + amd_iommu=on iommu=pt + amd_pstate=active · Intel: ibt=off max_cstate=1"

# ── Kubuntu logo: install start-here-kubuntu icon into breeze theme ───────────
# kubuntu-settings-desktop ships this icon but we remove that package as bloat.
# Extract just the icon by downloading the deb and copying the SVG files,
# so the kicker launcher button shows the Kubuntu circle logo.
_KSD_DEB=$(mktemp -d)
if apt-get download kubuntu-settings-desktop -t "${UBUNTU_CODENAME}" 2>/dev/null \
        --target-release "${UBUNTU_CODENAME}" -o Dir::Cache::Archives="$_KSD_DEB" 2>/dev/null \
    || apt-get download kubuntu-settings-desktop 2>/dev/null; then
    _KSD_PKG=$(find "$_KSD_DEB" /. -maxdepth 2 -name "kubuntu-settings-desktop*.deb" 2>/dev/null | head -1)
    [[ -z "$_KSD_PKG" ]] && _KSD_PKG=$(ls kubuntu-settings-desktop*.deb 2>/dev/null | head -1)
    if [[ -f "$_KSD_PKG" ]]; then
        _KSD_TMP=$(mktemp -d)
        dpkg-deb -x "$_KSD_PKG" "$_KSD_TMP" 2>/dev/null
        for _size in 16 22 24 32 48 64 96; do
            install -Dm644 "$_KSD_TMP/usr/share/icons/breeze/places/16/start-here-kubuntu.svg" \
                "/usr/share/icons/breeze/places/${_size}/start-here-kubuntu.svg" 2>/dev/null || true
            install -Dm644 "$_KSD_TMP/usr/share/icons/breeze-dark/places/16/start-here-kubuntu.svg" \
                "/usr/share/icons/breeze-dark/places/${_size}/start-here-kubuntu.svg" 2>/dev/null || true
        done
        gtk-update-icon-cache -f /usr/share/icons/breeze      2>/dev/null || true
        gtk-update-icon-cache -f /usr/share/icons/breeze-dark 2>/dev/null || true
        ok "Kubuntu logo icon installed into Breeze theme (start-here-kubuntu)"
        rm -rf "$_KSD_TMP"
    else
        warn "kubuntu-settings-desktop deb not found — Kubuntu logo icon not installed"
    fi
    rm -rf "$_KSD_DEB"
else
    warn "kubuntu-settings-desktop download failed — Kubuntu logo icon not installed"
fi

# ── Cursor: set Breeze Dark system-wide (SDDM + root + Xresources) ────────────
# kwriteconfig6 sets it for the user session (in post-login block).
# The lines below ensure the cursor is consistent at the login screen and for
# root applications.
# Ensure the Breeze Dark cursor theme is installed
apt-get install -y breeze-cursor-theme 2>/dev/null || true
if [[ -f /usr/share/icons/Breeze_Dark/index.theme ]]; then
    mkdir -p /usr/share/icons/default
    cat > /usr/share/icons/default/index.theme << 'CURSOR_EOF'
[Icon Theme]
Inherits=Breeze_Dark
CURSOR_EOF
    # Also set via Xresources for X11 apps launched as root
    mkdir -p /etc/X11/Xresources
    echo 'Xcursor.theme: Breeze_Dark' > /etc/X11/Xresources/xcursor
    ok "Cursor theme: Breeze Dark set system-wide (login screen + root)"
else
    warn "Breeze_Dark cursor theme not found — install breeze-cursor-theme"
fi
fi  # ─── end: 3/15 ───

hdr "4/15  Development tools"
if (( _DOTFILES_ONLY )); then
    info "4/15 skipped  (profile: ${INSTALL_PROFILE})"
else

info "Adding development tool repositories..."
install -m 0755 -d /etc/apt/keyrings

if [[ ! -f /etc/apt/keyrings/microsoft.gpg ]]; then
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --batch --yes --dearmor > /etc/apt/keyrings/microsoft.gpg
    chmod a+r /etc/apt/keyrings/microsoft.gpg
fi

# Always maintain a valid azure-cli.list (cleanup may have removed a stale entry)
_AZ_SUITE="$(lsb_release -cs)"
# Microsoft only publishes Azure CLI for LTS releases. Try the exact current codename
# first; if it has no Release yet fall back directly to noble (last confirmed LTS).
if ! curl -fsLm 10 -o /dev/null \
    "https://packages.microsoft.com/repos/azure-cli/dists/${_AZ_SUITE}/Release" 2>/dev/null; then
    warn "Azure CLI repo has no '${_AZ_SUITE}' release yet — falling back to noble"
    _AZ_SUITE="noble"
fi
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/azure-cli ${_AZ_SUITE} main" \
    | tee /etc/apt/sources.list.d/azure-cli.list > /dev/null
info "  Azure CLI repo set (suite: ${_AZ_SUITE})"

# Repo check is separate from binary check: OS upgrade may have disabled the .list
# file even though docker/kubectl are still installed.
if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    rm -f /etc/apt/sources.list.d/docker.list.disabled 2>/dev/null || true
    [[ ! -f /etc/apt/keyrings/docker.gpg ]] && \
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=${HOST_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    info "  Docker CE repo added"
fi

if [[ ! -f /etc/apt/sources.list.d/kubernetes.list ]]; then
    rm -f /etc/apt/sources.list.d/kubernetes.list.disabled 2>/dev/null || true
    KUBE_VER="v1.32"
    [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]] && \
        curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBE_VER}/deb/Release.key" \
        | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/${KUBE_VER}/deb/ /" \
        | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    info "  kubectl repo added"
fi

apt-get update -qq 2>&1 | grep -E '^(E:|W:)' || true

# ── Pulsar editor ─────────────────────────────────────────────────────────────
if ! command -v pulsar &>/dev/null; then
    _PULSAR_TAG="$(
        curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            -H "User-Agent: Mozilla/5.0" \
            https://api.github.com/repos/pulsar-edit/pulsar/releases/latest \
        | python3 -c 'import sys, json; print(json.load(sys.stdin)["tag_name"])'
    )"
    _PULSAR_VER="${_PULSAR_TAG#v}"
    _PULSAR_URL="https://github.com/pulsar-edit/pulsar/releases/download/${_PULSAR_TAG}/Linux.pulsar_${_PULSAR_VER}_${HOST_ARCH}.deb"
    _PULSAR_TMP="$(mktemp "/tmp/pulsar_${_PULSAR_VER}_${HOST_ARCH}.XXXXXX.deb")"
    trap 'rm -f "$_PULSAR_TMP"' EXIT
    curl -fL "$_PULSAR_URL" -o "$_PULSAR_TMP"
    dpkg -i "$_PULSAR_TMP" || apt-get -f install -y
    rm -f "$_PULSAR_TMP"
    ok "Pulsar ${_PULSAR_VER} installed"
else
    ok "Pulsar already installed"
fi

if command -v pulsar &>/dev/null; then
    # git-plus: command-palette git without any GitHub login prompt
    sudo -u "$USER_NAME" pulsar -p install git-plus \
        && ok "  git-plus package installed" \
        || warn "  git-plus install failed — run: pulsar -p install git-plus"
    # Disable bundled packages that are unused, dev-only, or hurt performance
    sudo -u "$USER_NAME" pulsar -p disable \
        github \
        open-on-github \
        metrics \
        exception-reporting \
        dev-live-reload \
        deprecation-cop \
        autocomplete-atom-api \
        package-generator \
        timecop \
        styleguide \
        spell-check \
        welcome \
        about \
        background-tips \
        keybinding-resolver \
        && ok "  performance/junk packages disabled" \
        || warn "  some packages could not be disabled — check Settings > Packages"
fi

# ── Pulsar performance config + launch wrapper ────────────────────────────────
_PULSAR_CFG="${USER_HOME}/.pulsar/config.cson"
mkdir -p "${USER_HOME}/.pulsar"

# Write config.cson — preserves disabledPackages and adds performance settings.
# Pulsar rewrites this file on launch so we only write it if Pulsar isn't running.
if ! pgrep -u "$USER_NAME" -x pulsar &>/dev/null; then
    cat > "$_PULSAR_CFG" << 'PULSAR_CFG_EOF'
"*":
  core:
    disabledPackages: [
      "github"
      "open-on-github"
      "dev-live-reload"
      "deprecation-cop"
      "autocomplete-atom-api"
      "package-generator"
      "timecop"
      "styleguide"
      "spell-check"
      "welcome"
      "about"
      "background-tips"
      "keybinding-resolver"
    ]
    excludeVcsIgnoredPaths: true
    followSymlinks: false
    ignoredNames: [
      ".git"
      "node_modules"
      "dist"
      "build"
      ".next"
      "venv"
      ".venv"
      "__pycache__"
      "*.pyc"
      "*.o"
      "*.a"
      "target"
    ]
  editor:
    softWrap: false
    showIndentGuide: false
    scrollPastEnd: false
  "autocomplete-plus":
    minimumWordLength: 3
    autoActivationDelay: 300
  "fuzzy-finder":
    ignoredNames: [
      "node_modules/**"
      "dist/**"
      "build/**"
      ".git/**"
      "__pycache__/**"
      "venv/**"
      ".venv/**"
      "target/**"
    ]
  autosave:
    enabled: true
PULSAR_CFG_EOF
    chown "$USER_NAME:$USER_NAME" "$_PULSAR_CFG"
    ok "  Pulsar config.cson written (performance settings)"
else
    warn "  Pulsar is running — skipping config.cson write (run setup again after closing Pulsar)"
fi

# ── Pulsar init.js — auto-reload editors when files change on disk ─────────────
# Pulsar already silently reloads clean (unsaved) buffers when the file changes
# on disk.  This init.js snippet also handles the conflict case: if you have
# unsaved edits AND the file is modified externally, it reverts to disk instead
# of showing the "file-changed" warning banner.
_PULSAR_INIT="${USER_HOME}/.pulsar/init.js"
if ! pgrep -u "$USER_NAME" -x pulsar &>/dev/null; then
    cat > "$_PULSAR_INIT" << 'PULSAR_INIT_EOF'
// Auto-reload any open editor when the underlying file changes on disk.
// Handles both the clean case (Pulsar does this built-in) and the conflict
// case (unsaved edits + external change) by reverting to the disk version.
atom.workspace.observeTextEditors(function (editor) {
  editor.getBuffer().onDidConflict(function () {
    editor.getBuffer().revert();
  });
});
PULSAR_INIT_EOF
    chown "$USER_NAME:$USER_NAME" "$_PULSAR_INIT"
    ok "  Pulsar init.js written (auto-reload on external file change)"
else
    warn "  Pulsar is running — skipping init.js write (run setup again after closing Pulsar)"
fi

# Wrapper script: injects Electron/V8 performance flags without touching the
# system /usr/bin/pulsar (which gets overwritten on package upgrades).
_PULSAR_WRAPPER="${USER_HOME}/.local/bin/pulsar"
mkdir -p "${USER_HOME}/.local/bin"
cat > "$_PULSAR_WRAPPER" << 'PULSAR_WRAP_EOF'
#!/usr/bin/env bash
# Wrapper to launch Pulsar with performance-tuned Electron/V8 flags.
# Calls the real /usr/bin/pulsar (the system script) so updates don't break this.
export UV_THREADPOOL_SIZE="$(nproc)"
export NODE_ENV=production
exec /usr/bin/pulsar \
    --js-flags="--max-old-space-size=8192 --turbo-fast-api-calls" \
    --disable-renderer-backgrounding \
    --disable-backgrounding-occluded-windows \
    --enable-features=UseOzonePlatform,WaylandWindowDecorations,VaapiVideoDecoder,CanvasOopRasterization \
    --disable-features=TranslateUI,AutofillServerCommunication \
    --ozone-platform=wayland \
    --ignore-gpu-blocklist \
    --enable-gpu-rasterization \
    --enable-zero-copy \
    --enable-native-gpu-memory-buffers \
    --num-raster-threads="$(nproc)" \
    "$@"
PULSAR_WRAP_EOF
chmod +x "$_PULSAR_WRAPPER"
chown "$USER_NAME:$USER_NAME" "$_PULSAR_WRAPPER"
ok "  Pulsar launch wrapper written (${_PULSAR_WRAPPER})"

# User-level .desktop file: overrides /usr/share/applications/pulsar.desktop so
# the KDE app launcher also goes through our wrapper. Survives Pulsar updates.
_PULSAR_DESKTOP="${USER_HOME}/.local/share/applications/pulsar.desktop"
mkdir -p "${USER_HOME}/.local/share/applications"
cat > "$_PULSAR_DESKTOP" << PULSAR_DESKTOP_EOF
[Desktop Entry]
Name=Pulsar
Exec=${USER_HOME}/.local/bin/pulsar %U
Terminal=false
Type=Application
Icon=pulsar
StartupWMClass=Pulsar
Comment=A Community-led Hyper-Hackable Text Editor
Categories=Development;
PULSAR_DESKTOP_EOF
chown "$USER_NAME:$USER_NAME" "$_PULSAR_DESKTOP"
sudo -u "$USER_NAME" update-desktop-database "${USER_HOME}/.local/share/applications/" 2>/dev/null || true
ok "  Pulsar .desktop override written (app launcher now uses wrapper)"

if ! command -v docker &>/dev/null; then
    apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        || { warn "Docker CE from docker.com failed; falling back to docker.io"
             apt-get install -y docker.io docker-compose; }
    usermod -aG docker "$USER_NAME"
    systemctl enable --now docker
    ok "Docker installed (${USER_NAME} added to 'docker' group)"
else
    ok "Docker already installed"
fi

# ── Docker daemon: log rotation + live-restore ────────────────────────────────
# By default Docker logs are unbounded — one chatty container can fill an entire
# HDD partition. Capping at 10 MB × 5 files = max 50 MB per container.
# live-restore=true: containers keep running if dockerd is restarted (upgrades).
# overlay2: already the default on Ubuntu 22.04+, but explicit is idempotent.
mkdir -p /etc/docker
if [[ ! -f /etc/docker/daemon.json ]]; then
    cat > /etc/docker/daemon.json << 'DOCKERD_EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
DOCKERD_EOF
    ok "Docker daemon.json: json-file logs (10 MB × 5), overlay2, live-restore"
else
    info "Docker daemon.json already exists — not overwritten"
fi

apt-get install -y \
    ansible \
    ansible-lint \
    python3-proxmoxer \
    python3-requests \
    python3-netaddr \
    python3-dnspython \
    yamllint
ok "Ansible + YAML tooling installed"

if ! command -v az &>/dev/null; then
    apt-get install -y azure-cli \
        || warn "Azure CLI install failed (non-fatal)"
    ok "Azure CLI installed"
else
    ok "Azure CLI already installed"
fi

info "Installing extra DevOps + sysadmin CLI tools..."
apt-get install -y \
    awscli \
    sshuttle \
    autossh \
    fping \
    apache2-utils \
    wrk \
    siege \
    || true
apt-get install -y kubectx 2>/dev/null || true
ok "Extra DevOps tools installed  (awscli, sshuttle, autossh, fping, kubectx, wrk, siege)"

if ! command -v kubectl &>/dev/null; then
    apt-get install -y kubectl
    ok "kubectl installed"
else
    ok "kubectl already installed"
fi


info "Installing Python packages for infrastructure + Ansible work..."
sudo -u "$USER_NAME" pip3 install --user --break-system-packages \
    proxmoxer requests paramiko boto3 pyyaml jinja2 ansible-runner \
    netmiko napalm pynetbox \
    molecule 'molecule[docker]' ansible-navigator \
    passlib cryptography mitogen hvac \
    nornir nornir-utils nornir-netmiko \
    2>/dev/null \
    || warn "Some Python packages failed (non-fatal)"
ok "Python infra packages done"

info "Installing system observability + performance tools..."
apt-get install -y iotop-c 2>/dev/null || apt-get install -y iotop 2>/dev/null || true
apt-get install -y \
    iftop \
    nethogs \
    sysstat \
    stress-ng \
    powertop \
    linux-tools-generic \
    power-profiles-daemon \
    cpufrequtils \
    irqbalance \
    zram-tools \
    preload \
    earlyoom \
    || true

info "Installing storage + disk management tools..."
apt-get install -y \
    smartmontools \
    nvme-cli \
    hdparm \
    lvm2 \
    cryptsetup \
    gparted \
    xfsprogs \
    btrfs-progs \
    || true
ok "Observability + storage tools installed"

info "Installing security hardening + auditing tools..."
apt-get install -y \
    lynis \
    fail2ban \
    ufw \
    clamav \
    clamav-freshclam \
    age \
    || true
systemctl enable fail2ban 2>/dev/null || true
# ClamAV: on-demand scanning only — mask daemon + socket to keep ~1 GB RAM free
systemctl stop clamav-daemon 2>/dev/null || true
systemctl disable clamav-daemon 2>/dev/null || true
systemctl mask clamav-daemon 2>/dev/null || true
systemctl mask clamav-daemon.socket 2>/dev/null || true
systemctl enable clamav-freshclam 2>/dev/null || true
systemctl start clamav-freshclam 2>/dev/null || true

# ── UFW — default-deny firewall ───────────────────────────────────────────────
info "Configuring UFW firewall (default-deny inbound)..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH — allow from everywhere (Tailscale + LAN + public, restricted by fail2ban)
ufw allow 22/tcp comment 'SSH'

# mDNS / Avahi — LAN service discovery
ufw allow in on any to 224.0.0.251 port 5353 proto udp comment 'mDNS'

# KDE Connect (LAN only — 192.168.0.0/16 covers most home/office subnets)
ufw allow from 192.168.0.0/16 to any port 1714:1764 proto tcp comment 'KDE Connect TCP'
ufw allow from 192.168.0.0/16 to any port 1714:1764 proto udp comment 'KDE Connect UDP'

# Tailscale tunnel itself
ufw allow in on tailscale0 comment 'Tailscale VPN'

# ZeroTier tunnel itself (ztXXXXXXXX interface — wildcard via ufw route)
ufw allow in on zt+ comment 'ZeroTier VPN'

ufw --force enable
ok "UFW enabled  (default-deny; SSH/22 open; KDE Connect on LAN; Tailscale + ZeroTier interfaces allowed)"

# ── fail2ban — SSH + xrdp jails ──────────────────────────────────────────────
info "Writing fail2ban jail configuration..."
cat > /etc/fail2ban/jail.local << 'F2B_EOF'
# kubuntu-setup managed — fail2ban jails
# Regenerated by setup-kubuntu.sh; local overrides go in jail.d/*.local

[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

# ── SSH ───────────────────────────────────────────────────────────────────────
[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = %(sshd_log)s
maxretry = 4
bantime  = 2h

# ── xrdp — brute-force on RDP port ───────────────────────────────────────────
[xrdp]
enabled  = true
port     = 3389
filter   = xrdp
logpath  = /var/log/xrdp.log
maxretry = 4
bantime  = 2h

F2B_EOF

# xrdp filter — fail2ban ships no built-in xrdp filter
cat > /etc/fail2ban/filter.d/xrdp.conf << 'XRDPF_EOF'
[Definition]
failregex = .*\[xrdp\].*(?:authentication failure|authfail|Login failed).*client ip: <HOST>
            .*\[xrdp-sesman\].*(?:login failed|auth failed).*<HOST>
ignoreregex =
XRDPF_EOF

systemctl restart fail2ban 2>/dev/null || systemctl start fail2ban 2>/dev/null || true
ok "fail2ban configured  (sshd + xrdp jails active, 4 retries → 2 h ban)"
info "Security audit:  sudo lynis audit system"
info "Jail status:     sudo fail2ban-client status sshd"

info "Installing Podman + buildah + skopeo..."
apt-get install -y \
    podman \
    buildah \
    skopeo \
    || true
ok "Podman + buildah + skopeo installed  (rootless, Docker-compatible CLI)"
info "Drop-in alias:  alias docker=podman  (add to ~/.bashrc)"

# ── Tier-1: modern CLI replacements + essential sysadmin tools ────────────────
info "Installing modern CLI tooling (bat, eza, fzf, zoxide, fd, ripgrep, btop, duf, tmux, jq, sops, trivy…)"
apt-get install -y \
    bat \
    fzf \
    ripgrep \
    fd-find \
    btop \
    ncdu \
    tmux \
    jq \
    git-delta \
    || true

# sops — secrets management; not in Ubuntu apt. Install from GitHub releases.
if ! command -v sops &>/dev/null; then
    _SOPS_VER=$(curl -fsSLm 10 \
        'https://api.github.com/repos/getsops/sops/releases/latest' \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    if [[ -n "$_SOPS_VER" ]]; then
        wget -qO /tmp/sops.deb \
            "https://github.com/getsops/sops/releases/download/${_SOPS_VER}/sops_${_SOPS_VER#v}_amd64.deb" \
            && apt-get install -y /tmp/sops.deb \
            && ok  "sops ${_SOPS_VER} installed  (secrets management / Helm secrets)" \
            || warn "sops deb install failed — download from https://github.com/getsops/sops/releases"
        rm -f /tmp/sops.deb
    else
        warn "sops: GitHub release fetch failed — install manually from https://github.com/getsops/sops/releases"
    fi
fi

# eza — not in Ubuntu repos, install from GitHub
if ! command -v eza &>/dev/null; then
    _EZA_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/eza-community/eza/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _EZA_VER=${_EZA_VER:-v0.20.9}
    wget -qO /tmp/eza.tar.gz \
        "https://github.com/eza-community/eza/releases/download/${_EZA_VER}/eza_x86_64-unknown-linux-gnu.tar.gz" \
    && tar -xzf /tmp/eza.tar.gz -C /usr/local/bin eza \
    && ok "eza ${_EZA_VER} installed" \
    || warn "eza install failed — install manually from https://github.com/eza-community/eza"
    rm -f /tmp/eza.tar.gz
fi

# zoxide — not in Ubuntu repos
if ! command -v zoxide &>/dev/null; then
    _ZO_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _ZO_VER=${_ZO_VER:-v0.9.6}
    wget -qO /tmp/zoxide.tar.gz \
        "https://github.com/ajeetdsouza/zoxide/releases/download/${_ZO_VER}/zoxide-${_ZO_VER#v}-x86_64-unknown-linux-musl.tar.gz" \
    && tar -xzf /tmp/zoxide.tar.gz -C /usr/local/bin zoxide \
    && ok "zoxide ${_ZO_VER} installed" \
    || warn "zoxide install failed — install manually from https://github.com/ajeetdsouza/zoxide"
    rm -f /tmp/zoxide.tar.gz
fi

# duf — not in Ubuntu repos
if ! command -v duf &>/dev/null; then
    _DUF_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/muesli/duf/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _DUF_VER=${_DUF_VER:-v0.8.1}
    wget -qO /tmp/duf.tar.gz \
        "https://github.com/muesli/duf/releases/download/${_DUF_VER}/duf_${_DUF_VER#v}_linux_x86_64.tar.gz" \
    && tar -xzf /tmp/duf.tar.gz -C /usr/local/bin duf \
    && ok "duf ${_DUF_VER} installed" \
    || warn "duf install failed — install manually from https://github.com/muesli/duf"
    rm -f /tmp/duf.tar.gz
fi

# yq — not in Ubuntu repos
if ! command -v yq &>/dev/null; then
    _YQ_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/mikefarah/yq/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _YQ_VER=${_YQ_VER:-v4.44.3}
    wget -qO /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/${_YQ_VER}/yq_linux_amd64" \
    && chmod +x /usr/local/bin/yq \
    && ok "yq ${_YQ_VER} installed" \
    || warn "yq install failed — install manually from https://github.com/mikefarah/yq"
fi

# trivy — add official apt repo (repo check separate from binary check)
if [[ ! -f /etc/apt/sources.list.d/trivy.list ]]; then
    rm -f /etc/apt/sources.list.d/trivy.list.disabled 2>/dev/null || true
    # Must dearmor the ASCII key — writing raw ASCII to .gpg causes "unsupported filetype"
    curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
        | gpg --batch --yes --dearmor -o /etc/apt/keyrings/trivy.gpg
    chmod 644 /etc/apt/keyrings/trivy.gpg
    echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
        | tee /etc/apt/sources.list.d/trivy.list > /dev/null
    apt-get update -qq 2>&1 | grep -E '^(E:|W:)' || true
fi
if ! command -v trivy &>/dev/null; then
    apt-get install -y trivy 2>/dev/null \
        && ok "trivy installed" \
        || warn "trivy install failed — install manually from https://aquasec.com/trivy"
fi

ok "Modern CLI tooling installed"

# ── Tier-2: GitHub release tools ─────────────────────────────────────────────
info "Installing Tier-2 tools from GitHub releases (lazygit, lazydocker, k9s, stern, Bitwarden CLI)…"

# ── lazygit ───────────────────────────────────────────────────────────────────
if ! command -v lazygit &>/dev/null; then
    _LG_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _LG_VER=${_LG_VER:-v0.44.1}
    wget -qO /tmp/lazygit.tar.gz \
        "https://github.com/jesseduffield/lazygit/releases/download/${_LG_VER}/lazygit_${_LG_VER#v}_Linux_x86_64.tar.gz" \
    && tar -xzf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit \
    && ok "lazygit ${_LG_VER} installed" \
    || warn "lazygit install failed"
    rm -f /tmp/lazygit.tar.gz
fi

# ── lazydocker ────────────────────────────────────────────────────────────────
if ! command -v lazydocker &>/dev/null; then
    _LD_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _LD_VER=${_LD_VER:-v0.23.3}
    wget -qO /tmp/lazydocker.tar.gz \
        "https://github.com/jesseduffield/lazydocker/releases/download/${_LD_VER}/lazydocker_${_LD_VER#v}_Linux_x86_64.tar.gz" \
    && tar -xzf /tmp/lazydocker.tar.gz -C /usr/local/bin lazydocker \
    && ok "lazydocker ${_LD_VER} installed" \
    || warn "lazydocker install failed"
    rm -f /tmp/lazydocker.tar.gz
fi

# ── k9s ───────────────────────────────────────────────────────────────────────
if ! command -v k9s &>/dev/null; then
    _K9_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/derailed/k9s/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _K9_VER=${_K9_VER:-v0.32.7}
    wget -qO /tmp/k9s.tar.gz \
        "https://github.com/derailed/k9s/releases/download/${_K9_VER}/k9s_Linux_amd64.tar.gz" \
    && tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s \
    && ok "k9s ${_K9_VER} installed" \
    || warn "k9s install failed"
    rm -f /tmp/k9s.tar.gz
fi

# ── stern (multi-pod log tailing) ─────────────────────────────────────────────
if ! command -v stern &>/dev/null; then
    _ST_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/stern/stern/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _ST_VER=${_ST_VER:-v1.32.0}
    wget -qO /tmp/stern.tar.gz \
        "https://github.com/stern/stern/releases/download/${_ST_VER}/stern_${_ST_VER#v}_linux_amd64.tar.gz" \
    && tar -xzf /tmp/stern.tar.gz -C /usr/local/bin stern \
    && ok "stern ${_ST_VER} installed" \
    || warn "stern install failed"
    rm -f /tmp/stern.tar.gz
fi

# ── Bitwarden CLI ─────────────────────────────────────────────────────────────
if ! command -v bw &>/dev/null; then
    _BW_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/bitwarden/clients/releases" \
        | grep '"tag_name"' | grep '"cli-' | head -1 | grep -oP 'cli-v[\d.]+' | head -1)
    _BW_TAG=${_BW_VER:-cli-v2025.4.0}
    _BW_NUM=${_BW_TAG#cli-v}
    wget -qO /tmp/bw.zip \
        "https://github.com/bitwarden/clients/releases/download/${_BW_TAG}/bw-linux-${_BW_NUM}.zip" \
    && unzip -qo /tmp/bw.zip -d /usr/local/bin bw \
    && chmod +x /usr/local/bin/bw \
    && ok "Bitwarden CLI ${_BW_TAG} installed" \
    || warn "Bitwarden CLI install failed — download from https://bitwarden.com/help/cli/"
    rm -f /tmp/bw.zip
fi

ok "Tier-2 tools done (lazygit, lazydocker, k9s, stern, Bitwarden CLI)"

# ── git-delta as default diff pager ──────────────────────────────────────────
if command -v delta &>/dev/null; then
    _ugit() { sudo -u "$USER_NAME" env -i HOME="$USER_HOME" PATH="$PATH" git -C /tmp config --file "$USER_HOME/.gitconfig" "$@"; }
    _ugit core.pager               delta
    _ugit interactive.diffFilter   "delta --color-only"
    _ugit delta.navigate            true
    _ugit delta.side-by-side        true
    _ugit merge.conflictstyle        diff3
    unset -f _ugit
    ok "git-delta set as default git pager"
fi

# ── global git hooks: strip AI co-author trailers ────────────────────────────
_HOOKS_DIR="$USER_HOME/.config/git/hooks"
sudo -u "$USER_NAME" mkdir -p "$_HOOKS_DIR"
for _hook in commit-msg prepare-commit-msg; do
cat > "$_HOOKS_DIR/$_hook" << 'HOOK_EOF'
#!/bin/sh
# Strip AI assistant Co-Authored-By trailers; preserves human co-authors.
# Covered: Anthropic Claude, GitHub Copilot, Cursor, Aider, Sourcegraph Cody,
#           Devin (Cognition), Google Gemini Code Assist, Amazon Q, Codeium/Windsurf, Tabnine.
sed -i -E \
  -e '/^Co-Authored-By:.*@anthropic\.com/Id' \
  -e '/^Co-Authored-By:.*Copilot@users\.noreply\.github\.com/Id' \
  -e '/^Co-Authored-By:.*cursoragent@cursor\.com/Id' \
  -e '/^Co-Authored-By:.*git@aider\.chat/Id' \
  -e '/^Co-Authored-By:.*sourcegraph-bot/Id' \
  -e '/^Co-Authored-By:.*noreply@cognition\.ai/Id' \
  -e '/^Co-Authored-By:.*devin-ai-integration/Id' \
  -e '/^Co-Authored-By:.*gemini-code-assist/Id' \
  -e '/^Co-Authored-By:.*amazonq@amazon\.com/Id' \
  -e '/^Co-Authored-By:.*@codeium\.com/Id' \
  -e '/^Co-Authored-By:.*@tabnine\.com/Id' \
  "$1"
HOOK_EOF
chmod +x "$_HOOKS_DIR/$_hook"
chown "$USER_NAME:$USER_NAME" "$_HOOKS_DIR/$_hook"
done
unset _hook
sudo -u "$USER_NAME" env -i HOME="$USER_HOME" PATH="$PATH" \
    git -C /tmp config --file "$USER_HOME/.gitconfig" core.hooksPath "$_HOOKS_DIR"
unset _HOOKS_DIR
ok "git: commit-msg + prepare-commit-msg hooks installed — AI co-author trailers stripped"

echo "wireshark-common wireshark-common/install-setuid boolean true" \
    | debconf-set-selections
apt-get install -y \
    wireshark tshark \
    man-db manpages manpages-dev manpages-posix manpages-posix-dev \
    linux-doc glibc-doc
usermod -aG wireshark "$USER_NAME"
ok "Wireshark + man-pages + linux-doc installed"
fi  # ─── end: 4/15 ───

hdr "5/15  Remote desktop access"
if (( _SKIP_INFRA || _DOTFILES_ONLY )); then
    info "5/15 skipped  (profile: ${INSTALL_PROFILE})"
else

# kwin-x11 is required for startplasma-x11 (used by xrdp) — not present on
# minimal Kubuntu installs which default to Wayland-only.
apt-get install -y kwin-x11 2>/dev/null \
    || warn "kwin-x11 unavailable — RDP/X11 sessions may fall back to failsafe"

apt-get install -y xrdp
systemctl enable xrdp

cat > /etc/xrdp/startwm.sh << 'XRDP_EOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi
export DESKTOP_SESSION=plasma
export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=KDE
exec startplasma-x11
XRDP_EOF
chmod +x /etc/xrdp/startwm.sh

adduser xrdp ssl-cert 2>/dev/null || true

# RDP (3389) — allow only from Tailscale (100.64.0.0/10) and ZeroTier (192.168.192.0/24 default)
# The UFW firewall is configured in the security hardening step; this adds the xrdp-specific rules.
ufw allow from 100.64.0.0/10 to any port 3389 proto tcp comment 'RDP via Tailscale' 2>/dev/null || true
ufw allow from 192.168.192.0/24 to any port 3389 proto tcp comment 'RDP via ZeroTier'  2>/dev/null || true

ok "xrdp (RDP server) configured on port 3389"
info "Connect using: Windows mstsc / xfreerdp3 CLI / KRDC (GUI) → host:3389"

apt-get install -y \
    freerdp3-x11 \
    tigervnc-viewer \
    || true
apt-get install -y freerdp3-wayland 2>/dev/null || true

ok "FreeRDP3 (xfreerdp3) + TigerVNC viewer installed"
info "GUI RDP/VNC:  KRDC → Start menu → KRDC  (auto-uses FreeRDP3 lib)"
info "CLI RDP:      xfreerdp3 /v:HOST /u:USER /p:PASS /w:1920 /h:1080 +clipboard +home-drive"
info "CLI VNC:      vncviewer HOST:PORT"
fi  # ─── end: 5/15 ───

hdr "6/15  GPU drivers ($GPU_TYPE)"
if (( _DOTFILES_ONLY )) || [[ "$GPU_TYPE" == "none" ]]; then
    info "6/15 skipped  (GPU type: ${GPU_TYPE})"
else

# ── GPU device permissions ─────────────────────────────────────────────────
# /dev/dri/card*       → group: video   (display access, KDE System Monitor)
# /dev/dri/renderD*    → group: render  (off-screen render, VA-API, Vulkan)
# Without both groups System Monitor shows 0% GPU and VA-API/Vulkan may fail.
usermod -aG video,render "$USER_NAME"
ok "User $USER_NAME added to video + render groups (GPU device access)"

if [[ "$GPU_TYPE" == "vm" ]]; then
    apt-get install -y \
        libgl1-mesa-dri \
        libgl1-mesa-dri:i386 \
        libglx-mesa0 \
        libegl-mesa0 \
        mesa-utils \
        || true

    VM_PLATFORM=""
    if systemd-detect-virt --quiet 2>/dev/null; then
        VM_PLATFORM=$(systemd-detect-virt 2>/dev/null || true)
    fi

    if [[ "$VM_PLATFORM" == "vmware" ]]; then
        info "VMware detected — installing open-vm-tools..."
        apt-get install -y \
            open-vm-tools \
            open-vm-tools-desktop \
            || true
        # xserver-xorg-video-vmware is an Xorg-only driver; Kubuntu 26.04+ is
        # Wayland-only so the vmwgfx kernel module drives the display directly.
        if (( UBUNTU_MAJOR < 26 )); then
            apt-get install -y xserver-xorg-video-vmware 2>/dev/null || true
        fi
        systemctl enable --now open-vm-tools 2>/dev/null || true
        ok "VMware guest tools installed (open-vm-tools-desktop + vmwgfx kernel driver)"
        info "Enables: clipboard share, drag-and-drop, dynamic screen resize, shared folders"

    elif [[ "$VM_PLATFORM" == "oracle" ]]; then
        info "VirtualBox detected — installing guest additions..."
        apt-get install -y virtualbox-guest-utils || true
        # virtualbox-guest-x11 is Xorg-only; Kubuntu 26.04+ is Wayland-only.
        # VirtualBox 7.1+ handles clipboard/resize via virtualbox-guest-utils alone.
        if (( UBUNTU_MAJOR < 26 )); then
            apt-get install -y virtualbox-guest-x11 2>/dev/null || true
        fi
        usermod -aG vboxsf "$USER_NAME" 2>/dev/null || true
        ok "VirtualBox guest additions installed (virtualbox-guest-utils)"
        info "Enables: clipboard share, drag-and-drop, dynamic screen resize, shared folders"
        info "Shared folders: user '${USER_NAME}' added to 'vboxsf' group (re-login required)"

    else
        info "QEMU/KVM or unknown hypervisor — installing virtio-gpu/SPICE stack..."
        # xserver-xorg-video-qxl is an Xorg-only driver; skip on Kubuntu 26.04+
        # (Wayland-only). SPICE agent works on Wayland since version 0.22 for
        # clipboard, dynamic resize, and folder sharing.
        if (( UBUNTU_MAJOR < 26 )); then
            apt-get install -y xserver-xorg-video-qxl 2>/dev/null || true
        fi
        apt-get install -y \
            spice-vdagent \
            spice-webdavd \
            || true
        apt-get install -y qemu-guest-agent || true
        systemctl enable --now qemu-guest-agent 2>/dev/null || true

        # 3D acceleration via Mesa virgl — requires the virtio-gpu display device
        # in virt-manager (not QXL). Install full Mesa + Vulkan software layer so
        # OpenGL 4.3 and Vulkan 1.1 work inside the guest without a physical GPU.
        apt-get install -y \
            mesa-vulkan-drivers \
            libvulkan1 \
            mesa-va-drivers \
            mesa-vdpau-drivers \
            libgl1-mesa-dri \
            libegl-mesa0 \
            libglx-mesa0 \
            mesa-utils \
            || true
        dpkg --add-architecture i386 2>/dev/null || true
        apt-get install -y libgl1-mesa-dri:i386 2>/dev/null || true

        # Tell Mesa to prefer the virgl Gallium driver for the virtio-gpu device.
        # DRI_PRIME is not needed here (no discrete GPU); MESA_LOADER_DRIVER_OVERRIDE
        # forces the virtio_gpu kernel driver path even if detection is ambiguous.
        cat > /etc/environment.d/99-virgl.conf << 'VIRGL_EOF'
MESA_LOADER_DRIVER_OVERRIDE=virtio_gpu
LIBGL_ALWAYS_SOFTWARE=0
VIRGL_EOF

        ok "QEMU/KVM guest tools installed (virtio-gpu/SPICE + Mesa virgl + Vulkan SW layer)"
        info "For 3D acceleration: set Display to 'virtio-gpu' (not QXL) in virt-manager"
        info "SPICE agent enables: clipboard share, dynamic screen resize, folder share"
    fi
fi

# ── NVIDIA userspace (no driver auto-install) ─────────────────────────────────
# The NVIDIA kernel driver must be installed via Driver Manager after reboot.
# Auto-installing it here risks leaving the system unbootable (initramfs/KMS
# conflicts, secure-boot signing issues). We install only the driver-independent
# userspace layer so the system is ready the moment the driver lands.
if [[ "$GPU_TYPE" == "nvidia" ]]; then
    dpkg --add-architecture i386 2>/dev/null || true
    apt-get install -y \
        libvulkan1 libvulkan1:i386 \
        vulkan-tools \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        || true
    ok "NVIDIA: Vulkan loader + Mesa fallback Vulkan installed"
    warn "NVIDIA driver intentionally NOT installed — open Driver Manager after reboot"
    info "  System Settings → Driver Manager  (or run: software-properties-qt)"
    info "  Select: nvidia-driver-595-open (recommended for Turing/Ampere/Ada)"
    info "  After driver install + reboot, nvidia-smi and vulkaninfo will show the dGPU"
fi

# ── AMD userspace (Mesa + RADV + VA-API/VDPAU) ───────────────────────────────
# Ubuntu 25.10+: mesa-va-drivers / mesa-vdpau-drivers are now thin wrappers that
# just depend on mesa-libgallium (which ships the actual drivers). Install
# mesa-libgallium explicitly and try the wrapper packages too so the block works
# on older Ubuntu without branching.
if [[ "$GPU_TYPE" == "amd" ]] || [[ "$GPU_TYPE" == "hybrid" ]]; then
    dpkg --add-architecture i386 2>/dev/null || true
    apt-get install -y \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        libvulkan1 libvulkan1:i386 \
        vulkan-tools \
        mesa-libgallium mesa-libgallium:i386 \
        libva2 libva2:i386 \
        libva-drm2 libva-drm2:i386 \
        libvdpau1 libvdpau1:i386 \
        libgl1-mesa-dri libgl1-mesa-dri:i386 \
        libglx-mesa0 \
        libegl-mesa0 \
        mesa-utils \
        radeontop \
        || true
    # Pre-26.04: mesa-va-drivers / mesa-vdpau-drivers are separate packages
    apt-get install -y mesa-va-drivers mesa-va-drivers:i386 \
        mesa-vdpau-drivers mesa-vdpau-drivers:i386 2>/dev/null || true
    ok "AMD: Mesa + RADV Vulkan + VA-API/VDPAU + radeontop installed"
    info "Vulkan: RADV (Mesa open-source) is the default ICD — set AMD_VULKAN_ICD=RADV to force it"
fi

# ── Intel userspace (Mesa + ANV Vulkan + VA-API) ─────────────────────────────
# intel-media-va-driver is the free (open-source) VA-API driver for Intel.
# intel-media-va-driver-non-free adds proprietary codec support (HEVC encode etc).
# Both are separate packages on Ubuntu 25.10; try non-free with || true in case
# it's been merged or removed in a future Ubuntu release.
if [[ "$GPU_TYPE" == "intel" ]]; then
    dpkg --add-architecture i386 2>/dev/null || true
    apt-get install -y \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        libvulkan1 libvulkan1:i386 \
        vulkan-tools \
        intel-media-va-driver intel-media-va-driver:i386 \
        libva2 libva2:i386 \
        libva-drm2 libva-drm2:i386 \
        libgl1-mesa-dri libgl1-mesa-dri:i386 \
        libglx-mesa0 \
        libegl-mesa0 \
        mesa-utils \
        intel-gpu-tools \
        || true
    # Pre-26.04: separate non-free variant with additional codec support
    apt-get install -y intel-media-va-driver-non-free 2>/dev/null || true
    ok "Intel: Mesa + ANV Vulkan + intel-media-va-driver + intel-gpu-tools installed"
fi

# ── Hybrid: NVIDIA Vulkan loader + switcheroo-control ────────────────────────
if [[ "$GPU_TYPE" == "hybrid" ]]; then
    apt-get install -y \
        switcheroo-control \
        || true
    systemctl enable --now switcheroo-control 2>/dev/null || true
    ok "Hybrid: switcheroo-control enabled (dynamic GPU switching for KDE/GNOME)"
    warn "NVIDIA dGPU driver intentionally NOT installed — open Driver Manager after reboot"
    info "  After driver install + reboot, AMD iGPU drives the display; NVIDIA via PRIME offload"
    info "  NOTE: PRIME hybrid setups on Wayland are complex — AMD-only is simpler and stable"
fi

# ── KDE System Monitor: GPU sensor prerequisites ─────────────────────────────
# ksystemstats reads GPU counters via three backends:
#   AMD/Intel  →  DRM sysfs  (/sys/class/drm/card*/device/gpu_busy_percent)
#                 requires /dev/dri/* readable by group 'video'/'render'
#   NVIDIA     →  NVML library (libnvidia-ml.so.1 from libnvidia-ml1)
#                 requires the driver to be loaded (post-reboot)
#
# Write a udev rule to enforce correct permissions on DRM device nodes.
# Ubuntu ships 60-drm.rules but some minimal installs omit the renderD* sub-rule;
# ours is numbered 61 so it overrides without replacing the distro default.
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/61-drm-ksystemstats.rules << 'UDEV_DRM_EOF'
# DRM GPU node permissions for KDE System Monitor (ksystemstats DRM backend)
# card*     — display / modesetting access (group: video)
# renderD*  — off-screen render / VA-API / Vulkan compute (group: render)
SUBSYSTEM=="drm", KERNEL=="card*",    GROUP="video",  MODE="0660"
SUBSYSTEM=="drm", KERNEL=="renderD*", GROUP="render", MODE="0660"
UDEV_DRM_EOF
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=drm 2>/dev/null || true
ok "udev: DRM GPU nodes group:video/render mode:0660  (/etc/udev/rules.d/61-drm-ksystemstats.rules)"

# ── i2c-dev udev rule: DDC/CI access for KDE powerdevil ──────────────────────
# powerdevil uses DDC/CI over i2c to read/set brightness on external monitors.
# Without a group + udev rule, /dev/i2c-* is root-only and logs EACCES at login.
groupadd -f i2c 2>/dev/null || true
cat > /etc/udev/rules.d/45-i2c-ddc.rules << 'I2C_UDEV_EOF'
# kubuntu-setup: grant i2c group access to i2c-dev nodes for DDC/CI (powerdevil)
SUBSYSTEM=="i2c-dev", KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
I2C_UDEV_EOF
usermod -aG i2c "$USER_NAME" 2>/dev/null || true
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=i2c-dev 2>/dev/null || true
ok "i2c group + udev rule added  (/dev/i2c-* → group i2c, powerdevil DDC/CI brightness works)"

# Run lm-sensors hardware detection non-interactively so GPU hwmon paths
# (amdgpu/nvidia/coretemp) are loaded into /etc/sensors3.conf automatically.
if command -v sensors-detect &>/dev/null; then
    sensors-detect --auto >> /var/log/kubuntu-setup-sensors.log 2>&1 || true
    ok "lm-sensors: auto-detected hardware sensors  (GPU temps visible in System Monitor)"
fi

# Restart ksystemstats so it picks up the new GPU backend without requiring a
# full logout/login. Non-fatal — user may be running a TTY-only install.
pkill -u "$USER_NAME" ksystemstats 2>/dev/null \
    && ok "ksystemstats restarted — GPU sensors active on next login" \
    || info "ksystemstats will auto-start with GPU sensors on next login"

fi  # ─── end: 6/15 ───

hdr "7/15  GPU tweaks ($GPU_TYPE)"
if (( _DOTFILES_ONLY )); then
    info "7/15 skipped  (profile: ${INSTALL_PROFILE})"
else

# ── AMD: prefer RADV over AMDVLK + amdgpu performance udev rule ──────────────
if [[ "$GPU_TYPE" == "amd" ]] || [[ "$GPU_TYPE" == "hybrid" ]]; then
    # AMD_VULKAN_ICD=RADV — prefer the Mesa open-source Vulkan driver over the
    # proprietary AMDVLK if both are installed. RADV has better Proton/DXVK
    # compatibility and receives faster updates than AMDVLK.
    mkdir -p /etc/environment.d
    cat > /etc/environment.d/60-amd-vulkan.conf << 'AMD_VULKAN_EOF'
AMD_VULKAN_ICD=RADV
AMD_VULKAN_EOF
    ok "AMD: AMD_VULKAN_ICD=RADV set  (Mesa RADV preferred over AMDVLK)"

    # amdgpu performance udev rule — sets power_dpm_force_performance_level to
    # 'auto' on all amdgpu DRM devices at boot. 'auto' lets the firmware use its
    # own heuristics (vs 'low' which caps clocks). Change to 'high' to always
    # run at max clocks (better for desktop, worse for battery).
    cat > /etc/udev/rules.d/62-amdgpu-performance.rules << 'AMDGPU_PERF_EOF'
# amdgpu: set power profile to 'auto' at boot (firmware-controlled clocks)
# Change 'auto' → 'high' for maximum performance (no power saving)
SUBSYSTEM=="drm", KERNEL=="card*", DRIVERS=="amdgpu", \
    ATTR{device/power_dpm_force_performance_level}="auto"
AMDGPU_PERF_EOF
    udevadm control --reload-rules 2>/dev/null || true
    ok "AMD: udev power profile rule written  (/etc/udev/rules.d/62-amdgpu-performance.rules)"
fi

# ── NVIDIA: threaded GL optimisations env var ─────────────────────────────────
if [[ "$GPU_TYPE" == "nvidia" ]] || [[ "$GPU_TYPE" == "hybrid" ]]; then
    mkdir -p /etc/environment.d
    # __GL_THREADED_OPTIMIZATIONS — NVIDIA's multi-threaded GL driver path.
    # Already set in section 12 gaming env for /etc/environment; writing here
    # via environment.d covers non-gaming sessions (Wayland compositors, apps
    # that don't inherit /etc/environment directly).
    cat > /etc/environment.d/61-nvidia-gl.conf << 'NVIDIA_GL_EOF'
__GL_THREADED_OPTIMIZATIONS=1
__GL_SHADER_DISK_CACHE=1
NVIDIA_GL_EOF
    ok "NVIDIA: __GL_THREADED_OPTIMIZATIONS=1 + shader disk cache set  (/etc/environment.d/61-nvidia-gl.conf)"
    info "ForceFullCompositionPipeline: set post-driver-install via nvidia-settings or ~/.nvidia-settings-rc"
fi

# ── Intel: set ANV Vulkan ICD explicitly ─────────────────────────────────────
# Ubuntu 25.10+: Mesa ships intel_icd.json (arch-agnostic) and intel_hasvk_icd.json
# (Haswell/Broadwell fallback). Older Ubuntu used intel_icd.x86_64.json per-arch files.
# Setting VK_ICD_FILENAMES to non-existent paths silently breaks Vulkan, so we
# detect which naming the installed Mesa uses and write the correct paths.
if [[ "$GPU_TYPE" == "intel" ]]; then
    mkdir -p /etc/environment.d
    _ICD_DIR="/usr/share/vulkan/icd.d"
    if [[ -f "${_ICD_DIR}/intel_icd.json" ]]; then
        # Mesa 25.x+ (Ubuntu 25.10+): arch-agnostic single file + Haswell fallback
        _INTEL_ICD="${_ICD_DIR}/intel_icd.json"
        [[ -f "${_ICD_DIR}/intel_hasvk_icd.json" ]] && \
            _INTEL_ICD="${_INTEL_ICD}:${_ICD_DIR}/intel_hasvk_icd.json"
    else
        # Older Mesa: per-arch files
        _INTEL_ICD="${_ICD_DIR}/intel_icd.x86_64.json:${_ICD_DIR}/intel_icd.i686.json"
    fi
    printf 'VK_ICD_FILENAMES=%s\n' "$_INTEL_ICD" \
        > /etc/environment.d/60-intel-vulkan.conf
    ok "Intel: ANV Vulkan ICD path set  (/etc/environment.d/60-intel-vulkan.conf → ${_INTEL_ICD})"
fi

# ── Hybrid: write prime-run wrapper if not present ───────────────────────────
if [[ "$GPU_TYPE" == "hybrid" ]]; then
    if [[ ! -f /usr/local/bin/prime-run ]]; then
        cat > /usr/local/bin/prime-run << 'PRIME_RUN_EOF'
#!/bin/bash
# prime-run — offload a single application to the NVIDIA dGPU.
# Usage: prime-run <command> [args…]
# Requires: NVIDIA driver installed + switcheroo-control active.
export DRI_PRIME=1
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
exec "$@"
PRIME_RUN_EOF
        chmod +x /usr/local/bin/prime-run
        ok "Hybrid: /usr/local/bin/prime-run wrapper written"
    else
        info "Hybrid: /usr/local/bin/prime-run already exists — not overwritten"
    fi
fi

fi  # ─── end: 7/15 ───

hdr "8/15  NTFS + filesystem support (read/write)"
if (( _DOTFILES_ONLY )); then
    info "8/15 skipped  (profile: ${INSTALL_PROFILE})"
else

apt-get install -y ntfs-3g exfatprogs exfat-fuse \
    dosfstools mtools fuseiso

ok "ntfs-3g, exfatprogs, fuseiso installed"

USER_UID=$(id -u "$USER_NAME")
USER_GID=$(id -g "$USER_NAME")
_NTFS_COUNT=0
while IFS= read -r NTFS_PART; do
    [[ -z "$NTFS_PART" ]] && continue
    NTFS_UUID=$(blkid -s UUID -o value "$NTFS_PART" 2>/dev/null)
    [[ -z "$NTFS_UUID" ]] && continue
    if grep -q "$NTFS_UUID" /etc/fstab 2>/dev/null; then
        warn "$(basename "$NTFS_PART"): UUID already in /etc/fstab — skipped"
        continue
    fi
    RAW_LABEL=$(blkid -s LABEL -o value "$NTFS_PART" 2>/dev/null)
    if [[ -n "$RAW_LABEL" ]]; then
        NTFS_SLUG=$(echo "$RAW_LABEL" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_-')
    else
        NTFS_SLUG="ntfs_$(basename "$NTFS_PART")"
    fi
    NTFS_MNT="/mnt/${NTFS_SLUG}"
    _IDX=1
    while [[ -d "$NTFS_MNT" && "$_IDX" -lt 10 ]]; do
        NTFS_MNT="/mnt/${NTFS_SLUG}_${_IDX}"
        (( _IDX++ ))
    done
    mkdir -p "$NTFS_MNT"
    chmod 755 "$NTFS_MNT"
    {
        echo ""
        echo "# NTFS: $(basename "$NTFS_PART")${RAW_LABEL:+ ($RAW_LABEL)} — added by setup-kubuntu.sh"
        echo "UUID=${NTFS_UUID}  ${NTFS_MNT}  ntfs3  uid=${USER_UID},gid=${USER_GID},dmask=022,fmask=033,noatime,nofail  0  0"
    } >> /etc/fstab
    ok "$(basename "$NTFS_PART")${RAW_LABEL:+ [${RAW_LABEL}]} → ${NTFS_MNT} (auto-mount at boot)"
    (( _NTFS_COUNT++ ))
done < <(blkid -t TYPE=ntfs -o device 2>/dev/null)
[[ "$_NTFS_COUNT" -eq 0 ]] && warn "No NTFS partitions detected — ntfs-3g installed; add fstab entries manually if needed"
fi  # ─── end: 8/15 ───

hdr "9/15  Gaming — Wine, Steam, launchers"
if (( _SKIP_GAMING || _DOTFILES_ONLY )); then
    info "9/15 skipped  (profile: ${INSTALL_PROFILE})"
else

info "Setting up WineHQ repository (${UBUNTU_CODENAME})..."

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/winehq-archive.key ]]; then
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
        | gpg --batch --yes --dearmor -o /etc/apt/keyrings/winehq-archive.key
    ok "WineHQ signing key saved"
fi

WINEHQ_SOURCES_URL="https://dl.winehq.org/wine-builds/ubuntu/dists/${UBUNTU_CODENAME}/winehq-${UBUNTU_CODENAME}.sources"
WINEHQ_SOURCES_FILE="/etc/apt/sources.list.d/winehq-${UBUNTU_CODENAME}.sources"
if curl -fsLm 15 -o /dev/null "${WINEHQ_SOURCES_URL}" 2>/dev/null; then
    info "WineHQ carries packages for '${UBUNTU_CODENAME}' — adding sources file..."
    if [[ ! -f "$WINEHQ_SOURCES_FILE" ]]; then
        wget -qO "$WINEHQ_SOURCES_FILE" "${WINEHQ_SOURCES_URL}"
    fi
    apt-get update -qq 2>&1 | grep -E '^(E:|W:)' || true
    apt-get install -y --install-recommends winehq-staging \
        && ok "winehq-staging installed (WoW64-capable on 25.10+)" \
        || {
            warn "winehq-staging failed; trying ubuntu wine..."
            apt-get install -y wine || true
        }
else
    warn "WineHQ does not yet publish packages for '${UBUNTU_CODENAME}' — using Ubuntu wine"
    apt-get install -y wine || true
fi

info "Installing winetricks (latest)..."
wget -q https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    -O /usr/local/bin/winetricks
chmod +x /usr/local/bin/winetricks
ok "winetricks installed"

info "Installing Wine/Proton runtime libraries..."
# Ubuntu 25.04+ uses t64-suffixed lib names (64-bit time_t ABI transition).
# Try the t64 name first; fall back to the legacy name for older Ubuntu releases.
_t64_pkg() {
    local base=$1 arch=${2:-}
    local suffix=${arch:+:${arch}}
    if apt-cache show "${base}t64${suffix}" &>/dev/null 2>&1; then
        echo "${base}t64${suffix}"
    else
        echo "${base}${suffix}"
    fi
}
apt-get install -y \
    "$(_t64_pkg libgnutls30 i386)" \
    libgpg-error0:i386 \
    "$(_t64_pkg libxml2 i386)" \
    libsdl2-2.0-0:i386 \
    libfreetype6:i386 \
    libdbus-1-3:i386 \
    libsqlite3-0:i386 \
    libvulkan1:i386 \
    mesa-vulkan-drivers:i386 \
    libgl1:i386 \
    libgl1-mesa-dri:i386 \
    libopenal1:i386 libopenal1 \
    libpulse0:i386 libpulse0 \
    libfontconfig1:i386 \
    libxcomposite1:i386 libxcursor1:i386 libxi6:i386 \
    libxrandr2:i386 libxinerama1:i386 \
    "$(_t64_pkg libglib2.0-0 i386)" \
    libasound2-plugins:i386 \
    || warn "Some 32-bit Wine libs failed (usually non-fatal with winehq-staging)"
unset -f _t64_pkg
# winbind provides ntlm_auth ≥ 3.0.25 which Wine requires for NTLM/Kerberos
# authentication used by Battle.net-style launchers and custom WoW launchers.
# libgssapi-krb5-2 / libkrb5-3 are pulled in by winbind but listed explicitly
# to ensure they're present even if the winbind package name changes.
apt-get install -y \
    winbind \
    libgssapi-krb5-2 \
    libkrb5-3 \
    || warn "winbind/Kerberos install failed — Battle.net-style launchers may have auth issues"
ok "Wine runtime libraries installed (+ winbind NTLM auth)"

info "Installing Steam..."
apt-get install -y steam-installer 2>/dev/null \
    || apt-get install -y steam 2>/dev/null \
    || warn "Steam install failed — download from https://store.steampowered.com/about/"
ok "Steam installed"

# Steam on Linux has a buggy HTTP/2 download implementation that causes
# throttling and unstable speeds (well-documented on Arch Linux forums).
# Disabling HTTP/2 restores full download rate; fDownloadRateImprovement
# controls when Steam opens additional parallel connections (1.0 = only when
# current connection stalls, which avoids the multi-connection race condition).
_STEAM_CFG_DIR="${USER_HOME}/.steam/steam"
mkdir -p "${_STEAM_CFG_DIR}"
cat > "${_STEAM_CFG_DIR}/steam_dev.cfg" << 'STEAM_DEV_EOF'
@nClientDownloadEnableHTTP2PlatformLinux 0
@fDownloadRateImprovementToAddAnotherConnection 1.0
STEAM_DEV_EOF
chown -R "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.steam"
ok "Steam HTTP/2 disabled (networking stability + speed fix)"

info "Installing Discord (deb-get adds apt repo for auto-updates)..."
if ! dg_install discord; then
    warn "deb-get discord failed — falling back to direct download"
    wget -q "https://discord.com/api/download?platform=linux&format=deb" \
        -O /tmp/discord.deb
    apt-get install -y /tmp/discord.deb || warn "Discord install failed"
    rm -f /tmp/discord.deb
fi
ok "Discord installed"

info "Installing Heroic Games Launcher (Epic / GOG) via deb-get..."
if ! dg_install heroic; then
    warn "deb-get heroic failed — falling back to GitHub API download"
    HEROIC_URL=$(curl -sLm 30 \
        https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest \
        | grep '"browser_download_url"' | grep '_amd64\.deb"' | head -1 | cut -d '"' -f 4)
    if [[ -n "$HEROIC_URL" ]]; then
        wget -q "$HEROIC_URL" -O /tmp/heroic_amd64.deb
        apt-get install -y /tmp/heroic_amd64.deb
        rm -f /tmp/heroic_amd64.deb
    else
        warn "Could not fetch Heroic — install manually from https://heroicgameslauncher.com"
    fi
fi
ok "Heroic Games Launcher installed (Epic Games + GOG)"

info "Installing Lutris runtime dependencies..."
apt-get install -y \
    python3-gi python3-gi-cairo \
    gir1.2-gtk-3.0 \
    python3-yaml python3-requests python3-pydbus \
    cabextract p7zip-full 7zip-rar \
    fluid-soundfont-gm \
    xterm xdg-utils \
    || true
apt-get install -y gir1.2-webkit2-4.0 2>/dev/null \
    || apt-get install -y gir1.2-webkit2-4.1 2>/dev/null \
    || true

info "Installing Lutris via deb-get..."
if ! dg_install lutris; then
    warn "deb-get lutris failed — falling back to GitHub API download"
    LUTRIS_URL=$(curl -sLm 30 \
        https://api.github.com/repos/lutris/lutris/releases/latest \
        | grep '"browser_download_url"' | grep '\.deb"' | head -1 | cut -d '"' -f 4)
    if [[ -n "$LUTRIS_URL" ]]; then
        wget -q "$LUTRIS_URL" -O /tmp/lutris.deb
        apt-get install -y /tmp/lutris.deb
        rm -f /tmp/lutris.deb
    else
        apt-get install -y lutris \
            || warn "Lutris install failed — visit https://lutris.net/downloads"
    fi
fi
ok "Lutris installed"
info "Use Lutris to install: EA Desktop App, Rockstar Games Launcher"


info "Fetching Proton-GE + Wine-GE release info in parallel..."
STEAM_COMPAT_DIR="${USER_HOME}/.local/share/Steam/compatibilitytools.d"
WINE_GE_LUTRIS_DIR="${USER_HOME}/.local/share/lutris/runners/wine"
WINE_GE_HEROIC_DIR="${USER_HOME}/.local/share/heroic/tools/wine"
mkdir -p "${STEAM_COMPAT_DIR}" "${WINE_GE_LUTRIS_DIR}" "${WINE_GE_HEROIC_DIR}"
# chown the Steam parent dir too — script runs as root and mkdir creates it root-owned,
# which prevents steam-installer from writing its bootstrap files.
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/share/Steam" "${STEAM_COMPAT_DIR}"
chown -R "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/share/lutris"
chown -R "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/share/heroic"

_TMP_PGE=$(mktemp); _TMP_WGE=$(mktemp)
curl -sLm 30 https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
    > "$_TMP_PGE" 2>/dev/null &
_PID_PGE=$!
curl -sLm 30 https://api.github.com/repos/GloriousEggroll/wine-ge-custom/releases/latest \
    > "$_TMP_WGE" 2>/dev/null &
_PID_WGE=$!
wait "$_PID_PGE" "$_PID_WGE"
PROTON_GE_INFO=$(cat "$_TMP_PGE"); rm -f "$_TMP_PGE"
WINE_GE_INFO=$(cat "$_TMP_WGE");   rm -f "$_TMP_WGE"

PROTON_GE_URL=$(echo "${PROTON_GE_INFO}" \
    | grep '"browser_download_url"' | grep '\.tar\.gz"' \
    | grep -v '\.sha512sum' | head -1 | cut -d '"' -f 4)
PROTON_GE_VER=$(echo "${PROTON_GE_INFO}" \
    | grep '"tag_name"' | head -1 | cut -d '"' -f 4)

if [[ -n "$PROTON_GE_URL" ]]; then
    _PGE_FILE="${GE_CACHE}/$(basename "$PROTON_GE_URL")"
    _PGE_DEST="${STEAM_COMPAT_DIR}/${PROTON_GE_VER}"
    if [[ -d "$_PGE_DEST" ]]; then
        ok "Proton-GE ${PROTON_GE_VER} already installed → ${_PGE_DEST} (skipped)"
    else
        if [[ -f "$_PGE_FILE" ]]; then
            info "Proton-GE ${PROTON_GE_VER}: found in cache → ${_PGE_FILE}"
        else
            info "Downloading Proton-GE ${PROTON_GE_VER} (~500 MB) → cache..."
            wget --progress=bar:force:noscroll "${PROTON_GE_URL}" -O "$_PGE_FILE"
        fi
        tar -xzf "$_PGE_FILE" -C "${STEAM_COMPAT_DIR}/"
        chown -R "${USER_NAME}:${USER_NAME}" "${STEAM_COMPAT_DIR}"
        ok "Proton-GE ${PROTON_GE_VER} → ${STEAM_COMPAT_DIR}/"
    fi
else
    warn "Could not fetch Proton-GE — use ProtonUp-Qt after login to download it"
fi

WINE_GE_URL=$(echo "${WINE_GE_INFO}" \
    | grep '"browser_download_url"' | grep '\.tar\.xz"' \
    | grep -v '\.sha512sum' | head -1 | cut -d '"' -f 4)
WINE_GE_VER=$(echo "${WINE_GE_INFO}" \
    | grep '"tag_name"' | head -1 | cut -d '"' -f 4)

if [[ -n "$WINE_GE_URL" ]]; then
    _WGE_FILE="${GE_CACHE}/$(basename "$WINE_GE_URL")"
    _WGE_BASENAME=$(basename "$WINE_GE_URL" .tar.xz)
    _WGE_DEST_LUTRIS="${WINE_GE_LUTRIS_DIR}/${_WGE_BASENAME}"
    if [[ -d "$_WGE_DEST_LUTRIS" ]]; then
        ok "Wine-GE ${WINE_GE_VER} already installed (skipped)"
    else
        if [[ -f "$_WGE_FILE" ]]; then
            info "Wine-GE ${WINE_GE_VER}: found in cache → ${_WGE_FILE}"
        else
            info "Downloading Wine-GE ${WINE_GE_VER} (~200 MB) → cache..."
            wget --progress=bar:force:noscroll "${WINE_GE_URL}" -O "$_WGE_FILE"
        fi
        tar -xJf "$_WGE_FILE" -C "${WINE_GE_LUTRIS_DIR}/"
        tar -xJf "$_WGE_FILE" -C "${WINE_GE_HEROIC_DIR}/"
        chown -R "${USER_NAME}:${USER_NAME}" "${WINE_GE_LUTRIS_DIR}"
        chown -R "${USER_NAME}:${USER_NAME}" "${WINE_GE_HEROIC_DIR}"
        ok "Wine-GE ${WINE_GE_VER} → Lutris runners + Heroic tools"
    fi
else
    warn "Could not fetch Wine-GE — use ProtonUp-Qt after login to download it"
fi

# ── Proton-GE auto-updater (weekly systemd user timer) ────────────────────────
info "Deploying Proton-GE auto-updater (weekly systemd user timer)..."
mkdir -p "${USER_HOME}/.local/bin"
cat > "${USER_HOME}/.local/bin/proton-ge-update.sh" << 'PGUPD_EOF'
#!/usr/bin/env bash
# proton-ge-update.sh — download latest Proton-GE into Steam compatibilitytools.d
# Runs weekly via systemd user timer; sends a KDE notification on install.
set -euo pipefail

COMPAT_DIR="${HOME}/.local/share/Steam/compatibilitytools.d"
GE_CACHE="${HOME}/.cache/proton-ge"
mkdir -p "${COMPAT_DIR}" "${GE_CACHE}"

API_JSON=$(curl -fsSLm 30 \
    https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest)
VER=$(echo "$API_JSON" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
URL=$(echo "$API_JSON" | grep '"browser_download_url"' | grep '\.tar\.gz"' \
    | grep -v '\.sha512sum' | head -1 | cut -d'"' -f4)

[[ -z "$VER" || -z "$URL" ]] && { echo "ERROR: Could not fetch Proton-GE release info"; exit 1; }

DEST="${COMPAT_DIR}/${VER}"
if [[ -d "$DEST" ]]; then
    echo "Proton-GE ${VER} already installed — nothing to do"
    exit 0
fi

CACHE_FILE="${GE_CACHE}/$(basename "$URL")"
[[ -f "$CACHE_FILE" ]] || wget -q --show-progress "$URL" -O "$CACHE_FILE"
tar -xzf "$CACHE_FILE" -C "${COMPAT_DIR}/"
echo "Proton-GE ${VER} installed → ${DEST}"
notify-send -u normal -i applications-games \
    "Proton-GE Updated" "Installed ${VER}" 2>/dev/null || true
PGUPD_EOF
chmod +x "${USER_HOME}/.local/bin/proton-ge-update.sh"
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/proton-ge-update.sh"

mkdir -p "${USER_HOME}/.config/systemd/user"
cat > "${USER_HOME}/.config/systemd/user/proton-ge-update.service" << 'PGUSVC_EOF'
[Unit]
Description=Proton-GE auto-updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/proton-ge-update.sh
PGUSVC_EOF

cat > "${USER_HOME}/.config/systemd/user/proton-ge-update.timer" << 'PGUTMR_EOF'
[Unit]
Description=Weekly Proton-GE update check

[Timer]
OnBootSec=10min
OnUnitActiveSec=7d
Persistent=true

[Install]
WantedBy=timers.target
PGUTMR_EOF

chown -R "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.config/systemd/user"
sudo -u "$USER_NAME" systemctl --user daemon-reload 2>/dev/null || true
sudo -u "$USER_NAME" systemctl --user enable --now proton-ge-update.timer 2>/dev/null || true
ok "Proton-GE auto-updater timer deployed  (checks weekly + 10 min after boot)"


info "Installing MangoHud + GameMode..."
apt-get install -y \
    gamemode \
    libgamemode0 \
    libgamemodeauto0 \
    libgamemode0:i386 \
    libgamemodeauto0:i386 \
    mangohud \
    goverlay \
    kscreen \
    || true
ok "MangoHud + GameMode + GOverlay + kscreen installed"
info "Steam launch option: mangohud gamemoderun %command%"
info "  (use the mangohud wrapper — MANGOHUD=1 alone is unreliable with Steam)"

# ── MangoHud config ───────────────────────────────────────────────────────────
# Deploy a sensible default MangoHud config if none exists.
# Users can tweak ~/.config/MangoHud/MangoHud.conf at any time.
_MANGOHUD_CFG_DIR="${USER_HOME}/.config/MangoHud"
mkdir -p "$_MANGOHUD_CFG_DIR"
if [[ ! -f "${_MANGOHUD_CFG_DIR}/MangoHud.conf" ]]; then
    cat > "${_MANGOHUD_CFG_DIR}/MangoHud.conf" << 'MANGOHUD_CFG_EOF'
# MangoHud config — kubuntu-setup
# Toggle with Shift_R+F12. Full option reference: man MangoHud.conf

# GPU stats — required for iGPU (Intel/AMD integrated) to show up
gpu_stats
gpu_temp
gpu_core_clock
gpu_mem_clock
gpu_load_change
vram

# CPU stats
cpu_temp
cpu_mhz
cpu_load_change
cpu_core_load

# Memory
ram

# Frame pacing
fps
frametime
frame_timing=1

# Display
font_size=22
background_alpha=0.5

# If MangoHud picks the wrong GPU (e.g. dGPU instead of iGPU), run
# 'mangohud --info' to list PCI addresses, then uncomment and set:
#pci_dev=0:00:02.0

# Keybinds
toggle_hud=Shift_R+F12
toggle_fps_limit=Shift_R+F1
MANGOHUD_CFG_EOF
    chown -R "${USER_NAME}:${USER_NAME}" "$_MANGOHUD_CFG_DIR"
    ok "MangoHud config deployed  (~/.config/MangoHud/MangoHud.conf)"
else
    info "MangoHud: existing ~/.config/MangoHud/MangoHud.conf untouched"
fi

info "Deploying gamemode configuration + KWin compositor hooks..."

mkdir -p "${USER_HOME}/.config"
cat > "${USER_HOME}/.config/gamemode.ini" << 'GAMEMODE_EOF'
[general]
# How often (seconds) gamemoded checks for dead game processes
reaper_freq = 5
# cpu governor while gamemode is active
desiredgov = performance
# soft-realtime scheduling (auto = only for games that can use it)
softrealtime = auto
# renice games by this amount (negative = higher prio; safe range: -10 to 0)
renice = -5
# ioprio class for game process I/O
ioprio = 0
# Prevent screensaver/display power-off while gamemode is active
inhibit_screensaver = 1

[gpu]
# Uncomment the block below to let gamemode also manage GPU power profiles.
# Requires gamemoded to have sysfs write access (system daemon with polkit/sudo).
# Test by running:  gamemoded -t
;
apply_gpu_optimisations = accept-responsibility
gpu_device = 0
# AMD RDNA2/3 / Vega / Polaris (amdgpu kernel driver)
amd_performance_level = high
# NVIDIA (0=adaptive, 1=prefer max performance, 2=auto, 3=on-demand)
;nv_powermizer_mode = 1

[custom]
# These scripts are called by gamemoded when a game starts and stops.
# They handle compositor suspension which gamemode doesn't do natively.
start = ${HOME}/.local/bin/gamemode-start.sh
end   = ${HOME}/.local/bin/gamemode-end.sh
GAMEMODE_EOF

chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.config/gamemode.ini"
ok "gamemode.ini deployed"

mkdir -p "${USER_HOME}/.local/bin"
cat > "${USER_HOME}/.local/bin/gamemode-start.sh" << 'GMSTART_EOF'
#!/bin/bash
# gamemode-start.sh
# Called by gamemoded when a game activates gamemode.
# Suspends KWin compositor to free GPU resources and reduce frame latency.
# Works whether gamemoded runs as the user or as a system daemon (root).

# ---- locate the active desktop session D-Bus socket ----
# Priority: environment already set (user service) > /run/user/<uid>/bus
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    # For a system daemon running as root: scan /run/user/ for non-root sessions
    for RU in /run/user/[0-9]*/; do
        _UID=$(basename "$RU")
        [ "$_UID" = "0" ] && continue
        [ -S "${RU}bus" ] || continue
        SESSION_UID="$_UID"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${RU}bus"
        break
    done
fi

_run_as_session_user() {
    # Run a command in the context of the session owner
    if [ -n "$SESSION_UID" ] && [ "$(id -u)" = "0" ]; then
        sudo -u "#${SESSION_UID}" \
            env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
            XDG_RUNTIME_DIR="/run/user/${SESSION_UID}" \
            "$@"
    else
        "$@"
    fi
}

# ---- suspend KWin compositor (reduces latency / frees GPU for direct rendering) ----
_run_as_session_user qdbus6 org.kde.KWin /Compositor \
    org.kde.kwin.Compositing.suspend 2>/dev/null || \
_run_as_session_user qdbus  org.kde.KWin /Compositor suspend 2>/dev/null || true

# ---- request highest refresh rate on all connected outputs (kscreen-doctor) ----
# kscreen-doctor lists available modes; we pick the mode with the highest Hz
# at the current resolution for each enabled output.
if command -v kscreen-doctor >/dev/null 2>&1; then
    _run_as_session_user bash -c '
        kscreen-doctor 2>/dev/null \
        | awk "/^Output:/{out=\$2} /mode:.*@/{match(\$0,/@([0-9.]+)/,a); r=a[1]+0; if(r>max[out]){max[out]=r; mode[out]=\$0}} END{for(o in max) print \"output.\"o\".mode.\"int(max[o])}"
        | grep -v output.. \
        | while read -r CMD; do kscreen-doctor "$CMD" 2>/dev/null || true; done
    ' 2>/dev/null || true
fi

logger -t gamemode-hook "START — compositor suspended, max refresh rate requested"
GMSTART_EOF
chmod +x "${USER_HOME}/.local/bin/gamemode-start.sh"
chown    "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/gamemode-start.sh"

cat > "${USER_HOME}/.local/bin/gamemode-end.sh" << 'GMEND_EOF'
#!/bin/bash
# gamemode-end.sh
# Called by gamemoded when all games using gamemode have exited.
# Resumes KWin compositor so the desktop returns to normal.

# ---- locate the active desktop session D-Bus socket ----
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    for RU in /run/user/[0-9]*/; do
        _UID=$(basename "$RU")
        [ "$_UID" = "0" ] && continue
        [ -S "${RU}bus" ] || continue
        SESSION_UID="$_UID"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${RU}bus"
        break
    done
fi

_run_as_session_user() {
    if [ -n "$SESSION_UID" ] && [ "$(id -u)" = "0" ]; then
        sudo -u "#${SESSION_UID}" \
            env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
            XDG_RUNTIME_DIR="/run/user/${SESSION_UID}" \
            "$@"
    else
        "$@"
    fi
}

# ---- resume KWin compositor ----
_run_as_session_user qdbus6 org.kde.KWin /Compositor \
    org.kde.kwin.Compositing.resume 2>/dev/null || \
_run_as_session_user qdbus  org.kde.KWin /Compositor resume 2>/dev/null || true

logger -t gamemode-hook "END — compositor resumed"
GMEND_EOF
chmod +x "${USER_HOME}/.local/bin/gamemode-end.sh"
chown    "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/gamemode-end.sh"

ok "GameMode config + compositor hooks deployed"

# ── Additional gaming tools ────────────────────────────────────────────────────

info "Installing gamescope (Valve micro-compositor)..."
apt-get install -y gamescope 2>/dev/null \
    || warn "gamescope not available for ${UBUNTU_CODENAME} — install manually"
ok "gamescope installed"

info "Installing vkbasalt (Vulkan post-processing layer)..."
apt-get install -y vkbasalt vkbasalt:i386 2>/dev/null \
    || warn "vkbasalt unavailable — install manually"
ok "vkbasalt installed"

info "Installing DXVK (apt) + vkd3d-proton (apt)..."
apt-get install -y \
    dxvk \
    libvkd3d1 \
    libvkd3d-dev \
    2>/dev/null || warn "dxvk/vkd3d apt packages unavailable — Proton-GE bundles its own copies"
ok "DXVK + vkd3d installed (Proton-GE also bundles its own; these cover native Wine)"

info "Installing input-remapper (kernel-level controller remapping)..."
apt-get install -y input-remapper 2>/dev/null \
    || warn "input-remapper unavailable — install from https://github.com/sezanzeb/input-remapper"
systemctl enable input-remapper 2>/dev/null || true
ok "input-remapper installed"

# ── Controller kernel drivers: xone, hid-nintendo, xpadneo ───────────────────
info "Installing controller kernel drivers (xone/hid-nintendo/xpadneo)..."
apt-get install -y dkms 2>/dev/null || true

# xone — Xbox One/Series wireless USB dongle (GIP protocol, no official kernel support)
if ! dkms status 2>/dev/null | grep -q "^xone"; then
    _XONE_TMP=$(mktemp -d)
    if git clone --depth=1 https://github.com/medusalix/xone "$_XONE_TMP" 2>/dev/null; then
        ( cd "$_XONE_TMP" && make dkms-install KVER="$(uname -r)" 2>/dev/null ) \
            && ok  "xone DKMS module installed  (Xbox One/Series wireless USB dongle)" \
            || warn "xone DKMS build failed — install manually from https://github.com/medusalix/xone"
    else
        warn "xone git clone failed (no internet?) — install manually from https://github.com/medusalix/xone"
    fi
    rm -rf "$_XONE_TMP"
else
    ok "xone DKMS module already installed"
fi

# hid-nintendo — Nintendo Switch Pro Controller + Joy-Con over Bluetooth/USB
apt-get install -y hid-nintendo-dkms 2>/dev/null \
|| {
    _HNITN_TMP=$(mktemp -d)
    if git clone --depth=1 https://github.com/nicman23/dkms-hid-nintendo "$_HNITN_TMP" 2>/dev/null; then
        _HNITN_VER=$(grep '^PACKAGE_VERSION=' "$_HNITN_TMP/dkms.conf" | cut -d= -f2 | tr -d '"')
        ( cd "$_HNITN_TMP" \
          && dkms add    -m hid-nintendo -v "$_HNITN_VER" --sourcetree . 2>/dev/null \
          && dkms build  -m hid-nintendo -v "$_HNITN_VER" 2>/dev/null \
          && dkms install -m hid-nintendo -v "$_HNITN_VER" 2>/dev/null ) \
            && ok  "hid-nintendo DKMS installed  (Nintendo Switch Pro / Joy-Con)" \
            || warn "hid-nintendo DKMS build failed — install manually from https://github.com/nicman23/dkms-hid-nintendo"
    else
        warn "hid-nintendo git clone failed — install manually from https://github.com/nicman23/dkms-hid-nintendo"
    fi
    rm -rf "$_HNITN_TMP"
}

# xpadneo — Xbox controller Bluetooth (better than the in-kernel xpad driver)
apt-get install -y xpadneo 2>/dev/null \
|| {
    if ! dkms status 2>/dev/null | grep -q "^xpadneo"; then
        _XPNEO_TMP=$(mktemp -d)
        if git clone --depth=1 https://github.com/atar-axis/xpadneo "$_XPNEO_TMP" 2>/dev/null; then
            ( cd "$_XPNEO_TMP" && bash install.sh 2>/dev/null ) \
                && ok  "xpadneo DKMS installed  (Xbox controller Bluetooth — better rumble/trigger support)" \
                || warn "xpadneo install failed — install manually from https://github.com/atar-axis/xpadneo"
        else
            warn "xpadneo git clone failed — install manually from https://github.com/atar-axis/xpadneo"
        fi
        rm -rf "$_XPNEO_TMP"
    else
        ok "xpadneo DKMS module already installed"
    fi
}
ok "Controller drivers: xone (Xbox wireless) + hid-nintendo (Switch Pro) + xpadneo (Xbox BT)"

# ── AntiMicroX (gamepad → keyboard/mouse mapping GUI) ────────────────────────
info "Installing AntiMicroX (gamepad → keyboard/mouse mapping GUI)..."
_AMX_URL=$(curl -fsSLm 15 \
    "https://api.github.com/repos/AntiMicroX/antimicrox/releases/latest" \
    | grep '"browser_download_url"' | grep '_amd64\.deb"' \
    | head -1 | cut -d'"' -f4)
if [[ -n "$_AMX_URL" ]]; then
    wget -qO /tmp/antimicrox.deb "$_AMX_URL" \
    && apt-get install -y /tmp/antimicrox.deb \
    && ok  "AntiMicroX installed  (GUI gamepad remapper — launch from app menu)" \
    || warn "AntiMicroX deb install failed — download from https://github.com/AntiMicroX/antimicrox/releases"
    rm -f /tmp/antimicrox.deb
else
    apt-get install -y antimicrox 2>/dev/null \
        && ok  "AntiMicroX installed" \
        || warn "AntiMicroX unavailable — install from https://github.com/AntiMicroX/antimicrox/releases"
fi

info "Installing switcheroo-control (hybrid GPU dGPU selector)..."
# switcheroo-control: D-Bus service that exposes the GPU list and per-GPU offload
# capability to userspace.  gamemoderun, Lutris, Heroic, and MangoHud all use it
# to auto-select the dGPU.  Needs to be running before any game is launched.
apt-get install -y switcheroo-control 2>/dev/null || true
systemctl enable --now switcheroo-control 2>/dev/null || true
ok "switcheroo-control installed + enabled  (D-Bus GPU offload for gamemoderun/Lutris/Heroic)"

info "Installing s-tui (thermal/clock monitor)..."
apt-get install -y s-tui 2>/dev/null || pip3 install s-tui 2>/dev/null \
    || warn "s-tui unavailable"
ok "s-tui installed"

info "Installing GTK/libappindicator runtime libs (Flatpak launcher dependencies)..."
apt-get install -y \
    libadwaita-1-0 \
    libayatana-appindicator3-1 \
    libappindicator3-1 \
    2>/dev/null || true
ok "libadwaita + libappindicator runtime libs installed"

info "Installing ProtonUp-Qt via Flatpak (Proton-GE/Wine-GE updater GUI)..."
if command -v flatpak &>/dev/null; then
    sudo -u "$USER_NAME" flatpak install -y --noninteractive \
        flathub net.davidotek.pupgui2 2>/dev/null \
        && ok "ProtonUp-Qt installed (run from app menu after login)" \
        || warn "ProtonUp-Qt Flatpak install failed — run manually: flatpak install flathub net.davidotek.pupgui2"
else
    warn "Flatpak not available — ProtonUp-Qt skipped"
fi

info "Installing Flatseal (Flatpak permission manager) via Flatpak..."
if command -v flatpak &>/dev/null; then
    sudo -u "$USER_NAME" flatpak install -y --noninteractive \
        flathub com.github.tchx84.Flatseal 2>/dev/null \
        && ok "Flatseal installed" \
        || warn "Flatseal Flatpak install failed — run manually: flatpak install flathub com.github.tchx84.Flatseal"
else
    warn "Flatpak not available — Flatseal skipped"
fi

# ── Bottles (isolated Wine environment manager) ───────────────────────────────
info "Installing Bottles (isolated Wine environment manager) via Flatpak..."
if command -v flatpak &>/dev/null; then
    sudo -u "$USER_NAME" flatpak install -y --noninteractive \
        flathub com.usebottles.bottles 2>/dev/null \
        && ok "Bottles installed  (isolated Wine/Proton envs — better than bare Lutris for non-Steam games)" \
        || warn "Bottles Flatpak install failed — run manually: flatpak install flathub com.usebottles.bottles"
else
    warn "Flatpak not available — Bottles skipped"
fi

# ── Sunshine + Moonlight (self-hosted GPU game streaming) ─────────────────────
# Sunshine: server-side GameStream replacement (runs on this machine)
# Moonlight: client-side viewer (installed for use on remote machines)
info "Installing Sunshine (self-hosted game streaming server)..."
_SUN_API=$(curl -fsSLm 15 \
    "https://api.github.com/repos/LizardByte/Sunshine/releases/latest" 2>/dev/null)
# Prefer ubuntu-24.04 deb; fall back to any amd64 deb
_SUN_URL=$(echo "$_SUN_API" \
    | grep '"browser_download_url"' \
    | grep -i 'ubuntu.*amd64\.deb\|amd64.*ubuntu.*\.deb' \
    | head -1 | cut -d'"' -f4)
[[ -z "$_SUN_URL" ]] && _SUN_URL=$(echo "$_SUN_API" \
    | grep '"browser_download_url"' | grep '_amd64\.deb"' \
    | head -1 | cut -d'"' -f4)
if [[ -n "$_SUN_URL" ]]; then
    wget -qO /tmp/sunshine.deb "$_SUN_URL" \
    && apt-get install -y /tmp/sunshine.deb \
    && ok "Sunshine installed  (game streaming server — pair with Moonlight client on any device)" \
    || warn "Sunshine deb install failed — download from https://github.com/LizardByte/Sunshine/releases"
    rm -f /tmp/sunshine.deb
else
    warn "Could not determine Sunshine download URL — install manually from https://github.com/LizardByte/Sunshine/releases"
fi
info "Sunshine web UI: https://localhost:47990  (start with: sunshine)"
info "Moonlight client: https://moonlight-stream.org  (or install on Android/iOS/TV)"

info "Installing Moonlight (game streaming client) via Flatpak..."
if command -v flatpak &>/dev/null; then
    sudo -u "$USER_NAME" flatpak install -y --noninteractive \
        flathub com.moonlight_stream.Moonlight 2>/dev/null \
        && ok "Moonlight installed  (game streaming client — connect to Sunshine or NVIDIA GameStream)" \
        || warn "Moonlight Flatpak install failed — run manually: flatpak install flathub com.moonlight_stream.Moonlight"
else
    warn "Flatpak not available — Moonlight skipped"
fi

# ── Wayland support ───────────────────────────────────────────────────────────
# Kubuntu Plasma 6 runs Wayland by default.
# xwayland: backwards-compat layer so X11 games and Wine/Proton apps run under
#   the Wayland session without needing a native Wayland path.
# xdg-desktop-portal-kde: KDE portal backend — required for screen capture,
#   file pickers, and game overlay APIs (MangoHud, gamescope) under Wayland.
# libdecor-0-plugin-1-cairo: client-side window decorations for SDL2/Wayland;
#   prevents borderless/undecorated windows in some native Linux games.
apt-get install -y \
    xwayland \
    xdg-desktop-portal-kde \
    libdecor-0-plugin-1-cairo \
    2>/dev/null || true
ok "Wayland support: xwayland + xdg-desktop-portal-kde + libdecor installed"
fi  # ─── end: 9/15 ───

hdr "10/15  Networking — Tailscale + ZeroTier"
if (( _SKIP_INFRA || _DOTFILES_ONLY )); then
    info "10/15 skipped  (profile: ${INSTALL_PROFILE})"
else

# Repo check separate from binary check so an OS upgrade that disables tailscale.list
# gets healed even when tailscale is already installed.
if ! command -v tailscale &>/dev/null || [[ ! -f /etc/apt/sources.list.d/tailscale.list ]]; then
    _TS_SUITE="${UBUNTU_CODENAME}"
    # Tailscale only publishes packages for LTS-era Ubuntu. Try the exact current
    # codename first; fall back directly to noble if not published yet.
    if ! curl -fsLm 10 -o /dev/null \
        "https://pkgs.tailscale.com/stable/ubuntu/${_TS_SUITE}/Release" 2>/dev/null; then
        warn "Tailscale has no packages for '${_TS_SUITE}' yet — falling back to noble"
        _TS_SUITE="noble"
    fi
    rm -f /etc/apt/sources.list.d/tailscale.list.disabled 2>/dev/null || true
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${_TS_SUITE}.noarmor.gpg" \
        | tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] \
https://pkgs.tailscale.com/stable/ubuntu ${_TS_SUITE} main" \
        | tee /etc/apt/sources.list.d/tailscale.list > /dev/null
    apt-get update -qq 2>&1 | grep -E '^(E:|W:)' || true
    if ! command -v tailscale &>/dev/null; then
        info "Installing Tailscale..."
        apt-get install -y tailscale \
            && systemctl enable --now tailscaled 2>/dev/null || true \
            && ok "Tailscale installed (suite: ${_TS_SUITE})" \
            || warn "Tailscale install failed"
        info "Activate with: sudo tailscale up"
        info "Options:       sudo tailscale up --advertise-exit-node  (for exit node)"
    else
        ok "Tailscale repo restored (suite: ${_TS_SUITE})"
    fi
else
    ok "Tailscale already installed"
fi

# ZeroTier uses its own install script which manages the repo; remove any stale
# .disabled remnant left by the OS upgrade migration.
rm -f /etc/apt/sources.list.d/zerotier.list.disabled 2>/dev/null || true

if ! command -v zerotier-cli &>/dev/null; then
    info "Installing ZeroTier..."
    if curl -s https://install.zerotier.com | bash; then
        systemctl enable --now zerotier-one 2>/dev/null || true
        ok "ZeroTier installed"
        info "Join network with: sudo zerotier-cli join <network-id>"
    else
        warn "ZeroTier install script failed — install manually: curl -s https://install.zerotier.com | bash"
    fi
else
    ok "ZeroTier already installed"
fi

# Copy the auth token to a user-readable location so infra-connections.py can
# query the ZeroTier REST API without root.  The token is regenerated by the
# daemon only on first install, so this copy stays valid across reboots.
_ZT_TOKEN_SRC=/var/lib/zerotier-one/authtoken.secret
_ZT_TOKEN_DST="${USER_HOME}/.config/zerotier-one/authtoken.secret"
if [[ -f "$_ZT_TOKEN_SRC" ]]; then
    mkdir -p "${USER_HOME}/.config/zerotier-one"
    install -m 600 -o "${USER_NAME}" -g "${USER_NAME}" \
        "$_ZT_TOKEN_SRC" "$_ZT_TOKEN_DST"
    ok "ZeroTier auth token copied → ${_ZT_TOKEN_DST}  (infra-connections can now use REST API)"
else
    warn "ZeroTier auth token not found at ${_ZT_TOKEN_SRC} — daemon may not have started yet; copy manually after joining a network"
fi
unset _ZT_TOKEN_SRC _ZT_TOKEN_DST

apt-get install -y samba-common smbclient cifs-utils gvfs-backends \
    || true
ok "Samba/CIFS client tools installed"
fi  # ─── end: 10/15 ───

hdr "11/15  Virtualisation — virt-manager + QEMU/KVM"
if (( _SKIP_INFRA || _DOTFILES_ONLY )); then
    info "11/15 skipped  (profile: ${INSTALL_PROFILE})"
else

apt-get install -y \
    qemu-system-x86 qemu-utils \
    libvirt-daemon-system libvirt-clients \
    virt-manager \
    ovmf \
    bridge-utils \
    virtinst \
    cpu-checker

systemctl enable --now libvirtd
virsh net-autostart default 2>/dev/null || true
virsh net-start   default 2>/dev/null || true

usermod -aG libvirt "$USER_NAME"
usermod -aG kvm     "$USER_NAME"

ok "virt-manager + QEMU/KVM configured"
warn "Re-login for libvirt/kvm group membership to take effect"
fi  # ─── end: 11/15 ───

hdr "12/15  Gaming environment — shader cache + env vars"
if (( _SKIP_GAMING || _DOTFILES_ONLY )); then
    info "12/15 gaming env skipped  (profile: ${INSTALL_PROFILE})"
else

SHADER_CACHE_ROOT="${USER_HOME}/Shader_CACHE"
MESA_CACHE_DIR="${SHADER_CACHE_ROOT}/MESA_SHADER_CACHE"
GL_CACHE_DIR="${SHADER_CACHE_ROOT}/GL_SHADER_DISK_CACHE"
DXVK_CACHE_DIR="${SHADER_CACHE_ROOT}/DXVK_State_Cache"
ORIGIN_CACHE_DIR="${MESA_CACHE_DIR}/shadercacheOriginSteam"

info "Creating shader cache directories..."
for DIR in \
    "$SHADER_CACHE_ROOT" "$MESA_CACHE_DIR" "$GL_CACHE_DIR" \
    "$DXVK_CACHE_DIR" "$ORIGIN_CACHE_DIR"
do
    if [[ -d "$DIR" ]]; then
        info "exists  : $DIR"
    else
        mkdir -p "$DIR"
        ok "created : $DIR"
    fi
done
chown -R "${USER_NAME}:${USER_NAME}" "$SHADER_CACHE_ROOT"

cp -f /etc/environment /etc/environment.bak 2>/dev/null || touch /etc/environment

set_env_var "CLUTTER_VBLANK"                "none"
set_env_var "vblank_mode"                   "0"

set_env_var "MESA_GLSL_CACHE_ENABLE"        "true"
set_env_var "MESA_GLSL_CACHE_DIR"           "${MESA_CACHE_DIR}"
set_env_var "MESA_SHADER_CACHE_DISABLE"     "false"
set_env_var "MESA_SHADER_CACHE_DIR"         "${MESA_CACHE_DIR}"
set_env_var "MESA_SHADER_CACHE_MAX_SIZE"    "160G"
set_env_var "mesa_glthread"                 "true"

set_env_var "__GL_THREADED_OPTIMIZATIONS"   "1"
set_env_var "__GL_SHADER_DISK_CACHE"        "1"
set_env_var "__GL_SHADER_DISK_CACHE_PATH"   "${GL_CACHE_DIR}"

set_env_var "DXVK_STATE_CACHE_PATH"         "${DXVK_CACHE_DIR}"

# ── Cross-GPU: DXVK async shader compilation ─────────────────────────────────
# DXVK_ASYNC=1: compile shaders in background threads instead of blocking the
# game while it generates pipeline state. Eliminates the hitching/stuttering on
# first execution of a new shader. Safe on AMD/NVIDIA/Intel — no visual glitches
# on DXVK 2.x (the non-deterministic behaviour was fixed in DXVK 2.0).
set_env_var "DXVK_ASYNC" "1"
ok "DXVK_ASYNC=1 set  (async shader compilation — eliminates pipeline stutter)"

# ── Cross-GPU: vkd3d-proton DXR / DirectX Raytracing ────────────────────────
# VKD3D_CONFIG=dxr11,dxr: enable both the older DXR11 path (used by most RTX
# titles via DX11 RT) and the full DXR12 path. Safe to set globally — vkd3d
# skips DXR silently if the hardware / driver does not support VK_KHR_ray_query.
# Hardware that benefits: AMD RDNA2+, NVIDIA Turing+, Intel Arc (Xe-HPG+).
set_env_var "VKD3D_CONFIG" "dxr11,dxr"
ok "VKD3D_CONFIG=dxr11,dxr set  (DirectX Raytracing via vkd3d-proton on RDNA2+/Turing+/Arc)"

# ── Wayland gaming env vars ───────────────────────────────────────────────────
# PROTON_ENABLE_WAYLAND=1: opt-in to Proton 9+'s native Wayland rendering path
#   (gamescope-based, bypasses XWayland entirely for supported titles).
#   Falls back to XWayland silently for games that don't support it yet.
set_env_var "PROTON_ENABLE_WAYLAND" "1"
ok "PROTON_ENABLE_WAYLAND=1 set  (Proton 9+ native Wayland path — XWayland fallback for unsupported titles)"


ok "Shader cache directories and gaming env vars configured"
info "Recommended Steam launch option: mangohud gamemoderun %command%"
info "  (use the mangohud wrapper — MANGOHUD=1 alone is unreliable with Steam)"
info "For CP2077/Proton-GE: MANGOHUD=1 gamemoderun %command% --launcher-skip"
fi  # ─── end: 12/15 gaming env ───

if (( _DOTFILES_ONLY )); then
    info "12/15 perf hardening skipped  (profile: ${INSTALL_PROFILE})"
else

# ── System-wide performance hardening ────────────────────────────────────────
info "Applying kernel + system performance tuning..."

# ── sysctl: kernel tunables ───────────────────────────────────────────────────
cat > /etc/sysctl.d/99-kubuntu-perf.conf << 'SYSCTL_EOF'
# ── VM / memory ──────────────────────────────────────────────────────────────
# Prefer RAM over swap aggressively — 10 keeps the kernel quick to reclaim cold
# pages while leaving headroom for the cache to breathe under memory pressure.
# Lower values (5) suit pure desktops; 10 is the sweet spot for gaming + dev.
vm.swappiness = 10
# How much RAM can hold dirty pages before the kernel MUST write them out.
# 3% is tight — reduces write latency spikes; zram absorbs RAM pressure first.
vm.dirty_ratio = 3
# Start background writeback at 2% — triggers flusher very early so the
# foreground never stalls at dirty_ratio.
vm.dirty_background_ratio = 2
# Time (ms) a dirty page can sit before being flushed (3 s default → 1.5 s)
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 500
# Allow more memory-mapped files (needed by JVMs, Electron apps, databases)
vm.max_map_count = 2147483642
# VFS dentry/inode cache pressure — default 100 (aggressively reclaimed).
# 50 keeps more directory/file metadata in RAM, halving the number of times
# the kernel re-reads directory structures from disk — significant on HDD.
vm.vfs_cache_pressure = 50
# How many pages to read ahead per swap-out (default=3 → 8 pages per seek).
# 4 → 16 pages batches HDD seeks, trading slightly more swap RAM for fewer
# head movements. Only relevant when swap is actually touched.
vm.page-cluster = 4
# Disable proactive memory compaction — saves background CPU cycles on
# workloads that don't rely on huge pages (THP). Does nothing visible on
# desktop; just stops periodic compaction kthread from waking.
vm.compaction_proactiveness = 0
# Disable NMI watchdog — frees one hardware perf counter and stops the NMI
# interrupt from firing every second (measurable on low-spec CPUs).
kernel.nmi_watchdog = 0
# Proactive reclaim — kswapd wakes before the zone watermark is crossed,
# preventing allocation-stall spikes. 125 = 1.25× gap (default: 10 = hairline).
vm.watermark_scale_factor = 125
# Disable kswapd burst mode — after a reclaim event kswapd would normally
# reclaim a large burst to stay ahead; disabling prevents sudden swap storms.
vm.watermark_boost_factor = 0
# Minimum free memory floor — kernel always reserves this many kB for interrupt
# handlers and atomic allocations (GFP_ATOMIC). 65536 kB (64 MB) prevents the
# allocator from ever reaching a state where even interrupt-context allocs fail,
# which manifests as a hard system hang. Default is ~1600 kB (dangerously low).
vm.min_free_kbytes = 65536
# VM stats update interval: once per 10 s not 1 s — reduces inter-processor
# interrupts (IPIs) on multi-core systems. No visible user-space impact.
vm.stat_interval = 10

# ── Scheduler ────────────────────────────────────────────────────────────────
# Reduce scheduler migration latency — keeps threads on their current CPU longer
kernel.sched_migration_cost_ns = 5000000
# Disable autogroup scheduling — autogroup puts unrelated background processes
# in their own scheduler group which can deprive game/foreground threads of CPU
# time under load. 0 = all tasks compete equally in CFS — better for gaming.
kernel.sched_autogroup_enabled = 0
# Tighter scheduler timeslice (default 6 ms → 4 ms) — reduces input latency
# and UI stutter under CPU load. Works with preempt=full in GRUB.
kernel.sched_latency_ns = 4000000
kernel.sched_min_granularity_ns = 500000
# A woken task must have been sleeping at least 1 ms before it can preempt
# the currently running task — prevents thrash on burst workloads.
kernel.sched_wakeup_granularity_ns = 1000000

# ── Network ──────────────────────────────────────────────────────────────────
# Large socket buffers — 256 MB ceiling lets a fast connection (1 Gbps+) fill
# its TCP window without the kernel dropping bytes. Steam, SCP, VPN tunnels,
# and RDP all benefit. The kernel auto-tunes per-socket from the default up;
# the max is only reached under sustained high-BDP flows.
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 268435456
net.ipv4.tcp_wmem = 4096 1048576 268435456
# BBR congestion control — lower latency, higher throughput over WAN/VPN
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
# Faster TCP connection reuse
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
# Harden against SYN flood without heavy CPU cost
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
# TCP send buffer anti-bloat — limits unsent data queued per socket to 16 kB.
# Prevents kernel-side bufferbloat on LAN/loopback (Docker, Redis, Postgres).
net.ipv4.tcp_notsent_lowat = 16384
# Don't reset TCP slow-start after idle — persistent connections (SSH, Redis,
# DB pools) keep their congestion window across quiet periods.
net.ipv4.tcp_slow_start_after_idle = 0
# MTU probing — recovers from PMTUD blackholes in VPN / PPPoE paths.
net.ipv4.tcp_mtu_probing = 1
# RFC 1337 TIME-WAIT fix — drops RST packets targeting TIME_WAIT sockets,
# preventing connection reuse attacks.
net.ipv4.tcp_rfc1337 = 1
# Larger TIME_WAIT table — prevents overflow under Docker / microservice load.
net.ipv4.tcp_max_tw_buckets = 2000000
# Wider ephemeral port range — prevents exhaustion with Docker + services.
net.ipv4.ip_local_port_range = 1024 65535
# Larger listen() backlog for local servers, Docker, Redis, Postgres.
net.core.somaxconn = 8192
# TCP keepalive — detect dead connections in ~2 min not 2+ hours.
# Reclaims sockets left by VPN drops, container restarts, suspended VMs.
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
# Explicit Congestion Notification — signals congested routers to slow down
# before they drop packets. ECN=1 enables it for outbound connections and
# accepts it when the remote peer offers. Works synergistically with BBR:
# instead of detecting congestion via loss, the stack reacts to CE marks.
# Modern ISPs and home routers support ECN; the fallback is automatic.
net.ipv4.tcp_ecn = 1
# Disable TCP autocorking — the kernel normally batches small writes to fill a
# full segment before sending. Disabling sends each write immediately, cutting
# per-packet latency for gaming, SSH keystrokes, and VoIP at negligible cost.
net.ipv4.tcp_autocorking = 0
# UDP minimum socket buffers — gaming traffic is sparse UDP; raising the floor
# to 8 kB ensures the kernel never shrinks buffers below what a single game
# packet needs. The kernel auto-tunes up from here; this prevents pathological
# under-allocation on lightly-loaded sockets. Default is 4096.
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# ── File descriptors ─────────────────────────────────────────────────────────
# libvirt, Docker, and IDEs easily exhaust the default 8192 limit
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
# Larger pipe buffer — ffmpeg, cargo, xargs pipelines need more headroom.
# Default 1 MB; 4 MB prevents I/O stalls when producer briefly outpaces consumer.
fs.pipe-max-size = 4194304

# ── TCP Fast Open + NIC queue ─────────────────────────────────────────────────
# TCP Fast Open (TFO): client + server — eliminates one RTT on repeat connections
# to the same host (HTTPS reload, SSH reconnect, VS Code remote, RDP sessions).
net.ipv4.tcp_fastopen = 3
# Larger NIC receive queue: prevents packet drops during GbE/WiFi burst I/O.
# Default is 1000; 16384 absorbs spikes from Docker, VMs, or SCP without drops.
net.core.netdev_max_backlog = 16384
# More packets processed per softirq round — prevents NIC RX drops under burst.
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000
# Receive Flow Steering (RFS) socket-flow table — kernel maps each active flow
# to the CPU running its socket so incoming packets land on the right core,
# avoiding cross-core wakeups and L3 cache misses. 32768 covers typical desktop
# workloads (gaming + browser + containers). Per-NIC queue CPU masks are set at
# boot via the 70-network-rps udev rule (applied by kubuntu-set-rps.sh).
net.core.rps_sock_flow_entries = 32768

# ── NUMA / zone reclaim ────────────────────────────────────────────────────────
# On desktop/single-socket machines zone_reclaim_mode=0 is always correct:
# the kernel should allocate from any available zone rather than reclaiming.
vm.zone_reclaim_mode = 0
# Disable background NUMA page migration — the numa_balancing kthread wakes
# periodically to move pages between NUMA nodes, burning CPU even on machines
# with a single socket (UMA) where the "balancing" achieves nothing.
kernel.numa_balancing = 0

# ── Core dumps: disable ────────────────────────────────────────────────────────
# A crashing process can write gigabytes to disk — devastating on HDD.
# Route to /bin/false to silently discard; production servers use a coredump
# collector, but a workstation gains nothing from crash dumps.
kernel.core_pattern = |/bin/false
kernel.core_uses_pid = 0

# ── OOM + task management ─────────────────────────────────────────────────────
# Kill the OOM-triggering task directly rather than hunting the "largest" victim.
# earlyoom intercepts most pressure first; this governs kernel OOM fallback.
vm.oom_kill_allocating_task = 1
# Higher PID limit — Docker + systemd spawn many short-lived containers/processes.
kernel.pid_max = 4194304
# Hung task watchdog — 300 s (5 min). Long enough to avoid false positives from
# heavy HDD I/O (large copies, backups can stall D-state for 30–60 s) while still
# reporting a genuinely deadlocked process in dmesg. Default kernel value is 120 s.
kernel.hung_task_timeout_secs = 300
# Disable per-task I/O delay accounting — used by iotop/blktrace but adds
# per-task overhead on every context switch. Re-enable with sysctl if needed.
kernel.task_delayacct = 0

# ── Developer / profiling ─────────────────────────────────────────────────────
# perf_event_paranoid=1: allow non-root users to use perf, gdb hardware counters,
# flamegraphs (perf record), VS Code Perf extension, and eBPF tracing tools.
# Default is 2 (read kernel perf only as root); 1 unlocks per-process profiling.
# Set to 0 only on dedicated dev VMs where all users are trusted.
kernel.perf_event_paranoid = 1
# Allow non-root to read kallsyms (function addresses) needed for flamegraphs
kernel.kptr_restrict = 1
SYSCTL_EOF
sysctl --system -q 2>/dev/null || sysctl -p /etc/sysctl.d/99-kubuntu-perf.conf 2>/dev/null || true
ok "sysctl tunables applied  (/etc/sysctl.d/99-kubuntu-perf.conf)"

# ── RPS/RFS: steer NIC softirq to the socket's owning CPU core ───────────────
# rps_sock_flow_entries (sysctl above) reserves the flow table. This udev rule
# applies a per-queue CPU bitmask so every receive queue fans out across all
# cores, eliminating the single-core softirq bottleneck on high-traffic systems.
cat > /usr/local/sbin/kubuntu-set-rps.sh << 'RPS_SCRIPT_EOF'
#!/bin/bash
iface="${1:-}"
[ -z "$iface" ] && exit 0
mask=$(python3 -c "import os; n=os.cpu_count() or 1; print(f'{(1<<n)-1:x}')" 2>/dev/null \
    || printf '%x' $(( (1 << $(nproc)) - 1 )) 2>/dev/null \
    || echo "ffffffff")
for f in /sys/class/net/"$iface"/queues/rx-*/rps_cpus; do
    [ -f "$f" ] && echo "$mask" > "$f" 2>/dev/null || true
done
RPS_SCRIPT_EOF
chmod 755 /usr/local/sbin/kubuntu-set-rps.sh

cat > /usr/local/sbin/kubuntu-set-coalesce.sh << 'COALESCE_SCRIPT_EOF'
#!/bin/bash
# Disable adaptive IRQ coalescing — adaptive mode batches packets for 100-250 μs
# before firing an interrupt (good for throughput, bad for latency). Turning it
# off and setting rx/tx-usecs=0 fires the IRQ immediately on packet arrival,
# cutting per-packet latency by 20-50 μs. NICs that don't support the value
# will silently reject it; the 2>/dev/null suppresses those errors.
iface="${1:-}"
[ -z "$iface" ] && exit 0
ethtool -c "$iface" &>/dev/null 2>&1 || exit 0
ethtool -C "$iface" adaptive-rx off adaptive-tx off rx-usecs 0 tx-usecs 0 2>/dev/null || true
COALESCE_SCRIPT_EOF
chmod 755 /usr/local/sbin/kubuntu-set-coalesce.sh

cat > /etc/udev/rules.d/70-network-rps.rules << 'UDEV_RPS_EOF'
# Enable Receive Packet Steering — spreads softirq across all CPU cores,
# reducing per-core saturation and L3 cache misses on socket-bound workloads.
ACTION=="add", SUBSYSTEM=="net", KERNEL!="lo", RUN+="/usr/local/sbin/kubuntu-set-rps.sh %k"
# Disable adaptive IRQ coalescing for lower per-packet latency (~20-50 μs gain).
# Fires IRQ immediately on packet arrival instead of batching 100-250 μs worth.
ACTION=="add", SUBSYSTEM=="net", KERNEL!="lo", RUN+="/usr/local/sbin/kubuntu-set-coalesce.sh %k"
UDEV_RPS_EOF
udevadm control --reload-rules 2>/dev/null || true
# Apply immediately to interfaces already up
for _net_iface in $(ls /sys/class/net/ | grep -v '^lo$'); do
    /usr/local/sbin/kubuntu-set-rps.sh "$_net_iface" 2>/dev/null || true
    /usr/local/sbin/kubuntu-set-coalesce.sh "$_net_iface" 2>/dev/null || true
done
ok "RPS/RFS: NIC softirq spread across all CPU cores  (/etc/udev/rules.d/70-network-rps.rules)"
ok "ethtool: adaptive coalescing disabled, rx/tx-usecs=0  (20-50 μs latency gain)"

# ── sudo: show * feedback while typing password ───────────────────────────────
# By default sudo shows nothing when you type — pwfeedback echoes a * per key.
# Drop-in file so /etc/sudoers is never edited directly (visudo-safe approach).
cat > /etc/sudoers.d/pwfeedback << 'SUDOERS_EOF'
Defaults pwfeedback
SUDOERS_EOF
chmod 0440 /etc/sudoers.d/pwfeedback
ok "sudo: pwfeedback enabled  (/etc/sudoers.d/pwfeedback)"

# ── Transparent Huge Pages → always (enabled) + defer+madvise (defrag) ───────
# "always": every allocation is eligible for 2 MB THP pages — benefits gaming
# (DXVK/VKD3D shader/buffer allocs), VMs, and JVMs which all use large contiguous
# regions. Cost: slightly higher per-allocation memory usage.
# "defer+madvise": defrag only for regions that opt in (MADV_HUGEPAGE) and defers
# the rest — avoids the latency stall of synchronous THP compaction.
# Apply immediately + via tmpfiles.d so it survives every reboot.
echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag  2>/dev/null || true
cat > /etc/tmpfiles.d/99-thp-gaming.conf << 'THP_EOF'
# Transparent Huge Pages: always (gaming/VM) + defer+madvise (defrag) — kubuntu-setup
# Overrides the kernel default on every boot before any service starts.
w /sys/kernel/mm/transparent_hugepage/enabled - - - - always
w /sys/kernel/mm/transparent_hugepage/defrag  - - - - defer+madvise
THP_EOF
ok "THP: always (enabled) + defer+madvise (defrag)  (better for gaming/VMs — no alloc stalls)"

# ── Disable systemd-oomd — conflicts with earlyoom ───────────────────────────
# Ubuntu 22.04+ ships systemd-oomd as the default OOM daemon. It uses a cgroup
# memory-pressure heuristic that fires independently of earlyoom, causing
# double-kill races. earlyoom's direct RSS measurement is more desktop-friendly;
# disable systemd-oomd entirely to let earlyoom operate without interference.
systemctl disable --now systemd-oomd 2>/dev/null || true
ok "systemd-oomd disabled  (earlyoom handles all OOM — no cgroup kill conflict)"

# ── systemd service stop/start timeouts ──────────────────────────────────────
# Default stop timeout is 90 s — a single hung service stalls every shutdown
# for 1.5 minutes. 10 s is aggressive but correct for a workstation: if a
# service cannot stop cleanly in 10 s it will be SIGKILL'd.
# DefaultTimeoutStartSec=30 s: services that never finish starting (broken
# configs, missing deps) fail fast instead of blocking boot for 90 s.
# DefaultDeviceTimeoutSec is intentionally NOT overridden here — the systemd
# default (infinity) is correct for block devices; a 10s override caused
# emergency mode on boot when NTFS/HDD partitions took >10s to appear.
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/99-kubuntu-timeouts.conf << 'SDTMO_EOF'
[Manager]
DefaultTimeoutStartSec=30s
DefaultTimeoutStopSec=10s
# fsync/esync ulimits — Wine/Proton shader storms open thousands of file handles;
# without this the NOFILE limit causes stutters or hard failures.
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
SDTMO_EOF
# user.conf.d — same limits for the user-level systemd manager (Steam, launchers)
mkdir -p /etc/systemd/user.conf.d
cat > /etc/systemd/user.conf.d/99-kubuntu-limits.conf << 'USERLIM_EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
USERLIM_EOF
systemctl daemon-reload 2>/dev/null || true
ok "systemd: DefaultTimeoutStopSec=10s  StartSec=30s  DeviceTimeout=10s  (fast shutdown)"
ok "systemd: DefaultLimitNOFILE=1048576 (system + user)  — fsync/esync ulimits active"

# ── Open file + realtime limits ───────────────────────────────────────────────
# Allow the user to open many files and use mild realtime scheduling
# (needed for: libvirt/KVM, Docker, heavy IDEs, low-latency audio, VMs)
grep -q "^${USER_NAME}.*nofile" /etc/security/limits.conf 2>/dev/null \
    || cat >> /etc/security/limits.conf << LIMITS_EOF

# Added by kubuntu-setup — workstation performance limits for ${USER_NAME}
${USER_NAME}  soft  nofile   524288
${USER_NAME}  hard  nofile   1048576
${USER_NAME}  soft  nproc    65536
${USER_NAME}  hard  nproc    65536
${USER_NAME}  soft  memlock  unlimited
${USER_NAME}  hard  memlock  unlimited
${USER_NAME}  soft  rtprio   95
${USER_NAME}  hard  rtprio   95
LIMITS_EOF
ok "Security limits raised  (nofile=1M, nproc=64k, rtprio=95, memlock=unlimited)"

# ── CPU governor — schedutil (burst-on-demand, scales with actual load) ──────
apt-get install -y cpufrequtils irqbalance 2>/dev/null || true
# cpufrequtils ships a legacy SysV init script that triggers "deprecated" warnings
# in systemd-sysv-generator on every boot. Our cpu-schedutil-governor.service
# handles governor setup, so mask the SysV wrappers to silence the warnings.
systemctl mask cpufrequtils loadcpufreq 2>/dev/null || true
ok "cpufrequtils SysV init scripts masked  (our systemd unit handles governor)"
cat > /etc/systemd/system/cpu-schedutil-governor.service << 'CPUGOV_EOF'
[Unit]
Description=Set CPU governor to schedutil on all cores
After=sysinit.target
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
# schedutil: kernel scheduler-driven DVFS — fast ramp-up, efficient at idle
# Falls back to ondemand on CPUs without schedutil (rare on modern kernels)
ExecStart=/bin/sh -c 'for cpu in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do [ -f "$cpu" ] && (echo schedutil > "$cpu" 2>/dev/null || echo ondemand > "$cpu" 2>/dev/null || true); done'

[Install]
WantedBy=multi-user.target
CPUGOV_EOF
systemctl daemon-reload
systemctl enable --now cpu-schedutil-governor.service 2>/dev/null || true
ok "CPU governor: schedutil on all cores (burst-on-demand, scales with load)"

# ── IRQ balancing ─────────────────────────────────────────────────────────────
systemctl enable --now irqbalance 2>/dev/null || true
ok "irqbalance enabled  (hardware IRQs distributed across all CPU cores)"

# ── NVMe SSD trim (prevent write amplification, maintain peak IOPS) ───────────
systemctl enable --now fstrim.timer 2>/dev/null || true
ok "fstrim.timer enabled  (weekly TRIM keeps NVMe at peak performance)"

# ── ext4 root: noatime + commit=60 in fstab ──────────────────────────────────
# noatime is already active via GRUB rootflags= but making it explicit in fstab
# ensures it survives any future GRUB regeneration that drops rootflags.
# commit=60 delays ext4 journal commits from the 5 s default to 60 s — reduces
# journal writeback frequency by 12×, which matters even on NVMe because journal
# commits are synchronous and hold a lock that blocks all writes momentarily.
# Safe on NVMe: crash recovery replays at most 60 s of metadata, taking < 1 s.
_EXT4_ROOT_UPDATED=0
if grep -qE '^\S+\s+/\s+ext4\s+' /etc/fstab 2>/dev/null; then
    if ! grep -qE '^\S+\s+/\s+ext4\s+[^#]*commit=' /etc/fstab 2>/dev/null; then
        sed -i -E '/^\S+\s+\/\s+ext4\s+/ s/\bdefaults\b/defaults,noatime,commit=60/' /etc/fstab
        mount -o remount,commit=60 / 2>/dev/null || true
        _EXT4_ROOT_UPDATED=1
        ok "ext4 root fstab: noatime,commit=60 added  (12× fewer journal commits)"
    else
        ok "ext4 root fstab: commit= already present — skipped"
    fi
fi

# ── Intel WiFi power management ───────────────────────────────────────────────
# iwlwifi defaults to aggressive power save which causes latency spikes on
# SSH sessions, VPN tunnels, and RDP. Disable for a work machine.
if modinfo iwlwifi &>/dev/null 2>&1; then
    cat > /etc/modprobe.d/iwlwifi-perf.conf << 'WIFI_EOF'
# Disable iwlwifi power saving — eliminates latency spikes on SSH/VPN/RDP
options iwlwifi power_save=0
WIFI_EOF
    update-initramfs -u -k all 2>/dev/null || true
    ok "iwlwifi: power_save=0  (no latency spikes on Intel WiFi)"
fi

# ── Swap sizing: 4 GB zram + 2 GB swapfile = 6 GB total ──────────────────────
#
# Philosophy for any workstation (HDD or SSD):
#   - zram = min(RAM * 25%, 4096 MB)  — compressed in RAM, ~3:1 ratio, zero disk writes
#   - swapfile = 2 GB fixed           — last resort before OOM, minimal disk wear
#   - Total ≤ 6 GB regardless of RAM size (matches Fedora/RHEL 9+ workstation defaults)
#   - With swappiness=5 the swapfile is almost never touched; it exists for safety only
#   - On HDD this is critical: zram absorbs all swap pressure in RAM; the swapfile
#     is only touched in genuine OOM conditions (earlyoom kills before that point)
#
_RAM_MB=$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)
_ZRAM_MB=$(( _RAM_MB / 4 ))
(( _ZRAM_MB > 4096 )) && _ZRAM_MB=4096
(( _ZRAM_MB < 512  )) && _ZRAM_MB=512    # floor for very low-RAM machines
_SWAPFILE_MB=2048
# zram PERCENT relative to actual RAM (for /etc/default/zramswap)
_ZRAM_PERCENT=$(( _ZRAM_MB * 100 / _RAM_MB ))
(( _ZRAM_PERCENT < 1 )) && _ZRAM_PERCENT=1

info "Swap sizing: RAM=${_RAM_MB} MB  →  zram=${_ZRAM_MB} MB (in-RAM)  +  swapfile=${_SWAPFILE_MB} MB (NVMe, last resort)"

# ── zram (compressed in-RAM swap, priority 100) ───────────────────────────────
if ! dpkg -l zram-tools &>/dev/null; then
    apt-get install -y zram-tools 2>/dev/null || true
fi
if dpkg -l zram-tools &>/dev/null; then
    cat > /etc/default/zramswap << ZRAM_EOF
# zram-tools configuration — kubuntu-setup
# Dynamically calculated: ${_ZRAM_MB} MB  (${_ZRAM_PERCENT}% of ${_RAM_MB} MB RAM)
PERCENT=${_ZRAM_PERCENT}
# zstd: best ratio/speed tradeoff; lz4 is faster but lower ratio
ALGO=zstd
# Priority 100 — always prefer zram over the on-disk swapfile
PRIORITY=100
ZRAM_EOF
    systemctl enable --now zramswap 2>/dev/null \
        && ok "zram enabled  (${_ZRAM_MB} MB, zstd, priority 100 — zero disk writes)" \
        || warn "zramswap service not found — reboot will activate zram-tools"
fi

# ── swapfile (NVMe disk swap, priority 10 — last resort before OOM) ───────────
# Sized to half the budget so disk is only touched when zram is fully exhausted.
# fallocate allocates blocks without touching every byte → minimal write overhead.
# swappiness=5 (set in sysctl) means the kernel almost never reaches this.
_SWAPFILE=/swapfile
if [[ -f "$_SWAPFILE" ]]; then
    _EXISTING_MB=$(( $(stat -c%s "$_SWAPFILE" 2>/dev/null || echo 0) / 1048576 ))
    if (( _EXISTING_MB == _SWAPFILE_MB )); then
        ok "swapfile already exists at correct size  (${_SWAPFILE_MB} MB) — skipping"
    else
        warn "swapfile exists but wrong size (${_EXISTING_MB} MB vs ${_SWAPFILE_MB} MB) — replacing"
        swapoff "$_SWAPFILE" 2>/dev/null || true
        rm -f "$_SWAPFILE"
    fi
fi
if [[ ! -f "$_SWAPFILE" ]]; then
    fallocate -l "${_SWAPFILE_MB}M" "$_SWAPFILE" 2>/dev/null \
        || dd if=/dev/zero of="$_SWAPFILE" bs=1M count="$_SWAPFILE_MB" status=none
    chmod 600 "$_SWAPFILE"
    mkswap "$_SWAPFILE" -L kubuntu-swap >/dev/null
    ok "swapfile created  (${_SWAPFILE_MB} MB at ${_SWAPFILE})"
fi
# Activate now and persist in fstab
swapon --priority 10 "$_SWAPFILE" 2>/dev/null || true
grep -q "$_SWAPFILE" /etc/fstab 2>/dev/null \
    || echo "${_SWAPFILE}  none  swap  sw,pri=10,nofail  0  0" >> /etc/fstab
ok "swapfile active  (priority 10 — only used when zram is exhausted)"
ok "Swap summary: ${_ZRAM_MB} MB zram (in-RAM, pri=100) + ${_SWAPFILE_MB} MB swapfile (disk, pri=10)"

# ── Dynamic swappiness: scale to installed RAM ────────────────────────────────
# The static conf above sets vm.swappiness=10 as a safe default.
# Machines with more RAM have less reason to swap, so we override it here with
# a tighter value: 32 GB+ barely needs to swap at all; <8 GB keeps 10.
# Written to 99-kubuntu-perf-ram.conf which sorts after 99-kubuntu-perf.conf
# so it wins on sysctl --system load order (lexicographic).
if   (( _RAM_MB >= 32768 )); then _SWAPPINESS=1   # 32 GB+ : almost never swap
elif (( _RAM_MB >= 16384 )); then _SWAPPINESS=3   # 16 GB+ : very low pressure
elif (( _RAM_MB >=  8192 )); then _SWAPPINESS=7   # 8 GB+  : light pressure
else                               _SWAPPINESS=10  # <8 GB  : keep static default
fi
printf '# Dynamic swappiness — computed at install time (%d MB RAM installed)\n# Re-run setup-kubuntu.sh to recalculate.  Lower = prefer RAM over swap.\nvm.swappiness = %d\n' \
    "${_RAM_MB}" "${_SWAPPINESS}" > /etc/sysctl.d/99-kubuntu-perf-ram.conf
sysctl -w vm.swappiness=${_SWAPPINESS} 2>/dev/null || true
ok "vm.swappiness=${_SWAPPINESS}  (${_RAM_MB} MB RAM — overrides static default of 10)"

# ── preload — adaptive application prefetch ───────────────────────────────────
# Learns which apps/libs you start frequently and reads them into the page
# cache in the background, making application launch noticeably faster
if ! dpkg -l preload &>/dev/null; then
    apt-get install -y preload 2>/dev/null || true
fi
if dpkg -l preload &>/dev/null; then
    # preload ships only a legacy SysV init script — provide a native systemd unit
    # so systemd-sysv-generator does NOT generate a deprecated SysV shim at boot.
    # Always overwrite — /etc/systemd/system/ takes precedence over any distro unit
    # and ensures re-runs always apply the correct Type= and options.
    cat > /etc/systemd/system/preload.service << 'PRELOAD_SVC_EOF'
[Unit]
Description=Preload — adaptive application prefetch daemon
Documentation=man:preload(8)
After=local-fs.target
ConditionPathExists=/usr/sbin/preload

[Service]
Type=simple
ExecStart=/usr/sbin/preload -f /var/lib/preload/preload.state
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
PRELOAD_SVC_EOF
    systemctl daemon-reload
    systemctl enable --now preload 2>/dev/null || true
    ok "preload enabled  (adaptive application prefetch — native systemd unit)"
fi

# ── NVMe poll queues: enable io_poll completion polling ──────────────────────
# io_poll requires dedicated poll queues allocated at driver load time.
# poll_queues=4 creates 4 polling queues per controller (one per 4 cores on 8C).
# The udev rule sets io_poll=1 per namespace; this is the prerequisite.
# Takes effect on next reboot (module reloads when root is on NVMe = unsafe live).
cat > /etc/modprobe.d/nvme-poll.conf << 'NVME_POLL_EOF'
# Dedicated NVMe poll queues — prerequisite for io_poll=1 per namespace
options nvme poll_queues=4
NVME_POLL_EOF
update-initramfs -u -k all 2>/dev/null || true
ok "nvme poll_queues=4 configured  (io_poll=1 active after next reboot)"

# ── I/O scheduler — BFQ for HDD, mq-deadline for SATA SSD, none for NVMe ────
# BFQ (Budget Fair Queueing) is the biggest single win for HDD performance:
#   • Minimises seek distance by sorting and batching requests
#   • Provides fairness between processes — desktop stays responsive during
#     large background I/O (apt upgrade, Docker pull, backup)
#   • read_ahead_kb=2048: read 2 MB ahead on sequential access — fills the
#     HDD platter-to-cache transfer in one revolution instead of many seeks
#   • nr_requests=256: larger request queue lets BFQ reorder more aggressively
# Rules fire on every block device add/change (survives hot-plug, reboots).
cat > /etc/udev/rules.d/60-io-scheduler.rules << 'IOSCHED_EOF'
# ── HDD (rotational=1) ── BFQ + 2 MB readahead ───────────────────────────────
ACTION=="add|change", KERNEL=="sd[a-z]|sd[a-z][a-z]", ATTR{queue/rotational}=="1", \
    ATTR{queue/scheduler}="bfq", \
    ATTR{queue/read_ahead_kb}="2048", \
    ATTR{queue/nr_requests}="256", \
    ATTR{queue/rq_affinity}="1"
# ── SATA SSD (rotational=0, not NVMe) ── mq-deadline + 128 KB readahead ──────
ACTION=="add|change", KERNEL=="sd[a-z]|sd[a-z][a-z]", ATTR{queue/rotational}=="0", \
    ATTR{queue/scheduler}="mq-deadline", \
    ATTR{queue/read_ahead_kb}="128"
# ── NVMe ── no scheduler + polling + no write-back throttle ──────────────────
# scheduler=none: hardware queue handles ordering — no kernel reordering overhead
# io_poll=1: hybrid polling — CPU polls for completions after submit instead of
#   waiting for an interrupt, cutting completion latency by 30-60% on fast NVMe
# wbt_lat_usec=0: disable write-back throttling — WBT caps background writes to
#   protect read latency; on NVMe with deep HW queues it only adds overhead
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]|nvme[0-9][0-9]n[0-9]", \
    ATTR{queue/scheduler}="none", \
    ATTR{queue/read_ahead_kb}="64", \
    ATTR{queue/io_poll}="1", \
    ATTR{queue/wbt_lat_usec}="0"
IOSCHED_EOF
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --type=devices --action=change 2>/dev/null || true
ok "I/O scheduler: BFQ (HDD) / mq-deadline (SATA SSD) / none+io_poll+wbt=off (NVMe)  + readahead tuned per type"

# ── journald: size cap + compression — reduces ongoing HDD writes ─────────────
# By default journald is unbounded and writes every log line directly to disk.
# These limits cap the persistent journal at 256 MB total, always keep 256 MB
# free on the partition, compress entries (saves ~60% space/IOPS), and
# rate-limit log storms that would otherwise saturate HDD write bandwidth.
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-kubuntu-perf.conf << 'JRNL_EOF'
[Journal]
# Compress journal entries with zstd — saves ~60% disk space and IOPS
Compress=yes
# Cap persistent on-disk journal to 256 MB
SystemMaxUse=256M
# Always leave at least 256 MB free on the journal's filesystem
SystemKeepFree=256M
# Cap in-memory (volatile) journal to 64 MB
RuntimeMaxUse=64M
# Rate-limit per-service: max 1000 messages per 30 s window
RateLimitIntervalSec=30s
RateLimitBurst=1000
JRNL_EOF
systemctl kill --kill-who=main --signal=SIGUSR2 systemd-journald 2>/dev/null || true
ok "journald: compressed, capped at 256 MB, rate-limited  (fewer HDD writes)"

# ── /tmp on tmpfs — keep temp file churn off the HDD ─────────────────────────
# systemd ships a tmp.mount unit that mounts /tmp as tmpfs (in RAM).
# Ubuntu does NOT enable it by default. Enabling it means all temp file I/O
# (compilers, package managers, browsers) happens entirely in RAM with zero
# HDD seeks. Size is capped at 50% of RAM by default (overridden below to
# min(RAM/4, 2 GB) so we don't crowd out other RAM users on low-memory systems).
_TMPFS_MB=$(( _RAM_MB / 4 ))
(( _TMPFS_MB > 2048 )) && _TMPFS_MB=2048
(( _TMPFS_MB < 256  )) && _TMPFS_MB=256
mkdir -p /etc/systemd/system/tmp.mount.d
cat > /etc/systemd/system/tmp.mount.d/kubuntu-size.conf << TMPCFG_EOF
[Mount]
Options=mode=1777,strictatime,nosuid,nodev,size=${_TMPFS_MB}m
TMPCFG_EOF
systemctl enable tmp.mount 2>/dev/null || true
systemctl start  tmp.mount 2>/dev/null || true
ok "/tmp on tmpfs  (${_TMPFS_MB} MB in RAM — compiler/browser temp I/O never hits HDD)"

# ── earlyoom — kill memory hogs before kernel OOM thrash ─────────────────────
# The kernel OOM killer fires AFTER the system has been thrashing swap for
# minutes (catastrophic — full desktop freeze). earlyoom checks every 5 s and
# kills the biggest memory consumer the moment free RAM drops below 5%,
# reacting within seconds instead of waiting for the kernel OOM deadlock.
if ! dpkg -l earlyoom &>/dev/null; then
    apt-get install -y earlyoom 2>/dev/null || true
fi
if dpkg -l earlyoom &>/dev/null; then
    cat > /etc/default/earlyoom << 'EOOM_EOF'
# earlyoom — kubuntu-setup
# Kill at 5% free RAM or 5% free swap, check every 60 s, send desktop notification
# --prefer: target browser/Electron first (biggest consumers)
# --avoid:  never kill sshd, sudo, or systemd
EARLYOOM_ARGS="-r 5 -m 5 -s 5 --prefer '(chromium|chrome|firefox|code|electron)' --avoid '(sshd|sudo|systemd)' -n"
EOOM_EOF
    systemctl enable --now earlyoom 2>/dev/null || true
    ok "earlyoom enabled  (kills at 5% free RAM, checks every 5 s — prevents OOM freeze within seconds)"
fi

# ── /etc/profile.d/kubuntu-mem.sh — consistent RAM reporting function ─────────
# Linux has two conflicting "used RAM" numbers that confuse every monitoring tool:
#
#   htop  → green bar = app memory only (MemTotal - MemFree - Buffers - Cached)
#            but the displayed number also includes buffers+cache in the total
#   KSysGuard / KDE System Monitor → "Used" includes page cache entirely
#
# The authoritative metric is MemAvailable (kernel since 3.14): the amount of
# memory available to start new applications WITHOUT swapping. It counts free RAM
# PLUS reclaimable page cache. The kernel drops page cache instantly when an app
# needs the RAM — cache is never "stuck"; it is free RAM being put to useful work.
#
# This function adds a `mem` command to every shell that shows:
#   - RAM used by processes only (MemTotal - MemAvailable)  ← what you actually care about
#   - Reclaimable page cache                                 ← effectively free
#   - Available RAM (MemAvailable)                          ← what new apps can use
#   - Total RAM
# All numbers in MiB for easy comparison across tools.
cat > /etc/profile.d/kubuntu-mem.sh << 'MEMFN_EOF'
# kubuntu-setup: `mem` — consistent RAM reporter using MemAvailable
mem() {
    local -A m=()
    while IFS=': ' read -r key val _; do
        m[$key]=${val}
    done < /proc/meminfo
    local total=$(( m[MemTotal]       / 1024 ))
    local avail=$(( m[MemAvailable]   / 1024 ))
    local cache=$(( (m[Cached] + m[Buffers] + m[SReclaimable]) / 1024 ))
    local apps=$((  total - avail ))
    local pct=$(( apps * 100 / total ))
    printf '\n  RAM used by apps : %6d MiB  (%d%%)\n' "$apps"  "$pct"
    printf    '  Page cache       : %6d MiB  (reclaimable — effectively free)\n' "$cache"
    printf    '  Available        : %6d MiB\n' "$avail"
    printf    '  Total            : %6d MiB\n\n' "$total"
    printf '  TIP: htop green bar = apps only (correct). KSysGuard "Used" includes cache.\n'
    printf '       Both are right; cache is free RAM the kernel uses as a disk speed-up.\n\n'
}
export -f mem 2>/dev/null || true
MEMFN_EOF
chmod 644 /etc/profile.d/kubuntu-mem.sh
ok "mem function installed  (/etc/profile.d/kubuntu-mem.sh — run \`mem\` for consistent RAM breakdown)"

# ── remove ksshaskpass — KDE's GUI SSH passphrase helper
# It intercepts SSH_ASKPASS and pops a GUI dialog even in terminals, breaking
# interactive git/ssh credential prompts. Remove it; the profile.d fix below
# handles any other askpass program that may be installed in future.
if dpkg-query -W -f='${Status}' ksshaskpass 2>/dev/null | grep -q "install ok installed"; then
    apt-get purge -y ksshaskpass
    ok "ksshaskpass removed"
else
    ok "ksshaskpass not installed — skipping"
fi

# ── suppress ksshaskpass at the source — Plasma env file + profile.d + bashrc
# KDE Plasma injects SSH_ASKPASS=/usr/bin/ksshaskpass via
# /etc/xdg/plasma-workspace/env/ksshaskpass.sh at every session start.
# When ksshaskpass is not installed this causes "cannot exec ksshaskpass" errors
# on every git push / ssh that needs credentials, even in a terminal.
#
# ksshaskpass.sh is owned by the kubuntu-settings-desktop package and gets
# restored to its original content on every package upgrade — so we must NOT
# rely on editing it.  Instead we drop a separate override file that sorts
# after it alphabetically; the package will never touch a file it doesn't own.
#
# Three-layer fix so no shell type is missed:
#   1. /etc/xdg/plasma-workspace/env/zzz-no-askpass.sh — Plasma session env
#      (loads after ksshaskpass.sh; survives kubuntu-settings-desktop upgrades).
#   2. /etc/profile.d/ script — login shells (ssh, su -l, …).
#   3. ~/.bashrc snippet — non-login interactive shells (Konsole default).

# Layer 1: drop an override env file that outlives kubuntu-settings-desktop upgrades
PLASMA_OVERRIDE=/etc/xdg/plasma-workspace/env/zzz-no-askpass.sh
cat > "$PLASMA_OVERRIDE" << 'PLASMA_EOF'
# kubuntu-setup: override ksshaskpass.sh — clear askpass vars so git/ssh use the terminal.
# This file is intentionally named zzz-* so it loads after ksshaskpass.sh and is NOT
# owned by kubuntu-settings-desktop, so package upgrades cannot restore the original vars.
unset SSH_ASKPASS
unset SSH_ASKPASS_REQUIRE
PLASMA_EOF
chmod 644 "$PLASMA_OVERRIDE"
ok "Plasma askpass override installed  ($PLASMA_OVERRIDE)"

# Layer 2: /etc/profile.d/ — login shells
cat > /etc/profile.d/99-ssh-terminal-askpass.sh << 'ASKPASS_EOF'
# kubuntu-setup: use terminal for SSH/git prompts, not ksshaskpass GUI pop-up
unset SSH_ASKPASS
unset SSH_ASKPASS_REQUIRE
ASKPASS_EOF
chmod 644 /etc/profile.d/99-ssh-terminal-askpass.sh

# Layer 3: ~/.bashrc — non-login interactive shells (Konsole default)
BASHRC_MARKER="# kubuntu-setup: suppress ksshaskpass"
if ! grep -qF "$BASHRC_MARKER" "${USER_HOME}/.bashrc" 2>/dev/null; then
    cat >> "${USER_HOME}/.bashrc" << 'BASHRC_EOF'

# kubuntu-setup: suppress ksshaskpass — git/ssh prompt in terminal, not GUI
unset SSH_ASKPASS
unset SSH_ASKPASS_REQUIRE
BASHRC_EOF
    ok "SSH askpass fix added to ~/.bashrc"
else
    ok "SSH askpass fix already in ~/.bashrc — skipping"
fi

ok "SSH askpass fix installed  (Plasma env override + profile.d + bashrc)"

ok "System performance hardening complete"

info "Deploying KWin gaming-performance script files..."

KWIN_SCRIPT_DIR="${USER_HOME}/.local/share/kwin/scripts/gaming-performance"
mkdir -p "${KWIN_SCRIPT_DIR}/contents/code"

cat > "${KWIN_SCRIPT_DIR}/metadata.json" << 'KWMETA_EOF'
{
    "KPlugin": {
        "Authors": [{"Email": "", "Name": "BeanGreen247"}],
        "Description": "Disables compositing / desktop effects for fullscreen windows and known gaming + video-editing apps. Pairs with gamemode hooks for maximum performance.",
        "Id": "gaming-performance",
        "License": "GPL-2.0-or-later",
        "Name": "Gaming Performance",
        "Version": "1.1",
        "Website": "https://github.com/BeanGreen247"
    }
}
KWMETA_EOF

cat > "${KWIN_SCRIPT_DIR}/contents/code/main.js" << 'KWMAIN_EOF'
"use strict";
// Gaming Performance — KWin Script for Plasma 6
// Automatically blocks compositing for fullscreen windows and known
// gaming / video-editing applications, reducing frame latency.

var GAMING_CLASSES = [
    // Steam (all games appear as steam_app_<APPID>)
    "steam_app",
    // Launchers
    "heroic", "heroicgameslauncher",
    "lutris",
    // Wine / Proton (non-Steam games)
    "wine", "wineserver", "explorer.exe",
    // Battle.net / Blizzard
    "battlenet", "battle.net", "overwatch", "overwatch2",
    // Riot / League
    "leagueclient", "leagueclientux",
    // Video editing
    "davinciresolve", "resolve",
    "kdenlive",
    "shotcut",
    "openshot",
    "obs",
    // Add your own below:
    // "mygame",
];

function isGamingWindow(win) {
    var cls  = win.resourceClass.toString().toLowerCase();
    var name = win.resourceName.toString().toLowerCase();
    for (var i = 0; i < GAMING_CLASSES.length; i++) {
        var p = GAMING_CLASSES[i];
        if (cls.indexOf(p) !== -1 || name.indexOf(p) !== -1) return true;
    }
    return false;
}

function applyPerf(win, enable) {
    win.blocksCompositing = enable;
}

// --- Hook: any window going fullscreen ---
workspace.windowAdded.connect(function(win) {
    win.fullScreenChanged.connect(function() {
        if (win.fullScreen) {
            applyPerf(win, true);
        } else {
            // Only release if it was not already a gaming-class window
            if (!isGamingWindow(win)) applyPerf(win, false);
        }
    });

    // --- Hook: gaming-class window appears (even windowed) ---
    if (isGamingWindow(win)) applyPerf(win, true);
});

// --- Hook: restore when gaming window closes ---
workspace.windowRemoved.connect(function(win) {
    if (win.blocksCompositing) applyPerf(win, false);
});
KWMAIN_EOF

chown -R "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/share/kwin"
ok "KWin gaming-performance script deployed to ${KWIN_SCRIPT_DIR}"
info "Setting up post-login autostart (Wine prefix + KWin activation)..."
SCRIPT_SRC="$(realpath "$0")"
SCRIPT_DEST="${USER_HOME}/.local/bin/setup-kubuntu.sh"
POSTLOGIN_DEST="${USER_HOME}/.local/bin/post-login-setup.py"
mkdir -p "${USER_HOME}/.local/bin"
cp "${SCRIPT_SRC}" "${SCRIPT_DEST}"
chmod +x "${SCRIPT_DEST}"
chown "${USER_NAME}:${USER_NAME}" "${SCRIPT_DEST}"

# Deploy the post-login GUI app and the setup installer GUI
SCRIPT_DIR_PL="$(cd "$(dirname "$(realpath "$0")" )" && pwd)"
INSTALLER_DEST="${USER_HOME}/.local/bin/setup-installer.py"

if [[ -f "${SCRIPT_DIR_PL}/post-login-setup.py" ]]; then
    install -m 755 "${SCRIPT_DIR_PL}/post-login-setup.py" "${POSTLOGIN_DEST}"
    ok "post-login-setup.py installed from repo"
else
    wget -q https://raw.githubusercontent.com/BeanGreen247/kubuntu-setup/main/post-login-setup.py \
        -O "${POSTLOGIN_DEST}" \
    && chmod +x "${POSTLOGIN_DEST}" \
    && ok "post-login-setup.py downloaded from GitHub" \
    || warn "post-login-setup.py download failed — post-login GUI will not be available"
fi
chown "${USER_NAME}:${USER_NAME}" "${POSTLOGIN_DEST}" 2>/dev/null || true

if [[ -f "${SCRIPT_DIR_PL}/setup-installer.py" ]]; then
    install -m 755 "${SCRIPT_DIR_PL}/setup-installer.py" "${INSTALLER_DEST}"
    ok "setup-installer.py installed from repo"
else
    wget -q https://raw.githubusercontent.com/BeanGreen247/kubuntu-setup/main/setup-installer.py \
        -O "${INSTALLER_DEST}" \
    && chmod +x "${INSTALLER_DEST}" \
    && ok "setup-installer.py downloaded from GitHub" \
    || warn "setup-installer.py download failed — installer GUI will not be available"
fi
chown "${USER_NAME}:${USER_NAME}" "${INSTALLER_DEST}" 2>/dev/null || true

# Sentinel file: post-login runner touches this on completion.
# The autostart entry is skipped if it already exists, so even a crash on
# first run will not loop — the user can simply re-run manually.
POSTLOGIN_DONE_DIR="${USER_HOME}/.local/share/kubuntu-setup"
POSTLOGIN_DONE_FLAG="${POSTLOGIN_DONE_DIR}/.post-login-done"
mkdir -p "${POSTLOGIN_DONE_DIR}"
chown "${USER_NAME}:${USER_NAME}" "${POSTLOGIN_DONE_DIR}"
# Remove any stale flag so the upcoming post-login run actually executes
rm -f "${POSTLOGIN_DONE_FLAG}"

mkdir -p "${USER_HOME}/.config/autostart"
cat > "${USER_HOME}/.config/autostart/kubuntu-post-login.desktop" << AUTOSTART_EOF
[Desktop Entry]
Type=Application
Name=Kubuntu Post-Login Setup
Comment=Runs once after install — shows progress GUI for Wine prefix init and KWin setup
Exec=python3 ${POSTLOGIN_DEST}
Terminal=false
X-KDE-autostart-phase=2
X-KDE-autostart-after=panel
X-KDE-AutostartCondition=if [ ! -f ${POSTLOGIN_DONE_FLAG} ]; then exit 0; else exit 1; fi
AUTOSTART_EOF
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.config/autostart"
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.config/autostart/kubuntu-post-login.desktop"
ok "Post-login autostart registered — GUI setup wizard will run automatically on first login"
fi  # ─── end: 12/15 perf hardening ───

hdr "13/15  Dotfiles"
if (( _SKIP_DOTFILES )); then
    info "13/15 skipped  (profile: ${INSTALL_PROFILE})"
else

info "Deploying dotfile-sync..."
mkdir -p "${USER_HOME}/.local/bin"
SCRIPT_DIR_DS="$(cd "$(dirname "$(realpath "$0")" )" && pwd)"
if [[ -f "${SCRIPT_DIR_DS}/dotfile-sync.py" ]]; then
    install -m 755 "${SCRIPT_DIR_DS}/dotfile-sync.py" "${USER_HOME}/.local/bin/dotfile-sync"
    ok "dotfile-sync installed from repo"
else
    wget -q https://raw.githubusercontent.com/BeanGreen247/kubuntu-setup/main/dotfile-sync.py \
        -O "${USER_HOME}/.local/bin/dotfile-sync" \
    && chmod +x "${USER_HOME}/.local/bin/dotfile-sync" \
    && ok "dotfile-sync downloaded from GitHub" \
    || warn "dotfile-sync download failed — copy dotfile-sync.py to ~/.local/bin/dotfile-sync manually"
fi
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/dotfile-sync" 2>/dev/null || true

info "Running initial dotfile sync (bashrc + vimrc from BeanGreen247/dotfiles)..."
if sudo -u "${USER_NAME}" HOME="${USER_HOME}" "${USER_HOME}/.local/bin/dotfile-sync"; then
    ok "Dotfiles synced via dotfile-sync"
else
    warn "dotfile-sync initial run failed — falling back to direct wget"
    wget -q "https://raw.githubusercontent.com/BeanGreen247/dotfiles/master/bashrc/bashrc" \
        -O "${USER_HOME}/.bashrc" \
        && ok "bashrc-linux deployed from GitHub" \
        || warn ".bashrc fetch failed — check internet access"
    wget -q "https://raw.githubusercontent.com/BeanGreen247/dotfiles/master/vim/vimrc" \
        -O "${USER_HOME}/.vimrc" \
        && ok "vimrc deployed from GitHub" \
        || warn ".vimrc fetch failed — check internet access"
    chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.bashrc" "${USER_HOME}/.vimrc" 2>/dev/null || true
fi

info "dotfile-sync timer + tray will auto-start on first login (checks + syncs every 12 h)"

info "Deploying dotfile-sync-tray..."
if [[ -f "${SCRIPT_DIR_DS}/dotfile-sync-tray.py" ]]; then
    install -m 755 "${SCRIPT_DIR_DS}/dotfile-sync-tray.py" \
        "${USER_HOME}/.local/bin/dotfile-sync-tray"
    ok "dotfile-sync-tray installed from repo"
else
    wget -q https://raw.githubusercontent.com/BeanGreen247/kubuntu-setup/main/dotfile-sync-tray.py \
        -O "${USER_HOME}/.local/bin/dotfile-sync-tray" \
    && chmod +x "${USER_HOME}/.local/bin/dotfile-sync-tray" \
    && ok "dotfile-sync-tray downloaded from GitHub" \
    || warn "dotfile-sync-tray download failed — copy dotfile-sync-tray.py to ~/.local/bin/dotfile-sync-tray manually"
fi
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/dotfile-sync-tray" 2>/dev/null || true

mkdir -p "${USER_HOME}/.config/autostart"
cat > "${USER_HOME}/.config/autostart/dotfile-sync-tray.desktop" << TRAYDESK_EOF
[Desktop Entry]
Type=Application
Name=Dotfile Sync Tray
Comment=System-tray indicator for BeanGreen247/dotfiles — checks and syncs twice a day (every 12 h)
Exec=${USER_HOME}/.local/bin/dotfile-sync-tray
Icon=vcs-normal
Categories=Utility;
X-KDE-autostart-phase=2
X-KDE-UniqueApplet=true
TRAYDESK_EOF
chown "${USER_NAME}:${USER_NAME}" \
    "${USER_HOME}/.config/autostart/dotfile-sync-tray.desktop"
ok "dotfile-sync-tray autostart registered → ~/.config/autostart/dotfile-sync-tray.desktop"
info "Tray icon will appear on next login (double-click or middle-click = check now)"

# ── infra-connections (Tailscale + ZeroTier status tray) ──────────────────────
info "Deploying infra-connections tray…"
SCRIPT_DIR_IC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR_IC}/infra-connections.py" ]]; then
    install -m 755 "${SCRIPT_DIR_IC}/infra-connections.py" \
        "${USER_HOME}/.local/bin/infra-connections"
    ok "infra-connections installed from repo"
else
    wget -q https://raw.githubusercontent.com/BeanGreen247/kubuntu-setup/main/infra-connections.py \
        -O "${USER_HOME}/.local/bin/infra-connections" \
    && chmod +x "${USER_HOME}/.local/bin/infra-connections" \
    && ok "infra-connections downloaded from GitHub" \
    || warn "infra-connections download failed — copy infra-connections.py to ~/.local/bin/infra-connections manually"
fi
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/infra-connections" 2>/dev/null || true

mkdir -p "${USER_HOME}/.config/autostart"
cat > "${USER_HOME}/.config/autostart/infra-connections.desktop" << INFRA_EOF
[Desktop Entry]
Type=Application
Name=Infra Connections
Comment=Tailscale + ZeroTier status tray indicator
Exec=${USER_HOME}/.local/bin/infra-connections
Icon=network-vpn
Categories=Utility;Network;
X-KDE-autostart-phase=2
INFRA_EOF
chown "${USER_NAME}:${USER_NAME}" \
    "${USER_HOME}/.config/autostart/infra-connections.desktop"
ok "infra-connections autostart registered → ~/.config/autostart/infra-connections.desktop"
fi  # ─── end: 13/15 ───

hdr "14/15  Python tooling"
if (( _DOTFILES_ONLY )); then
    info "14/15 skipped  (profile: ${INSTALL_PROFILE})"
else

# Ensure the user bin dir exists before all three installs
mkdir -p "${USER_HOME}/.local/bin"
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin"

# ── mise (polyglot version manager — replaces nvm/pyenv/rbenv/asdf) ──────────
# Installed as a single precompiled binary from GitHub — no installer script,
# no distro detection, works on any Ubuntu codename.
if ! sudo -u "$USER_NAME" test -x "${USER_HOME}/.local/bin/mise" 2>/dev/null; then
    _MISE_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/jdx/mise/releases/latest" \
        | grep '"tag_name"' | grep -oP 'v[\d.]+' | head -1)
    _MISE_VER=${_MISE_VER:-v2025.5.0}
    if curl -fsSLm 60 \
            "https://github.com/jdx/mise/releases/download/${_MISE_VER}/mise-${_MISE_VER}-linux-x64" \
            -o "${USER_HOME}/.local/bin/mise"; then
        chmod +x "${USER_HOME}/.local/bin/mise"
        chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/mise"
        ok "mise ${_MISE_VER} installed  (${USER_HOME}/.local/bin/mise)"
    else
        warn "mise install failed — see https://mise.jdx.dev"
    fi
    unset _MISE_VER
else
    ok "mise already installed  ($(sudo -u "$USER_NAME" "${USER_HOME}/.local/bin/mise" --version 2>/dev/null || echo 'unknown version'))"
fi

# ── uv (fast Python package manager / venv tool) ─────────────────────────────
if ! sudo -u "$USER_NAME" test -x "${USER_HOME}/.local/bin/uv" 2>/dev/null; then
    _UV_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/astral-sh/uv/releases/latest" \
        | grep '"tag_name"' | grep -oP '[\d.]+' | head -1)
    _UV_VER=${_UV_VER:-0.7.0}
    if curl -fsSLm 60 \
            "https://github.com/astral-sh/uv/releases/download/${_UV_VER}/uv-x86_64-unknown-linux-gnu.tar.gz" \
            -o /tmp/uv.tar.gz \
        && tar -xzf /tmp/uv.tar.gz -C /tmp; then
        _UV_BIN=$(find /tmp -maxdepth 2 -name 'uv' -not -name 'uvx' -type f 2>/dev/null | head -1)
        if [[ -n "$_UV_BIN" ]]; then
            mv "$_UV_BIN" "${USER_HOME}/.local/bin/uv"
            chmod +x "${USER_HOME}/.local/bin/uv"
            chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/uv"
            ok "uv ${_UV_VER} installed  (${USER_HOME}/.local/bin/uv)"
        else
            warn "uv install failed — binary not found in archive"
        fi
        unset _UV_BIN
    else
        warn "uv install failed — see https://docs.astral.sh/uv"
    fi
    rm -f /tmp/uv.tar.gz
    find /tmp -maxdepth 1 -name 'uv-*' -type d -exec rm -rf {} + 2>/dev/null || true
    unset _UV_VER
else
    ok "uv already installed"
fi

# ── ruff (fast Python linter / formatter, written in Rust) ───────────────────
if ! sudo -u "$USER_NAME" test -x "${USER_HOME}/.local/bin/ruff" 2>/dev/null; then
    _RUFF_VER=$(curl -fsSLm 10 \
        "https://api.github.com/repos/astral-sh/ruff/releases/latest" \
        | grep '"tag_name"' | grep -oP '[\d.]+' | head -1)
    _RUFF_VER=${_RUFF_VER:-0.11.0}
    if curl -fsSLm 60 \
            "https://github.com/astral-sh/ruff/releases/download/${_RUFF_VER}/ruff-x86_64-unknown-linux-gnu.tar.gz" \
            -o /tmp/ruff.tar.gz \
        && tar -xzf /tmp/ruff.tar.gz -C /tmp; then
        _RUFF_BIN=$(find /tmp -maxdepth 2 -name 'ruff' -type f 2>/dev/null | head -1)
        if [[ -n "$_RUFF_BIN" ]]; then
            mv "$_RUFF_BIN" "${USER_HOME}/.local/bin/ruff"
            chmod +x "${USER_HOME}/.local/bin/ruff"
            chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.local/bin/ruff"
            ok "ruff ${_RUFF_VER} installed  (${USER_HOME}/.local/bin/ruff)"
        else
            warn "ruff install failed — binary not found in archive"
        fi
        unset _RUFF_BIN
    else
        warn "ruff install failed — see https://docs.astral.sh/ruff"
    fi
    rm -f /tmp/ruff.tar.gz
    find /tmp -maxdepth 1 -name 'ruff-*' -type d -exec rm -rf {} + 2>/dev/null || true
    unset _RUFF_VER
else
    ok "ruff already installed"
fi

# ── pipx (isolated Python app installer) ─────────────────────────────────────
if ! command -v pipx &>/dev/null; then
    apt-get install -y pipx 2>/dev/null \
    && ok "pipx installed via apt" \
    || warn "pipx install failed"
fi

ok "Python tooling done (mise, uv, ruff, pipx)"

fi  # ─── end: 14/15 ───

hdr "15/15  Services + cleanup"
if (( _DOTFILES_ONLY )); then
    info "15/15 skipped  (profile: ${INSTALL_PROFILE})"
else

(( _SKIP_INFRA )) || systemctl enable xrdp
systemctl enable docker
(( _SKIP_INFRA )) || systemctl enable libvirtd
(( _SKIP_INFRA )) || systemctl enable tailscaled  2>/dev/null || true
(( _SKIP_INFRA )) || systemctl enable zerotier-one 2>/dev/null || true
systemctl enable apt-key-refresh.timer 2>/dev/null || true

# ── ModemManager: disable if no mobile broadband hardware present ─────────────
# ModemManager is a D-Bus daemon that probes USB/PCIe ports for 3G/4G/5G modems
# on every boot (~15 MB RSS, constant udev polling). Disable it unless a WWAN
# interface or a modem-class USB device is actually present.
if ! (ls /sys/class/net/ 2>/dev/null | grep -qiE 'wwan|mbm|qmi|cdc') && \
   ! (lsusb 2>/dev/null | grep -iqE 'modem|wwan|3g|4g|lte|huawei|sierra|zte|option|cdc-wdm'); then
    systemctl disable --now ModemManager 2>/dev/null || true
    ok "ModemManager disabled  (no WWAN/modem hardware detected — saves ~15 MB RAM)"
else
    info "ModemManager kept enabled  (WWAN or modem hardware detected)"
fi

# ── cups-browsed: mask — network printer browse daemon ───────────────────────
# cups.service handles all local printing and is kept. cups-browsed is a
# separate daemon that continuously scans the LAN for shared printers via
# mDNS/Bonjour and IPP Every Poll. On a desktop that prints via USB or a
# manually-configured URI this background scan is pure overhead (~20 MB RSS).
# To re-enable network printer discovery:
#   sudo systemctl unmask cups-browsed && sudo systemctl enable --now cups-browsed
systemctl disable --now cups-browsed 2>/dev/null || true
systemctl mask        cups-browsed 2>/dev/null || true
ok "cups-browsed masked  (network printer scan disabled — saves ~20 MB RAM; cups.service kept for local printing)"

# ── seatd: disable — redundant seat manager on KDE + logind ──────────────────
# seatd is a minimal seat management daemon used by wlroots compositors
# (sway, river, labwc). KDE Plasma with SDDM uses systemd-logind for all
# seat and session management; seatd serves no purpose here and wastes ~2 MB RSS.
systemctl disable --now seatd 2>/dev/null || true
ok "seatd disabled  (redundant with systemd-logind on KDE Plasma — saves ~2 MB RAM)"

# ── apport / whoopsie: mask — Ubuntu crash + telemetry reporters ─────────────
# apport: intercepts crashing processes, writes core files to /var/crash, and
#   can upload crash reports to Canonical's error tracker. Core dumps are
#   already suppressed by our sysctl (kernel.core_pattern=|/bin/false) so
#   apport never has anything to capture — it just runs as a service eating RAM.
# whoopsie: Ubuntu's error reporting daemon — batches and uploads crash data in
#   the background. Purely passive telemetry; zero user value on a hardened desktop.
# Masking (not just disabling) prevents apt from re-enabling them on upgrades.
for _svc in apport whoopsie whoopsie.path; do
    if systemctl list-unit-files "${_svc}" 2>/dev/null | grep -q "${_svc}"; then
        systemctl disable --now "${_svc}" 2>/dev/null || true
        systemctl mask        "${_svc}" 2>/dev/null || true
    fi
done
ok "apport + whoopsie masked  (crash reporter + telemetry disabled — saves ~15 MB RAM)"

info "Running final system update + upgrade..."
apt-get update -qq 2>&1 | grep -E '^(E:|W:)' || true
dpkg --configure -a 2>/dev/null || true
apt --fix-broken install -y 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true
apt-get dist-upgrade -y -qq
ok "System fully up to date"

info "Running full cache cleanup..."
# Remove packages no longer needed by any installed package
apt-get autoremove -y --purge
# Remove partial/obsolete downloaded package files
apt-get autoclean
# Wipe entire apt package cache (all .deb files in /var/cache/apt/archives/)
apt-get clean
# pip/pipx cache
pip3 cache purge 2>/dev/null || true
pipx runpip list 2>/dev/null | awk '{print $1}' | xargs -r pipx runpip cache remove 2>/dev/null || true
# npm cache (if installed)
command -v npm &>/dev/null && npm cache clean --force 2>/dev/null || true
# Go module download cache (if installed) — delete build cache only, keep module sources
command -v go &>/dev/null && go clean -cache 2>/dev/null || true
# Docker build cache — only if Docker is running and user opted for docker
if systemctl is-active --quiet docker 2>/dev/null; then
    docker builder prune -f --filter "until=24h" 2>/dev/null || true
fi
# Thumbnail cache (can grow large unnoticed)
find "${USER_HOME}/.cache/thumbnails" -type f -atime +30 -delete 2>/dev/null || true
# Journal: keep last 2 weeks, cap at 500 MB
journalctl --vacuum-time=2weeks 2>/dev/null || true
journalctl --vacuum-size=500M  2>/dev/null || true
ok "Cache cleanup complete"

info "Re-enabling unattended-upgrades..."
systemctl enable --now unattended-upgrades 2>/dev/null || true
systemctl enable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

ok "Cleanup complete"

if [[ -d "$GE_CACHE" ]] && [[ -n "$(ls -A "$GE_CACHE" 2>/dev/null)" ]]; then
    echo ""
    _GE_SIZE=$(du -sh "$GE_CACHE" 2>/dev/null | cut -f1)
    echo -e "  ${YELLOW}GE download cache:${NC} ${GE_CACHE}  (${_GE_SIZE})"
    echo -e "  Contains: $(ls "$GE_CACHE" | tr '\n' '  ')"
    echo -e "  Keep it to avoid re-downloading on future re-runs."
    if [[ $_ARG_YES -eq 0 ]]; then
        read -rp "  Remove cache now? [y/N]: " -n 1 -r; echo
    else
        REPLY="n"  # keep cache when running non-interactively
    fi
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$GE_CACHE"
        ok "GE cache removed"
    else
        ok "GE cache kept → ${GE_CACHE}"
    fi
fi

_clear_progress
echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║           KUBUNTU 26.04 SETUP COMPLETE                    ║${NC}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}  ✓${NC}  deb-get (third-party package manager — auto-updates Discord, Heroic, Lutris)"
echo -e "${GREEN}  ✓${NC}  System updated — i386 multiarch + universe/multiverse enabled"
echo -e "${GREEN}  ✓${NC}  Multimedia codecs (ffmpeg, gstreamer, ubuntu-restricted-extras)"
echo -e "${GREEN}  ✓${NC}  KDE extras + comprehensive font collection"
echo -e "${GREEN}  ✓${NC}  Brave Browser (auto-updates via apt)"
echo -e "${GREEN}  ✓${NC}  Pulsar (claude-chat + git-plus) + Docker CE + Ansible + kubectl + Azure CLI"
echo -e "${GREEN}  ✓${NC}  Python infra packages: proxmoxer, netmiko, napalm, pynetbox"
echo -e "${GREEN}  ✓${NC}  Wireshark + man-pages (POSIX) + linux-doc"
echo -e "${GREEN}  ✓${NC}  xrdp  (RDP server, port 3389)"
echo -e "${GREEN}  ✓${NC}  FreeRDP3 (xfreerdp3 CLI) + TigerVNC + KRDC (KDE GUI) — best-in-class RDP/VNC stack"
echo -e "${GREEN}  ✓${NC}  Extended networking: net-tools, iperf3, socat, arp-scan, mosh, ldnsutils, ipcalc"
echo -e "${GREEN}  ✓${NC}  LLVM toolchain: clang, lldb, meson, ninja, valgrind, shellcheck"
echo -e "${GREEN}  ✓${NC}  Modern CLI: pv, moreutils, parallel, entr, ncdu, duf, zoxide, httpie, aria2"
echo -e "${GREEN}  ✓${NC}  Observability: sysstat (sar/iostat), iotop-c, iftop, nethogs, perf, stress-ng, powertop"
echo -e "${GREEN}  ✓${NC}  Disk + storage: smartmontools, nvme-cli, hdparm, lvm2, cryptsetup, gparted, xfs/btrfs"
echo -e "${GREEN}  ✓${NC}  Security: UFW enabled (default-deny; SSH open; RDP restricted to VPN subnets), fail2ban (sshd + xrdp jails, 2 h ban), lynis, clamav (on-demand; clamd masked), age"
echo -e "${GREEN}  ✓${NC}  Rootless containers: Podman + buildah + skopeo"
echo -e "${GREEN}  ✓${NC}  GPU: ${GPU_TYPE}$([ "$GPU_TYPE" = vm ] && echo '  (virtio-gpu/SPICE + Mesa virgl + qemu-guest-agent)' || echo '  (no drivers installed — see gpu-setup-commands.txt)')"
echo -e "${GREEN}  ✓${NC}  NTFS support (ntfs3 in-kernel driver + ntfs-3g fallback + exFAT)"
echo -e "${GREEN}  ✓${NC}  Wine staging (WineHQ, WoW64) + winetricks + 32/64-bit runtime libs"
echo -e "${GREEN}  ✓${NC}  Proton-GE (Steam compat tools) + Wine-GE (Heroic + Lutris runners)"
echo -e "${GREEN}  ✓${NC}  Post-login autostart: Wine prefix init + KWin script + KDE power/perf tuning (runs automatically on first login)"
echo -e "${GREEN}  ✓${NC}  Steam"
echo -e "${GREEN}  ✓${NC}  Discord"
echo -e "${GREEN}  ✓${NC}  Heroic Games Launcher  (Epic Games + GOG — uses Wine-GE runner)"
echo -e "${GREEN}  ✓${NC}  Lutris  (EA Desktop App + Rockstar — uses Wine-GE runner)"
echo -e "${GREEN}  ✓${NC}  MangoHud + GameMode + GOverlay + kscreen"
echo -e "${GREEN}  ✓${NC}  gamemode.ini: CPU governor + AMD GPU profile + compositor hooks"
echo -e "${GREEN}  ✓${NC}  KWin gaming-performance script (Plasma 6): blocks compositing on fullscreen/gaming windows"
echo -e "${GREEN}  ✓${NC}  Gamemode hooks: suspend/resume KWin compositor + max refresh rate via kscreen-doctor"
echo -e "${GREEN}  ✓${NC}  dotfile-sync-tray — KDE system-tray icon: hover for status, auto-notifies on upstream changes"
echo -e "${GREEN}  ✓${NC}  apt-key-refresh — weekly systemd timer validates + refreshes all third-party signing keys, notifies on rotation"
echo -e "${GREEN}  ✓${NC}  Tailscale + ZeroTier + Samba client"
echo -e "${GREEN}  ✓${NC}  virt-manager + QEMU/KVM"
echo -e "${GREEN}  ✓${NC}  System performance hardening: sysctl tunables (BBR, dirty pages, network buffers), CPU schedutil governor, irqbalance, zram+swapfile (capped 4 GB total, NVMe-friendly), preload prefetch, raised file/RT limits"
echo -e "${GREEN}  ✓${NC}  Dotfiles: bashrc-linux + vimrc (BeanGreen247/dotfiles)"
echo -e "${GREEN}  ✓${NC}  dotfile-sync: periodic dotfile pull (systemd user timer, 24 h interval)"
echo -e "${GREEN}  ✓${NC}  Repos — official: main + universe + multiverse + restricted + backports + partner"
echo -e "${GREEN}  ✓${NC}  Repos — PPAs: Python, git, Mesa/NVIDIA drivers, Plasma, GCC, LibreOffice, fish, Go, PHP, OBS, Java, Ansible, grub-customizer"
echo -e "${GREEN}  ✓${NC}  Repos — 3rd-party: Google Chrome, Signal, NodeSource (Node.js 22), Spotify, Azure CLI, Docker, k8s, Wine, Tailscale, ZeroTier"
echo -e "${GREEN}  ✓${NC}  APT discovery: apt-file + command-not-found + synaptic (GUI) | apt-file search <file>  to find which pkg owns it"
echo -e "${GREEN}  ✓${NC}  Package managers: apt (broad), deb-get (.deb/vendor repos), Flatpak/Flathub, Snap, AppImages (libfuse2t64 installed)"
echo ""
echo -e "${YELLOW}${BOLD}  NEXT STEPS (do these after reboot):${NC}"
echo ""
echo "  1.  REBOOT — required for GPU driver changes + group membership"
echo "      (docker, libvirt, kvm, wireshark groups take effect on re-login)"
echo ""
echo "  2.  Tailscale:    sudo tailscale up"
echo "  3.  ZeroTier:     sudo zerotier-cli join <your-network-id>"
echo ""
echo "  4.  POST-LOGIN SETUP runs automatically on first login after reboot."
echo "      It will initialise your Wine prefix (corefonts, vcrun2015, vcrun2019,"
echo "      d3dcompiler_43/47, SSL certs + WoW/launcher registry tweaks)"
echo "      and activate the KWin gaming-performance script — nothing to do manually."
echo "      If it didn't run or you want to re-run it:"
echo "        bash ~/.local/bin/setup-kubuntu.sh --post-login"
echo ""
echo "  5.  Steam:        Settings → Compatibility → Enable for all titles"
echo "      Default compatibility tool → Proton-GE (already installed by script)"
echo "      Add existing library: /mnt/d-drive/SteamLibrary"
echo "      To upgrade Proton-GE later: open ProtonUp-Qt from the app menu"
echo ""
echo "  6.  Heroic:       Log in to Epic Games + GOG"
echo "      Wine-GE runner was pre-installed; Heroic should auto-detect it"
echo "      Wine Settings → Wine version → select Wine-GE"
echo "      Install path suggestion: /mnt/d-drive/hry/<GameName>"
echo "      To upgrade Wine-GE later: open ProtonUp-Qt → Heroic tab"
echo ""
echo "  7.  Lutris:       Preferences → Runners → Wine → version → Wine-GE (auto-detected)"
echo "      Search and install in Lutris:"
echo "      • EA Desktop App  (needed for FC 25, Battlefield, etc.)"
echo "      • Rockstar Games Launcher  (needed for GTA V, RDR2)"
echo "      To upgrade Wine-GE later: ProtonUp-Qt → Lutris tab"
echo ""
echo "  8.  osu! (lazer): AppImage from https://osu.ppy.sh/home/download"
echo "      WotLK / retail WoW: copy your D: WoW folder → run via Lutris/Wine"
echo ""
echo "  9.  xrdp:         Connect from Windows mstsc / KRDC (KDE) / xfreerdp3 CLI:"
echo "      Host: $(hostname -I | awk '{print $1}') or Tailscale IP"
echo "      Port: 3389  |  Session type: Xorg (or leave default)"
echo ""
echo "  10. PCSX2:        Set BIOS path → /mnt/d-drive/ps2_roms/ (or your BIOS dir)"
echo ""
echo -e "  Script by ${GREEN}BeanGreen247${NC} — https://github.com/BeanGreen247"
echo ""
fi  # ─── end: 15/15 ───

_print_summary
