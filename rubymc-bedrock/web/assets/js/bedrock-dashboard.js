/* =========================================================
   RubyMC Bedrock Dashboard Final
   Corrige a interface para Bedrock-only e trata versões do jogo.
   ========================================================= */
(() => {
  "use strict";

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  const API = {
    clientCheck: "/api/bedrock/check",
    clientVersions: "/api/bedrock/client/versions",
    clientRemove: "/api/bedrock/client/remove",
    bdsAvailable: "/api/bedrock/servers/available",
    bdsInstalled: "/api/bedrock/servers/installed",
    bdsDownload: "/api/bedrock/servers/download",
    bdsStart: "/api/bedrock/servers/start",
    bdsStop: "/api/bedrock/servers/stop",
    bdsRemove: "/api/bedrock/servers/remove",
    bdsRestart: "/api/bedrock/servers/restart",
    bdsStatus: "/api/bedrock/servers/status",
    openManager: "/api/bedrock/open-manager"
  };

  function esc(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  async function safeJson(response, endpoint) {
    const text = await response.text();
    let data = {};
    if (text.trim()) {
      try { data = JSON.parse(text); }
      catch (error) { throw new Error(`JSON inválido em ${endpoint}: ${error.message}`); }
    }
    if (!response.ok || data.ok === false) {
      throw new Error(data.error || data.message || `HTTP ${response.status}`);
    }
    return data;
  }

  async function getJson(endpoint) {
    return safeJson(await fetch(endpoint, { headers: { Accept: "application/json" } }), endpoint);
  }

  async function postJson(endpoint, payload = {}) {
    return safeJson(await fetch(endpoint, {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    }), endpoint);
  }

  function versionSort(a, b) {
    const av = String(a.version || a).split(".").map((n) => Number(n) || 0);
    const bv = String(b.version || b).split(".").map((n) => Number(n) || 0);
    for (let i = 0; i < Math.max(av.length, bv.length); i += 1) {
      const diff = (bv[i] || 0) - (av[i] || 0);
      if (diff) return diff;
    }
    return 0;
  }

  function extractVersionFromUrl(url) {
    const match = String(url || "").match(/bedrock-server-([0-9]+(?:\.[0-9]+){2,3})\.zip/i);
    return match ? match[1] : "";
  }

  function normalizeBds(item) {
    if (typeof item === "string") {
      return { version: extractVersionFromUrl(item) || item, url: item.startsWith("http") ? item : "", channel: "stable", platform: "linux" };
    }
    if (!item || typeof item !== "object") return null;
    const url = item.url || item.download_url || item.href || "";
    const version = item.version || item.id || item.name || extractVersionFromUrl(url);
    if (!version) return null;
    return {
      version: String(version),
      url: String(url || ""),
      channel: String(item.channel || (String(url).includes("preview") ? "preview" : "stable")),
      platform: String(item.platform || (String(url).includes("bin-linux") ? "linux" : "linux"))
    };
  }

  function unique(items) {
    const seen = new Set();
    return items.filter((item) => {
      if (!item || !item.version || seen.has(item.version)) return false;
      seen.add(item.version);
      return true;
    });
  }

  function fillBdsSelects(stable, preview = []) {
    const stableItems = unique(stable.map(normalizeBds).filter(Boolean)).sort(versionSort);
    const previewItems = unique(preview.map(normalizeBds).filter(Boolean)).sort(versionSort);
    const selects = ["#bedrock-server-version-select", "#bedrock-version-select", "#rubymc-bedrock-bds-game-version-select"]
      .map((id) => $(id)).filter(Boolean);

    for (const select of selects) {
      if (!stableItems.length && !previewItems.length) {
        select.innerHTML = '<option value="">Nenhuma versão do jogo encontrada</option>';
        select.disabled = true;
        continue;
      }
      let html = "";
      if (stableItems.length) {
        html += `<optgroup label="Versões estáveis do jogo">${stableItems.map((item) => `<option value="${esc(item.version)}" data-url="${esc(item.url)}" data-channel="${esc(item.channel)}">Minecraft Bedrock ${esc(item.version)}</option>`).join("")}</optgroup>`;
      }
      if (previewItems.length) {
        html += `<optgroup label="Preview">${previewItems.map((item) => `<option value="${esc(item.version)}" data-url="${esc(item.url)}" data-channel="preview">Minecraft Bedrock ${esc(item.version)} Preview</option>`).join("")}</optgroup>`;
      }
      select.innerHTML = html;
      select.disabled = false;
    }
  }

  async function refreshAvailableBds() {
    const selects = ["#bedrock-server-version-select", "#bedrock-version-select"].map((id) => $(id)).filter(Boolean);
    selects.forEach((select) => { select.innerHTML = '<option value="">Carregando versões do jogo...</option>'; });
    try {
      const data = await getJson(API.bdsAvailable);
      fillBdsSelects(data.versions || [], data.preview_versions || []);
    } catch (error) {
      selects.forEach((select) => { select.innerHTML = `<option value="">Erro ao carregar: ${esc(error.message)}</option>`; });
    }
  }

  async function refreshClientVersions() {
    const mainSelect = $("#bedrock-version");
    const lists = [$("#bedrock-client-version-list"), $("#bedrock-client-version-list-secondary")].filter(Boolean);

    try {
      let data;
      try { data = await getJson(API.clientVersions); }
      catch (_) { data = await getJson(API.clientCheck); }

      const versions = [...new Set((data.versions || []).map(String))].sort((a, b) => versionSort({ version: a }, { version: b }));
      const status = $("#bedrock-client-status") || $("#bedrock-status");

      if (mainSelect) {
        if (versions.length) {
          mainSelect.innerHTML = versions.map((version) => `<option value="${esc(version)}">Minecraft Bedrock ${esc(version)}</option>`).join("");
          mainSelect.disabled = false;
          $("#active-profile") && ($("#active-profile").textContent = versions[0]);
        } else {
          mainSelect.innerHTML = '<option value="">Nenhuma versão do jogo instalada</option>';
        }
      }

      lists.forEach((list) => {
        if (!versions.length) {
          list.innerHTML = '<span class="empty-state">Nenhuma versão do jogo instalada. Abra o gerenciador para instalar uma versão pelo Google Play.</span>';
          return;
        }
        list.innerHTML = versions.map((version) => `
          <div class="bedrock-client-version-row">
            <div><strong>Minecraft Bedrock ${esc(version)}</strong><small>Cliente local mcpelauncher</small></div>
            <div class="bedrock-client-version-actions">
              <button class="btn btn-cyan btn-sm" data-bedrock-use-client-version="${esc(version)}">Usar</button>
            </div>
          </div>
        `).join("");
      });

      if (status) status.textContent = data.installed ? "mcpelauncher detectado." : "mcpelauncher não detectado.";
    } catch (error) {
      lists.forEach((list) => { list.innerHTML = `<span class="empty-state">Erro: ${esc(error.message)}</span>`; });
    }
  }

  async function refreshInstalledBds() {
    const list = $("#bedrock-version-installed-list");
    const homeList = $("#bedrock-server-list");
    try {
      const data = await getJson(API.bdsInstalled);
      const servers = data.servers || [];
      const html = servers.length ? servers.map((server) => `
        <div class="bedrock-version-item ${server.running ? "is-running" : ""}">
          <span class="bedrock-version-item-info">
            <span class="bedrock-version-item-status ${server.running ? "running" : "stopped"}">${server.running ? "● Online" : "○ Parado"}</span>
            <strong>Minecraft Bedrock ${esc(server.version)}</strong>
            <small>BDS compatível com a versão do jogo ${esc(server.version)}</small>
            ${server.pid ? `<span class="bedrock-version-item-pid">PID ${esc(server.pid)}</span>` : ""}
          </span>
          <span class="bedrock-version-item-actions">
            ${server.running ? `<button class="btn btn-red btn-sm" data-bedrock-server-stop-version="${esc(server.version)}">Parar</button>` : `<button class="btn btn-cyan btn-sm" data-bedrock-server-start-version="${esc(server.version)}">Iniciar</button>`}
            <button class="btn btn-dark btn-sm" data-bedrock-version-remove="${esc(server.version)}">Remover</button>
          </span>
        </div>
      `).join("") : '<span class="empty-state">Nenhuma versão BDS instalada.</span>';

      if (list) list.innerHTML = html;
      if (homeList) homeList.innerHTML = html;
      renderActiveBds(servers);
    } catch (error) {
      if (list) list.innerHTML = `<span class="empty-state">Erro: ${esc(error.message)}</span>`;
      if (homeList) homeList.innerHTML = `<small class="bedrock-hint">Erro: ${esc(error.message)}</small>`;
    }
  }

  function renderActiveBds(servers) {
    const detail = $("#bedrock-version-active-detail");
    if (!detail) return;
    const running = servers.find((s) => s.running);
    if (!running) {
      detail.innerHTML = '<div class="bedrock-version-active-none">Nenhum BDS rodando.</div>';
      return;
    }
    detail.innerHTML = `
      <div class="bedrock-version-active-card">
        <span class="bedrock-version-active-badge online">● Rodando</span>
        <span class="bedrock-version-active-version">Minecraft Bedrock ${esc(running.version)}</span>
        ${running.pid ? `<span class="bedrock-version-active-pid">PID ${esc(running.pid)}</span>` : ""}
      </div>
    `;
  }

  async function installSelectedBds(button, selectId = "bedrock-server-version-select", statusId = "bedrock-server-download-status") {
    const select = $("#" + selectId);
    const status = $("#" + statusId);
    const option = select?.selectedOptions?.[0];
    const version = select?.value || "";
    if (!version) {
      if (status) status.textContent = "Nenhuma versão oficial carregada. Use a instalação manual apenas com uma versão BDS válida.";
      alert("Nenhuma versão oficial carregada. Use a instalação manual apenas se souber uma versão BDS válida.");
      return;
    }
    const oldText = button.textContent;
    button.disabled = true;
    button.textContent = "Instalando...";
    if (status) status.textContent = `Baixando BDS compatível com Minecraft Bedrock ${version}...`;
    try {
      const payload = { version };
      if (option?.dataset?.url) payload.url = option.dataset.url;
      if (option?.dataset?.channel) payload.channel = option.dataset.channel;
      const data = await postJson(API.bdsDownload, payload);
      if (status) status.textContent = data.message || `BDS ${version} instalado.`;
      await refreshInstalledBds();
    } catch (error) {
      if (status) status.textContent = "Erro: " + error.message;
      alert("Erro ao instalar BDS: " + error.message);
    } finally {
      button.disabled = false;
      button.textContent = oldText;
    }
  }

  function bindDashboardEvents() {
    $("#bedrock-client-refresh")?.addEventListener("click", refreshClientVersions);
    $("#bedrock-manual-download")?.addEventListener("click", async () => {
      const input = $("#bedrock-manual-game-version");
      const version = input?.value?.trim();
      const status = $("#bedrock-server-download-status");
      if (!version) return alert("Informe a versão do jogo Bedrock. Ex.: 1.21.101.1");
      if (status) status.textContent = `Baixando BDS compatível com Minecraft Bedrock ${version}...`;
      try {
        const data = await postJson(API.bdsDownload, { version });
        if (status) status.textContent = data.message || "Instalado.";
        await refreshInstalledBds();
      } catch (error) {
        if (status) status.textContent = "Erro: " + error.message;
      }
    });

    document.addEventListener("click", async (event) => {
      const useClient = event.target.closest("[data-bedrock-use-client-version]");
      if (useClient) {
        const version = useClient.dataset.bedrockUseClientVersion;
        const select = $("#bedrock-version");
        if (select) select.value = version;
        $("#active-profile") && ($("#active-profile").textContent = version);
        return;
      }
    }, true);

    const downloadButton = $("#bedrock-server-download");
    if (downloadButton) {
      downloadButton.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopImmediatePropagation();
        installSelectedBds(downloadButton);
      }, true);
    }
  }

  async function refreshAllBedrock() {
    await Promise.allSettled([refreshClientVersions(), refreshAvailableBds(), refreshInstalledBds()]);
  }

  document.addEventListener("DOMContentLoaded", () => {
    bindDashboardEvents();
    setTimeout(refreshAllBedrock, 150);
    setTimeout(refreshAvailableBds, 900);
    window.addEventListener("bedrock-versions-changed", refreshAllBedrock);
    $$('[data-tab="versions"], [data-tab="client"], [data-tab="server"]').forEach((btn) => {
      btn.addEventListener("click", () => setTimeout(refreshAllBedrock, 180));
    });
  });
})();
