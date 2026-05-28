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
    join_server: ["join_server", "server_join"],
    enter_server: ["enter_server"],
    play_bedrock: ["play_bedrock"],
    play_bedrock_server: ["play_bedrock_server"],
    update_modpacks: ["update_modpacks", "refresh_modpacks", "list_modpacks"],
    validate_discord: ["validate_discord", "discord_validate", "validate_discord_settings"],
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
    "server_stop", "restart_server", "server_restart", "play", "start_minecraft",
    "launch_minecraft", "launch_classic", "play_bedrock", "play_bedrock_server"
  ]);

  const SERVER_CONTROL_ACTIONS = new Set([
    "test_server",
    "start_server",
    "stop_server",
    "restart_server"
  ]);

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

    document.body.dataset.currentTab = tab;

    $$(".tab-link, .side-link").forEach((button) => {
      button.classList.toggle("active", button.dataset.tab === tab);
    });

    $$(".tab-panel").forEach((panel) => {
      panel.classList.toggle("active", panel.id === `tab-${tab}`);
    });

    const panel = $(`#tab-${tab}`);
    if (panel) document.title = `RubyMC Launcher — ${panel.dataset.panelTitle || tab}`;

    if (tab === "server") {
      if (typeof window.currentType === "function" && window.currentType() === "bedrock") {
        setTimeout(() => window.dispatchEvent(new Event("bedrock-versions-changed")), 120);
      } else {
        setTimeout(refreshServerLiveStatus, 120);
      }
      setTimeout(loadVersions, 160);
    }
    if (tab === "versions") setTimeout(loadVersions, 100);
    if (tab === "settings") setTimeout(loadAccounts, 200);
  }

  function actionPayload(action) {
    return {
      action,
      profile: $("#profile-select")?.value || "vanilla",
      modpack_name: $("#modpack-name")?.value || "",
      server_address: $("#server-address")?.value || "",
      server_version_id: $("#server-version-select")?.value || "",
      server_loader: $("#server-version-select")?.selectedOptions?.[0]?.dataset?.loader || "",
      bedrock_version: $("#bedrock-version")?.value || "",
      settings: {
        version: $("#settings-version")?.value || "",
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

      try {
        return await apiPost(`/api/${alias}`, actionPayload(alias));
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError;
  }

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
    setText("minecraft-version", status.minecraft_version || status.default_version || status.version);
    setText("active-profile", status.active_profile || status.profile);
    setText("server-state", status.server_status || status.server_state || status.server);
    setText("server-players", status.server_players || status.players);
    setText("launcher-state", status.launcher_status || status.status);
    setText("launcher-version", status.launcher_version || status.version);
    setValue("server-address", status.server_address || status.community_server || status.address);

    if (status.versions && status.versions.active) {
      const active = status.versions.active;
      setText("minecraft-version", active.id);
      setText("active-profile", active.label || active.loader || "Vanilla");

      const profileSelect = $("#profile-select");
      if (profileSelect) {
        profileSelect.dataset.installedVersions = JSON.stringify(status.versions.installed || []);
        populateProfileSelect(profileSelect);
      }

      const settingsVersion = $("#settings-version");
      if (settingsVersion) {
        const current = settingsVersion.value;
        const versions = status.versions.installed || [];
        settingsVersion.innerHTML = versions
            .map((version) => `<option value="${esc(version.id)}">${esc(version.id)} (${esc(version.loader_label || version.loader || "vanilla")})</option>`)
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
      const botOnline = discord.bot_enabled === true || discord.bot === true || discord.status === "ativo" || discord.bot_state === "ativo";
      setText("discord-bot-state", botOnline ? "Ativo" : (discord.bot_state || "Inativo"));
      setText("discord-channel-count", discord.channels || discord.channel_count || discord.channels_count ||
          (discord.channels_configured !== undefined ? `${discord.channels_configured}/${discord.channels_total}` : undefined));
      setText("discord-role-count", discord.roles || discord.role_count || discord.roles_count ||
          (discord.roles_configured !== undefined ? `${discord.roles_configured}/${discord.roles_total}` : undefined));
      setText("logs-channel-state", discord.logs_channel || discord.logs_channel_id ? "configurado" : "pendente");
      setText("discord-config-state", discord.configured === false ? "pendente" : "configurado");
      setText("discord-member-count", discord.members_count);
      setText("discord-online-count", discord.presence_count);
    }
  }

  function populateProfileSelect(select) {
    if (!select) return;

    const current = select.value;
    let html = '<option value="vanilla">Vanilla / sem modpack</option>';
    html += select._modpackOptions || "";

    try {
      const raw = select.dataset.installedVersions;
      if (raw) {
        const versions = JSON.parse(raw);
        if (Array.isArray(versions) && versions.length) {
          html += '<option disabled>── Versões ──</option>';
          versions.forEach((version) => {
            const label = version.loader_label || version.loader || "vanilla";
            html += `<option value="version:${esc(version.id)}">🎮 ${esc(version.id)} (${esc(label)})</option>`;
          });
        }
      }
    } catch (_) {}

    select.innerHTML = html;
    if ([...select.options].some((option) => option.value === current)) select.value = current;
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
        return `<option value="${esc(name)}">${esc(name)}</option>`;
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

    if (value.startsWith("version:")) {
      const versionId = value.slice(8);
      busy = true;
      try {
        const data = await apiPost("/api/action", { action: "profile_select", version_id: versionId });
        if (data.ok) {
          log("OK", "Perfil alterado para versão " + versionId);
          refreshStatus();
        } else {
          log("ERROR", "Falha ao ativar versão: " + (data.error || "erro desconhecido"));
        }
      } catch (error) {
        log("ERROR", "Falha ao alterar perfil: " + error.message);
      } finally {
        busy = false;
      }
      return;
    }

    log("ACTION", "Perfil alterado para: " + value);
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
    setText("server-overlay-status", online ? "Online" : "Offline");
    setText("server-overlay-players", playerRatio(status));
    setText("server-overlay-ping", status.latency ? `${status.latency} ms` : "--");
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
    const activeButton = $(".side-link.active, .tab-link.active");
    return activeButton?.dataset?.tab === "server" || $("#tab-server")?.classList.contains("active");
  }

  function startServerPolling() {
    if (serverPollTimer) clearInterval(serverPollTimer);
    serverPollTimer = setInterval(() => {
      if (!isServerTabActive()) return;
      if (typeof window.currentType === "function" && window.currentType() === "bedrock") {
        window.dispatchEvent(new Event("bedrock-versions-changed"));
      } else {
        refreshServerLiveStatus();
      }
    }, 15000);
  }

  async function loadVersions() {
    try {
      const data = await apiFetch("/api/versions");
      if (!data.ok) throw new Error(data.error || "Falha ao carregar versões");

      activeVersion = data.active || null;
      installedVersions = data.installed || [];

      renderActiveVersion();
      renderInstalledVersions();
      renderServerVersionSelect();
    } catch (error) {
      log("ERROR", "Versões: " + error.message);
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

    element.innerHTML = installedVersions.map((version) => {
      const isActive = activeVersion && activeVersion.id === version.id;
      return `
        <div class="version-item ${isActive ? "version-active" : ""}">
          <div class="version-item-info">
            <strong>${esc(version.id)}</strong>
            <span class="version-item-loader">${esc(version.loader_label || version.loader || "vanilla")}</span>
            <small>${esc(version.size_kb || "")} KB</small>
          </div>
          <div class="version-item-actions">
            ${isActive
          ? '<span class="version-active-badge">Ativa</span>'
          : `<button class="btn btn-red btn-sm" data-version-activate="${esc(version.id)}">Ativar</button>`
      }
            <button class="btn btn-dark btn-sm" data-version-remove="${esc(version.id)}" ${isActive ? 'disabled title="Desative primeiro"' : ""}>Remover</button>
          </div>
        </div>
      `;
    }).join("");
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

  async function checkBedrock() {
    const section = document.getElementById("bedrock-section");
    const statusElement = document.getElementById("bedrock-status");
    const versionSelect = document.getElementById("bedrock-version");
    const playButton = document.querySelector('[data-action="play_bedrock"]');
    const playServerButton = document.querySelector('[data-action="play_bedrock_server"]');

    if (!section || !statusElement) return;

    try {
      const data = await apiFetch("/api/bedrock/check");
      if (!data.ok) throw new Error(data.error || "Falha na verificação");

      if (!data.installed) {
        statusElement.textContent = "mcpelauncher não detectado. Instale via Flatpak: flatpak install io.mrarm.mcpelauncher";
        return;
      }

      section.style.display = "";
      statusElement.textContent = "mcpelauncher detectado!";

      const versions = data.versions || [];
      if (versionSelect) {
        if (versions.length) {
          versionSelect.innerHTML = versions.map((version) => `<option value="${esc(version)}">${esc(version)}</option>`).join("");
          versionSelect.disabled = false;
        } else {
          versionSelect.innerHTML = '<option value="">Nenhuma versão instalada</option>';
        }
      }

      if (playButton) playButton.disabled = false;
      if (playServerButton) playServerButton.disabled = false;
    } catch (error) {
      statusElement.textContent = "Erro: " + error.message;
    }
  }

  async function reloadBedrockVersions() {
    const versionSelect = document.getElementById("bedrock-version");
    if (!versionSelect) return;

    try {
      const data = await apiFetch("/api/bedrock/check");
      if (!data.ok) return;

      const versions = data.versions || [];
      if (versions.length) {
        versionSelect.innerHTML = versions.map((version) => `<option value="${esc(version)}">${esc(version)}</option>`).join("");
        versionSelect.disabled = false;
      } else {
        versionSelect.innerHTML = '<option value="">Nenhuma versão instalada</option>';
      }
    } catch (_) {}
  }

  function setBedrockStatus(message) {
    const element = document.getElementById("bedrock-status");
    if (element) element.textContent = message;
  }

  async function openBedrockManager(button) {
    if (!button) return;

    button.disabled = true;
    button.textContent = "Abrindo...";

    try {
      const data = await apiFetch("/api/bedrock/open-manager", { method: "POST" });
      setBedrockStatus(data.ok ? "Gerenciador aberto." : "Erro: " + (data.error || "desconhecido"));
    } catch (error) {
      setBedrockStatus("Erro de rede: " + error.message);
    } finally {
      button.disabled = false;
      button.textContent = "Abrir Gerenciador";
    }
  }

  async function importBedrockApk(button) {
    const input = document.getElementById("bedrock-apk-input");
    const status = document.getElementById("bedrock-import-status");

    if (!button || !input || !status) return;

    const file = input.files[0];
    if (!file) {
      status.textContent = "Selecione um arquivo .apk primeiro.";
      return;
    }

    button.disabled = true;
    button.textContent = "Extraindo...";
    status.textContent = "";

    try {
      const formData = new FormData();
      formData.append("apk", file, file.name);
      const data = await apiFetch("/api/bedrock/import-apk", { method: "POST", body: formData });
      status.textContent = data.ok ? data.message : "Erro: " + (data.error || "desconhecido");

      if (data.ok) {
        setTimeout(() => window.dispatchEvent(new CustomEvent("bedrock-versions-changed")), 500);
      }
    } catch (error) {
      status.textContent = "Erro de rede: " + error.message;
    } finally {
      button.disabled = false;
      button.textContent = "Extrair versão";
      input.value = "";
    }
  }

  async function loadAvailableBedrockServers() {
    const select = document.getElementById("bedrock-server-version-select");
    const downloadStatus = document.getElementById("bedrock-server-download-status");
    if (!select) return;

    select.innerHTML = "<option>Carregando...</option>";

    try {
      const data = await apiFetch("/api/bedrock/servers/available");
      if (!data.ok) throw new Error(data.error || "Falha na requisição");

      const versions = data.versions || [];
      if (!versions.length) {
        select.innerHTML = '<option value="">Nenhuma versão encontrada</option>';
        return;
      }

      select.innerHTML = versions.map((version) => `<option value="${esc(version)}">${esc(version)}</option>`).join("");

      const preview = data.preview_versions || [];
      if (preview.length) {
        const optgroup = document.createElement("optgroup");
        optgroup.label = "Preview";
        preview.forEach((version) => {
          const option = document.createElement("option");
          option.value = version;
          option.textContent = version + " (preview)";
          optgroup.appendChild(option);
        });
        select.appendChild(optgroup);
      }

      select.disabled = false;
    } catch (error) {
      select.innerHTML = '<option value="">Erro ao carregar</option>';
      if (downloadStatus) downloadStatus.textContent = "Erro: " + error.message;
    }
  }

  async function downloadBedrockServer(button) {
    const select = document.getElementById("bedrock-server-version-select");
    const status = document.getElementById("bedrock-server-download-status");

    if (!button || !select) return;

    const version = select.value;
    if (!version) return;

    button.disabled = true;
    button.textContent = "Baixando...";
    if (status) status.textContent = "Aguarde, baixando " + version + "...";

    try {
      const data = await apiPost("/api/bedrock/servers/download", { version });
      if (status) {
        status.textContent = data.ok
            ? "Servidor " + version + " instalado com sucesso!"
            : "Erro: " + (data.error || "desconhecido");
      }
      if (data.ok) refreshInstalledBedrockServers();
    } catch (error) {
      if (status) status.textContent = "Erro de rede: " + error.message;
    } finally {
      button.disabled = false;
      button.textContent = "Baixar";
      loadAvailableBedrockServers();
    }
  }

  async function refreshInstalledBedrockServers() {
    const list = document.getElementById("bedrock-server-list");
    const statusDiv = document.getElementById("bedrock-server-status");
    const versionLabel = document.getElementById("bedrock-server-version-label");
    const pidLabel = document.getElementById("bedrock-server-pid-label");

    if (!list) return;

    try {
      const data = await apiFetch("/api/bedrock/servers/installed");
      if (!data.ok) throw new Error(data.error || "Falha");

      const servers = data.servers || [];
      if (!servers.length) {
        list.innerHTML = '<small class="bedrock-hint">Nenhum servidor instalado. Baixe uma versão acima.</small>';
        if (statusDiv) statusDiv.style.display = "none";
        return;
      }

      list.innerHTML = servers.map((server) => `
        <div class="bedrock-server-item ${server.running ? "bedrock-server-item-running" : ""}">
          <span class="bedrock-server-item-version">
            ${server.running ? '<span class="bedrock-server-badge bedrock-server-online">●</span> ' : '<span class="bedrock-server-badge bedrock-server-offline">○</span> '}
            ${esc(server.version)}
          </span>
          ${server.running
          ? `<span class="bedrock-server-item-pid">PID ${esc(server.pid)}</span>
               <button class="btn btn-red btn-sm bedrock-server-item-stop" data-bedrock-server-stop-version="${esc(server.version)}">Parar</button>`
          : `<button class="btn btn-cyan btn-sm bedrock-server-item-start" data-bedrock-server-start-version="${esc(server.version)}">Iniciar</button>`
      }
        </div>
      `).join("");

      const running = servers.find((server) => server.running);
      if (running) {
        if (statusDiv) statusDiv.style.display = "flex";
        if (versionLabel) versionLabel.textContent = running.version;
        if (pidLabel) pidLabel.textContent = "PID " + running.pid;

        // fetch real RakNet status for dedicated bedrock elements
        try {
          const statusData = await apiFetch("/api/bedrock/servers/status");
          const badge = statusDiv?.querySelector(".bedrock-server-badge");
          if (badge) {
            if (statusData.online) {
              badge.textContent = "● Online";
              badge.className = "bedrock-server-badge bedrock-server-online";
            } else {
              badge.textContent = "● Rodando (offline)";
              badge.className = "bedrock-server-badge bedrock-server-offline";
            }
          }
          setText("bedrock-server-latency", statusData.latency_ms ? `${statusData.latency_ms} ms` : "");
          const players = statusData.players || {};
          setText("bedrock-server-players", players.online != null ? `${players.online}/${players.max || "?"}` : "");
          const motd = document.getElementById("bedrock-server-motd");
          if (motd) motd.textContent = statusData.description || "";
        } catch (_) {
          const badge = statusDiv?.querySelector(".bedrock-server-badge");
          if (badge) {
            badge.textContent = "● Rodando";
            badge.className = "bedrock-server-badge bedrock-server-online";
          }
        }
      } else if (statusDiv) {
        statusDiv.style.display = "none";
      }
    } catch (_) {
      list.innerHTML = '<small class="bedrock-hint">Erro ao carregar servidores.</small>';
    }
  }

  async function startBedrockServer(version) {
    try {
      const data = await apiPost("/api/bedrock/servers/start", { version });
      if (data.ok) refreshInstalledBedrockServers();
      else alert("Erro ao iniciar servidor: " + (data.error || "desconhecido"));
    } catch (error) {
      alert("Erro de rede: " + error.message);
    }
  }

  async function stopBedrockServer(version) {
    try {
      const data = await apiPost("/api/bedrock/servers/stop", { version });
      if (data.ok) refreshInstalledBedrockServers();
      else alert("Erro ao parar servidor: " + (data.error || "desconhecido"));
    } catch (error) {
      alert("Erro de rede: " + error.message);
    }
  }

  function bindEvents() {
    $$(".tab-link, .side-link").forEach((button) => {
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

    const settingsVersion = document.getElementById("settings-version");
    if (settingsVersion) {
      settingsVersion.addEventListener("change", () => {
        if (settingsVersion.value) handleProfileChange("version:" + settingsVersion.value);
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

    const addBedrockButton = document.getElementById("add-bedrock-btn");
    if (addBedrockButton) addBedrockButton.addEventListener("click", () => startAuth("bedrock"));

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

    const openManagerButton = document.getElementById("bedrock-open-manager");
    if (openManagerButton) openManagerButton.addEventListener("click", () => openBedrockManager(openManagerButton));

    const apkImportButton = document.getElementById("bedrock-apk-import");
    if (apkImportButton) apkImportButton.addEventListener("click", () => importBedrockApk(apkImportButton));

    const bedrockDownloadButton = document.getElementById("bedrock-server-download");
    if (bedrockDownloadButton) {
      bedrockDownloadButton.addEventListener("click", () => downloadBedrockServer(bedrockDownloadButton));
    }

    const bedrockStopButton = document.getElementById("bedrock-server-stop");
    if (bedrockStopButton) {
      bedrockStopButton.addEventListener("click", async () => {
        await stopBedrockServer("");
        refreshInstalledBedrockServers();
      });
    }

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

    const startBedrockButton = event.target.closest("[data-bedrock-server-start-version]");
    if (startBedrockButton) {
      startBedrockServer(startBedrockButton.dataset.bedrockServerStartVersion);
      return;
    }

    const stopBedrockButton = event.target.closest("[data-bedrock-server-stop-version]");
    if (stopBedrockButton) {
      stopBedrockServer(stopBedrockButton.dataset.bedrockServerStopVersion);
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
      setText("discord-member-count", data.members_count);
      setText("discord-online-count", data.presence_count);
      button.classList.add(simClass);
      button.textContent = labelOff;
    }

    document.querySelectorAll('[data-action="validate_discord"]').forEach((validateButton) => {
      validateButton.addEventListener("click", resetSimulation);
    });

    button.addEventListener("click", async (event) => {
      event.stopImmediatePropagation();

      if (button.classList.contains(simClass)) {
        ["discord-member-count", "discord-online-count"].forEach((id) => setText(id, "--"));
        setText("discord-bot-state", "Inativo");
        setText("discord-channel-count", "--/--");
        setText("discord-role-count", "--/--");
        resetSimulation();
        return;
      }

      try {
        const data = await apiPost("/api/action", { action: "simular_discord" });
        if (data.ok && data.discord) applySimulation(data.discord);
      } catch (_) {}
    });
  }

  function init() {
    document.body.dataset.currentTab = document.body.dataset.currentTab || "home";

    bindEvents();

    log("SYSTEM", "Interface RubyMC pronta. Safe JSON parser ativo.");

    refreshStatus();
    updateModpacks(false).catch(() => {});
    setTimeout(loadVersions, 350);
    setTimeout(loadAccounts, 500);
    setTimeout(checkBedrock, 1000);
    loadAvailableBedrockServers();
    refreshInstalledBedrockServers();
    startServerPolling();

    setInterval(pollLogs, 4000);

    window.addEventListener("bedrock-versions-changed", () => {
      reloadBedrockVersions();
      refreshInstalledBedrockServers();
    });
  }

  document.addEventListener("DOMContentLoaded", init);

  window.refreshServerLiveStatus = refreshServerLiveStatus;
})();