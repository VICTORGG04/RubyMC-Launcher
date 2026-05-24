(() => {
  'use strict';

  const API = {
    status: '/api/status',
    logs: '/api/logs',
    action: '/api/action',
    modpacks: '/api/modpacks',
    importModpack: '/api/modpacks/import',
    discordStatus: '/api/discord/status',
    discordValidate: '/api/discord/validate',
    discordTestLog: '/api/discord/test-log',
    ping: '/api/ping'
  };

  const state = {
    busy: false,
    activeTab: 'home',
    lastLogText: '',
    modpacks: [],
    bootedAt: new Date()
  };

  const ACTION_ALIASES = {
    clear: 'clear_logs',
    clear_log: 'clear_logs',
    clear_logs: 'clear_logs',
    limpar: 'clear_logs',
    refresh: 'refresh_status',
    atualizar: 'refresh_status',
    refresh_status: 'refresh_status',
    run_tests: 'run_tests',
    tests: 'run_tests',
    test: 'run_tests',
    refresh_modpacks: 'refresh_modpacks',
    update_modpacks: 'refresh_modpacks',
    play: 'play',
    jogar: 'play',
    enter_server: 'enter_server',
    test_server: 'test_server',
    organize_project: 'organize_project',
    launch_classic: 'launch_classic',
    classic: 'launch_classic',
    validate_discord_config: 'validate_discord_config',
    validate_discord: 'validate_discord_config',
    test_discord_log: 'test_discord_log',
    discord_test_log: 'test_discord_log'
  };

  function $(selector, root = document) {
    return root.querySelector(selector);
  }

  function $all(selector, root = document) {
    return Array.from(root.querySelectorAll(selector));
  }

  function logConsole(...args) {
    // Ajuda a diagnosticar se o JS carregou no DevTools.
    console.log('[RubyMC Web]', ...args);
  }

  function normalizeAction(action) {
    const key = String(action || '').trim().toLowerCase().replace(/-/g, '_');
    return ACTION_ALIASES[key] || key;
  }

  function normalizeTab(tab) {
    const key = String(tab || '').trim().toLowerCase().replace(/-/g, '_');
    if (key === 'inicio' || key === 'início') return 'home';
    if (key === 'servidor') return 'server';
    if (key === 'projeto') return 'project';
    return key;
  }

  async function requestJSON(url, options = {}) {
    const isFormData = options.body instanceof FormData;
    const requestOptions = {
      cache: 'no-store',
      credentials: 'same-origin',
      ...options,
      headers: {
        ...(isFormData ? {} : { 'Content-Type': 'application/json' }),
        ...(options.headers || {})
      }
    };

    const response = await fetch(url, requestOptions);
    const text = await response.text();
    let data = {};

    try {
      data = text ? JSON.parse(text) : {};
    } catch (_) {
      data = { ok: false, error: text || `Resposta inválida de ${url}` };
    }

    if (!response.ok || data.ok === false) {
      const message = data.error || data.message || `HTTP ${response.status} em ${url}`;
      const error = new Error(message);
      error.payload = data;
      throw error;
    }

    return data;
  }

  function setText(selectors, value) {
    for (const selector of selectors) {
      const node = $(selector);
      if (node) node.textContent = value ?? '--';
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

  function localTimestamp() {
    return new Date().toLocaleTimeString('pt-BR', { hour12: false });
  }

  function appendLocalLog(line) {
    const display = findDisplayNode();
    const current = display ? display.textContent : state.lastLogText;
    const prefix = current && !current.includes('Conectando ao backend') ? current.split('\n') : [];
    prefix.push(`[${localTimestamp()}] JS      ${line}`);
    renderLogs(prefix.slice(-250));
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

  function setStatusLabel(message, ok = true) {
    setText(['#connectionStatus', '#displayStatus', '[data-field="display_status"]', '.display-status'], message);
    const badge = $('#connectionStatus') || $('#displayStatus') || $('[data-field="display_status"]') || $('.display-status');
    if (badge) {
      badge.classList.toggle('is-ok', ok);
      badge.classList.toggle('is-error', !ok);
    }
  }

  function escapeHTML(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;'
    }[char]));
  }

  function renderModpacks(modpacks) {
    state.modpacks = Array.isArray(modpacks) ? modpacks : [];

    const list = $('#modpackList');
    if (list) {
      if (state.modpacks.length === 0) {
        list.innerHTML = '<div class="empty-state">Nenhum modpack importado ainda.</div>';
      } else {
        list.innerHTML = state.modpacks.map((pack) => `
          <div class="modpack-item">
            <div>
              <strong>${escapeHTML(pack.name || pack.id || 'Modpack')}</strong>
              <span>${escapeHTML([pack.minecraft_version, pack.loader].filter(Boolean).join(' • ') || 'perfil local')}</span>
            </div>
            <small>${escapeHTML(pack.source || 'local')}</small>
          </div>
        `).join('');
      }
    }

    const select = $('#profileSelect');
    if (select) {
      const current = select.value;
      select.innerHTML = '<option value="vanilla">Vanilla / sem modpack</option>' + state.modpacks.map((pack) => {
        const value = escapeHTML(pack.id || pack.name || 'modpack');
        const label = escapeHTML(pack.name || pack.id || 'Modpack');
        return `<option value="${value}">${label}</option>`;
      }).join('');
      if ([...select.options].some((option) => option.value === current)) select.value = current;
    }

    setText(['#modpacksCount', '[data-field="modpacks_count"]', '.modpacks-count'], String(state.modpacks.length));
  }

  function renderDiscord(discord) {
    if (!discord) return;
    setText(['#discordBotStatus'], discord.bot_enabled ? 'ativo' : 'inativo');
    setText(['#discordChannelsCount'], `${discord.channels_configured ?? 0}/${discord.channels_total ?? 0}`);
    setText(['#discordRolesCount'], `${discord.roles_configured ?? 0}/${discord.roles_total ?? 0}`);
    setText(['#discordConfigStatus'], discord.status || '--');
    setText(['#discordLogsChannel'], discord.logs_channel_configured ? 'configurado' : 'pendente');
  }

  async function refreshStatus() {
    try {
      const data = await requestJSON(API.status);
      setStatusLabel('Display conectado', true);

      setText(['#rubyVersion', '[data-field="ruby_version"]', '.ruby-version'], data.ruby_version || '--');
      setText(['#javaVersion', '[data-field="java_version"]', '.java-version'], data.java_version || '--');
      setText(['#serverStatus', '[data-field="server_status"]', '.server-status'], data.server?.status || '--');
      setText(['#serverAddress', '[data-field="server_address"]', '.server-address'], data.server?.address || '--');

      renderDiscord(data.discord);

      if (Array.isArray(data.modpacks)) renderModpacks(data.modpacks);
    } catch (error) {
      setStatusLabel('Display desconectado', false);
      appendLocalLog(`ERRO   Backend não respondeu: ${error.message}`);
    }
  }

  async function refreshLogs() {
    try {
      const data = await requestJSON(API.logs);
      renderLogs(data.logs || []);
    } catch (error) {
      appendLocalLog(`ERRO   Não foi possível ler logs: ${error.message}`);
    }
  }

  async function refreshModpacks(logAction = true) {
    try {
      const data = await requestJSON(API.modpacks);
      renderModpacks(data.modpacks || []);
      if (logAction) await refreshLogs();
    } catch (error) {
      appendLocalLog(`ERRO   Não foi possível atualizar modpacks: ${error.message}`);
    }
  }

  function setBusy(isBusy) {
    state.busy = isBusy;
    $all('[data-action], #modpackImportForm button').forEach((button) => {
      const action = normalizeAction(button.dataset.action);
      if (!['clear_logs', 'refresh_status', 'refresh_modpacks'].includes(action)) {
        button.disabled = isBusy;
      }
    });
  }

  async function runAction(rawAction) {
    const action = normalizeAction(rawAction);
    if (!action) return;

    if (state.busy && !['clear_logs', 'refresh_status', 'refresh_modpacks'].includes(action)) {
      appendLocalLog('WARN   Aguarde a ação atual terminar.');
      return;
    }

    try {
      setBusy(true);
      logConsole('Ação acionada:', action);

      if (action === 'refresh_modpacks') {
        appendLocalLog('ACTION Atualizando lista de modpacks...');
        await requestJSON(API.action, { method: 'POST', body: JSON.stringify({ action }) });
        await refreshModpacks(false);
        await refreshLogs();
        return;
      }

      if (action === 'validate_discord_config') {
        showTab('display');
        appendLocalLog('ACTION Validando Discord pelo backend...');
        await requestJSON(API.discordValidate, { method: 'POST', body: JSON.stringify({ action }) });
        await refreshStatus();
        await refreshLogs();
        return;
      }

      if (action === 'test_discord_log') {
        showTab('display');
        appendLocalLog('ACTION Enviando mensagem de teste para o Discord...');
        await requestJSON(API.discordTestLog, { method: 'POST', body: JSON.stringify({ action }) });
        await refreshStatus();
        await refreshLogs();
        return;
      }

      await requestJSON(API.action, {
        method: 'POST',
        body: JSON.stringify({ action })
      });

      if (action === 'clear_logs') renderLogs([]);
      await refreshStatus();
      await refreshLogs();
    } catch (error) {
      appendLocalLog(`ERRO   ${error.message}`);
      showTab('display');
    } finally {
      setBusy(false);
    }
  }

  async function importModpack(event) {
    event.preventDefault();

    const form = event.currentTarget;
    const fileInput = $('#modpackFile', form);
    const file = fileInput?.files?.[0];

    if (!file) {
      appendLocalLog('WARN   Selecione um arquivo .mrpack ou .zip antes de importar.');
      showTab('display');
      return;
    }

    if (!/\.(mrpack|zip)$/i.test(file.name)) {
      appendLocalLog(`WARN   Formato não suportado: ${file.name}. Use .mrpack ou .zip.`);
      showTab('display');
      return;
    }

    const formData = new FormData(form);

    try {
      setBusy(true);
      appendLocalLog(`ACTION Importando modpack: ${file.name}`);
      showTab('display');

      await requestJSON(API.importModpack, {
        method: 'POST',
        body: formData
      });

      form.reset();
      updateSelectedFileName();
      await refreshStatus();
      await refreshModpacks(false);
      await refreshLogs();
    } catch (error) {
      appendLocalLog(`ERRO   Falha ao importar modpack: ${error.message}`);
    } finally {
      setBusy(false);
    }
  }

  function updateSelectedFileName() {
    const fileInput = $('#modpackFile');
    const label = $('#modpackFileName');
    if (!label) return;
    const file = fileInput?.files?.[0];
    label.textContent = file ? file.name : 'Clique para escolher um .mrpack ou .zip';
  }

  function showTab(rawTab) {
    const tabName = normalizeTab(rawTab || 'home');
    state.activeTab = tabName;

    $all('[data-tab-target], [data-tab], .nav-item, .tab-button').forEach((button) => {
      const target = normalizeTab(button.dataset.tabTarget || button.dataset.tab || inferTabFromText(button.textContent));
      const active = target === tabName;
      button.classList.toggle('active', active);
      button.classList.toggle('is-active', active);
    });

    $all('[data-panel], .panel').forEach((panel) => {
      const panelName = normalizeTab(panel.dataset.panel || panel.id);
      const active = panelName === tabName || panel.id === `${tabName}-panel`;
      panel.classList.toggle('active', active);
      panel.classList.toggle('is-active', active);
      if (panel.classList.contains('panel')) panel.hidden = !active;
    });
  }

  function inferTabFromText(text) {
    const normalized = String(text || '').toLowerCase();
    if (normalized.includes('início') || normalized.includes('inicio')) return 'home';
    if (normalized.includes('modpack')) return 'modpacks';
    if (normalized.includes('servidor')) return 'server';
    if (normalized.includes('discord')) return 'discord';
    if (normalized.includes('display')) return 'display';
    if (normalized.includes('projeto')) return 'project';
    return '';
  }

  function inferActionFromButton(button) {
    const explicit = button.dataset.action;
    if (explicit) return explicit;

    const text = String(button.textContent || '').trim().toLowerCase();
    if (text.includes('rodar testes')) return 'run_tests';
    if (text.includes('atualizar modpacks') || text.includes('atualizar lista')) return 'refresh_modpacks';
    if (text.includes('atualizar')) return 'refresh_status';
    if (text.includes('limpar')) return 'clear_logs';
    if (text.includes('jogar')) return 'play';
    if (text.includes('entrar no servidor')) return 'enter_server';
    if (text.includes('testar servidor')) return 'test_server';
    if (text.includes('validar discord')) return 'validate_discord_config';
    if (text.includes('canal de logs')) return 'test_discord_log';
    if (text.includes('organizar')) return 'organize_project';
    if (text.includes('clássico') || text.includes('classico')) return 'launch_classic';
    return null;
  }

  function bindDelegatedEvents() {
    document.addEventListener('click', (event) => {
      const clickable = event.target.closest('button, a, [role="button"], [data-action], [data-tab-target], [data-tab]');
      if (!clickable) return;

      const targetTab = clickable.dataset.tabTarget || clickable.dataset.tab;
      const action = clickable.dataset.action || inferActionFromButton(clickable);

      if (targetTab && !action) {
        event.preventDefault();
        showTab(targetTab);
        return;
      }

      if (action) {
        event.preventDefault();
        runAction(action);
      }
    }, true);

    const form = $('#modpackImportForm');
    if (form) form.addEventListener('submit', importModpack);

    const fileInput = $('#modpackFile');
    if (fileInput) fileInput.addEventListener('change', updateSelectedFileName);
  }

  function fixButtonTypes() {
    $all('button').forEach((button) => {
      if (!button.hasAttribute('type')) button.type = 'button';
      const action = button.dataset.action || inferActionFromButton(button);
      if (action) button.dataset.action = normalizeAction(action);
    });
  }

  async function boot() {
    logConsole('launcher.js carregado. Boot iniciado.');
    fixButtonTypes();
    bindDelegatedEvents();
    showTab('home');
    appendLocalLog('SYSTEM JS conectado. Botões habilitados.');

    await refreshStatus();
    await refreshLogs();
    await refreshModpacks(false);

    setInterval(refreshStatus, 2500);
    setInterval(refreshLogs, 1000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
