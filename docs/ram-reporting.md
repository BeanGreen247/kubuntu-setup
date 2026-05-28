# RAM Reporting — Why htop and KSysGuard Show Different Numbers

Linux page cache (the yellow/orange bar in htop) is **free RAM** the kernel repurposes as a disk read-cache. When an application needs that memory the kernel drops the cache instantly — no swap involved. Neither tool is wrong; they measure different things.

## The numbers

| Tool | What "Used" means | Cache included? |
|---|---|---|
| htop green bar | processes only (`MemTotal − MemFree − Buffers − Cached`) | No |
| htop top number | `MemTotal − MemFree` (all non-free pages) | Yes |
| KSysGuard / KDE System Monitor "Used" | same as htop top number | Yes |
| `free -h` "used" | `MemTotal − MemFree − Buffers − Cached` | No |
| `free -h` "available" | **MemAvailable** — what new apps can actually use | No |

## The right metric

`MemAvailable` from `/proc/meminfo` is the canonical answer to *"how much RAM can I still use?"*. It equals free RAM **plus** reclaimable page cache. The kernel reclaims cache pages immediately on demand — cache is never stuck.

```
used by apps  =  MemTotal − MemAvailable
```

This is what `free -h`'s **available** column shows and what the `mem` shell function (installed by `setup-kubuntu.sh`) reports.

## Quick check in every terminal

`setup-kubuntu.sh` installs a `mem` function via `/etc/profile.d/kubuntu-mem.sh`. Open any terminal and run:

```
mem
```

Output example:
```
  RAM used by apps :   9012 MiB  (24%)
  Page cache       :   4150 MiB  (reclaimable — effectively free)
  Available        :  28400 MiB
  Total            :  38400 MiB

  TIP: htop green bar = apps only (correct). KSysGuard "Used" includes cache.
       Both are right; cache is free RAM the kernel uses as a disk speed-up.
```

## Fix KDE System Monitor to show app memory only

In **plasma-systemmonitor**:
1. Right-click the memory graph → **Edit page**
2. Change the sensor from `memory/physical/used` → `memory/physical/application`

This makes the graph match htop's green bar and the `mem` function output.

## Summary

| Scenario | Recommended tool |
|---|---|
| Terminal at a glance | `mem` (installed by setup-kubuntu.sh) |
| Terminal detailed | `free -h` → read the **available** column |
| `/proc/meminfo` directly | `MemAvailable` line |
| GUI (KDE System Monitor) | sensor `memory/physical/application` |
| htop | Green bar = app memory (ignore the total-used bar) |
