Config = {}

-- Language: set it in server.cfg with   setr ox:locale ja   (default: en)
-- Available: locales/en.json, locales/ja.json  (copy en.json to add your own)

-- ■ General ---------------------------------------------------------------
Config.Command          = 'tv'          -- /tv opens the nearest TV
Config.BroadcastCommand = 'broadcast'   -- /broadcast opens the broadcast manager anywhere (nil = disabled)
Config.UseOxTarget      = true          -- use ox_target on TVs / boomboxes (falls back to key + TextUI when ox_target is not running)
Config.TargetDistance   = 5.0           -- ox_target distance for TVs (m)
Config.InteractKey      = 'E'           -- default key for the ox_lib keybind (fallback mode); players can rebind it
Config.InteractDistance = 4.0           -- fallback mode interaction distance (m)
Config.NotifyPosition   = 'top-right'   -- ox_lib notification position
Config.RenderDistance   = 20.0          -- draw the screen within this distance (m). Per-model `Range` overrides it
Config.MaxScreens       = 4             -- how many TV screens can be drawn at once
Config.DuiWidth         = 1280          -- screen resolution
Config.DuiHeight        = 720

-- ■ UI --------------------------------------------------------------------
Config.UI = {
    Side = 'right',   -- reserved for panel-style layouts ('right' / 'left')
}

-- Window used by "Interact" (mouse control of the screen). The game stays visible around it.
Config.BrowseWindow = {
    Width   = 0.70,    -- window width relative to the screen width (0.3 - 0.95). Height follows 16:9
    CenterY = 0.45,    -- vertical center (0.0 = top, 1.0 = bottom)
    HideHud = true,    -- hide the HUD / radar while interacting (the window is drawn on the top layer)
}
Config.InvertScroll = false   -- set to true if the mouse wheel scrolls the wrong way

-- ■ Volume ----------------------------------------------------------------
Config.DefaultVolume     = 50     -- 0-100. Each player can change it in the UI (only affects themselves)
Config.AudioFullDistance = 3.0    -- full volume up to this distance, then fades to the model's Range

-- Sound is muffled by walls / floors of the map
Config.Occlusion = {
    Enabled    = true,
    WallFactor = 0.45,   -- volume multiplier per wall (smaller = muffled more)
    MaxWalls   = 3,      -- max number of walls counted
    MinFactor  = 0.06,   -- minimum multiplier when blocked

    -- Completely silent when the source is in a sealed space:
    -- the player and the source are in different interiors and at least one wall is between them.
    SilentWhenSealed = true,
    -- Silent when this many walls (or more) are in between, regardless of interiors (0 / nil = disabled)
    SilentWalls = 0,
}

-- ■ NO SIGNAL screen ------------------------------------------------------
Config.ShowNoSignal     = true    -- show a "NO SIGNAL" screen on TVs that are not playing anything
Config.NoSignalDistance = 8.0     -- ...within this distance (m)

-- ■ Permissions (ACE) -----------------------------------------------------
-- nil = everyone is allowed
Config.PlayAce      = nil                             -- who can play on TVs
Config.BroadcastAce = 'rensyu_television.broadcast'   -- who can broadcast to channels
-- server.cfg:  add_ace group.admin rensyu_television.broadcast allow

Config.ActionCooldown  = 1500    -- anti-spam for actions (ms)
Config.ControlCooldown = 300     -- anti-spam for pause / seek (ms)
Config.SeekSeconds     = 10      -- seconds for rewind / forward
Config.MaxUrlLength    = 512
Config.MaxTVStates     = 300     -- max number of TVs the server remembers

Config.BlockedHosts = {}              -- e.g. { 'example.com' }
Config.BannedWords  = { 'google' }    -- URLs containing these strings are rejected (lowercase)

-- ■ Approval hooks (return false to deny) ---------------------------------
Config.Hooks = {
    -- Playing on one TV (key = TV identifier)
    ScreenInteract = function(source, key, media)
        return true
    end,
    -- Broadcasting to a channel (channelId is 'new' when a player opens their own channel)
    Broadcast = function(source, channelId, media)
        return true
    end,
    -- Playing on a boombox
    Boombox = function(source, id, media)
        return true
    end,
}

-- ■ BOOMBOX (ox_inventory item) --------------------------------------------
-- Add the item from install/ox_inventory_items.lua to ox_inventory's data/items.lua.
-- Using the item places a prop in front of the player; picking it up gives the item back.
Config.Boombox = {
    Enabled          = true,
    Item             = 'boombox',          -- ox_inventory item name
    Model            = 'prop_boombox_01',  -- prop to place
    Range            = 25.0,               -- how far the sound reaches (m)
    MaxActive        = 3,                  -- how many boomboxes can play at once (nearest first)
    MaxPerPlayer     = 1,                  -- how many a player can have placed
    InteractDistance = 4.0,                -- ox_target / key distance (m)
    PlaceDistance    = 0.9,                -- placement distance in front of the player (m)
    HeadingOffset    = 180.0,              -- rotate the prop if it faces the wrong way
    PlayAce          = nil,                -- who can play (nil = everyone)
    PickupAnyone     = true,               -- true: anyone can pick it up / false: only the owner
    -- Animation played while the boombox panel is open (false = disabled). Change dict / clip to taste.
    Animation        = { dict = 'mini@repair', clip = 'fixing_a_player', flag = 1 },
}

-- ■ Page titles (shown in the history, status and channel lists) -------------
-- The server looks titles up: YouTube via oEmbed, Twitch / media files from the URL,
-- other web pages by reading their <title>. Results are cached on the server.
Config.Titles = {
    Enabled   = true,
    FetchWeb  = true,    -- also read <title> of ordinary web pages (the server makes an HTTP request to the URL)
    MaxLength = 100,
}

-- ■ YouTube language ------------------------------------------------------
Config.YouTube = {
    Language = 'auto',           -- 'auto' = follow ox:locale, or a code such as 'ja' / 'en'. nil = no preference
    Captions = false,            -- false: always hide captions (avoids unwanted auto-captions)
    PreferAudioLanguage = true,  -- pick the audio track of that language when a video has several (unofficial; may not work)
}

-- ■ Twitch ----------------------------------------------------------------
-- The player page's own host name is added as `parent` automatically.
-- If Twitch does not load, add more parents here.
Config.TwitchParents = { 'localhost' }

-- ■ Channels --------------------------------------------------------------
-- Channels with a `url` are FIXED (nobody can overwrite them).
-- Channels without a `url` can be used by players with broadcast permission.
-- Players with broadcast permission can also open their own channel (closed when they leave).
Config.Channels = {
    { id = 'twitch', label = 'Twitch Official', url = 'https://www.twitch.tv/twitch' },
    { id = 'main',   label = 'Main Channel' },
    { id = 'sub',    label = 'Sub Channel' },
}

-- ■ Presets (one-click entries in the UI) ---------------------------------
Config.Presets = {
    { label = 'Lofi Girl (YouTube Live)', url = 'https://www.youtube.com/watch?v=jfKfPfyJRdk', type = 'auto' },
    { label = 'Twitch Official', url = 'https://www.twitch.tv/twitch', type = 'auto' },
}

-- ■ Supported TV models ----------------------------------------------------
-- Style 1)  [model] = 'render target name'
--   GTA V shares one screen between all models with the same render target name:
--   only the last-used / nearest TV is drawn, others of the same model look the same.
--
-- Style 2)  [model] = { Target = nil, Range = 20.0, Scale = 0.085, Offset = vector3(x, y, z) }
--   With Target = nil the screen is drawn in 3D at the given Offset / Scale, so every TV of that
--   model can show a different picture. Offset / Scale must be tuned per model.
Config.TVModels = {
    prop_tv_flat_01         = 'tvscreen',
    prop_tv_flat_01_screen  = 'tvscreen',
    prop_tv_flat_02         = 'tvscreen',
    prop_tv_flat_02b        = 'tvscreen',
    prop_tv_flat_03         = 'tvscreen',
    prop_tv_flat_03b        = 'tvscreen',
    prop_tv_flat_michael    = 'tvscreen',
    prop_flatscreen_overlay = 'tvscreen',
    prop_trev_tv_01         = 'tvscreen',
    prop_tv_02              = 'tvscreen',
    prop_tv_03              = 'tvscreen',
    prop_tv_03_overlay      = 'tvscreen',
    prop_tv_06              = 'tvscreen',
    prop_monitor_02         = 'tvscreen',
    prop_monitor_w_large    = 'tvscreen',
    prop_laptop_lester2     = 'tvscreen',
    des_tvsmash_start       = 'tvscreen',

    -- Untested guesses (adjust the render target name if nothing shows)
    prop_tv_01              = 'tvscreen',
    prop_tv_04              = 'tvscreen',
    prop_tv_05              = 'tvscreen',
    prop_tv_07              = 'tvscreen',
    prop_tv_cabinet_03      = 'tvscreen',
    prop_tv_cabinet_04      = 'tvscreen',
    prop_tv_cabinet_05      = 'tvscreen',
    ex_prop_ex_tv_flat_01   = 'ex_tvscreen',

    -- 3D mode example (one picture per TV; values need tuning)
    -- prop_example_tv = { Target = nil, Range = 15.0, Scale = 0.085, Offset = vector3(0.0, -0.05, 0.5) },

    -- Missing a TV? Stand next to it and run /tvmodel, look the printed hash up and add the model here.
}

-- ■ Extra TVs placed by this script ---------------------------------------
-- (TVs that already exist on the map need no configuration.)
-- Spawned when you get close, removed when you leave (OneSync recommended).
Config.TVs = {
    -- { id = 'lobby', label = 'Lobby TV', model = 'prop_tv_flat_01',
    --   coords = vector3(144.30, -1037.46, 29.41), heading = 70.0 },
}
Config.SpawnDistance = 60.0
