local RES = GetCurrentResourceName()
local W, H = Config.DuiWidth, Config.DuiHeight
local PLAYER_URL = ('https://cfx-nui-%s/html/player.html'):format(RES)

-- 3D描画モードで使う Scaleform (gfx のファイル名ごとに別のムービー)
local SLOT_NAMES = {
    'generic_texture_renderer', 'generic_texture_renderer_2',
    'generic_texture_renderer_3', 'generic_texture_renderer_4',
}
local SLOT_COUNT = math.max(1, math.min(Config.MaxScreens or 4, 8))

local State = { tvs = {}, channels = {}, canBroadcast = false }
local ModelSet = {}      -- [modelHash] = { name, rt, range, scale, offset, mode }
local Spawned = {}       -- [entity] = { id, label }
local Nearby = {}        -- 近くのテレビ一覧 (近い順)
local Slots = {}         -- 映像スロット (DUI)
local SlotFailed = {}
local LinkedModels = {}
local Priority = {}      -- [グループ] = 最後に操作したテレビのkey
local Menu, Browse = nil, nil
local BoxMenu = nil    -- 操作パネルを開いているブームボックスのid
local Boxes = {}       -- [id] = { id, owner, coords, heading, media, entity, point, range }
local BoomSlots = {}   -- ブームボックス用の音声スロット (映像なしのDUI)
local syncing, pendingSync = false, false

local Volume = tonumber(GetResourceKvpString('rensyu_tv_volume')) or Config.DefaultVolume

for name, v in pairs(Config.TVModels) do
    local cfg = type(v) == 'table' and v or { Target = v }
    ModelSet[GetHashKey(name)] = {
        name = name,
        rt = cfg.Target,
        mode = cfg.Target and 'rt' or '3d',
        range = cfg.Range or Config.RenderDistance,
        scale = cfg.Scale or 0.085,
        offset = cfg.Offset or vector3(0.0, 0.0, 0.0),
    }
end

-- ■ ユーティリティ ----------------------------------------------------
-- Translation table for the NUI / player page (locales/<lang>.json)
local function LoadStrings()
    if type(lib.getLocales) == 'function' then
        local t = lib.getLocales()
        if type(t) == 'table' and next(t) then return t end
    end
    local function load(lang)
        local raw = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(lang))
        return raw and json.decode(raw) or {}
    end
    local t = load('en')
    for k, v in pairs(load(GetConvar('ox:locale', 'en'))) do t[k] = v end
    return t
end

local UiStringsCache, PlayerStringsCache
local function UiStrings()
    UiStringsCache = UiStringsCache or LoadStrings()
    return UiStringsCache
end
local function PlayerStrings()
    if not PlayerStringsCache then
        local t = UiStrings()
        PlayerStringsCache = {}
        for _, k in ipairs({ 'pl_err_image', 'pl_err_video', 'pl_err_audio', 'pl_err_youtube', 'pl_err_twitch',
                             'pl_audio_playing', 'pl_ns_title', 'pl_ns_sub' }) do
            PlayerStringsCache[k] = t[k] or ''
        end
    end
    return PlayerStringsCache
end

-- YouTube settings sent to the player page ('auto' follows the ox:locale convar)
local function YtConfig()
    local y = Config.YouTube or {}
    local lang = y.Language
    if lang == 'auto' then lang = GetConvar('ox:locale', 'en') end
    return { Language = lang, Captions = y.Captions == true, PreferAudioLanguage = y.PreferAudioLanguage ~= false }
end

-- ox_lib notification
local function Notify(msg, ntype)
    lib.notify({ title = locale('notify_title'), description = msg, type = ntype or 'inform', position = Config.NotifyPosition })
end

local function stamp(m)
    if m then m.recv = GetGameTimer() end
    return m
end

local function elapsedOf(m)
    if m.paused then return m.elapsed or 0 end
    return (m.elapsed or 0) + (GetGameTimer() - (m.recv or GetGameTimer())) / 1000.0
end

-- 一時停止・シークができる種類か (ライブ・Web・画像などは不可)
local function IsControllable(m)
    if not m or m.live then return false end
    if m.type == 'video' or m.type == 'audio' then return true end
    if m.type == 'youtube' then return m.sub == 'video' end
    if m.type == 'twitch' then return m.sub == 'vod' end
    return false
end

-- そのテレビに今映すべき内容: media, チャンネル情報, チャンネルid
local function Effective(key)
    local st = State.tvs[key]
    if not st then return nil end
    if st.mode == 'channel' then
        local ch = State.channels[st.channel]
        return ch and ch.media, ch, st.channel
    end
    return st.media
end

local function SortedChannels()
    local list = {}
    for _, ch in pairs(State.channels) do list[#list + 1] = ch end
    table.sort(list, function(a, b) return a.num < b.num end)
    return list
end

-- ■ 映像スロット ---------------------------------------------------------
local function InitSlot(i)
    if Slots[i] then return Slots[i] end
    local txdName = 'rensyu_tv_txd_' .. i
    local txd = CreateRuntimeTxd(txdName)
    local dui = CreateDui('about:blank', W, H)
    CreateRuntimeTextureFromDuiHandle(txd, 'screen', GetDuiHandle(dui))
    Slots[i] = { idx = i, tag = tostring(i), dui = dui, txd = txdName, page = 'blank', loaded = false, vol = -1 }
    return Slots[i]
end

-- 3D描画モード用の Scaleform を必要になった時だけ読み込む
local function EnsureScaleform(slot)
    if slot.sf then return true end
    local name = SLOT_NAMES[slot.idx]
    if not name or SlotFailed[slot.idx] then return false end

    local sf = RequestScaleformMovie(name)
    local t = GetGameTimer()
    while not HasScaleformMovieLoaded(sf) do
        Wait(0)
        if GetGameTimer() - t > 5000 then
            SlotFailed[slot.idx] = true
            print(('[rensyu_television] Failed to load scaleform "%s" (check the stream folder)'):format(name))
            return false
        end
    end

    PushScaleformMovieFunction(sf, 'SET_TEXTURE')
    PushScaleformMovieMethodParameterString(slot.txd)
    PushScaleformMovieMethodParameterString('screen')
    PushScaleformMovieFunctionParameterInt(0)
    PushScaleformMovieFunctionParameterInt(0)
    PushScaleformMovieFunctionParameterInt(W)
    PushScaleformMovieFunctionParameterInt(H)
    PopScaleformMovieFunctionVoid()

    slot.sf = sf
    return true
end

local function SendTo(slot, msg)
    SendDuiMessage(slot.dui, json.encode(msg))
end

-- プレイヤーとテレビの間にある壁の数を数える (マップ地形のみ判定)
local function CountWalls(from, to, ignore, maxWalls)
    local walls, cur = 0, from
    for _ = 1, maxWalls do
        local remaining = #(to - cur)
        if remaining < 1.0 then break end
        local h = StartExpensiveSynchronousShapeTestLosProbe(cur.x, cur.y, cur.z, to.x, to.y, to.z, 1, ignore, 4)
        local _, hit, hitCoords = GetShapeTestResult(h)
        if hit ~= 1 and hit ~= true then break end
        walls = walls + 1
        cur = hitCoords + ((to - cur) / remaining) * 1.0   -- 壁の向こう側から続きを判定
    end
    return walls
end

-- 壁による音量倍率を更新 (判定は300msごと、変化は滑らかに)
local function UpdateOcclusion(slot)
    local oc = Config.Occlusion
    if not oc or not oc.Enabled or not slot.entry then
        slot.occ, slot.occTarget = 1.0, 1.0
        return
    end

    local now = GetGameTimer()
    if not slot.occAt or now - slot.occAt >= 300 then
        slot.occAt = now
        local ped = PlayerPedId()
        local listener = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.7)
        local tv = slot.entry.coords + vector3(0.0, 0.0, 0.3)
        local dist = #(tv - listener)
        if dist > slot.entry.range then
            slot.occTarget = 1.0
        else
            -- テレビ自身が載っている壁や台に当たらないよう、手前で止める
            local to = tv + ((listener - tv) / math.max(dist, 0.01)) * math.min(0.4, dist * 0.5)
            local walls = CountWalls(listener, to, slot.entry.entity or 0, math.max(1, oc.MaxWalls or 3))

            -- 密閉判定: 別のインテリア同士で壁がある / 壁が一定枚数以上
            local silent = false
            if walls >= 1 and oc.SilentWhenSealed then
                local tvInt = GetInteriorAtCoords(tv.x, tv.y, tv.z)
                local plInt = GetInteriorAtCoords(listener.x, listener.y, listener.z)
                if tvInt ~= plInt then silent = true end
            end
            if oc.SilentWalls and oc.SilentWalls > 0 and walls >= oc.SilentWalls then silent = true end

            if silent then
                slot.occTarget = 0.0
            else
                slot.occTarget = math.max(oc.MinFactor or 0.06, (oc.WallFactor or 0.45) ^ walls)
            end
        end
    end

    local cur, target = slot.occ or 1.0, slot.occTarget or 1.0
    cur = cur + (target - cur) * 0.4
    if target == 0.0 and cur < 0.02 then cur = 0.0 end
    slot.occ = cur
end

-- 距離と壁に応じた音量 (0-100)
local function CalcVolume(slot)
    if Browse and Browse.slot == slot then return Volume end
    local e = slot.entry
    if not e then return 0 end
    local d = #(GetEntityCoords(PlayerPedId()) - e.coords)
    local full, maxd = Config.AudioFullDistance, e.range
    local f = 1.0
    if d > full then f = math.max(0.0, 1.0 - (d - full) / math.max(maxd - full, 0.1)) end
    return math.floor(Volume * f * (slot.occ or 1.0) + 0.5)
end

local function BuildMessage(slot)
    local m, ch = slot.media, slot.ch
    local chInfo = ch and { num = ch.num, label = ch.label } or nil
    if m.type == 'nosignal' then
        return { action = 'nosignal', channel = chInfo, t = PlayerStrings() }
    end
    return {
        action = 'media',
        media = { type = m.type, sub = m.sub, ref = m.ref, url = m.url, loop = m.loop, live = m.live },
        elapsed = elapsedOf(m),
        paused = m.paused == true,
        parents = Config.TwitchParents,
        yt = YtConfig(),
        channel = chInfo,
        volume = CalcVolume(slot),
        audioOnly = slot.audio == true,
        t = PlayerStrings(),
    }
end

-- 一時停止・再生・シークを再生ページへ送る (force: 位置が近くても必ず合わせる)
local function SendControl(slot, force)
    local m = slot.media
    if not m or slot.page ~= 'player' or not slot.loaded then return end
    if not IsControllable(m) then return end
    SendTo(slot, { action = 'control', paused = m.paused == true, pos = elapsedOf(m), force = force == true })
end

-- スロットの media / ch を DUI に反映
local function ApplyContent(slot)
    local m = slot.media
    if m.type == 'web' then
        if slot.page ~= 'web' or slot.webUrl ~= m.url then
            slot.page, slot.webUrl, slot.loaded = 'web', m.url, false
            SetDuiUrl(slot.dui, Media.WebUrl(m.url))
        end
        return
    end

    if slot.page ~= 'player' then
        slot.page, slot.webUrl, slot.loaded = 'player', nil, false
        SetDuiUrl(slot.dui, PLAYER_URL .. '?slot=' .. (slot.tag or slot.idx))
        return -- 読み込み完了 (pageLoaded) で内容を送信
    end
    if slot.loaded then SendTo(slot, BuildMessage(slot)) end
end

local CloseBrowse

local function ReleaseSlot(slot)
    SetDuiUrl(slot.dui, 'about:blank') -- 音も止める
    if Browse and Browse.slot == slot then CloseBrowse() end
    slot.grp, slot.key, slot.sig, slot.renderId = nil, nil, nil, nil
    slot.media, slot.ch, slot.chId, slot.entry = nil, nil, nil, nil
    slot.page, slot.webUrl, slot.loaded, slot.vol = 'blank', nil, false, -1
    slot.occ, slot.occTarget, slot.occAt = 1.0, 1.0, nil
end

local function PrepareRenderTarget(entry)
    if not IsNamedRendertargetRegistered(entry.rt) then
        RegisterNamedRendertarget(entry.rt, false)
    end
    if not LinkedModels[entry.model] then
        if not IsNamedRendertargetLinked(entry.model) then
            LinkNamedRendertarget(entry.model)
        end
        LinkedModels[entry.model] = true
    end
    return GetNamedRendertargetRenderId(entry.rt)
end

local function FindSlot(key)
    for i = 1, SLOT_COUNT do
        local s = Slots[i]
        if s and s.grp and s.key == key then return s end
    end
end

-- どのテレビにどの映像を割り当てるか決める
local function SyncScreens()
    if syncing then pendingSync = true return end
    syncing = true

    local desired, order = {}, {}
    local function consider(e, allowIdle)
        if desired[e.grp] or #order >= SLOT_COUNT then return end
        local m, ch, chId = Effective(e.key)
        if not m then
            local st = State.tvs[e.key]
            if st and st.mode == 'channel' then
                m = { type = 'nosignal', seq = 'ns:' .. tostring(chId) }   -- 放送していないチャンネル
            elseif allowIdle and Config.ShowNoSignal and e.dist <= Config.NoSignalDistance then
                m = { type = 'nosignal', seq = 'ns:idle' }                  -- 何も映していないテレビ
            else
                return
            end
        end
        desired[e.grp] = { entry = e, media = m, ch = ch, chId = chId }
        order[#order + 1] = e.grp
    end

    -- 近くにいない優先指定は解除
    local present = {}
    for _, e in ipairs(Nearby) do present[e.key] = true end
    for grp, key in pairs(Priority) do
        if not present[key] then Priority[grp] = nil end
    end

    -- ①最後に操作したテレビ ②近い順 ③(空きがあれば) NO SIGNAL
    for _, e in ipairs(Nearby) do
        if Priority[e.grp] == e.key then consider(e, true) end
    end
    for _, e in ipairs(Nearby) do consider(e, false) end
    for _, e in ipairs(Nearby) do consider(e, true) end

    for i = 1, SLOT_COUNT do
        local s = Slots[i]
        if s and s.grp then
            local d = desired[s.grp]
            if not d or d.entry.key ~= s.key then ReleaseSlot(s) end
        end
    end

    for _, grp in ipairs(order) do
        local d = desired[grp]
        local slot
        for i = 1, SLOT_COUNT do
            local s = Slots[i]
            if s and s.grp == grp then slot = s break end
        end
        if not slot then
            for i = 1, SLOT_COUNT do
                local s = Slots[i]
                if not s or not s.grp then slot = s or InitSlot(i) break end
            end
        end

        if slot and d.entry.mode == '3d' and not EnsureScaleform(slot) then
            slot = nil
        end

        if slot then
            slot.grp, slot.key, slot.entry, slot.chId = grp, d.entry.key, d.entry, d.chId
            if d.entry.mode == 'rt' then
                slot.renderId = PrepareRenderTarget(d.entry)
            end
            local sig = tostring(d.media.seq) .. ':' .. (d.ch and (d.ch.num .. d.ch.label) or '')
            if slot.sig ~= sig then
                slot.sig, slot.media, slot.ch = sig, d.media, d.ch
                slot.rev = d.media.rev or 0
                ApplyContent(slot)
            else
                -- 同じ映像で状態だけ変わった (一時停止・シーク)
                slot.media, slot.ch = d.media, d.ch
                if (slot.rev or 0) ~= (d.media.rev or 0) then
                    slot.rev = d.media.rev or 0
                    SendControl(slot, false)
                end
            end
        end
    end

    syncing = false
    if pendingSync then
        pendingSync = false
        SyncScreens()
    end
end

-- 再生ページの読み込み完了 → 現在の内容を送る
RegisterNUICallback('pageLoaded', function(d, cb)
    cb({})
    local tag = tostring(d and d.slot or '')
    local slot
    if tag:sub(1, 1) == 'b' then
        slot = BoomSlots[tonumber(tag:sub(2))]    -- ブームボックス
    else
        slot = Slots[tonumber(tag)]               -- テレビ
    end
    if slot and slot.page == 'player' and slot.media then
        slot.loaded = true
        slot.vol = -1
        SendTo(slot, BuildMessage(slot))
    end
end)

-- The player page asks to open the normal YouTube / Twitch page (video cannot be embedded)
RegisterNUICallback('pageFallback', function(d, cb)
    cb({})
    local url = type(d) == 'table' and d.url
    if type(url) ~= 'string' then return end
    if not (url:find('^https://www%.youtube%.com/') or url:find('^https://www%.twitch%.tv/')
        or url:find('^https://clips%.twitch%.tv/')) then return end

    local tag = tostring(d.slot or '')
    local slot
    if tag:sub(1, 1) == 'b' then slot = BoomSlots[tonumber(tag:sub(2))] else slot = Slots[tonumber(tag)] end
    if slot and slot.page == 'player' then
        slot.page, slot.webUrl, slot.loaded = 'web', url, false
        SetDuiUrl(slot.dui, url)
    end
end)

-- ■ テレビの検出 ---------------------------------------------------------
local function tvKey(entity, model)
    local sp = Spawned[entity]
    if sp then return 'cfg:' .. sp.id, sp.label end
    local c = GetEntityCoords(entity)
    return ('w:%d:%d:%d:%d'):format(model, math.floor(c.x * 10 + 0.5), math.floor(c.y * 10 + 0.5), math.floor(c.z * 10 + 0.5)),
        ModelSet[model].name
end

local function MakeEntry(obj, model, info, pc)
    local c = GetEntityCoords(obj)
    local key, label = tvKey(obj, model)
    return {
        entity = obj, key = key, label = label, model = model, info = info,
        mode = info.mode, range = info.range, coords = c, dist = #(pc - c),
        grp = info.mode == '3d' and ('3d:' .. key) or info.rt,
        rt = info.rt,
    }
end

local function ScanNearby()
    local pc = GetEntityCoords(PlayerPedId())
    local list = {}
    for _, obj in ipairs(GetGamePool('CObject')) do
        local model = GetEntityModel(obj)
        local info = ModelSet[model]
        if info then
            local e = MakeEntry(obj, model, info, pc)
            if e.dist <= info.range then list[#list + 1] = e end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    Nearby = list
end

CreateThread(function()
    while true do
        ScanNearby()
        SyncScreens()
        for _ = 1, 10 do
            Wait(50)
            if pendingSync and not syncing then
                pendingSync = false
                SyncScreens()
            end
        end
    end
end)

-- 設定で追加したテレビ: 近づくと生成、離れると削除 (ox_lib points)
local SpawnedByCfg, Inside, Points = {}, {}, {}

local function SpawnTV(tv)
    if SpawnedByCfg[tv.id] then return end
    local hash = GetHashKey(tv.model)
    if not IsModelInCdimage(hash) then
        print(('[rensyu_television] Model %s not found'):format(tv.model))
        return
    end
    if not pcall(lib.requestModel, hash, 5000) then
        print(('[rensyu_television] Failed to load model %s'):format(tv.model))
        return
    end
    if SpawnedByCfg[tv.id] or not Inside[tv.id] then   -- 読み込み中に離れた / 二重生成の防止
        SetModelAsNoLongerNeeded(hash)
        return
    end
    local o = CreateObject(hash, tv.coords.x, tv.coords.y, tv.coords.z, false, false, false)
    SetEntityHeading(o, tv.heading or 0.0)
    FreezeEntityPosition(o, true)
    Spawned[o] = { id = tv.id, label = tv.label or tv.id }
    SpawnedByCfg[tv.id] = o
    SetModelAsNoLongerNeeded(hash)
end

local function DespawnTV(tv)
    local o = SpawnedByCfg[tv.id]
    if not o then return end
    Spawned[o] = nil
    if DoesEntityExist(o) then DeleteEntity(o) end
    SpawnedByCfg[tv.id] = nil
end

for _, tv in ipairs(Config.TVs) do
    Points[#Points + 1] = lib.points.new({
        coords = tv.coords,
        distance = Config.SpawnDistance,
        onEnter = function()
            Inside[tv.id] = true
            CreateThread(function() SpawnTV(tv) end)
        end,
        onExit = function()
            Inside[tv.id] = false
            DespawnTV(tv)
        end,
    })
end

-- ■ 描画 -----------------------------------------------------------------
CreateThread(function()
    while true do
        local active = false
        for i = 1, SLOT_COUNT do
            local s = Slots[i]
            if s and s.grp and s.entry then
                active = true
                if s.entry.mode == 'rt' then
                    if s.renderId and s.renderId ~= -1 then
                        SetTextRenderId(s.renderId)
                        Set_2dLayer(4)
                        SetScriptGfxDrawBehindPausemenu(true)
                        DrawSprite(s.txd, 'screen', 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
                        SetTextRenderId(GetDefaultScriptRendertargetRenderId())
                        SetScriptGfxDrawBehindPausemenu(false)
                    end
                elseif s.sf and DoesEntityExist(s.entry.entity) then
                    local info = s.entry.info
                    local p = GetOffsetFromEntityInWorldCoords(s.entry.entity, info.offset.x, info.offset.y, info.offset.z)
                    DrawScaleformMovie_3dSolid(s.sf, p.x, p.y, p.z, 0.0, 0.0, -GetEntityHeading(s.entry.entity),
                        2.0, 2.0, 2.0, info.scale, info.scale * (9.0 / 16.0), 2)
                end
            end
        end

        if Browse and Browse.slot.grp then
            local r = Browse.rect
            if Config.BrowseWindow and Config.BrowseWindow.HideHud then HideHudAndRadarThisFrame() end
            SetScriptGfxDrawOrder(7)   -- draw on the top layer, above other script drawing
            DrawRect(r.cx, r.cy, r.w + 0.008, r.h + 0.014, 18, 22, 34, 235)   -- frame
            DrawSprite(Browse.slot.txd, 'screen', r.cx, r.cy, r.w, r.h, 0.0, 255, 255, 255, 255)
        end

        Wait(active and 0 or 250)
    end
end)

-- 距離・壁に応じた音量を再生ページへ送る (テレビ + ブームボックス)
CreateThread(function()
    while true do
        for _, list in ipairs({ Slots, BoomSlots }) do
            for i = 1, 8 do
                local sl = list[i]
                if sl and (sl.grp or sl.boxId) and sl.loaded and sl.page == 'player' and sl.media then
                    local t = sl.media.type
                    if t == 'youtube' or t == 'twitch' or t == 'video' or t == 'audio' then
                        UpdateOcclusion(sl)
                        local v = CalcVolume(sl)
                        if v ~= sl.vol then
                            sl.vol = v
                            SendTo(sl, { action = 'volume', value = v })
                        end
                    end
                end
            end
        end
        Wait(150)
    end
end)

-- ■ メニュー / ブラウズ -----------------------------------------------------
-- Animation while the boombox panel is open
local BoxAnimActive = false

local function BoxAnimCfg()
    local a = Config.Boombox and Config.Boombox.Animation
    return (type(a) == 'table' and a.dict and a.clip) and a or nil
end

local function StartBoxAnim(box)
    local a = BoxAnimCfg()
    if not a then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    if box and box.coords then                      -- face the boombox
        local d = box.coords - GetEntityCoords(ped)
        SetEntityHeading(ped, GetHeadingFromVector_2d(d.x, d.y))
    end
    if not pcall(lib.requestAnimDict, a.dict, 3000) then return end
    BoxAnimActive = true
    TaskPlayAnim(ped, a.dict, a.clip, 3.0, -3.0, -1, a.flag or 1, 0.0, false, false, false)
end

local function StopBoxAnim()
    if not BoxAnimActive then return end
    BoxAnimActive = false
    local a = BoxAnimCfg()
    if a then
        local ped = PlayerPedId()
        if IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then StopAnimTask(ped, a.dict, a.clip, 3.0) end
    end
end

-- keep the animation going if something interrupts it
CreateThread(function()
    while true do
        if BoxAnimActive then
            local a = BoxAnimCfg()
            local ped = PlayerPedId()
            if a and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
                TaskPlayAnim(ped, a.dict, a.clip, 3.0, -3.0, -1, a.flag or 1, 0.0, false, false, false)
            end
        end
        Wait(500)
    end
end)

local function CloseMenu()
    StopBoxAnim()
    Menu = nil
    BoxMenu = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

CloseBrowse = function()
    if not Browse then return end
    Browse = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- リモコンUIに渡す状態 (key が nil のときは放送管理のみ)
local function MenuState(key)
    local myId = GetPlayerServerId(PlayerId())
    local current = { mode = 'off' }
    local st = key and State.tvs[key]
    if st then
        if st.mode == 'channel' then
            local ch = State.channels[st.channel]
            current = {
                mode = 'channel', channel = st.channel,
                channelLabel = ch and ch.label or locale('channel_closed'), channelNum = ch and ch.num or 0,
                idle = not (ch and ch.media),
                type = ch and ch.media and ch.media.type, url = ch and ch.media and ch.media.url,
                live = ch and ch.media and ch.media.live or false,
                sub = ch and ch.media and ch.media.sub,
                paused = ch and ch.media and ch.media.paused == true or false,
                pos = ch and ch.media and elapsedOf(ch.media) or 0,
                controllable = ch and IsControllable(ch.media) or false,
                canControl = State.canBroadcast and ch ~= nil and not ch.fixed
                    and (ch.owner == nil or ch.owner == myId),
            }
        elseif st.media then
            local m = st.media
            current = {
                mode = 'media', type = m.type, sub = m.sub, url = m.url, live = m.live or false,
                paused = m.paused == true, pos = elapsedOf(m),
                controllable = IsControllable(m), canControl = true,
            }
        end
    end

    local channels, mine = {}, nil
    for _, ch in ipairs(SortedChannels()) do
        local isMine = ch.owner ~= nil and ch.owner == myId
        if isMine then mine = ch.id end
        channels[#channels + 1] = {
            id = ch.id, label = ch.label, num = ch.num, fixed = ch.fixed,
            active = ch.media ~= nil, type = ch.media and ch.media.type, url = ch.media and ch.media.url,
            mine = isMine, foreign = ch.owner ~= nil and not isMine,
        }
    end
    return current, channels, mine
end

local function PushMenuState()
    if not Menu then return end
    local current, channels, mine = MenuState(Menu.key)
    SendNUIMessage({ action = 'updateMenu', data = { current = current, channels = channels, myChannel = mine } })
end

local function OpenMenu(e)
    if e then
        Menu = { key = e.key, label = e.label }
        Priority[e.grp] = e.key
        SyncScreens()
    else
        Menu = { key = nil, label = locale('st_bc_title') }
    end

    local current, channels, mine = MenuState(Menu.key)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openMenu',
        data = {
            label = Menu.label,
            noTv = Menu.key == nil,
            current = current,
            channels = channels,
            myChannel = mine,
            canBroadcast = State.canBroadcast,
            presets = Config.Presets,
            volume = Volume,
            seekStep = Config.SeekSeconds or 10,
            side = Config.UI and Config.UI.Side or 'right',
            t = UiStrings(),
        },
    })
end

-- 操作ウィンドウの位置と大きさ (画面に対する割合 0.0-1.0)
local function ComputeBrowseRect()
    local cfg = Config.BrowseWindow or {}
    local sw, sh = GetActiveScreenResolution()
    local w = math.max(0.3, math.min(0.95, cfg.Width or 0.7))
    local h = w * sw * H / (W * sh)          -- DUIと同じ縦横比にする
    if h > 0.82 then
        h = 0.82
        w = h * sh * W / (sw * H)
    end
    local cy = cfg.CenterY or 0.45
    cy = math.max(h / 2 + 0.01, math.min(0.99 - h / 2, cy))
    return { cx = 0.5, cy = cy, w = w, h = h }
end

local function EnterBrowse(key)
    local slot = FindSlot(key)
    if not slot or not slot.media or slot.media.type == 'nosignal' then
        Notify(locale('no_screen'), 'error')
        return
    end
    Menu = nil
    local r = ComputeBrowseRect()
    Browse = { slot = slot, key = key, rect = r }
    SendNUIMessage({
        action = 'openBrowse',
        data = {
            url = slot.media.url or '',
            rect = { left = r.cx - r.w / 2, top = r.cy - r.h / 2, width = r.w, height = r.h },
        },
    })
end

RegisterNUICallback('close', function(_, cb)
    CloseMenu()
    cb({})
end)

RegisterNUICallback('closeBrowse', function(_, cb)
    CloseBrowse()
    cb({})
end)

RegisterNUICallback('play', function(d, cb)
    if Menu and Menu.key then
        TriggerServerEvent('rensyu_tv:play', Menu.key, d.url, d.type, { live = d.live, loop = d.loop })
    end
    cb({})
end)

RegisterNUICallback('browseGo', function(d, cb)
    if Browse then
        TriggerServerEvent('rensyu_tv:play', Browse.key, d.url, 'auto', {})
    end
    cb({})
end)

RegisterNUICallback('tune', function(d, cb)
    if Menu and Menu.key then
        TriggerServerEvent('rensyu_tv:tune', Menu.key, d.channel)
    end
    cb({})
end)

RegisterNUICallback('off', function(_, cb)
    if Menu and Menu.key then
        TriggerServerEvent('rensyu_tv:off', Menu.key)
    end
    cb({})
end)

RegisterNUICallback('broadcast', function(d, cb)
    if Menu then
        TriggerServerEvent('rensyu_tv:broadcast', d.channel, d.label, d.url, d.type, { live = d.live, loop = d.loop })
    end
    cb({})
end)

RegisterNUICallback('stopChannel', function(d, cb)
    if Menu then
        TriggerServerEvent('rensyu_tv:stopChannel', d.channel)
    end
    cb({})
end)

RegisterNUICallback('control', function(d, cb)
    if Menu and Menu.key and type(d.action) == 'string' then
        local value = d.action == 'seek' and ((tonumber(d.value) or 0)) or nil
        TriggerServerEvent('rensyu_tv:control', Menu.key, d.action, value)
    end
    cb({})
end)

-- 自分の画面だけ、全員の再生位置に合わせ直す
RegisterNUICallback('resync', function(_, cb)
    cb({})
    if Menu and Menu.key then
        local s = FindSlot(Menu.key)
        if s then SendControl(s, true) end
    end
end)

-- Page title lookup (history / status / channel lists). The server fetches and caches it.
RegisterNUICallback('getTitle', function(d, cb)
    CreateThread(function()
        local title = type(d.url) == 'string' and lib.callback.await('rensyu_tv:title', false, d.url) or nil
        cb({ title = title or '' })
    end)
end)

RegisterNUICallback('setVolume', function(d, cb)
    Volume = math.max(0, math.min(100, math.floor(tonumber(d.value) or Volume)))
    SetResourceKvp('rensyu_tv_volume', tostring(Volume))
    for i = 1, SLOT_COUNT do
        if Slots[i] then Slots[i].vol = -1 end   -- 次のループで再送
    end
    cb({})
end)

-- 画面を窓表示にしてマウス操作 (どの映像でも可)
RegisterNUICallback('browse', function(_, cb)
    cb({})
    if Menu and Menu.key then EnterBrowse(Menu.key) end
end)

-- ブラウズ中のマウス操作を DUI へ転送
RegisterNUICallback('mouse', function(d, cb)
    cb({})
    if not Browse or not Browse.slot.grp then return end
    local dui = Browse.slot.dui
    local x = math.floor(math.max(0.0, math.min(1.0, d.x or 0)) * W)
    local y = math.floor(math.max(0.0, math.min(1.0, d.y or 0)) * H)

    SendDuiMouseMove(dui, x, y)
    if d.kind == 'down' then
        SendDuiMouseDown(dui, d.button or 'left')
    elseif d.kind == 'up' then
        SendDuiMouseUp(dui, d.button or 'left')
    elseif d.kind == 'wheel' then
        local dir = (d.dy or 0) > 0 and -1 or 1
        if Config.InvertScroll then dir = -dir end
        SendDuiMouseWheel(dui, dir * 100, 0)
    end
end)

-- ■ ブームボックス (ox_inventory のアイテムで設置する小道具) ----------------
local BCFG = Config.Boombox or {}
local BoomHash = BCFG.Model and GetHashKey(BCFG.Model) or nil
local BOOM_SLOT_COUNT = math.max(1, math.min(BCFG.MaxActive or 3, 8))

local function MyId()
    return GetPlayerServerId(PlayerId())
end

local function BoxFromEntity(entity)
    for _, b in pairs(Boxes) do
        if b.entity == entity then return b end
    end
end

local function NearbyBox(extra)
    local pc = GetEntityCoords(PlayerPedId())
    local best, bd
    for _, b in pairs(Boxes) do
        local d = #(pc - b.coords)
        if d <= (BCFG.InteractDistance or 2.0) + (extra or 0.0) and (not bd or d < bd) then
            best, bd = b, d
        end
    end
    return best, bd
end

-- 小道具の生成 / 削除 (近づくと出て、離れると消える)
local function SpawnBox(box)
    if not BoomHash or (box.entity and DoesEntityExist(box.entity)) then return end
    if not pcall(lib.requestModel, BoomHash, 5000) then
        print(('[rensyu_television] Failed to load model %s'):format(tostring(BCFG.Model)))
        return
    end
    if not Boxes[box.id] or not box.inside then   -- 読み込み中に離れた / 消えた
        SetModelAsNoLongerNeeded(BoomHash)
        return
    end
    local o = CreateObject(BoomHash, box.coords.x, box.coords.y, box.coords.z, false, false, false)
    SetEntityHeading(o, box.heading + 0.0)
    PlaceObjectOnGroundProperly(o)
    FreezeEntityPosition(o, true)
    box.entity = o
    SetModelAsNoLongerNeeded(BoomHash)
end

local function DespawnBox(box)
    if box.entity then
        if DoesEntityExist(box.entity) then DeleteEntity(box.entity) end
        box.entity = nil
    end
end

local function AddBox(data)
    local box = Boxes[data.id]
    if box then
        box.owner = data.owner
        box.media = stamp(data.media)
        return box
    end
    box = {
        id = data.id, owner = data.owner, coords = data.coords, heading = data.heading,
        media = stamp(data.media), range = BCFG.Range or 25.0, inside = false,
    }
    Boxes[data.id] = box
    box.point = lib.points.new({
        coords = box.coords,
        distance = Config.SpawnDistance,
        onEnter = function()
            box.inside = true
            CreateThread(function() SpawnBox(box) end)
        end,
        onExit = function()
            box.inside = false
            DespawnBox(box)
        end,
    })
    return box
end

local function RemoveBox(id)
    local box = Boxes[id]
    if not box then return end
    if BoxMenu == id then CloseMenu() end
    if box.point then box.point:remove() end
    DespawnBox(box)
    Boxes[id] = nil
end

-- ---- 音声スロット (映像なしの小さなDUI) ----
local function InitBoomSlot(i)
    if BoomSlots[i] then return BoomSlots[i] end
    local dui = CreateDui('about:blank', 480, 270)
    BoomSlots[i] = { idx = i, tag = 'b' .. i, audio = true, dui = dui, page = 'blank', loaded = false, vol = -1, occ = 1.0, occTarget = 1.0 }
    return BoomSlots[i]
end

local function ReleaseBoomSlot(sl)
    SetDuiUrl(sl.dui, 'about:blank')
    sl.boxId, sl.entry, sl.media, sl.sig, sl.rev = nil, nil, nil, nil, nil
    sl.page, sl.webUrl, sl.loaded, sl.vol = 'blank', nil, false, -1
    sl.occ, sl.occTarget, sl.occAt = 1.0, 1.0, nil
end

-- 近くで鳴っているブームボックスを、近い順に MaxActive 台まで再生する
local function SyncBoombox()
    local pc = GetEntityCoords(PlayerPedId())
    local list = {}
    for _, b in pairs(Boxes) do
        if b.media then
            local d = #(pc - b.coords)
            if d <= b.range then list[#list + 1] = { box = b, d = d } end
        end
    end
    table.sort(list, function(x, y) return x.d < y.d end)

    local want = {}
    for i = 1, math.min(#list, BOOM_SLOT_COUNT) do want[list[i].box.id] = list[i].box end

    for i = 1, BOOM_SLOT_COUNT do
        local sl = BoomSlots[i]
        if sl and sl.boxId and not want[sl.boxId] then ReleaseBoomSlot(sl) end
    end

    for id, box in pairs(want) do
        local slot
        for i = 1, BOOM_SLOT_COUNT do
            local sl = BoomSlots[i]
            if sl and sl.boxId == id then slot = sl break end
        end
        if not slot then
            for i = 1, BOOM_SLOT_COUNT do
                local sl = BoomSlots[i]
                if not sl or not sl.boxId then slot = InitBoomSlot(i) break end
            end
        end

        if slot then
            slot.boxId, slot.entry = id, box
            local sig = tostring(box.media.seq)
            if slot.sig ~= sig then
                slot.sig, slot.media, slot.rev = sig, box.media, box.media.rev or 0
                ApplyContent(slot)
            else
                slot.media = box.media
                if (slot.rev or 0) ~= (box.media.rev or 0) then
                    slot.rev = box.media.rev or 0
                    SendControl(slot, false)
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        SyncBoombox()
        Wait(500)
    end
end)

-- ---- 操作パネル ----
local function BoxState(box)
    local m = box.media
    if not m then return { mode = 'off' } end
    return {
        mode = 'media', type = m.type, sub = m.sub, url = m.url, live = m.live or false,
        paused = m.paused == true, pos = elapsedOf(m), controllable = IsControllable(m), canControl = true,
    }
end

local function OpenBoombox(box)
    if Menu or Browse or BoxMenu then return end
    BoxMenu = box.id
    StartBoxAnim(box)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openBoombox',
        data = {
            id = box.id,
            label = locale('label_boombox'),
            current = BoxState(box),
            canPickup = BCFG.PickupAnyone ~= false or box.owner == MyId(),
            presets = Config.Presets,
            volume = Volume,
            seekStep = Config.SeekSeconds or 10,
            side = Config.UI and Config.UI.Side or 'right',
            t = UiStrings(),
        },
    })
end

local function PushBoxState()
    local box = BoxMenu and Boxes[BoxMenu]
    if box then
        SendNUIMessage({ action = 'updateBoombox', data = { current = BoxState(box) } })
    end
end

local function PickupBox(box)
    local ok = lib.progressCircle({
        duration = 1200, label = locale('picking'), position = 'bottom', canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'pickup_object', clip = 'pickup_low' },
    })
    if ok then TriggerServerEvent('rensyu_tv:boombox:pickup', box.id) end
end

RegisterNUICallback('bx_play', function(d, cb)
    if BoxMenu then
        TriggerServerEvent('rensyu_tv:boombox:play', BoxMenu, d.url, d.type, { live = d.live, loop = d.loop })
    end
    cb({})
end)

RegisterNUICallback('bx_stop', function(_, cb)
    if BoxMenu then TriggerServerEvent('rensyu_tv:boombox:stop', BoxMenu) end
    cb({})
end)

RegisterNUICallback('bx_control', function(d, cb)
    if BoxMenu and type(d.action) == 'string' then
        local value = d.action == 'seek' and (tonumber(d.value) or 0) or nil
        TriggerServerEvent('rensyu_tv:boombox:control', BoxMenu, d.action, value)
    end
    cb({})
end)

RegisterNUICallback('bx_resync', function(_, cb)
    cb({})
    if not BoxMenu then return end
    for i = 1, BOOM_SLOT_COUNT do
        local sl = BoomSlots[i]
        if sl and sl.boxId == BoxMenu then SendControl(sl, true) end
    end
end)

RegisterNUICallback('bx_pickup', function(_, cb)
    cb({})
    local box = BoxMenu and Boxes[BoxMenu]
    if not box then return end
    CloseMenu()
    CreateThread(function() PickupBox(box) end)
end)

-- ox_inventory のアイテムを使ったとき (items.lua の client.event から呼ばれる)
RegisterNetEvent('rensyu_television:useBoombox', function()
    if not BCFG.Enabled then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) or IsPedRagdoll(ped) then
        return Notify(locale('cannot_now'), 'error')
    end

    local mine = 0
    for _, b in pairs(Boxes) do
        if b.owner == MyId() then mine = mine + 1 end
    end
    if mine >= (BCFG.MaxPerPlayer or 1) then
        return Notify(locale('err_box_limit'), 'error')
    end

    local front = GetOffsetFromEntityInWorldCoords(ped, 0.0, BCFG.PlaceDistance or 0.9, 0.0)
    local found, gz = GetGroundZFor_3dCoord(front.x, front.y, front.z + 1.0, false)
    local pos = vector3(front.x, front.y, found and gz or (front.z - 0.9))
    local heading = (GetEntityHeading(ped) + (BCFG.HeadingOffset or 180.0)) % 360.0

    local ok = lib.progressCircle({
        duration = 1500, label = locale('placing'), position = 'bottom', canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'pickup_object', clip = 'pickup_low' },
    })
    if ok then TriggerServerEvent('rensyu_tv:boombox:place', pos, heading) end
end)

-- ■ 操作入力 ---------------------------------------------------------------
local function UsingOxTarget()
    return Config.UseOxTarget and GetResourceState('ox_target') == 'started'
end

-- E キー (ox_target を使わない場合): ox_lib のキーバインド + TextUI
local function NearbyTV(extra)
    local e = Nearby[1]
    if e and #(GetEntityCoords(PlayerPedId()) - e.coords) <= Config.InteractDistance + (extra or 0.0) then
        return e
    end
end

-- いちばん近い操作対象 (テレビ or ブームボックス)
local function Nearest()
    local e = NearbyTV()
    local b, bd = NearbyBox()
    if b then
        local ed = e and #(GetEntityCoords(PlayerPedId()) - e.coords) or math.huge
        if bd < ed then return 'box', b end
    end
    if e then return 'tv', e end
end

lib.addKeybind({
    name = 'rensyu_tv_interact',
    description = locale('key_desc'),
    defaultMapper = 'keyboard',
    defaultKey = Config.InteractKey or 'E',
    onReleased = function()
        if Menu or Browse or BoxMenu or UsingOxTarget() then return end
        local kind, obj = Nearest()
        if kind == 'box' then OpenBoombox(obj)
        elseif kind == 'tv' then OpenMenu(obj) end
    end,
})

local shownText = nil
local function HideHelpText()
    if shownText then
        local open, text = lib.isTextUIOpen()
        if open and text == shownText then lib.hideTextUI() end
        shownText = nil
    end
end

CreateThread(function()
    while true do
        local want
        if not Menu and not Browse and not BoxMenu and not UsingOxTarget() then
            local kind = Nearest()
            if kind == 'box' then want = locale('help_boom')
            elseif kind == 'tv' then want = locale('help_tv') end
        end
        if want and want ~= shownText then
            HideHelpText()
            lib.showTextUI(want)
            shownText = want
        elseif not want then
            HideHelpText()
        end
        Wait(want and 200 or 400)
    end
end)

RegisterCommand(Config.Command, function()
    local e = NearbyTV(1.5)
    if e and not Menu and not Browse then
        OpenMenu(e)
    else
        Notify(locale('no_tv'), 'error')
    end
end, false)

if Config.BroadcastCommand then
    RegisterCommand(Config.BroadcastCommand, function()
        if not Menu and not Browse then OpenMenu(nil) end
    end, false)
end

-- ■ ox_target -------------------------------------------------------------
local function EntryFor(entity)
    for _, e in ipairs(Nearby) do
        if e.entity == entity then return e end
    end
    local model = GetEntityModel(entity)
    local info = ModelSet[model]
    if not info then return nil end
    return MakeEntry(entity, model, info, GetEntityCoords(PlayerPedId()))
end

local function TargetOptions()
    return {
        {
            name = 'rensyu_tv_menu',
            icon = 'fa-solid fa-tv',
            label = locale('target_tv'),
            distance = Config.TargetDistance,
            canInteract = function() return not Menu and not Browse end,
            onSelect = function(data)
                local e = EntryFor(data.entity)
                if e then OpenMenu(e) end
            end,
        },
    }
end

local TargetNames = { 'rensyu_tv_menu' }
local TargetModels = {}
for hash in pairs(ModelSet) do TargetModels[#TargetModels + 1] = hash end

local BoomTargetNames = { 'rensyu_boombox_open', 'rensyu_boombox_pickup' }

local function BoomTargetOptions()
    local dist = BCFG.InteractDistance or 2.0
    return {
        {
            name = 'rensyu_boombox_open', icon = 'fa-solid fa-music', label = locale('target_boom_open'), distance = dist,
            canInteract = function() return not Menu and not Browse and not BoxMenu end,
            onSelect = function(data)
                local b = BoxFromEntity(data.entity)
                if b then OpenBoombox(b) end
            end,
        },
        {
            name = 'rensyu_boombox_pickup', icon = 'fa-solid fa-hand', label = locale('target_boom_pickup'), distance = dist,
            canInteract = function(entity)
                local b = BoxFromEntity(entity)
                return b ~= nil and not Menu and not Browse and not BoxMenu
                    and (BCFG.PickupAnyone ~= false or b.owner == MyId())
            end,
            onSelect = function(data)
                local b = BoxFromEntity(data.entity)
                if b then PickupBox(b) end
            end,
        },
    }
end

local function RegisterTargets()
    if not UsingOxTarget() then return end
    exports.ox_target:addModel(TargetModels, TargetOptions())
    if BCFG.Enabled and BoomHash then
        exports.ox_target:addModel(BoomHash, BoomTargetOptions())
    end
end

CreateThread(function()
    if not Config.UseOxTarget then return end
    while GetResourceState('ox_target') ~= 'started' do Wait(500) end
    RegisterTargets()
end)

AddEventHandler('onResourceStart', function(res)
    if res == 'ox_target' then
        Wait(500)
        RegisterTargets()
    end
end)

-- 対応していないテレビのモデル(ハッシュ)を調べるデバッグコマンド
RegisterCommand('tvmodel', function()
    local pc = GetEntityCoords(PlayerPedId())
    local best, bd
    for _, obj in ipairs(GetGamePool('CObject')) do
        local d = #(pc - GetEntityCoords(obj))
        if d < 3.0 and (not bd or d < bd) then best, bd = obj, d end
    end
    if not best then return Notify(locale('no_object'), 'error') end
    local hash = GetEntityModel(best)
    local msg = ('model hash: %d (0x%X)'):format(hash, hash & 0xFFFFFFFF)
    print('[rensyu_television] ' .. msg)
    Notify(locale('model_hash_msg', msg))
end, false)

-- ■ サーバーからの同期 ---------------------------------------------------------
local function stampChannel(ch)
    if ch and ch.media then stamp(ch.media) end
    return ch
end

local function ApplyFullSync(data)
    State.channels, State.tvs, State.canBroadcast = {}, {}, data.canBroadcast == true
    for id, ch in pairs(data.channels or {}) do State.channels[id] = stampChannel(ch) end
    for key, st in pairs(data.tvs or {}) do
        if st.media then stamp(st.media) end
        State.tvs[key] = st
    end

    for id in pairs(Boxes) do
        if not (data.boomboxes and data.boomboxes[id]) then RemoveBox(id) end
    end
    for _, b in pairs(data.boomboxes or {}) do AddBox(b) end

    SyncScreens()
    SyncBoombox()
    PushMenuState()
end

RegisterNetEvent('rensyu_tv:setBoombox', function(id, data)
    if data then AddBox(data) else RemoveBox(id) end
    SyncBoombox()
    PushBoxState()
end)

RegisterNetEvent('rensyu_tv:setTV', function(key, st)
    if st and st.media then stamp(st.media) end
    State.tvs[key] = st
    SyncScreens()
    PushMenuState()
end)

RegisterNetEvent('rensyu_tv:setChannel', function(id, ch)
    local old = State.channels[id]
    State.channels[id] = stampChannel(ch)

    -- 画面上に「CH xx 放送開始/終了」を表示
    local text
    if ch and ch.media then
        text = locale('ch_live', ch.num, ch.label)
    elseif old then
        text = locale('ch_ended', old.num, old.label)
    end

    SyncScreens()
    PushMenuState()

    if text then
        for i = 1, SLOT_COUNT do
            local s = Slots[i]
            if s and s.grp and s.loaded and s.page == 'player'
                and (s.chId == id or (s.media and s.media.type == 'nosignal')) then
                SendTo(s, { action = 'notify', text = text })
            end
        end
    end
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(200) end
    local data = lib.callback.await('rensyu_tv:sync', false)   -- ox_lib callback
    if data then ApplyFullSync(data) end
end)

-- ■ 後片付け -----------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    StopBoxAnim()
    SetNuiFocus(false, false)
    HideHelpText()
    for _, p in ipairs(Points) do p:remove() end
    if GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeModel(TargetModels, TargetNames) end)
        if BoomHash then
            pcall(function() exports.ox_target:removeModel(BoomHash, BoomTargetNames) end)
        end
    end
    for _, b in pairs(Boxes) do
        if b.point then b.point:remove() end
        DespawnBox(b)
    end
    for i = 1, 8 do
        local sl = BoomSlots[i]
        if sl then DestroyDui(sl.dui) end
    end
    for entity in pairs(Spawned) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    for i = 1, SLOT_COUNT do
        local s = Slots[i]
        if s then
            DestroyDui(s.dui)
            if s.sf then pcall(SetScaleformMovieAsNoLongerNeeded, s.sf) end
        end
    end
end)
