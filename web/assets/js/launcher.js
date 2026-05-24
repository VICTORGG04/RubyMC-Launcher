(() => {
  const API = {
    status: '/api/status',
    logs: '/api/logs',
    action: '/api/action'
  };

  const state = {
    busy: false,
    activeTab: 'home',
    lastLogText: ''
  };

  function $(selector, root = document) {
    return root.querySelector(selector);
  }

  function $all(selector, root = document) {
    return Array.from(root.querySelectorAll(selector));
  }

  async function requestJSON(url, options = {}) {
    const response = await fetch(url, {
      cache: 'no-store',
      headers: { 'Content-Type': 'application/json' },
      ...options
    });

    const text = await response.text();
    let data = {};
    try { data = text ? JSON.parse(text) : {}; } catch (_) { data = { ok: false, error: text }; }

    if (!response.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }

    return data;
  }

  function setText(selectors, value) {
    for (const selector of selectors) {
      const node = $(selector);
      if (node) node.textContent = value;
    }
  }

  function setStatusLabel(message, ok = true) {
    setText(['#connectionStatus', '#displayStatus', '[data-field="display_status"]', '.display-status'], message);
    const badge = $('#connectionStatus') || $('#displayStatus') || $('[data-field="display_status"]') || $('.display-status');
    if (badge) {
      badge.classList.toggle('is-ok', ok);
      badge.classList.toggle('is-error', !ok);
    }
  }

  function findDisplayNode() {
    return $('#displayLog') ||
      $('#display-log') ||
      $('#displayOutput') ||
      $('[data-display-log]') ||
      $('.display-log') ||
      $('.display-output') ||
      $('.terminal-output') ||
      $('.console-output') ||
      $('pre');
  }

  function renderLogs(lines) {
    const node = findDisplayNode();
    if (!node) return;

    const text = (lines || []).join('\n');
    if (text === state.lastLogText) return;

    state.lastLogText = text;
    node.textContent = text || '[Display] Aguardando eventos...';
    node.scrollTop = node.scrollHeight;
  }

  async function refreshStatus() {
    try {
      const data = await requestJSON(API.status);
      setStatusLabel('Display conectado', true);

      setText(['#rubyVersion', '[data-field="ruby_version"]', '.ruby-version'], data.ruby_version || '--');
      setText(['#javaVersion', '[data-field="java_version"]', '.java-version'], data.java_version || '--');
      setText(['#modpacksCount', '[data-field="modpacks_count"]', '.modpacks-count'], String(data.modpacks_count ?? '0'));
      setText(['#serverStatus', '[data-field="server_status"]', '.server-status'], data.server?.status || '--');
      setText(['#serverAddress', '[data-field="server_address"]', '.server-address'], data.server?.address || '--');
    } catch (error) {
      setStatusLabel('Display desconectado', false);
      renderLogs([`[ERRO] Falha ao conectar ao backend: ${error.message}`]);
    }
  }

  async function refreshLogs() {
    try {
      const data = await requestJSON(API.logs);
      renderLogs(data.logs || []);
    } catch (error) {
      renderLogs([`[ERRO] Não foi possível ler logs: ${error.message}`]);
    }
  }

  function setBusy(isBusy) {
    state.busy = isBusy;
    $all('[data-action]').forEach((button) => {
      const action = button.dataset.action;
      if (action !== 'clear_logs' && action !== 'refresh_status') {
        button.disabled = isBusy;
      }
    });
  }

  async function runAction(action) {
    if (!action) return;

    if (state.busy && !['clear_logs', 'refresh_status'].includes(action)) return;

    try {
      setBusy(true);
      await requestJSON(API.action, {
        method: 'POST',
        body: JSON.stringify({ action })
      });
      await refreshStatus();
      await refreshLogs();
    } catch (error) {
      renderLogs([...(state.lastLogText ? state.lastLogText.split('\n') : []), `[ERRO] ${error.message}`]);
    } finally {
      setBusy(false);
    }
  }

  function normalizeText(text) {
    return (text || '').trim().toLowerCase();
  }

  function inferActionFromButton(button) {
    const explicit = button.dataset.action;
    if (explicit) return explicit;

    const text = normalizeText(button.textContent);
    if (text.includes('rodar testes')) return 'run_tests';
    if (text.includes('atualizar')) return 'refresh_status';
    if (text.includes('limpar')) return 'clear_logs';
    if (text.includes('abrir display')) return 'refresh_status';
    if (text === 'jogar' || text.includes('jogar')) return 'play';
    if (text.includes('entrar no servidor')) return 'enter_server';
    if (text.includes('testar servidor')) return 'test_server';
    if (text.includes('organizar')) return 'organize_project';
    if (text.includes('clássico') || text.includes('classico')) return 'launch_classic';

    return null;
  }

  function bindActions() {
    $all('button, a').forEach((button) => {
      const action = inferActionFromButton(button);
      if (!action) return;

      button.dataset.action = action;
      button.addEventListener('click', (event) => {
        event.preventDefault();
        runAction(action);
      });
    });
  }

  function showTab(tabName) {
    state.activeTab = tabName;

    $all('[data-tab-target], [data-tab]').forEach((button) => {
      const target = button.dataset.tabTarget || button.dataset.tab;
      button.classList.toggle('active', target === tabName);
      button.classList.toggle('is-active', target === tabName);
    });

    $all('[data-panel], .panel').forEach((panel) => {
      const panelName = panel.dataset.panel || panel.id;
      const active = panelName === tabName || panelName === `${tabName}-panel`;
      panel.classList.toggle('active', active);
      panel.classList.toggle('is-active', active);
      if (panel.classList.contains('panel')) {
        panel.hidden = !active;
      }
    });
  }

  function bindTabs() {
    const tabButtons = $all('[data-tab-target], [data-tab], .nav-item, .tab-button');

    tabButtons.forEach((button) => {
      let target = button.dataset.tabTarget || button.dataset.tab;

      if (!target) {
        const text = normalizeText(button.textContent);
        if (text.includes('início') || text.includes('inicio')) target = 'home';
        if (text.includes('modpack')) target = 'modpacks';
        if (text.includes('servidor')) target = 'server';
        if (text.includes('display')) target = 'display';
        if (text.includes('projeto')) target = 'project';
      }

      if (!target) return;

      button.dataset.tabTarget = target;
      button.addEventListener('click', (event) => {
        event.preventDefault();
        showTab(target);
      });
    });

    showTab('home');
  }

  function boot() {
    bindTabs();
    bindActions();
    refreshStatus();
    refreshLogs();

    setInterval(refreshStatus, 2500);
    setInterval(refreshLogs, 1000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
