// Playback page loaded into the DUI. Controlled from Lua with SendDuiMessage.
const RES = location.hostname.replace(/^cfx-nui-/, '');
const SLOT = new URLSearchParams(location.search).get('slot') || '0';   // TV: '1'...  boombox: 'b1'...
const $ = (id) => document.getElementById(id);

// Translations are sent from Lua with every message (msg.t)
let TR = {};
const tr = (key, fallback) => (TR[key] != null && TR[key] !== '' ? TR[key] : fallback);
const stage = $('stage');

let kind = null;          // 'youtube' | 'twitch' | 'video' | 'image' | null
let player = null;
let volume = 50;          // 0-100
let wantPaused = false;   // whether the server state is paused
let yt = { Language: 'ja', Captions: false, PreferAudioLanguage: true };
const ytQueue = [];

window.onYouTubeIframeAPIReady = () => { ytQueue.splice(0).forEach((f) => f()); };

function fmtTime(sec) {
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return `${h}h${m}m${s}s`;
}

// --- Fallback: videos that cannot be embedded (owner disabled embedding, API blocked, ...) are opened
// as the normal YouTube / Twitch page instead. Volume / pause sync do not work on those pages.
let fbTimer = null;
function clearFbTimer() { if (fbTimer) { clearTimeout(fbTimer); fbTimer = null; } }
function armFallback(ms, url) { clearFbTimer(); fbTimer = setTimeout(() => goFallback(url), ms); }
function goFallback(url) {
  clearFbTimer();
  if (!url) return;
  fetch(`https://${RES}/pageFallback`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ slot: SLOT, url }),
  }).catch(() => { location.href = url; });
}
function ytWatchUrl(m, start) {
  const lang = yt.Language ? '&hl=' + encodeURIComponent(yt.Language) : '';
  if (m.sub === 'channel') return `https://www.youtube.com/channel/${encodeURIComponent(m.ref)}/live`;
  if (m.sub === 'playlist') return `https://www.youtube.com/playlist?list=${encodeURIComponent(m.ref)}${lang}`;
  return `https://www.youtube.com/watch?v=${encodeURIComponent(m.ref)}${start > 0 ? '&t=' + start + 's' : ''}${lang}`;
}
function twitchPageUrl(m, start) {
  if (m.sub === 'vod') return `https://www.twitch.tv/videos/${encodeURIComponent(m.ref)}${start > 0 ? '?t=' + fmtTime(start) : ''}`;
  if (m.sub === 'clip') return `https://clips.twitch.tv/${encodeURIComponent(m.ref)}`;
  return `https://www.twitch.tv/${encodeURIComponent(m.ref)}`;
}

function clearStage() {
  clearFbTimer();
  try { if (player && player.destroy) player.destroy(); } catch (_) {}
  player = null;
  kind = null;
  stage.replaceChildren();
  $('error').classList.add('hidden');
}

function showError(text) {
  $('error').textContent = text;
  $('error').classList.remove('hidden');
}

function setChannel(ch) {
  const ov = $('overlay');
  if (ch && ch.num) {
    $('ov-num').textContent = 'CH ' + String(ch.num).padStart(2, '0');
    $('ov-label').textContent = ch.label || '';
    ov.classList.remove('hidden');
  } else {
    ov.classList.add('hidden');
  }
}

function makeTarget() {
  const d = document.createElement('div');
  d.className = 'fill';
  stage.appendChild(d);
  return d;
}

// ---- YouTube captions / audio language ----
function langRegex(lang) {
  if (!lang) return null;
  const l = String(lang).toLowerCase();
  const names = { ja: 'japanese|日本語', en: 'english|英語', ko: 'korean|한국어', zh: 'chinese|中文|中国語' };
  return new RegExp('(^|[^a-z])' + l + '([^a-z]|$)' + (names[l] ? '|' + names[l] : ''), 'i');
}

let audioChecks = 0;
function pickAudio(p) {
  // unofficial API: does nothing where it is not available
  try {
    const re = langRegex(yt.Language);
    if (!re || typeof p.getAvailableAudioTracks !== 'function' || typeof p.setAudioTrack !== 'function') return;
    const tracks = p.getAvailableAudioTracks() || [];
    if (tracks.length < 2) return;
    const want = tracks.find((t) => re.test(JSON.stringify(t)));
    if (!want) return;
    const cur = typeof p.getAudioTrack === 'function' ? p.getAudioTrack() : null;
    if (!cur || JSON.stringify(cur) !== JSON.stringify(want)) p.setAudioTrack(want);
  } catch (_) {}
}

function applyYT(p) {
  try {
    if (!yt.Captions) { p.unloadModule('captions'); p.unloadModule('cc'); }
  } catch (_) {}
  if (yt.PreferAudioLanguage && audioChecks < 3) { audioChecks++; pickAudio(p); }
}

function setMedia(msg) {
  clearStage();
  $('nosignal').classList.add('hidden');
  if (typeof msg.volume === 'number') volume = msg.volume;
  if (msg.yt) yt = { ...yt, ...msg.yt };
  audioChecks = 0;
  wantPaused = !!msg.paused;
  document.body.classList.toggle('audioonly', !!msg.audioOnly);   // boomboxes play sound only
  setChannel(msg.channel);

  const m = msg.media;
  const elapsed = Math.floor(msg.elapsed || 0);
  const start = (!m.live && elapsed >= 3) ? elapsed : 0;
  const parents = Array.from(new Set([location.hostname, ...(msg.parents || [])]));

  if (m.type === 'image') {
    kind = 'image';
    const img = new Image();
    img.onerror = () => showError(tr('pl_err_image', "Couldn't load the image"));
    img.src = m.url;
    stage.appendChild(img);

  } else if (m.type === 'video') {
    kind = 'video';
    const v = document.createElement('video');
    v.autoplay = true; v.loop = !!m.loop; v.playsInline = true;
    v.volume = Math.max(0, Math.min(1, volume / 100));
    v.onerror = () => showError(tr('pl_err_video', "Couldn't load the video"));
    v.addEventListener('loadedmetadata', () => {
      if (start > 0 && isFinite(v.duration)) v.currentTime = m.loop ? start % v.duration : Math.min(start, v.duration);
      if (wantPaused) return;
      v.play().catch(() => { v.muted = true; v.play().catch(() => {}); });
    });
    v.src = m.url;
    stage.appendChild(v);
    player = v;

  } else if (m.type === 'audio') {
    kind = 'audio';
    const card = document.createElement('div');
    card.className = 'audiocard';
    let name = '';
    try { name = decodeURIComponent((m.url.split('?')[0].split('/').pop() || '').trim()); } catch (_) {}
    card.innerHTML = '<div class="note">♪</div><div class="t"></div><div class="n"></div>';
    card.querySelector('.t').textContent = tr('pl_audio_playing', 'Playing audio');
    card.querySelector('.n').textContent = name;
    stage.appendChild(card);
    const a = document.createElement('audio');
    a.autoplay = true; a.loop = !!m.loop;
    a.volume = Math.max(0, Math.min(1, volume / 100));
    a.onerror = () => showError(tr('pl_err_audio', "Couldn't load the audio"));
    a.addEventListener('loadedmetadata', () => {
      if (start > 0 && isFinite(a.duration)) a.currentTime = m.loop ? start % a.duration : Math.min(start, a.duration);
      if (wantPaused) return;
      a.play().catch(() => { a.muted = true; a.play().catch(() => {}); });
    });
    a.src = m.url;
    stage.appendChild(a);
    player = a;

  } else if (m.type === 'youtube') {
    kind = 'youtube';
    const target = makeTarget();
    const create = () => {
      const events = {
        onReady: (e) => { clearFbTimer(); e.target.setVolume(volume); e.target.unMute(); e.target.playVideo(); applyYT(e.target); },
        onStateChange: (e) => {
          if (e.data === YT.PlayerState.PLAYING) {
            e.target.unMute(); e.target.setVolume(volume); applyYT(e.target);
            if (wantPaused) e.target.pauseVideo();
          }
          else if (e.data === YT.PlayerState.ENDED && m.loop && m.sub === 'video') e.target.playVideo();
        },
        onError: (e) => {
          // 101 / 150: the owner disabled embedding -> open the normal YouTube page
          if (e && (e.data === 101 || e.data === 150)) goFallback(ytWatchUrl(m, start));
          else showError(tr('pl_err_youtube', "Couldn't play this YouTube video"));
        },
      };
      const vars = { autoplay: 1, controls: 0, rel: 0, modestbranding: 1, playsinline: 1,
                     disablekb: 1, iv_load_policy: 3, fs: 0, start: start,
                     cc_load_policy: yt.Captions ? 1 : 0 };
      if (yt.Language) { vars.hl = yt.Language; vars.cc_lang_pref = yt.Language; }
      if (m.sub === 'video') {
        if (m.loop) { vars.loop = 1; vars.playlist = m.ref; }
        player = new YT.Player(target, { width: '100%', height: '100%', videoId: m.ref, playerVars: vars, events });
      } else if (m.sub === 'playlist') {
        vars.listType = 'playlist'; vars.list = m.ref;
        player = new YT.Player(target, { width: '100%', height: '100%', playerVars: vars, events });
      } else { // live channel
        const f = document.createElement('iframe');
        f.className = 'fill';
        f.allow = 'autoplay; encrypted-media';
        f.src = 'https://www.youtube.com/embed/live_stream?channel=' + encodeURIComponent(m.ref) +
          '&autoplay=1&controls=0&rel=0&playsinline=1&cc_load_policy=' + (yt.Captions ? 1 : 0) +
          (yt.Language ? '&hl=' + encodeURIComponent(yt.Language) + '&cc_lang_pref=' + encodeURIComponent(yt.Language) : '') +
          '&enablejsapi=1&origin=' + encodeURIComponent(location.origin);
        stage.replaceChildren(f);
        player = new YT.Player(f, { events });
      }
    };
    armFallback(12000, ytWatchUrl(m, start));   // API blocked / player never became ready
    if (window.YT && YT.Player) create(); else ytQueue.push(create);

  } else if (m.type === 'twitch') {
    kind = 'twitch';
    if (m.sub === 'clip') {            // clips: open the clip page directly (no volume control)
      kind = null;
      goFallback(twitchPageUrl(m, start));
      return;
    }
    if (typeof Twitch === 'undefined' || !Twitch.Player) { goFallback(twitchPageUrl(m, start)); return; }
    const target = makeTarget();
    const opts = { width: '100%', height: '100%', parent: parents, autoplay: true, muted: false };
    if (m.sub === 'vod') { opts.video = 'v' + m.ref; if (start > 0) opts.time = fmtTime(start); }
    else opts.channel = m.ref;
    player = new Twitch.Player(target, opts);
    armFallback(12000, twitchPageUrl(m, start));   // embed refused (parent mismatch, blocked, ...)
    const apply = () => {
      try { player.setMuted(false); player.setVolume(volume / 100); if (wantPaused) player.pause(); } catch (_) {}
    };
    player.addEventListener(Twitch.Player.READY, () => { clearFbTimer(); apply(); try { player.play(); } catch (_) {} });
    player.addEventListener(Twitch.Player.PLAYING, apply);
  }
}

// pause / play / seek
function control(msg) {
  wantPaused = !!msg.paused;
  let pos = Math.max(0, msg.pos || 0);
  const off = (cur) => msg.force || Math.abs(cur - pos) > 1.5;
  try {
    if (kind === 'youtube' && player && player.getCurrentTime) {
      if (off(player.getCurrentTime())) player.seekTo(pos, true);
      if (wantPaused) player.pauseVideo(); else player.playVideo();
    } else if (kind === 'twitch' && player && player.seek) {
      if (off(player.getCurrentTime())) player.seek(pos);
      if (wantPaused) player.pause(); else player.play();
    } else if ((kind === 'video' || kind === 'audio') && player) {
      if (isFinite(player.duration) && player.loop) pos = pos % player.duration;
      if (off(player.currentTime)) player.currentTime = pos;
      if (wantPaused) player.pause(); else player.play().catch(() => {});
    }
  } catch (_) {}
}

function setNoSignal(msg) {
  clearStage();
  $('ns-title').textContent = tr('pl_ns_title', 'NO SIGNAL');
  $('ns-sub').textContent = TR.pl_ns_sub != null ? TR.pl_ns_sub : '';
  setChannel(msg.channel);
  $('nosignal').classList.remove('hidden');
}

function setVolume(v) {
  volume = Math.max(0, Math.min(100, v));
  try {
    if (kind === 'youtube' && player && player.setVolume) { player.unMute(); player.setVolume(volume); }
    else if (kind === 'twitch' && player && player.setVolume) { player.setMuted(volume === 0); player.setVolume(volume / 100); }
    else if ((kind === 'video' || kind === 'audio') && player) { player.volume = volume / 100; }
  } catch (_) {}
}

let bannerTimer = null;
function notify(text) {
  const b = $('banner');
  b.textContent = text;
  b.classList.remove('hidden');
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => b.classList.add('hidden'), 4000);
}

window.addEventListener('message', (e) => {
  let d = e.data;
  if (typeof d === 'string') { try { d = JSON.parse(d); } catch (_) { return; } }
  if (!d) return;
  if (d.t) TR = d.t;
  if (d.action === 'media') setMedia(d);
  else if (d.action === 'nosignal') setNoSignal(d);
  else if (d.action === 'control') control(d);
  else if (d.action === 'volume') setVolume(d.value);
  else if (d.action === 'notify') notify(d.text);
});

// tell Lua the page has loaded
fetch(`https://${RES}/pageLoaded`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ slot: SLOT }),
}).catch(() => {});
