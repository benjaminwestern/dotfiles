# Hyprland tweaks for usability

These tweaks layer on top of Omarchy's default Hyprland configuration. Omarchy sources its defaults from `~/.local/share/omarchy/default/hypr/` first, then loads user overrides from `~/.config/hypr/`.

## Trackpad

File: `~/.config/hypr/input.conf`

Overrides Omarchy's touchpad defaults for a macOS-like feel:

```ini
input {
  natural_scroll = true

  touchpad {
    natural_scroll = true

    # Disable tap-to-click; require physical clicks
    tap-to-click = false

    # Single physical click = left click; two-finger click = right click
    clickfinger_behavior = true

    # Disable tap-and-drag and drag lock
    tap-and-drag = false
    drag_lock = false

    scroll_factor = 0.4
  }
}

# macOS-style 3-finger trackpad gestures
gesture = 3, horizontal, workspace
gesture = 3, up, fullscreen
gesture = 3, down, fullscreen, 0
```

- 3-finger swipe left/right → switch workspaces
- 3-finger swipe up → fullscreen active window
- 3-finger swipe down → un-fullscreen active window

## Monitor scaling

File: `~/.config/hypr/monitors.conf`

Omarchy ships with `env = GDK_SCALE,2`, which is meant for retina-class displays.
On this 1920x1080 laptop that makes Ghostty feel comically zoomed in because
Ghostty honors `GDK_SCALE` and doubles its configured font size. Alacritty did
not, which is why it looked fine there.

Changed to:

```ini
env = GDK_SCALE,1
monitor=,preferred,auto,auto
```

This keeps terminal font sizes predictable at 1x scaling.
