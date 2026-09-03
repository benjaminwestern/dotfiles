-- Input configuration

hl.config({
    input = {
        -- sensitivity = -0.25,
        accel_profile = "flat",
        natural_scroll = true,
        touchpad = {
            natural_scroll = true,
            tap_to_click = false,
            clickfinger_behavior = true,
            tap_and_drag = false,
            drag_lock = false,
            scroll_factor = 0.4,
        },
    },
    -- Uncomment the section below to enable software cursors; this can help with cursor display or behavior issues
    -- cursor = {
    --     no_hardware_cursors = 1,
    -- },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({
    fingers = 3,
    direction = "up",
    action = function()
        if not hl.get_active_special_workspace() then
            hl.dispatch(hl.dsp.workspace.toggle_special())
        end
    end,
})
hl.gesture({
    fingers = 3,
    direction = "down",
    action = function()
        if hl.get_active_special_workspace() then
            hl.dispatch(hl.dsp.workspace.toggle_special())
        end
    end,
})
hl.gesture({ fingers = 4, direction = "up",         action = "fullscreen" })
hl.gesture({ fingers = 4, direction = "down",       action = "fullscreen", mode = "0" })
