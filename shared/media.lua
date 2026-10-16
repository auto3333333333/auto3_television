-- URLの判定・検証・埋め込みURL生成 (client / server 共通)
Media = {}

local IMAGE_EXT = { png = true, jpg = true, jpeg = true, gif = true, webp = true, bmp = true, svg = true, avif = true }
local VIDEO_EXT = { mp4 = true, webm = true, ogv = true, mov = true, m4v = true }
local AUDIO_EXT = { mp3 = true, ogg = true, oga = true, wav = true, m4a = true, aac = true, flac = true, opus = true, weba = true }

local function hostIs(h, domain)
    return h == domain or h:sub(-(#domain + 1)) == '.' .. domain
end

function Media.UrlEncode(s)
    return (tostring(s):gsub('[^%w%-_%.~]', function(c)
        return string.format('%%%02X', string.byte(c))
    end))
end

local function normalize(raw)
    if type(raw) ~= 'string' then return nil end
    raw = raw:gsub('^%s+', ''):gsub('%s+$', '')
    if raw == '' or #raw > (Config.MaxUrlLength or 512) then return nil end
    if raw:find('[%c%s]') then return nil end

    local lower = raw:lower()
    if not lower:match('^https?://') then
        -- "youtube.com/..." のようなスキーム無し入力のみ許可 (javascript: 等は拒否)
        if lower:match('^[%w%-%.]+%.%a%a+') and not lower:match('^%a[%w+.-]*:') then
            raw = 'https://' .. raw
        else
            return nil
        end
    end

    local authority = raw:match('^[Hh][Tt][Tt][Pp][Ss]?://([^/?#]*)')
    if not authority or authority == '' or authority:find('@') then return nil end
    return raw
end

local function hostOf(url)
    local h = url:match('^[Hh][Tt][Tt][Pp][Ss]?://([^/?#:]+)')
    return h and h:lower() or ''
end

local function extOf(url)
    local path = url:match('^https?://[^/?#]+([^?#]*)') or ''
    local e = path:match('%.(%w+)$')
    return e and e:lower() or nil
end

-- "90", "90s", "1m30s", "1h2m3s" -> seconds
local function parseTime(str)
    if not str or str == '' then return nil end
    if str:match('^%d+$') then return tonumber(str) end
    local h = tonumber(str:match('(%d+)h')) or 0
    local m = tonumber(str:match('(%d+)m')) or 0
    local sec = tonumber(str:match('(%d+)s')) or 0
    local total = h * 3600 + m * 60 + sec
    return total > 0 and total or nil
end

local function parseYouTube(url, h)
    local isYT = hostIs(h, 'youtube.com') or hostIs(h, 'youtube-nocookie.com') or h == 'youtu.be'
    if not isYT then return nil end

    local startAt = parseTime(url:match('[?&]t=([%w]+)') or url:match('[?&]start=(%d+)'))

    local id
    if h == 'youtu.be' then
        id = url:match('^https?://youtu%.be/([%w_%-]+)')
    else
        id = url:match('[?&]v=([%w_%-]+)') or url:match('/embed/([%w_%-]+)')
            or url:match('/shorts/([%w_%-]+)') or url:match('/live/([%w_%-]+)')
            or url:match('/v/([%w_%-]+)')
        if id == 'live_stream' or id == 'videoseries' then id = nil end
    end
    if id then
        return { type = 'youtube', sub = 'video', ref = id, startAt = startAt }
    end

    local channel = url:match('/channel/(UC[%w_%-]+)') or url:match('[?&]channel=(UC[%w_%-]+)')
    if channel then
        return { type = 'youtube', sub = 'channel', ref = channel, live = true }
    end

    local list = url:match('[?&]list=([%w_%-]+)')
    if list then
        return { type = 'youtube', sub = 'playlist', ref = list }
    end
    return nil
end

local RESERVED_TWITCH = {
    videos = true, directory = true, downloads = true, jobs = true, store = true, turbo = true, settings = true,
    popout = true, embed = true, p = true, ['subscriptions'] = true, wallet = true, friends = true,
}

local function parseTwitch(url, h)
    local startAt = parseTime(url:match('[?&]t=([%w]+)') or url:match('[?&]time=([%w]+)'))

    if h == 'clips.twitch.tv' then
        local slug = url:match('[?&]clip=([%w_%-]+)') or url:match('^https?://clips%.twitch%.tv/([%w_%-]+)')
        if slug and slug ~= 'embed' then return { type = 'twitch', sub = 'clip', ref = slug } end
        return nil
    end
    if not hostIs(h, 'twitch.tv') then return nil end

    -- player.twitch.tv/?channel=x / ?video=v123 / ?clip=slug (embed-style links)
    local qVideo = url:match('[?&]video=v?(%d+)')
    if qVideo then return { type = 'twitch', sub = 'vod', ref = qVideo, startAt = startAt } end
    local qClip = url:match('[?&]clip=([%w_%-]+)')
    if qClip then return { type = 'twitch', sub = 'clip', ref = qClip } end
    local qChannel = url:match('[?&]channel=([%w_]+)')
    if qChannel then return { type = 'twitch', sub = 'channel', ref = qChannel, live = true } end

    local vod = url:match('/videos/(%d+)') or url:match('/v/(%d+)')
    if vod then return { type = 'twitch', sub = 'vod', ref = vod, startAt = startAt } end

    local clip = url:match('/clip/([%w_%-]+)')
    if clip then return { type = 'twitch', sub = 'clip', ref = clip } end

    -- twitch.tv/popout/<channel>/chat , twitch.tv/embed/<channel>
    local pop = url:match('/popout/([%w_]+)') or url:match('/embed/([%w_]+)')
    if pop then return { type = 'twitch', sub = 'channel', ref = pop, live = true } end

    local ch = url:match('^https?://[^/]+/([%w_]+)')
    if ch and not RESERVED_TWITCH[ch:lower()] then
        return { type = 'twitch', sub = 'channel', ref = ch, live = true }
    end
    return nil
end

-- raw: 入力URL / forced: auto|youtube|twitch|web|image|video / opts: { live, loop }
-- 成功: mediaテーブル  失敗: nil, エラーメッセージ
function Media.Parse(raw, forced, opts)
    opts = opts or {}
    local url = normalize(raw)
    if not url then return nil, locale('err_url_invalid') end

    local h = hostOf(url)
    local lowerUrl = url:lower()
    for _, w in ipairs(Config.BannedWords or {}) do
        if w ~= '' and lowerUrl:find(w:lower(), 1, true) then
            return nil, locale('err_url_banned')
        end
    end
    for _, b in ipairs(Config.BlockedHosts or {}) do
        if hostIs(h, b:lower()) then return nil, locale('err_host_blocked') end
    end

    local valid = { auto = true, youtube = true, twitch = true, web = true, image = true, video = true, audio = true }
    if not valid[forced] then forced = 'auto' end

    local m
    if forced == 'auto' or forced == 'youtube' then m = parseYouTube(url, h) end
    if not m and (forced == 'auto' or forced == 'twitch') then m = parseTwitch(url, h) end

    if not m then
        if forced == 'youtube' then return nil, locale('err_not_youtube') end
        if forced == 'twitch' then return nil, locale('err_not_twitch') end
        local t = forced
        if t == 'auto' then
            local ext = extOf(url)
            t = (ext and IMAGE_EXT[ext] and 'image') or (ext and VIDEO_EXT[ext] and 'video')
                or (ext and AUDIO_EXT[ext] and 'audio') or 'web'
        end
        m = { type = t }
    end

    m.url = url
    m.loop = opts.loop == true
    if opts.live == true then m.live = true end
    return m
end

-- Add hl=<language> when opening YouTube / Google pages
function Media.WebUrl(url)
    local h = hostOf(url)
    local isTarget = hostIs(h, 'youtube.com') or h:match('^[%w%.]*google%.[%a%.]+$') ~= nil
    local lang = Config.YouTube and Config.YouTube.Language
    if lang == 'auto' then lang = GetConvar('ox:locale', 'en') end
    if isTarget and lang and lang ~= '' and not url:find('[?&]hl=') then
        local base, frag = url:match('^([^#]*)(#?.*)$')
        base = base .. (base:find('?', 1, true) and '&' or '?') .. 'hl=' .. lang
        return base .. frag
    end
    return url
end
