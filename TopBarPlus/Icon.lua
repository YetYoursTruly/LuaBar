--[[
    TopbarIcon
    A standalone, executor-friendly topbar icon module with a TopbarPlus-style
    chainable API, so code like the HD Admin example ports almost 1:1.

        local Icon = loadstring(game:HttpGet(".../TopbarIcon.lua"))()

        local icon = Icon.new()
            :setImage("YouTube")                 -- ImageLib name, asset id, or rbxasset:// string
            :setImageScale(0.45)
            :bindToggleItem(someFrame)           -- Visible = true while selected
            :setOrder(0)

    Supported (same names/behaviour as TopbarPlus):
      Icon.new, :setImage, :setLabel, :setImageScale, :setOrder, :setEnabled,
      :setName, :setWidth, :setCornerRadius, :align/:setLeft/:setRight,
      :bindToggleItem, :unbindToggleItem, :bindEvent, :unbindEvent,
      :bindToggleKey, :unbindToggleKey, :select, :deselect, :toggle,
      :oneClick, :autoDeselect, :lock, :unlock, :call, :destroy
      Events: .selected  .deselected  .toggled   (use :Connect)
      Static: Icon.getIcons(), Icon.getIcon(name), Icon.setTopbarEnabled(bool)

    Extra: :setImageColor(color3, state), :setTextColor(color3, state)

    Not included (needs the full TopbarPlus module tree): menus, dropdowns,
    notices, captions, themes, gamepad support.

    `state` is "selected", "deselected", or nil (both).
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")

--==================================================
-- ENVIRONMENT
--==================================================

local env = _G

if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)

    if ok and type(result) == "table" then
        env = result
    end
end

-- Clean up a previous copy if this script is run again.
if type(env.TopbarIconCleanup) == "function" then
    pcall(env.TopbarIconCleanup)
end

--==================================================
-- SETTINGS
--==================================================

local SPACING = 12
local DEFAULT_IMAGE_SCALE = 0.5

local THEME = {
    deselected = {
        background = Color3.fromRGB(0, 0, 0),
        transparency = 0.3,
        hoverTransparency = 0.15,
        foreground = Color3.fromRGB(255, 255, 255),
    },
    selected = {
        background = Color3.fromRGB(255, 255, 255),
        transparency = 0.1,
        hoverTransparency = 0.03,
        foreground = Color3.fromRGB(0, 0, 0),
    },
}

--==================================================
-- HELPERS
--==================================================

local function newSignal()
    local handlers = {}
    local signal = {}

    function signal:Connect(callback)
        local connection = { Connected = true }

        function connection:Disconnect()
            connection.Connected = false

            for index, item in ipairs(handlers) do
                if item == connection then
                    table.remove(handlers, index)
                    break
                end
            end
        end

        connection.callback = callback
        table.insert(handlers, connection)

        return connection
    end

    function signal:Fire(...)
        local snapshot = { table.unpack(handlers) }

        for _, connection in ipairs(snapshot) do
            if connection.Connected then
                task.spawn(connection.callback, ...)
            end
        end
    end

    function signal:Destroy()
        for _, connection in ipairs(handlers) do
            connection.Connected = false
        end

        handlers = {}
    end

    return signal
end

local function resolveImage(value)
    if type(value) == "number" then
        return string.format("rbxassetid://%d", value)
    end

    if type(value) ~= "string" or value == "" then
        return nil
    end

    if tonumber(value) then
        return "rbxassetid://" .. value
    end

    if string.find(value, "^rbx") or string.find(value, "^https?://") then
        return value
    end

    -- Otherwise treat it as an ImageLib image name.
    if type(env.FetchImage) == "function" then
        local asset = env.FetchImage(value)
        return asset
    end

    warn("[TopbarIcon] '" .. value .. "' needs ImageLib (run the ImageLib Loader first)")
    return nil
end

local function statesFor(state)
    if state == nil then
        return { "deselected", "selected" }
    end

    local lowered = string.lower(tostring(state))

    if lowered == "selected" or lowered == "deselected" then
        return { lowered }
    end

    return { "deselected", "selected" }
end

local function tween(instance, props, duration)
    TweenService:Create(
        instance,
        TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        props
    ):Play()
end

--==================================================
-- CONTAINER (ScreenGui + holders)
--==================================================

local Icon = {}
Icon.__index = Icon

Icon.leftOffset = 150 -- set a number to override the automatic left offset
Icon.rightOffset = 100

local icons = {}
local totalCreated = 0
local anySelected = newSignal()
local connections = {}

local barHeight = 36
local iconSize = 28

local gui = Instance.new("ScreenGui")
gui.Name = "TopbarIcons"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 998
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local holders = {}

local function createHolder(name, alignment)
    local holder = Instance.new("Frame")
    holder.Name = name
    holder.BackgroundTransparency = 1
    holder.BorderSizePixel = 0
    holder.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = alignment
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, SPACING)
    layout.Parent = holder

    return holder
end

holders.Left = createHolder("Left", Enum.HorizontalAlignment.Left)
holders.Right = createHolder("Right", Enum.HorizontalAlignment.Right)
holders.Right.AnchorPoint = Vector2.new(1, 0)

local function getBarHeight()
    local ok, inset = pcall(function()
        return GuiService.TopbarInset
    end)

    if ok and typeof(inset) == "Rect" and inset.Height > 0 then
        return inset.Height
    end

    return 36
end

local function getLeftOffset()
    if Icon.leftOffset then
        return Icon.leftOffset
    end

    -- Roblox menu button (+ chat button when enabled) sit at the far left.
    local ok, chatEnabled = pcall(function()
        return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat)
    end)

    if ok and chatEnabled == false then
        return 68
    end

    return 124
end

--==================================================
-- CONSTRUCTOR
--==================================================

function Icon.new()
    local self = setmetatable({}, Icon)

    totalCreated = totalCreated + 1

    self.selected = newSignal()
    self.deselected = newSignal()
    self.toggled = newSignal()

    self.isSelected = false
    self.isViewing = false
    self.isEnabled = true
    self.locked = false
    self.isDestroyed = false
    self.deselectWhenOtherIconSelected = true
    self.selectedHasOwnImage = false
    self.alignment = "Left"
    self.toggleItems = {}
    self.toggleKeys = {}
    self.bindedEvents = {}
    self.connections = {}
    self.appearance = {
        selected = {},
        deselected = {},
    }

    -- Widget: the clickable pill/circle
    local widget = Instance.new("TextButton")
    widget.Name = "Widget"
    widget.AutoButtonColor = false
    widget.Text = ""
    widget.BorderSizePixel = 0
    widget.AutomaticSize = Enum.AutomaticSize.X
    widget.Size = UDim2.fromOffset(0, iconSize)
    widget.LayoutOrder = 100 + totalCreated
    widget.BackgroundColor3 = THEME.deselected.background
    widget.BackgroundTransparency = THEME.deselected.transparency
    widget.ClipsDescendants = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = widget

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(iconSize, 0)
    sizeConstraint.Parent = widget

    local padding = Instance.new("UIPadding")
    padding.Parent = widget

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = widget

    local image = Instance.new("ImageLabel")
    image.Name = "IconImage"
    image.BackgroundTransparency = 1
    image.BorderSizePixel = 0
    image.ScaleType = Enum.ScaleType.Fit
    image.LayoutOrder = 1
    image.Visible = false
    image.Parent = widget

    local label = Instance.new("TextLabel")
    label.Name = "IconLabel"
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.AutomaticSize = Enum.AutomaticSize.X
    label.Size = UDim2.new(0, 0, 1, 0)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 15
    label.Text = ""
    label.LayoutOrder = 2
    label.Visible = false
    label.Parent = widget

    self.widget = widget
    self.imageLabel = image
    self.textLabel = label
    self.padding = padding
    self.corner = corner
    self.sizeConstraint = sizeConstraint

    widget.Parent = holders.Left
    icons[self] = true

    -- Clicking
    table.insert(self.connections, widget.Activated:Connect(function()
        if self.locked then
            return
        end

        self:toggle()
    end))

    -- Hover (skipped on touch-only devices)
    table.insert(self.connections, widget.MouseEnter:Connect(function()
        if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
            return
        end

        self.isViewing = true
        self:_refresh()
    end))

    table.insert(self.connections, widget.MouseLeave:Connect(function()
        self.isViewing = false
        self:_refresh()
    end))

    -- Keybinds
    table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or self.locked then
            return
        end

        if self.toggleKeys[input.KeyCode] then
            self:toggle()
        end
    end))

    -- Deselect when another icon is selected
    table.insert(self.connections, anySelected:Connect(function(incoming)
        if incoming ~= self
            and self.deselectWhenOtherIconSelected
            and incoming.deselectWhenOtherIconSelected then
            self:deselect("AutoDeselect", incoming)
        end
    end))

    self:_refresh()

    return self
end

--==================================================
-- INTERNAL
--==================================================

function Icon:_refresh()
    if self.isDestroyed then
        return
    end

    local state = self.isSelected and "selected" or "deselected"
    local theme = THEME[state]
    local look = self.appearance[state]

    -- Background
    local transparency = theme.transparency

    if self.isViewing then
        transparency = theme.hoverTransparency
    end

    tween(self.widget, {
        BackgroundColor3 = look.backgroundColor or theme.background,
        BackgroundTransparency = look.backgroundTransparency or transparency,
    })

    -- Image
    local image = self.imageLabel
    local hasImage = look.image ~= nil

    image.Visible = hasImage

    if hasImage then
        local scale = look.imageScale or DEFAULT_IMAGE_SCALE
        local pixels = math.max(1, math.floor(iconSize * scale))

        image.Image = look.image
        image.Size = UDim2.fromOffset(pixels, pixels)

        -- Default tint: dark on the selected (white) background unless a
        -- dedicated selected image was given.
        local tint = Color3.fromRGB(255, 255, 255)

        if state == "selected" and not self.selectedHasOwnImage then
            tint = theme.foreground
        end

        image.ImageColor3 = look.imageColor or tint
    end

    -- Label
    local text = look.label or ""
    local hasLabel = text ~= ""

    self.textLabel.Visible = hasLabel
    self.textLabel.Text = text
    self.textLabel.TextColor3 = look.textColor or theme.foreground

    -- Sizing
    local sidePadding = hasLabel and 12 or 0

    self.padding.PaddingLeft = UDim.new(0, sidePadding)
    self.padding.PaddingRight = UDim.new(0, sidePadding)
    self.widget.Size = UDim2.fromOffset(0, iconSize)
    self.sizeConstraint.MinSize = Vector2.new(iconSize, 0)
end

function Icon:_setState(selected, source, sourceIcon)
    if self.isDestroyed or self.isSelected == selected then
        return
    end

    self.isSelected = selected

    if selected then
        self.toggled:Fire(true, source, sourceIcon)
        self.selected:Fire(source, sourceIcon)
    else
        self.toggled:Fire(false, source, sourceIcon)
        self.deselected:Fire(source, sourceIcon)
    end

    self:_setToggleItemsVisible(selected, sourceIcon)
    self:_refresh()

    if selected then
        anySelected:Fire(self)
    end
end

function Icon:_setToggleItemsVisible(visible, sourceIcon)
    for item in pairs(self.toggleItems) do
        -- Don't hide an item that the icon which caused this also controls.
        if not sourceIcon
            or sourceIcon == self
            or sourceIcon.toggleItems[item] == nil then
            local property = item:IsA("LayerCollector") and "Enabled" or "Visible"
            item[property] = visible
        end
    end
end

function Icon:_setAppearance(states, key, value)
    for _, state in ipairs(states) do
        self.appearance[state][key] = value
    end

    self:_refresh()
end

--==================================================
-- APPEARANCE METHODS
--==================================================

function Icon:setImage(image, state)
    if state ~= nil and string.lower(tostring(state)) == "selected" then
        self.selectedHasOwnImage = true
    end

    local states = statesFor(state)

    -- Resolved in the background so a chain never stalls on a download.
    task.spawn(function()
        local resolved = resolveImage(image)

        if self.isDestroyed then
            return
        end

        self:_setAppearance(states, "image", resolved)
    end)

    return self
end

function Icon:setImageScale(number, state)
    self:_setAppearance(statesFor(state), "imageScale", number)
    return self
end

function Icon:setImageColor(color, state)
    self:_setAppearance(statesFor(state), "imageColor", color)
    return self
end

function Icon:setLabel(text, state)
    self:_setAppearance(statesFor(state), "label", text)
    return self
end

function Icon:setTextColor(color, state)
    self:_setAppearance(statesFor(state), "textColor", color)
    return self
end

function Icon:setOrder(number)
    self.widget.LayoutOrder = math.floor(number * 100)
    return self
end

function Icon:setName(name)
    self.name = name
    self.widget.Name = name
    return self
end

function Icon:setWidth(minWidth)
    self.customMinWidth = minWidth
    self.sizeConstraint.MinSize = Vector2.new(minWidth, 0)
    return self
end

function Icon:setCornerRadius(udim)
    self.corner.CornerRadius = udim
    return self
end

function Icon:setEnabled(bool)
    self.isEnabled = bool
    self.widget.Visible = bool
    return self
end

function Icon:align(leftOrRight)
    local direction = string.lower(tostring(leftOrRight))
    local name = direction == "right" and "Right" or "Left"

    self.alignment = name
    self.widget.Parent = holders[name]

    return self
end
Icon.setAlignment = Icon.align

function Icon:setLeft()
    return self:align("Left")
end

function Icon:setRight()
    return self:align("Right")
end

--==================================================
-- STATE METHODS
--==================================================

function Icon:select(source, sourceIcon)
    self:_setState(true, source or "User", sourceIcon or self)
    return self
end

function Icon:deselect(source, sourceIcon)
    self:_setState(false, source or "User", sourceIcon or self)
    return self
end

function Icon:toggle()
    if self.isSelected then
        self:deselect("User", self)
    else
        self:select("User", self)
    end

    return self
end

function Icon:autoDeselect(bool)
    if bool == nil then
        bool = true
    end

    self.deselectWhenOtherIconSelected = bool
    return self
end

function Icon:oneClick(bool)
    if self.oneClickConnection then
        self.oneClickConnection:Disconnect()
        self.oneClickConnection = nil
    end

    if bool == nil or bool then
        self.oneClickConnection = self.selected:Connect(function()
            self:deselect("OneClick", self)
        end)
    end

    return self
end

function Icon:lock()
    self.locked = true
    return self
end

function Icon:unlock()
    self.locked = false
    return self
end

--==================================================
-- BINDING METHODS
--==================================================

function Icon:bindToggleItem(item)
    if typeof(item) ~= "Instance"
        or not (item:IsA("GuiObject") or item:IsA("LayerCollector")) then
        error("Toggle item must be a GuiObject or LayerCollector!", 2)
    end

    self.toggleItems[item] = true
    return self
end

function Icon:unbindToggleItem(item)
    self.toggleItems[item] = nil
    return self
end

function Icon:bindEvent(eventName, callback)
    local event = self[eventName]

    assert(type(event) == "table" and event.Connect, "argument[1] must be a valid icon event name!")
    assert(type(callback) == "function", "argument[2] must be a function!")

    local existing = self.bindedEvents[eventName]

    if existing then
        existing:Disconnect()
    end

    self.bindedEvents[eventName] = event:Connect(function(...)
        callback(self, ...)
    end)

    return self
end

function Icon:unbindEvent(eventName)
    local connection = self.bindedEvents[eventName]

    if connection then
        connection:Disconnect()
        self.bindedEvents[eventName] = nil
    end

    return self
end

function Icon:bindToggleKey(keyCode)
    assert(typeof(keyCode) == "EnumItem", "argument[1] must be a KeyCode EnumItem!")
    self.toggleKeys[keyCode] = true
    return self
end

function Icon:unbindToggleKey(keyCode)
    self.toggleKeys[keyCode] = nil
    return self
end

function Icon:call(callback, ...)
    local args = table.pack(...)

    task.spawn(function()
        callback(self, table.unpack(args, 1, args.n))
    end)

    return self
end

--==================================================
-- DESTROY
--==================================================

function Icon:destroy()
    if self.isDestroyed then
        return
    end

    self.isDestroyed = true
    icons[self] = nil

    for _, connection in ipairs(self.connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    for _, connection in pairs(self.bindedEvents) do
        connection:Disconnect()
    end

    if self.oneClickConnection then
        self.oneClickConnection:Disconnect()
    end

    self.selected:Destroy()
    self.deselected:Destroy()
    self.toggled:Destroy()

    self.widget:Destroy()
end
Icon.Destroy = Icon.destroy

--==================================================
-- STATIC FUNCTIONS
--==================================================

function Icon.getIcons()
    local list = {}

    for icon in pairs(icons) do
        table.insert(list, icon)
    end

    return list
end

function Icon.getIcon(name)
    for icon in pairs(icons) do
        if icon.name == name then
            return icon
        end
    end

    return nil
end

function Icon.setTopbarEnabled(bool)
    gui.Enabled = bool
end

local function relayout()
    barHeight = getBarHeight()
    iconSize = math.clamp(barHeight - 8, 28, 44)

    local left = getLeftOffset()
    local right = Icon.rightOffset

    holders.Left.Position = UDim2.fromOffset(left, 0)
    holders.Left.Size = UDim2.new(0.5, -left, 0, barHeight)

    holders.Right.Position = UDim2.new(1, -right, 0, 0)
    holders.Right.Size = UDim2.new(0.5, -right, 0, barHeight)

    for icon in pairs(icons) do
        icon:_refresh()
    end
end

-- Call this after changing Icon.leftOffset / Icon.rightOffset.
Icon.relayout = relayout

--==================================================
-- CLEANUP + START
--==================================================

local cleanedUp = false

local function cleanup()
    if cleanedUp then
        return
    end

    cleanedUp = true

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    for icon in pairs(icons) do
        icon:destroy()
    end

    anySelected:Destroy()

    pcall(function()
        gui:Destroy()
    end)

    if env.TopbarIconCleanup == cleanup then
        env.TopbarIconCleanup = nil
    end
end

env.TopbarIconCleanup = cleanup
env.TopbarIcon = Icon

pcall(function()
    table.insert(connections, GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(relayout))
end)

relayout()
gui.Parent = CoreGui

return Icon