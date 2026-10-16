local Boomboxes = {}  -- [id] = { id, owner, coords, heading, media }
local Channels = {}   -- [id] = { id, label, num, media, owner, fixed }
local TVs = {}        -- [tvKey] = { mode = 'media', media } | { mode = 'channel', channel = id }
local LastAction = {}
local LastControl = {}
local seqCounter = 0

-- ■ ユーティリティ ----------------------------------------------------
-- ox_lib の通知。文頭の ~r~ ~g~ ~y~ は通知の種類(エラー/成功/警告)に変換する
local function notify(src, msg)
    local ntype = 'inform'
    local c, rest = msg:match('^~(%a)~(.*)$')
    if c then
        ntype = ({ r = 'error', g = 'success', y = 'warning' })[c] or 'inform'
        msg = rest
    end
    lib.notify(src, { title = locale('notify_title'), description = msg, type = ntype, position = Config.NotifyPosition })
end

local function allowed(src, ace)
    if not ace then return true end
    return IsPlayerAceAllowed(tostring(src), ace)
end

local function validKey(key)
    return type(key) == 'string' and #key <= 64 and key:match('^[%w_:%.%-]+$') ~= nil
end

local function onCooldown(src)
    local now = GetGameTimer()
    if LastAction[src] and now - LastAction[src] < Config.ActionCooldown then
        notify(src, locale('err_cooldown'))
        return true
    end
    LastAction[src] = now
    return false
end

local function pack(media)
    if not media then return nil end
    return {
        type = media.type, url = media.url, ref = media.ref, sub = media.sub,
        live = media.live, loop = media.loop, seq = media.seq,
        elapsed = media.paused and media.pos or (os.time() - media.startedAt),
        paused = media.paused == true, rev = media.rev or 0,
    }
end

local function packChannel(ch)
    return {
        id = ch.id, label = ch.label, num = ch.num, fixed = ch.fixed == true,
        owner = ch.owner, media = pack(ch.media),
    }
end

local function packTV(st)
    if not st then return nil end
    if st.mode == 'channel' then return { mode = 'channel', channel = st.channel } end
    return { mode = 'media', media = pack(st.media) }
end

local function newMedia(src, url, forced, opts)
    opts = type(opts) == 'table' and opts or {}
    local media, err = Media.Parse(url, forced, { live = opts.live == true, loop = opts.loop == true })
    if not media then
        notify(src, '~r~' .. tostring(err))
        return nil
    end
    seqCounter = seqCounter + 1
    media.seq = seqCounter
    media.startedAt = os.time() - math.floor(media.startAt or 0)   -- ?t=90 links start at that position
    media.by = GetPlayerName(src)
    return media
end

local function countTVs()
    local n = 0
    for _ in pairs(TVs) do n = n + 1 end
    return n
end

local function setTV(key, st)
    TVs[key] = st
    TriggerClientEvent('rensyu_tv:setTV', -1, key, packTV(st))
end

local function broadcastChannel(ch, id)
    TriggerClientEvent('rensyu_tv:setChannel', -1, id or ch.id, ch and packChannel(ch) or nil)
end

-- 空いている最小のチャンネル番号 (CH 01, CH 02 ...)
local function nextNum()
    local used = {}
    for _, ch in pairs(Channels) do used[ch.num] = true end
    local n = 1
    while used[n] do n = n + 1 end
    return n
end

local function cleanLabel(label, fallback)
    label = type(label) == 'string' and label or ''
    label = label:gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if label == '' then label = fallback end
    return label:sub(1, 24)
end

local function hookOk(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        print('[rensyu_television] Hook error: ' .. tostring(res))
        return false
    end
    return res ~= false
end

-- 設定のチャンネルを登録 (url ありは固定チャンネル)
for _, c in ipairs(Config.Channels) do
    local ch = { id = c.id, label = c.label, num = nextNum(), owner = nil, fixed = false }
    if c.url then
        local media, err = Media.Parse(c.url, c.type or 'auto', { live = c.live, loop = c.loop })
        if media then
            seqCounter = seqCounter + 1
            media.seq = seqCounter
            media.startedAt = os.time()
            ch.media = media
            ch.fixed = true
        else
            print(('[rensyu_television] Invalid URL for channel "%s": %s'):format(c.id, tostring(err)))
        end
    end
    Channels[c.id] = ch
end

-- ■ 同期 ---------------------------------------------------------------
-- 参加時の全体同期 (ox_lib callback)
lib.callback.register('rensyu_tv:sync', function(src)
    local ch, tvs = {}, {}
    for id, c in pairs(Channels) do ch[id] = packChannel(c) end
    for key, st in pairs(TVs) do tvs[key] = packTV(st) end
    local boxes = {}
    for id, b in pairs(Boomboxes) do
        boxes[id] = { id = b.id, owner = b.owner, coords = b.coords, heading = b.heading, media = pack(b.media) }
    end
    return { channels = ch, tvs = tvs, boomboxes = boxes, canBroadcast = allowed(src, Config.BroadcastAce) }
end)

-- ■ テレビ単体の操作 -----------------------------------------------------
RegisterNetEvent('rensyu_tv:play', function(key, url, forced, opts)
    local src = source
    if not validKey(key) then return end
    if not allowed(src, Config.PlayAce) then return notify(src, '~r~' .. locale('err_no_play_perm')) end
    if onCooldown(src) then return end
    if not TVs[key] and countTVs() >= Config.MaxTVStates then
        return notify(src, '~r~' .. locale('err_tv_limit'))
    end

    local media = newMedia(src, url, forced, opts)
    if not media then return end
    if not hookOk(Config.Hooks.ScreenInteract, src, key, media) then
        return notify(src, '~r~' .. locale('err_content_play'))
    end
    setTV(key, { mode = 'media', media = media })
end)

RegisterNetEvent('rensyu_tv:tune', function(key, channelId)
    local src = source
    if not validKey(key) or type(channelId) ~= 'string' or not Channels[channelId] then return end
    if not allowed(src, Config.PlayAce) then return notify(src, '~r~' .. locale('err_no_op_perm')) end
    if onCooldown(src) then return end
    if not TVs[key] and countTVs() >= Config.MaxTVStates then
        return notify(src, '~r~' .. locale('err_tv_limit'))
    end
    setTV(key, { mode = 'channel', channel = channelId })
end)

RegisterNetEvent('rensyu_tv:off', function(key)
    local src = source
    if not validKey(key) or not TVs[key] then return end
    if not allowed(src, Config.PlayAce) then return notify(src, '~r~' .. locale('err_no_op_perm')) end
    if onCooldown(src) then return end
    setTV(key, nil)
end)

-- ■ チャンネルへの配信 ---------------------------------------------------
-- target: 既存チャンネルのid / 'new' (自分のチャンネルを新規開設)
RegisterNetEvent('rensyu_tv:broadcast', function(target, label, url, forced, opts)
    local src = source
    if type(target) ~= 'string' then return end
    if not allowed(src, Config.BroadcastAce) then return notify(src, '~r~' .. locale('err_no_bc_perm')) end
    if onCooldown(src) then return end

    local media = newMedia(src, url, forced, opts)
    if not media then return end
    if not hookOk(Config.Hooks.Broadcast, src, target, media) then
        return notify(src, '~r~' .. locale('err_content_bc'))
    end

    if target == 'new' then
        local id = 'p' .. src
        local ch = Channels[id]
        if ch then
            ch.media = media
            ch.label = cleanLabel(label, ch.label)
        else
            ch = { id = id, label = cleanLabel(label, GetPlayerName(src)), num = nextNum(), owner = src, fixed = false, media = media }
            Channels[id] = ch
        end
        broadcastChannel(ch)
        return notify(src, '~g~' .. locale('ok_bc_new', ch.num, ch.label))
    end

    local ch = Channels[target]
    if not ch then return end
    if ch.fixed then return notify(src, '~r~' .. locale('err_fixed_edit')) end
    if ch.owner and ch.owner ~= src then return notify(src, '~r~' .. locale('err_other_channel')) end
    ch.media = media
    broadcastChannel(ch)
    notify(src, '~g~' .. locale('ok_bc', ch.num))
end)

RegisterNetEvent('rensyu_tv:stopChannel', function(channelId)
    local src = source
    local ch = type(channelId) == 'string' and Channels[channelId] or nil
    if not ch then return end
    if not allowed(src, Config.BroadcastAce) then return notify(src, '~r~' .. locale('err_no_bc_perm')) end
    if ch.fixed then return notify(src, '~r~' .. locale('err_fixed_stop')) end
    if ch.owner and ch.owner ~= src then return notify(src, '~r~' .. locale('err_other_channel')) end
    if onCooldown(src) then return end

    if ch.owner then
        Channels[channelId] = nil          -- 開設したチャンネルは削除
        TriggerClientEvent('rensyu_tv:setChannel', -1, channelId, nil)
    else
        ch.media = nil                     -- 共有チャンネルは配信だけ止める
        broadcastChannel(ch)
    end
    notify(src, '~y~' .. locale('info_bc_stopped'))
end)

-- 配信者が退出したらそのチャンネルを閉じる
-- ■ 再生コントロール (一時停止 / 再生 / シーク / 最初から) ------------------
-- 一時停止や位置の変更は、そのテレビ(チャンネル)を見ている全員に同期されます
local function controllable(media)
    if not media or media.live then return false end
    if media.type == 'video' or media.type == 'audio' then return true end
    if media.type == 'youtube' then return media.sub == 'video' end
    if media.type == 'twitch' then return media.sub == 'vod' end
    return false
end

local function currentPos(media)
    return media.paused and media.pos or (os.time() - media.startedAt)
end

local function applyControl(media, action, value)
    local pos = currentPos(media)

    if action == 'toggle' then
        action = media.paused and 'play' or 'pause'
    end

    if action == 'pause' then
        if media.paused then return false end
        media.paused, media.pos = true, pos
    elseif action == 'play' then
        if not media.paused then return false end
        media.startedAt = os.time() - media.pos
        media.paused, media.pos = false, nil
    elseif action == 'seek' or action == 'restart' then
        local newPos = 0
        if action == 'seek' then
            local v = math.max(-3600, math.min(3600, tonumber(value) or 0))
            newPos = math.max(0, pos + v)
        end
        if media.paused then media.pos = newPos else media.startedAt = os.time() - newPos end
    else
        return false
    end

    media.rev = (media.rev or 0) + 1
    return true
end

RegisterNetEvent('rensyu_tv:control', function(key, action, value)
    local src = source
    if not validKey(key) or type(action) ~= 'string' then return end
    local st = TVs[key]
    if not st then return end

    local now = GetGameTimer()
    if LastControl[src] and now - LastControl[src] < (Config.ControlCooldown or 300) then return end
    LastControl[src] = now

    if st.mode == 'channel' then
        local ch = Channels[st.channel]
        if not ch or not ch.media then return end
        if not allowed(src, Config.BroadcastAce) then return notify(src, '~r~' .. locale('err_no_ch_perm')) end
        if ch.fixed then return notify(src, '~r~' .. locale('err_fixed_ctl')) end
        if ch.owner and ch.owner ~= src then return notify(src, '~r~' .. locale('err_other_channel')) end
        if not controllable(ch.media) then return end
        if applyControl(ch.media, action, value) then broadcastChannel(ch) end
        return
    end

    if not allowed(src, Config.PlayAce) then return notify(src, '~r~' .. locale('err_no_op_perm')) end
    if not controllable(st.media) then return end
    if applyControl(st.media, action, value) then
        setTV(key, st)
    end
end)

-- ■ ブームボックス (ox_inventory のアイテムで設置する小道具) ----------------
local BC = Config.Boombox or {}
local boomCounter = 0
local BOOM_TYPES = { youtube = true, twitch = true, audio = true, video = true }

local function packBox(b)
    return { id = b.id, owner = b.owner, coords = b.coords, heading = b.heading, media = pack(b.media) }
end

local function sendBox(id, b)
    TriggerClientEvent('rensyu_tv:setBoombox', -1, id, b and packBox(b) or nil)
end

local function inventoryReady()
    return GetResourceState('ox_inventory') == 'started'
end

local function playerNear(src, coords, dist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= dist
end

local function getBox(id)
    return type(id) == 'string' and Boomboxes[id] or nil
end

-- 設置: アイテムを1つ消費して小道具を出す
RegisterNetEvent('rensyu_tv:boombox:place', function(coords, heading)
    local src = source
    if not BC.Enabled then return end
    if type(coords) ~= 'vector3' or type(heading) ~= 'number' then return end
    if onCooldown(src) then return end
    if not playerNear(src, coords, 8.0) then return notify(src, '~r~' .. locale('err_place_far')) end

    local owned = 0
    for _, b in pairs(Boomboxes) do
        if b.owner == src then owned = owned + 1 end
    end
    if owned >= (BC.MaxPerPlayer or 1) then return notify(src, '~r~' .. locale('err_box_limit')) end

    if not inventoryReady() then return notify(src, '~r~' .. locale('err_no_inventory')) end
    if (exports.ox_inventory:GetItemCount(src, BC.Item) or 0) < 1 then
        return notify(src, '~r~' .. locale('err_no_item'))
    end
    if not exports.ox_inventory:RemoveItem(src, BC.Item, 1) then
        return notify(src, '~r~' .. locale('err_item_consume'))
    end

    boomCounter = boomCounter + 1
    local box = { id = 'bx' .. boomCounter, owner = src, coords = coords, heading = heading % 360.0 }
    Boomboxes[box.id] = box
    sendBox(box.id, box)
    notify(src, '~g~' .. locale('ok_placed'))
end)

-- 回収: アイテムが手元に戻る
RegisterNetEvent('rensyu_tv:boombox:pickup', function(id)
    local src = source
    local box = getBox(id)
    if not box then return end
    if onCooldown(src) then return end
    if not playerNear(src, box.coords, 6.0) then return notify(src, '~r~' .. locale('err_box_far')) end
    if not BC.PickupAnyone and box.owner ~= src then return notify(src, '~r~' .. locale('err_owner_only')) end
    if not inventoryReady() then return notify(src, '~r~' .. locale('err_no_inventory')) end
    if not exports.ox_inventory:CanCarryItem(src, BC.Item, 1) then return notify(src, '~r~' .. locale('err_inv_full')) end
    if not exports.ox_inventory:AddItem(src, BC.Item, 1) then return notify(src, '~r~' .. locale('err_item_receive')) end

    Boomboxes[box.id] = nil
    sendBox(box.id, nil)
    notify(src, '~y~' .. locale('info_picked'))
end)

RegisterNetEvent('rensyu_tv:boombox:play', function(id, url, forced, opts)
    local src = source
    local box = getBox(id)
    if not box then return end
    if not allowed(src, BC.PlayAce) then return notify(src, '~r~' .. locale('err_no_play_perm')) end
    if onCooldown(src) then return end
    if not playerNear(src, box.coords, 12.0) then return notify(src, '~r~' .. locale('err_box_far')) end

    local media = newMedia(src, url, forced, opts)
    if not media then return end
    if not BOOM_TYPES[media.type] then
        return notify(src, '~r~' .. locale('err_box_types'))
    end
    if not hookOk(Config.Hooks.Boombox, src, id, media) then
        return notify(src, '~r~' .. locale('err_content_play'))
    end
    box.media = media
    sendBox(box.id, box)
end)

RegisterNetEvent('rensyu_tv:boombox:stop', function(id)
    local src = source
    local box = getBox(id)
    if not box or not box.media then return end
    if not allowed(src, BC.PlayAce) then return notify(src, '~r~' .. locale('err_no_op_perm')) end
    if onCooldown(src) then return end
    box.media = nil
    sendBox(box.id, box)
end)

RegisterNetEvent('rensyu_tv:boombox:control', function(id, action, value)
    local src = source
    local box = getBox(id)
    if not box or not box.media or type(action) ~= 'string' then return end
    if not allowed(src, BC.PlayAce) then return end
    local now = GetGameTimer()
    if LastControl[src] and now - LastControl[src] < (Config.ControlCooldown or 300) then return end
    LastControl[src] = now
    if not controllable(box.media) then return end
    if applyControl(box.media, action, value) then sendBox(box.id, box) end
end)

-- リソース停止時は、設置中のブームボックスをオンラインの持ち主へ返す
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not inventoryReady() then return end
    for _, b in pairs(Boomboxes) do
        if b.owner and GetPlayerName(b.owner) then
            pcall(function() exports.ox_inventory:AddItem(b.owner, BC.Item, 1) end)
        end
    end
end)

-- ■ Page titles ------------------------------------------------------------
local TC = Config.Titles or {}
local TitleCache = {}      -- [url] = { title = string|false, at = os.time() }
local LastTitleReq = {}
local TITLE_TTL, FAIL_TTL = 86400, 600
local UA = 'Mozilla/5.0 (compatible; rensyu_television title fetch)'

-- Refuse obvious local / private targets (the server must not be used to probe the internal network)
local function isPrivateHost(h)
    h = (h or ''):lower()
    if h == '' or h == 'localhost' or h:match('%.local$') or h:match('%.localhost$') or h:match('%.internal$') then return true end
    if h:find('[', 1, true) or h:find(':', 1, true) then return true end         -- IPv6 literal
    if h:match('^%d+$') or h:match('^0x') then return true end                   -- decimal / hex IP
    if h:match('^127%.') or h:match('^10%.') or h:match('^192%.168%.') or h:match('^169%.254%.') or h:match('^0%.') then return true end
    local second = h:match('^172%.(%d+)%.')
    if second and tonumber(second) >= 16 and tonumber(second) <= 31 then return true end
    return false
end

local function htmlDecode(s)
    s = s:gsub('&#(%d+);', function(n) n = tonumber(n); return n and n < 0x110000 and utf8.char(n) or '' end)
    s = s:gsub('&#[xX](%x+);', function(n) n = tonumber(n, 16); return n and n < 0x110000 and utf8.char(n) or '' end)
    local map = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ' }
    return (s:gsub('&(%a+);', function(name) return map[name] end))
end

local function extractTitle(html)
    html = html:sub(1, 200000)
    local og = html:match('<meta[^>]-property=["\']og:title["\'][^>]-content=["\']([^"\']+)["\']')
        or html:match('<meta[^>]-content=["\']([^"\']+)["\'][^>]-property=["\']og:title["\']')
    local t = og or html:match('<[Tt][Ii][Tt][Ll][Ee][^>]*>(.-)</[Tt][Ii][Tt][Ll][Ee]>')
    return t and htmlDecode(t) or nil
end

local function fileNameOf(url)
    local path = url:match('^https?://[^/?#]+([^?#]*)') or ''
    local name = path:match('([^/]+)$')
    if not name then return nil end
    local ok, decoded = pcall(function()
        return (name:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
    end)
    return ok and decoded or name
end

local function httpGet(url)
    local p, done = promise.new(), false
    PerformHttpRequest(url, function(status, body)
        if not done then done = true; p:resolve({ status = status, body = body }) end
    end, 'GET', '', { ['User-Agent'] = UA, ['Range'] = 'bytes=0-200000', ['Accept-Language'] = GetConvar('ox:locale', 'en') })
    SetTimeout(6000, function()
        if not done then done = true; p:resolve(nil) end
    end)
    return Citizen.Await(p)
end

local function webTitle(url)
    local host = url:match('^https?://([^/?#:]+)')
    if not TC.FetchWeb or isPrivateHost(host) then return nil end
    local res = httpGet(url)
    if res and (res.status == 200 or res.status == 206) and type(res.body) == 'string' then
        return extractTitle(res.body)
    end
end

local function resolveTitle(url)
    local media = Media.Parse(url, 'auto', {})
    if not media then return nil end
    local t = media.type

    if t == 'image' or t == 'video' or t == 'audio' then
        return fileNameOf(media.url)
    elseif t == 'twitch' then
        if media.sub == 'channel' then return 'Twitch: ' .. media.ref end
        if media.sub == 'vod' then return 'Twitch VOD ' .. media.ref end
        return 'Twitch clip ' .. media.ref
    elseif t == 'youtube' then
        local target = media.sub == 'video' and ('https://www.youtube.com/watch?v=' .. media.ref) or media.url
        local res = httpGet('https://www.youtube.com/oembed?format=json&url=' .. Media.UrlEncode(target))
        if res and res.status == 200 and type(res.body) == 'string' then
            local ok, data = pcall(json.decode, res.body)
            if ok and type(data) == 'table' and data.title then return data.title end
        end
        return nil
    end
    return webTitle(media.url)
end

local function cleanTitle(title)
    if type(title) ~= 'string' then return nil end
    title = title:gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if title == '' then return nil end
    local max = TC.MaxLength or 100
    if #title > max then title = title:sub(1, max) .. '...' end
    return title
end

lib.callback.register('rensyu_tv:title', function(src, url)
    if not TC.Enabled or type(url) ~= 'string' or #url > (Config.MaxUrlLength or 512) then return nil end

    local hit = TitleCache[url]
    if hit and os.time() - hit.at < (hit.title and TITLE_TTL or FAIL_TTL) then
        return hit.title or nil
    end

    local now = GetGameTimer()
    if LastTitleReq[src] and now - LastTitleReq[src] < 200 then return nil end   -- anti-spam
    LastTitleReq[src] = now

    local ok, title = pcall(resolveTitle, url)
    title = ok and cleanTitle(title) or nil
    TitleCache[url] = { title = title or false, at = os.time() }
    return title
end)

AddEventHandler('playerDropped', function()
    local src = source
    LastAction[src] = nil
    LastControl[src] = nil
    LastTitleReq[src] = nil
    for id, ch in pairs(Channels) do
        if ch.owner == src then
            Channels[id] = nil
            TriggerClientEvent('rensyu_tv:setChannel', -1, id, nil)
        end
    end
end)
