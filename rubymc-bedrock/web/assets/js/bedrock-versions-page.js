/* =========================================================
   RubyMC Bedrock Versions Page
   Adiciona downloads/gerenciamento Bedrock na aba Versões.

   Usa endpoints existentes:
   - GET  /api/bedrock/check
   - POST /api/bedrock/open-manager
   - POST /api/bedrock/import-apk
   - GET  /api/bedrock/servers/available
   - POST /api/bedrock/servers/download
   - GET  /api/bedrock/servers/installed
   ========================================================= */
(() => {
  "use strict";

  let injected = false;
  let clientLoading = false;
  let serverLoading = false;

  function injectPanel() {
    if (injected || $("#bedrock-versions-page")) {
      injected = true;
      return;
    }

    const container = $("#tab-versions .panel-copy");
    if (!container) return;

    const panel = document.createElement("div");
    panel.id = "bedrock-versions-page";
    panel.className = "version-section bedrock-versions-page";
    panel.innerHTML = `
      <div class="bedrock-versions-header">
        <div>
          <span class="cyan-label">BEDROCK EDITION</span>
          <h3>Versões Bedrock</h3>
          <p>Gerencie versões do cliente Bedrock via mcpelauncher e baixe servidores Bedrock Dedicated Server diretamente pela aba Versões.</p>
        </div>
        <button class="btn btn-dark btn-sm" id="bedrock-page-refresh-all">Atualizar Bedrock</button>
      </div>

      <div class="bedrock-page-tabs" role="tablist" aria-label="Gerenciamento Bedrock">
        <button class="bedrock-page-tab active" type="button" data-bedrock-page-mode="client">Cliente Bedrock</button>
        <button class="bedrock-page-tab" type="button" data-bedrock-page-mode="server">Servidor BDS</button>
      </div>

      <div class="bedrock-page-panel active" data-bedrock-page-panel="client">
        <div class="bedrock-page-grid">
          <div class="bedrock-page-card">
            <h4>Cliente Bedrock instalado</h4>
            <p class="bedrock-page-hint">As versões do cliente são detectadas pelo mcpelauncher. Para baixar via Google Play, use o gerenciador.</p>
            <div class="field-box">
              <small>Versões detectadas</small>
              <select id="bedrock-page-client-version-select" disabled>
                <option>Carregando...</option>
              </select>
            </div>
            <div class="actions compact-actions">
              <button class="btn btn-cyan btn-sm" id="bedrock-page-open-manager">Abrir Gerenciador</button>
              <button class="btn btn-dark btn-sm" id="bedrock-page-refresh-client">Atualizar cliente</button>
            </div>
            <p class="bedrock-page-status" id="bedrock-page-client-status">Aguardando verificação...</p>
          </div>

          <div class="bedrock-page-card">
            <h4>Importar APK</h4>
            <p class="bedrock-page-hint">Use quando você já possui um APK compatível. Requer <code>mcpelauncher-extract</code> no PATH.</p>
            <input type="file" id="bedrock-page-apk-input" accept=".apk" class="bedrock-page-file">
            <div class="actions compact-actions">
              <button class="btn btn-dark btn-sm" id="bedrock-page-apk-import">Extrair versão</button>
            </div>
            <p class="bedrock-page-status" id="bedrock-page-apk-status"></p>
          </div>
        </div>
      </div>

      <div class="bedrock-page-panel" data-bedrock-page-panel="server">
        <div class="bedrock-page-grid">
          <div class="bedrock-page-card">
            <h4>Baixar servidor Bedrock</h4>
            <p class="bedrock-page-hint">Baixa versões do Bedrock Dedicated Server para iniciar depois pela Página Servidor.</p>
            <div class="bedrock-download-row">
              <div class="field-box">
                <small>Versão disponível</small>
                <select id="bedrock-page-bds-available" disabled>
                  <option>Carregando...</option>
                </select>
              </div>
              <button class="btn btn-cyan btn-sm" id="bedrock-page-bds-download" disabled>Baixar BDS</button>
            </div>
            <div class="actions compact-actions">
              <button class="btn btn-dark btn-sm" id="bedrock-page-refresh-bds">Atualizar lista</button>
            </div>
            <p class="bedrock-page-status" id="bedrock-page-bds-download-status"></p>
          </div>

          <div class="bedrock-page-card">
            <h4>Servidores Bedrock instalados</h4>
            <p class="bedrock-page-hint">Essas versões aparecem no seletor Bedrock da Página Servidor.</p>
            <div id="bedrock-page-bds-installed-list" class="bedrock-page-list">
              <span class="loading-dots">Carregando</span>
            </div>
          </div>
        </div>
      </div>
    `;

    container.appendChild(panel);
    bindPanelEvents();
    injected = true;
  }

  function bindPanelEvents() {
    $$("#bedrock-versions-page [data-bedrock-page-mode]").forEach((button) => {
      button.addEventListener("click", () => setMode(button.dataset.bedrockPageMode));
    });

    $("#bedrock-page-refresh-all")?.addEventListener("click", refreshAll);
    $("#bedrock-page-refresh-client")?.addEventListener("click", loadClientVersions);
    $("#bedrock-page-open-manager")?.addEventListener("click", () => openManager($("#bedrock-page-open-manager")));
    $("#bedrock-page-apk-import")?.addEventListener("click", () => importApk($("#bedrock-page-apk-import")));
    $("#bedrock-page-refresh-bds")?.addEventListener("click", refreshBds);
    $("#bedrock-page-bds-download")?.addEventListener("click", () => downloadBds($("#bedrock-page-bds-download")));
  }

  function setMode(mode) {
    $$("#bedrock-versions-page [data-bedrock-page-mode]").forEach((button) => {
      button.classList.toggle("active", button.dataset.bedrockPageMode === mode);
    });

    $$("#bedrock-versions-page [data-bedrock-page-panel]").forEach((panel) => {
      panel.classList.toggle("active", panel.dataset.bedrockPagePanel === mode);
    });

    if (mode === "client") loadClientVersions();
    if (mode === "server") refreshBds();
  }

  async function loadClientVersions() {
    if (clientLoading) return;
    clientLoading = true;

    const select = $("#bedrock-page-client-version-select");
    const status = $("#bedrock-page-client-status");

    if (select) {
      select.disabled = true;
      select.innerHTML = "<option>Carregando...</option>";
    }

    if (status) status.textContent = "Verificando mcpelauncher...";

    try {
      const data = await apiFetch("/api/bedrock/check");
      if (!data.ok) throw new Error(data.error || "Falha ao verificar Bedrock");

      if (!data.installed) {
        if (select) select.innerHTML = '<option value="">mcpelauncher não detectado</option>';
        if (status) status.textContent = "mcpelauncher não detectado. Instale via Flatpak ou use o gerenciador quando disponível.";
        return;
      }

      const versions = Array.isArray(data.versions) ? data.versions : [];
      if (!versions.length) {
        if (select) select.innerHTML = '<option value="">Nenhuma versão detectada</option>';
        if (status) status.textContent = "mcpelauncher detectado, mas nenhuma versão Bedrock foi encontrada.";
        return;
      }

      if (select) {
        select.innerHTML = versions.map((version) => `<option value="${esc(version)}">${esc(version)}</option>`).join("");
        select.disabled = false;
      }

      if (status) status.textContent = `${versions.length} versão(ões) Bedrock detectada(s).`;
      log("OK", `Bedrock cliente: ${versions.length} versão(ões) detectada(s).`);
    } catch (error) {
      if (select) select.innerHTML = '<option value="">Erro ao carregar</option>';
      if (status) status.textContent = "Erro: " + error.message;
      log("ERROR", "Bedrock cliente: " + error.message);
    } finally {
      clientLoading = false;
    }
  }

  async function openManager(button) {
    setBusy(button, true, "Abrir Gerenciador");
    setText("#bedrock-page-client-status", "Abrindo gerenciador do mcpelauncher...");

    try {
      const data = await apiFetch("/api/bedrock/open-manager", { method: "POST" });
      if (!data.ok) throw new Error(data.error || data.message || "Falha ao abrir gerenciador");

      setText("#bedrock-page-client-status", data.message || "Gerenciador aberto.");
      log("OK", "Gerenciador Bedrock aberto.");
    } catch (error) {
      setText("#bedrock-page-client-status", "Erro: " + error.message);
      log("ERROR", "Gerenciador Bedrock: " + error.message);
    } finally {
      setBusy(button, false, "Abrir Gerenciador");
    }
  }

  async function importApk(button) {
    const input = $("#bedrock-page-apk-input");
    const status = $("#bedrock-page-apk-status");
    const file = input?.files?.[0];

    if (!file) {
      if (status) status.textContent = "Selecione um arquivo .apk primeiro.";
      return;
    }

    setBusy(button, true, "Extrair versão");
    if (status) status.textContent = "Extraindo versão do APK...";

    try {
      const formData = new FormData();
      formData.append("apk", file, file.name);

      const data = await apiFetch("/api/bedrock/import-apk", {
        method: "POST",
        body: formData
      });

      if (!data.ok) throw new Error(data.error || data.message || "Falha ao importar APK");

      if (status) status.textContent = data.message || "Versão extraída com sucesso.";
      if (input) input.value = "";

      log("OK", "APK Bedrock importado com sucesso.");
      window.dispatchEvent(new CustomEvent("bedrock-versions-changed"));
      setTimeout(loadClientVersions, 600);
    } catch (error) {
      if (status) status.textContent = "Erro: " + error.message;
      log("ERROR", "Importar APK Bedrock: " + error.message);
    } finally {
      setBusy(button, false, "Extrair versão");
    }
  }

  async function loadBdsAvailable() {
    const select = $("#bedrock-page-bds-available");
    const button = $("#bedrock-page-bds-download");
    const status = $("#bedrock-page-bds-download-status");

    if (select) {
      select.disabled = true;
      select.innerHTML = "<option>Carregando...</option>";
    }
    if (button) button.disabled = true;

    try {
      const data = await apiFetch("/api/bedrock/servers/available");
      if (!data.ok) throw new Error(data.error || "Falha ao listar versões BDS");

      const versions = Array.isArray(data.versions) ? data.versions : [];
      const preview = Array.isArray(data.preview_versions) ? data.preview_versions : [];

      if (!versions.length && !preview.length) {
        if (select) select.innerHTML = '<option value="">Nenhuma versão disponível</option>';
        if (status) status.textContent = "Nenhuma versão Bedrock Server disponível no backend.";
        return;
      }

      if (select) {
        const toOption = (v) => {
          const label = typeof v === "string" ? v : `${v.version}${v.channel === "preview" ? " (Preview)" : ""}`;
          const val = typeof v === "string" ? v : v.version;
          return `<option value="${esc(val)}">${esc(label)}</option>`;
        };
        const releaseOptions = versions.map(toOption).join("");
        select.innerHTML = releaseOptions;

        if (preview.length) {
          const optgroup = document.createElement("optgroup");
          optgroup.label = "Preview";
          preview.forEach((v) => {
            const option = document.createElement("option");
            const val = typeof v === "string" ? v : v.version;
            option.value = val;
            option.textContent = `${val} (preview)`;
            optgroup.appendChild(option);
          });
          select.appendChild(optgroup);
        }

        select.disabled = false;
      }

      if (button) button.disabled = false;
      if (status) status.textContent = `${versions.length + preview.length} versão(ões) BDS disponível(is).`;
    } catch (error) {
      if (select) select.innerHTML = '<option value="">Erro ao carregar</option>';
      if (status) status.textContent = "Erro: " + error.message;
      log("ERROR", "Versões BDS disponíveis: " + error.message);
    }
  }

  async function loadBdsInstalled() {
    const list = $("#bedrock-page-bds-installed-list");
    if (!list) return;

    list.innerHTML = '<span class="loading-dots">Carregando</span>';

    try {
      const data = await apiFetch("/api/bedrock/servers/installed");
      if (!data.ok) throw new Error(data.error || "Falha ao carregar servidores instalados");

      const servers = Array.isArray(data.servers) ? data.servers : [];
      if (!servers.length) {
        list.innerHTML = '<span class="empty-state">Nenhum servidor Bedrock instalado ainda.</span>';
        return;
      }

      list.innerHTML = servers.map((server) => {
        const version = server.version || server.id || "desconhecida";
        const running = server.running === true;
        const pid = server.pid ? `PID ${esc(server.pid)}` : "";

        return `
          <div class="bedrock-page-installed-item ${running ? "is-running" : ""}">
            <div>
              <strong>${esc(version)}</strong>
              <small>${running ? "● Rodando" : "○ Instalada"}${pid ? " · " + pid : ""}</small>
            </div>
            <span class="bedrock-page-badge">BDS</span>
          </div>
        `;
      }).join("");
    } catch (error) {
      list.innerHTML = `<span class="empty-state">Erro: ${esc(error.message)}</span>`;
      log("ERROR", "Servidores BDS instalados: " + error.message);
    }
  }

  async function refreshBds() {
    if (serverLoading) return;
    serverLoading = true;

    try {
      await Promise.all([loadBdsAvailable(), loadBdsInstalled()]);
    } finally {
      serverLoading = false;
    }
  }

  async function downloadBds(button) {
    const select = $("#bedrock-page-bds-available");
    const status = $("#bedrock-page-bds-download-status");
    const version = select?.value;

    if (!version) {
      if (status) status.textContent = "Selecione uma versão Bedrock Server.";
      return;
    }

    setBusy(button, true, "Baixar BDS");
    if (status) status.textContent = `Baixando Bedrock Dedicated Server ${version}...`;
    log("ACTION", `Baixando BDS ${version}...`);

    try {
      const data = await apiPost("/api/bedrock/servers/download", { version });
      if (!data.ok) throw new Error(data.error || data.message || "Download falhou");

      if (status) status.textContent = data.message || `Servidor Bedrock ${version} instalado com sucesso.`;
      log("OK", `Servidor Bedrock ${version} instalado.`);

      await loadBdsInstalled();
      await loadBdsAvailable();
      window.dispatchEvent(new CustomEvent("bedrock-servers-changed", { detail: { version } }));
      window.dispatchEvent(new CustomEvent("bedrock-versions-changed", { detail: { version } }));
    } catch (error) {
      if (status) status.textContent = "Erro: " + error.message;
      log("ERROR", `Download BDS ${version}: ${error.message}`);
    } finally {
      setBusy(button, false, "Baixar BDS");
    }
  }

  async function refreshAll() {
    const button = $("#bedrock-page-refresh-all");
    setBusy(button, true, "Atualizar Bedrock");

    try {
      await Promise.all([loadClientVersions(), refreshBds()]);
    } finally {
      setBusy(button, false, "Atualizar Bedrock");
    }
  }

  function init() {
    injectPanel();
    if (!injected) return;

    loadClientVersions();
    refreshBds();

    window.addEventListener("bedrock-versions-changed", () => {
      loadClientVersions();
      loadBdsInstalled();
    });

    window.addEventListener("bedrock-servers-changed", () => {
      loadBdsInstalled();
    });

    $$("[data-tab='versions']").forEach((button) => {
      button.addEventListener("click", () => setTimeout(refreshAll, 250));
    });
  }

  document.addEventListener("DOMContentLoaded", init);
})();
