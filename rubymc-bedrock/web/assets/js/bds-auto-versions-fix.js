/* RubyMC BDS Auto Versions UX Fix
   Deixa claro quando a lista automática vem de fallback e evita instalar "latest" sem versão.
*/
(() => {
  "use strict";

  async function getJson(endpoint) {
    const response = await fetch(endpoint, { headers: { Accept: "application/json" } });
    const text = await response.text();
    const data = text.trim() ? JSON.parse(text) : {};
    if (!response.ok || data.ok === false) throw new Error(data.error || data.message || `HTTP ${response.status}`);
    return data;
  }

  function $(selector) {
    return document.querySelector(selector);
  }

  function setText(selector, text) {
    const el = $(selector);
    if (el) el.textContent = text || "";
  }

  function optionHtml(item) {
    const version = item.version || item.id || item.name || "";
    const channel = item.channel || "stable";
    const source = item.source || "";
    const url = item.url || "";
    const label = `${version}${channel === "preview" ? " (Preview)" : ""}${item.installed ? " — instalado" : ""}`;
    return `<option value="${escapeHtml(version)}" data-url="${escapeHtml(url)}" data-channel="${escapeHtml(channel)}" data-source="${escapeHtml(source)}">${escapeHtml(label)}</option>`;
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  async function reloadBdsAvailableStrict() {
    const select = $("#bds-available-select");
    const latestBtn = $("#bds-install-latest");
    const installBtn = $("#bds-install-selected");
    if (!select) return;

    select.innerHTML = `<option value="">Carregando...</option>`;
    if (latestBtn) latestBtn.disabled = true;
    if (installBtn) installBtn.disabled = true;

    try {
      const data = await getJson("/api/bedrock/servers/available");
      const versions = [...(data.versions || []), ...(data.preview_versions || [])]
        .filter((item) => item && (item.version || item.id || item.name));

      if (!versions.length) {
        select.innerHTML = `<option value="">Nenhuma versão automática encontrada</option>`;
        setText("#bds-install-status", "A página oficial não retornou links de BDS. Use a instalação manual com uma versão válida ou tente Atualizar lista novamente.");
        return;
      }

      select.innerHTML = versions.map(optionHtml).join("");

      if (latestBtn) latestBtn.disabled = false;
      if (installBtn) installBtn.disabled = false;

      const msg = data.used_fallback
        ? `Lista carregada via índice auxiliar: ${versions.length} versão(ões).`
        : `Lista oficial carregada: ${versions.length} versão(ões).`;

      setText("#bds-install-status", msg);
    } catch (error) {
      select.innerHTML = `<option value="">Erro ao carregar versões</option>`;
      setText("#bds-install-status", `Erro ao carregar versões: ${error.message}`);
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    const refreshBtn = $("#bds-refresh-available");
    if (refreshBtn) {
      refreshBtn.addEventListener("click", () => setTimeout(reloadBdsAvailableStrict, 50));
    }

    const versionsTab = document.querySelector('[data-tab="versions"]');
    if (versionsTab) {
      versionsTab.addEventListener("click", () => setTimeout(reloadBdsAvailableStrict, 150));
    }

    setTimeout(reloadBdsAvailableStrict, 600);
  });

  window.RubyMCBDSReloadAvailable = reloadBdsAvailableStrict;
})();
