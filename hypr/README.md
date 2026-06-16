# Hyprland tweaks for usability

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
