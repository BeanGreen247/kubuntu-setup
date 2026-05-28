#!/usr/bin/env python3
"""
setup-installer.py — Kubuntu Setup Launcher

Frameless PyQt6 GUI for setup-kubuntu.sh.

Welcome screen:     two-panel layout — scrollable install groups (left) +
                    detail view (right), GPU selector, three action buttons.
Install screen:     step list (left, clickable) + per-step live log (right) +
                    progress bar at bottom.
Done screen:        summary + resource links.

Root elevation:     pkexec → kdesu → abort (polkit handles the password dialog).
Stdin automation:   watches output for prompt strings, writes answers to QProcess.

Requirements: python3-pyqt6  (installed by setup-kubuntu.sh)
Run:          python3 setup-installer.py
"""

import os
import re
import shutil
import subprocess
import sys
import webbrowser
from pathlib import Path

from PyQt6.QtCore import QPoint, QProcess, QProcessEnvironment, Qt, QTimer, QUrl
from PyQt6.QtGui import QColor, QDesktopServices, QTextCursor
from PyQt6.QtWidgets import (
    QApplication,
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QProgressBar,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSplitter,
    QStackedWidget,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

# ── Constants ──────────────────────────────────────────────────────────────────

SCRIPT_PATH    = Path(__file__).resolve().parent / "setup-kubuntu.sh"
CHANGELOG_PATH = Path(__file__).resolve().parent / "CHANGELOG.md"
README_PATH    = Path(__file__).resolve().parent / "README.md"
REPO_DIR       = Path(__file__).resolve().parent
GITHUB_URL     = "https://github.com/BeanGreen247/kubuntu-setup"
DOTFILES_URL = "https://github.com/BeanGreen247/dotfiles"
WIN_W, WIN_H = 1060, 720

ANSI_RE    = re.compile(r"\x1b\[[0-9;]*[mK]")
SECTION_RE = re.compile(r"\b(\d{1,2})/15\b")

GPU_OPTIONS = [
    ("nvidia",  "NVIDIA  — dGPU (Vulkan loader; Driver Manager installs driver post-reboot)"),
    ("amd",     "AMD     — iGPU / dGPU (Mesa + RADV + VA-API + Vulkan)"),
    ("intel",   "Intel   — iGPU (Mesa + ANV + VA-API)"),
    ("hybrid",  "Hybrid  — AMD iGPU + NVIDIA dGPU (switcheroo-control + prime-run)"),
    ("vm",      "VM      — virtio-gpu / SPICE"),
    ("none",    "None    — skip GPU setup entirely"),
]

PROFILE_OPTIONS = [
    ("full",                      "Full  — everything"),
    ("full-no-infra",             "Full, no infra  — gaming + dev, no remote/VPN/virt"),
    ("full-no-dotfiles",          "Full, no dotfiles  — everything except dotfile sync"),
    ("full-no-infra-no-dotfiles", "Full, no infra, no dotfiles  — gaming + dev only"),
    ("infra",                     "Infra  — dev + IT, no gaming stack"),
    ("dotfiles",                  "Dotfiles  — sync only, no packages/kernel changes"),
]

# (icon, short_label, estimated_mb, [detail lines])
INSTALL_GROUPS = [
    ("🔑", "1  Repositories",       512,  [
        "Ubuntu universe / multiverse / restricted + backports",
        "Chrome · Signal · NodeJS 22 · Spotify · WineHQ apt repos",
        "Docker CE · Azure CLI · Kubernetes apt repos",
        "12 PPAs: OBS · Ansible · Git · LLVM · LibreOffice · PHP…",
    ]),
    ("📦", "2  Base packages",      2560, [
        "Build: gcc · clang · lldb · cmake · meson · ninja · valgrind",
        "CLI: btop · bat · fd · ripgrep · fzf · jq · zoxide · aria2",
        "vim · nano · zsh · tmux  ·  Python 3 + pip + PyQt6",
        "timeshift · apt-file · command-not-found · synaptic",
    ]),
    ("🎵", "3  Multimedia + fonts", 1228, [
        "ubuntu-restricted-extras · ffmpeg · GStreamer full stack",
        "mpv · VLC · pavucontrol",
        "KDE extras: kdialog · plasma-systemmonitor · okular · ark",
        "Fonts: JetBrains Mono · Fira Code · Noto CJK · Ubuntu · Roboto",
        "Purge: Oxygen theme · extra wallpaper packs · GNOME theme data",
        "SDDM: Breeze theme · solid dark background (no wallpaper image)",
        "Plymouth: branded splash removed · text theme · no splash/quiet in GRUB",
        "GRUB: 25 s timeout · mitigations=off · preempt=full · nohz_full · threadirqs",
        "GRUB: rootflags=noatime · audit=0 · loglevel=0 · nosoftlockup · nomce",
        "Cursor: Breeze Dark set system-wide (login screen + root + user session)",
    ]),
    ("🛠", "4  Development",        3072, [
        "VS Code (Microsoft repo)  ·  Docker CE + compose plugin",
        "Ansible  ·  kubectl  ·  Azure CLI",
        "Node.js 22 LTS · Go · PHP 8.x",
        "Python: proxmoxer · netmiko · napalm · boto3 · paramiko",
        "Wireshark  ·  lynis · fail2ban · clamav  ·  podman · skopeo",
    ]),
    ("🖥", "5  Remote access",       512, [
        "xrdp — RDP server on port 3389",
        "FreeRDP3 (xfreerdp3 + Wayland)  ·  TigerVNC  ·  KRDC",
    ]),
    ("🖥", "6  GPU drivers",         512, [
        "nvidia: Vulkan loader + prime utils — NO driver auto-install (use Driver Manager after reboot)",
        "amd: Mesa + RADV Vulkan + VA-API/VDPAU + radeontop + 32-bit libs",
        "intel: Mesa + ANV Vulkan + intel-media-va-driver-non-free + intel-gpu-tools",
        "hybrid: AMD Mesa stack + NVIDIA Vulkan loader + switcheroo-control (prime-run wrapper)",
        "vm: virtio-gpu / SPICE + Mesa virgl + qemu-guest-agent (VMware/VirtualBox auto-detected)",
        "none: section skipped entirely",
        "All non-none: video+render group membership, udev DRM rules, lm-sensors auto-detect",
    ]),
    ("🖥", "7  GPU tweaks",            0, [
        "nvidia: __GL_THREADED_OPTIMIZATIONS=1, ForceFullCompositionPipeline hint",
        "amd: RADV preferred over AMDVLK (AMD_VULKAN_ICD=RADV), amdgpu performance udev rule",
        "intel: ANV Vulkan ICD set, intel_iommu=igfx_off (prevents AGP aperture conflicts)",
        "hybrid: DRI_PRIME=1 default for dGPU offload, prime-run wrapper written",
    ]),
    ("💾", "8  Filesystem",           51, [
        "ntfs-3g (NTFS read/write)  ·  exfatprogs (exFAT)",
        "Samba/CIFS: smbclient · cifs-utils · gvfs-smb",
    ]),
    ("🎮", "9  Gaming stack",        4096, [
        "Wine WoW64-staging (WineHQ) + winetricks",
        "Steam + 32/64-bit runtime libs (DXVK / VKD3D / FSR)",
        "Proton-GE (Steam compat)  ·  Wine-GE (Heroic + Lutris runners)",
        "Discord · Heroic Games Launcher (Epic/GOG) · Lutris (EA/Rockstar)",
        "MangoHud · GameMode · GOverlay  ·  KWin gaming-performance script",
        "Wayland: xwayland · xdg-desktop-portal-kde · libdecor",
    ]),
    ("🌐", "10  Networking",          205, [
        "Tailscale — mesh VPN (official apt repo)",
        "ZeroTier  — SDN overlay network",
    ]),
    ("🖧", "11  Virtualisation",    1536, [
        "virt-manager + QEMU/KVM + libvirt  ·  OVMF (UEFI firmware)",
        "User added to libvirt + kvm groups",
    ]),
    ("⚡", "12  Performance",          10, [
        "GRUB: mitigations=off · thermal.off=1 · preempt=full · nohz_full=all · rcu_nocbs=all · threadirqs",
        "GRUB: rootflags=noatime · audit=0 · loglevel=0 · nosoftlockup · ibt=off · split_lock_detect=off",
        "CPU: schedutil governor (burst-on-demand, efficient at idle)",
        "VM: swappiness=5 · vfs_cache_pressure=50 · dirty tuning · watermark_scale=125 · page-cluster=4",
        "VM: compaction=0 · zone_reclaim=0 · NUMA balancing off · stat_interval=10 · oom_kill_allocating_task=1",
        "Sched: sched_latency_ns=4ms · sched_min_gran=500µs · migration_cost=5ms · autogroup=1",
        "THP: madvise (opt-in per process — no background khugepaged scanning)",
        "Swap: zram min(RAM×25%,4GB) zstd pri=100  +  swapfile 2 GB pri=10 nofail",
        "I/O: BFQ+2MB readahead (HDD) · mq-deadline (SSD) · none (NVMe) — udev rule",
        "Net: BBR+fq · 128MB socket buffers · TCP FastOpen · notsent_lowat=16kB · keepalive=120s",
        "Net: netdev_budget=600 · somaxconn=8192 · port_range=1024-65535 · MTU probing · RFC1337",
        "OOM: earlyoom at 5% free RAM · systemd-oomd disabled · hung_task off · task_delayacct=0",
        "FS: /tmp on tmpfs · pipe-max=4MB · inotify watches=524288 · file-max=2097152 · core→/bin/false",
        "journald: compressed · 256 MB cap · RateLimitBurst=1000",
        "systemd timeouts: stop=10s · start=30s · device=10s",
        "irqbalance · preload · fstrim.timer · iwlwifi power_save=0",
    ]),
    ("📁", "13  Dotfiles",              1, [
        "~/.bashrc + ~/.vimrc from BeanGreen247/dotfiles",
        "dotfile-sync timer (12 h auto-sync) + KDE system tray",
    ]),
    ("🐍", "14  Python tooling",        50, [
        "mise — polyglot version manager (replaces nvm/pyenv/rbenv/asdf)",
        "uv — fast Python package manager and venv tool (Astral)",
        "ruff — fast Python linter and formatter (written in Rust, Astral)",
        "pipx — isolated Python app installer (installs CLI tools in their own venvs)",
    ]),
    ("🧹", "15  Services + cleanup",    0, [
        "Enable: xrdp · docker · libvirtd · tailscaled · zerotier-one",
        "Final apt upgrade + dist-upgrade",
        "apt / pip / npm / go / docker cache purge  ·  journal vacuum",
        "Re-enable unattended-upgrades",
    ]),
]

TOTAL_MB = sum(g[2] for g in INSTALL_GROUPS)

STEP_PENDING, STEP_RUNNING, STEP_DONE, STEP_WARN = 0, 1, 2, 3
_STEP_ICON  = {STEP_PENDING: "○", STEP_RUNNING: "◎", STEP_DONE: "✓", STEP_WARN: "⚠"}
_STEP_CLASS = {
    STEP_PENDING: "st_pending",
    STEP_RUNNING: "st_running",
    STEP_DONE:    "st_done",
    STEP_WARN:    "st_warn",
}

# ── Stylesheet ─────────────────────────────────────────────────────────────────

# Breeze Dark — plain, functional, minimal
QSS = """
QMainWindow, QWidget#root { background: #232629; }
QWidget#titlebar  { background: #1b1e20; border-bottom: 1px solid #3a3f44; }
QFrame#div_h      { background: #3a3f44; max-height: 1px; }
QFrame#div_v      { background: #3a3f44; max-width:  1px; }
QSplitter::handle { background: #3a3f44; width: 1px; height: 1px; }

QScrollArea { background: transparent; border: none; }
QScrollBar:vertical   { background: #1b1e20; width: 8px; }
QScrollBar::handle:vertical { background: #4a5056; min-height: 24px; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }

QLabel#app_title   { color: #eff0f1; font-size: 16px; font-weight: bold; }
QLabel#app_sub     { color: #7f8c8d; font-size: 11px; }
QLabel#sec_hdr     { color: #3daee9; font-size: 11px; font-weight: bold; }
QLabel#body        { color: #bdc3c7; font-size: 12px; }
QLabel#size_total  { color: #eff0f1; font-size: 11px; }
QLabel#size_badge  { color: #7f8c8d; font-size: 10px; padding-right: 4px; }
QLabel#detail_title{ color: #eff0f1; font-size: 12px; font-weight: bold; }
QLabel#grp_detail  { color: #7f8c8d; font-size: 11px; }

QLabel#st_pending  { color: #4a5056; font-size: 13px; }
QLabel#st_running  { color: #f67400; font-size: 13px; }
QLabel#st_done     { color: #27ae60; font-size: 13px; }
QLabel#st_warn     { color: #f67400; font-size: 13px; }

QPushButton#step_btn {
    background: transparent; color: #bdc3c7;
    border: none; border-left: 2px solid transparent;
    text-align: left; padding: 5px 8px; font-size: 11px;
}
QPushButton#step_btn:hover   { background: #2d3136; color: #eff0f1; }
QPushButton#step_btn:checked { border-left-color: #3daee9; color: #3daee9; background: #2d3136; }

QTextEdit#log {
    background: #1b1e20; color: #bdc3c7;
    border: 1px solid #3a3f44;
    font-family: "JetBrains Mono","Fira Code","Courier New",monospace;
    font-size: 11px;
}

QProgressBar {
    background: #1b1e20; border: 1px solid #3a3f44;
    height: 22px; color: transparent; text-align: center;
}
QProgressBar::chunk { background: #3daee9; }

QPushButton#btn_primary {
    background: #3daee9; color: #1b1e20; border: none;
    padding: 8px 24px; font-size: 12px; font-weight: bold;
}
QPushButton#btn_primary:hover    { background: #56b9ec; }
QPushButton#btn_primary:pressed  { background: #2b9dc8; }
QPushButton#btn_primary:disabled { background: #3a3f44; color: #4a5056; }

QPushButton#btn_outline {
    background: transparent; color: #3daee9; border: 1px solid #3daee9;
    padding: 7px 20px; font-size: 12px;
}
QPushButton#btn_outline:hover   { background: #1e3040; }
QPushButton#btn_outline:pressed { background: #162535; }

QPushButton#btn_danger {
    background: transparent; color: #da4453; border: 1px solid #da4453;
    padding: 7px 20px; font-size: 12px;
}
QPushButton#btn_danger:hover { background: #2e1519; }

QPushButton#tb_close {
    background: transparent; color: #7f8c8d; border: none;
    font-size: 14px; padding: 0 4px;
}
QPushButton#tb_close:hover { color: #da4453; }

QComboBox {
    background: #2d3136; color: #eff0f1; border: 1px solid #3a3f44;
    padding: 5px 10px; font-size: 12px;
    min-width: 80px;
}
QComboBox:focus  { border-color: #3daee9; }
QComboBox:hover  { border-color: #56b9ec; }
QComboBox::drop-down {
    subcontrol-origin: padding;
    subcontrol-position: top right;
    width: 26px;
    border-left: 1px solid #3a3f44;
    background: #3a3f44;
}
QComboBox::down-arrow {
    image: url("__ARROW_DOWN__");
    width: 10px; height: 6px;
}
QComboBox::down-arrow:on {
    image: url("__ARROW_UP__");
    width: 10px; height: 6px;
}
QComboBox QAbstractItemView {
    background: #2d3136; color: #eff0f1; border: 1px solid #3a3f44;
    selection-background-color: #3daee9; selection-color: #1b1e20;
    outline: none;
}
QLineEdit {
    background: #1b1e20; color: #eff0f1;
    border: 1px solid #3a3f44; border-radius: 3px;
    padding: 5px 8px; font-size: 12px;
}
QLineEdit:focus { border-color: #3daee9; }
"""
QSS = QSS.replace("__ARROW_DOWN__", (REPO_DIR / "img" / "arrow-down.svg").as_posix())
QSS = QSS.replace("__ARROW_UP__",   (REPO_DIR / "img" / "arrow-up.svg").as_posix())


# ── Shared widget helpers ──────────────────────────────────────────────────────

def _hdivider() -> QFrame:
    f = QFrame()
    f.setObjectName("div_h")
    f.setFixedHeight(1)
    return f


def _vdivider() -> QFrame:
    f = QFrame()
    f.setObjectName("div_v")
    f.setFixedWidth(1)
    return f


def _size_str(mb: int) -> str:
    if mb >= 1024:
        return f"{mb / 1024:.1f} GB"
    return f"{mb} MB" if mb > 0 else "—"


def _git(args: list[str]) -> str:
    """Run a git command in REPO_DIR; return stripped stdout or empty string."""
    try:
        return subprocess.check_output(
            ["git", "-C", str(REPO_DIR)] + args,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except Exception:
        return ""


def _local_version() -> str:
    """Short commit hash of the current local HEAD, or empty string."""
    return _git(["rev-parse", "--short", "HEAD"])


# ── Custom title bar with drag support ────────────────────────────────────────

class TitleBar(QWidget):
    def __init__(self, title: str, parent=None):
        super().__init__(parent)
        self.setObjectName("titlebar")
        self.setFixedHeight(36)
        self._drag_pos: QPoint | None = None

        h = QHBoxLayout(self)
        h.setContentsMargins(12, 0, 8, 0)
        h.setSpacing(8)

        lbl = QLabel(title)
        lbl.setStyleSheet("color: #7f8c8d; font-size: 11px;")
        h.addWidget(lbl)

        ver = _local_version()
        if ver:
            ver_lbl = QLabel(ver)
            ver_lbl.setStyleSheet("color: #4a5056; font-size: 10px; font-family: monospace;")
            h.addWidget(ver_lbl)

        h.addStretch()

        about_btn = QPushButton("About")
        about_btn.setObjectName("tb_close")
        about_btn.setToolTip("About")
        about_btn.clicked.connect(self._show_about)
        h.addWidget(about_btn)

        help_btn = QPushButton("Help")
        help_btn.setObjectName("tb_close")
        help_btn.setToolTip("Open README")
        help_btn.clicked.connect(self._show_help)
        h.addWidget(help_btn)

        self._btn_max = QPushButton("□")
        self._btn_max.setObjectName("tb_close")
        self._btn_max.setToolTip("Maximize / Restore")
        self._btn_max.clicked.connect(self._toggle_maximize)
        h.addWidget(self._btn_max)

        close_btn = QPushButton("✕")
        close_btn.setObjectName("tb_close")
        close_btn.clicked.connect(QApplication.quit)
        h.addWidget(close_btn)

    def _show_about(self):
        dlg = QMainWindow(self.window())
        dlg.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.Dialog
        )
        dlg.setStyleSheet(self.window().styleSheet())
        dlg.setFixedWidth(400)

        git_cfg = Path.home() / ".gitconfig"

        central = QWidget()
        dlg.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── Custom title bar ──────────────────────────────────────────────────
        tbar = QWidget()
        tbar.setObjectName("titlebar")
        tbar.setFixedHeight(36)
        th = QHBoxLayout(tbar)
        th.setContentsMargins(12, 0, 8, 0)
        th.setSpacing(8)
        tlbl = QLabel("About")
        tlbl.setStyleSheet("color: #7f8c8d; font-size: 11px;")
        th.addWidget(tlbl)
        th.addStretch()
        x_btn = QPushButton("✕")
        x_btn.setObjectName("tb_close")
        x_btn.clicked.connect(dlg.close)
        th.addWidget(x_btn)
        root.addWidget(tbar)

        # ── Body ──────────────────────────────────────────────────────────────
        body = QWidget()
        body.setStyleSheet("background: #1b1e22;")
        bv = QVBoxLayout(body)
        bv.setContentsMargins(20, 16, 20, 20)
        bv.setSpacing(10)

        app_title = QLabel("Kubuntu Setup Installer")
        app_title.setStyleSheet("font-size: 14px; font-weight: bold; color: #eff0f1;")
        bv.addWidget(app_title)

        author = QLabel("Made by <b>BeanGreen247</b>")
        author.setStyleSheet("color: #bdc3c7; font-size: 12px;")
        bv.addWidget(author)

        gh_lbl = QLabel('<a href="https://github.com/BeanGreen247" style="color:#3daee9;">github.com/BeanGreen247</a>')
        gh_lbl.setOpenExternalLinks(False)
        gh_lbl.setStyleSheet("font-size: 12px;")
        gh_lbl.linkActivated.connect(lambda url: QDesktopServices.openUrl(QUrl(url)))
        bv.addWidget(gh_lbl)

        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.HLine)
        sep.setStyleSheet("color: #3a3f44;")
        bv.addWidget(sep)

        gc_title = QLabel("Global git config:")
        gc_title.setStyleSheet("color: #7f8c8d; font-size: 11px;")
        bv.addWidget(gc_title)

        gc_path = QLabel(str(git_cfg))
        gc_path.setStyleSheet("font-family: monospace; font-size: 11px; color: #eff0f1;")
        gc_path.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        bv.addWidget(gc_path)

        exists_lbl = QLabel("(exists)" if git_cfg.exists() else "(not created yet)")
        exists_lbl.setStyleSheet(
            "color: #27ae60; font-size: 10px;" if git_cfg.exists()
            else "color: #f39c12; font-size: 10px;"
        )
        bv.addWidget(exists_lbl)

        bv.addSpacing(8)
        close_btn = QPushButton("Close")
        close_btn.clicked.connect(dlg.close)
        bv.addWidget(close_btn)

        root.addWidget(body)
        dlg.adjustSize()

        # centre over parent
        pg = self.window().geometry()
        dlg.move(
            pg.x() + (pg.width()  - dlg.width())  // 2,
            pg.y() + (pg.height() - dlg.height()) // 2,
        )
        dlg.show()

    def _show_help(self):
        dlg = QMainWindow(self.window())
        dlg.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.Dialog
        )
        dlg.setStyleSheet(self.window().styleSheet())
        dlg.setMinimumSize(900, 600)

        central = QWidget()
        dlg.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── Custom title bar ───────────────────────────────────────────────────────────────────
        tbar = QWidget()
        tbar.setObjectName("titlebar")
        tbar.setFixedHeight(36)
        th = QHBoxLayout(tbar)
        th.setContentsMargins(12, 0, 8, 0)
        th.setSpacing(8)
        tlbl = QLabel("Help — README")
        tlbl.setStyleSheet("color: #7f8c8d; font-size: 11px;")
        th.addWidget(tlbl)
        th.addStretch()
        x_btn = QPushButton("✕")
        x_btn.setObjectName("tb_close")
        x_btn.clicked.connect(dlg.close)
        th.addWidget(x_btn)
        root.addWidget(tbar)

        # ── Body ────────────────────────────────────────────────────────────────────────────
        viewer = QTextEdit()
        viewer.setReadOnly(True)
        viewer.setObjectName("help_viewer")
        viewer.setLineWrapMode(QTextEdit.LineWrapMode.WidgetWidth)
        viewer.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        viewer.setStyleSheet(
            "QTextEdit#help_viewer {"
            "  background: #1b1e22;"
            "  color: #eff0f1;"
            "  font-size: 13px;"
            "  border: none;"
            "  padding: 16px;"
            "}"
        )
        if README_PATH.exists():
            _img_re = re.compile(r"^!\[.*?\]\(.*?\)\s*$")
            lines = [
                ln for ln in README_PATH.read_text(encoding="utf-8").splitlines()
                if not _img_re.match(ln)
            ]
            viewer.setMarkdown("\n".join(lines))
        else:
            viewer.setPlainText("README.md not found next to this script.")
        root.addWidget(viewer)

        # centre over parent
        pg = self.window().geometry()
        dlg.resize(1000, 700)
        dlg.move(
            pg.x() + (pg.width()  - 1000) // 2,
            pg.y() + (pg.height() - 700)  // 2,
        )
        dlg.show()

    def _toggle_maximize(self):
        win = self.window()
        if win.isMaximized():
            win.showNormal()
            self._btn_max.setText("□")
        else:
            win.showMaximized()
            self._btn_max.setText("❐")

    def mouseDoubleClickEvent(self, ev):
        if ev.button() == Qt.MouseButton.LeftButton:
            self._toggle_maximize()

    def mousePressEvent(self, ev):
        if ev.button() == Qt.MouseButton.LeftButton and not self.window().isMaximized():
            self._drag_pos = (
                ev.globalPosition().toPoint() - self.window().frameGeometry().topLeft()
            )

    def mouseMoveEvent(self, ev):
        if self._drag_pos and ev.buttons() & Qt.MouseButton.LeftButton:
            self.window().move(ev.globalPosition().toPoint() - self._drag_pos)

    def mouseReleaseEvent(self, ev):
        self._drag_pos = None


# ── Changelog splash ──────────────────────────────────────────────────────────

class ChangelogDialog(QMainWindow):
    """Frameless startup splash that shows CHANGELOG.md then opens the installer."""

    def __init__(self, on_continue):
        super().__init__()
        self._on_continue = on_continue
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.Window
        )
        self.setMinimumSize(740, 520)
        self.resize(820, 600)

        root = QWidget()
        root.setObjectName("root")
        self.setCentralWidget(root)
        v = QVBoxLayout(root)
        v.setContentsMargins(0, 0, 0, 0)
        v.setSpacing(0)

        # ── Title bar ─────────────────────────────────────────────────────────
        tbar = QWidget()
        tbar.setObjectName("titlebar")
        tbar.setFixedHeight(36)
        self._drag_pos: QPoint | None = None
        th = QHBoxLayout(tbar)
        th.setContentsMargins(12, 0, 8, 0)
        th.setSpacing(8)
        title_lbl = QLabel("Kubuntu Setup  —  Changelog")
        title_lbl.setStyleSheet("color: #7f8c8d; font-size: 11px;")
        th.addWidget(title_lbl)
        ver = _local_version()
        if ver:
            ver_lbl = QLabel(ver)
            ver_lbl.setStyleSheet("color: #4a5056; font-size: 10px; font-family: monospace;")
            th.addWidget(ver_lbl)
        th.addStretch()
        v.addWidget(tbar)

        # ── Scrollable changelog text ──────────────────────────────────────────
        self._text = QTextEdit()
        self._text.setObjectName("log")
        self._text.setReadOnly(True)
        self._text.setStyleSheet(
            "QTextEdit#log { font-family: 'JetBrains Mono','Fira Code','Courier New',monospace;"
            " font-size: 11px; border: none; padding: 12px 16px; }"
        )
        self._load_changelog()
        v.addWidget(self._text, 1)

        # ── Footer ────────────────────────────────────────────────────────────
        v.addWidget(_hdivider())
        foot = QWidget()
        foot.setObjectName("root")
        fh = QHBoxLayout(foot)
        fh.setContentsMargins(16, 10, 16, 12)
        note = QLabel("Review the changes above, then click Continue to open the installer.")
        note.setObjectName("grp_detail")
        fh.addWidget(note, 1)
        fh.addSpacing(12)
        cont_btn = QPushButton("Continue  →")
        cont_btn.setObjectName("btn_primary")
        cont_btn.clicked.connect(self._continue)
        fh.addWidget(cont_btn)
        v.addWidget(foot)

        # Drag support on the title bar widget
        tbar.mousePressEvent   = self._tb_press
        tbar.mouseMoveEvent    = self._tb_move
        tbar.mouseReleaseEvent = self._tb_release

    def _load_changelog(self) -> None:
        if CHANGELOG_PATH.exists():
            text = CHANGELOG_PATH.read_text(encoding="utf-8")
        else:
            text = "(CHANGELOG.md not found)"
        # Render markdown-ish: colour date headers and bullet points
        html_lines = []
        for line in text.splitlines():
            if line.startswith("## "):
                html_lines.append(
                    f'<p style="color:#3daee9;font-weight:bold;margin:10px 0 2px 0;">'
                    f'{line[3:].strip()}</p>'
                )
            elif line.startswith("# "):
                html_lines.append(
                    f'<p style="color:#eff0f1;font-size:13px;font-weight:bold;margin:0 0 6px 0;">'
                    f'{line[2:].strip()}</p>'
                )
            elif line.startswith("- "):
                content = line[2:]
                # bold **text**
                content = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', content)
                # inline code `text`
                content = re.sub(
                    r'`([^`]+)`',
                    r'<span style="font-family:monospace;color:#a6e3a1;">\1</span>',
                    content,
                )
                html_lines.append(
                    f'<p style="color:#bdc3c7;margin:1px 0 1px 8px;">&#x2022;&nbsp;{content}</p>'
                )
            elif line.startswith("---"):
                html_lines.append('<hr style="border:none;border-top:1px solid #3a3f44;margin:6px 0;">')
            elif line.strip():
                html_lines.append(f'<p style="color:#7f8c8d;margin:2px 0;">{line}</p>')
        self._text.setHtml(
            '<body style="background:#1b1e20;">' + "".join(html_lines) + "</body>"
        )
        # Scroll to top
        self._text.verticalScrollBar().setValue(0)

    def _continue(self) -> None:
        self._on_continue()
        self.close()

    def _tb_press(self, ev):
        if ev.button() == Qt.MouseButton.LeftButton and not self.isMaximized():
            self._drag_pos = (
                ev.globalPosition().toPoint() - self.frameGeometry().topLeft()
            )

    def _tb_move(self, ev):
        if self._drag_pos and ev.buttons() & Qt.MouseButton.LeftButton:
            self.move(ev.globalPosition().toPoint() - self._drag_pos)

    def _tb_release(self, _ev):
        self._drag_pos = None


# ── Main window ────────────────────────────────────────────────────────────────

class InstallerWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.Window
        )
        self.setMinimumSize(1024, 768)
        self.resize(WIN_W, WIN_H)

        self._gpu              = GPU_OPTIONS[0][0]
        self._profile          = PROFILE_OPTIONS[0][0]
        self._process: QProcess | None = None
        self._step_logs        = [[] for _ in INSTALL_GROUPS]
        self._step_states      = [STEP_PENDING] * len(INSTALL_GROUPS)
        self._active_idx       = -1
        self._selected_idx     = 0
        self._done_count       = 0
        self._sent_confirm     = False
        self._sent_compat      = False

        root = QWidget()
        root.setObjectName("root")
        self.setCentralWidget(root)

        vbox = QVBoxLayout(root)
        vbox.setContentsMargins(0, 0, 0, 0)
        vbox.setSpacing(0)

        vbox.addWidget(TitleBar("Kubuntu Setup"))

        self._stack = QStackedWidget()
        vbox.addWidget(self._stack, 1)

        self._stack.addWidget(self._build_welcome())  # 0
        self._stack.addWidget(self._build_install())  # 1
        self._stack.addWidget(self._build_done())     # 2

    # ── Page 0: Welcome ────────────────────────────────────────────────────────

    def _build_welcome(self) -> QWidget:
        page = QWidget()
        page.setObjectName("root")
        outer = QHBoxLayout(page)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        outer.addWidget(self._welcome_left())
        outer.addWidget(_vdivider())
        outer.addWidget(self._welcome_right(), 1)
        self._select_group(0)
        return page

    def _welcome_left(self) -> QWidget:
        panel = QWidget()
        panel.setObjectName("root")
        panel.setFixedWidth(420)
        v = QVBoxLayout(panel)
        v.setContentsMargins(28, 24, 16, 24)
        v.setSpacing(0)

        title = QLabel("Kubuntu Setup")
        title.setObjectName("app_title")
        sub = QLabel("by BeanGreen247  ·  github.com/BeanGreen247/kubuntu-setup")
        sub.setObjectName("app_sub")
        v.addWidget(title)
        v.addWidget(sub)
        v.addSpacing(12)
        v.addWidget(_hdivider())
        v.addSpacing(10)

        hdr = QLabel("What will be installed")
        hdr.setObjectName("sec_hdr")
        v.addWidget(hdr)
        v.addSpacing(6)

        # Scrollable group list
        container = QWidget()
        container.setObjectName("root")
        cv = QVBoxLayout(container)
        cv.setContentsMargins(0, 0, 4, 0)
        cv.setSpacing(2)

        self._grp_btns: list[QPushButton] = []
        for i, (icon, label, size_mb, _) in enumerate(INSTALL_GROUPS):
            row = QWidget()
            row.setObjectName("root")
            rh = QHBoxLayout(row)
            rh.setContentsMargins(0, 0, 0, 0)
            rh.setSpacing(0)

            btn = QPushButton(f"{icon}  {label}")
            btn.setObjectName("step_btn")
            btn.setCheckable(True)
            btn.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
            )
            btn.clicked.connect(lambda _, i=i: self._select_group(i))

            sz = QLabel(_size_str(size_mb))
            sz.setObjectName("size_badge")
            sz.setFixedWidth(56)
            sz.setAlignment(
                Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter
            )

            rh.addWidget(btn, 1)
            rh.addWidget(sz)
            cv.addWidget(row)
            self._grp_btns.append(btn)

        cv.addStretch()

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setWidget(container)
        v.addWidget(scroll, 1)

        v.addSpacing(8)
        total_lbl = QLabel(f"Estimated disk usage:  ~{TOTAL_MB / 1024:.1f} GB")
        total_lbl.setObjectName("size_total")
        v.addWidget(total_lbl)

        return panel

    def _welcome_right(self) -> QWidget:
        panel = QWidget()
        panel.setObjectName("root")
        v = QVBoxLayout(panel)
        v.setContentsMargins(24, 24, 28, 24)
        v.setSpacing(10)

        self._dtl_title = QLabel()
        self._dtl_title.setObjectName("detail_title")
        v.addWidget(self._dtl_title)

        self._dtl_body = QLabel()
        self._dtl_body.setObjectName("body")
        self._dtl_body.setWordWrap(True)
        self._dtl_body.setAlignment(
            Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignLeft
        )
        v.addWidget(self._dtl_body, 1)

        v.addWidget(_hdivider())

        gpu_row = QHBoxLayout()
        lbl_gpu = QLabel("GPU type:")
        lbl_gpu.setObjectName("sec_hdr")
        lbl_gpu.setFixedWidth(80)
        self._gpu_combo = QComboBox()
        for val, lbl in GPU_OPTIONS:
            self._gpu_combo.addItem(lbl, val)
        self._gpu_combo.currentIndexChanged.connect(self._on_gpu_changed)
        gpu_row.addWidget(lbl_gpu)
        gpu_row.addWidget(self._gpu_combo, 1)
        v.addLayout(gpu_row)

        v.addSpacing(6)
        profile_row = QHBoxLayout()
        lbl_profile = QLabel("Profile:")
        lbl_profile.setObjectName("sec_hdr")
        lbl_profile.setFixedWidth(80)
        self._profile_combo = QComboBox()
        for val, lbl in PROFILE_OPTIONS:
            self._profile_combo.addItem(lbl, val)
        self._profile_combo.currentIndexChanged.connect(
            lambda i: setattr(self, "_profile", self._profile_combo.itemData(i))
        )
        profile_row.addWidget(lbl_profile)
        profile_row.addWidget(self._profile_combo, 1)
        v.addLayout(profile_row)

        v.addSpacing(10)

        # ── Git global config ──────────────────────────────────────────────
        lbl_git = QLabel("Git identity  (optional)")
        lbl_git.setObjectName("sec_hdr")
        v.addWidget(lbl_git)
        v.addSpacing(6)

        git_grid = QVBoxLayout()
        git_grid.setSpacing(6)

        row_name = QHBoxLayout()
        lbl_gn = QLabel("Name:")
        lbl_gn.setObjectName("body")
        lbl_gn.setFixedWidth(52)
        self._git_name = QLineEdit()
        self._git_name.setPlaceholderText("Jane Smith")
        row_name.addWidget(lbl_gn)
        row_name.addWidget(self._git_name, 1)

        row_email = QHBoxLayout()
        lbl_ge = QLabel("Email:")
        lbl_ge.setObjectName("body")
        lbl_ge.setFixedWidth(52)
        self._git_email = QLineEdit()
        self._git_email.setPlaceholderText("jane@example.com")
        row_email.addWidget(lbl_ge)
        row_email.addWidget(self._git_email, 1)

        git_grid.addLayout(row_name)
        git_grid.addLayout(row_email)
        v.addLayout(git_grid)

        v.addSpacing(4)
        lbl_git_note = QLabel("Written to ~/.gitconfig before install starts.")
        lbl_git_note.setObjectName("grp_detail")
        lbl_git_note.setWordWrap(True)
        v.addWidget(lbl_git_note)

        v.addWidget(_hdivider())

        btn_row = QHBoxLayout()
        b_gh = QPushButton("GitHub")
        b_gh.setObjectName("btn_outline")
        b_gh.clicked.connect(lambda: webbrowser.open(GITHUB_URL))

        self._update_btn = QPushButton("Check for updates")
        self._update_btn.setObjectName("btn_outline")
        self._update_btn.clicked.connect(self._check_updates)
        if not shutil.which("git"):
            self._update_btn.setEnabled(False)
            self._update_btn.setToolTip("git not found")

        self._install_btn = QPushButton("Install")
        self._install_btn.setObjectName("btn_primary")
        self._install_btn.clicked.connect(self._start_install)
        if not SCRIPT_PATH.exists():
            self._install_btn.setEnabled(False)
            self._install_btn.setToolTip(
                f"setup-kubuntu.sh not found:\n{SCRIPT_PATH}"
            )

        b_exit = QPushButton("Exit")
        b_exit.setObjectName("btn_danger")
        b_exit.clicked.connect(QApplication.quit)

        btn_row.addWidget(b_gh)
        btn_row.addSpacing(6)
        btn_row.addWidget(self._update_btn)
        btn_row.addStretch()
        btn_row.addWidget(self._install_btn)
        btn_row.addSpacing(8)
        btn_row.addWidget(b_exit)
        v.addLayout(btn_row)

        return panel

    def _select_group(self, idx: int) -> None:
        for i, btn in enumerate(self._grp_btns):
            btn.setChecked(i == idx)
        icon, label, size_mb, items = INSTALL_GROUPS[idx]
        self._dtl_title.setText(f"{icon}  {label}  ·  {_size_str(size_mb)}")
        self._dtl_body.setText("\n".join(f"  ·  {item}" for item in items))

    # ── Git config ─────────────────────────────────────────────────────────────

    def _apply_git_config(self) -> None:
        name  = self._git_name.text().strip()
        email = self._git_email.text().strip()
        if name:
            subprocess.run(["git", "config", "--global", "user.name",  name],  check=False)
        if email:
            subprocess.run(["git", "config", "--global", "user.email", email], check=False)
        for key, val in [
            ("core.editor",          "vim"),
            ("pull.rebase",          "true"),
            ("init.defaultBranch",   "main"),
            ("push.autoSetupRemote", "true"),
            ("core.autocrlf",        "input"),
        ]:
            subprocess.run(["git", "config", "--global", key, val], check=False)

    # ── GPU selection ──────────────────────────────────────────────────────────

    def _on_gpu_changed(self, i: int) -> None:
        self._gpu = self._gpu_combo.itemData(i)

    # ── Update check ───────────────────────────────────────────────────────────

    def _check_updates(self) -> None:
        self._update_btn.setEnabled(False)
        self._update_btn.setText("Checking\u2026")

        self._upd_proc = QProcess(self)
        self._upd_proc.setWorkingDirectory(str(REPO_DIR))
        self._upd_proc.finished.connect(self._on_update_check_done)
        self._upd_proc.start("git", ["fetch", "origin", "--quiet"])

    def _on_update_check_done(self) -> None:
        self._update_btn.setEnabled(True)
        self._update_btn.setText("Check for updates")

        behind_str = _git(["rev-list", "--count", "HEAD..origin/main"])
        behind = int(behind_str) if behind_str.isdigit() else 0

        if behind == 0:
            self._dtl_title.setText("Up to date")
            self._dtl_body.setText(
                f"  \u00b7  Local commit: {_local_version() or 'unknown'}\n"
                "  \u00b7  No new commits on origin/main."
            )
            return

        # There are updates — show changelog in the detail panel
        changelog = _git(["log", "--oneline", "HEAD..origin/main"])
        changed   = _git(["diff", "--name-only", "HEAD..origin/main"])
        rerun     = "setup-kubuntu.sh" in changed

        word = "update" if behind == 1 else "updates"
        self._dtl_title.setText(f"{behind} {word} available")
        body_lines = [f"  \u00b7  {line}" for line in changelog.splitlines()[:10]]
        if rerun:
            body_lines.append("")
            body_lines.append("  \u26a0  setup-kubuntu.sh changed — re-run Install after updating.")
        body_lines.append("")
        body_lines.append("  Run:  bash ~/kubuntu-setup/install.sh  to apply.")
        self._dtl_body.setText("\n".join(body_lines))
    # ── Page 1: Install ────────────────────────────────────────────────────────

    def _build_install(self) -> QWidget:
        page = QWidget()
        page.setObjectName("root")
        pv = QVBoxLayout(page)
        pv.setContentsMargins(24, 18, 24, 16)
        pv.setSpacing(10)

        hdr = QLabel("Installing Kubuntu…")
        hdr.setObjectName("app_title")
        pv.addWidget(hdr)

        split = QSplitter(Qt.Orientation.Horizontal)
        split.setHandleWidth(1)
        split.addWidget(self._install_step_panel())
        split.addWidget(self._install_detail_panel())
        split.setSizes([224, WIN_W - 248])
        pv.addWidget(split, 1)

        pv.addWidget(_hdivider())

        bot = QHBoxLayout()
        self._prog_label = QLabel("Waiting for root authentication…")
        self._prog_label.setObjectName("grp_detail")
        self._prog_bar = QProgressBar()
        self._prog_bar.setRange(0, len(INSTALL_GROUPS))
        self._prog_bar.setValue(0)
        self._prog_bar.setFixedHeight(22)
        bot.addWidget(self._prog_label)
        bot.addSpacing(16)
        bot.addWidget(self._prog_bar, 1)
        bot.addSpacing(16)
        self._next_btn = QPushButton("Next →")
        self._next_btn.setObjectName("btn_primary")
        self._next_btn.setFixedWidth(100)
        self._next_btn.setEnabled(False)
        self._next_btn.clicked.connect(lambda: self._stack.setCurrentIndex(2))
        bot.addWidget(self._next_btn)
        pv.addLayout(bot)

        self._show_step(0)
        return page

    def _install_step_panel(self) -> QWidget:
        container = QWidget()
        container.setObjectName("root")
        cv = QVBoxLayout(container)
        cv.setContentsMargins(0, 0, 0, 0)
        cv.setSpacing(2)

        self._step_btns: list[QPushButton] = []
        self._step_icos: list[QLabel]      = []

        for i, (icon, label, _, _) in enumerate(INSTALL_GROUPS):
            row = QWidget()
            row.setObjectName("root")
            rh = QHBoxLayout(row)
            rh.setContentsMargins(0, 0, 0, 0)
            rh.setSpacing(4)

            ico = QLabel("○")
            ico.setObjectName("st_pending")
            ico.setFixedWidth(16)
            ico.setAlignment(Qt.AlignmentFlag.AlignCenter)

            btn = QPushButton(f"{icon}  {label}")
            btn.setObjectName("step_btn")
            btn.setCheckable(True)
            btn.setSizePolicy(
                QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
            )
            btn.clicked.connect(lambda _, i=i: self._show_step(i))

            rh.addWidget(ico)
            rh.addWidget(btn, 1)
            cv.addWidget(row)
            self._step_btns.append(btn)
            self._step_icos.append(ico)

        cv.addStretch()

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setWidget(container)

        wrap = QWidget()
        wrap.setObjectName("root")
        wrap.setFixedWidth(224)
        wv = QVBoxLayout(wrap)
        wv.setContentsMargins(0, 0, 0, 0)
        wv.addWidget(scroll)

        # ── Done tile (shown below the step list, activated on finish) ──────
        done_row = QWidget()
        done_row.setObjectName("root")
        dr = QHBoxLayout(done_row)
        dr.setContentsMargins(0, 4, 0, 0)
        dr.setSpacing(4)

        self._done_tile_ico = QLabel("○")
        self._done_tile_ico.setObjectName("st_pending")
        self._done_tile_ico.setFixedWidth(16)
        self._done_tile_ico.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self._done_tile_btn = QPushButton("✦  Done")
        self._done_tile_btn.setObjectName("step_btn")
        self._done_tile_btn.setCheckable(True)
        self._done_tile_btn.setEnabled(False)
        self._done_tile_btn.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred
        )
        self._done_tile_btn.clicked.connect(self._show_done_tile)

        dr.addWidget(self._done_tile_ico)
        dr.addWidget(self._done_tile_btn, 1)
        wv.addWidget(done_row)
        return wrap

    def _install_detail_panel(self) -> QWidget:
        panel = QWidget()
        panel.setObjectName("root")
        dv = QVBoxLayout(panel)
        dv.setContentsMargins(16, 0, 0, 0)
        dv.setSpacing(8)

        self._d_title = QLabel()
        self._d_title.setObjectName("detail_title")
        dv.addWidget(self._d_title)

        self._d_items = QLabel()
        self._d_items.setObjectName("grp_detail")
        self._d_items.setWordWrap(True)
        dv.addWidget(self._d_items)

        dv.addWidget(_hdivider())

        self._log_view = QTextEdit()
        self._log_view.setObjectName("log")
        self._log_view.setReadOnly(True)
        dv.addWidget(self._log_view, 1)

        return panel

    def _show_step(self, idx: int) -> None:
        self._selected_idx = idx
        for i, btn in enumerate(self._step_btns):
            btn.setChecked(i == idx)
        self._done_tile_btn.setChecked(False)

        icon, label, size_mb, items = INSTALL_GROUPS[idx]
        self._d_title.setText(f"{icon}  {label}  ·  {_size_str(size_mb)}")
        self._d_items.setText("  ·  " + "   ·  ".join(items))

        self._log_view.clear()
        for line in self._step_logs[idx]:
            self._append_log(line)

    def _show_done_tile(self) -> None:
        for btn in self._step_btns:
            btn.setChecked(False)
        self._done_tile_btn.setChecked(True)

        passed  = sum(1 for s in self._step_states if s == STEP_DONE)
        warned  = sum(1 for s in self._step_states if s == STEP_WARN)
        failed  = len(self._step_states) - passed - warned
        elapsed = getattr(self, "_elapsed_str", "")
        self._d_title.setText("✦  Installation complete")
        lines = []
        lines.append(f"  ·  {passed} passed   {warned} warnings   {failed} failed")
        if elapsed:
            lines.append(f"  ·  Total time: {elapsed}")
        lines.append("")
        lines.append("  ·  Reboot to activate GPU, kernel, and performance changes.")
        lines.append("  ·  Post-login setup will run automatically on first login.")
        self._d_items.setText("\n".join(lines))
        # Show the full run summary (last section contains the SETUP COMPLETE
        # banner + every ✓ / ! / ✗ line the script printed after finishing)
        self._log_view.clear()
        for line in self._step_logs[-1]:
            self._append_log(line)

    # ── Page 2: Done ───────────────────────────────────────────────────────────

    def _build_done(self) -> QWidget:
        page = QWidget()
        page.setObjectName("root")
        v = QVBoxLayout(page)
        v.setContentsMargins(52, 60, 52, 48)
        v.setSpacing(14)

        self._done_title = QLabel("✓  Setup Complete")
        self._done_title.setObjectName("app_title")
        v.addWidget(self._done_title)

        self._done_body = QLabel(
            "All 15 sections finished successfully.\n"
            "Reboot to activate all kernel, GPU, and performance changes."
        )
        self._done_body.setObjectName("body")
        self._done_body.setWordWrap(True)
        v.addWidget(self._done_body)

        v.addSpacing(16)
        v.addWidget(_hdivider())
        v.addSpacing(12)

        lbl_res = QLabel("Resources")
        lbl_res.setObjectName("sec_hdr")
        v.addWidget(lbl_res)

        for text, url in (
            (f"📦  Setup script  —  {GITHUB_URL}",  GITHUB_URL),
            (f"📁  Dotfiles      —  {DOTFILES_URL}", DOTFILES_URL),
        ):
            lnk = QLabel(f'<a href="{url}" style="color:#89b4fa;">{text}</a>')
            lnk.setOpenExternalLinks(True)
            lnk.setObjectName("body")
            v.addWidget(lnk)

        v.addStretch()

        br = QHBoxLayout()
        br.addStretch()
        close_btn = QPushButton("Close")
        close_btn.setObjectName("btn_primary")
        close_btn.clicked.connect(self.close)
        br.addWidget(close_btn)
        v.addLayout(br)

        return page

    # ── Install runner ─────────────────────────────────────────────────────────

    def _start_install(self) -> None:
        self._install_btn.setEnabled(False)
        self._stack.setCurrentIndex(1)

        # Reset per-run state
        self._step_logs      = [[] for _ in INSTALL_GROUPS]
        self._step_states    = [STEP_PENDING] * len(INSTALL_GROUPS)
        self._active_idx     = -1
        self._done_count     = 0
        self._sent_confirm   = False
        self._sent_compat    = False
        self._next_btn.setEnabled(False)
        for i in range(len(INSTALL_GROUPS)):
            self._set_step_state(i, STEP_PENDING)
        self._prog_bar.setValue(0)
        self._prog_label.setText("Waiting for root authentication…")
        self._elapsed_str = ""
        # Reset Done tile
        self._done_tile_ico.setText("○")
        self._done_tile_ico.setObjectName("st_pending")
        self._done_tile_ico.setStyleSheet("")
        self._done_tile_ico.style().polish(self._done_tile_ico)
        self._done_tile_btn.setText("✦  Done")
        self._done_tile_btn.setEnabled(False)
        self._done_tile_btn.setChecked(False)
        self._show_step(0)

        self._process = QProcess(self)
        self._process.setProcessChannelMode(
            QProcess.ProcessChannelMode.MergedChannels
        )
        self._process.readyReadStandardOutput.connect(self._on_output)
        self._process.finished.connect(self._on_finished)

        env = QProcessEnvironment.systemEnvironment()
        env.insert("TERM", "xterm-256color")
        self._process.setProcessEnvironment(env)

        # Pass GPU, username, and --yes as CLI args — avoids stdin/tty issues under pkexec
        # read -rp writes its prompt to the controlling terminal, not the pipe,
        # so the GUI would never see it; --yes skips all interactive read prompts.
        current_user = os.getenv("USER") or os.getenv("LOGNAME") or ""
        extra_args = [f"--gpu={self._gpu}", f"--profile={self._profile}", "--yes"]
        if current_user and current_user != "root":
            extra_args.append(f"--user={current_user}")

        # Apply git config before elevation (runs as the current user)
        self._apply_git_config()

        # Elevation: pkexec (polkit, standard on KDE) → kdesu → abort
        if shutil.which("pkexec"):
            self._process.start(
                    "pkexec", ["bash", str(SCRIPT_PATH)] + extra_args
                )
        elif shutil.which("kdesu"):
            self._process.start(
                "kdesu", ["--", "bash", str(SCRIPT_PATH)] + extra_args
            )
        else:
            self._prog_label.setText(
                "No elevation tool found. Run: sudo python3 setup-installer.py"
            )
            self._install_btn.setEnabled(True)
            self._stack.setCurrentIndex(0)

    def _on_output(self) -> None:
        raw = bytes(self._process.readAllStandardOutput()).decode(
            "utf-8", errors="replace"
        )
        for raw_line in raw.splitlines():
            line = ANSI_RE.sub("", raw_line).strip()
            if not line:
                continue
            self._handle_prompts(line)
            self._update_active_step(line)

            # Capture elapsed time from the script's summary line
            if line.startswith("Total:"):
                self._elapsed_str = line.split("Total:", 1)[1].strip().split("—")[0].strip()

            idx = max(0, self._active_idx)
            self._step_logs[idx].append(line)
            if idx == self._selected_idx:
                self._append_log(line)

    def _handle_prompts(self, line: str) -> None:
        if not self._sent_confirm and "Continue?" in line and "[y/N]" in line:
            QTimer.singleShot(120, lambda: self._process.write(b"y\n"))
            self._sent_confirm = True
        elif not self._sent_compat and "Continue anyway?" in line:
            QTimer.singleShot(120, lambda: self._process.write(b"y\n"))
            self._sent_compat = True
        elif "Remove cache now?" in line:
            QTimer.singleShot(120, lambda: self._process.write(b"n\n"))

    def _update_active_step(self, line: str) -> None:
        m = SECTION_RE.search(line)
        if not m:
            return
        new_idx = int(m.group(1)) - 1
        if new_idx < 0 or new_idx >= len(INSTALL_GROUPS):
            return
        if self._active_idx >= 0 and self._active_idx != new_idx:
            self._set_step_state(self._active_idx, STEP_DONE)
        self._active_idx = new_idx
        self._set_step_state(new_idx, STEP_RUNNING)
        self._prog_label.setText(
            f"[{new_idx + 1}/{len(INSTALL_GROUPS)}]  "
            f"{INSTALL_GROUPS[new_idx][1]}"
        )

    def _set_step_state(self, idx: int, state: int) -> None:
        self._step_states[idx] = state
        ico = self._step_icos[idx]
        ico.setText(_STEP_ICON[state])
        ico.setObjectName(_STEP_CLASS[state])
        ico.setStyleSheet("")       # force QSS re-evaluation
        ico.style().polish(ico)
        if state in (STEP_DONE, STEP_WARN):
            self._done_count += 1
            self._prog_bar.setValue(self._done_count)

    def _append_log(self, line: str) -> None:
        if "✓" in line:
            colour = "#a6e3a1"
        elif "⚠" in line:
            colour = "#fab387"
        elif "✗" in line:
            colour = "#f38ba8"
        elif "→" in line:
            colour = "#89dceb"
        else:
            colour = "#cdd6f4"

        cur = self._log_view.textCursor()
        cur.movePosition(QTextCursor.MoveOperation.End)
        fmt = cur.charFormat()
        fmt.setForeground(QColor(colour))
        cur.setCharFormat(fmt)
        cur.insertText(line + "\n")
        self._log_view.setTextCursor(cur)
        self._log_view.ensureCursorVisible()

    def _on_finished(self, exit_code: int, _status) -> None:
        # pkexec returns 126 on auth cancel, 127 if not found
        if exit_code in (126, 127):
            self._prog_label.setText("Authentication cancelled — click Install to retry.")
            self._install_btn.setEnabled(True)
            self._stack.setCurrentIndex(0)
            return

        if self._active_idx >= 0:
            self._set_step_state(self._active_idx, STEP_DONE)
        self._prog_bar.setValue(len(INSTALL_GROUPS))

        if exit_code == 0:
            self._done_title.setText("✓  Setup Complete")
            self._done_body.setText(
                "All 15 sections finished successfully.\n"
                "Reboot to activate all kernel, GPU, and performance changes."
            )
        else:
            self._done_title.setText("⚠  Setup Finished with Warnings")
            self._done_body.setText(
                f"Setup finished (exit {exit_code}).\n"
                "Some optional steps may need attention — check the log on the previous screen."
            )

        subprocess.run(
            [
                "notify-send", "-u", "normal", "-i", "applications-system",
                "Kubuntu Setup", "Installation complete!",
            ],
            check=False,
        )
        self._next_btn.setEnabled(True)
        self._prog_label.setText("Done — click Next → to continue.")

        # Activate Done tile
        passed = sum(1 for s in self._step_states if s == STEP_DONE)
        warned = sum(1 for s in self._step_states if s == STEP_WARN)
        ico_state = STEP_DONE if exit_code == 0 else STEP_WARN
        self._done_tile_ico.setText(_STEP_ICON[ico_state])
        self._done_tile_ico.setObjectName(_STEP_CLASS[ico_state])
        self._done_tile_ico.setStyleSheet("")
        self._done_tile_ico.style().polish(self._done_tile_ico)
        self._done_tile_btn.setText(f"✦  Done  ({passed}✓ {warned}⚠)")
        self._done_tile_btn.setEnabled(True)
        self._done_tile_btn.click()


# ── Entry point ────────────────────────────────────────────────────────────────

def main() -> None:
    # Force X11/XCB platform so FramelessWindowHint works correctly.
    # Under KDE Wayland the window manager re-decorates frameless windows;
    # xcb bypasses that entirely and lets us draw our own title bar.
    if "QT_QPA_PLATFORM" not in os.environ:
        os.environ["QT_QPA_PLATFORM"] = "xcb"

    app = QApplication(sys.argv)
    app.setApplicationName("Kubuntu Setup")
    app.setStyleSheet(QSS)

    if not SCRIPT_PATH.exists():
        from PyQt6.QtWidgets import QMessageBox
        QMessageBox.critical(
            None,
            "Script not found",
            f"Cannot find setup-kubuntu.sh:\n{SCRIPT_PATH}\n\n"
            "Run this app from the kubuntu-setup repository directory.",
        )
        sys.exit(1)

    screen = app.primaryScreen().availableGeometry()

    def _open_installer():
        win = InstallerWindow()
        win.move(
            (screen.width()  - win.width())  // 2,
            (screen.height() - win.height()) // 2,
        )
        win.show()
        # Keep a reference so GC doesn't destroy it
        app._main_win = win  # noqa: SLF001

    splash = ChangelogDialog(on_continue=_open_installer)
    splash.move(
        (screen.width()  - splash.width())  // 2,
        (screen.height() - splash.height()) // 2,
    )
    splash.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
