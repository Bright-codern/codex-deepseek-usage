// ==UserScript==
// @name         DeepSeek 消耗
// @description  在 Codex 顶部菜单栏加一个「消耗」按钮，显示 DeepSeek 充值余额与今日消费
// @version      1.0.3
// @match        app://-/*
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  var VERSION = '1.0.3';
  if (window.__dsUsageUIVersion === VERSION) return;
  window.__dsUsageUIVersion = VERSION;

  var legacyButton = document.getElementById('ds-usage-menu-trigger');
  if (legacyButton && legacyButton.parentNode) legacyButton.parentNode.removeChild(legacyButton);
  var legacyPanel = document.getElementById('ds-usage-panel');
  if (legacyPanel && legacyPanel.parentNode) legacyPanel.parentNode.removeChild(legacyPanel);

  var BTN_ID = 'ds-usage-menu-trigger';
  var PANEL_ID = 'ds-usage-panel';
  var STATE = { open: false, panel: null, btn: null, hintTimer: null };
  var DATA = window.__DSUsage || null;

  function money(value, symbol) {
    if (value === null || value === undefined || value === '') return '—';
    var n = Number(value);
    if (!isFinite(n)) return String(value);
    return (symbol || '') + n.toFixed(2);
  }

  function timeText(ts) {
    if (!ts) return '—';
    var d = new Date(ts);
    function p(x) { return (x < 10 ? '0' : '') + x; }
    return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
  }

  function sourceText(data) {
    if (!data) return '';
    if (data.todaySpendSource === 'platform') return '官网账单';
    if (data.todaySpendSource === 'balance') return data.todaySpendLowerBound ? '余额差值（下限）' : '余额差值';
    return '';
  }

  function row(label, value, extraClass) {
    var wrap = document.createElement('div');
    wrap.style.cssText = 'display:flex;align-items:baseline;justify-content:space-between;gap:16px;padding:3px 0;';

    var l = document.createElement('span');
    l.textContent = label;
    l.style.cssText = 'color:var(--color-token-text-secondary, rgba(0,0,0,.55));flex:0 0 auto;font-weight:400;font-family:inherit;';

    var v = document.createElement('span');
    v.textContent = value;
    v.style.cssText = 'font-variant-numeric:tabular-nums;text-align:right;font-weight:400;font-family:inherit;' + (extraClass || '');

    wrap.append(l, v);
    return wrap;
  }

  function buildPanel() {
    var panel = document.createElement('div');
    panel.id = PANEL_ID;
    panel.style.cssText = [
      'position:fixed',
      'z-index:2147483000',
      'min-width:212px',
      'padding:12px 14px 10px',
      'border-radius:12px',
      'border:1px solid var(--color-token-border, rgba(0,0,0,.08))',
      'background:var(--color-token-main-surface-primary, #fff)',
      'color:var(--color-token-text-primary, #1a1c1f)',
      'box-shadow:0 10px 30px rgba(0,0,0,.18)',
      'font-size:13px',
      'line-height:1.55',
      'user-select:none'
    ].join(';');

    var title = document.createElement('div');
    title.textContent = 'DeepSeek 消耗';
    title.style.cssText = 'font-weight:600;font-size:13px;margin-bottom:8px;';

    var body = document.createElement('div');
    body.dataset.dsPart = 'body';

    var footer = document.createElement('div');
    footer.dataset.dsPart = 'footer';
    footer.style.cssText = [
      'display:flex',
      'align-items:center',
      'justify-content:space-between',
      'gap:10px',
      'margin-top:10px',
      'padding-top:8px',
      'border-top:1px solid var(--color-token-border, rgba(0,0,0,.08))'
    ].join(';');

    var stamp = document.createElement('span');
    stamp.dataset.dsPart = 'stamp';
    stamp.style.cssText = 'color:var(--color-token-text-secondary, rgba(0,0,0,.55));font-size:12px;font-weight:400;font-family:inherit;';

    var refresh = document.createElement('button');
    refresh.type = 'button';
    refresh.dataset.dsPart = 'refresh';
    refresh.textContent = '刷新';
    refresh.style.cssText = [
      'cursor:pointer',
      'border:1px solid var(--color-token-border, rgba(0,0,0,.12))',
      'background:transparent',
      'color:inherit',
      'border-radius:7px',
      'padding:2px 10px',
      'font-size:12px',
      'font-weight:400',
      'font-family:inherit',
      'line-height:1.5'
    ].join(';');
    refresh.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      requestRefresh();
    });

    footer.append(stamp, refresh);
    panel.append(title, body, footer);
    return panel;
  }

  function render() {
    if (!STATE.panel) return;
    var body = STATE.panel.querySelector('[data-ds-part=body]');
    var stamp = STATE.panel.querySelector('[data-ds-part=stamp]');
    if (!body || !stamp) return;

    body.textContent = '';
    var data = DATA;

    if (!data) {
      body.textContent = '等待助手进程…';
      body.style.color = 'var(--color-token-text-secondary, rgba(0,0,0,.55))';
      stamp.textContent = '';
      return;
    }

    body.style.color = '';

    if (data.error && !data.ok) {
      body.textContent = '获取失败：' + data.error;
      body.style.color = 'var(--color-token-text-secondary, rgba(0,0,0,.55))';
      stamp.textContent = timeText(data.updatedAt);
      return;
    }

    var symbol = data.symbol || '';
    var rows = [];

    if (data.toppedUpBalance !== null && data.toppedUpBalance !== undefined) {
      rows.push(row('充值余额', money(data.toppedUpBalance, symbol)));
    }
    rows.push(row('今日消费', money(data.todaySpend, symbol)));

    rows.forEach(function (r) { body.append(r); });

    var src = sourceText(data);
    if (src) {
      var note = document.createElement('div');
      note.textContent = '来源：' + src + (data.currency ? '（' + data.currency + '）' : '');
      note.style.cssText = 'margin-top:6px;font-size:12px;font-weight:400;font-family:inherit;color:var(--color-token-text-secondary, rgba(0,0,0,.55));';
      body.append(note);
    }

    stamp.textContent = data.updatedAt ? '同步于 ' + timeText(data.updatedAt) : '未同步';
  }

  function positionPanel() {
    if (!STATE.btn || !STATE.panel) return;
    var rect = STATE.btn.getBoundingClientRect();
    var width = STATE.panel.offsetWidth || 212;
    var left = Math.min(rect.left, Math.max(8, window.innerWidth - width - 8));
    STATE.panel.style.left = Math.round(left) + 'px';
    STATE.panel.style.top = Math.round(rect.bottom + 6) + 'px';
  }

  function closePanel() {
    if (STATE.panel && STATE.panel.parentNode) STATE.panel.parentNode.removeChild(STATE.panel);
    STATE.panel = null;
    STATE.open = false;
    document.removeEventListener('mousedown', onDocMouseDown, true);
    window.removeEventListener('resize', positionPanel, true);
  }

  function onDocMouseDown(event) {
    if (!STATE.panel) return;
    if (STATE.panel.contains(event.target)) return;
    if (STATE.btn && STATE.btn.contains(event.target)) return;
    closePanel();
  }

  function openPanel() {
    if (STATE.open) return;
    STATE.panel = buildPanel();
    document.body.append(STATE.panel);
    STATE.open = true;
    positionPanel();
    render();
    document.addEventListener('mousedown', onDocMouseDown, true);
    window.addEventListener('resize', positionPanel, true);
    requestRefresh();
  }

  function togglePanel() {
    if (STATE.open) closePanel(); else openPanel();
  }

  function requestRefresh() {
    try { window.__dsUsageRefreshFlag = true; } catch (error) {}
    var btn = STATE.btn;
    if (btn) {
      btn.dataset.dsBusy = '1';
      window.setTimeout(function () { if (btn) btn.dataset.dsBusy = ''; }, 1500);
    }
  }

  function ensureButton() {
    var bar = document.querySelector('[role=menubar]');
    if (!bar) return;
    if (bar.querySelector('#' + BTN_ID)) { STATE.btn = bar.querySelector('#' + BTN_ID); return; }

    var siblings = bar.querySelectorAll('button[role=menuitem]');
    var template = siblings.length ? siblings[0] : null;
    var anchor = bar.querySelector('#application-menu-content-anchor');

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.id = BTN_ID;
    btn.setAttribute('role', 'menuitem');
    btn.setAttribute('aria-haspopup', 'menu');
    btn.setAttribute('aria-expanded', 'false');
    btn.textContent = '消耗';
    if (template && template.className) btn.className = template.className;
    else btn.style.cssText = 'padding:2px 10px;border-radius:10px;border:1px solid transparent;background:transparent;cursor:pointer;';

    btn.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      togglePanel();
    });

    if (anchor && anchor.parentNode === bar) bar.insertBefore(btn, anchor);
    else bar.append(btn);

    STATE.btn = btn;
  }

  function apply(data) {
    DATA = data;
    window.__DSUsage = data;
    if (STATE.open) render();
  }
  window.__dsUsageApply = apply;

  window.addEventListener('message', function (event) {
    var message = event && event.data;
    if (message && message.type === 'ds-usage-data') apply(message.payload);
  }, true);

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && STATE.open) closePanel();
  }, true);

  var observer = new MutationObserver(function () { ensureButton(); });
  function boot() {
    ensureButton();
    if (!STATE.btn) window.setTimeout(boot, 800);
    if (document.body) observer.observe(document.body, { childList: true, subtree: true });
  }
  boot();
})();



