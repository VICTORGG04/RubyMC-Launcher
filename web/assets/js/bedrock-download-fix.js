(() => {
  "use strict";

  function findVersionsHost() {
    const tab = $("#tab-versions");
    if (!tab) return null;
    return $("#tab-versions .panel-copy") || $("#tab-versions .version-section")?.parentElement || tab;
  }

  function ensurePanel() {
    if ($("#rubymc-bedrock-download-fix")) return $("#rubymc-bedrock-download-fix");

    const host = findVersionsHost();
    if (!host) return null;

    const section = document.createElement("section");
    section.id = "rubymc-bedrock-download-fix";
    section.className = "rubymc-bds-fix-card";
    section.innerHTML = `
      <div class="rubymc-bds-fix-header">
        <div>
          <span class="rubymc-bds-kicker">BEDROCK EDITION</span>
          <h3>Download do Servidor Bedrock BDS</h3>
          <p>Baixe o Bedrock Dedicated Server oficial para Linux. Para o cliente Bedrock, use o gerenciador mcpelauncher ou importação de APK.</p>
        </div>
        <button class="btn btn-dark btn-sm" id="bds-fix-refresh">Atualizar</button>
      </div>

      <div class="rubymc-bds-fix-grid">
        <div class="rubymc-bds-fix-box">
          <h4>Baixar versão oficial</h4>
          <label for="bds-fix-version-select">Versão encontrada</label>
          <select id="bds-fix-version-select"><option value="">Carregando...</option></select>
          <div class="rubymc-bds-fix-actions">
            <button class="btn btn-cyan btn-sm" id="bds-fix-download-selected">Baixar selecionada</button>
            <button class="btn btn-dark btn-sm" id="bds-fix-download-latest">Baixar mais recente</button>
          </div>
          <p class="rubymc-bds-fix-status" id="bds-fix-available-status"></p>
        </div>

        <div class="rubymc-bds-fix-box">
          <h4>Baixar por versão manual</h4>
          <p class="rubymc-bds-note">Use quando a página oficial não listar corretamente. Exemplo: <code>1.21.101.1</code></p>
          <label for="bds-fix-manual-version">Versão BDS</label>
          <input id="bds-fix-manual-version" type="text" placeholder="Ex.: 1.21.101.1">
          <button class="btn btn-red btn-sm" id="bds-fix-download-manual">Baixar versão manual</button>
          <p class="rubymc-bds-fix-status" id="bds-fix-download-status"></p>
        </div>
      </div>

      <div class="rubymc-bds-fix-box rubymc-bds-installed-box">
        <div class="rubymc-bds-installed-head">
          <h4>Servidores Bedrock instalados</h4>
          <button class="btn btn-dark btn-sm" id="bds-fix-installed-refresh">Recarregar</button>
        </div>
        <div id="bds-fix-installed-list" class="rubymc-bds-installed-list">Carregando...</div>
      </div>
    `;

    host.appendChild(section);

    $("#bds-fix-refresh", section)?.addEventListener("click", refreshAll);
    $("#bds-fix-installed-refresh", section)?.addEventListener("click", refreshInstalled);

    $("#bds-fix-download-selected", section)?.addEventListener("click", async () => {
      const option = $("#bds-fix-version-select")?.selectedOptions?.[0];
      if (!option || !option.value) return setDownloadStatus("Selecione uma versão primeiro.");
      await downloadBds({ version: option.value, url: option.dataset.url || "", channel: option.dataset.channel || "stable" });
    });

    $("#bds-fix-download-latest", section)?.addEventListener("click", async () => downloadBds({}));

    $("#bds-fix-download-manual", section)?.addEventListener("click", async () => {
      const version = $("#bds-fix-manual-version")?.value?.trim();
      if (!version) return setDownloadStatus("Informe uma versão. Exemplo: 1.21.101.1");
      await downloadBds({ version });
    });

    return section;
  }

  function setAvailableStatus(message) {
    const el = $("#bds-fix-available-status");
    if (el) el.textContent = message || "";
  }

  function setDownloadStatus(message) {
    const el = $("#bds-fix-download-status");
    if (el) el.textContent = message || "";
  }

  async function refreshAvailable() {
    const select = $("#bds-fix-version-select");
    if (!select) return;

    select.innerHTML = '<option value="">Carregando...</option>';
    setAvailableStatus("Consultando página oficial do Minecraft...");

    try {
      const data = await getJson("/api/bedrock/bds/available");
      const versions = [...(data.versions || []), ...(data.preview_versions || [])];

      if (!versions.length) {
        select.innerHTML = '<option value="">Nenhuma versão encontrada</option>';
        setAvailableStatus("Não consegui listar automaticamente. Use a versão manual.");
        return;
      }

      select.innerHTML = versions.map((item) => {
        const label = `${item.version} ${item.channel === "preview" ? "(Preview)" : "(Stable)"}`;
        return `<option value="${escapeHtml(item.version)}" data-url="${escapeHtml(item.url)}" data-channel="${escapeHtml(item.channel || "stable")}">${escapeHtml(label)}</option>`;
      }).join("");

      setAvailableStatus(data.latest ? `Mais recente: ${data.latest.version}` : "Versões carregadas.");
    } catch (error) {
      select.innerHTML = '<option value="">Erro ao carregar</option>';
      setAvailableStatus(`Erro: ${error.message}. Use a versão manual.`);
      log(`Bedrock available: ${error.message}`, "ERROR");
    }
  }

  async function refreshInstalled() {
    const list = $("#bds-fix-installed-list");
    if (!list) return;
    list.textContent = "Carregando...";

    try {
      const data = await getJson("/api/bedrock/bds/installed");
      const servers = data.servers || [];

      if (!servers.length) {
        list.innerHTML = '<span class="rubymc-bds-empty">Nenhum servidor Bedrock BDS instalado ainda.</span>';
        return;
      }

      list.innerHTML = servers.map((server) => `
        <div class="rubymc-bds-installed-row">
          <div>
            <strong>${escapeHtml(server.version)}</strong>
            <small>${escapeHtml(server.channel || "stable")} · ${escapeHtml(server.path || "")}</small>
          </div>
          <span class="${server.running ? "rubymc-bds-running" : "rubymc-bds-stopped"}">${server.running ? "Rodando" : "Parado"}</span>
        </div>
      `).join("");
    } catch (error) {
      list.innerHTML = `<span class="rubymc-bds-error">Erro: ${escapeHtml(error.message)}</span>`;
      log(`Bedrock installed: ${error.message}`, "ERROR");
    }
  }

  async function downloadBds(payload) {
    setDownloadStatus("Baixando e extraindo. Aguarde...");
    log("Download Bedrock BDS iniciado...", "ACTION");

    try {
      const data = await postJson("/api/bedrock/bds/download", payload);
      setDownloadStatus(data.message || "Download concluído.");
      log(data.message || "Bedrock BDS baixado.", "OK");
      await refreshInstalled();
      window.dispatchEvent(new CustomEvent("bedrock-versions-changed"));
    } catch (error) {
      setDownloadStatus(`Erro: ${error.message}`);
      log(`Download Bedrock BDS: ${error.message}`, "ERROR");
    }
  }

  async function refreshAll() {
    ensurePanel();
    await refreshAvailable();
    await refreshInstalled();
  }

  document.addEventListener("DOMContentLoaded", () => {
    ensurePanel();
    const versionsTab = document.querySelector('[data-tab="versions"]');
    if (versionsTab) versionsTab.addEventListener("click", () => setTimeout(refreshAll, 150));
    if (document.body.dataset.currentTab === "versions" || $("#tab-versions")?.classList.contains("active")) setTimeout(refreshAll, 300);
  });

  window.RubyMCBedrockBDSFix = { refresh: refreshAll, download: downloadBds };
})();
