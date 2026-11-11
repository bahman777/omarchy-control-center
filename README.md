# Control Center for Omarchy

A GNOME Settings–style control center for [Omarchy](https://omarchy.org) Quattro, built as an Omarchy shell (Quickshell) plugin. Every common system setting in one window, showing what's on, what's available, and what you can change, and updating live as things change.

![Control Center](preview.png)

## Quick Settings

Click the status icons in the bar (network · Bluetooth · volume · battery) and a GNOME-style **Quick Settings** panel drops down from the bar. It is the same kind of panel as Omarchy's own bar menus, so it closes when you click elsewhere and never hides other windows.

- **Header:** battery, plus screenshot, settings, lock and power buttons. Power opens Suspend, Restart, Power Off and Log Out.
- **Sliders:** volume, microphone and brightness. The chevron next to a slider picks the output or input device, so a headset is one click away.
- **Toggles:** Wi-Fi, Wired, Bluetooth, Tailscale, VPN, Power Mode, Night Light, Do Not Disturb, Stay Awake, Airplane Mode, Window Layout, Printers and Scanners. Click a pill to switch it on or off. Click its chevron to open its menu in place: networks with inline password entry, Bluetooth devices with battery levels, Tailscale exit nodes, power modes, the Hyprland layout, printers (set the default, cancel jobs) and scanners (scan with Document Scanner).

Anything that opens a real window (settings, screenshot, printer setup, scanning) closes the panel first.

```bash
omarchy-shell control-center toggle          # open/close Quick Settings
omarchy-shell control-center menu wifi       # open with a menu expanded (wifi, bluetooth, tailscale, vpn,
                                             # power, layout, printers, scanners, outputs, inputs, session)
omarchy-shell control-center settings sound  # open the full settings window on a page
```

Right-clicking the bar icons opens the full settings window. You may want to remove Omarchy's separate network, Bluetooth and audio icons from the bar (`omarchy bar` or Omarchy's bar settings), since the cluster replaces them.

## Settings window

| Page | What you can do |
|---|---|
| **Wi-Fi** | Turn Wi-Fi on/off, see visible networks with signal and security, connect (with password), disconnect and forget networks. Shows the current connection's IP, gateway, signal and band, lets you pin the band (2.4/5/6 GHz) and runs a speed test |
| **Network** | Wired/LAN adapters (connect/disconnect, IPs, gateway, MAC), NetworkManager VPN and WireGuard profiles, other interfaces, DNS provider (Automatic/Cloudflare/Google/custom), hostname |
| **Tailscale** | Connect/disconnect, this machine's IPs and MagicDNS name, exit node picker with LAN access, DNS/subnet routes/shields-up/SSH preferences, live list of machines (click to copy the IP, right-click to send files with Taildrop) |
| **Bluetooth** | Power, discoverable, your devices with battery levels (connect, disconnect, forget), nearby devices to pair (scans while the page is open) |
| **Sound** | Output volume and mute, output devices (headsets and Bluetooth speakers appear as they connect), microphone volume and mute (shows which apps are recording), input devices, and per-app volume |
| **Displays** | Resolution, refresh rate and scale per monitor (follows hotplug, with a 15-second "Keep changes?" revert), brightness, mirroring, built-in display on/off, night light, text size |
| **Power** | Battery level, time remaining, charge rate and health. Peripheral batteries, power mode, stay awake, screensaver and lock timers, plus lock/suspend/log out/restart/shut down |
| **Windows & Layout** | Hyprland default layout (dwindle/master/scrolling) and layout-specific options, cycling the current workspace's layout, gaps, borders, rounding, animations, blur, shadows, dimming, opacity, focus-follows-mouse, and a live workspace overview |
| **Keyboard & Mouse** | Keyboard layouts and input methods, key repeat, pointer speed, natural scrolling, touchpad on/off, tap-to-click and disable-while-typing |
| **Appearance** | Omarchy theme (searchable), background, monospace font, bar position and background, window corners |
| **Notifications** | Do Not Disturb, clear all, crash notifications, test notification |
| **System** | Device, Omarchy/kernel/Hyprland versions, CPU, memory, graphics, disk, uptime. Update check and update, firmware, time zone, automatic time, Omarchy language |

Search (`/` or `Ctrl+F`) filters pages by keyword, so "headset", "gaps" or "exit node" all work. `↑`/`↓` move between pages and `Esc` closes.

## Install

```bash
omarchy plugin add https://github.com/bahman777/omarchy-control-center --enable
omarchy restart shell   # after updates, so the new QML is loaded
```

This adds the status-icon cluster to the right of the bar.

To open it from a key binding or a script:

```bash
omarchy-shell shell toggle io.github.bahman777.control-center
omarchy-shell shell summon io.github.bahman777.control-center '{"page":"bluetooth"}'
```

Page ids: `wifi`, `network`, `tailscale`, `bluetooth`, `sound`, `displays`, `power`, `windows`, `input`, `appearance`, `notifications`, `system`.

For example, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER CTRL, S", "Control Center", "exec", "omarchy-shell shell toggle io.github.bahman777.control-center")
```

## Remove

```bash
omarchy plugin remove io.github.bahman777.control-center
```

If you kept Hyprland changes after restart (see below), also delete the `pcall(dofile, … control-center.lua)` line at the end of `~/.config/hypr/hyprland.lua` and the file `~/.config/hypr/control-center.lua`. A backup of `hyprland.lua` from before the line was added is at `~/.config/hypr/hyprland.lua.bak.control-center`.

## How settings are applied

Wherever Omarchy has a command, the Control Center uses it (`omarchy-bluetooth-power`, `omarchy-powerprofiles-set`, `omarchy-dns`, `omarchy-theme-set`, `omarchy-audio-output-set-default`, and so on), so it behaves exactly like Omarchy's own menus and panels.

**Hyprland options** (Windows & Layout, Keyboard & Mouse, display modes) apply immediately with `hyprctl eval`. Only a fixed allowlist of options is ever written, and values are type-checked and clamped. Your changes are saved to `~/.config/hypr/control-center.lua`, a file the plugin owns. **The plugin never edits your own config without asking.** Until you press **Keep after restart**, changes last only until you log out. Pressing it adds one line at the end of `hyprland.lua` (after making a backup) that loads `control-center.lua` after your own files, so your choices there take precedence. **Reset window settings** clears all of this and reloads Hyprland.

**Idle timers** are written to `~/.config/omarchy/shell.json` (the `idle` section only), which the shell hot-reloads.

The plugin makes no network requests of its own. Wi-Fi, Bluetooth, sound, battery and monitor state come from Quickshell's NetworkManager, BlueZ, PipeWire, UPower and Hyprland bindings, so the window updates as soon as something changes. Tailscale and a few other details are polled only while their page is open.

## Requirements

- Omarchy Quattro (4.x) with the Omarchy shell
- NetworkManager (`nmcli`), `iproute2`, `brightnessctl`, `power-profiles-daemon`, `wl-clipboard`, `python3`. All ship with Omarchy
- Optional: CUPS (`lpstat`, `system-config-printer`) for Printers, SANE (`scanimage`) and `simple-scan` for Scanners
- Optional: `tailscale` for the Tailscale page (it offers to install Tailscale if missing)

Some actions ask for your password through Omarchy's polkit prompt, such as changing DNS or the time zone, and Tailscale changes if your user isn't the Tailscale operator (`sudo tailscale set --operator=$USER` fixes that).

## Development

The plugin lives in `~/.config/omarchy/plugins/io.github.bahman777.control-center/`. The shell caches compiled QML, so after changing files (or updating the plugin) run `omarchy restart shell`. `omarchy plugin validate .` checks the manifest.

```
manifest.json      plugin manifest (bar-widget + overlay)
BarWidget.qml      status icons in the bar + Quick Settings panel
quick/             Quick Settings pills, menus, sliders
Settings.qml       the window: sidebar, search, page host
Runner.qml         argv-only process runner (no shell strings built from data)
HyprOptions.qml    live Hyprland options + persistence
HyprSpec.js        option allowlist, validation, Lua serialization
Icons.js           Nerd Font glyphs
ui/                shared rows, groups, switches, sliders
pages/             one file per page
```

## License

MIT
