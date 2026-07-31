/// The single page served at `http://<phone-ip>:8787/`.
///
/// Everything (CSS + JS) is inlined so the TV browser makes exactly one
/// request before it can start playing, and it speaks the same WebSocket
/// protocol as the native TV app — the phone remote drives both identically.
class WebAssets {
  const WebAssets._();

  static String playerPage(String hostName) =>
      _page.replaceAll('__HOST_NAME__', _escape(hostName));

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static const _page = r'''<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#040814">
<link rel="icon" href="data:,">
<title>LanCast — پخش‌کننده</title>
<style>
  /* Served by the phone, so Persian renders correctly even on a smart TV
     that ships no Arabic-script font. Falls back silently if unavailable. */
  @font-face{font-family:Vazirmatn;src:url(/font/regular.ttf) format('truetype');
    font-weight:400;font-display:swap}
  @font-face{font-family:Vazirmatn;src:url(/font/bold.ttf) format('truetype');
    font-weight:700;font-display:swap}
  *{box-sizing:border-box;margin:0;padding:0}
  :root{
    --abyss:#040814; --navy:#071026; --navy-hi:#0c1a3c;
    --azure:#4ea8ff; --aqua:#6ee7f9; --violet:#8b7bff;
    --text:#eaf1ff; --dim:#9fb2d8; --faint:#6b7fa8;
    --glass:rgba(255,255,255,.08); --glass-2:rgba(255,255,255,.14);
    --stroke:rgba(255,255,255,.15); --r:22px;
  }
  html,body{height:100%;background:var(--abyss);color:var(--text);overflow:hidden}
  body{
    font-family:"Vazirmatn","Noto Naskh Arabic",system-ui,"Segoe UI",Roboto,sans-serif;
    background:
      radial-gradient(1100px 780px at 82% -12%, rgba(78,168,255,.30), transparent 62%),
      radial-gradient(950px 720px at 6% 112%, rgba(139,123,255,.26), transparent 62%),
      linear-gradient(140deg,#0a1330,#060c1f 55%,#040810);
  }
  #stage{position:fixed;inset:0;display:flex;align-items:center;justify-content:center}
  /* Hidden until a film is loaded, so the navy backdrop shows through the
     splash instead of a black rectangle. */
  video{width:100%;height:100%;object-fit:contain;background:#000;display:block;
    opacity:0;transition:opacity .35s ease}
  video.live{opacity:1}
  video.cover{object-fit:cover} video.stretch{object-fit:fill}

  /* ---- subtitles: rendered by us so the sync offset is exact ---- */
  #subs{
    position:fixed;left:5%;right:5%;bottom:6%;text-align:center;
    pointer-events:none;z-index:30;line-height:1.3;
    text-shadow:0 2px 6px rgba(0,0,0,.95),0 0 12px rgba(0,0,0,.8);
    font-weight:700;white-space:pre-wrap;
  }
  #subs span{background:rgba(0,0,0,.35);padding:.12em .45em;border-radius:.25em;
    display:inline-block;-webkit-box-decoration-break:clone;box-decoration-break:clone}

  /* ---- glass chrome ---- */
  .glass{
    position:relative;
    background:linear-gradient(140deg,rgba(255,255,255,.13),rgba(255,255,255,.045));
    border:1px solid var(--stroke);border-radius:var(--r);
    box-shadow:0 24px 70px -30px rgba(0,0,0,.9), inset 0 1px 0 rgba(255,255,255,.14);
    backdrop-filter:blur(24px) saturate(150%);-webkit-backdrop-filter:blur(24px) saturate(150%);
  }
  #bar{
    position:fixed;left:clamp(14px,2vw,34px);right:clamp(14px,2vw,34px);
    bottom:clamp(14px,2.2vh,34px);z-index:40;padding:clamp(14px,1.6vw,24px) clamp(18px,2vw,30px);
    display:flex;flex-direction:column;gap:clamp(10px,1.2vh,16px);
    transition:opacity .28s, transform .28s;
  }
  #bar.hide,#bar.idle{opacity:0;transform:translateY(18px);pointer-events:none}
  .row{display:flex;align-items:center;gap:10px}
  .title{font-size:clamp(15px,1.3vw,26px);font-weight:700;overflow:hidden;
    text-overflow:ellipsis;white-space:nowrap;flex:1}
  .time{font-size:clamp(13px,1.1vw,21px);color:var(--dim);
    font-variant-numeric:tabular-nums;direction:ltr}

  input[type=range]{
    -webkit-appearance:none;appearance:none;width:100%;height:clamp(6px,.5vh,10px);border-radius:99px;
    background:rgba(255,255,255,.2);outline:none;direction:ltr;cursor:pointer
  }
  input[type=range]::-webkit-slider-thumb{
    -webkit-appearance:none;width:16px;height:16px;border-radius:50%;background:#fff;
    box-shadow:0 0 0 4px rgba(78,168,255,.35)
  }
  input[type=range]::-moz-range-thumb{width:16px;height:16px;border:0;border-radius:50%;background:#fff}

  button{
    font:inherit;font-size:clamp(13px,1.05vw,20px);color:var(--text);background:var(--glass);
    border:1px solid var(--stroke);border-radius:14px;
    padding:clamp(9px,.8vw,15px) clamp(14px,1.2vw,24px);cursor:pointer;
    display:inline-flex;align-items:center;gap:7px;
    transition:transform .12s, background .2s;white-space:nowrap
  }
  button:hover{background:var(--glass-2)}
  button:focus-visible,button:focus{outline:none;border-color:var(--azure);
    box-shadow:0 0 0 3px rgba(78,168,255,.45);transform:scale(1.04)}
  button.primary{background:linear-gradient(90deg,var(--azure),var(--aqua));color:#04101f;
    border-color:transparent;font-weight:800;box-shadow:0 8px 26px -8px rgba(78,168,255,.8)}
  button.round{border-radius:50%;width:clamp(46px,4vw,72px);height:clamp(46px,4vw,72px);
    padding:0;justify-content:center;font-size:clamp(17px,1.4vw,26px)}
  button.round.big{width:clamp(58px,5.2vw,92px);height:clamp(58px,5.2vw,92px);
    font-size:clamp(22px,1.9vw,36px)}

  #splash{position:fixed;inset:0;z-index:60;display:flex;align-items:center;justify-content:center;padding:24px}
  #splash .card{max-width:min(760px,86vw);width:100%;padding:clamp(30px,3vw,52px);text-align:center}
  .brand{font-size:clamp(30px,3.2vw,60px);font-weight:800;letter-spacing:-.5px;
    background:linear-gradient(90deg,var(--azure),var(--aqua));-webkit-background-clip:text;
    background-clip:text;color:transparent;margin-bottom:8px}
  .sub{color:var(--dim);font-size:clamp(14px,1.15vw,23px);line-height:1.9;margin-bottom:22px}
  .dot{display:inline-block;width:9px;height:9px;border-radius:50%;background:var(--faint);
    margin-inline-end:8px;vertical-align:middle}
  .dot.on{background:#52e5a3;box-shadow:0 0 12px #52e5a3}
  .stack{display:flex;flex-direction:column;gap:10px;margin-top:18px}
  .hint{font-size:clamp(12px,.95vw,18px);color:var(--faint);margin-top:20px;line-height:1.9}
  .menu{position:fixed;z-index:50;bottom:96px;left:14px;right:14px;max-height:52vh;overflow:auto;
    padding:14px;display:none}
  .menu.show{display:block}
  .menu h4{font-size:12px;color:var(--dim);margin:6px 2px 10px;font-weight:700}
  .opt{display:flex;width:100%;justify-content:space-between;margin-bottom:8px}
  .opt.sel{border-color:var(--azure);background:rgba(78,168,255,.16)}
  #toast{position:fixed;top:18px;left:50%;transform:translateX(-50%);z-index:70;padding:10px 18px;
    font-size:14px;opacity:0;transition:opacity .25s;pointer-events:none}
  #toast.show{opacity:1}
  .spin{width:54px;height:54px;border-radius:50%;border:3px solid rgba(255,255,255,.15);
    border-top-color:var(--azure);animation:sp 1s linear infinite;position:fixed;z-index:35;
    top:50%;left:50%;margin:-27px 0 0 -27px;display:none}
  .spin.show{display:block}
  @keyframes sp{to{transform:rotate(360deg)}}
</style>
</head>
<body>

<div id="stage"><video id="v" playsinline preload="metadata"></video></div>
<div id="subs"></div>
<div class="spin" id="spin"></div>

<div class="glass menu" id="menu"></div>

<div class="glass idle" id="bar">
  <div class="row">
    <div class="title" id="title">آماده‌ی پخش</div>
    <span class="time" id="time">00:00 / 00:00</span>
  </div>
  <input type="range" id="seek" min="0" max="1000" value="0" step="1">
  <div class="row" style="justify-content:center;flex-wrap:wrap">
    <button class="round" id="back" title="۱۰ ثانیه عقب">«۱۰</button>
    <button class="round big primary" id="play">▶</button>
    <button class="round" id="fwd" title="۱۰ ثانیه جلو">۱۰»</button>
    <button id="subBtn">زیرنویس</button>
    <button id="delayDown" title="زیرنویس زودتر">−۰٫۵ ثانیه</button>
    <button id="delayUp" title="زیرنویس دیرتر">+۰٫۵ ثانیه</button>
    <button id="fitBtn">اندازه تصویر</button>
    <button id="fsBtn">تمام‌صفحه</button>
  </div>
</div>

<div id="splash">
  <div class="glass card">
    <div class="brand">LanCast</div>
    <div class="sub">
      <span class="dot" id="dot"></span><span id="conn">در حال اتصال به __HOST_NAME__…</span><br>
      برای شروع، یک بار دکمه‌ی زیر را بزنید تا مرورگر اجازه‌ی پخش بدهد.<br>
      بعد از آن همه‌چیز با گوشی کنترل می‌شود.
    </div>
    <button class="primary" id="startBtn" style="font-size:17px;padding:14px 30px">شروع</button>
    <div class="stack" id="picker"></div>
    <div class="hint">
      کلیدهای کنترل تلویزیون: چپ/راست = جلو و عقب • OK = پخش/مکث • بالا/پایین = صدا
      <br>اگر می‌خواهید نسخه‌ی نصبی روی تلویزیون داشته باشید:
      <a href="/app.apk" style="color:var(--azure)">دانلود فایل نصبی</a>
    </div>
  </div>
</div>

<div class="glass" id="toast"></div>

<script>
(() => {
  const $ = (id) => document.getElementById(id);
  const V = $('v');
  const state = {
    started:false, cues:[], cursor:0, subId:null, delay:0, subs:[], title:'',
    fit:'contain', style:{size:34,color:0xFFFFFFFF,backdrop:.35,outline:true,bottom:6,bold:true},
    seeking:false, media:null,
  };
  let ws = null, retry = 0;

  // ---------- helpers ----------
  const fmt = (s) => {
    if (!isFinite(s) || s < 0) s = 0;
    s = Math.floor(s);
    const h = Math.floor(s/3600), m = Math.floor(s%3600/60), x = s%60;
    const p = (n) => String(n).padStart(2,'0');
    return (h ? p(h)+':' : '') + p(m)+':'+p(x);
  };
  const toast = (msg) => {
    const t = $('toast'); t.textContent = msg; t.classList.add('show');
    clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 1800);
  };

  // ---------- subtitles ----------
  function parseVtt(text){
    const cues = [];
    const stamp = /(\d{1,3}):(\d{1,2}):(\d{1,2})[.,](\d{1,3})\s*-->\s*(\d{1,3}):(\d{1,2}):(\d{1,2})[.,](\d{1,3})/;
    const ms = (h,m,s,f) => (+h)*3600000 + (+m)*60000 + (+s)*1000 + (+String(f).padEnd(3,'0'));
    for (const block of text.replace(/\r/g,'').split(/\n\n+/)) {
      const lines = block.split('\n');
      const i = lines.findIndex(l => stamp.test(l));
      if (i < 0) continue;
      const m = lines[i].match(stamp);
      const body = lines.slice(i+1).join('\n').trim();
      if (!body) continue;
      cues.push({ s: ms(m[1],m[2],m[3],m[4]), e: ms(m[5],m[6],m[7],m[8]), t: body });
    }
    cues.sort((a,b) => a.s - b.s);
    return cues;
  }

  function cueAt(ms){
    const c = state.cues;
    if (!c.length) return null;
    let i = state.cursor;
    if (i < c.length && ms >= c[i].s && ms < c[i].e) return c[i];
    let lo = 0, hi = c.length - 1, found = -1;
    while (lo <= hi) { const mid = (lo+hi)>>1; if (c[mid].s <= ms) { found = mid; lo = mid+1; } else hi = mid-1; }
    if (found < 0) { state.cursor = 0; return null; }
    state.cursor = found;
    return ms < c[found].e ? c[found] : null;
  }

  function paintSubs(){
    const box = $('subs');
    const st = state.style;
    const scale = (window.innerHeight || 1080) / 1080;
    box.style.fontSize = (st.size * scale) + 'px';
    box.style.bottom = st.bottom + '%';
    box.style.color = '#' + (st.color >>> 0).toString(16).padStart(8,'0').slice(2);
    box.style.fontWeight = st.bold ? 700 : 500;
    box.style.textShadow = st.outline
      ? '0 2px 6px rgba(0,0,0,.95),0 0 12px rgba(0,0,0,.85)' : 'none';
    const cue = state.cues.length ? cueAt(V.currentTime*1000 - state.delay) : null;
    if (!cue) { box.innerHTML = ''; return; }
    const dir = /[\u0590-\u08FF\uFB1D-\uFDFF]/.test(cue.t) ? 'rtl' : 'ltr';
    const span = document.createElement('span');
    span.style.background = 'rgba(0,0,0,' + st.backdrop + ')';
    span.dir = dir;
    span.textContent = cue.t;
    box.innerHTML = '';
    box.appendChild(span);
  }

  async function loadSub(id){
    state.subId = id; state.cues = []; state.cursor = 0;
    $('subs').innerHTML = '';
    if (!id) { paintSubs(); return; }
    const track = state.subs.find(s => s.id === id);
    if (!track) return;
    try {
      const res = await fetch(track.url);
      state.cues = parseVtt(await res.text());
      toast('زیرنویس: ' + track.label);
    } catch (e) { toast('زیرنویس بارگذاری نشد'); }
    paintSubs();
  }

  // ---------- playback ----------
  function applyMedia(media, startMs, subId){
    state.media = media;
    state.title = media.title || '';
    state.subs = media.subs || [];
    $('title').textContent = state.title;
    const url = new URL(media.url, location.origin).href;
    if (V.src !== url) { V.src = url; V.load(); }
    if (startMs) V.currentTime = startMs/1000;
    loadSub(subId || null);
    V.classList.add('live');
    $('bar').classList.remove('idle');
    hideSplash();
    V.play().catch(() => toast('برای شروع، دکمه‌ی پخش را بزنید'));
  }

  function hideSplash(){ if (state.started) $('splash').style.display = 'none'; }

  function setFit(f){
    state.fit = f;
    V.className = f === 'contain' ? '' : f;
  }

  // ---------- websocket ----------
  function connect(){
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    ws = new WebSocket(proto + '://' + location.host + '/ws?kind=web&name=' +
      encodeURIComponent('مرورگر تلویزیون'));

    ws.onopen = () => { retry = 0; $('dot').classList.add('on'); $('conn').textContent = 'متصل به __HOST_NAME__'; };
    ws.onclose = () => {
      $('dot').classList.remove('on'); $('conn').textContent = 'ارتباط قطع شد، تلاش دوباره…';
      retry = Math.min(retry + 1, 10);
      setTimeout(connect, 400 * retry);
    };
    ws.onerror = () => { try { ws.close(); } catch(e){} };
    ws.onmessage = (ev) => {
      let m; try { m = JSON.parse(ev.data); } catch(e){ return; }
      switch (m.t) {
        case 'load':    applyMedia(m.media, m.start || 0, m.sub); break;
        case 'play':    hideSplash(); V.play().catch(()=>{}); break;
        case 'pause':   V.pause(); break;
        case 'toggle':  V.paused ? V.play().catch(()=>{}) : V.pause(); break;
        case 'stop':    V.pause(); V.removeAttribute('src'); V.load();
                        V.classList.remove('live'); $('bar').classList.add('idle');
                        state.media=null; state.cues=[]; $('subs').innerHTML='';
                        $('title').textContent='آماده‌ی پخش';
                        $('splash').style.display='flex'; break;
        case 'seek':    V.currentTime = m.pos/1000; break;
        case 'nudge':   V.currentTime = Math.max(0, V.currentTime + m.delta/1000); break;
        case 'sub':     loadSub(m.id); break;
        case 'subDelay':state.delay = m.ms; paintSubs(); toast('تأخیر زیرنویس: ' + (m.ms/1000).toFixed(1) + ' ثانیه'); break;
        case 'subStyle':state.style = m; paintSubs(); break;
        case 'addSub':  state.subs = state.subs.concat([m.sub]); break;
        case 'rate':    V.playbackRate = m.v; toast('سرعت ' + m.v + '×'); break;
        case 'volume':  V.volume = Math.max(0, Math.min(1, m.v)); break;
        case 'fit':     setFit(m.v); break;
      }
    };
  }

  function report(){
    if (!ws || ws.readyState !== 1) return;
    ws.send(JSON.stringify({
      t:'state',
      title: state.title,
      pos: Math.round((V.currentTime||0)*1000),
      dur: Math.round((isFinite(V.duration) ? V.duration : 0)*1000),
      buf: V.buffered.length ? Math.round(V.buffered.end(V.buffered.length-1)*1000) : 0,
      playing: !V.paused && !V.ended,
      buffering: V.readyState < 3 && !V.paused,
      ready: V.readyState >= 1,
      sub: state.subId, subDelay: state.delay, rate: V.playbackRate, vol: V.volume,
      fit: state.fit, style: state.style, subs: state.subs,
      receiver: 'مرورگر تلویزیون',
    }));
  }

  // ---------- local controls ----------
  const seek = $('seek');
  seek.addEventListener('input', () => { state.seeking = true; });
  seek.addEventListener('change', () => {
    if (isFinite(V.duration)) V.currentTime = V.duration * (seek.value/1000);
    state.seeking = false;
  });
  $('play').onclick = () => { V.paused ? V.play().catch(()=>{}) : V.pause(); };
  $('back').onclick = () => { V.currentTime = Math.max(0, V.currentTime - 10); };
  $('fwd').onclick  = () => { V.currentTime = V.currentTime + 10; };
  $('delayDown').onclick = () => { state.delay -= 500; paintSubs(); toast('تأخیر زیرنویس: ' + (state.delay/1000).toFixed(1) + 'ث'); };
  $('delayUp').onclick   = () => { state.delay += 500; paintSubs(); toast('تأخیر زیرنویس: ' + (state.delay/1000).toFixed(1) + 'ث'); };
  $('fitBtn').onclick = () => {
    const order = ['contain','cover','stretch'];
    setFit(order[(order.indexOf(state.fit)+1) % 3]);
    toast({contain:'اندازه‌ی اصلی',cover:'پرکردن صفحه',stretch:'کشیده'}[state.fit]);
  };
  $('fsBtn').onclick = () => {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen?.().catch(()=>{});
  };
  $('subBtn').onclick = () => {
    const menu = $('menu');
    if (menu.classList.contains('show')) { menu.classList.remove('show'); return; }
    menu.innerHTML = '<h4>زیرنویس</h4>';
    const mk = (label, id) => {
      const b = document.createElement('button');
      b.className = 'opt' + (state.subId === id ? ' sel' : '');
      b.innerHTML = '<span>' + label + '</span><span>' + (state.subId === id ? '✓' : '') + '</span>';
      b.onclick = () => { loadSub(id); menu.classList.remove('show'); };
      menu.appendChild(b);
    };
    mk('خاموش', null);
    state.subs.forEach(s => mk(s.label, s.id));
    menu.classList.add('show');
    menu.querySelector('button')?.focus();
  };

  $('startBtn').onclick = async () => {
    state.started = true;
    // A user gesture unlocks autoplay for the rest of the session.
    try { await V.play(); } catch(e) {}
    if (state.media) hideSplash(); else toast('حالا از گوشی یک فیلم انتخاب کنید');
    $('splash').style.display = state.media ? 'none' : 'flex';
  };

  // Standalone fallback: play something already published without the phone.
  async function loadPicker(){
    try {
      const info = await (await fetch('/info')).json();
      const box = $('picker');
      box.innerHTML = '';
      (info.media || []).forEach(m => {
        const b = document.createElement('button');
        b.textContent = '▶  ' + m.title;
        b.onclick = () => { state.started = true; applyMedia(m, 0, null); };
        box.appendChild(b);
      });
    } catch(e) {}
  }

  // ---------- TV remote / keyboard ----------
  addEventListener('keydown', (e) => {
    const k = e.key;
    if (k === 'ArrowRight') { V.currentTime += 10; showBar(); e.preventDefault(); }
    else if (k === 'ArrowLeft') { V.currentTime = Math.max(0, V.currentTime - 10); showBar(); e.preventDefault(); }
    else if (k === 'ArrowUp') { V.volume = Math.min(1, V.volume + .1); showBar(); }
    else if (k === 'ArrowDown') { V.volume = Math.max(0, V.volume - .1); showBar(); }
    else if (k === ' ' || k === 'Enter' || k === 'MediaPlayPause') {
      if (e.target.tagName !== 'BUTTON') { V.paused ? V.play() : V.pause(); showBar(); e.preventDefault(); }
    }
    else if (k === 'f') $('fsBtn').click();
    else if (k === ',') $('delayDown').click();
    else if (k === '.') $('delayUp').click();
    else showBar();
  });

  // ---------- auto-hiding bar ----------
  let hideTimer;
  function showBar(){
    $('bar').classList.remove('hide');
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      if (!V.paused) { $('bar').classList.add('hide'); $('menu').classList.remove('show'); }
    }, 3500);
  }
  ['mousemove','touchstart','click'].forEach(e => addEventListener(e, showBar));

  // ---------- ticker ----------
  V.addEventListener('waiting', () => $('spin').classList.add('show'));
  V.addEventListener('playing', () => $('spin').classList.remove('show'));
  V.addEventListener('canplay', () => $('spin').classList.remove('show'));
  V.addEventListener('play',  () => { $('play').textContent = '❚❚'; showBar(); });
  V.addEventListener('pause', () => { $('play').textContent = '▶'; showBar(); });
  V.addEventListener('error', () => toast('پخش این فایل ممکن نشد'));

  function tick(){
    if (!state.seeking && isFinite(V.duration) && V.duration > 0) {
      seek.value = Math.round(1000 * V.currentTime / V.duration);
    }
    $('time').textContent = fmt(V.currentTime) + ' / ' + fmt(V.duration);
    paintSubs();
    requestAnimationFrame(tick);
  }

  connect();
  loadPicker();
  showBar();
  requestAnimationFrame(tick);
  setInterval(report, 250);
})();
</script>
</body>
</html>
''';
}
