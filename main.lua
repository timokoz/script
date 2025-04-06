local OrionLib = loadstring(game:HttpGet(('https://raw.githubusercontent.com/jensonhirst/Orion/refs/heads/main/source')))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = game.Workspace.CurrentCamera

-- Error handling function
local function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        warn("Error in function:", result)
        return nil
    end
    return result
end

-- Game compatibility check
local function isGameCompatible()
    local success, _ = pcall(function()
        return Players.LocalPlayer and Players.LocalPlayer.Character
    end)
    return success
end

if not isGameCompatible() then
    warn("Game is not compatible with this script")
    return
end

local player = Players.LocalPlayer
local character = nil
local humanoid = nil
local rootPart = nil

-- Menu visibility state
local menuVisible = true

-- Movement settings
_G.Bhop = false
_G.BhopSpeed = 30
_G.PixelSurf = false
_G.ShowVelocity = false

-- Pixel surf constants (update these values)
local WALL_CHECK_DISTANCE = 2.5
local PIXEL_SURF_FORCE = 50
local PIXEL_SURF_GRAVITY = 0.5
local PIXEL_SURF_INCREMENT = 0.3
local PIXEL_SURF_MAX_SPEED = 45
local PIXEL_SURF_MIN_SPEED = 16
local currentPixelSpeed = PIXEL_SURF_MIN_SPEED
local isPixelSurfing = false
local pixelNormal = Vector3.new()

-- Aimbot settings
_G.Aimbot = false
_G.AimbotRange = 100
_G.AimbotSmoothness = 0.5
_G.AimbotFOV = 100
_G.AimbotTargetPart = "Head"
_G.AimbotKey = Enum.UserInputType.MouseButton2
_G.AimbotLock = false

-- ESP settings
_G.ESP = false
_G.ESPColor = Color3.fromRGB(255, 0, 0)
_G.ESPTransparency = 0.5
_G.ESPFOV = false
_G.ESPFOVColor = Color3.fromRGB(255, 255, 255)
_G.ESPFOVTransparency = 0.5

-- ESP Settings
local ESP_SETTINGS = {
    BoxOutlineColor = Color3.new(0, 0, 0),
    BoxColor = Color3.new(1, 1, 1),
    NameColor = Color3.new(1, 1, 1),
    HealthOutlineColor = Color3.new(0, 0, 0),
    HealthHighColor = Color3.new(0, 1, 0),
    HealthLowColor = Color3.new(1, 0, 0),
    CharSize = Vector2.new(4, 6),
    Teamcheck = false,
    WallCheck = false,
    Enabled = false,
    ShowBox = false,
    BoxType = "2D",
    ShowName = false,
    ShowHealth = false,
    ShowDistance = false,
    ShowSkeletons = false,
    ShowTracer = false,
    TracerColor = Color3.new(1, 1, 1), 
    TracerThickness = 2,
    SkeletonsColor = Color3.new(1, 1, 1),
    TracerPosition = "Bottom",
}

local bones = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "LowerTorso"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"}
}

local cache = {}

-- Character setup with error handling
local function setupCharacter()
    local success, result = pcall(function()
        character = player.Character
        if character then
            humanoid = character:FindFirstChild("Humanoid")
            rootPart = character:FindFirstChild("HumanoidRootPart")
        end
    end)
    
    if not success then
        warn("Error in setupCharacter:", result)
        character = nil
        humanoid = nil
        rootPart = nil
    end
end

-- Safe character setup
setupCharacter()
player.CharacterAdded:Connect(function()
    task.wait(0.1) -- Wait for character to fully load
    setupCharacter()
end)
player.CharacterRemoving:Connect(function()
    character = nil
    humanoid = nil
    rootPart = nil
end)

-- Wall check function with error handling
local function checkForWall()
    if not character or not rootPart then return nil, nil end
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {character}

    -- Check right wall
    local rightRay = workspace:Raycast(rootPart.Position, rootPart.CFrame.RightVector * WALL_CHECK_DISTANCE, params)
    if rightRay then
        return rightRay.Normal, rightRay.Position
    end

    -- Check left wall
    local leftRay = workspace:Raycast(rootPart.Position, rootPart.CFrame.RightVector * -WALL_CHECK_DISTANCE, params)
    if leftRay then
        return leftRay.Normal, leftRay.Position
    end

    return nil, nil
end

-- ESP functions
local function create(class, properties)
    local drawing = Drawing.new(class)
    for property, value in pairs(properties) do
        drawing[property] = value
    end
    return drawing
end

local function createEsp(player)
    local esp = {
        tracer = create("Line", {
            Thickness = ESP_SETTINGS.TracerThickness,
            Color = ESP_SETTINGS.TracerColor,
            Transparency = 0.5
        }),
        boxOutline = create("Square", {
            Color = ESP_SETTINGS.BoxOutlineColor,
            Thickness = 3,
            Filled = false
        }),
        box = create("Square", {
            Color = ESP_SETTINGS.BoxColor,
            Thickness = 1,
            Filled = false
        }),
        name = create("Text", {
            Color = ESP_SETTINGS.NameColor,
            Outline = true,
            Center = true,
            Size = 13
        }),
        healthOutline = create("Line", {
            Thickness = 3,
            Color = ESP_SETTINGS.HealthOutlineColor
        }),
        health = create("Line", {
            Thickness = 1
        }),
        distance = create("Text", {
            Color = Color3.new(1, 1, 1),
            Size = 12,
            Outline = true,
            Center = true
        }),
        boxLines = {},
        skeletonlines = {}
    }

    cache[player] = esp
end

local function isPlayerBehindWall(player)
    local character = player.Character
    if not character then return false end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    local ray = Ray.new(Camera.CFrame.Position, (rootPart.Position - Camera.CFrame.Position).Unit * (rootPart.Position - Camera.CFrame.Position).Magnitude)
    local hit, position = workspace:FindPartOnRayWithIgnoreList(ray, {player.Character, character})
    
    return hit and hit:IsA("Part")
end

local function removeEsp(player)
    local esp = cache[player]
    if not esp then return end

    for _, drawing in pairs(esp) do
        if typeof(drawing) == "Instance" then
            drawing:Remove()
        end
    end

    cache[player] = nil
end

local function updateEsp()
    for player, esp in pairs(cache) do
        local character, team = player.Character, player.Team
        if character and (not ESP_SETTINGS.Teamcheck or (team and team ~= player.Team)) then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local head = character:FindFirstChild("Head")
            local humanoid = character:FindFirstChild("Humanoid")
            local isBehindWall = ESP_SETTINGS.WallCheck and isPlayerBehindWall(player)
            local shouldShow = not isBehindWall and ESP_SETTINGS.Enabled
            if rootPart and head and humanoid and shouldShow then
                local position, onScreen = Camera:WorldToViewportPoint(rootPart.Position)
                if onScreen then
                    local hrp2D = Camera:WorldToViewportPoint(rootPart.Position)
                    local charSize = (Camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0)).Y - Camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 2.6, 0)).Y) / 2
                    local boxSize = Vector2.new(math.floor(charSize * 1.8), math.floor(charSize * 1.9))
                    local boxPosition = Vector2.new(math.floor(hrp2D.X - charSize * 1.8 / 2), math.floor(hrp2D.Y - charSize * 1.6 / 2))

                    if ESP_SETTINGS.ShowName then
                        esp.name.Visible = true
                        esp.name.Text = string.lower(player.Name)
                        esp.name.Position = Vector2.new(boxSize.X / 2 + boxPosition.X, boxPosition.Y - 16)
                        esp.name.Color = ESP_SETTINGS.NameColor
                    else
                        esp.name.Visible = false
                    end

                    if ESP_SETTINGS.ShowBox then
                        if ESP_SETTINGS.BoxType == "2D" then
                            esp.boxOutline.Size = boxSize
                            esp.boxOutline.Position = boxPosition
                            esp.box.Size = boxSize
                            esp.box.Position = boxPosition
                            esp.box.Color = ESP_SETTINGS.BoxColor
                            esp.box.Visible = true
                            esp.boxOutline.Visible = true
                            for _, line in ipairs(esp.boxLines) do
                                line:Remove()
                            end
                        elseif ESP_SETTINGS.BoxType == "Corner Box Esp" then
                            local lineW = (boxSize.X / 5)
                            local lineH = (boxSize.Y / 6)
                            local lineT = 1
    
                            if #esp.boxLines == 0 then
                                for i = 1, 16 do
                                    local boxLine = create("Line", {
                                        Thickness = 1,
                                        Color = ESP_SETTINGS.BoxColor,
                                        Transparency = 1
                                    })
                                    esp.boxLines[#esp.boxLines + 1] = boxLine
                                end
                            end
    
                            local boxLines = esp.boxLines
    
                            -- top left
                            boxLines[1].From = Vector2.new(boxPosition.X - lineT, boxPosition.Y - lineT)
                            boxLines[1].To = Vector2.new(boxPosition.X + lineW, boxPosition.Y - lineT)
    
                            boxLines[2].From = Vector2.new(boxPosition.X - lineT, boxPosition.Y - lineT)
                            boxLines[2].To = Vector2.new(boxPosition.X - lineT, boxPosition.Y + lineH)
    
                            -- top right
                            boxLines[3].From = Vector2.new(boxPosition.X + boxSize.X - lineW, boxPosition.Y - lineT)
                            boxLines[3].To = Vector2.new(boxPosition.X + boxSize.X + lineT, boxPosition.Y - lineT)
    
                            boxLines[4].From = Vector2.new(boxPosition.X + boxSize.X + lineT, boxPosition.Y - lineT)
                            boxLines[4].To = Vector2.new(boxPosition.X + boxSize.X + lineT, boxPosition.Y + lineH)
    
                            -- bottom left
                            boxLines[5].From = Vector2.new(boxPosition.X - lineT, boxPosition.Y + boxSize.Y - lineH)
                            boxLines[5].To = Vector2.new(boxPosition.X - lineT, boxPosition.Y + boxSize.Y + lineT)
    
                            boxLines[6].From = Vector2.new(boxPosition.X - lineT, boxPosition.Y + boxSize.Y + lineT)
                            boxLines[6].To = Vector2.new(boxPosition.X + lineW, boxPosition.Y + boxSize.Y + lineT)
    
                            -- bottom right
                            boxLines[7].From = Vector2.new(boxPosition.X + boxSize.X - lineW, boxPosition.Y + boxSize.Y + lineT)
                            boxLines[7].To = Vector2.new(boxPosition.X + boxSize.X + lineT, boxPosition.Y + boxSize.Y + lineT)
    
                            boxLines[8].From = Vector2.new(boxPosition.X + boxSize.X + lineT, boxPosition.Y + boxSize.Y - lineH)
                            boxLines[8].To = Vector2.new(boxPosition.X + boxSize.X + lineT, boxPosition.Y + boxSize.Y + lineT)
    
                            -- inline
                            for i = 9, 16 do
                                boxLines[i].Thickness = 2
                                boxLines[i].Color = ESP_SETTINGS.BoxOutlineColor
                                boxLines[i].Transparency = 1
                            end
    
                            boxLines[9].From = Vector2.new(boxPosition.X, boxPosition.Y)
                            boxLines[9].To = Vector2.new(boxPosition.X, boxPosition.Y + lineH)
    
                            boxLines[10].From = Vector2.new(boxPosition.X, boxPosition.Y)
                            boxLines[10].To = Vector2.new(boxPosition.X + lineW, boxPosition.Y)
    
                            boxLines[11].From = Vector2.new(boxPosition.X + boxSize.X - lineW, boxPosition.Y)
                            boxLines[11].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y)
    
                            boxLines[12].From = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y)
                            boxLines[12].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + lineH)
    
                            boxLines[13].From = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y - lineH)
                            boxLines[13].To = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y)
    
                            boxLines[14].From = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y)
                            boxLines[14].To = Vector2.new(boxPosition.X + lineW, boxPosition.Y + boxSize.Y)
    
                            boxLines[15].From = Vector2.new(boxPosition.X + boxSize.X - lineW, boxPosition.Y + boxSize.Y)
                            boxLines[15].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y)
    
                            boxLines[16].From = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y - lineH)
                            boxLines[16].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y)
    
                            for _, line in ipairs(boxLines) do
                                line.Visible = true
                            end
                            esp.box.Visible = false
                            esp.boxOutline.Visible = false
                        end
                    else
                        esp.box.Visible = false
                        esp.boxOutline.Visible = false
                        for _, line in ipairs(esp.boxLines) do
                            line:Remove()
                        end
                        esp.boxLines = {}
                    end

                    if ESP_SETTINGS.ShowHealth then
                        esp.healthOutline.Visible = true
                        esp.health.Visible = true
                        local healthPercentage = player.Character.Humanoid.Health / player.Character.Humanoid.MaxHealth
                        esp.healthOutline.From = Vector2.new(boxPosition.X - 6, boxPosition.Y + boxSize.Y)
                        esp.healthOutline.To = Vector2.new(esp.healthOutline.From.X, esp.healthOutline.From.Y - boxSize.Y)
                        esp.health.From = Vector2.new((boxPosition.X - 5), boxPosition.Y + boxSize.Y)
                        esp.health.To = Vector2.new(esp.health.From.X, esp.health.From.Y - (player.Character.Humanoid.Health / player.Character.Humanoid.MaxHealth) * boxSize.Y)
                        esp.health.Color = ESP_SETTINGS.HealthLowColor:Lerp(ESP_SETTINGS.HealthHighColor, healthPercentage)
                    else
                        esp.healthOutline.Visible = false
                        esp.health.Visible = false
                    end

                    if ESP_SETTINGS.ShowDistance then
                        local distance = (Camera.CFrame.p - rootPart.Position).Magnitude
                        esp.distance.Text = string.format("%.1f studs", distance)
                        esp.distance.Position = Vector2.new(boxPosition.X + boxSize.X / 2, boxPosition.Y + boxSize.Y + 5)
                        esp.distance.Visible = true
                    else
                        esp.distance.Visible = false
                    end

                    if ESP_SETTINGS.ShowSkeletons then
                        if #esp.skeletonlines == 0 then
                            for _, bonePair in ipairs(bones) do
                                local parentBone, childBone = bonePair[1], bonePair[2]
                                
                                if player.Character and player.Character[parentBone] and player.Character[childBone] then
                                    local skeletonLine = create("Line", {
                                        Thickness = 1,
                                        Color = ESP_SETTINGS.SkeletonsColor,
                                        Transparency = 1
                                    })
                                    esp.skeletonlines[#esp.skeletonlines + 1] = {skeletonLine, parentBone, childBone}
                                end
                            end
                        end
                    
                        for _, lineData in ipairs(esp.skeletonlines) do
                            local skeletonLine = lineData[1]
                            local parentBone, childBone = lineData[2], lineData[3]
                    
                            if player.Character and player.Character[parentBone] and player.Character[childBone] then
                                local parentPosition = Camera:WorldToViewportPoint(player.Character[parentBone].Position)
                                local childPosition = Camera:WorldToViewportPoint(player.Character[childBone].Position)
                    
                                skeletonLine.From = Vector2.new(parentPosition.X, parentPosition.Y)
                                skeletonLine.To = Vector2.new(childPosition.X, childPosition.Y)
                                skeletonLine.Color = ESP_SETTINGS.SkeletonsColor
                                skeletonLine.Visible = true
                            else
                                skeletonLine:Remove()
                            end
                        end
                    else
                        for _, lineData in ipairs(esp.skeletonlines) do
                            local skeletonLine = lineData[1]
                            skeletonLine:Remove()
                        end
                        esp.skeletonlines = {}
                    end                    

                    if ESP_SETTINGS.ShowTracer then
                        local tracerY
                        if ESP_SETTINGS.TracerPosition == "Top" then
                            tracerY = 0
                        elseif ESP_SETTINGS.TracerPosition == "Middle" then
                            tracerY = Camera.ViewportSize.Y / 2
                        else
                            tracerY = Camera.ViewportSize.Y
                        end
                        if ESP_SETTINGS.Teamcheck and player.TeamColor == player.TeamColor then
                            esp.tracer.Visible = false
                        else
                            esp.tracer.Visible = true
                            esp.tracer.From = Vector2.new(Camera.ViewportSize.X / 2, tracerY)
                            esp.tracer.To = Vector2.new(hrp2D.X, hrp2D.Y)            
                        end
                    else
                        esp.tracer.Visible = false
                    end
                else
                    for _, drawing in pairs(esp) do
                        if typeof(drawing) == "Instance" then
                            drawing.Visible = false
                        end
                    end
                    for _, lineData in ipairs(esp.skeletonlines) do
                        local skeletonLine = lineData[1]
                        skeletonLine:Remove()
                    end
                    esp.skeletonlines = {}
                    for _, line in ipairs(esp.boxLines) do
                        line:Remove()
                    end
                    esp.boxLines = {}
                end
            else
                for _, drawing in pairs(esp) do
                    if typeof(drawing) == "Instance" then
                        drawing.Visible = false
                    end
                end
                for _, lineData in ipairs(esp.skeletonlines) do
                    local skeletonLine = lineData[1]
                    skeletonLine:Remove()
                end
                esp.skeletonlines = {}
                for _, line in ipairs(esp.boxLines) do
                    line:Remove()
                end
                esp.boxLines = {}
            end
        else
            for _, drawing in pairs(esp) do
                if typeof(drawing) == "Instance" then
                    drawing.Visible = false
                end
            end
            for _, lineData in ipairs(esp.skeletonlines) do
                local skeletonLine = lineData[1]
                skeletonLine:Remove()
            end
            esp.skeletonlines = {}
            for _, line in ipairs(esp.boxLines) do
                line:Remove()
            end
            esp.boxLines = {}
        end
    end
end

-- Aimbot functions
local function getClosestPlayer()
    local closestPlayer = nil
    local shortestDistance = _G.AimbotRange
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
            local targetPart = player.Character:FindFirstChild(_G.AimbotTargetPart)
            if targetPart then
                local distance = (targetPart.Position - Camera.CFrame.Position).Magnitude
                if distance <= shortestDistance then
                    local screenPoint = Camera:WorldToViewportPoint(targetPart.Position)
                    if screenPoint.Z > 0 then
                        local mousePos = UserInputService:GetMouseLocation()
                        local distanceToMouse = (Vector2.new(screenPoint.X, screenPoint.Y) - mousePos).Magnitude
                        if distanceToMouse <= _G.AimbotFOV then
                            closestPlayer = player
                            shortestDistance = distance
                        end
                    end
                end
            end
        end
    end
    
    return closestPlayer
end

local function updateAimbot()
    if not _G.Aimbot then return end
    
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local targetPlayer = getClosestPlayer()
        if targetPlayer and targetPlayer.Character then
            local targetPart = targetPlayer.Character:FindFirstChild(_G.AimbotTargetPart)
            if targetPart then
                local targetPosition = targetPart.Position
                local cameraPosition = Camera.CFrame.Position
                local direction = (targetPosition - cameraPosition).Unit
                
                if _G.AimbotLock then
                    Camera.CFrame = CFrame.new(cameraPosition, targetPosition)
                else
                    local currentLook = Camera.CFrame.LookVector
                    local targetLook = direction
                    local newLook = currentLook:Lerp(targetLook, _G.AimbotSmoothness)
                    Camera.CFrame = CFrame.new(cameraPosition, cameraPosition + newLook)
                end
            end
        end
    end
end

-- Create Orion Window
local Window = OrionLib:MakeWindow({
    Name = "Movement Script",
    HidePremium = false,
    SaveConfig = true,
    ConfigFolder = "MovementScript"
})

-- Create Tabs
local MovementTab = Window:MakeTab({
    Name = "Movement",
    Icon = "rbxassetid://4485411256",
    PremiumOnly = false
})

local AimbotTab = Window:MakeTab({
    Name = "Aimbot",
    Icon = "rbxassetid://4485411256",
    PremiumOnly = false
})

local ESPTab = Window:MakeTab({
    Name = "ESP",
    Icon = "rbxassetid://4485411256",
    PremiumOnly = false
})

-- Movement Section
local MovementSection = MovementTab:AddSection({
    Name = "Movement"
})

MovementSection:AddToggle({
    Name = "Bunny Hop",
    Default = false,
    Callback = function(Value)
        _G.Bhop = Value
    end
})

MovementSection:AddToggle({
    Name = "Pixel Surf",
    Default = false,
    Callback = function(Value)
        _G.PixelSurf = Value
    end
})

MovementSection:AddSlider({
    Name = "Bhop Speed",
    Min = 20,
    Max = 50,
    Default = 30,
    Color = Color3.fromRGB(255,255,255),
    Increment = 1,
    ValueName = "Speed",
    Callback = function(Value)
        _G.BhopSpeed = Value
    end
})

-- Velocity Indicator Section
local VelocitySection = MovementTab:AddSection({
    Name = "Velocity Indicator"
})

VelocitySection:AddToggle({
    Name = "Show Velocity",
    Default = false,
    Callback = function(Value)
        _G.ShowVelocity = Value
    end
})

-- Create bottom center indicators
local function createBottomIndicators()
    local ScreenGui = Instance.new("ScreenGui")
    local Frame = Instance.new("Frame")
    local SpeedLabel = Instance.new("TextLabel")
    local VerticalLabel = Instance.new("TextLabel")
    local PixelLabel = Instance.new("TextLabel")
    
    ScreenGui.Name = "BottomIndicators"
    ScreenGui.Parent = game.CoreGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    Frame.Name = "MainFrame"
    Frame.Parent = ScreenGui
    Frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Frame.BackgroundTransparency = 0.5
    Frame.BorderSizePixel = 0
    Frame.Position = UDim2.new(0.5, -100, 1, -100)
    Frame.Size = UDim2.new(0, 200, 0, 80)
    Frame.AnchorPoint = Vector2.new(0.5, 1)
    
    SpeedLabel.Name = "SpeedLabel"
    SpeedLabel.Parent = Frame
    SpeedLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    SpeedLabel.BackgroundTransparency = 1
    SpeedLabel.Position = UDim2.new(0, 10, 0, 10)
    SpeedLabel.Size = UDim2.new(1, -20, 0, 20)
    SpeedLabel.Font = Enum.Font.GothamBold
    SpeedLabel.Text = "SPD: 0"
    SpeedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    SpeedLabel.TextSize = 14
    
    VerticalLabel.Name = "VerticalLabel"
    VerticalLabel.Parent = Frame
    VerticalLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    VerticalLabel.BackgroundTransparency = 1
    VerticalLabel.Position = UDim2.new(0, 10, 0, 40)
    VerticalLabel.Size = UDim2.new(1, -20, 0, 20)
    VerticalLabel.Font = Enum.Font.GothamBold
    VerticalLabel.Text = "VRT: 0"
    VerticalLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    VerticalLabel.TextSize = 14
    
    PixelLabel.Name = "PixelLabel"
    PixelLabel.Parent = Frame
    PixelLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    PixelLabel.BackgroundTransparency = 1
    PixelLabel.Position = UDim2.new(0, 10, 0, 70)
    PixelLabel.Size = UDim2.new(1, -20, 0, 20)
    PixelLabel.Font = Enum.Font.GothamBold
    PixelLabel.Text = "PX: NO"
    PixelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    PixelLabel.TextSize = 14
    
    return ScreenGui, SpeedLabel, VerticalLabel, PixelLabel
end

local BottomGui, BottomSpeedLabel, BottomVerticalLabel, BottomPixelLabel = createBottomIndicators()
BottomGui.Enabled = false

-- Create FOV Circle
local function createFOVCircle()
    local ScreenGui = Instance.new("ScreenGui")
    local Circle = Instance.new("Frame")
    
    ScreenGui.Name = "FOVCircle"
    ScreenGui.Parent = game.CoreGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    Circle.Name = "Circle"
    Circle.Parent = ScreenGui
    Circle.BackgroundColor3 = _G.ESPFOVColor
    Circle.BackgroundTransparency = _G.ESPFOVTransparency
    Circle.BorderSizePixel = 0
    Circle.Position = UDim2.new(0.5, -_G.AimbotFOV, 0.5, -_G.AimbotFOV)
    Circle.Size = UDim2.new(0, _G.AimbotFOV * 2, 0, _G.AimbotFOV * 2)
    Circle.AnchorPoint = Vector2.new(0.5, 0.5)
    
    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(1, 0)
    UICorner.Parent = Circle
    
    return ScreenGui, Circle
end

local FOVGui, FOVCircle = createFOVCircle()
FOVGui.Enabled = false

-- ESP Section
local ESPSection = ESPTab:AddSection({
    Name = "ESP Settings"
})

ESPSection:AddToggle({
    Name = "Enable ESP",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.Enabled = Value
        if not Value then
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= Players.LocalPlayer then
                    removeEsp(player)
                end
            end
        end
    end
})

ESPSection:AddToggle({
    Name = "Show Box",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.ShowBox = Value
    end
})

ESPSection:AddDropdown({
    Name = "Box Type",
    Default = "2D",
    Options = {"2D", "Corner Box Esp"},
    Callback = function(Value)
        ESP_SETTINGS.BoxType = Value
    end
})

ESPSection:AddToggle({
    Name = "Show Name",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.ShowName = Value
    end
})

ESPSection:AddToggle({
    Name = "Show Health",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.ShowHealth = Value
    end
})

ESPSection:AddToggle({
    Name = "Show Distance",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.ShowDistance = Value
    end
})

ESPSection:AddToggle({
    Name = "Show Skeletons",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.ShowSkeletons = Value
    end
})

ESPSection:AddToggle({
    Name = "Show Tracer",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.ShowTracer = Value
    end
})

ESPSection:AddDropdown({
    Name = "Tracer Position",
    Default = "Bottom",
    Options = {"Top", "Middle", "Bottom"},
    Callback = function(Value)
        ESP_SETTINGS.TracerPosition = Value
    end
})

ESPSection:AddColorpicker({
    Name = "ESP Color",
    Default = Color3.fromRGB(255, 0, 0),
    Callback = function(Value)
        ESP_SETTINGS.BoxColor = Value
        ESP_SETTINGS.NameColor = Value
        ESP_SETTINGS.TracerColor = Value
        ESP_SETTINGS.SkeletonsColor = Value
    end
})

ESPSection:AddToggle({
    Name = "Team Check",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.Teamcheck = Value
    end
})

ESPSection:AddToggle({
    Name = "Wall Check",
    Default = false,
    Callback = function(Value)
        ESP_SETTINGS.WallCheck = Value
    end
})

-- Aimbot Section
local AimbotSection = AimbotTab:AddSection({
    Name = "Aimbot Settings"
})

AimbotSection:AddToggle({
    Name = "Enable Aimbot",
    Default = false,
    Callback = function(Value)
        _G.Aimbot = Value
    end
})

AimbotSection:AddToggle({
    Name = "Aimlock",
    Default = false,
    Callback = function(Value)
        _G.AimbotLock = Value
    end
})

AimbotSection:AddSlider({
    Name = "Aimbot Range",
    Min = 50,
    Max = 500,
    Default = 100,
    Color = Color3.fromRGB(255,255,255),
    Increment = 10,
    ValueName = "Studs",
    Callback = function(Value)
        _G.AimbotRange = Value
    end
})

AimbotSection:AddSlider({
    Name = "Smoothness",
    Min = 0.1,
    Max = 1,
    Default = 0.5,
    Color = Color3.fromRGB(255,255,255),
    Increment = 0.1,
    ValueName = "Smooth",
    Callback = function(Value)
        _G.AimbotSmoothness = Value
    end
})

AimbotSection:AddSlider({
    Name = "FOV",
    Min = 10,
    Max = 500,
    Default = 100,
    Color = Color3.fromRGB(255,255,255),
    Increment = 10,
    ValueName = "FOV",
    Callback = function(Value)
        _G.AimbotFOV = Value
    end
})

AimbotSection:AddDropdown({
    Name = "Target Part",
    Default = "Head",
    Options = {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"},
    Callback = function(Value)
        _G.AimbotTargetPart = Value
    end
})

-- Initialize ESP for existing players
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= Players.LocalPlayer then
        createEsp(player)
    end
end

Players.PlayerAdded:Connect(function(player)
    if player ~= Players.LocalPlayer then
        createEsp(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeEsp(player)
end)

-- Main update loop with error handling
RunService.RenderStepped:Connect(function()
    if not character or not humanoid or humanoid.Health <= 0 then return end
    
    local success, result = pcall(function()
        -- Update ESP
        updateEsp()
        
        -- Update Aimbot
        updateAimbot()
        
        -- Update FOV Circle
        if _G.ESPFOV then
            FOVGui.Enabled = true
            FOVCircle.Size = UDim2.new(0, _G.AimbotFOV * 2, 0, _G.AimbotFOV * 2)
            FOVCircle.Position = UDim2.new(0.5, -_G.AimbotFOV, 0.5, -_G.AimbotFOV)
            FOVCircle.BackgroundColor3 = _G.ESPFOVColor
            FOVCircle.BackgroundTransparency = _G.ESPFOVTransparency
        else
            FOVGui.Enabled = false
        end
        
        -- Update bottom indicators
        if _G.ShowVelocity then
            BottomGui.Enabled = true
            
            local horizontalVelocity = Vector3.new(rootPart.Velocity.X, 0, rootPart.Velocity.Z)
            local speed = math.floor(horizontalVelocity.Magnitude)
            local verticalSpeed = math.floor(math.abs(rootPart.Velocity.Y))
            
            BottomSpeedLabel.Text = "SPD: " .. speed
            BottomVerticalLabel.Text = "VRT: " .. verticalSpeed
            BottomPixelLabel.Text = "PX: " .. (isPixelSurfing and "YES" or "NO")
        else
            BottomGui.Enabled = false
        end
        
        -- Bhop functionality
        if _G.Bhop then
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                humanoid.Jump = true
                local Speed = _G.BhopSpeed
                local Dir = Camera.CFrame.LookVector * Vector3.new(1, 0, 1)
                local Move = Vector3.new()

                Move = UserInputService:IsKeyDown(Enum.KeyCode.W) and Move + Dir or Move
                Move = UserInputService:IsKeyDown(Enum.KeyCode.S) and Move - Dir or Move
                Move = UserInputService:IsKeyDown(Enum.KeyCode.D) and Move + Vector3.new(-Dir.Z, 0, Dir.X) or Move
                Move = UserInputService:IsKeyDown(Enum.KeyCode.A) and Move + Vector3.new(Dir.Z, 0, -Dir.X) or Move
                
                if Move.Unit.X == Move.Unit.X then
                    Move = Move.Unit
                    rootPart.Velocity = Vector3.new(Move.X * Speed, rootPart.Velocity.Y, Move.Z * Speed)
                end
            end
        end
    end)
    
    if not success then
        warn("Error in main update loop:", result)
    end
end)

-- Pixel Surf functionality with error handling
RunService.Heartbeat:Connect(function(deltaTime)
    if not character or not humanoid or humanoid.Health <= 0 then return end
    
    -- Update ESP
    updateEsp()
    
    -- Update Aimbot
    updateAimbot()
    
    -- Update FOV Circle
    if _G.ESPFOV then
        FOVGui.Enabled = true
        FOVCircle.Size = UDim2.new(0, _G.AimbotFOV * 2, 0, _G.AimbotFOV * 2)
        FOVCircle.Position = UDim2.new(0.5, -_G.AimbotFOV, 0.5, -_G.AimbotFOV)
        FOVCircle.BackgroundColor3 = _G.ESPFOVColor
        FOVCircle.BackgroundTransparency = _G.ESPFOVTransparency
    else
        FOVGui.Enabled = false
    end
    
    -- Update bottom indicators
    if _G.ShowVelocity then
        BottomGui.Enabled = true
        
        local horizontalVelocity = Vector3.new(rootPart.Velocity.X, 0, rootPart.Velocity.Z)
        local speed = math.floor(horizontalVelocity.Magnitude)
        local verticalSpeed = math.floor(math.abs(rootPart.Velocity.Y))
        
        BottomSpeedLabel.Text = "SPD: " .. speed
        BottomVerticalLabel.Text = "VRT: " .. verticalSpeed
        BottomPixelLabel.Text = "PX: " .. (isPixelSurfing and "YES" or "NO")
    else
        BottomGui.Enabled = false
    end
    
    -- Pixel Surf functionality
    if _G.PixelSurf and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
        local normal, hitPos = checkForWall()
        
        if normal then
            isPixelSurfing = true
            pixelNormal = normal
            
            -- Wall stick force
            local surfForce = pixelNormal * PIXEL_SURF_FORCE
            rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + rootPart.CFrame.LookVector)
            rootPart.Velocity = Vector3.new(
                rootPart.Velocity.X,
                -PIXEL_SURF_GRAVITY,
                rootPart.Velocity.Z
            )
            
            -- Speed management
            currentPixelSpeed = math.min(currentPixelSpeed + PIXEL_SURF_INCREMENT, PIXEL_SURF_MAX_SPEED)
            
            -- Forward movement
            local forwardForce = rootPart.CFrame.LookVector * currentPixelSpeed
            rootPart.Velocity = Vector3.new(
                forwardForce.X,
                rootPart.Velocity.Y,
                forwardForce.Z
            )
        else
            if isPixelSurfing then
                -- Preserve momentum when leaving wall
                local jumpForce = pixelNormal * currentPixelSpeed * 0.5
                rootPart.Velocity = rootPart.Velocity + jumpForce
            end
            isPixelSurfing = false
            currentPixelSpeed = PIXEL_SURF_MIN_SPEED
        end
    else
        isPixelSurfing = false
        currentPixelSpeed = PIXEL_SURF_MIN_SPEED
    end
    
    -- Bhop functionality
    if _G.Bhop then
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            humanoid.Jump = true
            local Speed = _G.BhopSpeed
            local Dir = Camera.CFrame.LookVector * Vector3.new(1, 0, 1)
            local Move = Vector3.new()

            Move = UserInputService:IsKeyDown(Enum.KeyCode.W) and Move + Dir or Move
            Move = UserInputService:IsKeyDown(Enum.KeyCode.S) and Move - Dir or Move
            Move = UserInputService:IsKeyDown(Enum.KeyCode.D) and Move + Vector3.new(-Dir.Z, 0, Dir.X) or Move
            Move = UserInputService:IsKeyDown(Enum.KeyCode.A) and Move + Vector3.new(Dir.Z, 0, -Dir.X) or Move
            
            if Move.Unit.X == Move.Unit.X then
                Move = Move.Unit
                rootPart.Velocity = Vector3.new(Move.X * Speed, rootPart.Velocity.Y, Move.Z * Speed)
            end
        end
    end
end)

-- Menu toggle with error handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.RightShift then
        local success, result = pcall(function()
            menuVisible = not menuVisible
            Window:Toggle(menuVisible)
        end)
        
        if not success then
            warn("Error in menu toggle:", result)
        end
    end
end)

-- Cleanup on script termination
game:GetService("Players").PlayerRemoving:Connect(function(plr)
    if plr == player then
        -- Clean up ESP
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= Players.LocalPlayer then
                removeEsp(player)
            end
        end
        
        -- Clean up UI
        if BottomGui then
            BottomGui:Destroy()
        end
        if FOVGui then
            FOVGui:Destroy()
        end
    end
end)
