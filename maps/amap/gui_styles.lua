local Public = {}

Public.COLORS = {
    GREEN  = {0, 1, 0},
    GREY   = {0.686, 0.686, 0.686},
    CYAN   = {0, 0.686, 0.686},
    YELLOW = {1, 1, 0},
    WHITE  = {0.88, 0.88, 0.88},
    RED    = {1, 0, 0},
    ORANGE = {1, 0.647, 0},
    BLACK  = {0, 0, 0}
}

Public.QUALITY_COLOR = {
    {r = 200 / 255, g = 200 / 255, b = 200 / 255},
    {r = 50 / 255,  g = 205 / 255, b = 50 / 255},
    {r = 30 / 255,  g = 144 / 255, b = 255 / 255},
    {r = 147 / 255, g = 112 / 255, b = 219 / 255},
    {r = 255 / 255, g = 165 / 255, b = 0 / 255}
}

Public.DIFFICULTY_COLOR = {
    easy   = {r = 0.3, g = 0.6, b = 1.0},
    normal = {r = 0.7, g = 0.3, b = 1.0},
    hard   = {r = 1.0, g = 0.6, b = 0.2}
}

Public.GUI_COLOR = {
    COMFY       = {r = 0.98, g = 0.66, b = 0.22},
    GOLD        = {1, 0.84, 0},
    HINT_GREY   = {0.7, 0.7, 0.7},
    DEFAULT     = {0.87, 0.87, 0.87},
    LABEL_BLUE  = {0.55, 0.55, 0.99},
    DARK_RED    = {0.77, 0.11, 0.11},
    LINK_BLUE   = {0.33, 0.66, 0.9}
}

function Public.apply_style(element, style_table)
    for key, value in pairs(style_table) do
        element.style[key] = value
    end
    return element
end

return Public
