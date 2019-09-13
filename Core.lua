
local ItemTypeCheckButtons = {
    {name = 'Miscellaneous', button = nil, state = 1},
    {name = 'Armor', button = nil, state = 1},
    {name = 'Consumable', button = nil, state = 1},
    -- {name = 'Container', button = nil, state = 1},
    -- {name = 'Gem', button = nil, state = 1},
    -- {name = 'Key', button = nil, state = 1},
    -- {name = 'Money', button = nil, state = 1},
    {name = 'Reagent', button = nil, state = 1},
    -- {name = 'Recipe', button = nil, state = 1},
    {name = 'Projectile', button = nil, state = 1},
    {name = 'Quest', button = nil, state = 1},
    -- {name = 'Quiver', button = nil, state = 1},
    {name = 'Trade Goods', button = nil, state = 1},
    {name = 'Weapon', button = nil, state = 1},
}


TeamInventory = LibStub("AceAddon-3.0"):NewAddon("TeamInventory", 
    "AceConsole-3.0", 
    "AceEvent-3.0", 
    "AceComm-3.0")

-- Set to false to reduce Debug output
local verbose = true

-- local debug function
if verbose then
    Debug = function ( ... )
        TeamInventory:Print( ... )
    end
    seterrorhandler(
        function (msg)
        msg = msg .. "\n" .. debugstack()
        Debug(msg)
        end)
else
    Debug = function () end
end


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Ace Init functions
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
function TeamInventory:OnInitialize ()
    Debug("Init")
    
    -- The Team Inventory frame
    self.frame = getglobal('TeamInventory_Frame')
    
    -- The players own name
    self.player_name = UnitName('player')
    
    -- Comm index, used to sync item cache
    self.comm_index = 1
    
    -- The mumber of item buttons currently displayed
    self.item_button_count = 0

    -- Time of last redraw in ms
    self.last_redraw = 0

    -- Time of last comm message in ms
    self.last_comm_message = 0
    
    -- Mutex
    self.block = false

    -- Local item cache format:
    -- {
    --  charname = {
    --      last_comm_index = <comm index of last sync>,
    --      items = {
    --          item_id = {
    --              comm_index = comm_index,
    --              count = count,
    --              type = "bag" or "bank"
    --          }
    --      }
    --  }
    self.item_cache = {}
    
    -- Add local char's data to the cache
    self.item_cache[self.player_name] = {
        last_comm_index = 0,
        items = {}
    }

    local options = {
        name = 'TeamInventory',
        handler = TeamInventory,
        type = 'group',
        args = {
            show = {
                type = 'execute',
                name = 'Show',
                desc = 'Show the Team Inventory window,',
                func = 'Show'
            },
            hide = {
                type = 'execute',
                name = 'Hide',
                desc = 'Hide the Team Inventory window.',
                func = 'Hide',
            },
            toggle = {
                type = 'execute',
                name = 'Toggle',
                desc = 'Toggle the Team Inventory window.',
                func = 'Toggle',
            },
            update = {
                type = 'execute',
                name = 'Update',
                desc = 'Update item frame (debug function).',
                func = 'UpdateItemFrame',
            },
        },
    }
    
    LibStub('AceConfig-3.0'):RegisterOptionsTable('TeamInventory', options, 
        {'ti', 'teaminventory'})
    
    -- Create ItemType buttons
    local parent, last = getglobal("TeamInventory_TypeFrame"), nil
    for index, button in pairs(ItemTypeCheckButtons) do
        local b, label = CreateFrame('CheckButton', 'TeamInventory_ItemType' .. index,
            parent, 'TeamInventory_CheckButtonTemplate'),
            getglobal('TeamInventory_ItemType' .. index .. 'Text')
        
        button['buton'] = b
        label:SetText(button['name'])
        if last then
            b:SetPoint('TOPLEFT', last, 0, -22)
        else
            b:SetPoint('TOPLEFT', parent, 5, -19)
        end
        b:Show()
    
        b:SetScript('OnClick',
            function ()
                button['state'] = b:GetChecked()
                TeamInventory:UpdateItemFrame()
            end)

        last = b
    end
end

function TeamInventory:OnEnable ()
    self:RegisterComm('TiCommand', 'OnTiCommand') 
    self:RegisterComm('TiData', 'OnTiData') 
end

function TeamInventory:OnDisable ()
    self:UnregisterComm('TiCommand')
    self:UnregisterComm('TiData')
end


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Options Callbacks
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
function TeamInventory:Show ()
    self.frame:Show()
end

function TeamInventory:Hide ()
    self.frame:Hide()
end

function TeamInventory:Toggle ()
    if self.frame:IsShown() then self.frame:Hide()
    else self.frame:Show() end
end


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Frame event handlers
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
function TeamInventory:OnUpdate (s, elapsed)
    s.TimeSinceLastUpdate = s.TimeSinceLastUpdate + elapsed;

    if (s.TimeSinceLastUpdate > 0.5) then
        s.TimeSinceLastUpdate = 0
    end
    
    if ((TeamInventory:GetTimeMS() - self.last_comm_message) > 500) 
            and (self.last_comm_message > self.last_redraw) then
        TeamInventory:UpdateItemFrame()
    end
end

function TeamInventory:OnShow ()
    -- Scan local bags, then update the item frame
    self.item_cache[self.player_name]['items'] = TeamInventory:ScanBags()
    TeamInventory:UpdateItemFrame()

    -- Send a request to the party for items
    self:SendCommMessage('TiCommand', self.comm_index .. ' RequestBags', 'PARTY')
    self.comm_index = self.comm_index + 1
end


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- TeamInventory Internals
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
function TeamInventory:ScanBags ()
    local t = {}
    for bag = 0,4 do
        for slot = 1,GetContainerNumSlots(bag) do
            local _, count = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)

            if link then
                local _, item_id = strsplit(':', link)
                
                if t[item_id] then
                    t[item_id]['count'] = t[item_id]['count'] + count
                else
                    t[item_id] = {
                        comm_index = 0,
                        count = count,
                        type = 'bag',
                    }
                end
            end
        end
    end

    return t
end

function TeamInventory:TradeItemWithId(target, item_id)
    for i = 0, 4 do
        for x = 1, GetContainerNumSlots(i) do
            local item = GetContainerItemID(i, x)
            if item then
                if item_id == tostring(item) then
                    print("Found item " .. tostring(item) .. " " .. tostring(item_id) .. " " .. target)
                    PickupContainerItem(i, x)
                    DropItemOnUnit(target)
                    return
                end
            end
        end
    end
end

function TeamInventory:UpdateItemFrame ()
    if self.block then 
        Debug('Reenter, return')
        return 
    end

    self.block = true
    
    local old_count, iframe = self.item_button_count,
        getglobal('TeamInventory_ItemsFrame')
    
    self.item_button_count = 0
    
    local type_filter = {}
    for index, info in pairs(ItemTypeCheckButtons) do
        if info['state'] then
            if index == 0 then
                type_filter = {
                    Miscellaneous = 1,
                    Container = 1,
                    Gem = 1,
                    Key = 1,
                    Money = 1,
                    Recipe = 1,
                    Quiver = 1,
                }            
            else
                type_filter[info['name']] = 1
            end
        end
    end

    for charName, data in pairs(self.item_cache) do
        local last_comm_index = data['last_comm_index']
        local i = 0
        
        for item_id, info in pairs(data['items']) do
            i = i + 1
            if info['comm_index'] < last_comm_index then
            else
                local _, _, _, _, _, itype = GetItemInfo(item_id)
                
                if type_filter[itype] then
                    local button = TeamInventory:CreateItemButton (self.item_button_count,
                        item_id, info['count'], charName, info['type'])

                    button:SetParent(iframe)
                    button:SetPoint('TOPLEFT', iframe, 'TOPLEFT',
                        (self.item_button_count % 12) * 38,
                        floor(self.item_button_count / 12) * -38)

                    local this = self
                    button:SetScript("OnClick", function(self, arg1)
                        local msg = this.comm_index .. ' RequestTrade:' .. tostring(item_id) .. ":" .. charName
                        print("Sending " .. msg)
                        this:SendCommMessage('TiCommand', msg, 'PARTY')
                        this.comm_index = this.comm_index + 1
                    end)
                    
                    self.item_button_count = self.item_button_count + 1
                end
            end
        end
    end
   
    while old_count > (self.item_button_count - 1) do
        Debug('Hide: ' .. old_count)
        local b = getglobal("TeamInventory_ItemButton" .. old_count)
        if b then 
            --b:Hide() 
            SetItemButtonTexture(b, nil)
            SetItemButtonCount(b, 0)
            b:SetScript('OnEnter', nil)
            b:SetScript('OnLeave', nil)
        end
        old_count = old_count - 1
    end

    self.last_redraw = TeamInventory:GetTimeMS()
    self.block = false
end


function TeamInventory:CreateItemButton (index, item_id, count, owner, _type)
    local button = getglobal('TeamInventory_ItemButton' .. index)
    
    if button then
        button:SetScript('OnEnter', nil)
        button:SetScript('OnLeave', nil)
    else
        button = CreateFrame("Button", "TeamInventory_ItemButton" .. index,
            nil, "ItemButtonTemplate")
    end

    local icon = GetItemIcon(item_id)

    SetItemButtonTexture(button, icon)
    SetItemButtonCount(button, count)

    button:SetScript('OnEnter', 
        function ()
            local link = 'item:' .. item_id .. ':0:0:0:0:0:0:0:0'
            GameTooltip:SetOwner(button)
            GameTooltip:SetHyperlink(link)
            GameTooltip:AddLine(owner .. ' ' .. _type)
            GameTooltip:Show()
        end)
    button:SetScript('OnLeave',
        function ()
            GameTooltip:Hide()
        end)

    return button
end


function StringStartsWith(str, start)
    return str:sub(1, #start) == start
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Comms
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
function TeamInventory:OnTiCommand (prefix, msg, dist, sender)
    if not (sender == self.player_name) then
        local comm_index, command = strsplit(' ', msg)
        if command == 'RequestBags' then
            local c = TeamInventory:ScanBags()
            for item_id, info in pairs(c) do
                self:SendCommMessage('TiData', 
                    comm_index .. ':' .. item_id .. ':' .. info['count'] 
                    .. ':' .. info['type'],
                    'WHISPER', sender, 'BULK')
            end
        elseif StringStartsWith(command, "RequestTrade:") then
            local req, item_id, char_name = strsplit(':', command)
            if char_name == self.player_name then
                print("Requested trade " .. command .. " " .. item_id .. " " .. sender)
                self:TradeItemWithId(sender, item_id)
            end
        end
    end
end


function TeamInventory:OnTiData (prefix, msg, dist, sender)
    local comm_index, item_id, count, _type = strsplit(':', msg)

    if self.item_cache[sender] then
        if comm_index > self.item_cache[sender]['last_comm_index'] then
            Debug('Update last_comm_index to ' .. comm_index)
            self.item_cache[sender]['last_comm_index'] = comm_index
        end
    else
        self.item_cache[sender] = {
            last_comm_index = comm_index,
            items = {},
        }
    end

    self.item_cache[sender]['items'][item_id] = {
        comm_index = comm_index,
        count = tonumber(count),
        type = _type,
    }
    
    self.last_comm_message = TeamInventory:GetTimeMS()
end


function TeamInventory:GetTimeMS ()
    local s, ms = strsplit('.', GetTime())
    if not ms then ms = 0 end
    return (s * 1000) + ms
end



