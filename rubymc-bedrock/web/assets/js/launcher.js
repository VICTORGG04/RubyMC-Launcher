/* =========================================================
   RubyMC BDS Server-Only Frontend
   Controla somente Bedrock Dedicated Server. Não usa cliente
   Bedrock, mcpelauncher, Google Play ou importação APK.
   ========================================================= */
(() => {
  "use strict";

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  const state = {
    available: [],
    installed: [],
    status: null,
    busy: false
  };

  function esc(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function setText(selector, value) {
    const el = $(selector);
    if (el) el.textContent = value ?? "";
  }

  function setHTML(selector, html) {
    const el = $(selector);
    if (el) el.innerHTML = html;
  }

  function setBusy(button, busyText = "Processando...") {
    if (!button) return () => {};
    const oldText = button.textContent;
    button.disabled = true;
    button.textContent = busyText;
    return () => {
      button.disabled = false;
      button.textContent = oldText;
    };
  }

  async function readJson(response, endpoint) {
    const text = await response.text();

    let data = {};
    if (text.trim()) {
      try {
        data = JSON.parse(text);
      } catch (error) {
        throw new Error(`JSON inválido em ${endpoint}: ${error.message}`);
      }
    }

    if (!response.ok || data.ok === false) {
      throw new Error(data.error || data.message || `HTTP ${response.status}`);
    }

    return data;
  }

  async function getJson(endpoint) {
    const response = await fetch(endpoint, {
      headers: { Accept: "application/json" }
    });
    return readJson(response, endpoint);
  }

  async function postJson(endpoint, payload = {}) {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });
    return readJson(response, endpoint);
  }

  function logLine(type, message) {
    const display = $("#display-log");
    if (!display) return;

    const time = new Date().toLocaleTimeString("pt-BR", { hour12: false });
    display.textContent += `\n[${time}] ${String(type).toUpperCase().padEnd(7)} ${message}`;
    display.scrollTop = display.scrollHeight;
  }

  function activateTab(tabName) {
    if (!tabName) return;

    $$(".tab-link").forEach((button) => {
      button.classList.toggle("active", button.dataset.tab === tabName);
    });

    $$(".tab-panel").forEach((panel) => {
      panel.classList.toggle("active", panel.id === `tab-${tabName}`);
    });

    document.body.dataset.currentTab = tabName;

    if (tabName === "versions") {
      refreshVersions();
    } else if (tabName === "server" || tabName === "home") {
      refreshStatus();
      refreshInstalled();
    } else if (tabName === "display") {
      refreshLogs();
    }
  }

  function normalizeVersion(item) {
    if (!item) return null;

    if (typeof item === "string") {
      return {
        version: item,
        label: item,
        url: "",
        channel: "stable"
      };
    }

    const version = item.version || item.id || item.name || "";
    if (!version) return null;

    const channel = item.channel || "stable";

    return {
      version,
      label: `${version}${channel === "preview" ? " (Preview)" : ""}`,
      url: item.url || item.download_url || "",
      channel
    };
  }

  async function refreshAvailable() {
    const select = $("#bds-available-select");
    if (select) {
      select.innerHTML = '<option value="">Carregando...</option>';
    }

    try {
      const data = await getJson("/api/bedrock/servers/available");
      const versions = [
        ...(data.versions || []),
        ...(data.preview_versions || [])
      ].map(normalizeVersion).filter(Boolean);

      state.available = versions;

      if (!select) return;

      if (!versions.length) {
        select.innerHTML = '<option value="">Nenhuma versão oficial encontrada</option>';
        setText("#bds-install-status", "Não consegui carregar a lista oficial. Use instalação manual apenas com uma versão BDS válida.");
        return;
      }

      select.innerHTML = versions.map((item) => `
        <option value="${esc(item.version)}" data-url="${esc(item.url)}" data-channel="${esc(item.channel)}">
          ${esc(item.label)}
        </option>
      `).join("");

      setText("#bds-install-status", `Lista carregada: ${versions.length} versão(ões) encontradas.`);
    } catch (error) {
      state.available = [];
      if (select) {
        select.innerHTML = '<option value="">Erro ao carregar versões</option>';
      }
      setText("#bds-install-status", `Erro ao carregar versões oficiais: ${error.message}`);
      logLine("ERROR", `Versões BDS disponíveis: ${error.message}`);
    }
  }

  async function refreshInstalled() {
    try {
      const data = await getJson("/api/bedrock/servers/installed");
      state.installed = data.servers || data.installed || [];
      renderInstalled();
    } catch (error) {
      state.installed = [];
      renderInstalled(error);
      logLine("ERROR", `Versões BDS instaladas: ${error.message}`);
    }
  }

  function renderInstalled(error = null) {
    const html = error
      ? `<div class="bds-error">Erro: ${esc(error.message)}</div>`
      : state.installed.length
        ? state.installed.map(renderServerItem).join("")
        : '<div class="bds-empty">Nenhuma versão BDS instalada.</div>';

    setHTML("#bds-server-list", html);
    setHTML("#bds-installed-list", html);
  }

  function renderServerItem(server) {
    const version = server.version || server.id || "";
    const path = server.path || "";
    const pid = server.pid || "";
    const running = server.running === true || server.running === "true";

    const badge = running
      ? '<span class="bds-badge bds-badge-online">● Online</span>'
      : '<span class="bds-badge bds-badge-offline">○ Parado</span>';

    const mainAction = running
      ? `<button class="btn btn-red btn-sm" data-bds-stop="${esc(version)}">Parar</button>
         <button class="btn btn-dark btn-sm" data-bds-restart="${esc(version)}">Reiniciar</button>`
      : `<button class="btn btn-cyan btn-sm" data-bds-start="${esc(version)}">Iniciar</button>`;

    return `
      <div class="bds-server-item">
        <div class="bds-server-title">
          ${badge}
          <strong>Minecraft Bedrock ${esc(version)}</strong>
          <small>BDS instalado${pid ? ` · PID ${esc(pid)}` : ""}</small>
          ${path ? `<small>${esc(path)}</small>` : ""}
        </div>
        <div class="bds-server-actions">
          ${mainAction}
          <button class="btn btn-dark btn-sm" data-bds-logs="${esc(version)}">Logs</button>
          <button class="btn btn-dark btn-sm" data-bds-remove="${esc(version)}">Remover</button>
        </div>
      </div>
    `;
  }

  async function refreshStatus() {
    try {
      const data = await getJson("/api/bedrock/servers/status");
      state.status = data;
      renderStatus(data);
    } catch (error) {
      state.status = null;
      renderStatusError(error);
      logLine("ERROR", `Status BDS: ${error.message}`);
    }
  }

  function renderStatus(data) {
    const online = data.online === true || data.port_open === true;
    const running = data.running === true || data.process_running === true;
    const version = data.version || "--";
    const pid = data.pid || "--";
    const port = data.port || 19132;

    setText("#home-bds-state", online ? "Online" : running ? "Processo ativo" : "Offline");
    setText("#home-bds-detail", data.message || "--");
    setText("#home-bds-version", version || "--");
    setText("#home-bds-port", String(port));
    setText("#home-bds-players", playersText(data.players));

    setText("#server-test-state", online ? "Online" : "Offline");
    setText("#server-test-detail", data.message || data.error || "--");
    setText("#server-live-online", online ? "Sim" : "Não");
    setText("#server-live-max", playersText(data.players));
    setText("#server-live-latency", data.latency_ms ? `${data.latency_ms} ms` : "--");
    setText("#server-live-version", version || "--");
    setText("#server-live-checked", data.checked_at || "--");

    setText("#bedrock-server-latency", data.latency_ms ? `${data.latency_ms} ms` : "--");
    setText("#bedrock-server-players", playersText(data.players));
    setText("#bedrock-server-motd", data.description || "--");

    setText("#bds-active-version", running ? `Minecraft Bedrock ${version || "--"}` : "Nenhum BDS rodando");
    setText("#bds-active-pid", running ? `PID ${pid}` : "PID --");

    const activeBox = $("#bds-active-box");
    if (activeBox) {
      const badge = activeBox.querySelector(".bds-badge");
      if (badge) {
        badge.className = running ? "bds-badge bds-badge-online" : "bds-badge bds-badge-muted";
        badge.textContent = running ? "● Rodando" : "○ Parado";
      }
    }

    const address = data.address || `127.0.0.1:${port}`;
    const serverAddress = $("#server-address");
    if (serverAddress) serverAddress.value = address;

    setText("#settings-server-address", address);
  }

  function renderStatusError(error) {
    setText("#home-bds-state", "Erro");
    setText("#home-bds-detail", error.message);
    setText("#server-test-state", "Erro");
    setText("#server-test-detail", error.message);
  }

  function playersText(players) {
    if (!players) return "0/0";
    const online = players.online ?? 0;
    const max = players.max ?? 0;
    return `${online}/${max}`;
  }

  async function installSelected(button) {
    const select = $("#bds-available-select");
    const option = select?.selectedOptions?.[0];

    if (!option || !option.value) {
      alert("Nenhuma versão BDS oficial selecionada.");
      return;
    }

    const restore = setBusy(button);
    try {
      const payload = {
        version: option.value,
        url: option.dataset.url || "",
        channel: option.dataset.channel || "stable"
      };

      setText("#bds-install-status", `Instalando BDS ${payload.version}...`);
      logLine("ACTION", `Instalando BDS ${payload.version}...`);

      const data = await postJson("/api/bedrock/servers/download", payload);
      setText("#bds-install-status", data.message || "BDS instalado.");
      logLine("OK", data.message || `BDS ${payload.version} instalado.`);

      await refreshInstalled();
      await refreshStatus();
    } catch (error) {
      setText("#bds-install-status", `Erro: ${error.message}`);
      logLine("ERROR", `Instalar BDS: ${error.message}`);
      alert(`Erro ao instalar BDS: ${error.message}`);
    } finally {
      restore();
    }
  }

  async function installLatest(button) {
    const restore = setBusy(button);
    try {
      setText("#bds-install-status", "Instalando a versão mais recente...");
      const data = await postJson("/api/bedrock/servers/download", {});
      setText("#bds-install-status", data.message || "BDS instalado.");
      logLine("OK", data.message || "BDS mais recente instalado.");
      await refreshInstalled();
      await refreshStatus();
    } catch (error) {
      setText("#bds-install-status", `Erro: ${error.message}`);
      alert(`Erro ao instalar BDS: ${error.message}`);
    } finally {
      restore();
    }
  }

  async function installManual(button) {
    const input = $("#bds-manual-version");
    const version = input?.value?.trim();

    if (!version) {
      alert("Informe uma versão BDS válida.");
      return;
    }

    const restore = setBusy(button);
    try {
      setText("#bds-install-status", `Instalando BDS ${version}...`);
      const data = await postJson("/api/bedrock/servers/download", { version });
      setText("#bds-install-status", data.message || "BDS instalado.");
      logLine("OK", data.message || `BDS ${version} instalado.`);
      await refreshInstalled();
      await refreshStatus();
    } catch (error) {
      setText("#bds-install-status", `Erro: ${error.message}`);
      alert(`Erro ao instalar BDS ${version}: ${error.message}`);
    } finally {
      restore();
    }
  }

  async function startServer(version, button) {
    const restore = setBusy(button);
    try {
      logLine("ACTION", `Iniciando BDS ${version}...`);
      const data = await postJson("/api/bedrock/servers/start", { version });
      logLine(data.ok ? "OK" : "ERROR", data.message || data.error || "Start concluído.");
      await refreshInstalled();
      await refreshStatus();
    } catch (error) {
      logLine("ERROR", `Iniciar BDS: ${error.message}`);
      alert(`Erro ao iniciar BDS: ${error.message}`);
    } finally {
      restore();
    }
  }

  async function stopServer(version, button) {
    const restore = setBusy(button);
    try {
      const payload = version ? { version } : {};
      logLine("ACTION", version ? `Parando BDS ${version}...` : "Parando BDS ativo...");
      const data = await postJson("/api/bedrock/servers/stop", payload);
      logLine(data.ok ? "OK" : "ERROR", data.message || data.error || "Stop concluído.");
      await refreshInstalled();
      await refreshStatus();
    } catch (error) {
      logLine("ERROR", `Parar BDS: ${error.message}`);
      alert(`Erro ao parar BDS: ${error.message}`);
    } finally {
      restore();
    }
  }

  async function restartServer(version, button) {
    const restore = setBusy(button);
    try {
      logLine("ACTION", `Reiniciando BDS ${version}...`);
      const data = await postJson("/api/bedrock/servers/restart", { version });
      logLine(data.ok ? "OK" : "ERROR", data.message || data.error || "Restart concluído.");
      await refreshInstalled();
      await refreshStatus();
    } catch (error) {
      logLine("ERROR", `Reiniciar BDS: ${error.message}`);
      alert(`Erro ao reiniciar BDS: ${error.message}`);
    } finally {
      restore();
    }
  }

  async function removeServer(version, button) {
    if (!confirm(`Remover BDS ${version}? Essa ação apagará a pasta da versão instalada.`)) return;

    const restore = setBusy(button, "Removendo...");
    try {
      logLine("ACTION", `Removendo BDS ${version}...`);
      const data = await postJson("/api/bedrock/servers/remove", { version });
      logLine(data.ok ? "OK" : "ERROR", data.message || data.error || "Remove concluído.");
      await refreshInstalled();
      await refreshStatus();
    } catch (error) {
      logLine("ERROR", `Remover BDS: ${error.message}`);
      alert(`Erro ao remover BDS: ${error.message}`);
    } finally {
      restore();
    }
  }

  async function showLogs(version) {
    try {
      const endpoint = version
        ? `/api/bedrock/servers/logs?version=${encodeURIComponent(version)}`
        : "/api/bedrock/servers/logs";

      const data = await getJson(endpoint);
      const logs = data.logs || [];
      if (!logs.length) {
        logLine("LOG", "Nenhum log BDS disponível.");
      } else {
        const display = $("#display-log");
        if (display) {
          display.textContent += `\n\n===== LOGS BDS ${version || ""} =====\n${logs.join("\n")}`;
          display.scrollTop = display.scrollHeight;
        }
      }
      activateTab("display");
    } catch (error) {
      logLine("ERROR", `Logs BDS: ${error.message}`);
      alert(`Erro ao ler logs BDS: ${error.message}`);
    }
  }

  async function refreshLogs() {
    try {
      const data = await getJson("/api/logs");
      const logs = data.logs || [];
      const display = $("#display-log");
      if (display && logs.length) {
        display.textContent = logs.join("\n");
        display.scrollTop = display.scrollHeight;
      }
    } catch (error) {
      logLine("ERROR", `Atualizar display: ${error.message}`);
    }
  }

  async function openProjectFolder(button) {
    const restore = setBusy(button);
    try {
      await postJson("/api/action", { action: "open_project_folder" });
      logLine("OK", "Solicitação para abrir pasta enviada.");
    } catch (error) {
      alert(`Erro ao abrir pasta: ${error.message}`);
    } finally {
      restore();
    }
  }

  function bindEvents() {
    $$(".tab-link").forEach((button) => {
      button.addEventListener("click", () => activateTab(button.dataset.tab));
    });

    $$("[data-tab-jump]").forEach((button) => {
      button.addEventListener("click", () => activateTab(button.dataset.tabJump));
    });

    $("#home-refresh-status")?.addEventListener("click", (event) => {
      const restore = setBusy(event.currentTarget, "Atualizando...");
      Promise.all([refreshStatus(), refreshInstalled()]).finally(restore);
    });

    $("#bds-refresh-status")?.addEventListener("click", (event) => {
      const restore = setBusy(event.currentTarget, "Atualizando...");
      Promise.all([refreshStatus(), refreshInstalled()]).finally(restore);
    });

    $("#bds-test-server")?.addEventListener("click", (event) => {
      const restore = setBusy(event.currentTarget, "Testando...");
      refreshStatus().finally(restore);
    });

    $("#bds-refresh-available")?.addEventListener("click", (event) => {
      const restore = setBusy(event.currentTarget, "Atualizando...");
      refreshAvailable().finally(restore);
    });

    $("#bds-install-selected")?.addEventListener("click", (event) => installSelected(event.currentTarget));
    $("#bds-install-latest")?.addEventListener("click", (event) => installLatest(event.currentTarget));
    $("#bds-install-manual")?.addEventListener("click", (event) => installManual(event.currentTarget));

    $("#bds-stop-active")?.addEventListener("click", (event) => stopServer("", event.currentTarget));
    $("#bds-show-logs")?.addEventListener("click", () => showLogs(""));
    $("#clear-display")?.addEventListener("click", () => {
      const display = $("#display-log");
      if (display) display.textContent = "[SYSTEM] Display limpo.";
      postJson("/api/action", { action: "clear_logs" }).catch(() => {});
    });
    $("#refresh-display")?.addEventListener("click", refreshLogs);
    $("#open-project-folder")?.addEventListener("click", (event) => openProjectFolder(event.currentTarget));

    document.addEventListener("click", (event) => {
      const start = event.target.closest("[data-bds-start]");
      if (start) return startServer(start.dataset.bdsStart, start);

      const stop = event.target.closest("[data-bds-stop]");
      if (stop) return stopServer(stop.dataset.bdsStop, stop);

      const restart = event.target.closest("[data-bds-restart]");
      if (restart) return restartServer(restart.dataset.bdsRestart, restart);

      const remove = event.target.closest("[data-bds-remove]");
      if (remove) return removeServer(remove.dataset.bdsRemove, remove);

      const logs = event.target.closest("[data-bds-logs]");
      if (logs) return showLogs(logs.dataset.bdsLogs);
    });
  }

  async function boot() {
    bindEvents();
    await Promise.allSettled([
      refreshAvailable(),
      refreshInstalled(),
      refreshStatus(),
      refreshLogs()
    ]);

    window.setInterval(refreshStatus, 15_000);
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
