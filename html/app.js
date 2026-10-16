const $ = (id) => document.getElementById(id);

function post(name, data) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data || {}),
  }).catch(() => {});
}

/* ---------- translations (sent from Lua with every open message) ---------- */
let TR = {};
const T = (key, ...args) => {
  let s = TR[key] != null ? TR[key] : key;
  args.forEach((a) => { s = s.replace('%s', () => a); });
  return s;
};

/* ---------- icons (lucide 24x24 strokes) ---------- */
const ICONS = {
  'play': '<polygon points="6 3 20 12 6 21 6 3"/>',
  'pause': '<rect x="14" y="4" width="4" height="16" rx="1"/><rect x="6" y="4" width="4" height="16" rx="1"/>',
  'skip-back': '<polygon points="19 20 9 12 19 4 19 20"/><line x1="5" x2="5" y1="19" y2="5"/>',
  'rewind': '<polygon points="11 19 2 12 11 5 11 19"/><polygon points="22 19 13 12 22 5 22 19"/>',
  'fast-forward': '<polygon points="13 19 22 12 13 5 13 19"/><polygon points="2 19 11 12 2 5 2 19"/>',
  'refresh-cw': '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
  'power': '<path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.77.04"/>',
  'tv': '<rect width="20" height="15" x="2" y="7" rx="2" ry="2"/><polyline points="17 2 12 7 7 2"/>',
  'radio': '<path d="M4.9 19.1C1 15.2 1 8.8 4.9 4.9"/><path d="M7.8 16.2c-2.3-2.3-2.3-6.1 0-8.5"/><circle cx="12" cy="12" r="2"/><path d="M16.2 7.8c2.3 2.3 2.3 6.1 0 8.5"/><path d="M19.1 4.9C23 8.8 23 15.1 19.1 19"/>',
  'mouse-pointer': '<path d="M4.037 4.688a.495.495 0 0 1 .651-.651l16 6.5a.5.5 0 0 1-.063.947l-6.124 1.58a2 2 0 0 0-1.438 1.435l-1.579 6.126a.5.5 0 0 1-.947.063z"/>',
  'volume-2': '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>',
  'x': '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
  'square': '<rect width="18" height="18" x="3" y="3" rx="2"/>',
  'package': '<path d="m7.5 4.27 9 5.15"/><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/>',
  'lock': '<rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
  'user': '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  'speaker': '<rect width="16" height="20" x="4" y="2" rx="2"/><circle cx="12" cy="14" r="4"/><line x1="12" x2="12.01" y1="6" y2="6"/>',
  'music': '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
  'link': '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  'globe': '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
  'image': '<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>',
  'film': '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M7 3v18"/><path d="M3 7.5h4"/><path d="M3 12h18"/><path d="M3 16.5h4"/><path d="M17 3v18"/><path d="M17 7.5h4"/><path d="M17 16.5h4"/>',
  'youtube': '<path d="M2.5 17a24.12 24.12 0 0 1 0-10 2 2 0 0 1 1.4-1.4 49.56 49.56 0 0 1 16.2 0A2 2 0 0 1 21.5 7a24.12 24.12 0 0 1 0 10 2 2 0 0 1-1.4 1.4 49.55 49.55 0 0 1-16.2 0A2 2 0 0 1 2.5 17"/><path d="m10 15 5-3-5-3z"/>',
  'twitch': '<path d="M21 2H3v16h5v4l4-4h5l4-4V2z"/><path d="M11 11V7"/><path d="M16 11V7"/>',
  'sparkles': '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/>',
  'star': '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
  'history': '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>',
  'wifi': '<path d="M5 13a10 10 0 0 1 14 0"/><path d="M8.5 16.5a5 5 0 0 1 7 0"/><path d="M2 8.82a15 15 0 0 1 20 0"/><line x1="12" x2="12.01" y1="20" y2="20"/>',
  'battery': '<rect width="16" height="10" x="2" y="7" rx="2" ry="2"/><line x1="22" x2="22" y1="11" y2="13"/><line x1="6" x2="6" y1="11" y2="13"/><line x1="10" x2="10" y1="11" y2="13"/><line x1="14" x2="14" y1="11" y2="13"/>',
};
const ic = (name, size = 16) =>
  `<svg class="ic" xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pad = (n) => String(n).padStart(2, '0');
const short = (u, n = 60) => (u && u.length > n ? u.slice(0, n) + '…' : (u || ''));

/* ---------- source types ---------- */
const TYPE_ICON = { auto: 'sparkles', youtube: 'youtube', twitch: 'twitch', web: 'globe', image: 'image', video: 'film', audio: 'music' };
const PH = {
  youtube: 'https://www.youtube.com/watch?v=...', twitch: 'https://www.twitch.tv/...', web: 'https://example.com',
  image: 'https://.../image.png', video: 'https://.../movie.mp4', audio: 'https://.../music.mp3',
};
const tLabel = (t) => T('type_' + t);
const tHint = (t) => T('hint_' + t);
const tPh = (t) => (t === 'auto' ? T('ph_auto') : PH[t]);

const PAGE_ICON = { remote: 'tv', player: 'music', channels: 'radio', presets: 'star', history: 'history' };

/* ---------- state ---------- */
let mode = null;                 // 'tv' | 'bx' | 'browse' | null
let seekStep = 10;
let clockTimer = null;
const BC = { name: '', url: '', type: 'auto', live: false, loop: false };   // channel broadcast form
const V = {
  tv: { p: 'tv', kind: 'tv', types: ['auto', 'youtube', 'twitch', 'web', 'image', 'video', 'audio'],
        type: 'auto', page: 'remote', presetList: [], historyList: [], posBase: 0, posAt: 0, label: '',
        ctx: { current: { mode: 'off' }, channels: [], presets: [] } },
  bx: { p: 'bx', kind: 'bx', types: ['auto', 'youtube', 'twitch', 'audio'],
        type: 'auto', page: 'player', presetList: [], historyList: [], posBase: 0, posAt: 0, label: '',
        ctx: { current: { mode: 'off' }, presets: [] } },
};
const cur = () => (mode === 'tv' ? V.tv : mode === 'bx' ? V.bx : null);
const pagesOf = (v) => (v.kind === 'tv'
  ? (v.ctx.noTv ? ['channels'] : ['remote', 'channels', 'presets', 'history'])
  : ['player', 'presets', 'history']);
const mainPage = (v) => (v.kind === 'tv' ? 'remote' : 'player');

/* ---------- history (localStorage) ---------- */
const HKEY = 'rensyu_tv_history';
function loadHistory() { try { return JSON.parse(localStorage.getItem(HKEY)) || []; } catch (_) { return []; } }
function saveHistory(url, t) {
  try {
    const old = loadHistory().find((h) => h.url === url);
    const list = loadHistory().filter((h) => h.url !== url);
    list.unshift({ url, type: t, title: titleCache[url] || (old && old.title) || '' });
    localStorage.setItem(HKEY, JSON.stringify(list.slice(0, 15)));
  } catch (_) {}
}
function storeHistoryTitle(url, title) {
  try {
    const list = loadHistory();
    const h = list.find((x) => x.url === url);
    if (h) { h.title = title; localStorage.setItem(HKEY, JSON.stringify(list)); }
  } catch (_) {}
}

/* ---------- page titles (looked up by the server, cached) ---------- */
const titleCache = {};          // url -> title ('' = none found)
const titleQueued = new Set();
const titleQueue = [];
let titleBusy = false;
loadHistory().forEach((h) => { if (h.title) titleCache[h.url] = h.title; });
const titleOf = (url) => (url && titleCache[url]) || '';

function ensureTitle(url) {
  if (!url || titleCache[url] !== undefined || titleQueued.has(url)) return;
  titleQueued.add(url);
  titleQueue.push(url);
  pumpTitles();
}
function pumpTitles() {
  if (titleBusy || !titleQueue.length) return;
  titleBusy = true;
  const url = titleQueue.shift();
  fetch(`https://${GetParentResourceName()}/getTitle`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }),
  }).then((r) => r.json()).then((d) => {
    titleCache[url] = (d && d.title) || '';
    if (titleCache[url]) storeHistoryTitle(url, titleCache[url]);
  }).catch(() => { titleCache[url] = ''; }).finally(() => {
    titleQueued.delete(url);
    titleBusy = false;
    refreshTitles();
    setTimeout(pumpTitles, 250);
  });
}
function refreshTitles() {
  const v = cur();
  if (!v) return;
  renderStatus(v);
  renderLists(v);
  const typing = document.activeElement && document.activeElement.closest && document.activeElement.closest(`#${v.p}-channels`);
  if (!typing) renderChannels(v);
}

/* ---------- skeleton ---------- */
function skeleton(v) {
  const p = v.p, tv = v.kind === 'tv';
  const acts = tv
    ? `<button class="btn" id="${p}-browse">${ic('mouse-pointer')}<span id="${p}-browse-l"></span></button>
       <button class="btn danger" id="${p}-off">${ic('power')}<span id="${p}-off-l"></span></button>`
    : `<button class="btn" id="${p}-stop">${ic('square')}<span id="${p}-stop-l"></span></button>
       <button class="btn danger" id="${p}-pickup">${ic('package')}<span id="${p}-pickup-l"></span></button>`;
  const pages = tv ? ['channels', 'presets', 'history'] : ['presets', 'history'];
  return `
    <div class="page" data-page="${mainPage(v)}"><div class="grid2">
      <div class="col">
        <div class="card" id="${p}-status"></div>
        <div class="card hide" id="${p}-transport"></div>
        <div class="card volume">${ic('volume-2')}<span class="lbl" id="${p}-vollbl"></span>
          <input id="${p}-vol" type="range" min="0" max="100" value="50"><span class="v" id="${p}-volv">50</span></div>
      </div>
      <div class="col">
        <div class="card">
          <div class="subtabs" id="${p}-chips"></div>
          <div class="searchbox">${ic('link')}
            <input id="${p}-url" type="text" autocomplete="off" spellcheck="false">
            <button class="btn ghost sm" id="${p}-clear">${ic('x', 14)}</button>
          </div>
          <div class="hint" id="${p}-hint"></div>
          <div class="opts">
            <label class="switch"><input id="${p}-live" type="checkbox"><span></span><b id="${p}-livel" style="font-weight:400"></b></label>
            <label class="switch"><input id="${p}-loop" type="checkbox"><span></span><b id="${p}-loopl" style="font-weight:400"></b></label>
          </div>
          <button class="btn accent wide" id="${p}-play">${ic('play')}<span id="${p}-playlbl"></span></button>
        </div>
        <div class="acts">${acts}</div>
      </div>
    </div></div>
    ${pages.map((pg) => `<div class="page hide" data-page="${pg}"><div id="${p}-${pg}"></div></div>`).join('')}`;
}

/* ---------- rendering ---------- */
function renderNav(v) {
  const pages = pagesOf(v);
  if (!pages.includes(v.page)) v.page = pages[0];
  $('sb-nav').innerHTML = pages.map((pg) =>
    `<button class="nav ${pg === v.page ? 'on' : ''}" data-page="${pg}"><span class="ico">${ic(PAGE_ICON[pg], 20)}</span><span class="sb-label">${esc(T('nav_' + pg))}</span></button>`).join('');
  $('ph-title').textContent = T('nav_' + v.page);
  document.querySelectorAll(`#view-${v.p} .page`).forEach((el) => el.classList.toggle('hide', el.dataset.page !== v.page));
}

function renderStatus(v) {
  const x = v.ctx, c = x.current || { mode: 'off' }, tv = v.kind === 'tv';
  const on = c.mode !== 'off';
  let icon, title, sub, pills = '', tcls = 'off';

  if (tv && x.noTv) {
    icon = 'radio'; title = T('st_bc_title'); sub = T('st_bc_sub'); tcls = '';
  } else if (!on) {
    icon = tv ? 'power' : 'music';
    title = tv ? T('st_off_tv') : T('st_off_box');
    sub = tv ? T('st_off_tv_sub') : T('st_off_box_sub');
    pills = `<span class="pill">${esc(T('pill_off'))}</span>`;
  } else if (c.mode === 'channel' && c.idle) {
    icon = 'radio'; tcls = '';
    title = `CH ${pad(c.channelNum)} ${c.channelLabel}`;
    sub = T('st_nosignal_sub');
    pills = `<span class="pill st-warn">${esc(T('pill_nosignal'))}</span>`;
  } else {
    icon = TYPE_ICON[c.type] || 'tv';
    tcls = 't-' + c.type;
    title = T('type_' + c.type);
    sub = titleOf(c.url) || short(c.url, 64);
    ensureTitle(c.url);
    if (c.controllable && c.paused) pills += `<span class="pill st-warn">${esc(T('pill_paused'))}</span>`;
    else pills += `<span class="pill st-duty">${esc(c.type === 'web' || c.type === 'image' ? T('pill_showing') : T('pill_playing'))}</span>`;
    if (c.live) pills += `<span class="pill st-live">${esc(T('pill_live'))}</span>`;
    if (c.mode === 'channel') pills += `<span class="pill st-active">CH ${pad(c.channelNum)}</span>`;
  }

  const el = $(v.p + '-status');
  el.className = 'card' + (on && !x.noTv ? ' active' : '');
  el.innerHTML = `<div class="head"><div class="tile ${tcls}">${ic(icon, 20)}</div>
    <div class="meta"><div class="nm">${esc(title)}</div><div class="sub">${esc(sub)}</div></div>
    <div class="badges">${pills}</div></div>`;
}

function fmtPos(sec) {
  sec = Math.max(0, Math.floor(sec));
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

function renderTransport(v) {
  const x = v.ctx, c = x.current || {};
  const show = c.mode !== 'off' && c.controllable && !x.noTv;
  const el = $(v.p + '-transport');
  el.classList.toggle('hide', !show);
  if (!show) return;
  const can = c.canControl !== false;
  const dis = can ? '' : 'disabled';
  const note = can ? T('tp_note_ok') : (c.mode === 'channel' ? T('tp_note_noperm') : '');
  el.innerHTML = `
    <div class="tp-time">${ic(c.paused ? 'pause' : 'play')}<b data-time>0:00</b></div>
    <div class="tp-btns">
      <button class="btn" data-a="restart" title="${esc(T('tp_restart'))}" ${dis}>${ic('skip-back')}</button>
      <button class="btn" data-a="back" title="${esc(T('tp_back', seekStep))}" ${dis}>${ic('rewind')}</button>
      <button class="btn accent" data-a="toggle" title="${esc(T('tp_toggle'))}" ${dis}>${ic(c.paused ? 'play' : 'pause')}</button>
      <button class="btn" data-a="fwd" title="${esc(T('tp_fwd', seekStep))}" ${dis}>${ic('fast-forward')}</button>
      <button class="btn" data-a="sync" title="${esc(T('tp_sync'))}">${ic('refresh-cw')}</button>
    </div>
    <div class="hint center">${esc(note)}</div>`;
  tickTime(v);
}

function tickTime(v) {
  const c = v.ctx.current || {};
  const el = $(v.p + '-transport');
  if (!c.controllable || el.classList.contains('hide')) return;
  const t = el.querySelector('[data-time]');
  if (!t) return;
  const pos = c.paused ? v.posBase : v.posBase + (performance.now() - v.posAt) / 1000;
  t.textContent = fmtPos(pos);
}

function chipsHTML(types, active, attr) {
  return types.map((t) =>
    `<button ${attr}="${t}" class="${t === active ? 'on' : ''}">${ic(TYPE_ICON[t], 14)}${esc(tLabel(t))}</button>`).join('');
}

function renderChips(v) {
  $(v.p + '-chips').innerHTML = chipsHTML(v.types, v.type, 'data-t');
  $(v.p + '-url').placeholder = tPh(v.type);
  $(v.p + '-hint').textContent = tHint(v.type);
}

function renderActs(v) {
  const x = v.ctx, c = x.current || {}, on = c.mode !== 'off';
  if (v.kind === 'tv') {
    $('tv-browse').disabled = !(on && c.type && c.type !== 'nosignal') || !!x.noTv;
    $('tv-off').disabled = !on || !!x.noTv;
    $('tv-play').disabled = !!x.noTv;
    $('tv-playlbl').textContent = x.noTv ? T('btn_play_bc_mode') : T('btn_play_tv');
  } else {
    $('bx-stop').disabled = !on;
    $('bx-pickup').disabled = x.canPickup === false;
    $('bx-playlbl').textContent = T('btn_play_box');
  }
}

function applyLabels(v) {
  const p = v.p;
  $(p + '-vollbl').textContent = T('vol_label');
  $(p + '-livel').textContent = T('opt_live');
  $(p + '-loopl').textContent = T('opt_loop');
  $(p + '-clear').title = T('btn_clear');
  if (v.kind === 'tv') {
    $('tv-browse-l').textContent = T('btn_interact');
    $('tv-off-l').textContent = T('btn_off');
  } else {
    $('bx-stop-l').textContent = T('btn_stop');
    $('bx-pickup-l').textContent = T('btn_pickup');
  }
}

function cardsHTML(items, src, emptyMsg) {
  if (!items.length) return `<div class="empty">${esc(emptyMsg)}</div>`;
  return `<div class="grid2">${items.map((it, i) => `
    <div class="card row click" data-src="${src}" data-i="${i}">
      <div class="tile sm">${ic(TYPE_ICON[it.type] || 'link', 18)}</div>
      <div class="meta"><div class="nm" style="font-size:14px">${esc(it.label)}</div><div class="sub">${esc(short(it.url, 46))}</div></div>
      <div class="btns">
        <button class="btn sm" data-act="fill" data-src="${src}" data-i="${i}" title="${esc(T('list_fill'))}">${ic('link', 14)}</button>
        <button class="btn sm accent" data-act="play" data-src="${src}" data-i="${i}" title="${esc(T('list_play'))}">${ic('play', 14)}</button>
      </div>
    </div>`).join('')}</div>`;
}

function channelsHTML(v) {
  const x = v.ctx, now = x.current || {};
  const chs = x.channels || [];
  let bc = '';
  if (x.canBroadcast) {
    bc = `<div class="card bcbox span2">
      <div class="head"><div class="tile sm">${ic('radio', 18)}</div>
        <div class="meta"><div class="nm" style="font-size:14px">${esc(T('ch_card_title'))}</div>
        <div class="sub">${esc(T('ch_card_sub'))}</div></div></div>
      <div class="subtabs chips" id="bc-chips">${chipsHTML(v.types, BC.type, 'data-bt')}</div>
      <div class="searchbox">${ic('link')}<input id="bc-url" type="text" autocomplete="off" spellcheck="false" value="${esc(BC.url)}" placeholder="${esc(tPh(BC.type))}"></div>
      <div class="hint">${esc(tHint(BC.type))}</div>
      <div class="opts">
        <label class="switch"><input id="bc-live" type="checkbox" ${BC.live ? 'checked' : ''}><span></span>${esc(T('opt_live'))}</label>
        <label class="switch"><input id="bc-loop" type="checkbox" ${BC.loop ? 'checked' : ''}><span></span>${esc(T('opt_loop'))}</label>
      </div>
      <div class="row2">
        <div class="searchbox"><input id="bc-name" type="text" maxlength="24" value="${esc(BC.name)}" placeholder="${esc(T('ch_name_ph'))}"></div>
        <button class="btn accent" data-act="newbc">${ic('radio', 16)}${esc(T('ch_btn_broadcast'))}</button>
        ${x.myChannel ? `<button class="btn danger" data-act="stopch" data-id="${esc(x.myChannel)}" title="${esc(T('ch_btn_stop_mine'))}">${ic('square', 14)}</button>` : ''}
      </div></div>`;
  }
  if (!chs.length) return `<div class="grid2">${bc}</div><div class="empty">${esc(T('empty_channels'))}</div>`;

  const cards = chs.map((ch) => {
    if (ch.active) ensureTitle(ch.url);
    const on = now.mode === 'channel' && now.channel === ch.id;
    const sub = ch.active
      ? `<span style="color:var(--ok)">● ${esc(T('ch_live_tag'))}</span> · ${esc(ch.type ? T('type_' + ch.type) : '')} · ${esc(titleOf(ch.url) || short(ch.url, 30))}`
      : esc(T('ch_none'));
    const own = x.canBroadcast && !ch.fixed && !ch.foreign && !ch.mine;
    return `<div class="card row${on ? ' active' : ''}">
      <div class="meta">
        <div class="nm" style="font-size:14px"><span class="num">CH ${pad(ch.num)}</span>${esc(ch.label)}
          ${ch.fixed ? `<span class="tag">${ic('lock', 11)} ${esc(T('tag_fixed'))}</span>` : ''}
          ${ch.mine ? `<span class="tag mine">${ic('user', 11)} ${esc(T('tag_mine'))}</span>` : ''}</div>
        <div class="sub">${sub}</div>
      </div>
      <div class="btns">
        ${x.noTv ? '' : `<button class="btn sm" data-act="tune" data-id="${esc(ch.id)}" title="${esc(T('ch_tune'))}">${ic('tv', 14)}</button>`}
        ${own ? `<button class="btn sm" data-act="broadcast" data-id="${esc(ch.id)}" title="${esc(T('ch_bc_to'))}">${ic('radio', 14)}</button>
                 <button class="btn sm danger" data-act="stopch" data-id="${esc(ch.id)}" ${ch.active ? '' : 'disabled'} title="${esc(T('ch_stop'))}">${ic('square', 14)}</button>` : ''}
      </div>
    </div>`;
  }).join('');
  return `<div class="grid2">${bc}${cards}</div>`;
}

function renderChannels(v) {
  if (v.kind === 'tv') $('tv-channels').innerHTML = channelsHTML(v);
}

function renderLists(v) {
  v.presetList = (v.ctx.presets || []).map((p) => ({ label: p.label, url: p.url, type: p.type || 'auto' }));
  v.historyList = loadHistory().map((h) => {
    ensureTitle(h.url);
    return { label: titleOf(h.url) || h.title || tLabel(h.type) || tLabel('auto'), url: h.url, type: h.type };
  });
  $(v.p + '-presets').innerHTML = cardsHTML(v.presetList, 'p', T('empty_presets'));
  $(v.p + '-history').innerHTML = cardsHTML(v.historyList, 'h', T('empty_history'));
}

function renderHeader(v) {
  $('ph-nm').textContent = v.label;
  $('ph-sub').textContent = v.kind === 'tv' ? T('ui_tv_sub') : T('ui_box_sub');
  $('sb-app').textContent = v.kind === 'tv' ? T('ui_tv_sub') : T('ui_box_sub');
  $('sb-logo').innerHTML = ic(v.kind === 'tv' ? 'tv' : 'speaker', 20);
  $('ph-close').innerHTML = ic('x', 16);
  $('ph-close').title = T('nav_close');
}

function render(v) {
  renderHeader(v);
  renderNav(v);
  renderStatus(v);
  renderTransport(v);
  renderChips(v);
  renderActs(v);
  renderChannels(v);
  renderLists(v);
}

/* ---------- composer ---------- */
const form = (v) => ({
  url: $(v.p + '-url').value.trim(),
  type: v.type,
  live: $(v.p + '-live').checked,
  loop: $(v.p + '-loop').checked,
});
function setComposer(v, url, t) {
  $(v.p + '-url').value = url;
  v.type = v.types.includes(t) ? t : 'auto';
  renderChips(v);
}
function flash(el) {
  const box = el.closest('.searchbox') || el;
  box.style.borderColor = 'var(--danger)';
  setTimeout(() => (box.style.borderColor = ''), 700);
  el.focus();
}
function playNow(v) {
  const f = form(v);
  if (!f.url) return flash($(v.p + '-url'));
  saveHistory(f.url, f.type);
  post(v.kind === 'tv' ? 'play' : 'bx_play', f);
}
function setPage(v, pg) {
  v.page = pg;
  renderNav(v);
  if (pg === 'history') renderLists(v);
  if (pg === mainPage(v)) setTimeout(() => $(v.p + '-url').focus(), 30);
}
function setVolumeUI(val) {
  ['tv', 'bx'].forEach((p) => { $(p + '-vol').value = val; $(p + '-volv').textContent = val; });
}

function listClick(v, e) {
  const b = e.target.closest('[data-act]');
  const row = e.target.closest('[data-i]');
  const src = (b || row) && (b || row).dataset.src;
  const it = (b || row) && (src === 'h' ? v.historyList : v.presetList)[parseInt((b || row).dataset.i, 10)];
  if (!it) return;
  setComposer(v, it.url, it.type);
  if (b && b.dataset.act === 'play') return playNow(v);
  setPage(v, mainPage(v));
}

function bindView(v) {
  const p = v.p, tv = v.kind === 'tv';
  $(p + '-chips').addEventListener('click', (e) => {
    const b = e.target.closest('[data-t]');
    if (!b) return;
    v.type = b.dataset.t;
    renderChips(v);
    $(p + '-url').focus();
  });
  $(p + '-clear').onclick = () => { $(p + '-url').value = ''; $(p + '-url').focus(); };
  $(p + '-url').addEventListener('keydown', (e) => { if (e.key === 'Enter') playNow(v); });
  $(p + '-play').onclick = () => playNow(v);

  $(p + '-transport').addEventListener('click', (e) => {
    const b = e.target.closest('[data-a]');
    if (!b || b.disabled) return;
    const a = b.dataset.a, pre = tv ? '' : 'bx_';
    if (a === 'toggle' || a === 'restart') post(pre + 'control', { action: a });
    else if (a === 'back') post(pre + 'control', { action: 'seek', value: -seekStep });
    else if (a === 'fwd') post(pre + 'control', { action: 'seek', value: seekStep });
    else if (a === 'sync') post(tv ? 'resync' : 'bx_resync');
  });

  if (tv) {
    $('tv-off').onclick = () => post('off');
    $('tv-browse').onclick = () => post('browse', {});

    const ch = $('tv-channels');
    ch.addEventListener('input', (e) => {
      const id = e.target.id;
      if (id === 'bc-url') BC.url = e.target.value;
      else if (id === 'bc-name') BC.name = e.target.value;
    });
    ch.addEventListener('change', (e) => {
      if (e.target.id === 'bc-live') BC.live = e.target.checked;
      else if (e.target.id === 'bc-loop') BC.loop = e.target.checked;
    });
    ch.addEventListener('click', (e) => {
      const chip = e.target.closest('[data-bt]');
      if (chip) { BC.type = chip.dataset.bt; renderChannels(v); return; }
      const b = e.target.closest('[data-act]');
      if (!b) return;
      const a = b.dataset.act;
      if (a === 'tune') return post('tune', { channel: b.dataset.id });
      if (a === 'stopch') return post('stopChannel', { channel: b.dataset.id });
      if (a === 'broadcast' || a === 'newbc') {
        const url = BC.url.trim();
        if (!url) return flash($('bc-url'));
        saveHistory(url, BC.type);
        const f = { url, type: BC.type, live: BC.live, loop: BC.loop };
        if (a === 'broadcast') return post('broadcast', { ...f, channel: b.dataset.id });
        return post('broadcast', { ...f, channel: v.ctx.myChannel || 'new', label: BC.name.trim() });
      }
    });
  } else {
    $('bx-stop').onclick = () => post('bx_stop');
    $('bx-pickup').onclick = () => post('bx_pickup');
  }

  $(p + '-presets').addEventListener('click', (e) => listClick(v, e));
  $(p + '-history').addEventListener('click', (e) => listClick(v, e));

  $(p + '-vol').addEventListener('input', () => {
    const val = parseInt($(p + '-vol').value, 10) || 0;
    setVolumeUI(val);
    post('setVolume', { value: val });
  });
}

/* ---------- open / close ---------- */
function updateClock() {
  const d = new Date();
  $('sb-clock').textContent = d.toLocaleTimeString(T('locale_tag'), { hour: '2-digit', minute: '2-digit' });
}

function hideAll() {
  $('qs').classList.add('hide');
  $('browse').classList.add('hide');
  mode = null;
  if (clockTimer) { clearInterval(clockTimer); clockTimer = null; }
}

function updatePanel(v, data) {
  v.ctx = { ...v.ctx, ...data };
  v.posBase = (data.current && data.current.pos) || 0;
  v.posAt = performance.now();
  renderStatus(v);
  renderTransport(v);
  renderActs(v);
  renderNav(v);
  const typing = document.activeElement && document.activeElement.closest && document.activeElement.closest(`#${v.p}-channels`);
  if (!typing) renderChannels(v);
}

function openPanel(kind, data) {
  hideAll();
  if (data.t) TR = data.t;
  document.documentElement.lang = (T('locale_tag') || 'en').split('-')[0];
  const v = V[kind];
  v.ctx = { ...v.ctx, ...data };
  v.label = data.label || '';
  if (typeof data.seekStep === 'number') seekStep = data.seekStep;
  v.posBase = (data.current && data.current.pos) || 0;
  v.posAt = performance.now();
  v.type = 'auto';
  v.page = mainPage(v);
  if (v.ctx.noTv) v.page = 'channels';
  BC.type = 'auto';

  $('view-tv').classList.toggle('hide', kind !== 'tv');
  $('view-bx').classList.toggle('hide', kind !== 'bx');
  $(v.p + '-url').value = '';
  $(v.p + '-live').checked = false;
  $(v.p + '-loop').checked = false;
  setVolumeUI(typeof data.volume === 'number' ? data.volume : 50);
  applyLabels(v);
  render(v);

  const tablet = $('tablet');
  tablet.style.animation = 'none';
  void tablet.offsetHeight;
  tablet.style.animation = '';

  $('sb-icons').innerHTML = ic('wifi', 14) + ic('battery', 16);
  $('b-url').placeholder = T('browse_ph');
  $('b-go').textContent = T('browse_go');
  updateClock();
  clockTimer = setInterval(updateClock, 15000);

  $('qs').classList.remove('hide');
  mode = kind;
  if (v.page === mainPage(v)) setTimeout(() => $(v.p + '-url').focus(), 120);
}

/* ---------- Interact (windowed mouse control) ---------- */
const surface = $('surface');
const BUTTONS = ['left', 'middle', 'right'];
const pos = (e) => {
  const r = surface.getBoundingClientRect();
  const c = (val) => Math.max(0, Math.min(1, val));
  return { x: c((e.clientX - r.left) / r.width), y: c((e.clientY - r.top) / r.height) };
};

function layoutBrowse(rect) {
  const bar = $('bar');
  const x = $('b-x');
  x.innerHTML = ic('x', 18);
  x.title = T('nav_close');
  if (!rect) {
    surface.style.cssText = 'left:0;top:0;width:100%;height:100%';
    x.style.left = 'auto'; x.style.right = '12px'; x.style.top = '12px';
    return;
  }
  const pct = (val) => (val * 100) + '%';
  // x button: top-right corner of the window, just above it
  x.style.right = 'auto';
  x.style.left = `calc(${pct(rect.left + rect.width)} - 34px)`;
  x.style.top = `calc(${pct(rect.top)} - 44px)`;
  surface.style.cssText = `left:${pct(rect.left)};top:${pct(rect.top)};width:${pct(rect.width)};height:${pct(rect.height)}`;
  bar.style.top = `calc(${pct(rect.top + rect.height)} + 14px)`;
  bar.style.bottom = 'auto';
  bar.style.width = pct(rect.width);
}

let moveQueued = false, lastMove = null;
surface.addEventListener('mousemove', (e) => {
  lastMove = pos(e);
  if (moveQueued) return;
  moveQueued = true;
  requestAnimationFrame(() => { moveQueued = false; post('mouse', { kind: 'move', ...lastMove }); });
});
surface.addEventListener('mousedown', (e) => {
  e.preventDefault();
  post('mouse', { kind: 'down', button: BUTTONS[e.button] || 'left', ...pos(e) });
});
surface.addEventListener('mouseup', (e) => {
  e.preventDefault();
  post('mouse', { kind: 'up', button: BUTTONS[e.button] || 'left', ...pos(e) });
});
surface.addEventListener('wheel', (e) => {
  e.preventDefault();
  post('mouse', { kind: 'wheel', dy: e.deltaY, ...pos(e) });
}, { passive: false });
surface.addEventListener('contextmenu', (e) => e.preventDefault());

$('b-x').onclick = () => post('closeBrowse');
$('ph-close').onclick = () => post('close');
$('b-go').onclick = () => { const u = $('b-url').value.trim(); if (u) post('browseGo', { url: u }); };
$('b-url').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('b-go').click(); });

/* ---------- messages from Lua ---------- */
window.addEventListener('message', (e) => {
  const { action, data } = e.data || {};
  if (action === 'openMenu') openPanel('tv', data);
  else if (action === 'openBoombox') openPanel('bx', data);
  else if (action === 'updateMenu' && mode === 'tv') updatePanel(V.tv, data);
  else if (action === 'updateBoombox' && mode === 'bx') updatePanel(V.bx, data);
  else if (action === 'openBrowse') {
    hideAll();
    $('b-url').value = (data && data.url) || '';
    layoutBrowse(data && data.rect);
    $('browse').classList.remove('hide');
    mode = 'browse';
  } else if (action === 'close') hideAll();
});

/* ---------- init ---------- */
$('view-tv').innerHTML = skeleton(V.tv);
$('view-bx').innerHTML = skeleton(V.bx);
bindView(V.tv);
bindView(V.bx);

$('sb-nav').addEventListener('click', (e) => {
  const b = e.target.closest('[data-page]');
  const v = cur();
  if (b && v) setPage(v, b.dataset.page);
});

// click outside the tablet closes it
$('qs').addEventListener('mousedown', (e) => { if (e.target === $('qs')) post('close'); });

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (mode === 'tv' || mode === 'bx') post('close');
  else if (mode === 'browse') post('closeBrowse');
});

setInterval(() => {
  if (mode === 'tv') tickTime(V.tv);
  else if (mode === 'bx') tickTime(V.bx);
}, 500);
