#!/usr/bin/env python3
"""
post-login-setup.py — Kubuntu first-login setup GUI

Shows a welcome screen then streams the --post-login bash script output
in real time, tracking per-step progress.

Requirements: python3-pyqt6 (installed by setup-kubuntu.sh)
"""

import os
import re
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import QPoint, QProcess, QProcessEnvironment, Qt, QTimer
from PyQt6.QtGui import QColor, QTextCursor
from PyQt6.QtWidgets import (
    QApplication,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QProgressBar,
    QPushButton,
    QStackedWidget,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

# ── Constants ──────────────────────────────────────────────────────────────────

# Prefer the repo copy (same dir as this .py) so changes are always picked up;
# fall back to the installed copy in ~/.local/bin.
_REPO_SCRIPT = Path(__file__).resolve().parent / "setup-kubuntu.sh"
SCRIPT_PATH  = _REPO_SCRIPT if _REPO_SCRIPT.exists() else Path.home() / ".local" / "bin" / "setup-kubuntu.sh"
_INSTALLED   = Path.home() / ".local" / "bin" / "setup-kubuntu.sh"
GITHUB_URL   = "https://github.com/BeanGreen247/kubuntu-setup"
DOTFILES_URL = "https://github.com/BeanGreen247/dotfiles"
WIN_W, WIN_H = 960, 560

DONE_FLAG = Path.home() / ".local" / "share" / "kubuntu-setup" / ".post-login-done"

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[mK]")

# (id, display label, short description, trigger substring, done substring)
STEPS = [
    (
        "wine_init",
        "Wine prefix",
        "Create ~/.wine (win64)",
        "Initialising Wine prefix",
        "Wine prefix created",
    ),
    (
        "winetricks",
        "winetricks",
        "corefonts · vcrun2019 · d3dcompiler_47",
        "Installing corefonts",
        "winetricks components installed",
    ),
    (
        "dotfile",
        "dotfile-sync timer",
        "12-hour auto-sync timer",
        "dotfile-sync timer",
        "dotfile-sync timer registered",
    ),
    (
        "power",
        "KDE power profile",
        "Balanced profile on AC + battery",
        "Applying KDE power profile",
        "Power profiles:",
    ),
    (
        "kwin_tweaks",
        "KWin tweaks",
        "OpenGL · adaptive vsync · low latency",
        "Applying KWin compositor",
        "KWin:",
    ),
    (
        "kde_appearance",
        "KDE appearance",
        "dark mode · no splash · all effects off · no launch feedback · no shadows · Baloo off · activities off · no recent-docs · classic kicker menu · panel cleaned · clock+seconds",
        "Applying KDE appearance",
        "KDE appearance:",
    ),
]

STEP_PENDING = 0
STEP_RUNNING = 1
STEP_DONE    = 2
STEP_WARN    = 3

_STEP_ICON  = {STEP_PENDING: "○", STEP_RUNNING: "◎", STEP_DONE: "✓", STEP_WARN: "⚠"}
_STEP_CLASS = {
    STEP_PENDING: "st_pending",
    STEP_RUNNING: "st_running",
    STEP_DONE:    "st_done",
    STEP_WARN:    "st_warn",
}

# ── Stylesheet ─────────────────────────────────────────────────────────────────

QSS_INPUT = """
QLineEdit {
    background: #1b1e20; color: #eff0f1;
    border: 1px solid #3a3f44; border-radius: 3px;
    padding: 6px 10px; font-size: 12px;
}
QLineEdit:focus { border-color: #3daee9; }
QLineEdit:placeholder { color: #4a5056; }
"""

QSS = """
QMainWindow, QWidget#root { background: #232629; }
QWidget#titlebar  { background: #1b1e20; border-bottom: 1px solid #3a3f44; }
QFrame#divider    { background: #3a3f44; max-height: 1px; }

QLabel#title   { color: #eff0f1; font-size: 16px; font-weight: bold; }
QLabel#author  { color: #7f8c8d; font-size: 11px; }
QLabel#section { color: #3daee9; font-size: 13px; font-weight: bold; }
QLabel#body    { color: #bdc3c7; font-size: 12px; }

QLabel#step_name { color: #eff0f1; font-size: 12px; }
QLabel#step_desc { color: #4a5056; font-size: 11px; }

QLabel#st_pending { color: #4a5056; font-size: 15px; }
QLabel#st_running { color: #f67400; font-size: 15px; }
QLabel#st_done    { color: #27ae60; font-size: 15px; }
QLabel#st_warn    { color: #f67400; font-size: 15px; }

QPushButton#primary {
    background: #3daee9; color: #1b1e20;
    border: none; border-radius: 4px;
    padding: 10px 32px; font-size: 13px; font-weight: bold;
}
QPushButton#primary:hover    { background: #56b9ec; }
QPushButton#primary:pressed  { background: #2b9dc8; }
QPushButton#primary:disabled { background: #3a3f44; color: #4a5056; }

QPushButton#tb_close {
    background: transparent; color: #7f8c8d; border: none;
    font-size: 14px; padding: 0 4px;
}
QPushButton#tb_close:hover { color: #da4453; }

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
    font-family: "JetBrains Mono", "Fira Code", "Courier New", monospace;
    font-size: 11px;
}

QProgressBar {
    background: #1b1e20; border: 1px solid #3a3f44;
    height: 22px; color: transparent; text-align: center;
}
QProgressBar::chunk { background: #3daee9; }
"""


# ── Custom title bar (matches setup-installer.py) ─────────────────────────────

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
        h.addStretch()

        close_btn = QPushButton("✕")
        close_btn.setObjectName("tb_close")
        close_btn.clicked.connect(QApplication.quit)
        h.addWidget(close_btn)

    def mousePressEvent(self, ev):
        if ev.button() == Qt.MouseButton.LeftButton:
            self._drag_pos = (
                ev.globalPosition().toPoint() - self.window().frameGeometry().topLeft()
            )

    def mouseMoveEvent(self, ev):
        if self._drag_pos and ev.buttons() & Qt.MouseButton.LeftButton:
            self.window().move(ev.globalPosition().toPoint() - self._drag_pos)

    def mouseReleaseEvent(self, ev):
        self._drag_pos = None


# ── Main window ──────────────────────────────────────────────────────────────

class SetupWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.Window
        )
        self.setWindowTitle("Kubuntu Post-Login Setup")
        self.setFixedSize(WIN_W, WIN_H)

        self._process: QProcess | None = None
        self._step_states  = {s[0]: STEP_PENDING for s in STEPS}
        self._step_icons:  dict[str, QLabel] = {}
        self._steps_done   = 0
        self._exit_code    = 0

        # Fallback: remove the autostart entry 30 min after launch in case
        # the window is closed before _on_finished fires.
        self._autostart_cleanup_timer = QTimer(self)
        self._autostart_cleanup_timer.setSingleShot(True)
        self._autostart_cleanup_timer.timeout.connect(self._remove_autostart)
        self._autostart_cleanup_timer.start(30 * 60 * 1000)  # 30 minutes

        root = QWidget()
        root.setObjectName("root")
        self.setCentralWidget(root)

        layout = QVBoxLayout(root)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        layout.addWidget(TitleBar("Kubuntu Post-Login Setup"))

        self._stack = QStackedWidget(root)
        layout.addWidget(self._stack, 1)

        self._stack.addWidget(self._page_git_config()) # 0
        self._stack.addWidget(self._page_welcome())    # 1
        self._stack.addWidget(self._page_running())    # 2
        self._stack.addWidget(self._page_done())       # 3

    # ── Page: Git Config ──────────────────────────────────────────────────────

    def _page_git_config(self) -> QWidget:
        page = QWidget(); page.setObjectName("root")
        v = QVBoxLayout(page)
        v.setContentsMargins(52, 48, 52, 36)
        v.setSpacing(0)

        lbl_title = QLabel("Git Global Configuration")
        lbl_title.setObjectName("title")
        v.addWidget(lbl_title)

        lbl_sub = QLabel("Optional — sets user.name, user.email and sensible defaults")
        lbl_sub.setObjectName("author")
        v.addWidget(lbl_sub)

        v.addSpacing(22)
        v.addWidget(_divider())
        v.addSpacing(20)

        def _field(label: str, placeholder: str) -> tuple[QLabel, QLineEdit]:
            lbl = QLabel(label)
            lbl.setObjectName("step_name")
            inp = QLineEdit()
            inp.setPlaceholderText(placeholder)
            inp.setStyleSheet(QSS_INPUT)
            return lbl, inp

        lbl_name, self._git_name = _field("Full name", "Jane Smith")
        lbl_email, self._git_email = _field("Email address", "jane@example.com")

        for lbl, inp in ((lbl_name, self._git_name), (lbl_email, self._git_email)):
            v.addWidget(lbl)
            v.addSpacing(4)
            v.addWidget(inp)
            v.addSpacing(14)

        v.addSpacing(6)
        v.addWidget(_divider())
        v.addSpacing(12)

        lbl_note = QLabel(
            "These values are written to ~/.gitconfig and apply to every repository.\n"
            "Click \"Skip\" to leave your git config unchanged."
        )
        lbl_note.setObjectName("body")
        lbl_note.setWordWrap(True)
        v.addWidget(lbl_note)

        v.addStretch()

        btn_row = QHBoxLayout()
        skip_btn = QPushButton("Skip")
        skip_btn.setObjectName("primary")
        skip_btn.setStyleSheet(
            "QPushButton#primary { background: #3a3f44; color: #bdc3c7; }"
            "QPushButton#primary:hover { background: #4a5056; }"
        )
        skip_btn.clicked.connect(lambda: self._stack.setCurrentIndex(1))
        btn_row.addWidget(skip_btn)
        btn_row.addStretch()
        apply_btn = QPushButton("Apply & Continue")
        apply_btn.setObjectName("primary")
        apply_btn.clicked.connect(self._apply_git_config)
        btn_row.addWidget(apply_btn)
        v.addLayout(btn_row)

        return page

    def _apply_git_config(self) -> None:
        name  = self._git_name.text().strip()
        email = self._git_email.text().strip()
        if name:
            subprocess.run(["git", "config", "--global", "user.name",  name],  check=False)
        if email:
            subprocess.run(["git", "config", "--global", "user.email", email], check=False)
        for key, val in [
            ("core.editor",         "vim"),
            ("pull.rebase",         "true"),
            ("init.defaultBranch",  "main"),
            ("push.autoSetupRemote","true"),
            ("core.autocrlf",       "input"),
        ]:
            subprocess.run(["git", "config", "--global", key, val], check=False)
        self._stack.setCurrentIndex(1)

    # ── Page: Welcome ──────────────────────────────────────────────────────────

    def _page_welcome(self) -> QWidget:
        page = QWidget(); page.setObjectName("root")
        v = QVBoxLayout(page)
        v.setContentsMargins(52, 40, 52, 36)
        v.setSpacing(0)

        lbl_title = QLabel("Kubuntu — First Login Setup")
        lbl_title.setObjectName("title")
        v.addWidget(lbl_title)

        lbl_author = QLabel(
            "by  BeanGreen247  ·  github.com/BeanGreen247/kubuntu-setup"
        )
        lbl_author.setObjectName("author")
        v.addWidget(lbl_author)

        v.addSpacing(22)
        v.addWidget(_divider())
        v.addSpacing(18)

        lbl_what = QLabel("What this will do")
        lbl_what.setObjectName("section")
        v.addWidget(lbl_what)
        v.addSpacing(10)

        what_items = [
            ("🍷", "Wine prefix init",
             "Create ~/.wine (win64) · install corefonts, vcrun2019, d3dcompiler_47"),
            ("🔄", "dotfile-sync timer",
             "Register the 12-hour auto-sync timer for ~/.bashrc and ~/.vimrc"),
            ("⚡", "KDE power profile",
             "Set balanced profile on AC and battery, configure screen timeouts"),
            ("🖥 ", "KWin compositor tweaks",
             "OpenGL Core · adaptive vsync · low latency · animations off · no launch feedback"),
            ("🎨", "KDE appearance",
            "Dark mode · no splash · all effects off · no launch feedback · Breeze icons · no hot corners · black wallpaper"),
        ]
        for icon, label, desc in what_items:
            row = QHBoxLayout(); row.setSpacing(12)
            ico = QLabel(icon); ico.setFixedWidth(28)
            ico.setAlignment(Qt.AlignmentFlag.AlignTop)
            col = QVBoxLayout(); col.setSpacing(1)
            lbl_l = QLabel(label); lbl_l.setObjectName("step_name")
            lbl_d = QLabel(desc);  lbl_d.setObjectName("step_desc")
            col.addWidget(lbl_l); col.addWidget(lbl_d)
            row.addWidget(ico); row.addLayout(col)
            v.addLayout(row)
            v.addSpacing(8)

        v.addSpacing(10)
        v.addWidget(_divider())
        v.addSpacing(14)

        lbl_note = QLabel(
            "This runs once and removes itself from autostart when complete.\n"
            "A reboot is required for all changes (dark mode, effects, wallpaper) to take full effect."
        )
        lbl_note.setObjectName("body")
        lbl_note.setWordWrap(True)
        v.addWidget(lbl_note)

        v.addStretch()

        btn_row = QHBoxLayout()
        back_btn = QPushButton("← Git Config")
        back_btn.setObjectName("primary")
        back_btn.setStyleSheet(
            "QPushButton#primary { background: #3a3f44; color: #bdc3c7; }"
            "QPushButton#primary:hover { background: #4a5056; }"
        )
        back_btn.clicked.connect(lambda: self._stack.setCurrentIndex(0))
        btn_row.addWidget(back_btn)
        btn_row.addStretch()
        self._start_btn = QPushButton("Begin Setup")
        self._start_btn.setObjectName("primary")
        self._start_btn.clicked.connect(self._start_setup)
        btn_row.addWidget(self._start_btn)
        v.addLayout(btn_row)

        return page

    # ── Page: Running ──────────────────────────────────────────────────────────

    def _page_running(self) -> QWidget:
        page = QWidget(); page.setObjectName("root")
        v = QVBoxLayout(page)
        v.setContentsMargins(32, 24, 32, 16)
        v.setSpacing(10)

        lbl_title = QLabel("Setting up your system…")
        lbl_title.setObjectName("title")
        v.addWidget(lbl_title)

        h = QHBoxLayout(); h.setSpacing(20)

        # ── Left: step list + done tile ───────────────────────────────────────
        step_col = QWidget(); step_col.setObjectName("root")
        step_col.setFixedWidth(280)
        sc = QVBoxLayout(step_col)
        sc.setContentsMargins(0, 0, 0, 0)
        sc.setSpacing(6)

        for sid, slabel, sdesc, *_ in STEPS:
            row = QHBoxLayout(); row.setSpacing(8)
            ico = QLabel("○"); ico.setObjectName("st_pending"); ico.setFixedWidth(18)
            col = QVBoxLayout(); col.setSpacing(0)
            n = QLabel(slabel); n.setObjectName("step_name")
            d = QLabel(sdesc);  d.setObjectName("step_desc"); d.setWordWrap(True)
            col.addWidget(n); col.addWidget(d)
            row.addWidget(ico); row.addLayout(col)
            wrapper = QWidget(); wrapper.setObjectName("root"); wrapper.setLayout(row)
            sc.addWidget(wrapper)
            self._step_icons[sid] = ico

        sc.addStretch()

        # Done tile — appears below the step list, activated on finish
        done_row = QHBoxLayout(); done_row.setSpacing(6)
        self._done_tile_ico = QLabel("○")
        self._done_tile_ico.setObjectName("st_pending")
        self._done_tile_ico.setFixedWidth(18)

        self._done_tile_btn = QPushButton("✦  Done")
        self._done_tile_btn.setObjectName("step_btn")
        self._done_tile_btn.setCheckable(True)
        self._done_tile_btn.setEnabled(False)
        self._done_tile_btn.clicked.connect(self._show_done_tile)

        done_row.addWidget(self._done_tile_ico)
        done_row.addWidget(self._done_tile_btn, 1)
        done_wrapper = QWidget(); done_wrapper.setObjectName("root")
        done_wrapper.setLayout(done_row)
        sc.addWidget(done_wrapper)

        h.addWidget(step_col)

        # ── Right: live log ───────────────────────────────────────────────────
        self._log = QTextEdit()
        self._log.setObjectName("log")
        self._log.setReadOnly(True)
        h.addWidget(self._log, 1)

        v.addLayout(h, 1)

        # ── Bottom bar: progress label + bar + Next button ────────────────────
        v.addWidget(_divider())
        bot = QHBoxLayout()
        bot.setContentsMargins(0, 6, 0, 0)

        self._prog_label = QLabel("Waiting…")
        self._prog_label.setObjectName("body")
        self._prog_label.setStyleSheet("color: #7f8c8d; font-size: 11px;")
        bot.addWidget(self._prog_label)
        bot.addSpacing(12)

        self._progress = QProgressBar()
        self._progress.setRange(0, len(STEPS))
        self._progress.setValue(0)
        self._progress.setFixedHeight(18)
        bot.addWidget(self._progress, 1)
        bot.addSpacing(12)

        self._next_btn = QPushButton("Next →")
        self._next_btn.setObjectName("primary")
        self._next_btn.setFixedWidth(110)
        self._next_btn.setEnabled(False)
        self._next_btn.clicked.connect(self._go_to_done)
        bot.addWidget(self._next_btn)

        v.addLayout(bot)
        return page

    # ── Page: Done ─────────────────────────────────────────────────────────────

    def _page_done(self) -> QWidget:
        page = QWidget(); page.setObjectName("root")
        v = QVBoxLayout(page)
        v.setContentsMargins(52, 60, 52, 48)
        v.setSpacing(14)

        self._done_title = QLabel("✓  Setup Complete")
        self._done_title.setObjectName("title")
        v.addWidget(self._done_title)

        self._done_body = QLabel(
            "All steps finished. Your Wine prefix, KWin gaming script,\n"
            "and KDE settings are ready.\n\n"
            "⚠  Reboot to apply dark mode, animations, and wallpaper changes."
        )
        self._done_body.setObjectName("body")
        self._done_body.setWordWrap(True)
        v.addWidget(self._done_body)

        v.addSpacing(8)
        v.addWidget(_divider())
        v.addSpacing(8)

        # ── Per-step summary ──────────────────────────────────────────────────
        self._summary_widget = QWidget()
        self._summary_widget.setObjectName("root")
        sw = QVBoxLayout(self._summary_widget)
        sw.setContentsMargins(0, 0, 0, 0)
        sw.setSpacing(4)
        self._summary_rows: list[tuple[QLabel, QLabel]] = []
        for _, slabel, sdesc, *_ in STEPS:
            row = QHBoxLayout(); row.setSpacing(10)
            ico_lbl = QLabel("○"); ico_lbl.setObjectName("st_pending"); ico_lbl.setFixedWidth(16)
            name_lbl = QLabel(slabel); name_lbl.setObjectName("step_name")
            row.addWidget(ico_lbl); row.addWidget(name_lbl); row.addStretch()
            w = QWidget(); w.setObjectName("root"); w.setLayout(row)
            sw.addWidget(w)
            self._summary_rows.append((ico_lbl, name_lbl))
        v.addWidget(self._summary_widget)

        v.addSpacing(8)
        v.addWidget(_divider())
        v.addSpacing(8)

        lbl_links = QLabel("Resources")
        lbl_links.setObjectName("section")
        v.addWidget(lbl_links)

        for text, url in (
            (f"📦  Setup script  —  {GITHUB_URL}",  GITHUB_URL),
            (f"📁  Dotfiles      —  {DOTFILES_URL}", DOTFILES_URL),
        ):
            lnk = QLabel(f'<a href="{url}" style="color:#89b4fa;">{text}</a>')
            lnk.setOpenExternalLinks(True)
            lnk.setObjectName("body")
            v.addWidget(lnk)

        v.addStretch()

        self._reboot_lbl = QLabel("Rebooting in 30 s…")
        self._reboot_lbl.setObjectName("body")
        self._reboot_lbl.setStyleSheet("color: #f67400; font-size: 12px;")
        self._reboot_lbl.hide()
        v.addWidget(self._reboot_lbl)
        v.addSpacing(6)

        btn_row = QHBoxLayout()
        self._cancel_reboot_btn = QPushButton("Cancel Reboot")
        self._cancel_reboot_btn.setObjectName("primary")
        self._cancel_reboot_btn.setStyleSheet(
            "QPushButton#primary { background: #da4453; color: #eff0f1; }"
            "QPushButton#primary:hover { background: #e05060; }"
        )
        self._cancel_reboot_btn.clicked.connect(self._cancel_reboot)
        self._cancel_reboot_btn.hide()
        btn_row.addWidget(self._cancel_reboot_btn)
        btn_row.addStretch()
        reboot_btn = QPushButton("Reboot Now")
        reboot_btn.setObjectName("primary")
        reboot_btn.clicked.connect(lambda: subprocess.run(["systemctl", "reboot"], check=False))
        btn_row.addWidget(reboot_btn)
        btn_row.addSpacing(12)
        close_btn = QPushButton("Close")
        close_btn.setObjectName("primary")
        close_btn.setStyleSheet(
            "QPushButton#primary { background: #3a3f44; color: #bdc3c7; }"
            "QPushButton#primary:hover { background: #4a5056; }"
        )
        close_btn.clicked.connect(self.close)
        btn_row.addWidget(close_btn)
        v.addLayout(btn_row)

        return page

    # ── Done tile (running page) ───────────────────────────────────────────────

    def _show_done_tile(self) -> None:
        """Show the run summary in the log panel when the Done tile is clicked."""
        for ico in self._step_icons.values():
            pass  # icons stay as-is; tile just surfaces the final stats

        passed  = sum(1 for s in self._step_states.values() if s == STEP_DONE)
        warned  = sum(1 for s in self._step_states.values() if s == STEP_WARN)
        failed  = len(STEPS) - passed - warned

        self._log.clear()
        lines = [
            "─" * 48,
            "  Run summary",
            "─" * 48,
            f"  ✓  {passed} passed",
        ]
        if warned:
            lines.append(f"  ⚠  {warned} warnings")
        if failed:
            lines.append(f"  ✗  {failed} failed / skipped")
        lines += [
            "",
            "  ⚠  Reboot to apply dark mode, animations,",
            "     wallpaper, and Wine changes.",
            "",
            "  Click  Next →  to continue.",
            "─" * 48,
        ]
        for line in lines:
            self._append_log(line)

    # ── Setup runner ───────────────────────────────────────────────────────────

    def _start_setup(self) -> None:
        self._start_btn.setEnabled(False)
        self._stack.setCurrentIndex(2)
        self._prog_label.setText("Running…")

        # Keep the installed copy in sync with the repo so the user never runs
        # a stale version after pulling updates.
        if _REPO_SCRIPT.exists() and _REPO_SCRIPT != _INSTALLED:
            try:
                import shutil as _shutil
                _INSTALLED.parent.mkdir(parents=True, exist_ok=True)
                _shutil.copy2(_REPO_SCRIPT, _INSTALLED)
                _INSTALLED.chmod(0o755)
            except OSError:
                pass

        self._process = QProcess(self)
        self._process.setProcessChannelMode(
            QProcess.ProcessChannelMode.MergedChannels
        )
        self._process.readyReadStandardOutput.connect(self._on_output)
        self._process.finished.connect(self._on_finished)

        env = QProcessEnvironment.systemEnvironment()
        env.insert("TERM", "xterm-256color")
        self._process.setProcessEnvironment(env)

        self._process.start("bash", [str(SCRIPT_PATH), "--post-login"])

    def _on_output(self) -> None:
        raw = bytes(self._process.readAllStandardOutput()).decode(
            "utf-8", errors="replace"
        )
        for line in raw.splitlines():
            clean = ANSI_RE.sub("", line).strip()
            if not clean:
                continue
            self._append_log(clean)
            self._update_steps(clean)

    def _append_log(self, line: str) -> None:
        if "  ✓" in line or line.startswith("✓"):
            colour = "#a6e3a1"
        elif "  ⚠" in line or line.startswith("⚠") or "WARN" in line.upper():
            colour = "#fab387"
        elif "  ✗" in line or line.startswith("✗") or "ERR" in line.upper():
            colour = "#f38ba8"
        elif "  →" in line or line.startswith("→"):
            colour = "#89dceb"
        elif line.startswith("─"):
            colour = "#3a3f44"
        else:
            colour = "#cdd6f4"

        cursor = self._log.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        fmt = cursor.charFormat()
        fmt.setForeground(QColor(colour))
        cursor.setCharFormat(fmt)
        cursor.insertText(line + "\n")
        self._log.setTextCursor(cursor)
        self._log.ensureCursorVisible()

    def _update_steps(self, line: str) -> None:
        for sid, _label, _desc, trigger, done_str in STEPS:
            state = self._step_states[sid]
            if state == STEP_PENDING and trigger in line:
                self._set_step(sid, STEP_RUNNING)
                self._prog_label.setText(f"Running: {_label}…")
            elif state == STEP_RUNNING:
                if done_str in line:
                    self._set_step(sid, STEP_DONE)
                elif "warn" in line.lower() or "⚠" in line:
                    self._set_step(sid, STEP_WARN)

    def _set_step(self, sid: str, state: int) -> None:
        self._step_states[sid] = state
        ico = self._step_icons.get(sid)
        if ico is None:
            return

        ico.setText(_STEP_ICON[state])
        ico.setObjectName(_STEP_CLASS[state])
        ico.setStyleSheet("")
        ico.style().polish(ico)

        if state in (STEP_DONE, STEP_WARN):
            self._steps_done += 1
            self._progress.setValue(self._steps_done)

    def _on_finished(self, exit_code: int, _status) -> None:
        self._exit_code = exit_code

        # Promote any still-running steps to done
        for sid, st in self._step_states.items():
            if st == STEP_RUNNING:
                self._set_step(sid, STEP_DONE)

        self._progress.setValue(len(STEPS))

        passed = sum(1 for s in self._step_states.values() if s == STEP_DONE)
        warned = sum(1 for s in self._step_states.values() if s == STEP_WARN)

        # Activate Done tile
        tile_state = STEP_DONE if exit_code == 0 else STEP_WARN
        self._done_tile_ico.setText(_STEP_ICON[tile_state])
        self._done_tile_ico.setObjectName(_STEP_CLASS[tile_state])
        self._done_tile_ico.setStyleSheet("")
        self._done_tile_ico.style().polish(self._done_tile_ico)
        self._done_tile_btn.setText(f"✦  Done  ({passed}✓ {warned}⚠)")
        self._done_tile_btn.setEnabled(True)
        self._done_tile_btn.click()  # auto-select and show summary

        # Enable Next → so user can proceed when ready
        self._next_btn.setEnabled(True)
        self._prog_label.setText("Done — click  Next →  to continue.")

        # Write sentinel and clean up autostart now (don't wait for Next click)
        done_dir = Path.home() / ".local" / "share" / "kubuntu-setup"
        done_dir.mkdir(parents=True, exist_ok=True)
        (done_dir / ".post-login-done").touch()
        self._autostart_cleanup_timer.stop()
        self._remove_autostart()

        try:
            subprocess.Popen(
                [
                    "notify-send", "-u", "normal", "-i", "applications-system",
                    "Kubuntu Setup", "Post-login setup complete!",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError:
            pass

    def _go_to_done(self) -> None:
        """Navigate to the summary page and populate it, then start reboot countdown."""
        passed = sum(1 for s in self._step_states.values() if s == STEP_DONE)
        warned = sum(1 for s in self._step_states.values() if s == STEP_WARN)
        failed = len(STEPS) - passed - warned

        if self._exit_code == 0:
            self._done_title.setText("✓  Setup Complete")
            self._done_body.setText(
                "All steps finished successfully.\n"
                "Your Wine prefix, KWin gaming script, and KDE settings are ready.\n\n"
                "⚠  Reboot to apply dark mode, animations, and wallpaper changes."
            )
        else:
            self._done_title.setText("⚠  Setup Finished with Warnings")
            self._done_body.setText(
                f"Setup finished (exit {self._exit_code}).\n"
                "Some optional steps may need manual attention — check the log.\n\n"
                "⚠  Reboot to apply dark mode, animations, and wallpaper changes."
            )

        # Populate per-step summary icons on the done page
        for (ico_lbl, _name_lbl), (sid, *_) in zip(self._summary_rows, STEPS):
            state = self._step_states[sid]
            ico_lbl.setText(_STEP_ICON[state])
            ico_lbl.setObjectName(_STEP_CLASS[state])
            ico_lbl.setStyleSheet("")
            ico_lbl.style().polish(ico_lbl)

        self._stack.setCurrentIndex(3)

        # Auto-reboot countdown
        self._reboot_seconds_left = 30
        self._reboot_lbl.setText(f"Rebooting in {self._reboot_seconds_left} s…")
        self._reboot_lbl.show()
        self._cancel_reboot_btn.show()
        self._reboot_countdown = QTimer(self)
        self._reboot_countdown.setInterval(1000)
        self._reboot_countdown.timeout.connect(self._tick_reboot)
        self._reboot_countdown.start()

    def _tick_reboot(self) -> None:
        self._reboot_seconds_left -= 1
        if self._reboot_seconds_left <= 0:
            self._reboot_countdown.stop()
            subprocess.run(["systemctl", "reboot"], check=False)
            return
        self._reboot_lbl.setText(f"Rebooting in {self._reboot_seconds_left} s…")

    def _cancel_reboot(self) -> None:
        if hasattr(self, "_reboot_countdown"):
            self._reboot_countdown.stop()
        self._reboot_lbl.setText("Auto-reboot cancelled.")
        self._cancel_reboot_btn.hide()

    def _remove_autostart(self) -> None:
        autostart = Path.home() / ".config" / "autostart" / "kubuntu-post-login.desktop"
        autostart.unlink(missing_ok=True)


# ── Helpers ────────────────────────────────────────────────────────────────────

def _divider() -> QFrame:
    f = QFrame()
    f.setObjectName("divider")
    f.setFixedHeight(1)
    return f


# ── Entry point ────────────────────────────────────────────────────────────────

def main() -> None:
    # Already completed on a previous login — don't show the wizard again.
    if DONE_FLAG.exists():
        sys.exit(0)

    if "QT_QPA_PLATFORM" not in os.environ:
        os.environ["QT_QPA_PLATFORM"] = "xcb"

    app = QApplication(sys.argv)
    app.setApplicationName("Kubuntu Post-Login Setup")
    app.setStyleSheet(QSS)

    if not SCRIPT_PATH.exists():
        from PyQt6.QtWidgets import QMessageBox
        QMessageBox.critical(
            None,
            "Setup script not found",
            f"Cannot find:\n{SCRIPT_PATH}\n\nRe-run:  sudo bash setup-kubuntu.sh",
        )
        sys.exit(1)

    win = SetupWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
