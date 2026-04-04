-- Crafting Buddy - Your Buddy for crafting with ease
-- Fully automated crafting process for all crafting devices (excludes the Packaging Machine and the Automated Oven)
-- Supports batch crafting over different crafting stations
-- Uses Silos for Ingotstorage
-- Can be easily used with the Smelting Buddy together - All your crafting needs in just 2 Consoles!

-- ==================== SURFACES & VIEW ====================

local surfaces = {
    overview = ss.ui.surface("overview"),
    settings = ss.ui.surface("settings"),
    batch = ss.ui.surface("batch"),
}
local s = surfaces.overview
local view = "overview"

local W, H = 480, 272
local size = ss.ui.surface("overview"):size()
if size then
    W = size.w or W
    H = size.h or H
end

local elapsed = 0
local currenttime = 0
local LIVE_REFRESH_TICKS = 2
local MIN_LIVE_REFRESH_TICKS = 2
local global_power_on = true
local power_target_all = true

local handles = {
    view = nil,
    header = {},
    nav = {},
    footer = {},
    overview = {},
    settings = {},
    batch = {},
}

-- ==================== CONSTANTS ====================

local LT = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod
local hash = ic.hash
local batch_write = ic.batch_write
local batch_read_name = ic.batch_read_name
local batch_write_name = ic.batch_write_name
local LST = ic.enums.LogicSlotType
local batch_read_slot_name = ic.batch_read_slot_name
local ic = _G.ic
local util = _G.util
local ss = _G.ss

local dashboard_render
local set_view
local roles

local SILO_PREFABS = { hash("StructureSDBSilo") }
local LOGIC_SORTER_PREFABS = { hash("StructureLogicSorter"), hash("StructureLogicSorterMirrored") }
local CRAFTING_DEVICES = { hash("StructureAutolathe"), hash("StructureElectronicsPrinter"), hash("StructureHydraulicPipeBender"), hash("StructureRocketManufactory"), hash("StructureSecurityPrinter"), hash("StructureToolManufactory") }   
local STACKER_PREFABS = { hash("StructureStackerReverse"), hash("StructureStacker") }
local SORTER_STACKER = { hash("StructureSorter"), hash("StructureSorterMirrored"), hash("StructureStackerReverse"), hash("StructureStacker") }
local ORE_STACK_SIZE = 50
local CRAFTS_PER_BATCH = 5

local P = {
    x = 10, y = 14,
    w = 460, h = 400
}

local C = {
    bg = "#0A0E1A",
    header = "#0C1220",
    panel = "#0F1628",
    panel_light = "#151D30",
    text = "#E2E8F0",
    text_dim = "#64748B",
    text_muted = "#475569",
    accent = "#38BDF8",
    green = "#22C55E",
    yellow = "#EAB308",
    orange = "#F97316",
    red = "#EF4444",
    light_blue = "#38BDF8",
    blue = "#1D4ED8",
    dark_red = "#7F1D1D",
    bar_bg = "#1F2937",
    title = "#0a71d8ff",
}

-- ==================== MEMORY MAP ====================

local MEM_DEVICE_BEGIN = 0
local MEM_CONTROL_BEGIN = 150

local MEM_LIVE_REFRESH = MEM_CONTROL_BEGIN + 5
local MEM_CRAFTING_ACTIVE = MEM_CONTROL_BEGIN + 20
local MEM_CRAFTING_TARGET = MEM_CONTROL_BEGIN + 21
local MEM_CRAFTING_WAIT = MEM_CONTROL_BEGIN + 22
local MEM_CRAFTING_TARGET_REAG = MEM_CONTROL_BEGIN + 23
local MEM_POWER_TOGGLE = MEM_CONTROL_BEGIN + 24
local MEM_CRAFTING_CURRENT = MEM_CONTROL_BEGIN + 25
local MEM_STATION_INDEX = MEM_CONTROL_BEGIN + 26
local MEM_BATCH_RUNNING = MEM_CONTROL_BEGIN + 27
local MEM_UNLOAD_ACTIVE = MEM_CONTROL_BEGIN + 28
local MEM_UNLOAD_TICKS = MEM_CONTROL_BEGIN + 29
local MEM_ORIGINAL_TARGET = MEM_CONTROL_BEGIN + 30
local MEM_UNLOAD_STATION = MEM_CONTROL_BEGIN + 31
local MEM_REQUESTED_AMOUNT = MEM_CONTROL_BEGIN + 32
local MEM_RECIPE_HASH = MEM_CONTROL_BEGIN + 33
local MEM_RECIPE_INDEX_BASE = MEM_CONTROL_BEGIN + 40
local MEM_POWER_TARGET = 198
local MEM_QUEUE_COUNT = 199
local MEM_QUEUE_BEGIN = 200

-- =============== Logs & util functions ===============
local DEBUG_LOG_ENABLED = true
local DEBUG_LOG_UI = false
local debug_seq = 0
local gt, gtH, gtM, gtS = 0, 0, 0, 0

local function time()
    gt = util.game_time() or 0
    gtH = math.floor(gt / 3600)
    gtM = math.floor((gt % 3600) / 60)
    gtS = math.floor((gt % 3600) % 60)
    return gtH, gtM, gtS
end

local function log_action(message)
    if not DEBUG_LOG_ENABLED then return end
    time()
    debug_seq = debug_seq + 1
    print("[CraftingBuddy] #" .. tostring(debug_seq) .. " H" .. gtH .. " : M" .. gtM .. " : S" .. gtS .. " | " .. tostring(message))
end

local function log_step(message)
    log_action("[STEP] " .. tostring(message))
end

local function log_ui(message)
    if not DEBUG_LOG_UI then return end
    log_action("[UI] " .. tostring(message))
end

local function safe_call(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        log_action("[ERROR] " .. tostring(label) .. " | " .. tostring(err))
    end
    return ok
end

-- ==================== HELPERS ====================

local function write(address, value)
    mem_write(address, value)
end

local function read(address)
    return mem_read(address) or 0
end

local function fmt(v, d)
    if v == nil then return "--" end
    return string.format("%." .. tostring(d or 1) .. "f", v)
end

local function stock_amount_color(v)
    if v == nil then return C.text_dim end
    if v < 200 then return C.red end
    if v < 500 then return C.orange end
    if v < 1000 then return C.yellow end
    return C.green
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function to_number_or(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function safe_batch_read_name(prefab, namehash, logic_type, method)
    if batch_read_name == nil then return nil end
    local p = tonumber(prefab) or 0
    local n = tonumber(namehash) or 0
    if p == 0 or n == 0 then return nil end
    local ok, value = pcall(batch_read_name, p, n, logic_type, method)
    if not ok then return nil end
    return value
end

local function safe_batch_write_name(prefab, namehash, logic_type, value)
    if batch_write_name == nil then return false end
    local p = tonumber(prefab) or 0
    local n = tonumber(namehash) or 0
    if p == 0 or n == 0 then return false end
    local ok = pcall(batch_write_name, p, n, logic_type, value)
    return ok
end

local function resolve_name_hash(namehash)
    local n = tonumber(namehash) or 0
    if n == 0 then return "Unassigned" end
    local ok, resolved = pcall(namehash_name, n)
    if not ok or resolved == nil then
        return "#" .. tostring(n)
    end
    return tostring(resolved)
end

local function bool01(v)
    return (tonumber(v) or 0) > 0 and 1 or 0
end

local function logic_or_zero(role, logic_type)
    return safe_batch_read_name(role.prefab, role.namehash, logic_type, LBM.Average) or 0
end

local function role_is_bound(role)
    if role == nil then return false end
    return (tonumber(role.prefab) or 0) ~= 0 and (tonumber(role.namehash) or 0) ~= 0
end

local function roles_are_bound(keys)
    for _, key in ipairs(keys) do
        if not role_is_bound(roles[key]) then
            return false
        end
    end
    return true
end

local function device_list_safe()
    local ok, devices = pcall(device_list)
    if not ok or type(devices) ~= "table" then return {} end
    return devices
end

local function device_matches_prefabs(dev, allowed_prefabs)
    if allowed_prefabs == nil then
        return true
    end

    local prefab_hash = tonumber(dev and dev.prefab_hash) or 0
    for _, allowed in ipairs(allowed_prefabs) do
        if prefab_hash == allowed then
            return true
        end
    end

    return false
end

-- ==================== DEVICE ROLE MODEL ====================

local role_defs = {
    { key = "silo_iron",      label = "Iron Silo",      default_name = "Iron Silo",      slot = 24, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Iron" },
    { key = "silo_copper",    label = "Copper Silo",    default_name = "Copper Silo",    slot = 25, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Copper" },
    { key = "silo_gold",      label = "Gold Silo",      default_name = "Gold Silo",      slot = 26, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Gold" },
    { key = "silo_silicon",   label = "Silicon Silo",   default_name = "Silicon Silo",   slot = 27, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Silicon" },
    { key = "silo_silver",    label = "Silver Silo",    default_name = "Silver Silo",    slot = 28, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Silver" },
    { key = "silo_lead",      label = "Lead Silo",      default_name = "Lead Silo",      slot = 29, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Lead" },
    { key = "silo_nickel",    label = "Nickel Silo",    default_name = "Nickel Silo",    slot = 30, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Nickel" },
    { key = "silo_steel",     label = "Steel Silo",     default_name = "Steel Silo",     slot = 33, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Steel" },
    -- Spec Ingot Silos
    { key = "silo_electrum",   label = "Electrum Silo",   default_name = "Electrum Silo",   slot = 40, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Electrum" },
    { key = "silo_solder",     label = "Solder Silo",     default_name = "Solder Silo",     slot = 41, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Solder" },
    { key = "silo_constantan", label = "Constantan Silo", default_name = "Constantan Silo", slot = 42, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Constantan" },
    { key = "silo_invar",      label = "Invar Silo",      default_name = "Invar Silo",      slot = 43, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Invar" },
    -- Alloy Ingot Silos
    { key = "silo_astroloy",   label = "Astroloy Silo",   default_name = "Astroloy Silo",   slot = 44, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Astroloy" },
    { key = "silo_hastelloy",  label = "Hastelloy Silo",  default_name = "Hastelloy Silo",  slot = 45, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Hastelloy" },
    { key = "silo_stellite",   label = "Stellite Silo",   default_name = "Stellite Silo",   slot = 46, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Stellite" },
    { key = "silo_inconel",    label = "Inconel Silo",    default_name = "Inconel Silo",    slot = 47, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Inconel" },
    { key = "silo_waspaloy",   label = "Waspaloy Silo",   default_name = "Waspaloy Silo",   slot = 48, allowed_prefabs = SILO_PREFABS, is_batch = true, name_filter = "Waspaloy" },
    -- Crafting Station Sorters
    { key = "sorter_autolathe",   label = "Sorter - Autolathe",   default_name = "Sorter - Autolathe",   slot = 37, allowed_prefabs = LOGIC_SORTER_PREFABS },
    { key = "sorter_electronics", label = "Sorter - Electronics", default_name = "Sorter - Electronics", slot = 38, allowed_prefabs = LOGIC_SORTER_PREFABS },
    { key = "sorter_pipebender",  label = "Sorter - PipeBender",  default_name = "Sorter - PipeBender",  slot = 39, allowed_prefabs = LOGIC_SORTER_PREFABS },
    { key = "sorter_rocket",      label = "Sorter - Rocket",      default_name = "Sorter - Rocket",      slot = 58, allowed_prefabs = LOGIC_SORTER_PREFABS },
    { key = "sorter_security",    label = "Sorter - Security",    default_name = "Sorter - Security",    slot = 59, allowed_prefabs = LOGIC_SORTER_PREFABS },
    { key = "sorter_tools",       label = "Sorter - Tools",       default_name = "Sorter - Tools",       slot = 60, allowed_prefabs = LOGIC_SORTER_PREFABS },
    -- Crafting Stations
    { key = "station_autolathe",   label = "Station - Autolathe",   default_name = "Autolathe",   slot = 49, allowed_prefabs = CRAFTING_DEVICES },
    { key = "station_electronics", label = "Station - Electronics", default_name = "Electronics Printer", slot = 50, allowed_prefabs = CRAFTING_DEVICES },
    { key = "station_pipebender",  label = "Station - PipeBender",  default_name = "Hydraulic Pipe Bender", slot = 51, allowed_prefabs = CRAFTING_DEVICES },
    { key = "station_rocket",      label = "Station - Rocket",      default_name = "Rocket Manufactory",  slot = 55, allowed_prefabs = CRAFTING_DEVICES },
    { key = "station_security",    label = "Station - Security",    default_name = "Security Printer",    slot = 56, allowed_prefabs = CRAFTING_DEVICES },
    { key = "station_tools",       label = "Station - Tools",       default_name = "Tool Manufactory",    slot = 57, allowed_prefabs = CRAFTING_DEVICES },
    -- Stackers
    { key = "stacker_main",   label = "Main Stacker",   default_name = "Stacker",   slot = 52, allowed_prefabs = STACKER_PREFABS, name_filter = "Main" },
}

roles = {}
local settings_dropdown_selected = {}
local settings_dropdown_open = {}

for i, def in ipairs(role_defs) do
    roles[def.key] = {
        index = i,
        key = def.key,
        label = def.label,
        default_name = def.default_name,
        slot = def.slot,
        allowed_prefabs = def.allowed_prefabs,
        name_filter = def.name_filter,
        is_batch = def.is_batch or false
    }
    settings_dropdown_selected[def.key] = 0
    settings_dropdown_open[def.key] = "false"
end

local function load_roles_from_memory()
    log_step("load_roles_from_memory: begin")
    local summary = {}
    for _, def in ipairs(role_defs) do
        local role = roles[def.key]
        local slot = tonumber(role.slot) or role.index
        local base = MEM_DEVICE_BEGIN + (slot - 1) * 2
        role.prefab = tonumber(read(base)) or 0
        role.namehash = tonumber(read(base + 1)) or 0
        if role_is_bound(role) then
            log_step(string.format("role loaded: %s prefab=%s namehash=%s", role.key, tostring(role.prefab), tostring(role.namehash)))
        else
            log_step("role loaded unassigned: " .. tostring(role.key))
        end
        table.insert(summary, string.format("%s:[%s,%s]", role.key, tostring(role.prefab), tostring(role.namehash)))
    end
    print("[CraftingBuddy] Role summary: " .. table.concat(summary, "; "))
end

local function save_role_to_memory(role)
    local slot = tonumber(role.slot) or role.index
    local base = MEM_DEVICE_BEGIN + (slot - 1) * 2
    write(base, tonumber(role.prefab) or 0)
    write(base + 1, tonumber(role.namehash) or 0)
    log_step(string.format("save_role_to_memory: %s prefab=%s namehash=%s", tostring(role.key), tostring(role.prefab), tostring(role.namehash)))
end

-- ==================== CONTROL STATE ====================

local settings_subtab = "silo"
local settings_device_page = 1
local cached_role_dropdowns = {}

local ui_live_refresh = tostring(LIVE_REFRESH_TICKS)

local requested_amount = 1
local stock_ok = false
local status_text = "Idle"
local status_color = C.text_dim
local last_status_text = ""

local crafting_run_active = false
local crafting_target_amount = 0
local crafting_original_target = 0
local crafting_current_amount = 0
local crafting_wait_reagents = false
local crafting_target_reagents = 0
local crafting_recipe_hash = 0
local silo_recovery_checked = false
local boot_phase_ticks = 0

local unload_active = false
local unload_ticks = 0
local unload_station_index = 0
local crafting_queue = {}
local is_batch_running = false
local batch_queue_page = 1
local requested_amount = 1
local recipe_search_query = ""
local show_search_results = false

local crafting_stations = { "Autolathe", "Electronics", "Pipe Bender", "Rocket", "Security", "Tools" }
local selected_station_index = 1
local selected_recipe_per_station = { 1, 1, 1, 1, 1, 1 }

local function save_crafting_state()
    write(MEM_CRAFTING_ACTIVE, crafting_run_active and 1 or 0)
    write(MEM_CRAFTING_TARGET, crafting_target_amount)
    write(MEM_CRAFTING_WAIT, crafting_wait_reagents and 1 or 0)
    write(MEM_CRAFTING_TARGET_REAG, crafting_target_reagents)
    write(MEM_POWER_TOGGLE, global_power_on and 2 or 1)
    write(MEM_CRAFTING_CURRENT, crafting_current_amount)
    write(MEM_STATION_INDEX, selected_station_index)
    write(MEM_BATCH_RUNNING, is_batch_running and 1 or 0)
    write(MEM_UNLOAD_ACTIVE, unload_active and 1 or 0)
    write(MEM_UNLOAD_TICKS, unload_ticks)
    write(MEM_UNLOAD_STATION, unload_station_index)
    write(MEM_ORIGINAL_TARGET, crafting_original_target)
    write(MEM_REQUESTED_AMOUNT, requested_amount)
    write(MEM_RECIPE_HASH, crafting_recipe_hash)
    
    local q_len = #crafting_queue
    write(MEM_QUEUE_COUNT, q_len)
    if DEBUG_LOG_ENABLED then log_action("Persisting queue. Length=" .. q_len) end
    for i = 1, q_len do
        local q = crafting_queue[i]
        local base = MEM_QUEUE_BEGIN + (i - 1) * 3
        write(base, q.recipe_index or 1)
        write(base + 1, q.station or 1)
        write(base + 2, q.amount or 1)
    end
    
    for i = 1, #selected_recipe_per_station do
        write(MEM_RECIPE_INDEX_BASE + i - 1, selected_recipe_per_station[i])
    end
    write(MEM_LIVE_REFRESH, LIVE_REFRESH_TICKS)
    write(MEM_POWER_TARGET, power_target_all and 1 or 0)
end

local function load_crafting_state()
    crafting_run_active = (tonumber(read(MEM_CRAFTING_ACTIVE)) or 0) > 0
    crafting_target_amount = tonumber(read(MEM_CRAFTING_TARGET)) or 0
    crafting_wait_reagents = (tonumber(read(MEM_CRAFTING_WAIT)) or 0) > 0
    crafting_target_reagents = tonumber(read(MEM_CRAFTING_TARGET_REAG)) or 0
    crafting_current_amount = tonumber(read(MEM_CRAFTING_CURRENT)) or 0
    crafting_recipe_hash = tonumber(read(MEM_RECIPE_HASH)) or 0
    
    local loaded_idx = math.max(1, tonumber(read(MEM_STATION_INDEX)) or 1)
    if crafting_run_active then
        selected_station_index = loaded_idx
    else
        selected_station_index = 1 -- Always default to Autolathe (Station 1)
    end
    
    local pval = tonumber(read(MEM_POWER_TOGGLE)) or 0
    global_power_on = (pval ~= 1)

    is_batch_running = (tonumber(read(MEM_BATCH_RUNNING)) or 0) > 0
    unload_active = (tonumber(read(MEM_UNLOAD_ACTIVE)) or 0) > 0
    unload_ticks = tonumber(read(MEM_UNLOAD_TICKS)) or 0
    unload_station_index = math.max(0, tonumber(read(MEM_UNLOAD_STATION)) or 0)
    crafting_original_target = tonumber(read(MEM_ORIGINAL_TARGET)) or 0
    local req_amt = tonumber(read(MEM_REQUESTED_AMOUNT)) or 1
    if req_amt > 0 then requested_amount = req_amt else requested_amount = 1 end
    
    local q_len = tonumber(read(MEM_QUEUE_COUNT)) or 0
    crafting_queue = {}
    if q_len > 0 and q_len <= 100 then
        for i = 1, q_len do
            local base = MEM_QUEUE_BEGIN + (i - 1) * 3
            local r_idx = tonumber(read(base)) or 1
            local st = tonumber(read(base + 1)) or 1
            local amt = tonumber(read(base + 2)) or 1
            table.insert(crafting_queue, { recipe_index = r_idx, station = st, amount = amt })
        end
    end

    for i = 1, 6 do
        local val = tonumber(read(MEM_RECIPE_INDEX_BASE + i - 1)) or 1
        if val < 1 then val = 1 end
        selected_recipe_per_station[i] = val
    end
    LIVE_REFRESH_TICKS = math.max(2, tonumber(read(MEM_LIVE_REFRESH)) or 2)
    ui_live_refresh = tostring(LIVE_REFRESH_TICKS)
    power_target_all = (tonumber(read(MEM_POWER_TARGET)) or 1) > 0
end

local MIN_BATCH_AMOUNT = 1
local MAX_BATCH_AMOUNT = 50
local batch_queue_page = 1

local silo_request = {
    active = false,
    items = {},
    item_index = 1,
    phase = 0,
}

local SILO_ROLES = {
    Iron       = "silo_iron",
    Copper     = "silo_copper",
    Gold       = "silo_gold",
    Silicon    = "silo_silicon",
    Silver     = "silo_silver",
    Lead       = "silo_lead",
    Nickel     = "silo_nickel",
    Coal       = "silo_coal",
    Cobalt     = "silo_cobalt",
    Steel      = "silo_steel",
    Electrum   = "silo_electrum",
    Solder     = "silo_solder",
    Constantan = "silo_constantan",
    Invar      = "silo_invar",
    Astroloy   = "silo_astroloy",
    Hastelloy  = "silo_hastelloy",
    Stellite   = "silo_stellite",
    Inconel    = "silo_inconel",
    Waspaloy   = "silo_waspaloy",
}

local MATERIAL_ORDER = { "Iron", "Copper", "Gold", "Silicon", "Silver", "Lead", "Nickel", "Steel", "Electrum", "Solder", "Constantan", "Invar", "Astroloy", "Hastelloy", "Stellite", "Inconel", "Waspaloy" }


local SILO_HANDLE_KEY = {}
for _, mat in ipairs(MATERIAL_ORDER) do
    SILO_HANDLE_KEY[mat] = "ov_silo_" .. string.lower(mat)
end

-- ==================== CRAFTING STATION DATA ====================

local station_recipes

local CRAFTING_MATERIAL_DISPLAY_ORDER = {
    "Iron", "Copper", "Gold", "Silicon", "Silver", "Lead", "Nickel",
    "Steel", "Electrum", "Solder", "Constantan", "Invar",
    "Astroloy", "Hastelloy", "Stellite", "Inconel", "Waspaloy",
}

local recipe_hashes = {
    [1] = -1301215609,
    [2] = -404336834,
    [3] = 226410516,
    [4] = -290196476,
    [5] = -929742000,
    [6] = 2134647745,
    [7] = -1406385572,
    [8] = -654790771,
    [9] = -297990285,
    [10] = -82508479,
    [11] = 502280180,
    [12] = 1058547521,
    [13] = 156348098,
    [14] = -787796599,
    [15] = 412924554,
    [16] = 1579842814,
    [17] = -1897868623,
}

station_recipes = {
    -- ===== [1] AUTOLATHE =================
    [1] = {
        { name = "Iron Frames",       prefab = "ItemIronFrames",       req = { Iron = 4 } },
        { name = "Iron Sheets",       prefab = "ItemIronSheets",        req = { Iron = 1 } },
        { name = "Plastic Sheets",    prefab = "ItemPlasticSheets",     req = { Silicon = 0.5 } },
        { name = "Glass Sheets",      prefab = "ItemGlassSheets",       req = { Silicon = 2 } },
        { name = "Stellite Glass",    prefab = "ItemStelliteGlassSheets", req = { Silicon = 2, Stellite = 1 } },
        { name = "Steel Sheets",      prefab = "ItemSteelSheets",       req = { Steel = 0.5 } },
        { name = "Astroloy Sheets",   prefab = "ItemAstroloySheets",    req = { Astroloy = 1, Steel = 2 } },
        { name = "Steel Frames",      prefab = "ItemSteelFrames",       req = { Steel = 2 } },
        { name = "Kit Wall Iron",     prefab = "ItemKitWallIron",       req = { Iron = 1 } },
        { name = "Kit Railing",       prefab = "ItemKitRailing",        req = { Iron = 1 } },
        { name = "Kit Comp Cladding", prefab = "ItemKitCompositeCladding", req = { Iron = 1 } },
        { name = "Kit Wall (Steel)",  prefab = "ItemKitWall",           req = { Steel = 1 } },
        { name = "Kit Reinforced Windows", prefab = "ItemKitReinforcedWindows", req = { Astroloy = 2 } },
        { name = "Kit Window Shutter",   prefab = "ItemKitWindowShutter",  req = { Steel = 2, Solder = 1 } },
        { name = "Kit Ladder",        prefab = "ItemKitLadder",         req = { Iron = 2 } },
        { name = "Kit Pipe",          prefab = "ItemKitPipe",           req = { Iron = 0.5 } },
        { name = "Cable Coil",        prefab = "ItemCableCoil",         req = { Copper = 0.5 } },
        { name = "Kit Furnace",       prefab = "ItemKitFurnace",        req = { Iron = 30, Copper = 10 }, single_batch = true },
        { name = "Kit Arc Furnace",   prefab = "ItemKitArcFurnace",     req = { Iron = 20, Copper = 5 }, single_batch = true },
        { name = "Kit Elec Printer",  prefab = "ItemKitElectronicsPrinter", req = { Iron = 20, Copper = 10, Gold = 2 }, single_batch = true },
        { name = "Kit Rocket Manuf",  prefab = "ItemKitRocketManufactory", req = { Iron = 20, Copper = 10, Gold = 2 }, single_batch = true },
        { name = "Kit Security Printer", prefab = "ItemKitSecurityPrinter", req = { Gold = 20, Copper = 20, Steel = 20 }, single_batch = true },
        { name = "Kit Blast Door",    prefab = "ItemKitBlastDoor",      req = { Steel = 15, Copper = 3 }, single_batch = true },
        { name = "Kit Robot Arm Door",prefab = "ItemKitRobotArmDoor",   req = { Steel = 12, Copper = 5, Gold = 3 }, single_batch = true },
        { name = "Kit Furniture",     prefab = "ItemKitFurniture",      req = { Iron = 20, Copper = 5 }, single_batch = true },
        { name = "Kit Tables",        prefab = "ItemKitTables",         req = { Iron = 20, Copper = 5 }, single_batch = true },
        { name = "Kit Chairs",        prefab = "ItemKitChairs",         req = { Iron = 20, Copper = 5 }, single_batch = true },
        { name = "Kit Beds",          prefab = "ItemKitBeds",           req = { Iron = 20, Copper = 5 }, single_batch = true },
        { name = "Kit Sorter",        prefab = "ItemKitSorter",         req = { Iron = 10, Gold = 1, Copper = 5 }, single_batch = true },
        { name = "Kit Pipe Bender",   prefab = "ItemKitHydraulicPipeBender", req = { Iron = 20, Copper = 10, Gold = 2 }, single_batch = true },
        { name = "Kit Autolathe",     prefab = "ItemKitAutolathe",      req = { Iron = 20, Copper = 10, Gold = 2 }, single_batch = true },
        { name = "Kit Door",          prefab = "ItemKitDoor",           req = { Iron = 7, Copper = 3 }, single_batch = true },
        { name = "Kit Interior Doors",prefab = "ItemKitInteriorDoors",  req = { Iron = 5, Copper = 3 }, single_batch = true },
        { name = "Wall Light",        prefab = "ItemWallLight",         req = { Iron = 1, Silicon = 1, Copper = 2 } },
        { name = "Kit Wall Arch",     prefab = "ItemKitWallArch",       req = { Steel = 1 } },
        { name = "Kit Wall Flat",     prefab = "ItemKitWallFlat",       req = { Steel = 1 } },
        { name = "Kit Wall Geometry", prefab = "ItemKitWallGeometry",   req = { Steel = 1 } },
        { name = "Kit Wall Padded",   prefab = "ItemKitWallPadded",     req = { Steel = 1 } },
        { name = "Kit Locker",        prefab = "ItemKitLocker",         req = { Iron = 5 } },
        { name = "Kit Sign",          prefab = "ItemKitSign",           req = { Iron = 3 } },
        { name = "Kit Stairs",        prefab = "ItemKitStairs",         req = { Iron = 15 }, single_batch = true },
        { name = "Kit Stairwell",     prefab = "ItemKitStairwell",      req = { Iron = 15 }, single_batch = true },
        { name = "Kit Stacker",       prefab = "ItemKitStacker",        req = { Iron = 10, Copper = 2 }, single_batch = true },
        { name = "Empty Can",         prefab = "ItemEmptyCan",          req = { Steel = 1 } },
        { name = "Cardboard Box",     prefab = "CardboardBox",          req = { Silicon = 2 } },
        { name = "Cardboard Box Large",  prefab = "CardboardBoxLarge",     req = { Silicon = 4 } },
        { name = "Kit Chute",         prefab = "ItemKitChute",          req = { Iron = 3 } },
        { name = "Kit Powered Chute",prefab = "ItemKitStandardChute",  req = { Iron = 3, Constantan = 2, Electrum = 2 } },
        { name = "Kit SDB Hopper",    prefab = "ItemKitSDBHopper",      req = { Iron = 15 }, single_batch = true },
        { name = "Kit SDB Silo",      prefab = "KitSDBSilo",            req = { Gold = 20, Steel = 15, Copper = 10 }, single_batch = true },
        { name = "Kit Floor Grating", prefab = "ItemKitCompositeFloorGrating", req = { Iron = 1 } },
        { name = "Kit Tool Manufactory",    prefab = "ItemKitToolManufactory", req = { Iron = 20, Copper = 10 }, single_batch = true },
        { name = "Kit Recycler",      prefab = "ItemKitRecycler",       req = { Iron = 20, Copper = 10 }, single_batch = true },
        { name = "Kit Centrifuge",    prefab = "ItemKitCentrifuge",     req = { Iron = 20, Copper = 5 }, single_batch = true },
        { name = "Kit Combustion Centrifuge",prefab = "KitStructureCombustionCentrifuge", req = { Steel = 20, Constantan = 5, Invar = 10 }, single_batch = true },
        { name = "Kit Deep Miner",    prefab = "ItemKitDeepMiner",      req = { Steel = 50, Constantan = 5, Invar = 10, Electrum = 5 }, single_batch = true },
        { name = "Kit Combustion Deep Miner",prefab = "ItemKitCombustionDeepMiner", req = { Steel = 50, Hastelloy = 10, Astroloy = 5, Electrum = 5 }, single_batch = true },
        { name = "Kit Crate Mount",   prefab = "ItemKitCrateMount",     req = { Iron = 10 }, single_batch = true },
        { name = "Kit Crate",         prefab = "ItemKitCrate",          req = { Iron = 10 }, single_batch = true },
        { name = "Kit Crate MkII",    prefab = "ItemKitCrateMkII",      req = { Iron = 10, Gold = 5 }, single_batch = true },
        { name = "Space Helmet",      prefab = "ItemSpaceHelmet",       req = { Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Eva Suit",          prefab = "ItemEvaSuit",           req = { Iron = 5, Copper = 5 }, single_batch = true },
        { name = "Burger Box",        prefab = "ItemBurgerBox",         req = { Silicon = 2 } },
        { name = "Egg Carton",        prefab = "ItemEggCarton",         req = { Silicon = 2 } },
        { name = "Coffee Mug",        prefab = "ItemCoffeeMug",         req = { Iron = 1 }, single_batch = true },
        { name = "Kit Flag ODA",      prefab = "ItemKitFlagODA",        req = { Iron = 8 }, single_batch = true },
        { name = "Kit Access Bridge", prefab = "ItemKitAccessBridge",   req = { Copper = 2, Steel = 10, Solder = 2 }, single_batch = true },
        { name = "Bobblehead Basic",  prefab = "ApplianceBobbleHeadBasicSuit", req = { Iron = 5, Gold = 1 }, single_batch = true },
        { name = "Bobblehead Hard",   prefab = "ApplianceBobbleHeadHardSuit",  req = { Iron = 5, Gold = 1 }, single_batch = true },
        { name = "Bobblehead Marine", prefab = "ApplianceBobbleHeadMarine",    req = { Iron = 5, Gold = 1 }, single_batch = true },
    },
    -- ===== [2] ELECTRONICS =================
    [2] = {
        { name = "Grow Light",        prefab = "ItemKitGrowLight",      req = { Copper = 5, Steel = 5, Electrum = 10 }, single_batch = true },
        { name = "Battery Cell",      prefab = "ItemBatteryCell",       req = { Iron = 2, Gold = 2, Copper = 5 }, single_batch = true },
        { name = "Battery Cell Large",prefab = "ItemBatteryCellLarge",  req = { Steel = 5, Gold = 5, Copper = 10 }, single_batch = true },
        { name = "Wireless Battery",  prefab = "Battery_Wireless_cell", req = { Iron = 2, Gold = 2, Copper = 10 }, single_batch = true },
        { name = "Wireless Battery Lg",prefab = "Battery_Wireless_cell_Big", req = { Steel = 5, Gold = 5, Copper = 15 }, single_batch = true },
        { name = "Power Transmitter", prefab = "ItemKitPowerTransmitter", req = { Steel = 3, Gold = 5, Copper = 7 }, single_batch = true },
        { name = "Power Trans Omni",  prefab = "ItemKitPowerTransmitterOmni", req = { Steel = 4, Gold = 4, Copper = 8 }, single_batch = true },
        { name = "Nuclear Battery",   prefab = "ItemBatteryCellNuclear", req = { Steel = 5, Inconel = 5, Astroloy = 10 }, single_batch = true },
        { name = "HEMD Repair Kit",   prefab = "ItemHEMDroidRepairKit", req = { Solder = 5, Inconel = 5, Electrum = 10 }, single_batch = true },
        { name = "Battery Charger",   prefab = "ItemBatteryCharger",    req = { Steel = 10, Electrum = 5, Copper = 5 }, single_batch = true },
        { name = "Battery Charger Sm",prefab = "ItemBatteryChargerSmall", req = { Iron = 5, Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Atmos Analyser",    prefab = "CartridgeAtmosAnalyser", req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Plant Analyser",    prefab = "CartridgePlantAnalyser", req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Network Analyser",  prefab = "CartridgeNetworkAnalyser", req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Sound Bass",        prefab = "ItemSoundCartridgeBass",  req = { Silicon = 2, Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Sound Drums",       prefab = "ItemSoundCartridgeDrums", req = { Silicon = 2, Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Sound Leads",       prefab = "ItemSoundCartridgeLeads", req = { Silicon = 2, Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Sound Synth",       prefab = "ItemSoundCartridgeSynth", req = { Silicon = 2, Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Ore Scanner Color", prefab = "CartridgeOreScannerColor", req = { Silicon = 5, Electrum = 5, Invar = 5, Constantan = 5 }, single_batch = true },
        { name = "Kit AIMeE",         prefab = "ItemKitAIMeE",          req = { Gold = 5, Copper = 5, Steel = 22, Electrum = 15, Invar = 7, Constantan = 8, Astroloy = 10 }, single_batch = true },
        { name = "Kit Fridge Small",  prefab = "ItemKitFridgeSmall",    req = { Iron = 10, Gold = 2, Copper = 5 }, single_batch = true },
        { name = "Kit Fridge Big",    prefab = "ItemKitFridgeBig",      req = { Iron = 20, Gold = 5, Copper = 10, Steel = 15 }, single_batch = true },
        { name = "Config Cart",       prefab = "CartridgeConfiguration", req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Tracker Cart",      prefab = "CartridgeTracker",      req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Deep Miner Cart",   prefab = "CartridgeDeepMiner",    req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Air Control CB",    prefab = "CircuitboardAirControl", req = { Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Adv Airlock CB",    prefab = "CircuitboardAdvAirlockControl", req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Airlock CB",        prefab = "CircuitboardAirlockControl", req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Door CB",           prefab = "CircuitboardDoorControl", req = { Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Gas Display CB",    prefab = "CircuitboardGasDisplay", req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Mode CB",           prefab = "CircuitboardModeControl", req = { Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Power CB",          prefab = "CircuitboardPowerControl", req = { Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Solar CB",          prefab = "CircuitboardSolarControl", req = { Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Graph Display CB",  prefab = "CircuitboardGraphDisplay", req = { Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Hash Display CB",   prefab = "CircuitboardHashDisplay", req = { Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Area Power Control",prefab = "ItemAreaPowerControl",   req = { Iron = 5, Copper = 2, Solder = 3 }, single_batch = true },
        { name = "Cable Analyser",    prefab = "ItemCableAnalyser",     req = { Iron = 1, Copper = 2, Silicon = 2 }, single_batch = true },
        { name = "Cable Coil",        prefab = "ItemCableCoil",         req = { Copper = 0.5 } },
        { name = "Cable Coil Heavy",  prefab = "ItemCableCoilHeavy",    req = { Gold = 0.5, Copper = 0.5 } },
        { name = "Cable Coil S.Heavy",prefab = "ItemCableCoilSuperHeavy", req = { Constantan = 0.5, Electrum = 0.5 } },
        { name = "Cable Fuse",        prefab = "ItemCableFuse",         req = { Iron = 5, Copper = 5 }, single_batch = true },
        { name = "Data Disk",         prefab = "ItemDataDisk",          req = { Gold = 5, Copper = 5 }, single_batch = true },
        { name = "Flashing Light",    prefab = "ItemFlashingLight",     req = { Iron = 2, Copper = 3 }, single_batch = true },
        { name = "Kit Battery",       prefab = "ItemKitBattery",        req = { Gold = 20, Copper = 20, Steel = 20 }, single_batch = true },
        { name = "Kit Battery Large", prefab = "ItemKitBatteryLarge",   req = { Gold = 35, Copper = 35, Steel = 35, Electrum = 10, Silicon = 5, Stellite = 2 }, single_batch = true },
        { name = "Kit Computer",      prefab = "ItemKitComputer",       req = { Iron = 5, Gold = 5, Copper = 10 }, single_batch = true },
        { name = "Kit Console",       prefab = "ItemKitConsole",        req = { Iron = 2, Gold = 3, Copper = 5 }, single_batch = true },
        { name = "Kit Logic I/O",     prefab = "ItemKitLogicInputOutput", req = { Gold = 1, Copper = 1 }, single_batch = true },
        { name = "Kit Logic Memory",  prefab = "ItemKitLogicMemory",    req = { Gold = 1, Copper = 1 }, single_batch = true },
        { name = "Kit Speaker",       prefab = "ItemKitSpeaker",        req = { Gold = 1, Copper = 1, Steel = 5 }, single_batch = true },
        { name = "Kit Logic Processor",prefab = "ItemKitLogicProcessor", req = { Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Kit Music Machines",prefab = "ItemKitMusicMachines",  req = { Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Kit Logic Trans",   prefab = "ItemKitLogicTransmitter", req = { Gold = 2, Copper = 1, Electrum = 3, Silicon = 5 }, single_batch = true },
        { name = "Kit Logic Switch",  prefab = "ItemKitLogicSwitch",   req = { Gold = 1, Copper = 1 }, single_batch = true },
        { name = "IC10",              prefab = "ItemIntegratedCircuit10", req = { Gold = 10, Steel = 4, Electrum = 5, Solder = 2 }, single_batch = true },
        { name = "Kit Logic Circuit", prefab = "ItemKitLogicCircuit",  req = { Copper = 10, Steel = 4, Solder = 2 }, single_batch = true },
        { name = "Power Connector",   prefab = "ItemPowerConnector",   req = { Iron = 10, Gold = 3, Copper = 5 }, single_batch = true },
        { name = "Kit Pressure Plate",prefab = "ItemKitPressurePlate", req = { Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Kit Solid Generator",prefab = "ItemKitSolidGenerator", req = { Iron = 50, Copper = 10 }, single_batch = true },
        { name = "Kit Gas Generator", prefab = "ItemKitGasGenerator",  req = { Steel = 30, Constantan = 10, Electrum = 5 }, single_batch = true },
        { name = "Kit Sensor",        prefab = "ItemKitSensor",        req = { Iron = 3, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "Electronic Parts",  prefab = "ItemElectronicParts",  req = { Iron = 3, Gold = 2, Copper = 3 } },
        { name = "Weather Station",   prefab = "ItemKitWeatherStation", req = { Iron = 8, Gold = 3, Copper = 5, Steel = 3 }, single_batch = true },
        { name = "Solar Panel Basic", prefab = "ItemKitSolarPanelBasic", req = { Iron = 10, Gold = 2, Copper = 10 }, single_batch = true },
        { name = "Solar Panel Adv",   prefab = "ItemKitSolarPanel",    req = { Steel = 15, Gold = 5, Copper = 20 }, single_batch = true },
        { name = "Kit Stirling Engine",prefab = "ItemKitStirlingEngine", req = { Steel = 30, Gold = 5, Copper = 20 }, single_batch = true },
        { name = "Solar Basic Reinf", prefab = "ItemKitSolarPanelBasicReinforced", req = { Steel = 10, Invar = 10, Electrum = 2, Copper = 10 }, single_batch = true },
        { name = "Solar Adv Reinf",   prefab = "ItemKitSolarPanelReinforced", req = { Steel = 10, Astroloy = 15, Electrum = 5, Copper = 20 }, single_batch = true },
        { name = "Portable Solar",    prefab = "PortableSolarPanel",   req = { Iron = 5, Gold = 3, Copper = 5 }, single_batch = true },
        { name = "Transformer",       prefab = "ItemKitTransformer",   req = { Steel = 10, Electrum = 5 }, single_batch = true },
        { name = "Transformer Small", prefab = "ItemKitTransformerSmall", req = { Iron = 10, Copper = 3, Gold = 1 }, single_batch = true },
        { name = "Tablet",            prefab = "ItemTablet",           req = { Copper = 3, Gold = 2, Solder = 5 }, single_batch = true },
        { name = "Advanced Tablet",   prefab = "ItemAdvancedTablet",   req = { Iron = 3, Copper = 5, Gold = 12, Steel = 2, Solder = 5, Electrum = 1 }, single_batch = true },
        { name = "Laptop",            prefab = "ItemLaptop",           req = { Copper = 5, Gold = 12, Steel = 2, Solder = 5, Electrum = 5 }, single_batch = true },
        { name = "Wall Light (Elec)", prefab = "ItemWallLight",        req = { Iron = 1, Copper = 2 }, single_batch = true },
        { name = "Logic Motherboard", prefab = "MotherboardLogic",     req = { Copper = 5, Gold = 5 }, single_batch = true },
        { name = "Rockets MB",        prefab = "MotherboardRockets",   req = { Solder = 5, Electrum = 5 }, single_batch = true },
        { name = "Map Motherboard",   prefab = "MotherboardMap",       req = { Solder = 5, Electrum = 5 }, single_batch = true },
        { name = "Prog Chip MB",      prefab = "MotherboardProgrammableChip", req = { Copper = 5, Gold = 5 }, single_batch = true },
        { name = "Sorter Motherboard",prefab = "MotherboardSorter",    req = { Gold = 5, Silver = 5 }, single_batch = true },
        { name = "Comms Motherboard", prefab = "MotherboardComms",     req = { Copper = 5, Gold = 5, Silver = 5, Electrum = 2 }, single_batch = true },
        { name = "Kit Beacon",        prefab = "ItemKitBeacon",        req = { Copper = 2, Gold = 4, Steel = 5, Solder = 2 }, single_batch = true },
        { name = "Kit Elevator",      prefab = "ItemKitElevator",      req = { Copper = 2, Gold = 4, Steel = 2, Solder = 2 }, single_batch = true },
        { name = "Kit Hydroponics Stn",prefab = "ItemKitHydroponicStation", req = { Gold = 5, Copper = 20, Steel = 10 }, single_batch = true },
        { name = "Small Satellite Dish",prefab = "ItemKitSmallSatelliteDish", req = { Gold = 5, Copper = 10 }, single_batch = true },
        { name = "Satellite Dish",    prefab = "ItemKitSatelliteDish", req = { Electrum = 15, Steel = 20, Solder = 10 }, single_batch = true },
        { name = "Large Satellite Dish",prefab = "ItemKitLargeSatelliteDish", req = { Astroloy = 100, Inconel = 50, Waspaloy = 20 }, single_batch = true },
        { name = "Landing Pad Basic", prefab = "ItemKitLandingPadBasic", req = { Copper = 1, Steel = 5 }, single_batch = true },
        { name = "Landing Pad Atmos", prefab = "ItemKitLandingPadAtmos", req = { Copper = 1, Steel = 5 }, single_batch = true },
        { name = "Landing Pad Waypoint",prefab = "ItemKitLandingPadWaypoint", req = { Copper = 1, Steel = 5 }, single_batch = true },
        { name = "Harvie",            prefab = "ItemKitHarvie",        req = { Electrum = 10, Copper = 15, Steel = 10, Solder = 5, Silicon = 5 }, single_batch = true },
        { name = "Dynamic Generator", prefab = "ItemKitDynamicGenerator", req = { Gold = 15, Steel = 20, Solder = 5 }, single_batch = true },
        { name = "Vending Machine",   prefab = "ItemKitVendingMachine", req = { Steel = 10, Gold = 25, Solder = 5, Electrum = 25 }, single_batch = true },
        { name = "Vending Refrigerated",prefab = "ItemKitVendingMachineRefrigerated", req = { Steel = 40, Gold = 60, Solder = 30, Electrum = 80 }, single_batch = true },
        { name = "Kit Automated Oven",prefab = "ItemKitAutomatedOven", req = { Steel = 25, Gold = 10, Copper = 15, Solder = 10, Constantan = 5 }, single_batch = true },
        { name = "Advanced Packaging",prefab = "ItemKitAdvancedPackagingMachine", req = { Steel = 20, Copper = 10, Constantan = 10, Electrum = 15 }, single_batch = true },
        { name = "Advanced Composter",prefab = "ItemKitAdvancedComposter", req = { Steel = 30, Copper = 15, Electrum = 20, Solder = 5 }, single_batch = true },
        { name = "Portable Composter",prefab = "PortableComposter",    req = { Steel = 10, Copper = 15 }, single_batch = true },
        { name = "Upright Wind Turbine",prefab = "ItemKitUprightWindTurbine", req = { Iron = 10, Gold = 5, Copper = 10 }, single_batch = true },
        { name = "Wind Turbine",      prefab = "ItemKitWindTurbine",   req = { Steel = 20, Electrum = 5, Copper = 10 }, single_batch = true },
        { name = "Labeller",          prefab = "ItemLabeller",         req = { Iron = 3, Gold = 1, Copper = 2 }, single_batch = true },
        { name = "Electronics Printer Mod",prefab = "ElectronicPrinterMod", req = { Steel = 35, Electrum = 8, Solder = 8, Constantan = 8 }, single_batch = true },
        { name = "Autolathe Mod",     prefab = "AutolathePrinterMod",  req = { Steel = 35, Electrum = 8, Solder = 8, Constantan = 8 }, single_batch = true },
        { name = "Tool Printer Mod",  prefab = "ToolPrinterMod",       req = { Steel = 35, Electrum = 8, Solder = 8, Constantan = 8 }, single_batch = true },
        { name = "PipeBender Mod",    prefab = "PipeBenderMod",        req = { Steel = 35, Electrum = 8, Solder = 8, Constantan = 8 }, single_batch = true },
        { name = "Kit Adv Furnace",   prefab = "ItemKitAdvancedFurnace", req = { Gold = 5, Copper = 25, Steel = 30, Electrum = 15, Solder = 8, Silicon = 6 }, single_batch = true },
        { name = "Microwave",         prefab = "ApplianceMicrowave",   req = { Iron = 5, Gold = 1, Copper = 2 }, single_batch = true },
        { name = "Tablet Dock",       prefab = "ApplianceTabletDock",  req = { Iron = 5, Gold = 1, Copper = 2, Silicon = 1 }, single_batch = true },
        { name = "Packaging Machine", prefab = "AppliancePackagingMachine", req = { Iron = 10, Gold = 1, Copper = 2 }, single_batch = true },
        { name = "Desk Lamp Right",   prefab = "ApplianceDeskLampRight", req = { Iron = 2, Silicon = 1 }, single_batch = true },
        { name = "Desk Lamp Left",    prefab = "ApplianceDeskLampLeft",  req = { Iron = 2, Silicon = 1 }, single_batch = true },
        { name = "Reagent Processor", prefab = "ApplianceReagentProcessor", req = { Iron = 5, Gold = 1, Copper = 2 }, single_batch = true },
        { name = "Chemistry Station", prefab = "ApplianceChemistryStation", req = { Gold = 1, Copper = 5, Steel = 5 }, single_batch = true },
        { name = "Auto Miner Small",  prefab = "ItemKitAutoMinerSmall", req = { Iron = 15, Copper = 15, Steel = 100, Electrum = 50, Invar = 25 }, single_batch = true },
        { name = "Horizontal Auto Miner",prefab = "ItemKitHorizontalAutoMiner", req = { Iron = 8, Copper = 7, Steel = 60, Electrum = 25, Invar = 15 }, single_batch = true },
        { name = "Credit Card",       prefab = "ItemCreditCard",       req = { Silicon = 5, Copper = 2 }, single_batch = true },
        { name = "Genetic Analyzer",       prefab = "AppliancePlantGeneticAnalyzer",       req = { Gold = 1, Copper = 5, Steel = 5 }, single_batch = true },
        { name = "Genetic Splicer",       prefab = "AppliancePlantGeneticSplicer",       req = { Stellite = 20, Inconel = 10 }, single_batch = true },
        { name = "Genetic Stabilizer",       prefab = "AppliancePlantGeneticStabilizer",       req = { Stellite = 20, Inconel = 10 }, single_batch = true },
        { name = "Ground Telescope",       prefab = "ItemKitGroundTelescope",       req = { Electrum = 15, Steel = 25, Solder = 10 }, single_batch = true },
        { name = "Linear Rail",       prefab = "ItemKitLinearRail",       req = { Steel = 3 }, single_batch = true },
        { name = "Robotic Arm",       prefab = "ItemKitRoboticArm",       req = { Inconel = 10, Astroloy = 15, Hastelloy = 5 }, single_batch = true },
        { name = "LArRE Dock Atmos",       prefab = "ItemKitLarreDockAtmos",       req = { Inconel = 10, Astroloy = 15, Hastelloy = 5 }, single_batch = true },
        { name = "LArRE Dock Bypass",       prefab = "ItemKitLarreDockBypass",       req = { Inconel = 10, Astroloy = 15, Hastelloy = 5 }, single_batch = true },
        { name = "LArRE Dock Cargo",       prefab = "ItemKitLarreDockCargo",       req = { Inconel = 10, Astroloy = 15, Hastelloy = 5 }, single_batch = true },
        { name = "LArRE Dock Collector",       prefab = "ItemKitLarreDockCollector",       req = { Inconel = 10, Astroloy = 15, Hastelloy = 5 }, single_batch = true },
        { name = "LArRE Dock Hydroponics",       prefab = "ItemKitLarreDockHydroponics",       req = { Inconel = 10, Astroloy = 15, Hastelloy = 5 }, single_batch = true },
        { name = "Rover MKI",       prefab = "ItemKitRoverMKI",       req = { Copper = 15, Steel = 80, Electrum = 10, Constanttan = 5 }, single_batch = true },
    },
    -- ===== [3] PIPE BENDER =================
    [3] = {
        { name = "Active Vent",       prefab = "ItemActiveVent",       req = { Iron = 5, Gold = 1, Copper = 5 }, single_batch = true },
        { name = "Gas Canister",      prefab = "ItemGasCanisterEmpty", req = { Iron = 5 }, single_batch = true },
        { name = "Water Bottle Filler",prefab = "ItemKitWaterBottleFiller", req = { Copper = 3, Iron = 5, Silicon = 8 }, single_batch = true },
        { name = "Drinking Fountain", prefab = "ItemKitDrinkingFountain", req = { Copper = 3, Iron = 5, Silicon = 8 }, single_batch = true },
        { name = "Water Bottle",      prefab = "ItemWaterBottle",      req = { Iron = 2, Silicon = 4 }, single_batch = true },
        { name = "Smart Gas Canister",prefab = "ItemGasCanisterSmart", req = { Copper = 2, Steel = 15, Silicon = 2 }, single_batch = true },
        { name = "Smart Liq Canister",prefab = "ItemLiquidCanisterSmart", req = { Copper = 2, Steel = 15, Silicon = 2 }, single_batch = true },
        { name = "Liquid Canister",   prefab = "ItemLiquidCanisterEmpty", req = { Iron = 5 }, single_batch = true },
        { name = "Suit Storage",      prefab = "ItemKitSuitStorage",   req = { Iron = 15, Copper = 5, Silver = 5 }, single_batch = true },
        { name = "Gas Filter CO2 (S)",prefab = "ItemGasFilterCarbonDioxide", req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter Alc (S)",prefab = "ItemGasFilterAlcohol",       req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter HCl (S)",prefab = "ItemGasFilterHCl",           req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter He (S)", prefab = "ItemGasFilterHelium",        req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter N2H4 (S)",prefab = "ItemGasFilterHydrazine",    req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter H2 (S)", prefab = "ItemGasFilterHydrogen",      req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter O3 (S)", prefab = "ItemGasFilterOzone",         req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter PW (S)", prefab = "ItemGasFilterPollutedWater", req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter NaCl (S)",prefab = "ItemGasFilterSalt",         req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter SiH4 (S)",prefab = "ItemGasFilterSilanol",      req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter Pol (S)",prefab = "ItemGasFilterPollutants",    req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter N2 (S)", prefab = "ItemGasFilterNitrogen",      req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter O2 (S)", prefab = "ItemGasFilterOxygen",        req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter Vol (S)",prefab = "ItemGasFilterVolatiles",     req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter N2O (S)",prefab = "ItemGasFilterNitrousOxide",  req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter H2O (S)",prefab = "ItemGasFilterWater",         req = { Iron = 5 }, single_batch = true },
        { name = "Gas Filter CO2 (M)",prefab = "ItemGasFilterCarbonDioxideM", req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter Alc (M)",prefab = "ItemGasFilterAlcoholM",       req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter HCl (M)",prefab = "ItemGasFilterHClM",           req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter He (M)", prefab = "ItemGasFilterHeliumM",        req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter N2H4 (M)",prefab = "ItemGasFilterHydrazineM",   req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter H2 (M)", prefab = "ItemGasFilterHydrogenM",     req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter O3 (M)", prefab = "ItemGasFilterOzoneM",        req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter PW (M)", prefab = "ItemGasFilterPollutedWaterM",req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter NaCl(M)",prefab = "ItemGasFilterSaltM",         req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter SiH4(M)",prefab = "ItemGasFilterSilanolM",      req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter Pol (M)",prefab = "ItemGasFilterPollutantsM",   req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter N2 (M)", prefab = "ItemGasFilterNitrogenM",     req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter O2 (M)", prefab = "ItemGasFilterOxygenM",       req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter Vol (M)",prefab = "ItemGasFilterVolatilesM",    req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter N2O (M)",prefab = "ItemGasFilterNitrousOxideM", req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter H2O (M)",prefab = "ItemGasFilterWaterM",        req = { Iron = 5, Silver = 5, Constantan = 1 }, single_batch = true },
        { name = "Gas Filter CO2 (L)",prefab = "ItemGasFilterCarbonDioxideL", req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter Alc (L)",prefab = "ItemGasFilterAlcoholL",       req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter HCl (L)",prefab = "ItemGasFilterHClL",           req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter He (L)", prefab = "ItemGasFilterHeliumL",        req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter N2H4 (L)",prefab = "ItemGasFilterHydrazineL",   req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter H2 (L)", prefab = "ItemGasFilterHydrogenL",     req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter O3 (L)", prefab = "ItemGasFilterOzoneL",        req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter PW (L)", prefab = "ItemGasFilterPollutedWaterL",req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter NaCl(L)",prefab = "ItemGasFilterSaltL",         req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter SiH4(L)",prefab = "ItemGasFilterSilanolL",      req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter Pol (L)",prefab = "ItemGasFilterPollutantsL",   req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter N2 (L)", prefab = "ItemGasFilterNitrogenL",     req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter O2 (L)", prefab = "ItemGasFilterOxygenL",       req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter Vol (L)",prefab = "ItemGasFilterVolatilesL",    req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter N2O (L)",prefab = "ItemGasFilterNitrousOxideL", req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Gas Filter H2O (L)",prefab = "ItemGasFilterWaterL",        req = { Steel = 5, Stellite = 1, Invar = 1 }, single_batch = true },
        { name = "Pipe Utility",      prefab = "ItemKitPipeUtility",   req = { Iron = 5 } },
        { name = "Pipe Utility Liquid",prefab = "ItemKitPipeUtilityLiquid", req = { Iron = 5 } },
        { name = "Adhesive Insulation",prefab = "ItemAdhesiveInsulation", req = { Steel = 0.5, Silicon = 1 } },
        { name = "Insulated Pipe Util",prefab = "ItemKitInsulatedPipeUtility", req = { Steel = 5, Silicon = 1 } },
        { name = "Ins Pipe Util Liq", prefab = "ItemKitInsulatedPipeUtilityLiquid", req = { Steel = 5, Silicon = 1 } },
        { name = "Hydroponic Tray",   prefab = "ItemHydroponicTray",   req = { Iron = 10 } },
        { name = "Kit Planter",       prefab = "ItemKitPlanter",       req = { Iron = 10 }, single_batch = true },
        { name = "Kit Airlock",       prefab = "ItemKitAirlock",       req = { Steel = 15, Copper = 5, Gold = 5 }, single_batch = true },
        { name = "Kit Airlock Gate",  prefab = "ItemKitAirlockGate",   req = { Steel = 25, Copper = 5, Gold = 5 }, single_batch = true },
        { name = "Kit Atmospherics",  prefab = "ItemKitAtmospherics",  req = { Iron = 10, Gold = 5, Copper = 20 }, single_batch = true },
        { name = "Kit Liq Filtration",prefab = "ItemKitLiquidFiltration", req = { Iron = 10, Gold = 5, Copper = 20 }, single_batch = true },
        { name = "Kit Water Purifier",prefab = "ItemKitWaterPurifier", req = { Iron = 10, Gold = 5, Copper = 20 }, single_batch = true },
        { name = "Kit Chute",         prefab = "ItemKitChute",         req = { Iron = 3 } },
        { name = "Kit Powered Chute",prefab = "ItemKitStandardChute", req = { Iron = 3, Constantan = 2, Electrum = 2 } },
        { name = "Kit Pipe",          prefab = "ItemKitPipe",          req = { Iron = 0.5 } },
        { name = "Insulated Pipe",    prefab = "ItemKitInsulatedPipe", req = { Steel = 1, Silicon = 1 } },
        { name = "Insulated Liq Pipe",prefab = "ItemKitInsulatedLiquidPipe", req = { Steel = 1, Silicon = 1 } },
        { name = "Kit Liquid Pipe",   prefab = "ItemKitPipeLiquid",    req = { Iron = 0.5 } },
        { name = "Kit Regulator",     prefab = "ItemKitRegulator",     req = { Iron = 5, Copper = 2, Gold = 1 }, single_batch = true },
        { name = "Kit Liquid Regulator",prefab = "ItemKitLiquidRegulator", req = { Iron = 5, Copper = 2, Gold = 1 }, single_batch = true },
        { name = "Kit Tank",          prefab = "ItemKitTank",          req = { Copper = 5, Steel = 20 }, single_batch = true },
        { name = "Kit Liquid Tank",   prefab = "ItemKitLiquidTank",    req = { Copper = 5, Steel = 20 }, single_batch = true },
        { name = "Kit Tank Insulated",prefab = "ItemKitTankInsulated", req = { Copper = 5, Steel = 20, Silicon = 30 }, single_batch = true },
        { name = "Kit Liq Tank Ins",  prefab = "ItemKitLiquidTankInsulated", req = { Copper = 5, Steel = 20, Silicon = 30 }, single_batch = true },
        { name = "Passive Vent",      prefab = "ItemPassiveVent",      req = { Iron = 3 }, single_batch = true },
        { name = "Passive Vent Ins",  prefab = "ItemPassiveVentInsulated", req = { Steel = 1, Silicon = 5 }, single_batch = true },
        { name = "Pipe Cowl",         prefab = "ItemPipeCowl",         req = { Iron = 3 }, single_batch = true },
        { name = "Pipe Analyser",     prefab = "ItemPipeAnalyizer",    req = { Iron = 2, Gold = 2, Electrum = 2 }, single_batch = true },
        { name = "Liquid Pipe Analyser",prefab = "ItemLiquidPipeAnalyzer", req = { Iron = 2, Gold = 2, Electrum = 2 }, single_batch = true },
        { name = "Pipe Igniter",      prefab = "ItemPipeIgniter",      req = { Iron = 2, Electrum = 2 }, single_batch = true },
        { name = "Pipe Digital Valve",prefab = "ItemPipeDigitalValve",  req = { Copper = 2, Steel = 5, Invar = 3 }, single_batch = true },
        { name = "Water Pipe Dig Valve",prefab = "ItemWaterPipeDigitalValve", req = { Copper = 2, Steel = 5, Invar = 3 }, single_batch = true },
        { name = "Gas Mixer",         prefab = "ItemPipeGasMixer",     req = { Iron = 2, Gold = 2, Copper = 2 }, single_batch = true },
        { name = "Pipe Label",        prefab = "ItemPipeLabel",        req = { Iron = 1 } },
        { name = "Pipe Meter",        prefab = "ItemPipeMeter",        req = { Iron = 3, Copper = 2 }, single_batch = true },
        { name = "Water Pipe Meter",  prefab = "ItemWaterPipeMeter",   req = { Iron = 3, Copper = 2 }, single_batch = true },
        { name = "Liquid Drain",      prefab = "ItemLiquidDrain",      req = { Iron = 5, Copper = 2 }, single_batch = true },
        { name = "Pipe Radiator",     prefab = "ItemKitPipeRadiator",  req = { Gold = 3, Steel = 2 }, single_batch = true },
        { name = "Large Ext Radiator",prefab = "ItemKitLargeExtendableRadiator", req = { Copper = 10, Steel = 10, Invar = 10 }, single_batch = true },
        { name = "Passive Lg Rad Liq",prefab = "ItemKitPassiveLargeRadiatorLiquid", req = { Copper = 5, Steel = 5, Invar = 5 }, single_batch = true },
        { name = "Passive Lg Rad Gas",prefab = "ItemKitPassiveLargeRadiatorGas", req = { Copper = 5, Steel = 5, Invar = 5 }, single_batch = true },
        { name = "Powered Vent",      prefab = "ItemKitPoweredVent",   req = { Electrum = 5, Steel = 5, Invar = 2 }, single_batch = true },
        { name = "Large Dir HX",      prefab = "ItemKitLargeDirectHeatExchanger", req = { Invar = 10, Steel = 10 }, single_batch = true },
        { name = "Passthrough HX",    prefab = "ItemKitPassthroughHeatExchanger", req = { Invar = 10, Steel = 10 }, single_batch = true },
        { name = "Small Direct HX",   prefab = "ItemKitSmallDirectHeatExchanger", req = { Copper = 5, Steel = 3 }, single_batch = true },
        { name = "Evaporation Chamber",prefab = "ItemKitEvaporationChamber", req = { Copper = 10, Steel = 10, Silicon = 5 }, single_batch = true },
        { name = "Pipe Radiator Liq", prefab = "ItemKitPipeRadiatorLiquid", req = { Gold = 3, Steel = 2 }, single_batch = true },
        { name = "Pipe Valve",        prefab = "ItemPipeValve",        req = { Iron = 3, Copper = 2 }, single_batch = true },
        { name = "Liquid Pipe Valve", prefab = "ItemLiquidPipeValve",  req = { Iron = 3, Copper = 2 }, single_batch = true },
        { name = "Volume Pump",       prefab = "ItemPipeVolumePump",   req = { Iron = 5, Gold = 2, Copper = 3 }, single_batch = true },
        { name = "Turbo Volume Pump", prefab = "ItemKitTurboVolumePump", req = { Gold = 4, Electrum = 5, Copper = 4, Steel = 5 }, single_batch = true },
        { name = "Liq Turbo Vol Pump",prefab = "ItemKitLiquidTurboVolumePump", req = { Gold = 4, Electrum = 5, Copper = 4, Steel = 5 }, single_batch = true },
        { name = "Liquid Volume Pump",prefab = "ItemLiquidPipeVolumePump", req = { Iron = 5, Gold = 2, Copper = 3 }, single_batch = true },
        { name = "Liquid Pipe Heater",prefab = "ItemLiquidPipeHeater", req = { Iron = 5, Gold = 3, Copper = 3 }, single_batch = true },
        { name = "Pipe Heater",       prefab = "ItemPipeHeater",       req = { Iron = 5, Gold = 3, Copper = 3 }, single_batch = true },
        { name = "Portables Connector",prefab = "ItemKitPortablesConnector", req = { Iron = 5 }, single_batch = true },
        { name = "Wall Cooler",       prefab = "ItemWallCooler",       req = { Iron = 3, Gold = 1, Copper = 3 }, single_batch = true },
        { name = "Water Wall Cooler", prefab = "ItemWaterWallCooler",  req = { Iron = 3, Gold = 1, Copper = 3 }, single_batch = true },
        { name = "Wall Heater",       prefab = "ItemWallHeater",       req = { Iron = 3, Gold = 1, Copper = 3 }, single_batch = true },
        { name = "Kit Sleeper",       prefab = "ItemKitSleeper",       req = { Steel = 25, Gold = 10, Copper = 10 }, single_batch = true },
        { name = "Kit Cryo Tube",     prefab = "ItemKitCryoTube",      req = { Gold = 10, Silver = 5, Copper = 10, Steel = 35 }, single_batch = true },
        { name = "Dynamic Air Con",   prefab = "ItemDynamicAirCon",    req = { Gold = 5, Silver = 5, Steel = 20, Solder = 5 }, single_batch = true },
        { name = "Dynamic Scrubber",  prefab = "ItemDynamicScrubber",  req = { Gold = 5, Invar = 5, Steel = 20, Solder = 5 }, single_batch = true },
        { name = "Kit Dynamic Hydro", prefab = "ItemKitDynamicHydroponics", req = { Steel = 20, Copper = 5 }, single_batch = true },
        { name = "Kit Pipe Organ",    prefab = "ItemKitPipeOrgan",     req = { Iron = 3 }, single_batch = true },
        { name = "Kit Ice Crusher",   prefab = "ItemKitIceCrusher",    req = { Iron = 3, Copper = 1, Gold = 1 }, single_batch = true },
        { name = "Kit Shower",        prefab = "ItemKitShower",        req = { Iron = 5, Copper = 5, Silicon = 5 }, single_batch = true },
        { name = "Appliance Seed Tray",         prefab = "ApplianceSeedTray",    req = { Iron = 10, Copper = 5, Silicon = 15 }, single_batch = true },
    },
    -- ===== [4] ROCKET MANUFACTORY =================
    [4] = {
        { name = "ItemKitFuselage", prefab = "ItemKitFuselage", req = { Steel = 20 }, single_batch = true },
        { name = "ItemKitLaunchTower", prefab = "ItemKitLaunchTower", req = { Steel = 10 }, single_batch = true },
        { name = "ItemKitLaunchMount", prefab = "ItemKitLaunchMount", req = { Steel = 60 }, single_batch = true },
        { name = "ItemKitChuteUmbilical", prefab = "ItemKitChuteUmbilical", req = { Steel = 10, Copper = 3 }, single_batch = true },
        { name = "ItemKitElectricUmbilical", prefab = "ItemKitElectricUmbilical", req = { Steel = 5, Gold = 5 }, single_batch = true },
        { name = "ItemKitLiquidUmbilical", prefab = "ItemKitLiquidUmbilical", req = { Steel = 5, Copper = 5 }, single_batch = true },
        { name = "ItemKitGasUmbilical", prefab = "ItemKitGasUmbilical", req = { Steel = 5, Copper = 5 }, single_batch = true },
        { name = "ItemKitRocketBattery", prefab = "ItemKitRocketBattery", req = { Electrum = 5, Solder = 5, Steel = 10 }, single_batch = true },
        { name = "ItemKitRocketGasFuelTank", prefab = "ItemKitRocketGasFuelTank", req = { Copper = 5, Steel = 10 }, single_batch = true },
        { name = "ItemKitRocketLiquidFuelTank", prefab = "ItemKitRocketLiquidFuelTank", req = { Copper = 5, Steel = 20 }, single_batch = true },
        { name = "ItemKitRocketAvionics", prefab = "ItemKitRocketAvionics", req = { Solder = 3, Electrum = 2 }, single_batch = true },
        { name = "ItemKitRocketCelestialTracker", prefab = "ItemKitRocketCelestialTracker", req = { Steel = 5, Electrum = 5 }, single_batch = true },
        { name = "ItemKitRocketDatalink", prefab = "ItemKitRocketDatalink", req = { Solder = 3, Electrum = 2 }, single_batch = true },
        { name = "ItemKitRocketCircuitHousing", prefab = "ItemKitRocketCircuitHousing", req = { Solder = 3, Electrum = 2 }, single_batch = true },
        { name = "ItemKitRocketCargoStorage", prefab = "ItemKitRocketCargoStorage", req = { Invar = 5, Constantan = 10, Steel = 10 }, single_batch = true },
        { name = "ItemKitRocketMiner", prefab = "ItemKitRocketMiner", req = { Steel = 10, Electrum = 5, Invar = 5, Constantan = 10 }, single_batch = true },
        { name = "ItemKitAccessBridge", prefab = "ItemKitAccessBridge", req = { Copper = 2, Gold = 3, Steel = 10 }, single_batch = true },
        { name = "ItemKitStairwell", prefab = "ItemKitStairwell", req = { Iron = 15 }, single_batch = true },
        { name = "ItemKitRocketScanner", prefab = "ItemKitRocketScanner", req = { Copper = 10, Gold = 10 }, single_batch = true },
        { name = "ItemRocketScanningHead", prefab = "ItemRocketScanningHead", req = { Copper = 3, Gold = 2 }, single_batch = true },
        { name = "ItemRocketDeepScanningHead", prefab = "ItemRocketDeepScanningHead", req = { Copper = 3, Gold = 2 }, single_batch = true },
        { name = "ItemRocketMiningDrillHead", prefab = "ItemRocketMiningDrillHead", req = { Steel = 20 }, single_batch = true },
        { name = "ItemRocketMiningDrillHeadMineral", prefab = "ItemRocketMiningDrillHeadMineral", req = { Steel = 20, Constantan = 10 }, single_batch = true },
        { name = "ItemRocketMiningDrillHeadIce", prefab = "ItemRocketMiningDrillHeadIce", req = { Steel = 20, Electrum = 10 }, single_batch = true },
        { name = "ItemRocketMiningDrillHeadDurable", prefab = "ItemRocketMiningDrillHeadDurable", req = { Steel = 20 }, single_batch = true },
        { name = "ItemRocketMiningDrillHeadLongTerm", prefab = "ItemRocketMiningDrillHeadLongTerm", req = { Steel = 20, Invar = 10 }, single_batch = true },
        { name = "ItemRocketMiningDrillHeadHighSpeedIce", prefab = "ItemRocketMiningDrillHeadHighSpeedIce", req = { Steel = 20, Invar = 10 }, single_batch = true },
        { name = "ItemRocketMiningDrillHeadHighSpeedMineral", prefab = "ItemRocketMiningDrillHeadHighSpeedMineral", req = { Steel = 20, Invar = 10 }, single_batch = true },
        { name = "ItemKitGovernedGasRocketEngine", prefab = "ItemKitGovernedGasRocketEngine", req = { Copper = 10, Gold = 5, Steel = 15 }, single_batch = true },
        { name = "ItemKitPressureFedGasEngine", prefab = "ItemKitPressureFedGasEngine", req = { Steel = 20, Electrum = 5, Invar = 20, Constantan = 10 }, single_batch = true },
        { name = "ItemKitPressureFedLiquidEngine", prefab = "ItemKitPressureFedLiquidEngine", req = { Astroloy = 10, Inconel = 5, Waspaloy = 15 }, single_batch = true },
        { name = "ItemKitPumpedLiquidEngine", prefab = "ItemKitPumpedLiquidEngine", req = { Steel = 15, Electrum = 5, Constantan = 10 }, single_batch = true },
        { name = "ItemKitRocketTransformerSmall", prefab = "ItemKitRocketTransformerSmall", req = { Steel = 10, Electrum = 5 }, single_batch = true },
        { name = "ItemKitRocketAtmospherics", prefab = "ItemKitRocketAtmospherics", req = { Steel = 10, Electrum = 5, Copper = 20 }, single_batch = true },
    },
    -- ===== [5] SECURITY =================
    [5] = {
        { name = "CartridgeAccessController", prefab = "CartridgeAccessController", req = { Iron = 1, Gold = 5, Copper = 5 }, single_batch = true },
        { name = "AccessCardBlack", prefab = "AccessCardBlack", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardBlue", prefab = "AccessCardBlue", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardBrown", prefab = "AccessCardBrown", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardGray", prefab = "AccessCardGray", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardGreen", prefab = "AccessCardGreen", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardKhaki", prefab = "AccessCardKhaki", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardOrange", prefab = "AccessCardOrange", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardPink", prefab = "AccessCardPink", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardPurple", prefab = "AccessCardPurple", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardRed", prefab = "AccessCardRed", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardWhite", prefab = "AccessCardWhite", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "AccessCardYellow", prefab = "AccessCardYellow", req = { Iron = 1, Gold = 1, Copper = 1 }, single_batch = true },
        { name = "ItemExplosive", prefab = "ItemExplosive", req = { Solder = 1, Electrum = 1, Silicon = 3 }, single_batch = true },
        { name = "ItemMiningCharge", prefab = "ItemMiningCharge", req = { Gold = 1, Iron = 1, Silicon = 3 }, single_batch = true },
    },
    -- ===== [6] TOOLS =================
    [6] = {
        { name = "ItemMKIICrowbar", prefab = "ItemMKIICrowbar", req = { Iron = 5, Electrum = 5 }, single_batch = true },
        { name = "ItemMKIIWrench", prefab = "ItemMKIIWrench", req = { Iron = 3, Electrum = 3 }, single_batch = true },
        { name = "ItemMKIIDuctTape", prefab = "ItemMKIIDuctTape", req = { Iron = 2, Electrum = 1 }, single_batch = true },
        { name = "ItemMKIIDrill", prefab = "ItemMKIIDrill", req = { Iron = 5, Copper = 5, Electrum = 5 }, single_batch = true },
        { name = "ItemMKIIScrewdriver", prefab = "ItemMKIIScrewdriver", req = { Iron = 2, Electrum = 2 }, single_batch = true },
        { name = "ItemMKIIArcWelder", prefab = "ItemMKIIArcWelder", req = { Steel = 10, Solder = 10, Electrum = 14, Invar = 5 }, single_batch = true },
        { name = "ItemMKIIAngleGrinder", prefab = "ItemMKIIAngleGrinder", req = { Iron = 3, Copper = 1, Electrum = 4 }, single_batch = true },
        { name = "ItemMKIIWireCutters", prefab = "ItemMKIIWireCutters", req = { Iron = 3, Electrum = 5 }, single_batch = true },
        { name = "ItemMKIIMiningDrill", prefab = "ItemMKIIMiningDrill", req = { Iron = 3, Copper = 2, Electrum = 5 }, single_batch = true },
        { name = "ItemSprayGun", prefab = "ItemSprayGun", req = { Steel = 10, Silicon = 10, Invar = 5 }, single_batch = true },
        { name = "ItemCrowbar", prefab = "ItemCrowbar", req = { Iron = 5 }, single_batch = true },
        { name = "ItemWearLamp", prefab = "ItemWearLamp", req = { Gold = 2, Copper = 2 }, single_batch = true },
        { name = "ItemFlashlight", prefab = "ItemFlashlight", req = { Gold = 2, Copper = 2 }, single_batch = true },
        { name = "ItemDisposableBatteryCharger", prefab = "ItemDisposableBatteryCharger", req = { Iron = 2, Gold = 2, Copper = 5 }, single_batch = true },
        { name = "ItemBeacon", prefab = "ItemBeacon", req = { Iron = 2, Gold = 1, Copper = 2 }, single_batch = true },
        { name = "ItemWrench", prefab = "ItemWrench", req = { Iron = 3 }, single_batch = true },
        { name = "ItemDuctTape", prefab = "ItemDuctTape", req = { Iron = 2 }, single_batch = true },
        { name = "ItemDrill", prefab = "ItemDrill", req = { Iron = 5, Copper = 5 }, single_batch = true },
        { name = "ToyLuna", prefab = "ToyLuna", req = { Iron = 5, Gold = 1 }, single_batch = true },
        { name = "ItemScrewdriver", prefab = "ItemScrewdriver", req = { Iron = 2 }, single_batch = true },
        { name = "ItemArcWelder", prefab = "ItemArcWelder", req = { Steel = 10, Solder = 10, Electrum = 10, Invar = 5 }, single_batch = true },
        { name = "ItemWeldingTorch", prefab = "ItemWeldingTorch", req = { Iron = 3, Copper = 1 }, single_batch = true },
        { name = "ItemAngleGrinder", prefab = "ItemAngleGrinder", req = { Iron = 3, Copper = 1 }, single_batch = true },
        { name = "ItemWireCutters", prefab = "ItemWireCutters", req = { Iron = 3 }, single_batch = true },
        { name = "ItemLabeller", prefab = "ItemLabeller", req = { Iron = 2, Gold = 1 }, single_batch = true },
        { name = "ItemOreDetector", prefab = "ItemOreDetector", req = { Gold = 5, Copper = 5, Solder = 2 }, single_batch = true },
        { name = "ItemRemoteDetonator", prefab = "ItemRemoteDetonator", req = { Steel = 5, Solder = 5, Copper = 5 }, single_batch = true },
        { name = "ItemExplosive", prefab = "ItemExplosive", req = { Solder = 2, Electrum = 1, Silicon = 7 }, single_batch = true },
        { name = "ItemMiningCharge", prefab = "ItemMiningCharge", req = { Gold = 1, Iron = 1, Silicon = 5 }, single_batch = true },
        { name = "ItemMiningDrill", prefab = "ItemMiningDrill", req = { Iron = 3, Copper = 2 }, single_batch = true },
        { name = "ItemMiningDrillPneumatic", prefab = "ItemMiningDrillPneumatic", req = { Steel = 6, Solder = 4, Copper = 4 }, single_batch = true },
        { name = "ItemLiquidVacuum", prefab = "ItemLiquidVacuum", req = { Steel = 10, Solder = 10, Electrum = 5, Invar = 10 }, single_batch = true },
        { name = "ItemMiningDrillHeavy", prefab = "ItemMiningDrillHeavy", req = { Steel = 10, Solder = 10, Electrum = 5, Invar = 10 }, single_batch = true },
        { name = "ItemPickaxe", prefab = "ItemPickaxe", req = { Iron = 2, Copper = 1 }, single_batch = true },
        { name = "ItemMiningBelt", prefab = "ItemMiningBelt", req = { Iron = 3 }, single_batch = true },
        { name = "ItemMiningBeltMKII", prefab = "ItemMiningBeltMKII", req = { Steel = 10, Constantan = 5 }, single_batch = true },
        { name = "ItemMiningBackPack", prefab = "ItemMiningBackPack", req = { Iron = 6 }, single_batch = true },
        { name = "ItemHardMiningBackPack", prefab = "ItemHardMiningBackPack", req = { Steel = 6, Invar = 1 }, single_batch = true },
        { name = "ItemTerrainManipulator", prefab = "ItemTerrainManipulator", req = { Steel = 10, Solder = 5, Electrum = 2, Invar = 1 }, single_batch = true },
        { name = "ItemDirtCanister", prefab = "ItemDirtCanister", req = { Iron = 10, Solder = 2, Electrum = 2 }, single_batch = true },
        { name = "ItemGasMask", prefab = "ItemGasMask", req = { Steel = 2, Silicon = 1 }, single_batch = true },
        { name = "ItemHardHat", prefab = "ItemHardHat", req = { Silicon = 2, Gold = 2, Copper = 2 }, single_batch = true },
        { name = "ItemSpaceHelmet", prefab = "ItemSpaceHelmet", req = { Gold = 2, Copper = 2 }, single_batch = true },
        { name = "ItemIcarusHelmet", prefab = "ItemIcarusHelmet", req = { Gold = 2, Copper = 2 }, single_batch = true },
        { name = "ItemSpacepack", prefab = "ItemSpacepack", req = { Iron = 5, Copper = 2 }, single_batch = true },
        { name = "ItemJetpackBasic", prefab = "ItemJetpackBasic", req = { Gold = 2, Lead = 5, Steel = 10 }, single_batch = true },
        { name = "ItemEvaSuit", prefab = "ItemEvaSuit", req = { Iron = 5, Copper = 2 }, single_batch = true },
        { name = "ItemIcarusSuit", prefab = "ItemIcarusSuit", req = { Iron = 5, Copper = 2 }, single_batch = true },
        { name = "ItemToolBelt", prefab = "ItemToolBelt", req = { Iron = 3 }, single_batch = true },
        { name = "ItemMkIIToolbelt", prefab = "ItemMkIIToolbelt", req = { Iron = 3, Constantan = 5 }, single_batch = true },
        { name = "UniformCommander", prefab = "UniformCommander", req = { Silicon = 25 }, single_batch = true },
        { name = "UniformOrangeJumpSuit", prefab = "UniformOrangeJumpSuit", req = { Silicon = 10 }, single_batch = true },
        { name = "UniformMarine", prefab = "UniformMarine", req = { Silicon = 10 }, single_batch = true },
        { name = "ItemClothingBagOveralls_Aus", prefab = "ItemClothingBagOveralls_Aus", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_Brazil", prefab = "ItemClothingBagOveralls_Brazil", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_Canada", prefab = "ItemClothingBagOveralls_Canada", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_China", prefab = "ItemClothingBagOveralls_China", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_EU", prefab = "ItemClothingBagOveralls_EU", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_France", prefab = "ItemClothingBagOveralls_France", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_Germany", prefab = "ItemClothingBagOveralls_Germany", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_Japan", prefab = "ItemClothingBagOveralls_Japan", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_Korea", prefab = "ItemClothingBagOveralls_Korea", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_NZ", prefab = "ItemClothingBagOveralls_NZ", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_Russia", prefab = "ItemClothingBagOveralls_Russia", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_SouthAfrica", prefab = "ItemClothingBagOveralls_SouthAfrica", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_UK", prefab = "ItemClothingBagOveralls_UK", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_Ukraine", prefab = "ItemClothingBagOveralls_Ukraine", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemClothingBagOveralls_US", prefab = "ItemClothingBagOveralls_US", req = { Silicon = 25 }, single_batch = true },
        { name = "ItemRoadFlare", prefab = "ItemRoadFlare", req = { Iron = 1 }, single_batch = true },
        { name = "FlareGun", prefab = "FlareGun", req = { Iron = 10, Silicon = 10 }, single_batch = true },
        { name = "ItemChemLightBlue", prefab = "ItemChemLightBlue", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemChemLightGreen", prefab = "ItemChemLightGreen", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemChemLightRed", prefab = "ItemChemLightRed", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemChemLightWhite", prefab = "ItemChemLightWhite", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemChemLightYellow", prefab = "ItemChemLightYellow", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemIgniter", prefab = "ItemIgniter", req = { Copper = 3 }, single_batch = true },
        { name = "ItemHardSuit", prefab = "ItemHardSuit", req = { Steel = 20, Astroloy = 10, Stellite = 2 }, single_batch = true },
        { name = "ItemSuitHARM", prefab = "ItemSuitHARM", req = { Steel = 5, Astroloy = 20, Stellite = 20, Hastelloy = 20 }, single_batch = true },
        { name = "ItemSuitHelmetHARM", prefab = "ItemSuitHelmetHARM", req = { Steel = 5, Gold = 5, Astroloy = 5, Stellite = 5 }, single_batch = true },
        { name = "ItemReusableFireExtinguisher", prefab = "ItemReusableFireExtinguisher", req = { Steel = 5 }, single_batch = true },
        { name = "ItemHardsuitHelmet", prefab = "ItemHardsuitHelmet", req = { Steel = 10, Astroloy = 2, Stellite = 2 }, single_batch = true },
        { name = "ItemMarineBodyArmor", prefab = "ItemMarineBodyArmor", req = { Steel = 20, Silicon = 10 }, single_batch = true },
        { name = "ItemMarineHelmet", prefab = "ItemMarineHelmet", req = { Steel = 8, Silicon = 4, Gold = 4 }, single_batch = true },
        { name = "ItemNVG", prefab = "ItemNVG", req = { Hastelloy = 10, Silicon = 5, Steel = 5 }, single_batch = true },
        { name = "ItemSensorLenses", prefab = "ItemSensorLenses", req = { Inconel = 5, Silicon = 5, Steel = 5 }, single_batch = true },
        { name = "ItemSensorProcessingUnitOreScanner", prefab = "ItemSensorProcessingUnitOreScanner", req = { Electrum = 5, Waspaloy = 5, Silicon = 5 }, single_batch = true },
        { name = "ItemSensorProcessingUnitMesonScanner", prefab = "ItemSensorProcessingUnitMesonScanner", req = { Iron = 5, Electrum = 5, Waspaloy = 5, Silicon = 5 }, single_batch = true },
        { name = "ItemSensorProcessingUnitCelestialScanner", prefab = "ItemSensorProcessingUnitCelestialScanner", req = { Iron = 5, Electrum = 5, Waspaloy = 5, Silicon = 5 }, single_batch = true },
        { name = "ItemGlasses", prefab = "ItemGlasses", req = { Silicon = 10, Iron = 15 }, single_batch = true },
        { name = "ItemHardBackpack", prefab = "ItemHardBackpack", req = { Steel = 15, Astroloy = 5, Stellite = 5 }, single_batch = true },
        { name = "ItemHardJetpack", prefab = "ItemHardJetpack", req = { Steel = 20, Astroloy = 8, Stellite = 8, Waspaloy = 8 }, single_batch = true },
        { name = "ItemFlagSmall", prefab = "ItemFlagSmall", req = { Iron = 1 }, single_batch = true },
        { name = "ItemKitDynamicAFrameStripes", prefab = "ItemKitDynamicAFrameStripes", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemKitDynamicAFrameWIP1", prefab = "ItemKitDynamicAFrameWIP1", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemKitDynamicBarrier", prefab = "ItemKitDynamicBarrier", req = { Iron = 1 }, single_batch = true },
        { name = "ItemKitDynamicChannelizer", prefab = "ItemKitDynamicChannelizer", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemKitDynamicWorkCone", prefab = "ItemKitDynamicWorkCone", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemBasketBall", prefab = "ItemBasketBall", req = { Silicon = 1 }, single_batch = true },
        { name = "ItemKitBasket", prefab = "ItemKitBasket", req = { Iron = 5, Copper = 2 }, single_batch = true },
        { name = "ItemPlantSampler", prefab = "ItemPlantSampler", req = { Iron = 5, Copper = 5 }, single_batch = true },
        { name = "ItemSprayCanYellow", prefab = "ItemSprayCanYellow", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanWhite", prefab = "ItemSprayCanWhite", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanRed", prefab = "ItemSprayCanRed", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanPurple", prefab = "ItemSprayCanPurple", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanPink", prefab = "ItemSprayCanPink", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanOrange", prefab = "ItemSprayCanOrange", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanKhaki", prefab = "ItemSprayCanKhaki", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanGrey", prefab = "ItemSprayCanGrey", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanGreen", prefab = "ItemSprayCanGreen", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanBrown", prefab = "ItemSprayCanBrown", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanBlack", prefab = "ItemSprayCanBlack", req = { Iron = 1 }, single_batch = true },
        { name = "ItemSprayCanBlue", prefab = "ItemSprayCanBlue", req = { Iron = 1 }, single_batch = true },
    },

}

local settings_subtab_groups = {
    silo = {
        "silo_iron",
        "silo_copper",
        "silo_gold",
        "silo_silicon",
        "silo_silver",
        "silo_lead",
        "silo_nickel",
        "silo_steel",
        "silo_electrum",
        "silo_solder",
        "silo_constantan",
        "silo_invar",
        "silo_astroloy",
        "silo_hastelloy",
        "silo_stellite",
        "silo_inconel",
        "silo_waspaloy",
    },
    stations = {
        "station_autolathe",
        "sorter_autolathe",
        "station_electronics",
        "sorter_electronics",
        "station_pipebender",
        "sorter_pipebender",
        "station_rocket",
        "sorter_rocket",
        "station_security",
        "sorter_security",
        "station_tools",
        "sorter_tools",
        "stacker_main",
    },
}

local CRAFTS_PER_BATCH = 10


local function current_settings_roles()
    local keys = settings_subtab_groups[settings_subtab] or settings_subtab_groups.other
    local items = {}

    for _, key in ipairs(keys) do
        local role = roles[key]
        if role ~= nil then
            table.insert(items, role)
        end
    end

    return items
end

local function normalize_settings_subtab()
    if settings_subtab == "pas" or settings_subtab == "other" then
        settings_subtab = "silo"
        return
    end

    if settings_subtab ~= "silo"
        and settings_subtab ~= "stations"
        and settings_subtab ~= "control" then
        settings_subtab = "silo"
    end
end

-- ==================== CRAFTING STATION ROUTING ====================

local STATION_SORTER_KEYS = { "sorter_autolathe", "sorter_electronics", "sorter_pipebender", "sorter_rocket", "sorter_security", "sorter_tools" }

local function clear_sorter_memory(device_id)
    if device_id == nil or device_id <= 0 or mem_put_id == nil then return end
    for i = 0, 16 do
        pcall(mem_put_id, device_id, i, 0)
    end
end

local function apply_sorter_instructions(device_id)
    if device_id == nil or device_id <= 0 or mem_put_id == nil then return end
    local slot = 0
    for i = 1, 17 do
        local hash_val = recipe_hashes[i]
        if hash_val then
            local inst = (hash_val * 256) + 1
            pcall(mem_put_id, device_id, slot, inst)
            slot = slot + 1
        end
    end
end

local function route_to_station(station_index)
    for i, key in ipairs(STATION_SORTER_KEYS) do
        local role = roles[key]
        if role_is_bound(role) then
            local device_id = safe_batch_read_name(role.prefab, role.namehash, LT.ReferenceId, LBM.Average)
            if i == station_index then
                safe_batch_write_name(role.prefab, role.namehash, LT.Mode, 1)
                apply_sorter_instructions(device_id)
                log_action(string.format("route_to_station: %s -> Mode 1 (patched)", key))
            else
                safe_batch_write_name(role.prefab, role.namehash, LT.Mode, 0)
                safe_batch_write_name(role.prefab, role.namehash, LT.ClearMemory, 1)
                clear_sorter_memory(device_id)
                log_action(string.format("route_to_station: %s -> Mode 0 (cleared)", key))
            end
        end
    end
end

-- helper: get current recipe entry for the selected station
local function current_craft_entry()
    local recipes = station_recipes[selected_station_index] or {}
    local idx = selected_recipe_per_station[selected_station_index] or 1
    return recipes[idx] or recipes[1]
end

local function selected_output_amount()
    local entry = current_craft_entry()
    if entry and entry.single_batch then
        return requested_amount
    end
    return requested_amount * CRAFTS_PER_BATCH
end

-- helper: build req lines for preview display
local function craft_preview_lines(entry, amount)
    local total_crafts = entry.single_batch and amount or (amount * CRAFTS_PER_BATCH)
    if entry == nil or entry.req == nil then return { "No recipe", "", "" } end
    local parts = {}
    for _, mat in ipairs(CRAFTING_MATERIAL_DISPLAY_ORDER) do
        local count = entry.req[mat]
        if count and count > 0 then
            table.insert(parts, string.format("%s x%g", mat, count * total_crafts))
        end
    end
    if #parts == 0 then return { "No materials", "", "" } end
    local lines = { "", "", "" }
    if #parts == 1 then lines[1] = parts[1]
    elseif #parts == 2 then lines[1] = parts[1]; lines[2] = parts[2]
    elseif #parts == 3 then lines[1] = parts[1]; lines[2] = parts[2]; lines[3] = parts[3]
    else
        lines[1] = parts[1] .. " | " .. parts[2]
        lines[2] = parts[3] .. (parts[4] and (" | " .. parts[4]) or "")
        if parts[5] then lines[3] = parts[5] .. (parts[6] and (" | " .. parts[6]) or "") end
    end
    return lines
end

-- check if all required ingots are available in silos
local function craft_has_stock(entry, amount)
    local total_crafts = entry.single_batch and amount or (amount * CRAFTS_PER_BATCH)
    if entry == nil or entry.req == nil then return false, {} end
    local all_ok = true
    local missing = {}
    for mat, count in pairs(entry.req) do
        local required_grams = count * total_crafts
        local role_key = SILO_ROLES[mat]
        if role_key then
            local role = roles[role_key]
            if role and role_is_bound(role) then
                local current_grams = logic_or_zero(role, LT.Quantity) * ORE_STACK_SIZE
                if current_grams < required_grams then
                    all_ok = false
                    table.insert(missing, string.format("%s %g", mat, required_grams - current_grams))
                end
            else
                all_ok = false
                table.insert(missing, string.format("%s (Unbound)", mat))
            end
        else
            all_ok = false
            table.insert(missing, string.format("%s (No Silo)", mat))
        end
    end
    return all_ok, missing
end

-- start crafting: route sorters then queue silo requests
local function start_craft(entry, amount)
    local total_crafts = entry.single_batch and amount or (amount * CRAFTS_PER_BATCH)
    if entry == nil then return false end
    
    if unload_active and unload_station_index == selected_station_index then
        -- Cancel ongoing unload before starting new craft
        local station_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
        local station_key = station_keys[unload_station_index]
        local role = roles[station_key]
        if role and role_is_bound(role) then
            safe_batch_write_name(role.prefab, role.namehash, LT.Open, 0)
        end
        unload_active = false
        log_action("start_craft: Cancelled active unload for station " .. tostring(unload_station_index))
    end
    
    route_to_station(selected_station_index)
    
    local required_reagents = 0
    -- build silo request items from recipe req
    local items = {}
    for mat, count in pairs(entry.req) do
        local role_key = SILO_ROLES[mat]
        if role_key then
            local required_grams = count * total_crafts
            local drops = math.ceil(required_grams / ORE_STACK_SIZE)
            required_reagents = required_reagents + (drops * ORE_STACK_SIZE)
            table.insert(items, { material = mat, role_key = role_key, remaining = drops })
        end
    end
    if #items == 0 then return false end
    
    local station_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
    local station_key = station_keys[selected_station_index]
    local role = roles[station_key]
    if role and role_is_bound(role) then
        local entry_hash = ic.hash(entry.prefab)
        safe_batch_write_name(role.prefab, role.namehash, LT.ClearMemory, 1)
        safe_batch_write_name(role.prefab, role.namehash, LT.RecipeHash, entry_hash)
        
        local current_r = safe_batch_read_name(role.prefab, role.namehash, LT.Reagents, LBM.Average) or 0
        crafting_target_reagents = current_r + required_reagents
        crafting_recipe_hash = entry_hash
        crafting_wait_reagents = true
    else
        log_action("start_craft: fail, station not bound: " .. station_key)
        return false
    end
    
    -- Configure stacker
    local stacker_role = roles["stacker_main"]
    if stacker_role and role_is_bound(stacker_role) then
        safe_batch_write_name(stacker_role.prefab, stacker_role.namehash, LT.Setting, total_crafts)
    end
    
    crafting_target_amount = total_crafts
    crafting_original_target = total_crafts
    crafting_current_amount = 0
    crafting_run_active = true
    save_crafting_state()
    
    silo_request.active = true
    silo_request.items = items
    silo_request.item_index = 1
    silo_request.phase = 0
    log_action("start_craft: queued " .. #items .. " silo requests for station " .. selected_station_index)
    return true
end

local function process_silo_request_tick()
    if not silo_request.active then
        return
    end

    log_step("process_silo_request_tick: active index=" .. tostring(silo_request.item_index) .. " phase=" .. tostring(silo_request.phase))

    local current = silo_request.items[silo_request.item_index]
    while current ~= nil and (tonumber(current.remaining) or 0) <= 0 do
        silo_request.item_index = silo_request.item_index + 1
        current = silo_request.items[silo_request.item_index]
    end

    if current == nil then
        silo_request.active = false
        silo_request.phase = 0
        log_step("process_silo_request_tick: complete")
        return
    end

    local role = roles[current.role_key]
    if role == nil then
        current.remaining = 0
        log_step("process_silo_request_tick: missing role " .. tostring(current.role_key))
        return
    end

    if silo_request.phase == 0 then
        log_step("process_silo_request_tick: open silo " .. tostring(current.role_key))
        safe_batch_write_name(role.prefab, role.namehash, LT.ClearMemory, 1)
        safe_batch_write_name(role.prefab, role.namehash, LT.Open, 1)
        silo_request.phase = 1
    else
        log_step("process_silo_request_tick: close silo " .. tostring(current.role_key))
        safe_batch_write_name(role.prefab, role.namehash, LT.Open, 0)
        current.remaining = (tonumber(current.remaining) or 0) - 1
        silo_request.phase = 0
        log_step("process_silo_request_tick: remaining=" .. tostring(current.remaining))
    end
end

-- ==================== DEVICE LIST HELPERS ====================

local function build_filtered_device_options(devices, current_role)
    local options = { "Select device..." }
    local candidates = {}
    local selected = 0

    for i, dev in ipairs(devices) do
        if device_matches_prefabs(dev, current_role.allowed_prefabs) then
            local label = tostring((dev and dev.display_name) or ("Device " .. i))
            
            local match_ok = true
            if current_role.name_filter then
                local filter_lower = string.lower(current_role.name_filter)
                local label_lower = string.lower(label)
                if not string.find(label_lower, filter_lower, 1, true) then
                    match_ok = false
                end
            end

            if match_ok then
                label = label:gsub("|", "/")
                table.insert(options, label)
                table.insert(candidates, dev)

                local prefab_hash = tonumber(dev and dev.prefab_hash) or 0
                local name_hash = tonumber(dev and dev.name_hash) or 0
                if (tonumber(current_role.prefab) or 0) ~= 0
                    and (tonumber(current_role.namehash) or 0) ~= 0
                    and prefab_hash == (tonumber(current_role.prefab) or 0)
                    and name_hash == (tonumber(current_role.namehash) or 0) then
                    selected = #candidates
                end
            end
        end
    end

    if #candidates == 0 then
        options[1] = "No devices found"
    end

    return options, candidates, selected
end

-- ==================== CORE LOGIC ====================

local function read_silo_quantity(material)
    local role_key = SILO_ROLES[material]
    if role_key == nil then return 0 end
    local role = roles[role_key]
    if role == nil then return 0 end
    return logic_or_zero(role, LT.Quantity)
end

local function read_silo_ingot_amount(material)
    return read_silo_quantity(material) * ORE_STACK_SIZE
end

local function set_status_visuals()
    if crafting_run_active then
        status_text = "Status: Crafting..."
        status_color = C.accent
        return
    end
    if silo_request.active then
        status_text = "Status: Requesting materials..."
        status_color = C.orange
        return
    end

    local entry = current_craft_entry()
    local ok, missing_materials = craft_has_stock(entry, requested_amount)
    if ok then
        status_text = "Ready"
        status_color = C.green
    else
        status_text = "Missing Materials: " .. table.concat(missing_materials, ", ")
        status_color = C.red
    end
end

local function main_logic_tick(tick_count)
    set_status_visuals()
    
    -- HARDWARE SAFETY BOOT PHASE (Wait 30 ticks before allowing activity)
    if boot_phase_ticks < 30 then
        boot_phase_ticks = boot_phase_ticks + 1
        if boot_phase_ticks % 10 == 0 then
            log_step("main_logic_tick: Boot hardware safety " .. boot_phase_ticks .. "/30")
        end
        for _, role in pairs(roles) do
            if role_is_bound(role) then
                if role.key:find("silo") then
                    safe_batch_write_name(role.prefab, role.namehash, LT.Open, 0)
                elseif role.key:find("station") then
                    safe_batch_write_name(role.prefab, role.namehash, LT.Open, 0)
                    safe_batch_write_name(role.prefab, role.namehash, LT.Activate, 0)
                end
            end
        end
        return -- BLOCK ALL LOGIC
    end
    
    -- Sync ExportCount once when safety phase ends
    if boot_phase_ticks == 30 and crafting_run_active then
        local station_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
        local role = roles[station_keys[selected_station_index]]
        if role and role_is_bound(role) then
            local exp = safe_batch_read_name(role.prefab, role.namehash, LT.ExportCount, LBM.Average)
            if exp ~= nil then 
                crafting_current_amount = exp 
                log_action("Boot Resumption: Synced ExportCount=" .. exp)
            end
        end
        boot_phase_ticks = 31 -- Mark sync as done
    end
    
    if silo_request.active then
        process_silo_request_tick()
    elseif (tick_count % 10 == 0) then
        -- Defensive silo closure
        for _, prefab in ipairs(SILO_PREFABS) do
            safe_batch_write_name(prefab, 0, LT.Open, 0)
        end
    end
    
    if not crafting_run_active and not unload_active and (tick_count % 10 == 0) then
        -- Defensive station closure
        for _, prefab in ipairs(CRAFTING_DEVICES) do
            safe_batch_write_name(prefab, 0, LT.Open, 0)
        end
    end
    
    if crafting_run_active then
        local station_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
        local station_key = station_keys[selected_station_index]
        local role = roles[station_key]
        if role and role_is_bound(role) then
            if crafting_wait_reagents then
                local current_r = safe_batch_read_name(role.prefab, role.namehash, LT.Reagents, LBM.Average) or 0
                if current_r >= crafting_target_reagents then
                    safe_batch_write_name(role.prefab, role.namehash, LT.Activate, 1)
                    crafting_wait_reagents = false
                    save_crafting_state()
                    log_action("Reagents target reached. Activating station.")
                end
            else
                local exp_count = safe_batch_read_name(role.prefab, role.namehash, LT.ExportCount, LBM.Average)
                if exp_count ~= nil then
                    crafting_current_amount = exp_count
                end
                
                if crafting_current_amount >= crafting_target_amount then
                    safe_batch_write_name(role.prefab, role.namehash, LT.Activate, 0)
                    safe_batch_write_name(role.prefab, role.namehash, LT.ClearMemory, 1)
                    crafting_run_active = false
                    log_action("Crafting complete. ExportCount=" .. tostring(exp_count))
                    
                    unload_active = true
                    unload_ticks = 0
                    unload_station_index = selected_station_index
                    save_crafting_state()
                    
                    safe_batch_write_name(role.prefab, role.namehash, LT.Open, 1)
                    log_action("Starting machine unload sequence (30 ticks)...")
                else
                    safe_batch_write_name(role.prefab, role.namehash, LT.RecipeHash, crafting_recipe_hash)
                    safe_batch_write_name(role.prefab, role.namehash, LT.Activate, 1)
                end
            end
        end
    end
    
    
    if unload_active then
        unload_ticks = unload_ticks + 1
        
        local station_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
        
        local station_role = roles[station_keys[unload_station_index]]
        local stacker_role = roles["stacker_main"]
        
        -- Close station door after 10 ticks
        if unload_ticks == 10 then
            if station_role and role_is_bound(station_role) then
                safe_batch_write_name(station_role.prefab, station_role.namehash, LT.Open, 0)
            end
        end
        
        -- Stacker Management
        if stacker_role and role_is_bound(stacker_role) then
            if unload_ticks <= 12 then
                -- Stage 1: Stack finished items at original target size
                safe_batch_write_name(stacker_role.prefab, stacker_role.namehash, LT.Setting, crafting_original_target)
            else
                -- Stage 2: Fast-flush surplus ingots at max stack size
                safe_batch_write_name(stacker_role.prefab, stacker_role.namehash, LT.Setting, 50)
                if unload_ticks % 5 == 0 then
                    safe_batch_write_name(stacker_role.prefab, stacker_role.namehash, LT.Activate, 1)
                end
            end
        end
        
        if unload_ticks >= 30 then
            unload_active = false
            log_action("Unloading complete.")
            
            if stacker_role and role_is_bound(stacker_role) then
                safe_batch_write_name(stacker_role.prefab, stacker_role.namehash, LT.Activate, 0)
            end
            
            if is_batch_running and #crafting_queue > 0 then
                table.remove(crafting_queue, 1)
                save_crafting_state()
            end
            dashboard_render(true)
        end
    end
    
    if is_batch_running and not crafting_run_active and not unload_active and not silo_request.active then
        if #crafting_queue > 0 then
            local next_item = crafting_queue[1]
            local rec = station_recipes[next_item.station] and station_recipes[next_item.station][next_item.recipe_index or 1]
            if rec then
                log_action("Batch queue: starting next item " .. tostring(rec.name))
                selected_station_index = next_item.station
                requested_amount = next_item.amount
                selected_recipe_per_station[next_item.station] = next_item.recipe_index or 1
                start_craft(rec, next_item.amount)
                dashboard_render(true)
            else
                log_action("Batch queue: missing recipe for index " .. tostring(next_item.recipe_index))
                is_batch_running = false
            end
        else
            log_action("Batch queue: all items finished.")
            is_batch_running = false
            save_crafting_state()
            dashboard_render(true)
        end
    end
end

local function handle_power_toggle()
    global_power_on = not global_power_on
    local val = global_power_on and 1 or 0
    for key, role in pairs(roles) do
        if role_is_bound(role) then
            local is_silo = role.key:find("silo")
            if power_target_all or not is_silo then
                safe_batch_write_name(role.prefab, role.namehash, LT.On, val)
            end
        end
    end

    if power_target_all then
        for _, phash in ipairs(SORTER_STACKER) do
            batch_write(phash, LT.On, val)
        end
    end

    save_crafting_state()
    dashboard_render(true)
end

local function set_toggle(id, label, active, x, y, on_click_fn)
    local bg_col = active and C.green or C.bar_bg
    local txt_col = active and C.bg or C.text_dim
    handles.overview[id] = s:element({
        id = id,
        type = "button",
        rect = { unit = "px", x = x, y = y, w = 120, h = 18 },
        props = { text = label },
        style = { bg = bg_col, text = txt_col, font_size = 9, align = "center" },
        on_click = on_click_fn
    })
end

-- ==================== UI RENDER ====================

local function reset_handles()
    handles = { nav = {}, footer = {}, overview = {}, settings = {}, batch = {} }
end


local function render_header()
    local header = s:element({
        id = "header_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 30 },
        style = { bg = C.header }
    })

    header:element({
        id = "line_left",
        type = "line",
        props = { x1 = 10, y1 = 16, x2 = 170, y2 = 16 },
        style = { color = C.accent, thickness = 1 }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 0, y = 6, w = W, h = 20 },
        props = { text = "Crafting Buddy" },
        style = { font_size = 14, color = C.title, align = "center" }
    })

    header:element({
        id = "line_right",
        type = "line",
        props = { x1 = 290, y1 = 16, x2 = W - 10, y2 = 16 },
        style = { color = C.accent, thickness = 1 }
    })
end

local function render_nav_tabs()
    local tabs = {
        { id = "nav_overview", page = "overview", text = "Overview" },
        { id = "nav_batch",    page = "batch",    text = "Batch" },
        { id = "nav_settings", page = "settings", text = "Settings" },
    }
    local tab_gap = 4
    local tab_w = math.floor((W - 10 - tab_gap) / #tabs)
    local total_w = (#tabs * tab_w) + ((#tabs - 1) * tab_gap)
    local start_x = math.floor((W - total_w) / 2)

    for i, tab in ipairs(tabs) do
        local active = (view == tab.page)
        local target = tab.page
        handles.nav[tab.page] = s:element({
            id = tab.id,
            type = "button",
            rect = { unit = "px", x = start_x + (i - 1) * (tab_w + tab_gap), y = 34, w = tab_w, h = 22 },
            props = { text = tab.text },
            style = {
                bg = active and "#6844aa" or "#333344",
                text = "#FFFFFF",
                font_size = 11,
                gradient = active and "#3b1f88" or "#1c1c2e",
                gradient_dir = "vertical"
            },
            on_click = function()
                set_view(target)
            end
        })
    end
end

local function get_batch_requirements()
    local totals = {}
    local missing = {}
    for _, item in ipairs(crafting_queue) do
        local rec = station_recipes[item.station] and station_recipes[item.station][item.recipe_index or 1]
        if rec and rec.req then
            local total_qty = rec.single_batch and item.amount or (item.amount * CRAFTS_PER_BATCH)
            for mat, count in pairs(rec.req) do
                totals[mat] = (totals[mat] or 0) + count * total_qty
            end
        end
    end
    
    local has_missing = false
    for mat, total in pairs(totals) do
        local stock = read_silo_ingot_amount(mat)
        if stock < total then
            missing[mat] = total - stock
            has_missing = true
        end
    end
    return totals, missing, has_missing
end

local function update_nav_dynamic()
    local function set_nav(key)
        if handles.nav[key] == nil then return end
        local active = (view == key)
        handles.nav[key]:set_style({
            bg = active and "#6844aa" or "#333344",
            text = "#FFFFFF",
            font_size = 11,
            gradient = active and "#3b1f88" or "#1c1c2e",
            gradient_dir = "vertical"
        })
    end
    set_nav("overview")
    set_nav("batch")
    set_nav("settings")
end

local function render_batch()
    local center_x = function(w) return math.floor((W - w) / 2) end

    s:element({
        id = "queue_bg",
        type = "panel",
        rect = { unit = "px", x = 10, y = 60, w = W - 20, h = H - 82 },
        style = { bg = C.panel }
    })

    s:element({
        id = "queue_title",
        type = "label",
        rect = { unit = "px", x = 10, y = 70, w = W - 20, h = 14 },
        props = { text = "Multi-Station Crafting Queue" },
        style = { color = C.accent, font_size = 11, align = "center" }
    })

    local reqs, missing, has_missing = get_batch_requirements()
    
    local q_y = 100
    local items_per_page = 15
    local total_pages = math.max(1, math.ceil(#crafting_queue / items_per_page))
    if batch_queue_page > total_pages then batch_queue_page = total_pages end

    local start_idx = (batch_queue_page - 1) * items_per_page + 1
    local end_idx = math.min(#crafting_queue, start_idx + items_per_page - 1)

    for i = start_idx, end_idx do
        local item = crafting_queue[i]
        local item_name = "Unknown"
        local station_name = crafting_stations[item.station] or "Unknown"

        local rec = station_recipes[item.station] and station_recipes[item.station][item.recipe_index or 1]
        if rec then item_name = rec.name end

        local total_qty = rec and (rec.single_batch and item.amount or (item.amount * CRAFTS_PER_BATCH)) or 0
        
        s:element({
            id = "q_item_" .. i,
            type = "label",
            rect = { unit = "px", x = 15, y = q_y, w = 230, h = 10 },
            props = { text = string.format("%d. [%s] %dx %s", i, station_name, total_qty, item_name) },
            style = { color = C.text, font_size = 8, align = "left" }
        })
        s:element({
            id = "q_rem_" .. i,
            type = "button",
            rect = { unit = "px", x = 255, y = q_y, w = 12, h = 10 },
            props = { text = "X" },
            style = { bg = C.red, text = "#FFFFFF", font_size = 7, gradient = "#7F1D1D", gradient_dir = "vertical" },
            on_click = function()
                table.remove(crafting_queue, i)
                save_crafting_state()
                dashboard_render(true)
            end
        })
        q_y = q_y + 12
    end
    
    if total_pages > 1 then
        local p_y = 100 + items_per_page * 12 + 5
        s:element({
            id = "batch_prev", type = "button",
            rect = { unit = "px", x = 15, y = p_y, w = 40, h = 14 },
            props = { text = "<" },
            style = { bg = C.panel_light, text = batch_queue_page > 1 and C.text or C.text_dim, font_size = 9, gradient = "#7F1D1D", gradient_dir = "vertical" },
            on_click = function() if batch_queue_page > 1 then batch_queue_page = batch_queue_page - 1; dashboard_render(true) end end
        })
        s:element({
            id = "batch_lbl", type = "label",
            rect = { unit = "px", x = 65, y = p_y + 2, w = 60, h = 14 },
            props = { text = string.format("Page %d/%d", batch_queue_page, total_pages) },
            style = { color = C.accent, font_size = 9, align = "center" }
        })
        s:element({
            id = "batch_next", type = "button",
            rect = { unit = "px", x = 135, y = p_y, w = 40, h = 14 },
            props = { text = ">" },
            style = { bg = C.panel_light, text = batch_queue_page < total_pages and C.text or C.text_dim, font_size = 9, gradient = "#7F1D1D", gradient_dir = "vertical" },
            on_click = function() if batch_queue_page < total_pages then batch_queue_page = batch_queue_page + 1; dashboard_render(true) end end
        })
    end

    s:element({
        id = "batch_req_title",
        type = "label",
        rect = { unit = "px", x = 290, y = 85, w = 170, h = 12 },
        props = { text = "Total Batch Required Reagents:" },
        style = { color = C.accent, font_size = 9, align = "left" }
    })
    
    local ry = 100
    local req_col = 0
    for _, mat in ipairs(CRAFTING_MATERIAL_DISPLAY_ORDER) do
        if reqs[mat] and reqs[mat] > 0 then
            local rx = 290 + (req_col * 85)
            s:element({
                id = "batch_req_" .. mat,
                type = "label",
                rect = { unit = "px", x = rx, y = ry, w = 80, h = 10 },
                props = { text = string.format("%s: %g", mat, reqs[mat]) },
                style = { color = missing[mat] and C.red or C.text_dim, font_size = 8, align = "left" }
            })
            ry = ry + 12
            if ry > 100 + (items_per_page * 10) then
                ry = 100
                req_col = req_col + 1
            end
        end
    end

    if has_missing then
        s:element({
            id = "batch_missing_title",
            type = "label",
            rect = { unit = "px", x = 330, y = H - 150, w = 170, h = 12 },
            props = { text = "MISSING MATERIALS:" },
            style = { color = C.red, font_size = 9, align = "left" }
        })
        local my = H - 135
        for mat, amt in pairs(missing) do
            s:element({
                id = "batch_miss_" .. mat,
                type = "label",
                rect = { unit = "px", x = 330, y = my, w = 170, h = 10 },
                props = { text = string.format("- %s: %g", mat, amt) },
                style = { color = C.red, font_size = 8, align = "left" }
            })
            my = my + 11
            if my > H - 90 then break end
        end
    end

    s:element({
        id = "nav_batch_status",
        type = "label",
        rect = { unit = "px", x = 10, y = H - 85, w = W - 20, h = 14 },
        props = { text = "Status: " .. (is_batch_running and "Running" or "Idle") },
        style = { color = C.text_dim, font_size = 9, align = "center" }
    })
    
    handles.batch.start_btn = s:element({
        id = "batch_start_stop",
        type = "button",
        rect = { unit = "px", x = center_x(150), y = H - 65, w = 150, h = 22 },
        props = { text = is_batch_running and "Stop Batch Queue" or "Start Batch Queue" },
        style = { bg = is_batch_running and C.red or (has_missing and C.bar_bg or C.green), text = C.bg, font_size = 11, gradient = is_batch_running and "#7F1D1D" or (has_missing and "#1B2433" or "#0f4c63"), gradient_dir = "vertical" },
        on_click = function()
            if is_batch_running then
                is_batch_running = false
            elseif #crafting_queue > 0 then
                local _, _, ok_to_start = get_batch_requirements()
                
                if not ok_to_start then
                    is_batch_running = true
                    if not crafting_run_active and not unload_active then
                        local next_item = crafting_queue[1]
                        local rec = station_recipes[next_item.station] and station_recipes[next_item.station][next_item.recipe_index or 1]
                        if rec then
                            selected_recipe_per_station[next_item.station] = next_item.recipe_index or 1
                            selected_station_index = next_item.station
                            requested_amount = next_item.amount
                            start_craft(rec, next_item.amount)
                        else
                            is_batch_running = false
                        end
                    end
                end
            end
            dashboard_render(true)
        end
    })
end

local function update_batch_dynamic()
    if not handles.batch.start_btn then return end
    local _, _, has_missing = get_batch_requirements()

    handles.batch.start_btn:set_props({ text = is_batch_running and "Stop Batch Queue" or "Start Batch Queue" })
    handles.batch.start_btn:set_style({ 
        bg = is_batch_running and C.red or (has_missing and C.bar_bg or C.green), 
        color = C.bg,
        gradient = is_batch_running and "#7F1D1D" or (has_missing and "#1B2433" or "#0f4c63")
    })
end

local function render_footer()
    local footer = s:element({
        id = "footer_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = H - 18, w = W, h = 18 },
        style = { bg = C.header }
    })

    handles.footer.left = footer:element({
        id = "footer_left",
        type = "label",
        rect = { unit = "px", x = 8, y = 3, w = 120, h = 14 },
        props = { text = "Time: " .. currenttime },
        style = { font_size = 8, color = C.text_muted, align = "left" }
    })

    local toggle_w = 120
    local toggle_x = math.floor((W - toggle_w) / 2)
    local active = global_power_on
    handles.footer.power_toggle = footer:element({
        id = "power_toggle",
        type = "button",
        rect = { unit = "px", x = toggle_x, y = 0, w = toggle_w, h = 18 },
        props = { text = "Power Devices: " .. (active and "ON" or "OFF") },
        style = {
            bg = active and C.green or C.bar_bg,
            text = active and C.bg or C.text_dim,
            font_size = 9,
            align = "center",
            gradient = active and "#0f4c63" or "#182133",
            gradient_dir = "vertical"
        },
        on_click = handle_power_toggle
    })

    handles.footer.right = footer:element({
        id = "footer_right",
        type = "label",
        rect = { unit = "px", x = W - 220, y = 3, w = 212, h = 14 },
        props = { text = string.format("Tick %.0f | Refresh %dt", math.floor(elapsed), LIVE_REFRESH_TICKS) },
        style = { font_size = 8, color = C.text_muted, align = "right" }
    })
end

local function update_footer_dynamic()
    if handles.footer.left ~= nil then
        handles.footer.left:set_props({ text = "Time: " .. currenttime })
    end
    if handles.footer.power_toggle ~= nil then
        local active = global_power_on
        handles.footer.power_toggle:set_props({ text = "Power Devices: " .. (active and "ON" or "OFF") })
        handles.footer.power_toggle:set_style({
            bg = active and C.green or C.bar_bg,
            text = active and C.bg or C.text_dim,
            gradient = active and "#0f4c63" or "#182133"
        })
    end
    if handles.footer.right ~= nil then
        handles.footer.right:set_props({ text = string.format("Tick %.0f | Refresh %dt", math.floor(elapsed), LIVE_REFRESH_TICKS) })
    end
end

local function cancel_crafting()
    crafting_run_active = false
    silo_request.active = false
    is_batch_running = false
    
    local station_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
    local station_key = station_keys[selected_station_index]
    local role = roles[station_key]
    if role and role_is_bound(role) then
        safe_batch_write_name(role.prefab, role.namehash, LT.Activate, 0)
        safe_batch_write_name(role.prefab, role.namehash, LT.ClearMemory, 1)
        safe_batch_write_name(role.prefab, role.namehash, LT.Open, 1)
    end
    
    if #crafting_queue > 0 then
        table.remove(crafting_queue, 1)
    end
    
    unload_active = true
    unload_ticks = 0
    unload_station_index = selected_station_index
    
    save_crafting_state()
    dashboard_render(true)
    log_action("Crafting CANCELLED and UNLOADING.")
end

local function render_overview()

    local left_col_x = 8
    local left_col_w = 220
    local center_x = function(w) return left_col_x + math.floor((left_col_w - w) / 2) end

    if not global_power_on then
        handles.overview.power_warning = s:element({
            id = "power_warning",
            type = "label",
            rect = { unit = "px", x = center_x(300) + 112, y = 200, w = 300, h = 40 },
            props = { text = "WARNING: TURN ON POWER FIRST" },
            style = { color = C.red, font_size = 18, align = "center" }
        })
        return
    end

    local entry = current_craft_entry()
    local recipes_for_station = station_recipes[selected_station_index] or {}
    local total_recipes = #recipes_for_station
    local recipe_idx = math.max(1, selected_recipe_per_station[selected_station_index] or 1)
    local prev_req = craft_preview_lines(entry, requested_amount)
    local can_start = craft_has_stock(entry, requested_amount)

    s:element({
        id = "selector_bg",
        type = "panel",
        rect = { unit = "px", x = left_col_x, y = 60, w = left_col_w, h = H - 82 },
        style = { bg = C.panel }
    })

    local station_btn_w = math.floor((left_col_w - 4) / 3)
    local station_role_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
    local visible_count = 0
    for si, sname in ipairs(crafting_stations) do
        local role_key = station_role_keys[si]
        local bound = role_is_bound(roles[role_key])
        if bound then
            visible_count = visible_count + 1
            local active = (si == selected_station_index)
            local col = (visible_count - 1) % 3
            local row = math.floor((visible_count - 1) / 3)
            local sx = left_col_x + col * (station_btn_w + 2)
            local sy = 62 + (row * 18)
            s:element({
                id = "station_btn_" .. si,
                type = "button",
                rect = { unit = "px", x = sx, y = sy, w = station_btn_w, h = 16 },
                props = { text = sname },
                style = {
                    bg = active and "#6844aa" or "#333344",
                    text = active and "#FFFFFF" or "#AAAAAA",
                    font_size = 8,
                    gradient = active and "#3b1f88" or "#1c1c2e",
                    gradient_dir = "vertical"
                },
                on_click = function()
                    selected_station_index = si
                    route_to_station(si)
                    dashboard_render(true)
                end
            })
        end
    end

    local search_x = center_x(160)
    s:element({
        id = "search_label",
        type = "label",
        rect = { unit = "px", x = search_x, y = 100, w = 160, h = 10 },
        props = { text = "Search Recipe:" },
        style = { color = C.text_dim, font_size = 8, align = "center" }
    })
    s:element({
        id = "search_field",
        type = "textinput",
        rect = { unit = "px", x = search_x, y = 112, w = 140, h = 18 },
        props = { value = recipe_search_query or "", placeholder = "Type to filter..." },
        style = { bg = "#1C1C2E", color = "#FFFFFF", font_size = 9 },
        on_change = function(val) 
            recipe_search_query = val
            show_search_results = (val ~= "")
            dashboard_render(true) 
        end
    })
    s:element({
        id = "search_clear",
        type = "button",
        rect = { unit = "px", x = search_x + 142, y = 112, w = 18, h = 18 },
        props = { text = "X" },
        style = { bg = C.red, text = "#FFFFFF", font_size = 8, gradient = "#7F1D1D", gradient_dir = "vertical" },
        on_click = function()
            recipe_search_query = ""
            show_search_results = false
            dashboard_render(true)
        end
    })


    if handles.overview.icon == nil then
        handles.overview.icon = s:element({
            id = "selector_icon",
            type = "icon",
            rect = { unit = "px", x = center_x(80), y = 135, w = 80, h = 80 },
            props = { name = entry and entry.prefab or "", icon_type = "prefab" },
            style = { tint = "#FFFFFF" },
        })
    end
    if handles.overview.item_name == nil then
        handles.overview.item_name = s:element({
            id = "selector_name",
            type = "label",
            rect = { unit = "px", x = center_x(206), y = 216, w = 206, h = 16 },
            props = { text = entry and entry.name or "" },
            style = { color = C.text, font_size = 11, align = "center" },
        })
    end
    if handles.overview.item_counter == nil then
        handles.overview.item_counter = s:element({
            id = "selector_counter",
            type = "label",
            rect = { unit = "px", x = center_x(206), y = 233, w = 206, h = 13 },
            props = { text = string.format("%d / %d", recipe_idx, total_recipes) },
            style = { color = C.text_dim, font_size = 9, align = "center" },
        })
    end

    local btn_w = 40
    s:element({
        id = "selector_prev",
        type = "button",
        rect = { unit = "px", x = center_x(2 * btn_w + 20), y = 250, w = btn_w, h = 16 },
        props = { text = "<" },
        style = { bg = C.panel_light, text = C.text, font_size = 10, gradient = "#292929ff", gradient_dir = "vertical" },
        on_click = function()
            local n = #(station_recipes[selected_station_index] or {})
            if n > 0 then
                local idx = selected_recipe_per_station[selected_station_index] or 1
                selected_recipe_per_station[selected_station_index] = ((idx - 2) % n) + 1
            end
            dashboard_render(true)
        end
    })
    s:element({
        id = "selector_next",
        type = "button",
        rect = { unit = "px", x = center_x(2 * btn_w + 20) + btn_w + 20, y = 250, w = btn_w, h = 16 },
        props = { text = ">" },
        style = { bg = C.panel_light, text = C.text, font_size = 10, gradient = "#292929ff", gradient_dir = "vertical" },
        on_click = function()
            local n = #(station_recipes[selected_station_index] or {})
            if n > 0 then
                local idx = selected_recipe_per_station[selected_station_index] or 1
                selected_recipe_per_station[selected_station_index] = (idx % n) + 1
            end
            dashboard_render(true)
        end
    })

    s:element({
        id = "preview_label",
        type = "label",
        rect = { unit = "px", x = center_x(204), y = 268, w = 204, h = 12 },
        props = { text = string.format("Required Materials") },
        style = { color = C.text_dim, font_size = 8, align = "center" },
    })
    handles.overview.preview_1 = s:element({
        id = "preview_1",
        type = "label",
        rect = { unit = "px", x = center_x(204), y = 282, w = 204, h = 12 },
        props = { text = prev_req[1] },
        style = { color = C.text, font_size = 8, align = "center" },
    })
    handles.overview.preview_2 = s:element({
        id = "preview_2",
        type = "label",
        rect = { unit = "px", x = center_x(204), y = 296, w = 204, h = 12 },
        props = { text = prev_req[2] },
        style = { color = C.text, font_size = 8, align = "center" },
    })
    handles.overview.preview_3 = s:element({
        id = "preview_3",
        type = "label",
        rect = { unit = "px", x = center_x(204), y = 310, w = 204, h = 12 },
        props = { text = prev_req[3] },
        style = { color = C.text, font_size = 8, align = "center" },
    })

    local batch_label_w = 60
    local batch_value_w = 40
    local batch_total_w = batch_label_w + batch_value_w
    local batch_x = center_x(batch_total_w)
    s:element({
        id = "batch_label",
        type = "label",
        rect = { unit = "px", x = batch_x + 7, y = 340, w = batch_label_w, h = 14 },
        props = { text = "Batch Size:" },
        style = { color = C.text_dim, font_size = 9, align = "right" },
    })
    if handles.overview.batch_value == nil then
        handles.overview.batch_value = s:element({
            id = "batch_value",
            type = "label",
            rect = { unit = "px", x = batch_x + batch_label_w + 13, y = 340, w = batch_value_w, h = 14 },
            props = { text = tostring(requested_amount) },
            style = { color = C.text, font_size = 10, align = "left" },
        })
    end

    local batch_btn_w = 34
    local btn_spacing = 6
    local btns_total_w = (4 * batch_btn_w) + (3 * btn_spacing)
    local btns_x = center_x(btns_total_w)
    
    local btn_y = 360
    s:element({
        id = "batch_dec_5",
        type = "button",
        rect = { unit = "px", x = btns_x, y = btn_y, w = batch_btn_w, h = 18 },
        props = { text = "-5" },
        style = { bg = C.panel_light, text = C.text, font_size = 8, gradient = "#292929ff", gradient_dir = "vertical" },
        on_click = function()
            requested_amount = clamp(requested_amount - 5, MIN_BATCH_AMOUNT, MAX_BATCH_AMOUNT)
            save_crafting_state()
            dashboard_render(true)
        end
    })
    s:element({
        id = "batch_dec",
        type = "button",
        rect = { unit = "px", x = btns_x + (batch_btn_w + btn_spacing), y = btn_y, w = batch_btn_w, h = 18 },
        props = { text = "-1" },
        style = { bg = C.panel_light, text = C.text, font_size = 10, gradient = "#292929ff", gradient_dir = "vertical" },
        on_click = function()
            requested_amount = clamp(requested_amount - 1, MIN_BATCH_AMOUNT, MAX_BATCH_AMOUNT)
            save_crafting_state()
            dashboard_render(true)
        end
    })
    s:element({
        id = "batch_inc",
        type = "button",
        rect = { unit = "px", x = btns_x + 2 * (batch_btn_w + btn_spacing), y = btn_y, w = batch_btn_w, h = 18 },
        props = { text = "+1" },
        style = { bg = C.panel_light, text = C.text, font_size = 10, gradient = "#292929ff", gradient_dir = "vertical" },
        on_click = function()
            requested_amount = clamp(requested_amount + 1, MIN_BATCH_AMOUNT, MAX_BATCH_AMOUNT)
            save_crafting_state()
            dashboard_render(true)
        end
    })
    s:element({
        id = "batch_inc_5",
        type = "button",
        rect = { unit = "px", x = btns_x + 3 * (batch_btn_w + btn_spacing), y = btn_y, w = batch_btn_w, h = 18 },
        props = { text = "+5" },
        style = { bg = C.panel_light, text = C.text, font_size = 8, gradient = "#292929ff", gradient_dir = "vertical" },
        on_click = function()
            requested_amount = clamp(requested_amount + 5, MIN_BATCH_AMOUNT, MAX_BATCH_AMOUNT)
            save_crafting_state()
            dashboard_render(true)
        end
    })

    local output_label_w = 90
    local output_value_w = 40
    local output_total_w = output_label_w + output_value_w
    local output_x = center_x(output_total_w)
    s:element({
        id = "output_label",
        type = "label",
        rect = { unit = "px", x = output_x, y = 385, w = output_label_w, h = 14 },
        props = { text = "Items to craft:" },
        style = { color = C.text_dim, font_size = 9, align = "right" },
    })
    if handles.overview.output_value == nil then
        handles.overview.output_value = s:element({
            id = "output_value",
            type = "label",
            rect = { unit = "px", x = output_x + output_label_w + 6, y = 385, w = output_value_w, h = 14 },
            props = { text = tostring(selected_output_amount()) },
            style = { color = C.accent, font_size = 10, align = "left" },
        })
    end
    local action_y = 405
    local start_btn_w = 150
    local start_bg = C.green
    local start_gradient = "#166534"
    local start_text = C.bg
    local start_label = "Start Crafting"
    if crafting_run_active then
        start_bg = C.red
        start_gradient = "#7F1D1D"
        start_text = "#FFFFFF"
        start_label = "Stop Crafting"
        if crafting_wait_reagents then
            start_label = "Waiting for Materials..."
        else
            start_label = string.format("Crafting... (%d / %d)", crafting_current_amount, crafting_target_amount)
        end
    elseif boot_phase_ticks < 30 then
        start_bg = C.bar_bg
        start_gradient = "#1B2433"
        start_text = C.text_dim
        start_label = "Booting... " .. (30 - boot_phase_ticks)
    elseif not can_start then
        start_bg = C.bar_bg
        start_gradient = "#1B2433"
        start_text = C.text_dim
        start_label = "Missing Materials"
    end
    local bg_q = C.accent; local text_q = C.bg; local grad_q = "#0f4c63"
    handles.overview.add_queue_button = s:element({
        id = "add_queue_button",
        type = "button",
        rect = { unit = "px", x = center_x(190), y = action_y, w = 92, h = 24 },
        props = { text = "Add to Queue" },
        style = { bg = bg_q, text = text_q, font_size = 9, gradient = grad_q, gradient_dir = "vertical" },
        on_click = function()
            local idx = selected_recipe_per_station[selected_station_index] or 1
            local merged = false
            for _, q in ipairs(crafting_queue) do
                if q.recipe_index == idx and q.station == selected_station_index then
                    q.amount = q.amount + requested_amount
                    merged = true
                    break
                end
            end
            if not merged then
                table.insert(crafting_queue, { recipe_index = idx, station = selected_station_index, amount = requested_amount })
            end
            save_crafting_state()
            dashboard_render(true)
        end
    })

    handles.overview.start_button = s:element({
        id = "start_button",
        type = "button",
        rect = { unit = "px", x = center_x(190) + 100, y = action_y, w = 92, h = 24 },
        props = { text = start_label },
        style = {
            bg = start_bg,
            text = start_text,
            font_size = 10,
            gradient = start_gradient,
            gradient_dir = "vertical"
        },
        on_click = function()
            if crafting_run_active then
                crafting_run_active = false
                save_crafting_state()
            else
                local e = current_craft_entry()
                local ok, missing = craft_has_stock(e, requested_amount)
                if ok then
                    start_craft(e, requested_amount)
                end
            end
            dashboard_render(true)
        end
    })




    s:element({
        id = "overview_stats_bg",
        type = "panel",
        rect = { unit = "px", x = 232, y = 60, w = W - 240, h = H - 82 },
        style = { bg = C.panel }
    })

    local x0 = 265
    local stat_label_w = 112
    local stat_gap = 114 - 15
    local function stat_line(id, y, label, value, color)
        if show_search_results then return end
        local label_color = C.text_dim
        if id == "ov_room_press" or id == "ov_room_temp" then
            label_color = C.text_dim
        end
        handles.overview[id .. "_label"] = s:element({
            id = id .. "_label",
            type = "label",
            rect = { unit = "px", x = x0, y = y, w = stat_label_w, h = 14 },
            props = { text = label },
            style = { font_size = 9, color = label_color, align = "left" }
        })
        handles.overview[id] = s:element({
            id = id .. "_value",
            type = "label",
            rect = { unit = "px", x = x0 + stat_gap, y = y, w = 120, h = 14 },
            props = { text = value },
            style = { font_size = 9, color = color or C.text, align = "left" }
        })
    end

    local e = current_craft_entry()
    local ok, missing = craft_has_stock(e, requested_amount)

    if not show_search_results then
        stat_line("ov_stock", 74,  "Materials",      ok and "OK" or "LOW", ok and C.green or C.red)
        stat_line("ov_station", 90, "Station",        crafting_stations[selected_station_index] or "-", C.accent)
        stat_line("ov_boot", 106, "Boot Safety",     boot_phase_ticks < 30 and (30 - boot_phase_ticks .. "t") or "Ready", boot_phase_ticks < 30 and C.orange or C.green)
        
        local comp_text = "Idle"
        local comp_col = C.green
        if crafting_run_active then
            comp_text = "0%"
            comp_col = C.accent
            local station_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
            local station_key = station_keys[selected_station_index]
            local role = roles[station_key]
            if role and role_is_bound(role) then
                local ratio = safe_batch_read_name(role.prefab, role.namehash, LT.CompletionRatio, LBM.Average) or 0
                comp_text = string.format("%d%%", math.floor(ratio * 100))
            end
        elseif unload_active then
            local rem_ticks = math.max(0, 30 - unload_ticks)
            comp_text = string.format("Unload (%dt)", rem_ticks)
            comp_col = C.yellow
        end
        stat_line("ov_completion", 122, "Progress",   comp_text, comp_col)

        if crafting_run_active or silo_request.active or is_batch_running then
            s:element({
                id = "cancel_button",
                type = "button",
                rect = { unit = "px", x = x0 + stat_gap - 50, y = 300, w = 60, h = 14 },
                props = { text = "CANCEL" },
                style = { bg = C.red, text = "#FFFFFF", font_size = 9, gradient = "#7c2222ff", gradient_dir = "vertical" },
                on_click = cancel_crafting
            })
        end

        local req_y = 142
        if not ok and #missing > 0 then
            s:element({ id = "ov_missing_header", type = "label",
                rect = { unit = "px", x = x0, y = req_y, w = 200, h = 10 },
                props = { text = "Selected recipe is missing:" },
                style = { font_size = 8, color = C.red, align = "left" } })
            req_y = req_y + 12
            for i, m_str in ipairs(missing) do
                s:element({ id = "ov_missing_" .. i, type = "label",
                    rect = { unit = "px", x = x0 + 10, y = req_y, w = 210, h = 10 },
                    props = { text = "- " .. m_str },
                    style = { font_size = 8, color = C.red, align = "left" } })
                req_y = req_y + 11
            end
            req_y = req_y + 4
        end

        if e and e.req then
            local total_crafts = e.single_batch and requested_amount or (requested_amount * CRAFTS_PER_BATCH)
            s:element({ id = "ov_silo_header", type = "label",
                rect = { unit = "px", x = x0, y = req_y, w = 200, h = 10 },
                props = { text = "Silo Stock Check - Manual crafting:" },
                style = { font_size = 8, color = C.accent, align = "left" } })
            req_y = req_y + 12
            for _, mat in ipairs(CRAFTING_MATERIAL_DISPLAY_ORDER) do
                local need = e.req[mat]
                if need and need > 0 then
                    local current_grams = read_silo_ingot_amount(mat)
                    local needed_grams = need * total_crafts
                    local col = current_grams >= needed_grams and C.green or C.red
                    handles.overview["ov_silo_" .. mat] = s:element({ id = "ov_silo_" .. mat, type = "label",
                        rect = { unit = "px", x = x0, y = req_y, w = 220, h = 10 },
                        props = { text = string.format("%s: %g / %g", mat, current_grams, needed_grams) },
                        style = { font_size = 8, color = col, align = "left" } })
                    req_y = req_y + 11
                    if req_y > H - 100 then break end
                end
            end
        end
    else

        local query = recipe_search_query:lower()
        local results = {}
        local total_found = 0
        for si, station_recs in ipairs(station_recipes) do
            for ri, rec in ipairs(station_recs) do
                if rec and rec.name and rec.name:lower():find(query, 1, true) then
                    total_found = total_found + 1
                    if #results < 20 then
                        table.insert(results, { name = rec.name, s_idx = si, r_idx = ri })
                    end
                end
            end
        end

        s:element({
            id = "search_count", type = "label",
            rect = { unit = "px", x = x0 + 40, y = H - 65, w = 150, h = 12 },
            props = { text = string.format("%d recipes found", total_found) },
            style = { font_size = 9, color = C.accent, align = "left" }
        })

        if total_found > 20 then
            s:element({
                id = "search_warning", type = "label",
                rect = { unit = "px", x = x0 + 6, y = H - 77, w = 180, h = 12 },
                props = { text = "Specify search - too many results" },
                style = { font_size = 9, color = C.red, align = "left" }
            })
        end

        for i, res in ipairs(results) do
            local sname = crafting_stations[res.s_idx] or "Unknown"
            s:element({
                id = "search_res_" .. i, type = "button",
                rect = { unit = "px", x = x0 - 13, y = 65 + (i-1)*16, w = W - x0 - 15, h = 15 },
                props = { text = string.format("%s (%s)", res.name, sname) },
                style = { bg = C.panel_light, text = "#FFFFFF", font_size = 9, align = "left", gradient = "#292929ff", gradient_dir = "vertical" },
                on_click = function()
                    selected_station_index = res.s_idx
                    selected_recipe_per_station[res.s_idx] = res.r_idx
                    route_to_station(res.s_idx)
                    show_search_results = false
                    recipe_search_query = ""
                    dashboard_render(true)
                end
            })
        end

        s:element({
            id = "search_cancel", type = "button",
            rect = { unit = "px", x = x0 - 13, y = H - 50, w = W - x0 - 15, h = 16 },
            props = { text = "Cancel Search" },
            style = { bg = C.red, text = "#FFFFFF", font_size = 9, gradient = "#7F1D1D", gradient_dir = "vertical" },
            on_click = function()
                show_search_results = false
                recipe_search_query = ""
                dashboard_render(true)
            end
        })
    end

    local silo_x_start = 225
    if not show_search_results then
        local silo_y_base = 275
        local silo_col_w = 95
        local silo_total_w = silo_col_w * 2
        local silo_x_off = x0 - 15
        
        s:element({
            id = "silo_totals_title",
            type = "label",
            rect = { unit = "px", x = silo_x_off, y = silo_y_base + 47, w = silo_total_w, h = 12 },
            props = { text = "Ingot Stock" },
            style = { font_size = 8, color = "#7bbcc6", align = "center" }
        })

        for i, mat in ipairs(MATERIAL_ORDER) do
            local col = (i > 9) and 1 or 0
            local row = (i - 1) % 9
            if i > 17 then break end
            
            local col_x = silo_x_off + (col * silo_col_w) + 10
            local y = silo_y_base + (row * 9) + 60
            local key = SILO_HANDLE_KEY[mat]
            local ingot_amount = read_silo_ingot_amount(mat)

            s:element({
                id = key .. "_label",
                type = "label",
                rect = { unit = "px", x = col_x, y = y, w = 60, h = 9 },
                props = { text = mat },
                style = { font_size = 8, color = C.text_dim, align = "left" }
            })

            if handles.overview[key] == nil then
                handles.overview[key] = s:element({
                    id = key .. "_value",
                    type = "label",
                    rect = { unit = "px", x = col_x + 52, y = y, w = 45, h = 9 },
                    props = { text = fmt(ingot_amount, 0) },
                    style = { font_size = 8, color = stock_amount_color(ingot_amount), align = "left" }
                })
            end
        end
    end
end


local function update_overview_dynamic()

    local function set(id, text, color)
        local h = handles.overview[id]
        if h ~= nil then
            h:set_props({ text = tostring(text) })
            h:set_style({ color = color or C.text })
        end
    end

    local entry = current_craft_entry()
    local preview = craft_preview_lines(entry, requested_amount)
    local can_start, missing_v = craft_has_stock(entry, requested_amount)
    local recipe_idx = selected_recipe_per_station[selected_station_index] or 1
    local total_recipes = #(station_recipes[selected_station_index] or {})

    if handles.overview.icon ~= nil then
        handles.overview.icon:set_props({ name = entry and entry.prefab or "", icon_type = "prefab" })
    end
    if handles.overview.item_name ~= nil then
        handles.overview.item_name:set_props({ text = entry and entry.name or "" })
    end
    if handles.overview.item_counter ~= nil then
        handles.overview.item_counter:set_props({ text = string.format("%d / %d", recipe_idx, total_recipes) })
    end
    if handles.overview.batch_value ~= nil then
        handles.overview.batch_value:set_props({ text = tostring(requested_amount) })
    end
    if handles.overview.output_value ~= nil then
        handles.overview.output_value:set_props({ text = tostring(selected_output_amount()) })
    end
    if handles.overview.preview_1 ~= nil then
        handles.overview.preview_1:set_props({ text = preview[1] })
    end
    if handles.overview.preview_2 ~= nil then
        handles.overview.preview_2:set_props({ text = preview[2] })
    end
    if handles.overview.preview_3 ~= nil then
        handles.overview.preview_3:set_props({ text = preview[3] })
    end
    if handles.overview.start_button ~= nil then
        local start_bg = C.green
        local start_gradient = "#166534"
        local start_text = C.bg
        local start_label = "Start Crafting"
        if crafting_run_active then
            start_bg = C.red
            start_gradient = "#7F1D1D"
            start_text = "#FFFFFF"
            start_label = "Stop Crafting"
            if crafting_wait_reagents then
                start_label = "Waiting for Materials..."
            else
                start_label = string.format("Crafting... (%d / %d)", crafting_current_amount, crafting_target_amount)
            end
        elseif boot_phase_ticks < 30 then
            start_bg = C.bar_bg
            start_gradient = "#1B2433"
            start_text = C.text_dim
            start_label = "Booting... " .. (30 - boot_phase_ticks)
        elseif unload_active and unload_station_index == selected_station_index then
            start_bg = C.orange
            start_gradient = "#C2410C"
            start_text = C.bg
            start_label = "Unloading Leftovers..."
        elseif not can_start then
            start_bg = C.bar_bg
            start_gradient = "#1B2433"
            start_text = C.text_dim
            start_label = "Missing Materials"
        end

        handles.overview.start_button:set_props({ text = start_label })
        handles.overview.start_button:set_style({
            bg = start_bg,
            text = start_text,
            font_size = 10,
            gradient = start_gradient,
            gradient_dir = "vertical"
        })
    end

    set("ov_stock", can_start and "OK" or "LOW", can_start and C.green or C.red)
    set("ov_station", crafting_stations[selected_station_index] or "-", C.accent)

    if not can_start then
        for i = 1, 3 do
            local h = handles.overview["preview_" .. i]
            if h then
                local m = missing_v[i]
                h:set_props({ text = m and ("- " .. m) or "" })
                h:set_style({ color = C.red })
            end
        end
    end

    for _, mat in ipairs(CRAFTING_MATERIAL_DISPLAY_ORDER) do
        local h = handles.overview["ov_silo_" .. mat]
        if h then
            local need = entry and entry.req and entry.req[mat]
            if need then
                local total_crafts = entry.single_batch and requested_amount or (requested_amount * CRAFTS_PER_BATCH)
                local current_grams = read_silo_ingot_amount(mat)
                local needed_grams = need * total_crafts
                local col = current_grams >= needed_grams and C.green or C.red
                h:set_props({ text = string.format("%s: %g / %g", mat, current_grams, needed_grams) })
                h:set_style({ color = col })
            end
        end
    end

    local boot_text = "Ready"
    local boot_color = C.green
    local completion_text = "Idle"
    local completion_color = C.green

    if boot_phase_ticks < 30 then
        boot_text = (30 - boot_phase_ticks) .. " t"
        boot_color = C.orange
        completion_text = "Initialize"
        completion_color = C.text_dim
    elseif crafting_run_active then
        completion_text = "0%"
        completion_color = C.accent
        local station_keys = { "station_autolathe", "station_electronics", "station_pipebender", "station_rocket", "station_security", "station_tools" }
        local station_key = station_keys[selected_station_index]
        local role = roles[station_key]
        if role and role_is_bound(role) then
            local ratio = safe_batch_read_name(role.prefab, role.namehash, LT.CompletionRatio, LBM.Average) or 0
            completion_text = string.format("%d%%", math.floor(ratio * 100))
        end
    elseif unload_active then
        local rem_ticks = math.max(0, 30 - unload_ticks)
        completion_text = string.format("Unload (%dt)", rem_ticks)
        completion_color = C.yellow
    end

    set("ov_boot", boot_text, boot_color)
    set("ov_completion", completion_text, completion_color)

    for _, mat in ipairs(MATERIAL_ORDER) do
        local key = SILO_HANDLE_KEY[mat]
        local h = handles.overview[key]
        if h ~= nil then
            local ingot_amount = read_silo_ingot_amount(mat)
            h:set_props({ text = fmt(ingot_amount, 0) })
            h:set_style({ font_size = 8, color = stock_amount_color(ingot_amount), align = "left" })
        end
    end
end


local function update_settings_dynamic()
    return
end

local function render_settings()
    local panel_x, panel_y = 8, 60
    local panel_w, panel_h = W - 16, H - 82
    local tab_y = panel_y + 8

    s:element({
        id = "settings_bg",
        type = "panel",
        rect = { unit = "px", x = panel_x, y = panel_y, w = panel_w, h = panel_h },
        style = { bg = "#0A0A15" }
    })

    local subtabs = {
        { id = "settings_silo",     text = "SILOS",     key = "silo" },
        { id = "settings_stations", text = "STATIONS", key = "stations" },
        { id = "settings_control",  text = "CONTROL",  key = "control" },
    }

    local settings_tab_count = #subtabs
    local settings_button_w = math.floor((panel_w - 18) / settings_tab_count)

    for i, tab in ipairs(subtabs) do
        local active = (settings_subtab == tab.key)
        local target = tab.key
        s:element({
            id = tab.id,
            type = "button",
            rect = { unit = "px", x = panel_x + 6 + (i - 1) * settings_button_w, y = tab_y, w = settings_button_w - 2, h = 20 },
            props = { text = tab.text },
            style = {
                bg = active and C.accent or C.panel_light,
                text = active and C.bg or C.text,
                font_size = 8,
                gradient = active and "#0f4c63" or "#182133",
                gradient_dir = "vertical"
            },
            on_click = function()
                settings_subtab = target
                settings_device_page = 1
                settings_cache_dirty = true
                dashboard_render(true)
            end
        })
    end

    local content_y = tab_y + 30

    if settings_subtab ~= "control" then
        local grouped_roles = current_settings_roles()

        local y = content_y + 18
        local items_per_page = 12
        local total_pages = math.ceil(#grouped_roles / items_per_page)
        local start_idx = (settings_device_page - 1) * items_per_page + 1
        local end_idx = math.min(#grouped_roles, start_idx + items_per_page - 1)

        for i = start_idx, end_idx do
            local role = grouped_roles[i]
            local def = role ~= nil and role_defs[role.index] or nil
            local cache = cached_role_dropdowns[def.key] or { opts = { "Select device..." }, cands = {}, sel = 0 }
            local options, candidates, selected_idx = cache.opts, cache.cands, cache.sel
            local row_candidates = candidates
            settings_dropdown_selected[def.key] = selected_idx

            s:element({
                id = "dev_label_" .. def.key,
                type = "label",
                rect = { unit = "px", x = panel_x + 14, y = y + 2, w = 125, h = 14 },
                props = { text = role.label },
                style = { font_size = 8, color = C.text, align = "left" }
            })

            s:element({
                id = "dev_select_" .. def.key,
                type = "select",
                rect = { unit = "px", x = panel_x + 131, y = y, w = 300, h = 20 },
                props = {
                    options = table.concat(options, "|"),
                    selected = settings_dropdown_selected[def.key],
                    open = settings_dropdown_open[def.key],
                },
                on_toggle = function()
                    local opening = settings_dropdown_open[def.key] ~= "true"
                    if opening then
                        local devs = device_list_safe()
                        local opts, cands, sel = build_filtered_device_options(devs, role)
                        cached_role_dropdowns[def.key] = { opts = opts, cands = cands, sel = sel }
                    end
                    settings_dropdown_open[def.key] = opening and "true" or "false"
                    dashboard_render(true)
                end,
                on_change = function(optionIndex)
                    local selected_option = tonumber(optionIndex) or 0
                    settings_dropdown_selected[def.key] = selected_option
                    settings_dropdown_open[def.key] = "false"

                    if selected_option == 0 then
                        role.prefab = 0
                        role.namehash = 0
                    else
                        local picked = row_candidates[selected_option]
                        if picked ~= nil then
                            role.prefab = tonumber(picked.prefab_hash) or 0
                            role.namehash = tonumber(picked.name_hash) or 0
                        end
                    end

                    save_role_to_memory(role)
                    if cached_role_dropdowns[def.key] then
                        cached_role_dropdowns[def.key].sel = selected_option
                    end
                    dashboard_render(true)
                end
            })

            y = y + 22
        end

        if total_pages > 1 then
            local page_y = y + 5
            s:element({
                id = "settings_prev_page",
                type = "button",
                rect = { unit = "px", x = panel_x + 14, y = page_y, w = 60, h = 18 },
                props = { text = "< Prev" },
                style = { bg = C.panel_light, text = settings_device_page > 1 and C.text or C.text_dim, font_size = 9, gradient = "#292929ff", gradient_dir = "vertical" },
                on_click = function()
                    if settings_device_page > 1 then
                        settings_device_page = settings_device_page - 1
                        dashboard_render(true)
                    end
                end
            })
            
            s:element({
                id = "settings_page_label",
                type = "label",
                rect = { unit = "px", x = panel_x + 84, y = page_y + 2, w = 150, h = 14 },
                props = { text = "Page " .. settings_device_page .. " / " .. total_pages },
                style = { font_size = 9, color = C.accent, align = "center" }
            })

            s:element({
                id = "settings_next_page",
                type = "button",
                rect = { unit = "px", x = panel_x + 244, y = page_y, w = 60, h = 18 },
                props = { text = "Next >" },
                style = { bg = C.panel_light, text = settings_device_page < total_pages and C.text or C.text_dim, font_size = 9, gradient = "#292929ff", gradient_dir = "vertical" },
                on_click = function()
                    if settings_device_page < total_pages then
                        settings_device_page = settings_device_page + 1
                        dashboard_render(true)
                    end
                end
            })
        end

        return
    end

    local function row(label, value, y, on_change)
        s:element({
            id = "ctl_label_" .. label,
            type = "label",
            rect = { unit = "px", x = panel_x + 18, y = y + 2, w = 190, h = 16 },
            props = { text = label },
            style = { font_size = 9, color = C.text, align = "left" }
        })
        s:element({
            id = "ctl_input_" .. label,
            type = "textinput",
            rect = { unit = "px", x = panel_x + 212, y = y, w = 110, h = 20 },
            props = { value = value, placeholder = value },
            on_change = on_change
        })
    end

    s:element({
        id = "control_title",
        type = "label",
        rect = { unit = "px", x = panel_x + 14, y = content_y, w = panel_w - 28, h = 14 },
        props = { text = "Runtime Controls" },
        style = { font_size = 10, color = C.accent, align = "left" }
    })

    local y = content_y + 22
    row("Refresh Ticks (UI)", ui_live_refresh, y, function(v)
        LIVE_REFRESH_TICKS = to_number_or(v, LIVE_REFRESH_TICKS)
        save_crafting_state()
    end)
    
    y = y + 22
    local label = power_target_all and "All Devices" or "Crafting Devices Only"
    s:element({
        id = "row_power_target_lbl",
        type = "label",
        rect = { unit = "px", x = panel_x + 14, y = y + 2, w = 125, h = 14 },
        props = { text = "Power Target" },
        style = { font_size = 8, color = C.text, align = "left" }
    })
    s:element({
        id = "row_power_target_btn",
        type = "button",
        rect = { unit = "px", x = panel_x + 131, y = y, w = 240, h = 18 },
        props = { text = label },
        style = { bg = C.panel_light, text = C.text, font_size = 9, gradient = "#292929ff", gradient_dir = "vertical" },
        on_click = function()
            power_target_all = not power_target_all
            save_crafting_state()
            dashboard_render(true)
        end
    })
end

-- ==================== RENDER ENTRY ====================

dashboard_render = function(force_rebuild)
    log_ui("dashboard_render: begin")
    if force_rebuild == nil then force_rebuild = true end

    local desired = view or "overview"
    if surfaces[desired] == nil then desired = "overview" end
    s = surfaces[desired]

    if force_rebuild or handles.view ~= desired then
        s:clear()
        reset_handles()

        s:element({
            id = "bg",
            type = "panel",
            rect = { unit = "px", x = 0, y = 0, w = W, h = H },
            style = { bg = C.bg }
        })

        render_header()
        render_nav_tabs()

        if desired == "overview" then
            render_overview()
        elseif desired == "batch" then
            render_batch()
        else
            render_settings()
        end

        render_footer()
        handles.view = desired
        ss.ui.activate(desired)
        s:commit()
        log_ui("dashboard_render: full rebuild commit")
        return
    end

    update_nav_dynamic()
    update_footer_dynamic()
    if desired == "overview" then
        update_overview_dynamic()
    elseif desired == "batch" then
        update_batch_dynamic()
    elseif desired == "settings" then
        update_settings_dynamic()
    end

    ss.ui.activate(desired)
    s:commit()
    log_ui("dashboard_render: incremental commit")
end

set_view = function(name)
    local desired = name or "overview"
    if surfaces[desired] == nil then desired = "overview" end
    view = desired
    s = surfaces[desired]
    ss.ui.activate(desired)
    log_ui("set_view: " .. tostring(desired))
    safe_call("set_view dashboard_render", function()
        dashboard_render(true)
    end)
end

-- ==================== SERIALIZATION ====================

function serialize()
    log_step("serialize: begin")
    local state = {
        view = view,
        settings_subtab = settings_subtab,
        settings_device_page = settings_device_page,
        crafting_run_active = crafting_run_active,
        crafting_target_amount = crafting_target_amount,
        crafting_current_amount = crafting_current_amount,
        crafting_wait_reagents = crafting_wait_reagents,
        crafting_target_reagents = crafting_target_reagents,
        crafting_original_target = crafting_original_target,
        crafting_queue = crafting_queue,
        is_batch_running = is_batch_running,
        unload_active = unload_active,
        unload_ticks = unload_ticks,
        unload_station_index = unload_station_index,
        silo_request = silo_request,
    }
    local ok, json = pcall(util.json.encode, state)
    if not ok then return nil end
    log_step("serialize: success")
    return json
end

function deserialize(blob)
    log_step("deserialize: begin")
    if type(blob) ~= "string" or blob == "" then return end
    local ok, decoded = pcall(util.json.decode, blob)
    if not ok or type(decoded) ~= "table" then return end

    if type(decoded.view) == "string" then view = decoded.view end
    if type(decoded.settings_subtab) == "string" then settings_subtab = decoded.settings_subtab end
    settings_device_page = to_number_or(decoded.settings_device_page, settings_device_page)
    crafting_run_active = decoded.crafting_run_active and true or false
    crafting_target_amount = to_number_or(decoded.crafting_target_amount, 0)
    crafting_current_amount = to_number_or(decoded.crafting_current_amount, 0)
    crafting_wait_reagents = decoded.crafting_wait_reagents and true or false
    crafting_target_reagents = to_number_or(decoded.crafting_target_reagents, 0)
    crafting_original_target = to_number_or(decoded.crafting_original_target, 0)
    if type(decoded.crafting_queue) == "table" then crafting_queue = decoded.crafting_queue end
    is_batch_running = (decoded.is_batch_running == true)
    unload_active = (decoded.unload_active == true)
    unload_ticks = to_number_or(decoded.unload_ticks, 0)
    unload_station_index = to_number_or(decoded.unload_station_index, 1)
    if type(decoded.silo_request) == "table" then silo_request = decoded.silo_request end
    normalize_settings_subtab()
    log_step("deserialize: applied saved state")
end

-- ==================== BOOT ====================

load_roles_from_memory()
local boot_devs = device_list_safe()
for _, def in ipairs(role_defs) do
    local role = roles[def.key]
    if role ~= nil and role_is_bound(role) then
        local label = nil
        for _, dev in ipairs(boot_devs) do
            if (tonumber(dev.prefab_hash) or 0) == (tonumber(role.prefab) or 0)
                and (tonumber(dev.name_hash) or 0) == (tonumber(role.namehash) or 0) then
                label = tostring(dev.display_name or "")
                break
            end
        end
        if label == nil or label == "" then
            label = resolve_name_hash(role.namehash)
        end
        cached_role_dropdowns[def.key] = { opts = { "Select device...", label }, cands = {}, sel = 1 }
    end
end
load_crafting_state()
normalize_settings_subtab()

if global_power_on then
    log_step("boot: performing initial device power sync")
    for _, role in pairs(roles) do
        if role_is_bound(role) then
            safe_batch_write_name(role.prefab, role.namehash, LT.On, 1)
        end
    end
end

log_step("boot: performing initial role-based hardware reset")
for _, role in pairs(roles) do
    if role_is_bound(role) and (role.key:find("silo") or role.key:find("station")) then
        safe_batch_write_name(role.prefab, role.namehash, LT.Open, 0)
    end
end

log_step("boot: initialization complete")
safe_call("boot set_view", function()
    set_view(view)
end)

-- ==================== MAIN LOOP ====================

local tick = 0
while true do
    tick = tick + 1
    elapsed = elapsed + 1
    currenttime = util.clock_time()

    safe_call("main_logic_tick", function()
        main_logic_tick(tick)
    end)

    if tick % LIVE_REFRESH_TICKS == 0 then
        log_ui("loop: dashboard refresh")
        safe_call("loop dashboard_render", function()
            dashboard_render(false)
        end)
    end

    ic.yield()
end
