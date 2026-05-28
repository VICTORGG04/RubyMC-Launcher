/* =========================================================
   RubyMC Bedrock Game Version UI Fix
   - Corrige opções [object Object] no seletor BDS
   - Adiciona seleção de versão do jogo Bedrock na aba Versões
   - Diferencia Cliente Bedrock de Servidor BDS
   - Permite instalar/remover BDS pela versão do jogo
   ========================================================= */
(() => {
  "use strict";

  const API = {
    bedrockCheck: "/api/bedrock/check",
    bdsAvailable: "/api/bedrock/servers/available",
    bdsInstalled: "/api/bedrock/servers/installed",
    bdsDownload: "/api/bedrock/servers/download",
    bdsStart: "/api/bedrock/servers/start",
    bdsStop: "/api/bedrock/servers/stop",
    bdsRemove: "/api/bedrock/servers/remove",
    openManager: "/api/bedrock/open-manager"
  };

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  function esc(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function time() {
    return new Date().toLocaleTimeString("pt-BR", { hour12: false });
  }

  function log(type, message) {
    const display = $("#display-log");
    if (!display) return;
    display.textContent += `\n[${time()}] ${String(type).padEnd(7)} ${message}`;
    display.scrollTop = display.scrollHeight;
  }

  async function safeJson(response, endpoint) {
    const text = await response.text();
    let data = null;

    if (text.trim()) {
      try {
        data = JSON.parse(text);
      } catch (error) {
        throw new Error(`JSON inválido em ${endpoint}: ${error.message}`);
      }
    }

    if (!response.ok || data?.ok === false) {
      throw new Error(data?.error || data?.message || `HTTP ${response.status}`);
    }

    return data || { ok: true };
  }

  async function getJson(endpoint) {
    const response = await fetch(endpoint, { headers: { Accept: "application/json" } });
    return safeJson(response, endpoint);
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
    return safeJson(response, endpoint);
  }

  function extractVersionFromUrl(url) {
    const match = String(url || "").match(/bedrock-server-([0-9]+(?:\.[0-9]+){2,3})\.zip/i);
    return match ? match[1] : "";
  }

  function normalizeBdsVersion(item) {
    if (typeof item === "string") {
      const version = extractVersionFromUrl(item) || item;
      return {
        version,
        label: `Minecraft Bedrock ${version}`,
        url: item.startsWith("http") ? item : "",
        channel: "stable",
        platform: "linux"
      };
    }

    if (!item || typeof item !== "object") return null;

    const url = item.url || item.download_url || item.href || "";
    const version =
      item.version ||
      item.id ||
      item.name ||
      item.label ||
      extractVersionFromUrl(url);

    if (!version) return null;

    const channel = item.channel || item.type || (String(url).toLowerCase().includes("preview") ? "preview" : "stable");
    const platform = item.platform || (String(url).includes("bin-linux") ? "linux" : "");
    const suffix = channel === "preview" ? " Preview" : "";

    return {
      version: String(version),
      label: `Minecraft Bedrock ${version}${suffix}`,
      url: String(url || ""),
      channel: String(channel || "stable"),
      platform: String(platform || "linux")
    };
  }

  function uniqueByVersion(items) {
    const seen = new Set();
    return items.filter((item) => {
      if (!item || !item.version || seen.has(item.version)) return false;
      seen.add(item.version);
      return true;
    });
  }

  function sortVersionsDesc(items) {
    return [...items].sort((a, b) => {
      const av = a.version.split(".").map((n) => Number(n) || 0);
      const bv = b.version.split(".").map((n) => Number(n) || 0);
      for (let i = 0; i < Math.max(av.length, bv.length); i += 1) {
        const diff = (bv[i] || 0) - (av[i] || 0);
        if (diff) return diff;
      }
      return 0;
    });
  }

  function optionHtml(item) {
    return `<option value="${esc(item.version)}" data-url="${esc(item.url)}" data-channel="${esc(item.channel)}">${esc(item.label)}</option>`;
  }

  function fillBdsSelect(select, stableItems, previewItems = []) {
    if (!select) return;

    const stable = sortVersionsDesc(uniqueByVersion(stableItems));
    const preview = sortVersionsDesc(uniqueByVersion(previewItems));

    if (!stable.length && !preview.length) {
      select.innerHTML = '<option value="">Nenhuma versão encontrada automaticamente</option>';
      select.disabled = false;
      return;
    }

    let html = "";
    if (stable.length) {
      html += `<optgroup label="Versões estáveis">${stable.map(optionHtml).join("")}</optgroup>`;
    }
    if (preview.length) {
      html += `<optgroup label="Preview">${preview.map(optionHtml).join("")}</optgroup>`;
    }

    select.innerHTML = html;
    select.disabled = false;
  }

  function ensureBedrockVersionsPanel() {
    const tab = $("#tab-versions");
    if (!tab) return null;

    let panel = $("#rubymc-bedrock-game-version-panel");
    if (panel) return panel;

    const host = $("#tab-versions .panel-copy") || $("#tab-versions .panel-grid") || tab;
    panel = document.createElement("section");
    panel.id = "rubymc-bedrock-game-version-panel";
    panel.className = "version-section rubymc-bedrock-game-card";
    panel.innerHTML = `
      <div class="rubymc-bedrock-game-header">
        <div>
          <span class="rubymc-bedrock-kicker">BEDROCK EDITION</span>
          <h3>Versões do Jogo Bedrock</h3>
          <p>Escolha a versão do jogo para jogar no cliente ou instale o BDS compatível com essa versão.</p>
        </div>
        <button class="btn btn-dark btn-sm" id="rubymc-bedrock-refresh-all">Atualizar</button>
      </div>

      <div class="rubymc-bedrock-game-grid">
        <article class="rubymc-bedrock-game-box">
          <h4>Cliente Bedrock</h4>
          <p class="rubymc-bedrock-note">Versões instaladas localmente pelo mcpelauncher.</p>
          <label for="rubymc-bedrock-client-version-select">Versão do jogo instalada</label>
          <select id="rubymc-bedrock-client-version-select">
            <option value="">Carregando...</option>
          </select>
          <div class="rubymc-bedrock-actions">
            <button class="btn btn-cyan btn-sm" id="rubymc-bedrock-use-client-version">Usar no launcher</button>
            <button class="btn btn-dark btn-sm" id="rubymc-bedrock-open-manager-inline">Abrir Gerenciador</button>
          </div>
          <small class="bedrock-hint">Para baixar cliente Bedrock, use o gerenciador mcpelauncher/Google Play ou importe APK.</small>
        </article>

        <article class="rubymc-bedrock-game-box">
          <h4>Servidor BDS compatível</h4>
          <p class="rubymc-bedrock-note">A versão abaixo é a versão do jogo Bedrock que o servidor BDS suporta.</p>
          <label for="rubymc-bedrock-bds-game-version-select">Versão do jogo para instalar no BDS</label>
          <select id="rubymc-bedrock-bds-game-version-select">
            <option value="">Carregando...</option>
          </select>
          <div class="rubymc-bedrock-manual-row">
            <input id="rubymc-bedrock-bds-manual-version" type="text" placeholder="Ex.: 1.21.101.1">
            <button class="btn btn-dark btn-sm" id="rubymc-bedrock-bds-download-manual">Baixar manual</button>
          </div>
          <div class="rubymc-bedrock-actions">
            <button class="btn btn-red btn-sm" id="rubymc-bedrock-bds-download-selected">Instalar BDS desta versão</button>
          </div>
          <p class="rubymc-bedrock-status" id="rubymc-bedrock-bds-download-status"></p>
        </article>
      </div>

      <div class="rubymc-bedrock-game-box rubymc-bedrock-installed-box">
        <div class="rubymc-bedrock-installed-head">
          <h4>Versões BDS instaladas</h4>
          <button class="btn btn-dark btn-sm" id="rubymc-bedrock-bds-refresh-installed">Recarregar</button>
        </div>
        <div id="rubymc-bedrock-bds-installed-list" class="rubymc-bedrock-bds-installed-list">
          Carregando...
        </div>
      </div>
    `;

    host.appendChild(panel);
    bindPanelButtons(panel);
    return panel;
  }

  function bindPanelButtons(panel) {
    $("#rubymc-bedrock-refresh-all", panel)?.addEventListener("click", refreshAll);
    $("#rubymc-bedrock-open-manager-inline", panel)?.addEventListener("click", openManager);
    $("#rubymc-bedrock-use-client-version", panel)?.addEventListener("click", useSelectedClientGameVersion);
    $("#rubymc-bedrock-bds-download-selected", panel)?.addEventListener("click", () => downloadSelectedBdsVersion("rubymc-bedrock-bds-game-version-select", "rubymc-bedrock-bds-download-status"));
    $("#rubymc-bedrock-bds-download-manual", panel)?.addEventListener("click", downloadManualBdsVersion);
    $("#rubymc-bedrock-bds-refresh-installed", panel)?.addEventListener("click", refreshInstalledBdsVersions);
  }

  async function loadClientGameVersions() {
    ensureBedrockVersionsPanel();

    const inlineSelect = $("#rubymc-bedrock-client-version-select");
    const launcherSelect = $("#bedrock-version");

    [inlineSelect, launcherSelect].filter(Boolean).forEach((select) => {
      select.innerHTML = '<option value="">Carregando...</option>';
      select.disabled = true;
    });

    try {
      const data = await getJson(API.bedrockCheck);
      const versions = Array.isArray(data.versions) ? data.versions : [];

      if (!versions.length) {
        [inlineSelect, launcherSelect].filter(Boolean).forEach((select) => {
          select.innerHTML = '<option value="">Nenhuma versão do cliente instalada</option>';
          select.disabled = false;
        });
        return;
      }

      const html = versions.map((version) => `<option value="${esc(version)}">Minecraft Bedrock ${esc(version)}</option>`).join("");

      [inlineSelect, launcherSelect].filter(Boolean).forEach((select) => {
        select.innerHTML = html;
        select.disabled = false;
      });
    } catch (error) {
      [inlineSelect, launcherSelect].filter(Boolean).forEach((select) => {
        select.innerHTML = '<option value="">Erro ao carregar versões do cliente</option>';
        select.disabled = false;
      });
      log("ERROR", `Versões cliente Bedrock: ${error.message}`);
    }
  }

  async function loadAvailableBdsGameVersions() {
    ensureBedrockVersionsPanel();

    const selects = [
      $("#rubymc-bedrock-bds-game-version-select"),
      $("#bedrock-server-version-select"),
      $("#bedrock-version-select")
    ].filter(Boolean);

    selects.forEach((select) => {
      select.innerHTML = '<option value="">Carregando versões do jogo...</option>';
      select.disabled = true;
    });

    try {
      const data = await getJson(API.bdsAvailable);
      const stable = (data.versions || []).map(normalizeBdsVersion).filter(Boolean);
      const preview = (data.preview_versions || []).map(normalizeBdsVersion).filter(Boolean);

      selects.forEach((select) => fillBdsSelect(select, stable, preview));

      const status = $("#rubymc-bedrock-bds-download-status") || $("#bedrock-server-download-status");
      if (status) {
        const total = stable.length + preview.length;
        status.textContent = total ? `${total} versão(ões) do jogo disponíveis para BDS.` : "Nenhuma versão automática encontrada. Use o campo manual.";
      }
    } catch (error) {
      selects.forEach((select) => {
        select.innerHTML = '<option value="">Erro ao carregar; use versão manual</option>';
        select.disabled = false;
      });
      const status = $("#rubymc-bedrock-bds-download-status") || $("#bedrock-server-download-status");
      if (status) status.textContent = `Erro ao carregar versões BDS: ${error.message}`;
      log("ERROR", `Versões BDS: ${error.message}`);
    }
  }

  function selectedBdsPayload(selectId) {
    const select = document.getElementById(selectId) || $("#rubymc-bedrock-bds-game-version-select") || $("#bedrock-server-version-select");
    if (!select || !select.value) return null;

    const option = select.selectedOptions?.[0];
    return {
      version: select.value,
      url: option?.dataset?.url || "",
      channel: option?.dataset?.channel || "stable"
    };
  }

  async function downloadSelectedBdsVersion(selectId, statusId) {
    const payload = selectedBdsPayload(selectId);
    const status = document.getElementById(statusId) || $("#rubymc-bedrock-bds-download-status") || $("#bedrock-server-download-status");

    if (!payload || !payload.version) {
      if (status) status.textContent = "Selecione uma versão do jogo Bedrock.";
      return;
    }

    await downloadBdsVersion(payload, status);
  }

  async function downloadManualBdsVersion() {
    const input = $("#rubymc-bedrock-bds-manual-version");
    const status = $("#rubymc-bedrock-bds-download-status");
    const version = input?.value?.trim();

    if (!version) {
      if (status) status.textContent = "Informe uma versão do jogo. Ex.: 1.21.101.1";
      return;
    }

    await downloadBdsVersion({ version }, status);
  }

  async function downloadBdsVersion(payload, status) {
    const version = payload.version;
    const buttons = [
      $("#bedrock-server-download"),
      $("#bedrock-version-install-btn"),
      $("#rubymc-bedrock-bds-download-selected"),
      $("#rubymc-bedrock-bds-download-manual")
    ].filter(Boolean);

    buttons.forEach((button) => {
      button.disabled = true;
      button.dataset.oldText = button.textContent;
      button.textContent = "Baixando...";
    });

    if (status) status.textContent = `Baixando BDS compatível com Minecraft Bedrock ${version}...`;
    log("ACTION", `Baixando BDS da versão do jogo Bedrock ${version}`);

    try {
      const data = await postJson(API.bdsDownload, payload);
      if (status) status.textContent = data.message || `BDS ${version} instalado.`;
      log("OK", data.message || `BDS ${version} instalado.`);
      await refreshInstalledBdsVersions();
      await loadAvailableBdsGameVersions();
      window.dispatchEvent(new CustomEvent("bedrock-versions-changed"));
    } catch (error) {
      if (status) status.textContent = `Erro: ${error.message}`;
      log("ERROR", `Download BDS ${version}: ${error.message}`);
    } finally {
      buttons.forEach((button) => {
        button.disabled = false;
        button.textContent = button.dataset.oldText || "Baixar";
      });
    }
  }

  async function refreshInstalledBdsVersions() {
    ensureBedrockVersionsPanel();

    const inlineList = $("#rubymc-bedrock-bds-installed-list");
    const originalList = $("#bedrock-version-installed-list");
    const homeList = $("#bedrock-server-list");

    [inlineList, originalList, homeList].filter(Boolean).forEach((list) => {
      list.innerHTML = '<span class="loading-dots">Carregando</span>';
    });

    try {
      const data = await getJson(API.bdsInstalled);
      const servers = Array.isArray(data.servers) ? data.servers : [];

      if (!servers.length) {
        const empty = '<span class="empty-state">Nenhuma versão BDS instalada.</span>';
        [inlineList, originalList, homeList].filter(Boolean).forEach((list) => { list.innerHTML = empty; });
        return;
      }

      const html = servers.map((server) => renderInstalledBdsItem(server)).join("");
      [inlineList, originalList, homeList].filter(Boolean).forEach((list) => { list.innerHTML = html; });

      updateBdsStatusFromServers(servers);
    } catch (error) {
      const err = `<span class="empty-state">Erro ao carregar BDS: ${esc(error.message)}</span>`;
      [inlineList, originalList, homeList].filter(Boolean).forEach((list) => { list.innerHTML = err; });
      log("ERROR", `BDS instalados: ${error.message}`);
    }
  }

  function renderInstalledBdsItem(server) {
    const version = server.version || server.id || "desconhecida";
    const running = Boolean(server.running);
    return `
      <div class="rubymc-bds-version-row ${running ? "is-running" : ""}">
        <div class="rubymc-bds-version-info">
          <span class="rubymc-bds-status ${running ? "running" : "stopped"}">${running ? "● Online" : "○ Parado"}</span>
          <strong>Minecraft Bedrock ${esc(version)}</strong>
          <small>BDS compatível · ${esc(server.channel || "stable")} ${server.pid ? `· PID ${esc(server.pid)}` : ""}</small>
        </div>
        <div class="rubymc-bds-version-actions">
          ${running
            ? `<button class="btn btn-red btn-sm" data-rubymc-bds-stop="${esc(version)}">Parar</button>`
            : `<button class="btn btn-cyan btn-sm" data-rubymc-bds-start="${esc(version)}">Iniciar</button>`
          }
          <button class="btn btn-dark btn-sm" data-rubymc-bds-remove="${esc(version)}">Remover</button>
        </div>
      </div>
    `;
  }

  function updateBdsStatusFromServers(servers) {
    const running = servers.find((server) => server.running);
    const statusDiv = $("#bedrock-server-status");
    const versionLabel = $("#bedrock-server-version-label");
    const pidLabel = $("#bedrock-server-pid-label");

    if (!statusDiv) return;

    if (!running) {
      statusDiv.style.display = "none";
      return;
    }

    statusDiv.style.display = "flex";
    if (versionLabel) versionLabel.textContent = `Minecraft Bedrock ${running.version || running.id}`;
    if (pidLabel) pidLabel.textContent = running.pid ? `PID ${running.pid}` : "";
  }

  async function startBds(version) {
    try {
      const data = await postJson(API.bdsStart, { version });
      log(data.ok === false ? "ERROR" : "OK", data.message || `BDS ${version} iniciado.`);
      await refreshInstalledBdsVersions();
    } catch (error) {
      alert("Erro ao iniciar BDS: " + error.message);
    }
  }

  async function stopBds(version = "") {
    try {
      const data = await postJson(API.bdsStop, version ? { version } : {});
      log(data.ok === false ? "ERROR" : "OK", data.message || `BDS ${version || "ativo"} parado.`);
      await refreshInstalledBdsVersions();
    } catch (error) {
      alert("Erro ao parar BDS: " + error.message);
    }
  }

  async function removeBds(version) {
    if (!confirm(`Remover a versão BDS compatível com Minecraft Bedrock ${version}?`)) return;

    try {
      const data = await postJson(API.bdsRemove, { version });
      log(data.ok === false ? "ERROR" : "OK", data.message || `BDS ${version} removido.`);
      await refreshInstalledBdsVersions();
      await loadAvailableBdsGameVersions();
    } catch (error) {
      alert("Erro ao remover BDS: " + error.message);
    }
  }

  async function openManager() {
    try {
      const data = await postJson(API.openManager, {});
      log(data.ok === false ? "ERROR" : "OK", data.message || "Gerenciador Bedrock aberto.");
    } catch (error) {
      alert("Erro ao abrir gerenciador Bedrock: " + error.message);
    }
  }

  function useSelectedClientGameVersion() {
    const inline = $("#rubymc-bedrock-client-version-select");
    const launcher = $("#bedrock-version");
    if (!inline || !launcher || !inline.value) return;
    launcher.value = inline.value;
    log("OK", `Versão do jogo Bedrock selecionada: ${inline.value}`);
  }

  function interceptClicks() {
    document.addEventListener("click", (event) => {
      const installBtn = event.target.closest("#bedrock-server-download, #bedrock-version-install-btn, #rubymc-bedrock-bds-download-selected");
      if (installBtn) {
        event.preventDefault();
        event.stopImmediatePropagation();
        const selectId = installBtn.id === "bedrock-version-install-btn" ? "bedrock-version-select" :
          installBtn.id === "bedrock-server-download" ? "bedrock-server-version-select" :
          "rubymc-bedrock-bds-game-version-select";
        const statusId = installBtn.id === "bedrock-server-download" ? "bedrock-server-download-status" : "rubymc-bedrock-bds-download-status";
        downloadSelectedBdsVersion(selectId, statusId);
        return;
      }

      const startBtn = event.target.closest("[data-rubymc-bds-start], [data-bedrock-server-start-version]");
      if (startBtn) {
        event.preventDefault();
        event.stopImmediatePropagation();
        startBds(startBtn.dataset.rubymcBdsStart || startBtn.dataset.bedrockServerStartVersion);
        return;
      }

      const stopBtn = event.target.closest("[data-rubymc-bds-stop], [data-bedrock-server-stop-version], #bedrock-server-stop");
      if (stopBtn) {
        event.preventDefault();
        event.stopImmediatePropagation();
        stopBds(stopBtn.dataset.rubymcBdsStop || stopBtn.dataset.bedrockServerStopVersion || "");
        return;
      }

      const removeBtn = event.target.closest("[data-rubymc-bds-remove], [data-bedrock-version-remove]");
      if (removeBtn) {
        event.preventDefault();
        event.stopImmediatePropagation();
        removeBds(removeBtn.dataset.rubymcBdsRemove || removeBtn.dataset.bedrockVersionRemove);
      }
    }, true);
  }

  async function refreshAll() {
    ensureBedrockVersionsPanel();
    await Promise.allSettled([
      loadClientGameVersions(),
      loadAvailableBdsGameVersions(),
      refreshInstalledBdsVersions()
    ]);
  }

  function init() {
    ensureBedrockVersionsPanel();
    interceptClicks();

    const versionsTab = document.querySelector('[data-tab="versions"]');
    if (versionsTab) {
      versionsTab.addEventListener("click", () => setTimeout(refreshAll, 150));
    }

    setTimeout(refreshAll, 200);
    setTimeout(refreshAll, 900);

    window.addEventListener("bedrock-versions-changed", () => {
      setTimeout(refreshAll, 150);
    });

    window.RubyMCBedrockGameVersionFix = { refresh: refreshAll };
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
