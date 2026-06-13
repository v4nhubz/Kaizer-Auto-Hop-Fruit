repeat task.wait() until game:IsLoaded()

-- â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
--   FRUIT HOPPER v2  â€”  Blox Fruits / Delta
-- â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService= game:GetService("TeleportService")
local HttpService    = game:GetService("HttpService")
local UIS            = game:GetService("UserInputService")

local lp = Players.LocalPlayer

-- statusText declarado aquÃ­ para que todas las funciones lo vean
local statusText = "Starting..."

local CONFIG = {
    MinPlayers  = 3,
    HopCooldown = 10,
    TPOffset    = 3,
    EquipFruit  = true,   -- auto-equipar fruta recogida
}

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  ESTADO
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local running       = false
local teamSelected  = false
local isHopping     = false
local lastHopTime   = -999
local hopperThread  = nil

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  HELPERS
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function gc()  return lp.Character end
local function getHRP()
    local c = gc(); if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart")
end

-- Tween puro con lerp â€” funciona a cualquier distancia sin rubber-band.
-- Dividimos el viaje en pasos de ~50 studs para que el servidor lo acepte.
local function moveTo(targetCF)
    local c = gc(); if not c then return end
    local h = c:FindFirstChild("HumanoidRootPart"); if not h then return end
    local startCF = h.CFrame
    local dist    = (targetCF.Position - startCF.Position).Magnitude
    local steps   = math.clamp(math.floor(dist / 40), 6, 60)

    -- Desactivar colisiÃ³n durante el movimiento para evitar rubber-band
    local oldCollide = h.CanCollide
    pcall(function() h.CanCollide = false end)

    for i = 1, steps do
        if not running then break end
        pcall(function() c:PivotTo(startCF:Lerp(targetCF, i / steps)) end)
        task.wait(0.05)
    end
    pcall(function() c:PivotTo(targetCF) end)

    -- Restaurar colisiÃ³n
    pcall(function() h.CanCollide = oldCollide end)
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  SELECCIÃ“N DE EQUIPO â€” solo CommF_ (btn:Fire() no existe)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function selectPirates()
    if lp.Team and lp.Team.Name == "Pirates" then return true end

    -- MÃ©todo principal: CommF_ SetTeam
    pcall(function()
        local r = ReplicatedStorage:FindFirstChild("Remotes")
        local f = r and r:FindFirstChild("CommF_")
        if f then f:InvokeServer("SetTeam","Pirates") end
    end)
    task.wait(0.5)
    if lp.Team and lp.Team.Name == "Pirates" then return true end

    -- MÃ©todo 2: RE/OnEventServiceActivity
    pcall(function()
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v:IsA("RemoteEvent") and v.Name == "RE/OnEventServiceActivity" then
                v:FireServer("TeamSelect/Team/Pirates"); break
            end
        end
    end)
    task.wait(0.5)
    return lp.Team and lp.Team.Name == "Pirates"
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  DETECTAR FRUTA MÃS CERCANA
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function getNearestFruit()
    local h = getHRP(); if not h then return nil, math.huge end

    -- Si ya tienes UNA Demon Fruit equipada, no buscar mÃ¡s
    -- (en BF solo puedes tener una a la vez)
    local c = gc()
    if c then
        for _, t in pairs(c:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("WeaponType") == "Demon Fruit" then
                return nil, math.huge  -- ya tienes una, no buscar
            end
        end
    end

    local best, bestD = nil, math.huge
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:FindFirstChild("Handle") then
            local isFruit = obj:GetAttribute("FruitName")
                         or obj:GetAttribute("ItemName")
                         or obj.Name:lower():find("fruit")
            if isFruit then
                local d = (obj.Handle.Position - h.Position).Magnitude
                if d < bestD then bestD = d; best = obj end
            end
        end
    end
    return best, bestD
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  DETECTAR FRUTA EN BACKPACK
--  En BF la fruta se guarda automÃ¡ticamente
--  en el inventario al recogerla si tienes
--  espacio. Este listener lo detecta y avisa.
--  Si el jugador quiere guardarla manualmente
--  usa CommF_ "StoreBloxFruit".
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local VIM = game:GetService("VirtualInputManager")

-- Buscar y clickear el botÃ³n de guardar fruta en la UI de BF
local function clickStoreFruitButton()
    local pg2 = lp:FindFirstChild("PlayerGui"); if not pg2 then return false end

    -- BF usa estos nombres de botÃ³n para guardar fruta
    local storeNames = {
        "StoreButton","StoreFruit","Store","SavingFruit","SaveFruit",
        "btnStore","Btn_Store","StoreBloxFruit","ConfirmStore"
    }
    local storeTexts = {"store","guardar","save fruit","keep","guardar fruta"}

    for _, gui in pairs(pg2:GetDescendants()) do
        if not gui:IsA("TextButton") and not gui:IsA("ImageButton") then continue end
        if not gui.Visible then continue end

        local nameL = gui.Name:lower()
        local textL = gui:IsA("TextButton") and gui.Text:lower() or ""

        local match = false
        for _, n in ipairs(storeNames) do
            if nameL == n:lower() then match = true; break end
        end
        if not match then
            for _, t in ipairs(storeTexts) do
                if textL:find(t) then match = true; break end
            end
        end

        if match then
            -- VIM click directo en el centro del botÃ³n
            pcall(function()
                local abs = gui.AbsolutePosition
                local sz  = gui.AbsoluteSize
                local cx  = math.floor(abs.X + sz.X/2)
                local cy  = math.floor(abs.Y + sz.Y/2)
                VIM:SendMouseButtonEvent(cx, cy, 0, true,  game, 1)
                task.wait(0.08)
                VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
            end)
            return true
        end
    end
    return false
end

local function setupFruitDetection()
    workspace.DescendantRemoving:Connect(function(obj)
        if not CONFIG.EquipFruit then return end
        if not (obj:IsA("Model") and obj:FindFirstChild("Handle")) then return end
        local isFruit = obj:GetAttribute("FruitName") or obj:GetAttribute("ItemName")
                     or obj.Name:lower():find("fruit")
        if not isFruit then return end

        local h = getHRP()
        local handle = obj:FindFirstChild("Handle")
        if h and handle then
            local dist = (handle.Position - h.Position).Magnitude
            if dist < 15 then
                local name = obj:GetAttribute("FruitName") or obj.Name
                statusText = "Getting Fruit Info"..name.."..."
                -- Intentar clickear el botÃ³n Store de BF
                task.spawn(function()
                    task.wait(0.3)
                    local clicked = clickStoreFruitButton()
                    if clicked then
                        statusText = "Storing"..name.."Stored"
                    else
                        -- Fallback: remote directo
                        pcall(function()
                            local r = ReplicatedStorage:FindFirstChild("Remotes")
                            local f = r and r:FindFirstChild("CommF_")
                            if f then
                                pcall(function() f:InvokeServer("StoreBloxFruit", name) end)
                            end
                        end)
                        statusText = "ðŸ’¾ "..name.." recogida!"
                    end
                end)
            end
        end
    end)
end

local function storeFruitInBackpack()
    statusText = "Collected"
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  SERVER HOP â€” Sacred Code method
--  Usa __ServerBrowser interno de BF.
--  Para fruit hunting queremos servers con POCOS
--  jugadores (menos competencia por frutas).
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local _browser = ReplicatedStorage:FindFirstChild("__ServerBrowser")
local _place   = game.PlaceId
local _id      = game.JobId

local function serverHop()
    if isHopping then return false end
    if os.clock() - lastHopTime < CONFIG.HopCooldown then return false end
    isHopping   = true
    lastHopTime = os.clock()
    task.delay(15, function() isHopping = false end)

    statusText = "Looking for Servers."

    local allServers = {}
    local found      = false

    -- MÃ©todo 1: __ServerBrowser (Sacred Code â€” mÃ¡s confiable)
    if _browser then
        local pending = 0
        for page = 1, 10 do
            if found then break end
            pending += 1
            task.spawn(function()
                local ok, res = pcall(function()
                    return _browser:InvokeServer(page)
                end)
                if ok and type(res) == "table" then
                    for uuid, info in pairs(res) do
                        if type(info) == "table" and info.Count and uuid ~= _id then
                            table.insert(allServers, { uuid = uuid, count = info.Count or 0 })
                            found = true
                        end
                    end
                end
                pending -= 1
            end)
        end
        -- Esperar resultados mÃ¡x 5s
        local waited = 0
        while pending > 0 and waited < 5 do
            task.wait(0.2); waited += 0.2
            if found and waited > 1 then break end
        end
    end

    -- MÃ©todo 2: API pÃºblica (fallback si no hay __ServerBrowser)
    if #allServers == 0 then
        statusText = "ðŸ”„ Usando API pÃºblica..."
        for _, ord in ipairs({"Asc", "Desc"}) do
            pcall(function()
                local raw = game:HttpGet(
                    "https://games.roblox.com/v1/games/"..
                    _place.."/servers/Public?sortOrder="..ord.."&limit=100"
                )
                local data = HttpService:JSONDecode(raw)
                if data and data.data then
                    for _, sv in ipairs(data.data) do
                        if sv.id and sv.id ~= _id then
                            table.insert(allServers, { uuid = sv.id, count = sv.playing or 0 })
                        end
                    end
                end
            end)
            if #allServers > 0 then break end
        end
    end

    if #allServers == 0 then
        statusText = "Kaizer can't find any available server."
        isHopping = false
        return false
    end

    -- Para fruit hunting: preferir servers con MENOS jugadores
    table.sort(allServers, function(a, b) return a.count < b.count end)
    local target = allServers[math.random(1, math.min(3, #allServers))]

    statusText = "Hopping... ("..target.count.." players)"
    task.wait(0.3)

    local ok = pcall(function()
        if _browser then
            _browser:InvokeServer("teleport", target.uuid)
        else
            TeleportService:TeleportToPlaceInstance(_place, target.uuid, lp)
        end
    end)

    if not ok then
        statusText = "Teleporting Failed, Restarting"
        isHopping   = false
        lastHopTime = os.clock() - CONFIG.HopCooldown + 3
        return false
    end

    return true
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  BUCLE PRINCIPAL
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function mainLoop()
    -- Seleccionar Piratas al inicio
    if not teamSelected then
        statusText = "Selecting Pirates..."
        for _ = 1, 12 do
            if selectPirates() then teamSelected = true; break end
            task.wait(1)
        end
        if not teamSelected then
            statusText = "âš  Couldn't join pirates"
        else
            statusText = "Pirates selected"
        end
    end

    while running do
        task.wait(0.4)
        if not gc() or not getHRP() then task.wait(1); continue end

        local fruit, dist = getNearestFruit()

        if fruit then
            local name = fruit:GetAttribute("FruitName") or fruit.Name
            statusText = "Kaizer"..name.."  ("..math.floor(dist).."m)"

            -- Verificar que la fruta sigue existiendo antes de moverse
            if not fruit.Parent or not fruit:FindFirstChild("Handle") then
                continue
            end

            -- Moverse a la fruta pasando distancia para elegir mÃ©todo
            moveTo(fruit.Handle.CFrame * CFrame.new(0, CONFIG.TPOffset, 0))
            task.wait(1.2)

            -- Verificar si se recogiÃ³
            if not fruit.Parent or not fruit:FindFirstChild("Handle") then
                statusText = "Recognizing! Guarded..."
                task.wait(0.3)
                storeFruitInBackpack()
                task.wait(0.5)
            end
        else
            statusText = "Kaizer”„ No fruits at Hop"
            task.wait(0.5)
            teamSelected = false
            local hopOk = serverHop()
            if hopOk then
                -- Hop exitoso â€” el juego nos va a teleportar, parar el loop
                running = false
                break
            else
                -- Hop fallÃ³ â€” esperar y reintentar en el siguiente ciclo
                statusText = "Hop fail, restarting in 5s..."
                task.wait(5)
                -- No rompemos el loop, volvemos a buscar frutas o intentar hop
            end
        end
    end
end

local function startHopper()
    running = true
    while running do
        local ok, err = pcall(mainLoop)
        if not ok then
            statusText = "âŒ "..tostring(err):sub(1,30)
            task.wait(3)
        end
        if not running then break end
        task.wait(2)
    end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  ESP FRUTAS â€” bonito, con distancia y nombre
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local ESPEnabled = true

task.spawn(function()
    while task.wait(0.6) do
        local h = getHRP()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj:FindFirstChild("Handle") then
                local isFruit = obj:GetAttribute("FruitName") or obj:GetAttribute("ItemName")
                             or obj.Name:lower():find("fruit")
                if isFruit then
                    local handle = obj.Handle
                    local g = handle:FindFirstChild("FH_ESP")
                    if ESPEnabled then
                        if not g then
                            g = Instance.new("BillboardGui", handle)
                            g.Name = "FH_ESP"
                            g.AlwaysOnTop = true
                            g.Size = UDim2.new(0,160,0,46)
                            g.StudsOffset = Vector3.new(0,3.5,0)
                            local bg = Instance.new("Frame", g)
                            bg.Name = "BG"; bg.Size = UDim2.new(1,0,1,0)
                            bg.BackgroundColor3 = Color3.fromRGB(5,5,10)
                            bg.BackgroundTransparency = 0.4; bg.BorderSizePixel = 0
                            Instance.new("UICorner",bg).CornerRadius = UDim.new(0,5)
                            local stroke = Instance.new("UIStroke",bg)
                            stroke.Color = Color3.fromRGB(0,220,100); stroke.Thickness = 1.5
                            local n = Instance.new("TextLabel", bg)
                            n.Name = "N"; n.Size = UDim2.new(1,0,0.55,0)
                            n.BackgroundTransparency = 1
                            n.Font = Enum.Font.GothamBold; n.TextSize = 12
                            n.TextColor3 = Color3.fromRGB(0,230,110)
                            n.TextStrokeTransparency = 0.3
                            local d2 = Instance.new("TextLabel", bg)
                            d2.Name = "D"; d2.Size = UDim2.new(1,0,0.45,0)
                            d2.Position = UDim2.new(0,0,0.55,0)
                            d2.BackgroundTransparency = 1
                            d2.Font = Enum.Font.Gotham; d2.TextSize = 11
                            d2.TextColor3 = Color3.fromRGB(190,190,190)
                            d2.TextStrokeTransparency = 0.4
                        end
                        -- Actualizar texto
                        local bg2 = g:FindFirstChild("BG")
                        if bg2 then
                            local nLbl = bg2:FindFirstChild("N")
                            local dLbl = bg2:FindFirstChild("D")
                            local fruitName = obj:GetAttribute("FruitName") or obj.Name
                            if nLbl then nLbl.Text = "ðŸŽ "..fruitName end
                            if dLbl and h then
                                local dist2 = math.floor((handle.Position-h.Position).Magnitude)
                                dLbl.Text = dist2.."m"
                            end
                        end
                    elseif g then g:Destroy() end
                end
            end
        end
    end
end)

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  UI â€” compacta, limpia, Delta-safe
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local pg = lp:WaitForChild("PlayerGui")
pcall(function()
    local o = pg:FindFirstChild("FruitHopperUI"); if o then o:Destroy() end
end)

local SG = Instance.new("ScreenGui", pg)
SG.Name = "FruitHopperUI"; SG.ResetOnSpawn = false; SG.DisplayOrder = 999

local W, H = 210, 165

local Panel = Instance.new("Frame", SG)
Panel.Size = UDim2.new(0,W,0,H); Panel.Position = UDim2.new(0.02,0,0.3,0)
Panel.BackgroundColor3 = Color3.fromRGB(14,14,20)
Panel.BorderSizePixel = 0
Instance.new("UICorner",Panel).CornerRadius = UDim.new(0,9)
local ps = Instance.new("UIStroke",Panel)
ps.Color = Color3.fromRGB(0,210,90); ps.Thickness = 1.5

-- Header
local Hdr = Instance.new("Frame", Panel)
Hdr.Size = UDim2.new(1,0,0,34); Hdr.BackgroundColor3 = Color3.fromRGB(10,10,16)
Hdr.BorderSizePixel = 0
Instance.new("UICorner",Hdr).CornerRadius = UDim.new(0,9)
local hFix = Instance.new("Frame",Hdr)
hFix.Size=UDim2.new(1,0,0,9); hFix.Position=UDim2.new(0,0,1,-9)
hFix.BackgroundColor3=Color3.fromRGB(10,10,16); hFix.BorderSizePixel=0

local HTit = Instance.new("TextLabel",Hdr)
HTit.Text="Kaizer Fruit Hopper"; HTit.Size=UDim2.new(1,-30,1,0)
HTit.Position=UDim2.new(0,10,0,0); HTit.BackgroundTransparency=1
HTit.TextColor3=Color3.fromRGB(0,220,90); HTit.Font=Enum.Font.GothamBold
HTit.TextSize=12; HTit.TextXAlignment=Enum.TextXAlignment.Left

local CloseB = Instance.new("TextButton",Hdr)
CloseB.Size=UDim2.new(0,22,0,22); CloseB.Position=UDim2.new(1,-26,0,6)
CloseB.BackgroundColor3=Color3.fromRGB(200,50,50); CloseB.TextColor3=Color3.new(1,1,1)
CloseB.Font=Enum.Font.GothamBold; CloseB.TextSize=12; CloseB.BorderSizePixel=0; CloseB.Text="Pft"
Instance.new("UICorner",CloseB).CornerRadius=UDim.new(0,5)

-- Toggle btn â€” empieza en verde porque el script arranca solo
local TogBtn = Instance.new("TextButton", Panel)
TogBtn.Size=UDim2.new(0.88,0,0,32); TogBtn.Position=UDim2.new(0.06,0,0,42)
TogBtn.BackgroundColor3=Color3.fromRGB(0,140,0)
TogBtn.TextColor3=Color3.new(1,1,1); TogBtn.Font=Enum.Font.GothamBold
TogBtn.TextSize=12; TogBtn.BorderSizePixel=0; TogBtn.Text="Finding"
Instance.new("UICorner",TogBtn).CornerRadius=UDim.new(0,6)

-- Status label
local StatLbl = Instance.new("TextLabel", Panel)
StatLbl.Size=UDim2.new(0.88,0,0,16); StatLbl.Position=UDim2.new(0.06,0,0,80)
StatLbl.BackgroundTransparency=1; StatLbl.Text="Esperando..."
StatLbl.TextColor3=Color3.fromRGB(170,170,170); StatLbl.Font=Enum.Font.Gotham
StatLbl.TextSize=10; StatLbl.TextXAlignment=Enum.TextXAlignment.Left

-- ESP toggle
local ESPBtn = Instance.new("TextButton", Panel)
ESPBtn.Size=UDim2.new(0.88,0,0,26); ESPBtn.Position=UDim2.new(0.06,0,0,100)
ESPBtn.BackgroundColor3=Color3.fromRGB(0,130,60)
ESPBtn.TextColor3=Color3.new(1,1,1); ESPBtn.Font=Enum.Font.GothamBold
ESPBtn.TextSize=11; ESPBtn.BorderSizePixel=0; ESPBtn.Text="ESP: ON"
Instance.new("UICorner",ESPBtn).CornerRadius=UDim.new(0,5)

-- Auto-equip toggle
local EqBtn = Instance.new("TextButton", Panel)
EqBtn.Size=UDim2.new(0.88,0,0,26); EqBtn.Position=UDim2.new(0.06,0,0,130)
EqBtn.BackgroundColor3=Color3.fromRGB(0,100,160)
EqBtn.TextColor3=Color3.new(1,1,1); EqBtn.Font=Enum.Font.GothamBold
EqBtn.TextSize=11; EqBtn.BorderSizePixel=0; EqBtn.Text="Auto-Store: ON"
Instance.new("UICorner",EqBtn).CornerRadius=UDim.new(0,5)

-- Status update loop
task.spawn(function()
    while task.wait(0.3) do
        StatLbl.Text = statusText
    end
end)

-- Controles
local function stopHopper()
    running = false
    if hopperThread then task.cancel(hopperThread); hopperThread = nil end
    statusText = "Stopped"
    TogBtn.BackgroundColor3 = Color3.fromRGB(160,0,0)
    TogBtn.Text = "Kaizer”´  Start"
end

local function startHopperThread()
    stopHopper(); task.wait(0.05)
    running = true
    statusText = "Removing..."
    TogBtn.BackgroundColor3 = Color3.fromRGB(0,140,0)
    TogBtn.Text = "Hold"
    hopperThread = task.spawn(startHopper)
end

TogBtn.MouseButton1Click:Connect(function()
    if running then stopHopper() else startHopperThread() end
end)

ESPBtn.MouseButton1Click:Connect(function()
    ESPEnabled = not ESPEnabled
    ESPBtn.Text = ESPEnabled and "ESP: ON" or "ESP: OFF"
    ESPBtn.BackgroundColor3 = ESPEnabled and Color3.fromRGB(0,130,60) or Color3.fromRGB(60,60,80)
end)

EqBtn.MouseButton1Click:Connect(function()
    CONFIG.EquipFruit = not CONFIG.EquipFruit
    EqBtn.Text = CONFIG.EquipFruit and "Auto-Store: ON" or "Auto-Store: OFF"
    EqBtn.BackgroundColor3 = CONFIG.EquipFruit and Color3.fromRGB(0,100,160) or Color3.fromRGB(60,60,80)
end)

CloseB.MouseButton1Click:Connect(function()
    stopHopper(); SG:Destroy()
end)

-- Drag
do
    local drag, ds, sp
    Hdr.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=true; ds=i.Position; sp=Panel.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-ds
            Panel.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end
    end)
end

print("[Kaizer Fruit Hopper]”")

-- Activar detecciÃ³n de frutas en mochila
setupFruitDetection()

-- Auto-arrancar al ejecutar
startHopperThread()
