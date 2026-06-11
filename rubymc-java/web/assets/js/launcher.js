/* =========================================================
   RubyMC Launcher - Safe JSON Edition
   Corrige: unexpected end of input at line 1 column 1
   Causa: algum endpoint retornou HTTP 200/204 com corpo vazio
   ========================================================= */
(() => {
  "use strict";

  let busy = false;
  let authPollTimer = null;
  let serverPollTimer = null;
  let installedVersions = [];
  let activeVersion = null;
  let currentEdition = "java";

  const ROUTES = {
    status: ["/api/status", "/status"],
    logs: ["/api/logs", "/logs"],
    modpackImport: ["/api/modpacks/import", "/api/import_modpack", "/api/modpack/import"],
    modpacks: ["/api/modpacks", "/api/modpacks/list"],
    serverStatus: ["/api/server/status", "/api/server/live"]
  };

  const ACTION_ALIASES = {
    play: ["play", "start_minecraft", "launch_minecraft"],
    play_online: ["play_online", "play", "start_minecraft", "launch_minecraft"],
    play_offline: ["play_offline", "play", "start_minecraft", "launch_minecraft"],
    join_server: ["join_server", "server_join"],
    enter_server: ["enter_server"],
    update_modpacks: ["update_modpacks", "refresh_modpacks", "list_modpacks"],
    validate_discord: ["validate_discord", "discord_validate", "validate_discord_settings"],
    discord_simulate: ["discord_simulate", "simular_discord"],
    test_discord_logs: ["test_discord_logs", "discord_test_logs", "test_logs_channel"],
    test_all_channels: ["test_all_channels", "discord_test_channels", "test_channels"],
    create_invite: ["create_invite", "discord_create_invite", "generate_invite"],
    test_server: ["test_server", "server_test", "check_server"],
    clear_display: ["clear_display", "display_clear"],
    run_tests: ["run_tests", "test"],
    organize_project: ["organize_project", "organize"],
    open_project_folder: ["open_project_folder", "project_folder"],
    open_docs: ["open_docs", "docs"],
    check_updates: ["check_updates", "update_check"],
    refresh_status: ["refresh_status", "status"]
  };

  const GUARDED_ACTIONS = new Set([
    "validate_discord", "discord_validate", "test_discord_logs", "discord_test_logs",
    "test_logs_channel", "test_all_channels", "discord_test_channels", "test_channels",
    "create_invite", "discord_create_invite", "generate_invite", "join_server",
    "server_join", "enter_server", "start_server", "server_start", "stop_server",
    "server_stop", "restart_server", "server_restart", "play", "play_online",
    "play_offline", "start_minecraft", "launch_minecraft", "launch_classic"
  ]);

  const SERVER_CONTROL_ACTIONS = new Set([
    "test_server",
    "start_server",
    "stop_server",
    "restart_server"
  ]);

  const ROLE_TABS = {
    admin: ['home', 'server', 'versions', 'modpacks', 'ai', 'vip', 'db', 'display', 'project', 'settings'],
    staff: ['home', 'server', 'versions', 'modpacks', 'ai', 'vip', 'db', 'display', 'project', 'settings'],
    player: ['home', 'server', 'versions', 'modpacks', 'ai', 'vip', 'display', 'project', 'settings'],
    member: ['home', 'modpacks', 'display', 'settings']
  };

  const runningActions = new Set();

  function setValue(id, value) {
    const element = document.getElementById(id);
    if (element && value !== undefined && value !== null && value !== "") {
      element.value = String(value);
    }
  }

  function setClass(id, className, enabled) {
    const element = document.getElementById(id);
    if (element) element.classList.toggle(className, Boolean(enabled));
  }

  class ApiError extends Error {
    constructor(message, data = null, status = 0, endpointName = "requisição") {
      super(message);
      this.name = "ApiError";
      this.data = data;
      this.status = status;
      this.endpointName = endpointName;
      this.restartRequired = Boolean(data && data.restart_required);
    }
  }

  async function safeJson(response, endpointName = "requisição") {
    const text = await response.text();
    const trimmed = text.trim();
    let parsed = null;

    if (trimmed) {
      try {
        parsed = JSON.parse(trimmed);
      } catch (error) {
        if (!response.ok) {
          throw new ApiError(
              `Backend retornou HTTP ${response.status} em ${endpointName}: ${trimmed}`,
              null,
              response.status,
              endpointName
          );
        }

        throw new ApiError(
            `Resposta inválida do backend em ${endpointName}: ${error.message}`,
            null,
            response.status,
            endpointName
        );
      }
    }

    if (!response.ok) {
      const backendMessage =
          parsed?.error ||
          parsed?.message ||
          parsed?.details ||
          trimmed ||
          "corpo vazio";

      throw new ApiError(
          `Backend retornou HTTP ${response.status} em ${endpointName}: ${backendMessage}`,
          parsed,
          response.status,
          endpointName
      );
    }

    if (!trimmed) {
      throw new ApiError(
          `Backend retornou resposta vazia em ${endpointName}`,
          null,
          response.status,
          endpointName
      );
    }

    return parsed;
  }

  async function apiFetch(url, options = {}) {
    const response = await fetch(url, {
      ...options,
      headers: {
        Accept: "application/json",
        ...(options.headers || {})
      }
    });

    return safeJson(response, url);
  }

  async function apiPost(url, payload = {}) {
    return apiFetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
  }

  async function firstGet(urls) {
    let lastError;
    for (const url of urls) {
      try {
        return await apiFetch(url);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  function activateTab(tab) {
    if (!tab) return;

    const allowedTabs = ROLE_TABS[window._userRole] || ROLE_TABS.player;
    if (!allowedTabs.includes(tab)) {
      return activateTab('home');
    }

    document.body.dataset.currentTab = tab;

    document.querySelectorAll('.tab-link').forEach((button) => {
      button.classList.toggle("active", button.dataset.tab === tab);
    });

    $$(".tab-panel").forEach((panel) => {
      panel.classList.toggle("active", panel.id === `tab-${tab}`);
    });

    const panel = $(`#tab-${tab}`);
    if (panel) document.title = `RubyMC Launcher — ${panel.dataset.panelTitle || tab}`;

    if (tab === "server") {
      setTimeout(refreshServerLiveStatus, 120);
      setTimeout(loadVersions, 160);
    }
    if (tab === "versions") setTimeout(loadVersions, 100);
    if (tab === "vip") setTimeout(loadVipData, 100);
    if (tab === "db") setTimeout(loadDbPanel, 100);
    if (tab === "settings") setTimeout(loadAccounts, 200);
    if (tab === "modpacks") setTimeout(() => updateModpacks(false), 100);
  }

  function actionPayload(action) {
    return {
      action,
      profile: $("#profile-select")?.value || "vanilla",
      modpack_name: $("#modpack-name")?.value || "",
      server_address: $("#server-address")?.value || "",
      server_version_id: $("#server-version-select")?.value || "",
      server_loader: $("#server-version-select")?.selectedOptions?.[0]?.dataset?.loader || "",
      settings: {
        version: $("#home-version-select")?.value || $("#settings-version")?.value || "",
        ram: $("#settings-ram")?.value || "",
        username: $("#settings-username")?.value || "",
        account: window._activeAccount || ""
      }
    };
  }

  async function backendAction(action) {
    let lastError;
    const aliases = ACTION_ALIASES[action] || [action];

    for (const alias of aliases) {
      try {
        return await apiPost("/api/action", actionPayload(alias));
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError;
  }

  window.handleDiscordServerJoin = async function() {
    try {
      const res = await backendAction('discord_invite');
      const url = (res && res.url) || 'https://discord.gg/MnrSXTF4qx';
      window.open(url, '_blank');
    } catch (e) {
      log('ERROR', 'Falha ao obter link do Discord: ' + e.message);
    }
  };

  async function runAction(action) {
    if (!action || busy) return;

    busy = true;
    log("ACTION", `Executando: ${action}`);

    try {
      if (action === "import_modpack") {
        await importModpack();
      } else if (action === "update_modpacks") {
        await updateModpacks();
      } else if (action === "clear_display") {
        clearDisplay();
        try {
          applyResult(await backendAction(action), action);
        } catch (_) {}
      } else if (action === "play_online") {
        if (!window._activeAccount) {
          log("ERROR", "Nenhuma conta Microsoft selecionada. Adicione uma nas Configurações.");
        } else {
          applyResult(await backendAction("play"), action);
        }
      } else if (action === "play_offline") {
        const savedAccount = window._activeAccount;
        window._activeAccount = "";
        try {
          applyResult(await backendAction("play"), action);
        } finally {
          window._activeAccount = savedAccount;
        }
      } else {
        applyResult(await backendAction(action), action);
      }
    } catch (error) {
      log("ERROR", `${action}: ${error.message}`);
    } finally {
      busy = false;
    }
  }

  function clearDisplay() {
    const display = $("#display-log");
    if (display) {
      display.textContent = `[${time()}] SYSTEM  Display limpo. Aguardando novos eventos...`;
    }
    activateTab("display");
  }

  function updateDisplay(content) {
    const display = $("#display-log");
    if (!display) return;

    display.textContent = Array.isArray(content) ? content.join("\n") : String(content ?? "");
    display.scrollTop = display.scrollHeight;
  }

  function applyResult(result, action = "ação") {
    if (!result) {
      log("OK", `${action} concluído.`);
      return;
    }

    if (typeof result === "string") {
      log("OK", result);
      return;
    }

    if (result.message) log(result.ok === false ? "ERROR" : "OK", result.message);

    if (Array.isArray(result.logs)) {
      result.logs.forEach((item) => {
        if (typeof item === "string") log("LOG", item);
        else log(item.type || "LOG", item.message || JSON.stringify(item));
      });
    }

    if (result.display) updateDisplay(result.display);
    if (result.status) applyStatus(result.status);
    else applyStatus(result);
    if (result.modpacks) renderModpacks(result.modpacks);
    if (result.discord) applyStatus({ discord: result.discord });

    if (action === "test_server" && result.ok !== undefined) {
      setText("server-test-state", result.ok ? "Online" : "Offline");
      setText("server-test-detail", result.message || "");
    }
  }

  function applyStatus(status = {}) {
    const serverObj = (status.server && typeof status.server === "object") ? status.server : {};

    const serverLabelRaw =
        status.server_status ||
        status.server_state ||
        status.process_status ||
        serverObj.status ||
        serverObj.address ||
        status.server ||
        "";

    const serverLabel = (serverLabelRaw && typeof serverLabelRaw === "object")
        ? (serverLabelRaw.status || serverLabelRaw.address || "Configurado")
        : serverLabelRaw;

    const serverAddressRaw =
        status.server_address ||
        status.community_server ||
        status.address ||
        serverObj.address ||
        "";

    const serverAddress = (serverAddressRaw && typeof serverAddressRaw === "object")
        ? (serverAddressRaw.address || "")
        : serverAddressRaw;

    setText("minecraft-version", status.minecraft_version || status.default_version || status.version);
    setText("active-profile", status.active_profile || status.profile);
    setText("server-state", serverLabel || "--");
    setText("server-players", status.server_players || status.players);
    setText("launcher-state", status.launcher_status || status.status);
    setText("launcher-version", status.launcher_version || status.version);
    populateServerSelect(serverObj.servers, serverAddress);

    if (status.modpacks_count !== undefined) setText("home-modpacks-count", status.modpacks_count);

    if (status.versions && status.versions.active) {
      const active = status.versions.active;
      setText("minecraft-version", active.id);
      setText("active-profile", active.label || active.loader || "Vanilla");

      const profileSelect = $("#profile-select");
      if (profileSelect) {
        populateProfileSelect(profileSelect);
      }

      // Merge server versions (status.versions.installed) and client versions (status.versions.client_installed)
      const serverVersions = status.versions.installed || [];
      const clientVersions = status.versions.client_installed || [];
      const seen = new Set();
      const allVersions = [];
      serverVersions.forEach(v => { seen.add(v.id); allVersions.push(v); });
      clientVersions.forEach(v => { if (!seen.has(v.id)) { seen.add(v.id); allVersions.push(v); } });

      const homeVersion = $("#home-version-select");
      if (homeVersion) {
        populateHomeVersionSelect(homeVersion, allVersions, active.id);
      }

      const settingsVersion = $("#settings-version");
      if (settingsVersion) {
        const current = settingsVersion.value;
        settingsVersion.innerHTML = allVersions
            .map((v) => `<option value="${esc(v.id)}">${esc(v.id)} (${esc(v.loader_label || v.loader || "vanilla")})</option>`)
            .join("") || '<option value="">Nenhuma versão instalada</option>';

        if ([...settingsVersion.options].some((option) => option.value === current)) {
          settingsVersion.value = current;
        } else if (active.id && [...settingsVersion.options].some((option) => option.value === active.id)) {
          settingsVersion.value = active.id;
        }
      }
    }

    if (status.server_test) {
      setText("server-test-state", status.server_test.ok ? "Online" : "Offline");
      setText("server-test-detail", status.server_test.message || "");
    }

    const discord = status.discord || {};
    if (Object.keys(discord).length) {
      setText("home-discord-members", discord.members_count);
      setText("discord-bot-state", discord.bot_enabled === true || discord.bot === true || discord.status === "ativo" || discord.bot_state === "ativo" ? "Ativo" : (discord.bot_state || "Inativo"));
      setText("logs-channel-state", discord.logs_channel || discord.logs_channel_id ? "configurado" : "pendente");
      setText("discord-config-state", discord.configured === false ? "pendente" : "configurado");
    }
  }

  function populateProfileSelect(select) {
    if (!select) return;

    const current = select.value;
    let html = '<option value="vanilla">Vanilla / sem modpack</option>';
    html += select._modpackOptions || "";
    select.innerHTML = html;
    if ([...select.options].some((option) => option.value === current)) select.value = current;
  }

  function populateHomeVersionSelect(select, versions, activeVersion) {
    if (!select) return;
    const current = select.value;
    let html = '<option value="">Selecione uma versão</option>';
    if (Array.isArray(versions) && versions.length) {
      versions.forEach((v) => {
        const label = v.loader_label || v.loader || "vanilla";
        const selected = v.id === activeVersion ? ' selected' : '';
        html += `<option value="${esc(v.id)}"${selected}>${esc(v.id)} (${esc(label)})</option>`;
      });
    }
    select.innerHTML = html;
    if (current && [...select.options].some((o) => o.value === current)) select.value = current;
  }

  function populateServerSelect(servers, activeAddress) {
    const select = $("#server-address");
    if (!select) return;

    if (Array.isArray(servers) && servers.length) {
      const current = select.value;
      let html = '<option value="">Selecione um servidor...</option>';
      servers.forEach((s) => {
        const selected = s.address === activeAddress ? ' selected' : '';
        html += `<option value="${esc(s.address)}"${selected}>${esc(s.name)}</option>`;
      });
      select.innerHTML = html;
      if (current && [...select.options].some((o) => o.value === current)) select.value = current;
    }
  }

  async function loadServerList() {
    try {
      const data = await apiGet("/api/servers");
      if (data.ok && Array.isArray(data.servers)) {
        const select = $("#server-address");
        if (select && !select.options.length) {
          populateServerSelect(data.servers, data.servers[0]?.address || "");
        }
      }
    } catch (_) {}
  }

  async function renderServerGrid() {
    const grid = $("#server-grid");
    if (!grid) return;

    try {
      const [statusData, verData] = await Promise.all([
        apiGet("/api/servers/status"),
        apiGet("/api/user/version-status")
      ]);
      if (!statusData.ok || !Array.isArray(statusData.servers)) {
        grid.innerHTML = '<div class="server-grid-placeholder">Erro ao carregar status</div>';
        return;
      }

      const installed = (verData.ok && Array.isArray(verData.installed)) ? verData.installed : [];

      grid.innerHTML = statusData.servers.map((s) => {
        const running = s.running;
        const dotClass = running ? 'online' : 'offline';
        const statusText = running ? 'Online' : 'Offline';
        const btn = running
          ? `<button class="server-card-btn stop" data-sid="${esc(s.key)}">Parar</button>`
          : `<button class="server-card-btn start" data-sid="${esc(s.key)}">Iniciar</button>`;
        const badgeClass = s.type === 'bedrock' ? 'bedrock' : 'java';
        const badgeLabel = s.type === 'bedrock' ? 'Bedrock' : 'Java';
        const isBedrock = s.type === 'bedrock';

        const serverLoader = s.loader || 'vanilla';
        const matchingInstalled = installed.filter(v => v.loader === serverLoader);
        const versionOptions = matchingInstalled.map(v =>
          `<option value="${esc(v.id)}">${esc(v.id)}</option>`
        ).join("");

        const versionRow = isBedrock ? '' : `
          <div class="server-card-version-row">
            <select class="server-card-version-select" data-sid="${esc(s.key)}">
              ${versionOptions || `<option value="" disabled>---</option>`}
            </select>
            <button class="server-card-version-btn" data-sid="${esc(s.key)}" ${versionOptions ? '' : 'disabled'}>OK</button>
          </div>`;
        return `<div class="server-card" data-sid="${esc(s.key)}" data-address="${esc(s.address)}">
          <div class="server-card-header">
            <span class="server-card-name">${esc(s.name)}</span>
            <span class="server-card-badge ${badgeClass}">${badgeLabel}</span>
          </div>
          <div class="server-card-desc">${esc(s.address)}</div>
          ${versionRow}
          <div class="server-card-footer">
            <div class="server-card-status">
              <span class="server-card-dot ${dotClass}"></span>
              ${statusText}
            </div>
            <div class="server-card-actions">${btn}</div>
          </div>
        </div>`;
      }).join("");

      const onlineCount = statusData.servers.filter(s => s.running).length;
      setText("server-count", `${onlineCount} de ${statusData.servers.length} ativos`);

      statusData.servers.forEach((s) => {
        const select = grid.querySelector(`.server-card-version-select[data-sid="${s.key}"]`);
        if (select && s.version) {
          select.value = s.version;
        }
      });

      grid.querySelectorAll(".server-card-btn").forEach((btn) => {
        btn.addEventListener("click", async (e) => {
          e.stopPropagation();
          const sid = btn.dataset.sid;
          const action = btn.classList.contains("start") ? "start" : "stop";
          btn.disabled = true;

          if (action === "start") {
            const addr = btn.closest(".server-card")?.dataset?.address;
            if (addr) {
              const select = $("#server-address");
              if (select) select.value = addr;
            }
          }

          try {
            const ep = action === "start" ? "/api/servers/start" : "/api/servers/stop";
            await apiPost(ep, { server_id: sid });
          } catch (_) {}

          setTimeout(renderServerGrid, 1000);

          if (action === "start") {
            refreshServerLiveStatus();
            let attempts = 0;
            const poll = () => {
              attempts += 1;
              refreshServerLiveStatus();
              if (attempts < 15) setTimeout(poll, 3000);
            };
            setTimeout(poll, 2000);
          }
        });
      });

      grid.querySelectorAll(".server-card-version-btn").forEach((btn) => {
        btn.addEventListener("click", async (e) => {
          e.stopPropagation();
          const sid = btn.dataset.sid;
          const select = grid.querySelector(`.server-card-version-select[data-sid="${sid}"]`);
          if (!select) return;
          const version = select.value;
          btn.disabled = true;
          btn.textContent = "...";
          try {
            const result = await apiPost("/api/servers/version", { server_id: sid, version });
            if (result.ok) {
              btn.textContent = "✓";
            } else {
              btn.textContent = "✗";
            }
          } catch (_) {
            btn.textContent = "✗";
          }
          setTimeout(() => { btn.disabled = false; btn.textContent = "OK"; }, 1500);
          setTimeout(renderServerGrid, 1200);
        });
      });
    } catch (_) {
      grid.innerHTML = '<div class="server-grid-placeholder">Erro ao carregar servidores</div>';
    }
  }

  async function refreshStatus() {
    try {
      const data = await firstGet(ROUTES.status);
      applyStatus(data.status || data);
    } catch (_) {
      try {
        applyResult(await backendAction("refresh_status"), "refresh_status");
      } catch (_) {
        log("WARN", "Status será atualizado quando o backend responder.");
      }
    }
  }

  async function pollLogs() {
    try {
      const data = await firstGet(ROUTES.logs);
      if (data.display) updateDisplay(data.display);
      else if (data.logs) updateDisplay(data.logs);
    } catch (_) {}
  }

  async function importModpack() {
    const input = $("#modpack-file");
    const nameInput = $("#modpack-name");

    if (!input?.files?.length) {
      log("WARN", "Selecione um arquivo .mrpack ou .zip.");
      activateTab("modpacks");
      return;
    }

    const file = input.files[0];
    const profileName = nameInput?.value?.trim() || file.name.replace(/\.(mrpack|zip)$/i, "");
    const form = new FormData();
    form.append("file", file);
    form.append("modpack", file);
    form.append("profile_name", profileName);
    form.append("name", profileName);

    let lastError;
    for (const url of ROUTES.modpackImport) {
      try {
        applyResult(await apiFetch(url, { method: "POST", body: form }), "import_modpack");
        await updateModpacks(false);
        return;
      } catch (error) {
        lastError = error;
      }
    }

    try {
      applyResult(await backendAction("import_modpack"), "import_modpack");
      await updateModpacks(false);
    } catch (_) {
      throw lastError;
    }
  }

  async function updateModpacks(showMessage = true) {
    if (showMessage) log("ACTION", "Atualizando lista de modpacks...");

    for (const url of ROUTES.modpacks) {
      try {
        const data = await apiFetch(url);
        const modpacks = data.modpacks || data.data || data;
        renderModpacks(Array.isArray(modpacks) ? modpacks : []);
        if (showMessage) log("OK", "Lista de modpacks atualizada.");
        return;
      } catch (_) {}
    }

    applyResult(await backendAction("update_modpacks"), "update_modpacks");
  }

  function renderModpacks(modpacks) {
    const list = $("#modpack-list");
    const select = $("#profile-select");

    if (!list) return;

    if (!Array.isArray(modpacks) || !modpacks.length) {
      list.textContent = "Nenhum modpack importado ainda.";
      if (select) {
        select._modpackOptions = "";
        populateProfileSelect(select);
      }
      return;
    }

    list.innerHTML = modpacks.map((item) => {
      const name = typeof item === "string" ? item : (item.name || item.profile || item.title || "Modpack");
      const version = typeof item === "object" && item.version ? item.version : "";
      const id = typeof item === "object" ? (item.id || item.profile_id || name) : name;

      return `
        <div class="modpack-row">
          <strong>${esc(name)}</strong>
          <span>${esc(version)}</span>
          <button class="modpack-remove-btn" data-modpack-id="${esc(id)}" data-action="remove_modpack" title="Remover">✕</button>
        </div>
      `;
    }).join("");

    if (select) {
      select._modpackOptions = modpacks.map((item) => {
        const name = typeof item === "string" ? item : (item.name || item.profile || item.title || "Modpack");
        const id = typeof item === "object" ? (item.id || item.profile_id || name) : name;
        return `<option value="${esc(id)}">${esc(name)}</option>`;
      }).join("");
      populateProfileSelect(select);
    }
  }

  async function removeModpack(id) {
    if (!id) return;
    if (!confirm("Remover este modpack?")) return;

    try {
      const data = await apiPost("/api/modpacks/remove", { profile_id: id });
      if (data.ok) await updateModpacks(false);
      else alert("Erro ao remover: " + (data.message || data.error || "desconhecido"));
    } catch (error) {
      alert("Erro ao remover: " + error.message);
    }
  }

  async function handleProfileChange(value) {
    if (!value) return;

    if (value === "vanilla") {
      log("ACTION", "Perfil alterado para vanilla");
      return;
    }

    busy = true;
    try {
      const data = await apiPost("/api/action", { action: "profile_select", version_id: value });
      if (data.ok) {
        log("OK", "Modpack ativado: " + value);
        if (data.active && data.active.id) {
          const homeVer = $("#home-version-select");
          if (homeVer && [...homeVer.options].some((o) => o.value === data.active.id)) {
            homeVer.value = data.active.id;
          }
          const settingsVer = $("#settings-version");
          if (settingsVer && [...settingsVer.options].some((o) => o.value === data.active.id)) {
            settingsVer.value = data.active.id;
          }
        }
        refreshStatus();
      } else {
        log("WARN", "Modpack não encontrado: " + (data.error || value));
      }
    } catch (error) {
      log("WARN", "Falha ao ativar modpack: " + error.message);
    } finally {
      busy = false;
    }
  }

  function normalizeServerStatus(payload) {
    const live = payload.server_live || payload.live || payload.status || payload;
    const players = live.players || {};

    return {
      ok: live.ok === true || live.online === true,
      online: live.online === true || live.ok === true,
      address: live.address || payload.server?.address || "",
      latency: live.latency_ms || live.latency,
      version: live.version?.name || live.version_name || live.version || "",
      description: live.description || live.motd || "",
      checkedAt: live.checked_at || payload.time || time(),
      error: live.error || payload.error || "",
      playersOnline: Number(players.online || live.players_online || live.online_players || 0),
      playersMax: Number(players.max || live.players_max || live.max_players || 0),
      sample: Array.isArray(players.sample) ? players.sample : [],
      process_running: payload.process_running === true || live.process_running === true
    };
  }

  function playerRatio(status) {
    if (!status.playersMax) return `${status.playersOnline || 0} jogadores`;
    return `${status.playersOnline}/${status.playersMax} jogadores`;
  }

  function renderPlayers(names) {
    const target = $("#server-player-tags");
    if (!target) return;

    if (!names || !names.length) {
      target.innerHTML = '<span class="server-player-tag">Nenhum nome público retornado</span>';
      return;
    }

    target.innerHTML = names
        .slice(0, 12)
        .map((name) => `<span class="server-player-tag">${esc(name.name || name)}</span>`)
        .join("");
  }

  function updateServerUi(status) {
    const online = status.online;

    setText("server-test-state", online ? "Online" : "Offline");
    setText(
        "server-test-detail",
        online
            ? `Servidor respondeu em ${status.latency ?? "--"} ms. ${playerRatio(status)}.`
            : (status.error || "Servidor não respondeu ou não está configurado.")
    );

    setText("server-live-online", online ? status.playersOnline : "0");
    setText("server-live-max", status.playersMax || "--");
    setText("server-live-latency", status.latency ? `${status.latency} ms` : "--");
    setText("server-live-version", status.version || "--");
    setText("server-live-checked", status.checkedAt || "--");
    setText("server-state", online ? "Online" : "Offline");
    setText("server-players", playerRatio(status));
    setClass("server-test-state", "server-live-error", !online);

    const motd = $("#server-motd");
    if (motd) motd.textContent = status.description || (online ? "Servidor online." : "Sem descrição disponível.");

    renderPlayers(status.sample);

    const running = status.process_running === true;
    const startBtn = document.getElementById("server-start-btn");
    const stopBtn = document.getElementById("server-stop-btn");
    const restartBtn = document.getElementById("server-restart-btn");

    if (startBtn) startBtn.style.display = running ? "none" : "";
    if (stopBtn) stopBtn.style.display = running ? "" : "none";
    if (restartBtn) restartBtn.style.display = running ? "" : "none";
  }

  async function refreshServerLiveStatus() {
    setText("server-test-state", "Consultando...");
    setText("server-test-detail", "Buscando status, versão, ping e jogadores online.");

    try {
      const data = await firstGet(ROUTES.serverStatus.map((route) => `${route}?t=${Date.now()}`));
      updateServerUi(normalizeServerStatus(data));
    } catch (error) {
      updateServerUi({
        online: false,
        playersOnline: 0,
        playersMax: 0,
        sample: [],
        error: `API de status indisponível: ${error.message}`,
        checkedAt: time()
      });
    }
  }

  async function serverAction(action) {
    if (!SERVER_CONTROL_ACTIONS.has(action)) return;

    const selectedVersion = selectedServerVersionId();

    try {
      if ((action === "start_server" || action === "restart_server") && selectedVersion) {
        await ensureSelectedServerVersion();
      }

      const payload = {
        action,
        server_version_id: selectedServerVersionId(),
        version_id: selectedServerVersionId(),
        server_loader: document.getElementById("server-version-select")?.selectedOptions?.[0]?.dataset?.loader || "",
        start_only_server: true
      };

      const data = await apiPost("/api/action", payload);
      log(data.ok === false ? "ERROR" : "ACTION", `${action}: ${data.message || data.error || "ok"}`);

      let attempts = 0;
      const poll = () => {
        attempts += 1;
        refreshServerLiveStatus();
        if (attempts < 6) setTimeout(poll, 3000);
      };
      setTimeout(poll, 1500);
    } catch (error) {
      log("ERROR", `${action}: ${error.message}`);
    }
  }

  function isServerTabActive() {
    const activeButton = document.querySelector('.tab-link.active');
    return activeButton?.dataset?.tab === "server" || $("#tab-server")?.classList.contains("active");
  }

  function startServerPolling() {
    if (serverPollTimer) clearInterval(serverPollTimer);
    serverPollTimer = setInterval(() => {
      if (isServerTabActive()) refreshServerLiveStatus();
    }, 15000);
  }

  async function loadVersions() {
    try {
      const data = await apiFetch("/api/user/version-status");
      if (!data.ok) throw new Error(data.error || "Falha ao carregar versões");

      activeVersion = data.active || null;
      installedVersions = data.installed || [];

      renderActiveVersion();
      renderInstalledVersions();
      renderServerVersionSelect();

      const isAdmin = window._userRole === 'admin';
      document.querySelectorAll('#version-server-panel .version-section').forEach(el => {
        el.style.display = isAdmin ? '' : 'none';
      });
      const serverPanel = document.getElementById('version-server-panel');
      const serverNavBtn = document.querySelector('.version-subnav-link[data-panel="server"]');
      if (serverPanel) serverPanel.style.display = isAdmin ? '' : 'none';
      if (serverNavBtn) serverNavBtn.style.display = isAdmin ? '' : 'none';
      if (!isAdmin) {
        const clientBtn = document.querySelector('.version-subnav-link[data-panel="client"]');
        if (clientBtn) clientBtn.classList.add('active');
        const clientPanel = document.getElementById('version-client-panel');
        if (clientPanel) clientPanel.style.display = '';
      }
      initVersionSubnav();
      loadClientVersions();
    } catch (error) {
      log("ERROR", "Versões: " + error.message);
    }
  }

  let clientInstalledVersions = [];
  let clientVersionType = 'release';

  function initVersionSubnav() {
    const subnavBtns = document.querySelectorAll('.version-subnav-link');
    subnavBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        subnavBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const panel = btn.dataset.panel;
        document.getElementById('version-server-panel').style.display = panel === 'server' ? '' : 'none';
        document.getElementById('version-client-panel').style.display = panel === 'client' ? '' : 'none';
        if (panel === 'client') loadClientVersions();
      });
    });
  }

  async function loadClientVersions() {
    const loader = document.getElementById('client-loader')?.value || 'vanilla';
    try {
      const [listRes, availRes] = await Promise.all([
        apiFetch('/api/client/versions'),
        apiFetch('/api/client/versions/available?type=' + clientVersionType + '&limit=30&loader=' + loader)
      ]);
      if (listRes.ok) clientInstalledVersions = listRes.installed || [];
      const available = availRes.ok ? (availRes.versions || []) : [];
      renderClientAvailable(available);
      renderClientInstalled();
    } catch (e) {
      log('ERROR', 'Cliente: ' + e.message);
    }
  }

  function renderClientAvailable(available) {
    const grid = document.getElementById('client-versions-grid');
    if (!grid) return;
    const installedSet = new Set(clientInstalledVersions.map(v => typeof v === 'string' ? v : v.id));
    if (!available.length) {
      grid.innerHTML = '<span class="empty-state">Nenhuma versão encontrada.</span>';
      return;
    }
    const cardsHtml = available.map(v => {
      const isInstalled = installedSet.has(v.id);
      return `
        <div class="client-version-card ${isInstalled ? 'installed' : ''}">
          <div class="client-version-info">
            <strong>${esc(v.id)}</strong>
            <span class="client-version-type">${esc(v.type)}</span>
          </div>
          ${isInstalled
            ? '<span class="client-version-badge">✔ Instalado</span>'
            : `<button class="btn btn-red btn-sm" data-client-install="${esc(v.id)}">Instalar</button>`
          }
        </div>
      `;
    }).join('');
    grid.innerHTML = cardsHtml;
    grid.querySelectorAll('[data-client-install]').forEach(btn => {
      btn.addEventListener('click', () => installClientVersion(btn.dataset.clientInstall));
    });
  }

  function renderClientInstalled() {
    const list = document.getElementById('client-installed-list');
    if (!list) return;
    if (!clientInstalledVersions.length) {
      list.innerHTML = '<span class="empty-state">Nenhuma versão instalada.</span>';
      return;
    }
    const itemsHtml = clientInstalledVersions.map(v => {
      const id = typeof v === 'string' ? v : v.id;
      const loader = typeof v === 'string' ? '' : (v.loader || '');
      const inherits = typeof v === 'string' ? '' : (v.inheritsFrom || '');
      const type = typeof v === 'string' ? '' : (v.type || '');
      const size = typeof v === 'string' ? '' : v.size_kb;
      const loaderBadge = loader ? `<span class="version-item-loader">${esc(loader)}</span>` : '';
      const inheritsHint = inherits ? `<small>→ ${esc(inherits)}</small>` : '';
      const sizeHint = size ? `<small>${size} KB</small>` : '';
      return `
        <div class="version-item">
          <div class="version-item-info">
            <strong>${esc(id)}</strong>
            ${loaderBadge}
            ${inheritsHint}
            ${sizeHint}
          </div>
        </div>
      `;
    }).join('');
    list.innerHTML = `<div class="version-scroll-list">${itemsHtml}</div>`;
  }

  async function installClientVersion(versionId) {
    const loader = document.getElementById('client-loader')?.value || 'vanilla';
    const btn = document.querySelector(`[data-client-install="${versionId}"]`);
    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Instalando...';
    }
    try {
      const res = await apiPost('/api/client/versions/install', { version_id: versionId, loader: loader });
      if (!res.ok) {
        alert(res.error || 'Falha ao iniciar instalação.');
        if (btn) { btn.disabled = false; btn.textContent = 'Instalar'; }
        return;
      }
      log('OK', `Instalação de ${versionId} (${loader}) iniciada.`);

      // Poll until the version appears in the installed list
      const pollInterval = setInterval(async () => {
        try {
          const listRes = await apiFetch('/api/client/versions');
          if (!listRes.ok) return;
          const installed = (listRes.installed || []).map(v => typeof v === 'string' ? v : v.id);
          if (installed.includes(versionId)) {
            clearInterval(pollInterval);
            clearTimeout(pollTimeout);
            log('OK', `${versionId} (${loader}) instalado com sucesso.`);
            loadClientVersions();
          }
        } catch (_) {}
      }, 2000);

      const pollTimeout = setTimeout(() => {
        clearInterval(pollInterval);
        log('WARN', `Instalação de ${versionId} excedeu o tempo limite.`);
        loadClientVersions();
      }, 300000);
    } catch (e) {
      alert('Erro de rede: ' + e.message);
    }
  }

  function renderActiveVersion() {
    const element = document.getElementById("version-active-detail");
    if (!element) return;

    if (!activeVersion) {
      element.innerHTML = '<div class="version-active-none">Nenhuma versão ativa. Instale e ative uma versão.</div>';
      return;
    }

    element.innerHTML = `
      <div class="version-active-card">
        <span class="version-active-loader">${esc(activeVersion.label || activeVersion.loader)}</span>
        <strong class="version-active-id">${esc(activeVersion.id)}</strong>
        <span class="version-active-java">${esc(activeVersion.java || "Java padrão")}</span>
      </div>
    `;
  }

  function renderInstalledVersions() {
    const element = document.getElementById("version-installed-list");
    if (!element) return;

    if (!installedVersions.length) {
      element.innerHTML = '<span class="empty-state">Nenhuma versão instalada.</span>';
      return;
    }

    const isAdmin = window._userRole === 'admin';
    const loaderLabels = { vanilla: "Vanilla", paper: "Paper", fabric: "Fabric", forge: "Forge", neoforge: "NeoForge", quilt: "Quilt" };
    const loaders = ["all", ...new Set(installedVersions.map(v => (v.loader || "vanilla").toLowerCase()))];

    const filterBar = `
      <div class="version-filter-bar">
        ${loaders.map(l => `<button class="btn btn-sm btn-filter ${l === "all" ? "active" : ""}" data-filter="${esc(l)}">${l === "all" ? "Todas" : (loaderLabels[l] || l.charAt(0).toUpperCase() + l.slice(1))}</button>`).join("")}
      </div>`;

    const itemsHtml = installedVersions.map((version) => {
      const isActive = activeVersion && activeVersion.id === version.id;
      const loader = (version.loader || "vanilla").toLowerCase();
      return `
        <div class="version-item ${isActive ? "version-active" : ""}" data-loader="${esc(loader)}">
          <div class="version-item-info">
            <strong>${esc(version.id)}</strong>
            <span class="version-item-loader">${esc(version.loader_label || version.loader || "vanilla")}</span>
            <small>${esc(version.size_kb || "")} KB</small>
          </div>
          ${isAdmin
            ? `<div class="version-item-actions">
                ${isActive
                  ? '<span class="version-active-badge">Ativa</span>'
                  : `<button class="btn btn-red btn-sm" data-version-activate="${esc(version.id)}">Ativar</button>`
                }
                <button class="btn btn-dark btn-sm" data-version-remove="${esc(version.id)}" ${isActive ? 'disabled title="Desative primeiro"' : ""}>Remover</button>
              </div>`
            : ''
          }
        </div>
      `;
    }).join("");

    element.innerHTML = filterBar + `<div class="version-scroll-list">${itemsHtml}</div>`;

    element.querySelectorAll(".version-filter-bar .btn-filter").forEach(btn => {
      btn.addEventListener("click", () => {
        element.querySelectorAll(".version-filter-bar .btn-filter").forEach(b => b.classList.remove("active"));
        btn.classList.add("active");
        const filter = btn.dataset.filter;
        element.querySelectorAll(".version-scroll-list .version-item").forEach(item => {
          item.style.display = filter === "all" || item.dataset.loader === filter ? "" : "none";
        });
      });
    });
  }

  function renderServerVersionSelect() {
    const select = document.getElementById("server-version-select");
    const hint = document.getElementById("server-version-hint");
    if (!select) return;

    const previous = select.value;
    const activeId = activeVersion?.id || "";
    const versions = Array.isArray(installedVersions) ? installedVersions : [];

    if (!versions.length) {
      select.innerHTML = '<option value="">Nenhuma versão instalada</option>';
      select.disabled = true;
      if (hint) hint.textContent = "Instale uma versão na aba Versões antes de iniciar o servidor.";
      return;
    }

    select.disabled = false;
    select.innerHTML = versions.map((version) => {
      const id = version.id || "";
      const loader = version.loader || "vanilla";
      const label = version.loader_label || loader;
      const activeLabel = id === activeId ? " — ativa" : "";
      return `<option value="${esc(id)}" data-loader="${esc(loader)}">${esc(id)} (${esc(label)})${activeLabel}</option>`;
    }).join("");

    if (previous && versions.some((version) => version.id === previous)) {
      select.value = previous;
    } else if (activeId && versions.some((version) => version.id === activeId)) {
      select.value = activeId;
    }

    updateServerVersionHint();
  }

  function updateServerVersionHint() {
    const select = document.getElementById("server-version-select");
    const hint = document.getElementById("server-version-hint");
    if (!select || !hint) return;

    const selected = select.value;
    const activeId = activeVersion?.id || "";

    if (!selected) {
      hint.textContent = "Escolha uma versão instalada para iniciar somente aquele servidor.";
      return;
    }

    if (selected === activeId) {
      hint.textContent = `Versão ${selected} já está ativa. O servidor será iniciado diretamente.`;
    } else {
      hint.textContent = `Ao iniciar/reiniciar, a versão ${selected} será ativada antes de subir o servidor.`;
    }
  }

  function selectedServerVersionId() {
    return document.getElementById("server-version-select")?.value || "";
  }

  async function ensureSelectedServerVersion() {
    const versionId = selectedServerVersionId();
    if (!versionId) return null;

    if (activeVersion?.id === versionId) return versionId;

    log("ACTION", `Ativando servidor na versão ${versionId}...`);

    const data = await apiPost("/api/action", {
      action: "version_activate",
      version_id: versionId,
      server_version_id: versionId
    });

    if (!data.ok) {
      throw new Error(data.error || data.message || `Falha ao ativar versão ${versionId}`);
    }

    log("OK", data.message || `Versão ${versionId} ativada para o servidor.`);
    await loadVersions();
    return versionId;
  }

  async function loadAvailableVersions(loader) {
    const select = document.getElementById("version-id");
    const button = document.getElementById("version-install-btn");
    if (!select) return;

    select.innerHTML = "<option>Carregando...</option>";
    if (button) button.disabled = true;

    try {
      const data = await apiPost("/api/versions/available", { loader, limit: 60 });
      if (!data.ok) throw new Error(data.error || "Falha ao listar versões");

      const installedIds = new Set(installedVersions.map((version) => version.id));
      const available = (data.versions || []).filter((version) => !installedIds.has(version.id) && !version.error);

      if (!available.length) {
        select.innerHTML = '<option value="">Todas as versões já estão instaladas</option>';
        return;
      }

      select.innerHTML = available.map((version) => `<option value="${esc(version.id)}">${esc(version.id)}</option>`).join("");
      if (button) button.disabled = false;
    } catch (error) {
      select.innerHTML = `<option value="">Erro ao carregar: ${esc(error.message)}</option>`;
    }
  }

  async function installVersion() {
    const loader = document.getElementById("version-loader")?.value || "vanilla";
    const versionId = document.getElementById("version-id")?.value;
    const button = document.getElementById("version-install-btn");

    if (!versionId) return;

    if (button) {
      button.disabled = true;
      button.textContent = "Instalando...";
    }

    try {
      await apiPost("/api/action", { action: "version_install", version_id: versionId, loader });
      log("OK", `Instalação de ${versionId} (${loader}) iniciada.`);
      setTimeout(async () => {
        await loadVersions();
        refreshStatus();
        await loadAvailableVersions(document.getElementById("version-loader")?.value || "vanilla");
        if (button) {
          button.textContent = "Instalar";
          button.disabled = false;
        }
      }, 2000);
    } catch (error) {
      log("ERROR", `Falha ao instalar ${versionId}: ${error.message}`);
      if (button) {
        button.textContent = "Instalar";
        button.disabled = false;
      }
    }
  }

  async function activateVersion(versionId) {
    try {
      const data = await apiPost("/api/action", { action: "version_activate", version_id: versionId });
      if (data.ok) {
        log("OK", `Versão ${versionId} ativada.`);
        await loadVersions();
        refreshStatus();
        renderServerVersionSelect();
      } else {
        log("ERROR", `Falha ao ativar ${versionId}: ${data.error || "erro desconhecido"}`);
      }
    } catch (error) {
      log("ERROR", `Falha ao ativar ${versionId}: ${error.message}`);
    }
  }

  async function removeVersion(versionId) {
    if (!confirm(`Remover versão ${versionId}?`)) return;

    try {
      const data = await apiPost("/api/action", { action: "version_remove", version_id: versionId });
      if (data.ok) {
        log("OK", `Versão ${versionId} removida.`);
        await loadVersions();
        await loadAvailableVersions(document.getElementById("version-loader")?.value || "vanilla");
      } else {
        log("ERROR", `Falha ao remover ${versionId}: ${data.error || "erro desconhecido"}`);
      }
    } catch (error) {
      log("ERROR", `Falha ao remover ${versionId}: ${error.message}`);
    }
  }

  async function loadAccounts() {
    const element = document.getElementById("accounts-list");
    if (!element) return;

    try {
      const data = await apiFetch("/api/accounts");
      if (!data.ok) throw new Error(data.error || "Falha ao carregar contas");

      const accounts = data.accounts || [];
      if (!accounts.length) {
        element.innerHTML = '<span class="empty-state">Nenhuma conta adicionada.</span>';
        window._activeAccount = "";
        return;
      }

      const activeEmail = window._activeAccount || accounts[0]?.email || "";
      if (!window._activeAccount && activeEmail) window._activeAccount = activeEmail;

      element.innerHTML = accounts.map((account) => {
        const edition = account.edition || "java";
        const editionBadge = edition === "bedrock"
            ? '<span class="edition-badge-edition">Bedrock</span>'
            : '<span class="edition-badge-edition edition-badge-java">Java</span>';

        return `
          <div class="account-row ${activeEmail === account.email ? "account-active" : ""}">
            <div class="account-info">
              <span class="account-name">
                ${activeEmail === account.email ? '<span class="account-active-indicator">▶</span>' : ""}
                ${esc(account.username)}
                ${editionBadge}
              </span>
              <span class="account-email">${esc(account.email)}</span>
            </div>
            <span class="account-badge ${account.is_valid ? "account-badge-online" : "account-badge-offline"}">
              ${account.is_valid ? "Válida" : "Expirada"}
            </span>
            <div class="account-actions">
              <button class="btn btn-red btn-sm" data-account-use="${esc(account.email)}">Usar</button>
              <button class="btn btn-dark btn-sm" data-account-remove="${esc(account.email)}">Remover</button>
            </div>
          </div>
        `;
      }).join("");

      if (activeEmail && !accounts.some((account) => account.email === activeEmail)) {
        window._activeAccount = accounts[0]?.email || "";
      }
    } catch (error) {
      element.innerHTML = `<span class="empty-state">Erro: ${esc(error.message)}</span>`;
    }
  }

  async function startAuth(edition = "java") {
    currentEdition = edition;

    const modal = document.getElementById("auth-modal");
    const codeElement = document.getElementById("auth-code");
    const uriElement = document.getElementById("auth-uri");
    const statusElement = document.getElementById("auth-status");

    if (!modal || !codeElement || !statusElement) return;

    modal.style.display = "flex";
    codeElement.textContent = "---";
    statusElement.textContent = "Iniciando autenticação...";

    try {
      const data = await apiPost("/api/accounts/start-auth", { edition: currentEdition });
      if (!data.ok) throw new Error(data.error || "Falha ao iniciar autenticação");

      codeElement.textContent = data.user_code || "---";

      if (uriElement) {
        const uri = data.verification_uri || "https://www.microsoft.com/link";
        uriElement.textContent = uri;
        uriElement.href = uri;
      }

      const label = currentEdition === "bedrock" ? "Bedrock" : "Microsoft";
      statusElement.textContent = `Aguardando aprovação da conta ${label} no navegador...`;
      startAuthPolling(data.device_code, data.interval || 3);
    } catch (error) {
      statusElement.textContent = "Erro: " + error.message;
    }
  }

  function startAuthPolling(deviceCode, interval) {
    if (authPollTimer) clearInterval(authPollTimer);

    const statusElement = document.getElementById("auth-status");
    const maxAttempts = 120;
    let attempts = 0;

    authPollTimer = setInterval(async () => {
      attempts += 1;

      if (attempts > maxAttempts) {
        clearInterval(authPollTimer);
        authPollTimer = null;
        if (statusElement) statusElement.textContent = "Tempo esgotado. Tente novamente.";
        return;
      }

      try {
        const data = await apiPost("/api/accounts/poll-auth", {
          device_code: deviceCode,
          edition: currentEdition
        });

        if (!data.ok) {
          clearInterval(authPollTimer);
          authPollTimer = null;

          const message = data.error || "Falha na autenticação";
          const restartMessage = data.restart_required
              ? " Gere um novo código de login e tente novamente."
              : "";

          if (statusElement) statusElement.textContent = "Erro: " + message + restartMessage;
          return;
        }

        if (data.complete === true) {
          clearInterval(authPollTimer);
          authPollTimer = null;

          const label = data.edition === "bedrock" ? "Bedrock" : "Microsoft";
          if (statusElement) statusElement.textContent = "✅ Conta " + label + " adicionada: " + data.account.username;

          setTimeout(() => {
            const modal = document.getElementById("auth-modal");
            if (modal) modal.style.display = "none";
            loadAccounts();
          }, 1500);
        } else if (data.complete === false && statusElement) {
          statusElement.textContent = "Aguardando aprovação no navegador... (" + attempts + "s)";
        }
      } catch (error) {
        clearInterval(authPollTimer);
        authPollTimer = null;

        const backendMessage = error?.data?.error || error?.data?.message || error.message;
        const restartMessage = error?.restartRequired || error?.status >= 400
            ? " Gere um novo código de login e tente novamente."
            : "";

        if (statusElement) statusElement.textContent = "Erro: " + backendMessage + restartMessage;
      }
    }, interval * 1000);
  }

  async function removeAccount(email) {
    if (!confirm("Remover conta " + email + "?")) return;

    try {
      const data = await apiPost("/api/accounts/remove", { email });
      if (data.ok) {
        if (window._activeAccount === email) window._activeAccount = "";
        loadAccounts();
      } else {
        alert("Erro: " + (data.error || "Falha ao remover conta"));
      }
    } catch (error) {
      alert("Erro: " + error.message);
    }
  }

  function useAccount(email) {
    window._activeAccount = email;
    loadAccounts();

    const username = document.getElementById("settings-username");
    if (username) username.value = "";
  }

  function bindEvents() {
    document.querySelectorAll('.tab-link').forEach((button) => {
      button.addEventListener("click", () => activateTab(button.dataset.tab));
    });

    $$("[data-action]").forEach((button) => {
      button.addEventListener("click", () => runAction(button.dataset.action));
    });

    $$(".toggle").forEach((toggle) => {
      toggle.addEventListener("click", () => {
        toggle.classList.toggle("active");
        log("ACTION", `Configuração alterada: ${toggle.dataset.toggle}`);
      });
    });

    const modpackFile = document.getElementById("modpack-file");
    const modpackLabel = document.getElementById("modpack-file-label");
    if (modpackFile && modpackLabel) {
      modpackFile.addEventListener("change", () => {
        modpackLabel.textContent = modpackFile.files?.[0]
            ? modpackFile.files[0].name
            : "Clique para escolher ou arraste o arquivo aqui";
      });
    }

    const profileSelect = document.getElementById("profile-select");
    if (profileSelect) profileSelect.addEventListener("change", () => handleProfileChange(profileSelect.value));

    const homeVersion = document.getElementById("home-version-select");
    if (homeVersion) {
      homeVersion.addEventListener("change", () => {
        const settingsVer = document.getElementById("settings-version");
        if (settingsVer && homeVersion.value) {
          if ([...settingsVer.options].some((o) => o.value === homeVersion.value)) {
            settingsVer.value = homeVersion.value;
          }
        }
      });
    }

    const settingsVersion = document.getElementById("settings-version");
    if (settingsVersion) {
      settingsVersion.addEventListener("change", () => {
        const homeVer = document.getElementById("home-version-select");
        if (homeVer && settingsVersion.value && [...homeVer.options].some((o) => o.value === settingsVersion.value)) {
          homeVer.value = settingsVersion.value;
        }
        if (settingsVersion.value) {
          busy = true;
          apiPost("/api/action", { action: "profile_select", version_id: settingsVersion.value }).then(data => {
            if (data.ok) {
              log("OK", "Versão ativada: " + settingsVersion.value);
              refreshStatus();
            } else {
              log("WARN", "Falha ao ativar versão: " + (data.error || settingsVersion.value));
            }
          }).catch(error => {
            log("WARN", "Falha ao ativar versão: " + error.message);
          }).finally(() => { busy = false; });
        }
      });
    }

    const versionLoader = document.getElementById("version-loader");
    if (versionLoader) {
      versionLoader.addEventListener("change", () => {
        if (versionLoader.value) loadAvailableVersions(versionLoader.value);
      });
    }

    const installButton = document.getElementById("version-install-btn");
    if (installButton) {
      installButton.addEventListener("click", (event) => {
        event.preventDefault();
        installVersion();
      });
    }

    const addAccountButton = document.getElementById("add-account-btn");
    if (addAccountButton) addAccountButton.addEventListener("click", () => startAuth("java"));

    const cancelAuthButton = document.getElementById("auth-cancel-btn");
    if (cancelAuthButton) {
      cancelAuthButton.addEventListener("click", () => {
        if (authPollTimer) {
          clearInterval(authPollTimer);
          authPollTimer = null;
        }
        const modal = document.getElementById("auth-modal");
        if (modal) modal.style.display = "none";
      });
    }

    const discordSimulateButton = document.getElementById("discord-simulate-btn");
    if (discordSimulateButton) bindDiscordSimulation(discordSimulateButton);

    const serverVersionSelect = document.getElementById("server-version-select");
    if (serverVersionSelect) {
      serverVersionSelect.addEventListener("change", updateServerVersionHint);
    }

    const serverVersionRefresh = document.getElementById("server-version-refresh");
    if (serverVersionRefresh) {
      serverVersionRefresh.addEventListener("click", async () => {
        serverVersionRefresh.disabled = true;
        serverVersionRefresh.textContent = "Atualizando...";
        try {
          await loadVersions();
          log("OK", "Lista de versões do servidor atualizada.");
        } catch (error) {
          log("ERROR", "Falha ao atualizar versões do servidor: " + error.message);
        } finally {
          serverVersionRefresh.disabled = false;
          serverVersionRefresh.textContent = "Atualizar";
        }
      });
    }

    // Client version filter buttons
    document.querySelectorAll('.btn-filter').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.btn-filter').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        clientVersionType = btn.dataset.type;
        loadClientVersions();
      });
    });

    // Client loader select
    const clientLoader = document.getElementById('client-loader');
    if (clientLoader) {
      clientLoader.addEventListener('change', () => {
        loadClientVersions();
      });
    }

    document.addEventListener("click", handleDelegatedClick, true);
  }

  function handleDelegatedClick(event) {
    const actionButton = event.target.closest("[data-action]");

    if (actionButton) {
      const action = actionButton.dataset.action;

      if (SERVER_CONTROL_ACTIONS.has(action)) {
        event.preventDefault();
        event.stopImmediatePropagation();

        if (runningActions.has(action)) {
          log("WARN", `Ação ${action} já está em execução.`);
          return;
        }

        runningActions.add(action);
        const oldText = actionButton.textContent;
        actionButton.disabled = true;
        actionButton.classList.add("is-loading");
        actionButton.textContent = "Processando...";

        serverAction(action).finally(() => {
          runningActions.delete(action);
          actionButton.disabled = false;
          actionButton.classList.remove("is-loading");
          actionButton.textContent = oldText;
        });

        return;
      }

      if (GUARDED_ACTIONS.has(action)) {
        if (runningActions.has(action)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          log("WARN", `Ação ${action} já está em execução.`);
          return;
        }

        runningActions.add(action);
        const oldText = actionButton.textContent;
        actionButton.disabled = true;
        actionButton.classList.add("is-loading");
        actionButton.textContent = "Processando...";

        setTimeout(() => {
          runningActions.delete(action);
          actionButton.disabled = false;
          actionButton.classList.remove("is-loading");
          actionButton.textContent = oldText;
        }, 8000);
      }

      if (action === "remove_modpack") {
        event.preventDefault();
        event.stopImmediatePropagation();
        removeModpack(actionButton.dataset.modpackId);
      }
    }

    const activateButton = event.target.closest("[data-version-activate]");
    if (activateButton) {
      activateVersion(activateButton.dataset.versionActivate);
      return;
    }

    const removeVersionButton = event.target.closest("[data-version-remove]");
    if (removeVersionButton) {
      removeVersion(removeVersionButton.dataset.versionRemove);
      return;
    }

    const useAccountButton = event.target.closest("[data-account-use]");
    if (useAccountButton) {
      useAccount(useAccountButton.dataset.accountUse);
      return;
    }

    const removeAccountButton = event.target.closest("[data-account-remove]");
    if (removeAccountButton) {
      removeAccount(removeAccountButton.dataset.accountRemove);
      return;
    }

    const doacaoBtn = event.target.closest(".doacao-btn");
    if (doacaoBtn) {
      const card = doacaoBtn.closest(".vip-plan-card");
      const input = card ? card.querySelector(".doacao-input") : null;
      const amount = parseFloat((input ? input.value : "0").replace(",", "."));
      if (isNaN(amount) || amount <= 0) {
        alert("Digite um valor válido para doação.");
        return;
      }
      vipCheckoutVIP("doacao", doacaoBtn, amount);
      return;
    }

    const vipCheckout = event.target.closest("[data-vip-price-id]");
    if (vipCheckout) {
      vipCheckoutVIP(vipCheckout.dataset.vipPriceId, vipCheckout);
      return;
    }
  }

  function bindDiscordSimulation(button) {
    const simClass = "is-simulating";
    const labelOn = "Simular Discord";
    const labelOff = "Parar simulação";

    function resetSimulation() {
      button.classList.remove(simClass);
      button.textContent = labelOn;
    }

    function applySimulation(data) {
      button.classList.add(simClass);
      button.textContent = labelOff;
    }

    document.querySelectorAll('[data-action="validate_discord"]').forEach((validateButton) => {
      validateButton.addEventListener("click", resetSimulation);
    });

    button.addEventListener("click", async (event) => {
      event.stopImmediatePropagation();

      if (button.classList.contains(simClass)) {
        setText("discord-bot-state", "Inativo");
        resetSimulation();
        return;
      }

      try {
        const data = await apiPost("/api/action", { action: "simular_discord" });
        if (data.ok && data.discord) applySimulation(data.discord);
      } catch (_) {}
    });
  }

  /* ── VIP ──────────────────────────────────────────── */
  async function loadVipData() {
    await Promise.allSettled([
      loadVipStatus(),
      loadVipPlans(),
      loadPendingPayments()
    ]);
  }

  async function loadVipStatus() {
    const detail = document.getElementById("vip-status-detail");
    if (!detail) return;

    try {
      const data = await apiFetch("/api/vip/status");
      if (!data.ok) throw new Error(data.error || "Falha");

      if (data.active && data.plan != 'doacao') {
        const badge = data.role_granted
          ? '<span class="vip-role-badge team">Gratuito pela Equipe</span>'
          : '';
        detail.innerHTML = `
          <span class="vip-status-badge active">👑 ${esc(data.plan)}</span>
          <span class="vip-status-plan">${esc(data.plan_label || data.plan)}</span>
          ${badge}
          ${data.expires_at ? `<span class="vip-status-expires">Expira em ${esc(data.expires_at)}</span>` : ""}
        `;
      } else {
        detail.innerHTML = `
          <span class="vip-status-badge none">Nenhum plano ativo</span>
          <span style="color:var(--muted);font-size:13px;">Adquira um plano abaixo para desbloquear benefícios VIP no servidor.</span>
        `;
      }
    } catch (error) {
      detail.innerHTML = `<span style="color:var(--muted);font-style:italic;">Erro ao carregar status: ${esc(error.message)}</span>`;
    }
  }

  async function loadVipPlans() {
    const grid = document.getElementById("vip-plans-grid");
    if (!grid) return;

    try {
      const data = await apiFetch("/api/vip/plans");
      if (!data.ok) throw new Error(data.error || "Falha");

      const plans = data.plans || [];
      if (!plans.length) {
        grid.innerHTML = '<span style="color:var(--muted);font-style:italic;">Nenhum plano disponível no momento.</span>';
        return;
      }

      grid.innerHTML = plans.map((plan) => {
        if (plan.id === 'doacao') {
          return `
        <div class="vip-plan-card${data.staff_discount ? ' staff-discount' : ''}">
          <span class="vip-plan-name">${esc(plan.name)}</span>
          <span class="vip-plan-price">${esc(plan.price)}</span>
          <span class="vip-plan-desc">${esc(plan.description || "")}</span>
          <div class="doacao-row">
            <input type="number" class="doacao-input" min="1" step="0.01" placeholder="Valor (R$)">
            <button class="btn btn-green btn-sm doacao-btn" data-vip-price-id="doacao">Doar</button>
          </div>
        </div>`;
        }
        return `
        <div class="vip-plan-card${data.staff_discount ? ' staff-discount' : ''}">
          ${data.staff_discount ? '<span class="vip-staff-badge">50% OFF Equipe</span>' : ''}
          <span class="vip-plan-name">${esc(plan.name)}</span>
          <span class="vip-plan-price">R$ ${esc(plan.price)} <small>/${esc(plan.period || "mês")}</small></span>
          <span class="vip-plan-desc">${esc(plan.description || "")}</span>
          <button class="btn btn-red btn-sm vip-checkout-btn" data-vip-price-id="${esc(plan.id)}">Assinar</button>
        </div>`;
      }).join("");
    } catch (error) {
      grid.innerHTML = `<span style="color:var(--muted);font-style:italic;">Erro ao carregar planos: ${esc(error.message)}</span>`;
    }
  }

  let currentHistoryFilter = 'all';
  let allPayments = [];

  async function loadVipHistory() {
    const list = document.getElementById("db-payment-history");
    if (!list) return;

    try {
      const data = await apiFetch("/api/vip/history");
      if (!data.ok) throw new Error(data.error || "Falha");

      allPayments = data.payments || [];
      const countEl = document.getElementById("db-count-payments");
      if (countEl) countEl.textContent = `(${allPayments.length})`;
      renderVipHistory();
    } catch (error) {
      list.innerHTML = `<span style="color:var(--muted);font-style:italic;">Erro ao carregar histórico: ${esc(error.message)}</span>`;
    }
  }

  function renderVipHistory() {
    const list = document.getElementById("db-payment-history");
    if (!list) return;

    const filtered = currentHistoryFilter === 'all'
      ? allPayments
      : allPayments.filter(p => p.status === currentHistoryFilter);

    if (!filtered.length) {
      list.innerHTML = '<span style="color:var(--muted);font-style:italic;">Nenhum pagamento encontrado.</span>';
      return;
    }

    list.innerHTML = filtered.map((p) => `
      <div class="db-history-item">
        <span class="db-history-date">${esc(p.date || "")}</span>
        <span class="db-history-plan">${esc(p.plan_label || p.plan || "")}</span>
        <span class="db-history-amount">R$ ${esc(p.amount || "0")}</span>
        <span class="db-history-status ${p.status || "pending"}">${esc(p.status_label || p.status || "")}</span>
      </div>
    `).join("");
  }

  function setupHistoryFilters() {
    document.querySelectorAll(".db-filter-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        document.querySelectorAll(".db-filter-btn").forEach(b => b.classList.remove("active"));
        btn.classList.add("active");
        currentHistoryFilter = btn.dataset.filter;
        renderVipHistory();
      });
    });
  }

  async function loadPendingPayments() {
    const section = document.getElementById("vip-pending-section");
    const list = document.getElementById("vip-pending-list");
    if (!section || !list) return;

    try {
      const data = await apiFetch("/api/vip/pix/status");
      if (!data.ok) return;
      const pending = data.pending || [];
      if (!pending.length) { section.style.display = "none"; return; }
      section.style.display = "";

      list.innerHTML = pending.map((p) => `
        <div class="vip-pending-item" data-payment-id="${esc(p.id)}">
          <div class="pending-header">
            <span class="pending-plan">${esc(p.plan_label || p.plan)}</span>
            <span class="pending-amount">R$ ${esc(p.amount)}</span>
          </div>
          <div class="pending-user">Usuário: ${esc(p.user_id || "?")}</div>
          ${p.ocr_amount ? `<div class="pending-ocr">OCR: R$ ${esc(p.ocr_amount)} — ${esc(p.ocr_sender || "?")}</div>` : ""}
          ${p.receipt ? `<div class="pending-receipt"><a href="/api/vip/pix/receipt/${esc(p.id)}" target="_blank"><img src="/api/vip/pix/receipt/${esc(p.id)}" alt="Comprovante"></a></div>` : '<div class="pending-ocr" style="color:#fbbf24;">⏳ Aguardando upload do comprovante...</div>'}
          ${p.receipt ? `
          <div class="pending-actions">
            <button class="btn-confirm" onclick="confirmPendingPayment('${esc(p.id)}', this)">✅ Confirmar</button>
            <button class="btn-reject" onclick="rejectPendingPayment('${esc(p.id)}', this)">❌ Recusar</button>
          </div>` : ""}
        </div>
      `).join("");
    } catch (_) {
      section.style.display = "none";
    }
  }

  async function confirmPendingPayment(paymentId, btn) {
    btn.disabled = true;
    btn.textContent = "Confirmando...";
    try {
      const data = await apiPost("/api/vip/pix/confirm", { payment_id: paymentId });
      if (!data.ok) { alert(data.error || "Erro ao confirmar"); btn.disabled = false; btn.textContent = "✅ Confirmar"; return; }
      alert(data.message);
      loadPendingPayments();
    } catch (e) {
      alert("Erro: " + e.message);
      btn.disabled = false;
      btn.textContent = "✅ Confirmar";
    }
  }

  async function rejectPendingPayment(paymentId, btn) {
    if (!confirm("Tem certeza que deseja recusar este pagamento?")) return;
    btn.disabled = true;
    btn.textContent = "Recusando...";
    try {
      const data = await apiPost("/api/vip/pix/reject", { payment_id: paymentId });
      if (!data.ok) { alert(data.error || "Erro ao recusar"); btn.disabled = false; btn.textContent = "❌ Recusar"; return; }
      loadPendingPayments();
    } catch (e) {
      alert("Erro: " + e.message);
      btn.disabled = false;
      btn.textContent = "❌ Recusar";
    }
  }

  async function vipCheckoutVIP(priceId, button, amount) {
    const restore = setBusy(button, "Gerando PIX...");
    try {
      const body = { price_id: priceId };
      if (amount) body.amount = amount;
      const data = await apiPost("/api/vip/checkout", body);
      if (data.ok === false) {
        alert(data.error || "Erro ao processar checkout");
        return;
      }
      showPixModal(data);
    } catch (error) {
      alert("Erro de rede: " + error.message);
    } finally {
      restore();
    }
  }

  /* ── Modal PIX ──────────────────────────────────── */
  let pixPollTimer = null;

  function closePixModal() {
    if (pixPollTimer) { clearInterval(pixPollTimer); pixPollTimer = null; }
    const ov = document.getElementById("pix-modal-overlay");
    if (ov) ov.remove();
  }

  function showPixModal(pixData) {
    closePixModal();

    const overlay = document.createElement("div");
    overlay.id = "pix-modal-overlay";
    overlay.className = "pix-modal-overlay";

    overlay.innerHTML = `
      <div class="pix-modal">
        <button class="pix-modal-close" type="button">✕</button>
        <h2 class="pix-modal-title">💎 Pagamento PIX</h2>
        <p class="pix-modal-plan">${esc(pixData.plan)} — <strong>R$ ${esc(pixData.amount)}</strong></p>

        <div class="pix-modal-qr-wrapper">
          <img class="pix-modal-qr" src="data:image/png;base64,${pixData.qr_code_base64}" alt="QR Code PIX">
        </div>

        <div class="pix-modal-code">
          <label>Código PIX (copie e cole no seu banco)</label>
          <div class="pix-code-box">
            <code id="pix-code-text">${esc(pixData.pix_code)}</code>
            <button class="btn btn-sm btn-filter" type="button" id="pix-copy-btn">📋 Copiar</button>
          </div>
        </div>

        <div class="pix-modal-receipt">
          <label class="pix-receipt-label">📎 Comprovante de pagamento</label>
          <div class="pix-receipt-row">
            <input type="file" class="pix-receipt-input" id="receipt-file-input" accept="image/png,image/jpeg,image/gif,image/webp,application/pdf">
            <button class="btn btn-blue btn-sm" type="button" id="receipt-upload-btn">📤 Enviar</button>
          </div>
          <div class="pix-receipt-status" id="receipt-upload-status"></div>
        </div>

        <div class="pix-modal-status" id="pix-status-indicator">
          <span class="pix-status-dot pending"></span>
          Aguardando pagamento...
        </div>

        <div class="pix-modal-actions">
          <button class="btn btn-green" type="button" id="pix-confirm-btn">✅ Já paguei</button>
          <button class="btn btn-red" type="button" id="pix-cancel-btn">Cancelar</button>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);
    overlay.style.display = "flex";

    overlay.querySelector(".pix-modal-close").addEventListener("click", closePixModal);
    overlay.querySelector("#pix-cancel-btn").addEventListener("click", closePixModal);
    overlay.addEventListener("click", (e) => { if (e.target === overlay) closePixModal(); });

    overlay.querySelector("#pix-copy-btn").addEventListener("click", copyPixCode);

    const confirmBtn = overlay.querySelector("#pix-confirm-btn");
    confirmBtn.addEventListener("click", () => checkPixStatus(pixData.payment_id, confirmBtn));

    const uploadBtn = overlay.querySelector("#receipt-upload-btn");
    const fileInput = overlay.querySelector("#receipt-file-input");
    const uploadStatus = overlay.querySelector("#receipt-upload-status");
    uploadBtn.addEventListener("click", () => uploadReceipt(pixData.payment_id, fileInput, uploadStatus));

    startPixPolling(pixData.payment_id);
  }

  function startPixPolling(paymentId) {
    if (pixPollTimer) clearInterval(pixPollTimer);
    pixPollTimer = setInterval(async () => {
      const ov = document.getElementById("pix-modal-overlay");
      if (!ov) { clearInterval(pixPollTimer); pixPollTimer = null; return; }
      try {
        const data = await apiFetch("/api/vip/pix/status?payment_id=" + encodeURIComponent(paymentId));
        if (data.ok && data.status === "completed") {
          clearInterval(pixPollTimer);
          pixPollTimer = null;
          updatePixStatus("completed");
          setTimeout(() => { closePixModal(); loadVipData(); }, 2000);
        }
      } catch (_) {}
    }, 5000);
  }

  async function checkPixStatus(paymentId, button) {
    try {
      const data = await apiFetch("/api/vip/pix/status?payment_id=" + encodeURIComponent(paymentId));
      if (!data.ok) {
        alert(data.error || "Erro ao verificar status");
        return;
      }
      if (data.status === "completed") {
        updatePixStatus("completed");
        if (pixPollTimer) { clearInterval(pixPollTimer); pixPollTimer = null; }
        setTimeout(() => { closePixModal(); loadVipData(); }, 1500);
      } else {
        alert("Pagamento ainda não confirmado. Após o pagamento, um administrador precisa confirmar manualmente.");
      }
    } catch (error) {
      alert("Erro: " + error.message);
    }
  }

  async function uploadReceipt(paymentId, fileInput, statusEl) {
    const file = fileInput.files[0];
    if (!file) {
      statusEl.textContent = "Selecione um arquivo primeiro.";
      statusEl.className = "pix-receipt-status error";
      return;
    }
    if (file.size > 10_485_760) {
      statusEl.textContent = "Arquivo muito grande. Máximo 10MB.";
      statusEl.className = "pix-receipt-status error";
      return;
    }

    statusEl.textContent = "Enviando...";
    statusEl.className = "pix-receipt-status";

    const form = new FormData();
    form.append("payment_id", paymentId);
    form.append("receipt", file);

    try {
      const resp = await fetch("/api/vip/pix/receipt", { method: "POST", body: form });
      const data = await resp.json();
      if (!data.ok) {
        statusEl.textContent = data.error || "Erro ao enviar comprovante.";
        statusEl.className = "pix-receipt-status error";
        return;
      }
      if (data.confirmed) {
        statusEl.textContent = data.message;
        statusEl.className = "pix-receipt-status success";
        updatePixStatus("completed");
        if (pixPollTimer) { clearInterval(pixPollTimer); pixPollTimer = null; }
        setTimeout(() => { closePixModal(); loadVipData(); }, 2000);
      } else {
        const ocrInfo = data.ocr ? ` (detectado: R$ ${data.ocr.amount || "?"} — ${data.ocr.sender || "?"})` : "";
        statusEl.textContent = data.message + ocrInfo;
        statusEl.className = "pix-receipt-status";
      }
    } catch (error) {
      statusEl.textContent = "Erro de rede: " + error.message;
      statusEl.className = "pix-receipt-status error";
    }
  }

  let dbData = { users: [], payments: [], memberships: [] };
  let dbAutoTimer = null;
  let dbPanelSetup = false;

  let dbHistoryFiltersSetup = false;

  async function loadDbPanel() {
    if (!dbPanelSetup) {
      setupDbPanel();
      dbPanelSetup = true;
    }
    const usersEl = document.getElementById("db-users");
    const membershipsEl = document.getElementById("db-memberships");
    if (!usersEl || !membershipsEl) return;

    if (!dbHistoryFiltersSetup) {
      setupHistoryFilters();
      dbHistoryFiltersSetup = true;
    }

    const [usersRes, membershipsRes] = await Promise.allSettled([
      apiFetch("/api/admin/db/users"),
      apiFetch("/api/admin/db/memberships")
    ]);

    if (usersRes.value?.ok) dbData.users = usersRes.value.users || [];
    if (membershipsRes.value?.ok) dbData.memberships = membershipsRes.value.memberships || [];

    renderDbTables();
    loadVipHistory();
  }

  function renderDbTables() {
    renderDbUsers();
    renderDbMemberships();
  }

  function filterDbRows(type) {
    const q = (document.getElementById(`db-search-${type}`)?.value || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    return dbData[type].filter(r => JSON.stringify(Object.values(r)).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").includes(q));
  }

  function statusLabel(s) {
    const m = { completed: "Confirmado", rejected: "Recusado", pending: "Pendente" };
    return m[s] || s;
  }

  function renderDbUsers() {
    const el = document.getElementById("db-users");
    if (!el) return;
    const rows = filterDbRows("users");
    document.getElementById("db-count-users").textContent = `(${rows.length})`;
    if (!rows.length) {
      el.innerHTML = '<span class="db-empty">Nenhum usuário encontrado.</span>';
      return;
    }
    el.innerHTML = `<table class="db-table"><tr><th>Discord ID</th><th>Username</th><th>Role</th><th>Desde</th></tr>${rows.map(u => `<tr><td class="db-cell-id" title="Clique para copiar" onclick="navigator.clipboard.writeText('${esc(u.id)}');this.classList.add('db-copied');setTimeout(()=>this.classList.remove('db-copied'),800)">${esc(u.id)}</td><td>${esc(u.username)}${u.avatar_url ? `<a href="${esc(u.avatar_url)}" target="_blank" class="db-avatar-link" title="Abrir avatar">🖼</a>` : ''}</td><td><span class="db-role-badge role-${esc(u.role)}">${esc(u.role)}</span></td><td class="db-cell-date">${esc((u.created_at || "").slice(0,10))}</td></tr>`).join("")}</table>`;
  }

  function renderDbPayments() {
    const el = document.getElementById("db-payments");
    if (!el) return;
    const rows = filterDbRows("payments");
    document.getElementById("db-count-payments").textContent = `(${rows.length})`;
    if (!rows.length) {
      el.innerHTML = '<span class="db-empty">Nenhum pagamento encontrado.</span>';
      return;
    }
    el.innerHTML = `<table class="db-table"><tr><th>ID</th><th>Usuário</th><th>Plano</th><th>Valor</th><th>Status</th><th>Data</th></tr>${rows.map(p => `<tr><td class="db-cell-id">${esc(p.id)}</td><td>${esc(p.user)}</td><td>${esc(p.plan)}</td><td class="db-amount ${p.status}">R$ ${esc(p.amount)}</td><td><span class="db-status-badge ${p.status}">${esc(statusLabel(p.status))}</span></td><td class="db-cell-date">${esc((p.created_at || "").slice(0,10))}</td></tr>`).join("")}</table>`;
  }

  function renderDbMemberships() {
    const el = document.getElementById("db-memberships");
    if (!el) return;
    const rows = filterDbRows("memberships");
    document.getElementById("db-count-memberships").textContent = `(${rows.length})`;
    if (!rows.length) {
      el.innerHTML = '<span class="db-empty">Nenhuma membresia ativa.</span>';
      return;
    }
    el.innerHTML = `<table class="db-table"><tr><th>Usuário</th><th>Plano</th><th>Expira</th><th>Criada</th></tr>${rows.map(m => `<tr><td>${esc(m.user)}</td><td>${esc(m.plan)}</td><td class="db-cell-date">${esc(m.expires_at ? m.expires_at.slice(0,10) : "—")}</td><td class="db-cell-date">${esc((m.created_at || "").slice(0,10))}</td></tr>`).join("")}</table>`;
  }

  function setupDbPanel() {
    const refreshBtn = document.getElementById("db-refresh-btn");
    if (refreshBtn) refreshBtn.addEventListener("click", loadDbPanel);

    const autoToggle = document.getElementById("db-auto-refresh");
    if (autoToggle) {
      autoToggle.addEventListener("change", () => {
        if (dbAutoTimer) { clearInterval(dbAutoTimer); dbAutoTimer = null; }
        if (autoToggle.checked) dbAutoTimer = setInterval(loadDbPanel, 30000);
      });
      dbAutoTimer = setInterval(loadDbPanel, 30000);
    }

    document.querySelectorAll(".db-search").forEach(input => {
      input.addEventListener("input", renderDbTables);
    });

    document.querySelectorAll("[data-db-export]").forEach(btn => {
      btn.addEventListener("click", () => {
        const type = btn.dataset.dbExport;
        const rows = dbData[type] || [];
        if (!rows.length) return;
        const headers = Object.keys(rows[0]);
        const csv = [headers.join(","), ...rows.map(r => headers.map(h => `"${(r[h]||"").replace(/"/g,'""')}"`).join(","))].join("\n");
        const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" });
        const a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = `rubymc_${type}_${new Date().toISOString().slice(0,10)}.csv`;
        a.click();
        URL.revokeObjectURL(a.href);
      });
    });
  }

  function updatePixStatus(status) {
    const indicator = document.getElementById("pix-status-indicator");
    if (!indicator) return;
    if (status === "completed") {
      indicator.innerHTML = `<span class="pix-status-dot completed"></span> Pagamento confirmado! Seu VIP está ativo. 🎉`;
      indicator.className = "pix-modal-status success";
    } else {
      indicator.innerHTML = `<span class="pix-status-dot pending"></span> Aguardando pagamento...`;
      indicator.className = "pix-modal-status";
    }
  }

  function copyPixCode() {
    const code = document.getElementById("pix-code-text");
    if (!code) return;
    if (navigator.clipboard) {
      navigator.clipboard.writeText(code.textContent).then(() => {
        const btn = code.nextElementSibling;
        if (btn) { btn.textContent = "✅ Copiado!"; setTimeout(() => { btn.textContent = "📋 Copiar"; }, 2000); }
      });
    } else {
      const range = document.createRange();
      range.selectNodeContents(code);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    }
  }

  /* ── Auth / Discord Login ──────────────────────────── */
  async function checkAuth() {
    const overlay = document.getElementById('login-overlay');
    const prompt = document.getElementById('login-prompt');
    const loading = document.getElementById('login-loading');

    try {
      const data = await apiFetch('/api/auth/status');
      if (data.authenticated) {
        window._userRole = data.role;
        window._userData = data.user;
        overlay.style.display = 'none';
        applyRoleFilter(data.role);
        updateRoleBadge(data.role, data.user);
        updateSettingsUserInfo(data.user, data.role);
        updateMemberCardRole(data.role);
        return true;
      }
    } catch (_) {}

    if (loading) loading.style.display = 'none';
    overlay.style.display = 'flex';
    if (prompt) prompt.style.display = '';
    handleLoginRedirect();
    return false;
  }

  function updateSettingsUserInfo(user, role) {
    const box = document.getElementById('settings-user-info');
    if (!box) return;
    box.style.display = '';

    const nameEl = document.getElementById('sui-name');
    const roleEl = document.getElementById('sui-role');
    const avatarEl = document.getElementById('sui-avatar');

    if (nameEl) nameEl.textContent = user?.username || '---';
    if (roleEl) {
      const labels = { admin: 'Admin', staff: 'Staff', player: 'Membro Ruby', member: 'Membro' };
      roleEl.className = 'sui-role-row';
      roleEl.innerHTML = '<img src="' + roleBadgeUrl(role) + '" class="role-badge-img" alt=""> ' + (labels[role] || role);
    }
    if (avatarEl && user?.avatar) {
      avatarEl.style.backgroundImage = "url(https://cdn.discordapp.com/avatars/" + user.id + "/" + user.avatar + ".png)";
    } else if (avatarEl) {
      avatarEl.style.backgroundImage = '';
      avatarEl.textContent = (user?.username || '?')[0].toUpperCase();
    }
  }

  function applyRoleFilter(role) {
    const allowedTabs = ROLE_TABS[role] || ROLE_TABS.player;
    document.querySelectorAll('.tab-link').forEach((btn) => {
      const tab = btn.dataset.tab;
      btn.style.display = (allowedTabs.includes(tab) || !tab) ? '' : 'none';
    });
    const currentTab = document.body.dataset.currentTab || 'home';
    if (!allowedTabs.includes(currentTab)) {
      activateTab('home');
    }

    const aiContext = document.querySelector('.ai-context-panel');
    if (aiContext) {
      aiContext.style.display = (role !== 'member') ? '' : 'none';
    }

    const serverAdminPanel = document.getElementById('server-admin-panel');
    if (serverAdminPanel) {
      serverAdminPanel.style.display = (role === 'admin' || role === 'staff') ? '' : 'none';
    }

    const aiBtn = document.querySelector('.tab-link[data-tab="ai"]');
    if (aiBtn && role === 'member') {
      if (!aiBtn.querySelector('.limited-badge')) {
        const badge = document.createElement('span');
        badge.className = 'limited-badge';
        badge.textContent = 'Limitada';
        aiBtn.appendChild(badge);
      }
    }
  }

  function roleBadgeUrl(role) {
    const map = {
      admin: '99882-owner-ruby-shiny.png',
      staff: '29168-admin-ruby-shiny.png',
      player: '62392-vip-ruby-shiny.png',
      member: '95929-member-ruby-shiny.png'
    };
    return '/assets/img/ruby-packs/' + (map[role] || '65091-rubymember.png');
  }

  function updateRoleBadge(role, user) {
    const badge = document.getElementById('role-badge');
    if (!badge) return;
    const labels = { admin: 'Admin', staff: 'Staff', player: 'Membro Ruby', member: 'Membro' };
    const label = labels[role] || 'Jogador';
    badge.innerHTML = '<img src="' + roleBadgeUrl(role) + '" alt=""> ' + label;
    badge.className = 'role-badge ' + (role === 'admin' ? 'role-badge-admin' : 'role-badge-player');
    badge.style.display = '';
  }

  function handleLoginRedirect() {
    const params = new URLSearchParams(window.location.search);
    const errorMsg = document.getElementById('login-error-msg');
    if (!params.get('login')) return;

    if (params.get('login') === 'error') {
      const reason = params.get('reason') || 'unknown';
      const messages = {
        no_code: 'Código de autorização não recebido.',
        missing_config: 'Configuração do Discord incompleta.',
        token_exchange_failed: 'Falha ao autenticar com Discord.',
        userinfo_failed: 'Falha ao obter informações do usuário.'
      };
      if (errorMsg) {
        errorMsg.textContent = messages[reason] || 'Erro ao autenticar. Tente novamente.';
        errorMsg.style.display = '';
      }
    }
    window.history.replaceState({}, '', '/');
  }

  /* ── Discord Info Loader ──────────────────────────── */
  function updateMemberCardRole(role) {
    const el = document.getElementById('msc-member-role');
    if (!el) return;
    const labels = { admin: 'Admin', staff: 'Staff', player: 'Membro Ruby', member: 'Membro' };
    el.innerHTML = '<img src="' + roleBadgeUrl(role) + '" class="role-badge-img" alt=""> ' + (labels[role] || role);
  }

  async function loadDiscordInfo() {
    try {
      const data = await apiFetch('/api/discord/members');
      if (data.ok && data.members) {
        setText('discord-guild-name', data.members.guild_name || '---');
        setText('msc-guild-name', data.members.guild_name || 'RubyMC');
        setText('discord-member-count', data.members.members_count);
        setText('discord-online-count', data.members.presence_count);
        setText('home-discord-members', data.members.members_count);
      }
    } catch (_) {}
  }

  /* ── Verification (Membro → Membro Ruby) ──────────── */
  function initVerification() {
    const verBox = document.getElementById('verification-box');
    const memberStatusCard = document.getElementById('member-status-card');
    if (!verBox) return;
    if (window._userRole !== 'member') {
      verBox.style.display = 'none';
      if (memberStatusCard) memberStatusCard.style.display = '';
      return;
    }
    verBox.style.display = '';

    const termsCheckbox = document.getElementById('terms-checkbox');
    const termsAcceptBtn = document.getElementById('terms-accept-btn');
    const discordStep = document.getElementById('vstep-discord');
    const discordJoinBtn = document.getElementById('discord-join-verify-btn') || document.getElementById('discord-join-btn');
    const discordCheckGuildBtn = document.getElementById('discord-check-guild-btn');
    const discordJoinDiv = document.getElementById('vstep-discord-join');
    const discordCodeDiv = document.getElementById('vstep-discord-code');
    const discordSendBtn = document.getElementById('discord-send-code-btn');
    const discordCodeInput = document.getElementById('discord-code-input');
    const discordConfirmBtn = document.getElementById('discord-confirm-code-btn');
    const discordMsg = document.getElementById('discord-code-msg');
    const discordGuildMsg = document.getElementById('discordGuildMsg');
    const completeBtn = document.getElementById('complete-verification-btn');
    const termsOverlay = document.getElementById('terms-overlay');
    const termsShowBtn = document.getElementById('terms-show-btn');
    const termsModalClose = document.getElementById('terms-modal-close');
    const termsModalBack = document.getElementById('terms-modal-back');

    function showTermsOverlay(show) {
      if (!termsOverlay) return;
      termsOverlay.style.display = show ? 'flex' : 'none';
    }

    // Open terms overlay
    if (termsShowBtn) {
      termsShowBtn.addEventListener('click', (e) => {
        e.preventDefault();
        showTermsOverlay(true);
      });
    }

    // Close terms overlay
    function closeTermsOverlay() { showTermsOverlay(false); }
    if (termsModalClose) termsModalClose.addEventListener('click', closeTermsOverlay);
    if (termsModalBack) termsModalBack.addEventListener('click', closeTermsOverlay);
    if (termsOverlay) termsOverlay.addEventListener('click', (e) => {
      if (e.target === termsOverlay) closeTermsOverlay();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && termsOverlay && termsOverlay.style.display === 'flex') closeTermsOverlay();
    });

    function setDiscordMsg(el, text, color) {
      if (!el) return;
      el.textContent = text;
      el.style.color = color || 'var(--muted)';
    }

    // Enable "Confirmar Termos" when checkbox is checked
    if (termsCheckbox && termsAcceptBtn) {
      termsCheckbox.addEventListener('change', () => {
        termsAcceptBtn.disabled = !termsCheckbox.checked;
      });
    }

    // Accept terms
    if (termsAcceptBtn) {
      termsAcceptBtn.addEventListener('click', async () => {
        try {
          const res = await apiPost('/api/auth/verify/accept-terms', {});
          if (res.ok) {
            document.getElementById('vstep-terms-status').textContent = '✓ aceito';
            document.getElementById('vstep-terms-status').style.color = '#00c853';
            if (discordStep) {
              discordStep.style.opacity = '1';
              discordStep.style.pointerEvents = 'auto';
              document.getElementById('vstep-discord-status').textContent = 'pendente';
              document.getElementById('vstep-discord-status').style.color = '#ffc107';
            }
          } else {
            setDiscordMsg(discordGuildMsg, res.error || 'Erro ao aceitar termos.', '#e74c3c');
          }
        } catch (e) {
          setDiscordMsg(discordGuildMsg, 'Erro de rede: ' + e.message, '#e74c3c');
        }
      });
    }

    // Join Discord server (opens invite link in new tab)
    if (discordJoinBtn) {
      discordJoinBtn.addEventListener('click', async () => {
        try {
          const res = await backendAction('discord_invite');
          const url = (res && res.url) || 'https://discord.gg/MnrSXTF4qx';
          window.open(url, '_blank');
          setDiscordMsg(discordGuildMsg, '🔗 Link do Discord aberto! Entre no servidor e depois clique em "Verificar presença".', '#ffc107');
        } catch (e) {
          setDiscordMsg(discordGuildMsg, 'Erro ao obter link: ' + e.message, '#e74c3c');
        }
      });
    }

    // Check guild membership
    if (discordCheckGuildBtn) {
      discordCheckGuildBtn.addEventListener('click', async () => {
        discordCheckGuildBtn.disabled = true;
        discordCheckGuildBtn.textContent = 'Verificando...';
        try {
          const res = await apiPost('/api/auth/verify/check-guild-membership', {});
          if (res.ok && res.in_guild) {
            setDiscordMsg(discordGuildMsg, '✅ Você está no servidor! Agora envie o código.', '#00c853');
            if (discordJoinDiv) discordJoinDiv.style.display = 'none';
            if (discordCodeDiv) discordCodeDiv.style.display = '';
            document.getElementById('vstep-discord-status').textContent = 'pendente';
            document.getElementById('vstep-discord-status').style.color = '#ffc107';
          } else {
            setDiscordMsg(discordGuildMsg, '❌ Você não está no servidor. Entre e tente novamente.', '#e74c3c');
          }
        } catch (e) {
          setDiscordMsg(discordGuildMsg, 'Erro de rede: ' + e.message, '#e74c3c');
        } finally {
          discordCheckGuildBtn.disabled = false;
          discordCheckGuildBtn.textContent = 'Verificar presença';
        }
      });
    }

    // Send Discord code
    if (discordSendBtn) {
      discordSendBtn.addEventListener('click', async () => {
        discordSendBtn.disabled = true;
        discordSendBtn.textContent = 'Enviando...';
        try {
          const res = await apiPost('/api/auth/verify/send-discord-code', {});
          if (res.ok) {
            setDiscordMsg(discordMsg, '✅ Código enviado! Verifique seu DM no Discord.', '#00c853');
            if (discordCodeInput) discordCodeInput.disabled = false;
            if (discordConfirmBtn) discordConfirmBtn.disabled = false;
          } else {
            setDiscordMsg(discordMsg, res.error || 'Erro ao enviar código.', '#e74c3c');
          }
        } catch (e) {
          setDiscordMsg(discordMsg, 'Erro de rede: ' + e.message, '#e74c3c');
        } finally {
          discordSendBtn.disabled = false;
          discordSendBtn.textContent = 'Enviar código';
        }
      });
    }

    // Confirm Discord code
    if (discordConfirmBtn) {
      discordConfirmBtn.addEventListener('click', async () => {
        const code = discordCodeInput ? discordCodeInput.value.trim() : '';
        if (!code || code.length < 6) {
          setDiscordMsg(discordMsg, 'Insira o código de 6 dígitos recebido no Discord.', '#e74c3c');
          return;
        }
        discordConfirmBtn.disabled = true;
        discordConfirmBtn.textContent = 'Confirmando...';
        try {
          const res = await apiPost('/api/auth/verify/confirm-discord-code', { code: code });
          if (res.ok) {
            document.getElementById('vstep-discord-status').textContent = '✓ verificado';
            document.getElementById('vstep-discord-status').style.color = '#00c853';
            setDiscordMsg(discordMsg, '✅ Código confirmado!', '#00c853');
            checkVerificationComplete();
          } else {
            setDiscordMsg(discordMsg, res.error || 'Código inválido.', '#e74c3c');
          }
        } catch (e) {
          setDiscordMsg(discordMsg, 'Erro de rede: ' + e.message, '#e74c3c');
        } finally {
          discordConfirmBtn.disabled = false;
          discordConfirmBtn.textContent = 'Confirmar';
        }
      });
    }

    // Complete verification
    if (completeBtn) {
      completeBtn.addEventListener('click', async () => {
        completeBtn.disabled = true;
        completeBtn.textContent = 'Processando...';
        try {
          const res = await apiPost('/api/auth/verify/complete', {});
          if (res.ok) {
            window._userRole = res.role || 'player';
            applyRoleFilter(window._userRole);
            updateRoleBadge(window._userRole, window._userData);
            updateMemberCardRole(window._userRole);
            if (verBox) verBox.style.display = 'none';
            if (memberStatusCard) {
              memberStatusCard.style.display = '';
              memberStatusCard.querySelectorAll('button').forEach((btn) => {
                btn.disabled = false;
                btn.removeAttribute('disabled');
              });
            }
            loadDiscordInfo();
            log('OK', '🎉 Parabéns! Você agora é Membro Ruby!');
            alert('Parabéns! Agora você é Membro Ruby. As funcionalidades completas foram liberadas.');
          } else {
            alert(res.error || 'Erro ao completar verificação.');
          }
        } catch (e) {
          alert('Erro de rede: ' + e.message);
        } finally {
          completeBtn.disabled = false;
          completeBtn.textContent = 'Tornar-se Membro Ruby';
        }
      });
    }

    loadVerificationStatus();
  }

  async function checkVerificationComplete() {
    try {
      const res = await apiFetch('/api/auth/verify/status');
      if (res.ok && res.overall_complete) {
        const btn = document.getElementById('complete-verification-btn');
        if (btn) btn.disabled = false;
      }
    } catch (_) {}
  }

  async function loadVerificationStatus() {
    try {
      const res = await apiFetch('/api/auth/verify/status');
      if (!res.ok) return;

      if (res.terms_accepted) {
        document.getElementById('vstep-terms-status').textContent = '✓ aceito';
        document.getElementById('vstep-terms-status').style.color = '#00c853';
        const ds = document.getElementById('vstep-discord');
        if (ds) { ds.style.opacity = '1'; ds.style.pointerEvents = 'auto'; }
      }

      if (res.discord_verified) {
        document.getElementById('vstep-discord-status').textContent = '✓ verificado';
        document.getElementById('vstep-discord-status').style.color = '#00c853';
      }

      if (res.overall_complete) {
        const btn = document.getElementById('complete-verification-btn');
        if (btn) btn.disabled = false;
      }
    } catch (_) {}
  }

  function init() {
    const loginBtn = document.getElementById('login-discord-btn');
    if (loginBtn) {
      loginBtn.addEventListener('click', () => { window.location.href = '/api/auth/discord/login'; });
    }

    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) {
      logoutBtn.addEventListener('click', async () => {
        try {
          await apiFetch('/api/auth/logout', { method: 'POST' });
        } catch (_) {}
        window.location.reload();
      });
    }

    checkAuth().then((authenticated) => {
      if (!authenticated) return;

      document.body.dataset.currentTab = document.body.dataset.currentTab || 'home';

      bindEvents();

      log('SYSTEM', 'Interface RubyMC pronta. Safe JSON parser ativo.');

      refreshStatus();
      updateModpacks(false).catch(() => {});
      setTimeout(loadVersions, 350);
      setTimeout(loadAccounts, 500);
      setTimeout(loadServerList, 200);
      setTimeout(renderServerGrid, 300);
      startServerPolling();
      setInterval(renderServerGrid, 5000);

      setInterval(pollLogs, 4000);

      initVerification();
      setTimeout(loadDiscordInfo, 600);
    });
  }

  document.addEventListener("DOMContentLoaded", init);


  window.backendAction = async function(action) {
    try {
      const result = await backendAction(action);
      applyResult(result, action);
      return result;
    } catch (error) {
      log("ERROR", `${action}: ${error.message}`);
      throw error;
    }
  };

  window.runRubyMCAction = runAction;
  window.refreshServerLiveStatus = refreshServerLiveStatus;
  window.confirmPendingPayment = confirmPendingPayment;
  window.rejectPendingPayment = rejectPendingPayment;
})();