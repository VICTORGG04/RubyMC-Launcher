(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  let busy = false;

  const ROUTES = {
    status: ["/api/status", "/status"],
    logs: ["/api/logs", "/logs"],
    action: ["/api/action"],
    modpackImport: ["/api/modpacks/import", "/api/import_modpack", "/api/modpack/import"],
    modpacks: ["/api/modpacks", "/api/modpacks/list"]
  };

  const ROLE_TABS = {
    admin: ['home', 'server', 'versions', 'modpacks', 'discord', 'vip', 'display', 'project', 'settings'],
    staff: ['home', 'server', 'versions', 'modpacks', 'discord', 'vip', 'display', 'project', 'settings'],
    player: ['home', 'server', 'versions', 'modpacks', 'discord', 'vip', 'display', 'project', 'settings'],
    member: ['home', 'modpacks', 'display', 'settings']
  };

  const ACTION_ALIASES = {
    update_modpacks: ["update_modpacks", "refresh_modpacks", "list_modpacks"],
    validate_discord: ["validate_discord", "discord_validate", "validate_discord_settings"],
    test_discord_logs: ["test_discord_logs", "discord_test_logs", "test_logs_channel"],
    test_server: ["test_server", "server_test", "check_server"],
    join_server: ["join_server", "server_join"],
    clear_display: ["clear_display", "display_clear"],
    run_tests: ["run_tests", "test"],
    organize_project: ["organize_project", "organize"],
    open_project_folder: ["open_project_folder", "project_folder"],
    open_docs: ["open_docs", "docs"],
    check_updates: ["check_updates", "update_check"]
  };

  function time() {
    return new Date().toLocaleTimeString("pt-BR", { hour12: false });
  }

  function writeLog(type, message) {
    const display = $("#display-log");
    if (!display) return;
    display.textContent += `\n[${time()}] ${String(type).padEnd(7)} ${message}`;
    display.scrollTop = display.scrollHeight;
  }

  function activateTab(tab) {
    $$(".tab-link").forEach(btn => btn.classList.toggle("active", btn.dataset.tab === tab));
    $$(".tab-panel").forEach(panel => panel.classList.toggle("active", panel.id === `tab-${tab}`));
    document.body.dataset.currentTab = tab;
  }

  async function fetchJson(url, options = {}) {
    const response = await fetch(url, {
      headers: {
        "Accept": "application/json",
        ...(options.headers || {})
      },
      ...options
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`${response.status} ${response.statusText}${body ? ` — ${body.slice(0, 140)}` : ""}`);
    }

    return response.json();
  }

  async function postJson(url, payload = {}) {
    return fetchJson(url, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(payload)
    });
  }

  async function firstWorkingGet(urls) {
    let lastError;
    for (const url of urls) {
      try {
        return await fetchJson(url);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  function collectPayload(action) {
    return {
      action,
      profile: $("#profile-select")?.value || "vanilla",
      modpack_name: $("#modpack-name")?.value || "",
      server_address: $("#server-address")?.value || "",
      settings: {
        version: $("#settings-version")?.value || "",
        ram: $("#settings-ram")?.value || "",
        username: $("#settings-username")?.value || ""
      }
    };
  }

  async function sendBackendAction(action) {
    const aliases = ACTION_ALIASES[action] || [action];
    let lastError;

    for (const actionName of aliases) {
      try {
        return await postJson("/api/action", collectPayload(actionName));
      } catch (error) {
        lastError = error;
      }

      try {
        return await postJson(`/api/${actionName}`, collectPayload(actionName));
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError;
  }

  async function runAction(action) {
    if (!action || busy) return;
    busy = true;
    writeLog("ACTION", `Executando: ${action}`);

    try {
      if (action === "import_modpack") {
        await importModpack();
      } else if (action === "update_modpacks") {
        await updateModpacks();
      } else if (action === "clear_display") {
        clearDisplay();
        try {
          const result = await sendBackendAction(action);
          applyResult(result, action);
        } catch (_) {}
      } else {
        const result = await sendBackendAction(action);
        applyResult(result, action);
      }
    } catch (error) {
      writeLog("ERROR", `${action}: ${error.message}`);
    } finally {
      busy = false;
    }
  }

  async function importModpack() {
    const input = $("#modpack-file");
    const nameInput = $("#modpack-name");

    if (!input || !input.files || input.files.length === 0) {
      writeLog("WARN", "Selecione um arquivo .mrpack ou .zip.");
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
        const result = await fetchJson(url, { method: "POST", body: form });
        applyResult(result, "import_modpack");
        await updateModpacks(false);
        return;
      } catch (error) {
        lastError = error;
      }
    }

    try {
      const result = await sendBackendAction("import_modpack");
      applyResult(result, "import_modpack");
      await updateModpacks(false);
    } catch (_) {
      throw lastError;
    }
  }

  async function updateModpacks(showLog = true) {
    if (showLog) writeLog("ACTION", "Atualizando lista de modpacks...");

    for (const url of ROUTES.modpacks) {
      try {
        const result = await fetchJson(url);
        const modpacks = result.modpacks || result.data || result;
        renderModpacks(Array.isArray(modpacks) ? modpacks : []);
        if (showLog) writeLog("OK", "Lista de modpacks atualizada.");
        return;
      } catch (_) {}
    }

    const result = await sendBackendAction("update_modpacks");
    applyResult(result, "update_modpacks");
  }

  function clearDisplay() {
    const display = $("#display-log");
    if (display) display.textContent = `[${time()}] SYSTEM  Display limpo. Aguardando novos eventos...`;
  }

  function applyResult(result, action) {
    if (!result) {
      writeLog("OK", `${action} concluído.`);
      return;
    }

    if (typeof result === "string") {
      writeLog("OK", result);
      return;
    }

    if (result.message) writeLog(result.ok === false ? "ERROR" : "OK", result.message);

    if (Array.isArray(result.logs)) {
      result.logs.forEach(item => {
        if (typeof item === "string") writeLog("LOG", item);
        else writeLog(item.type || "LOG", item.message || JSON.stringify(item));
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

  function setText(id, value) {
    const el = document.getElementById(id);
    if (el && value !== undefined && value !== null && value !== "") el.textContent = value;
  }

  function setValue(id, value) {
    const el = document.getElementById(id);
    if (el && value !== undefined && value !== null && value !== "") el.value = value;
  }

  function applyStatus(status = {}) {
    setText("minecraft-version", status.minecraft_version || status.default_version || status.version);
    setText("active-profile", status.active_profile || status.profile);
    setText("server-state", status.server_status || status.server_state || status.server);
    setText("server-players", status.server_players || status.players);
    setText("launcher-state", status.launcher_status || status.status);
    setText("launcher-version", status.launcher_version || status.version);
    setValue("server-address", status.server_address || status.community_server || status.address);

    if (status.server_test) {
      setText("server-test-state", status.server_test.ok ? "Online" : "Offline");
      setText("server-test-detail", status.server_test.message || "");
    }

    const discord = status.discord || {};
    if (Object.keys(discord).length > 0) {
      const botActive = discord.bot_enabled === true || discord.bot === true || discord.status === "ativo" || discord.bot_state === "ativo";
      setText("discord-bot-state", botActive ? "Ativo" : (discord.bot_state || "Inativo"));
      setText("discord-channel-count", discord.channels || discord.channel_count || discord.channels_count);
      setText("discord-role-count", discord.roles || discord.role_count || discord.roles_count);
      setText("logs-channel-state", discord.logs_channel || discord.logs_channel_id ? "configurado" : "pendente");
      setText("discord-config-state", discord.configured === false ? "pendente" : "configurado");
    }
  }

  function renderModpacks(modpacks) {
    const list = $("#modpack-list");
    const select = $("#profile-select");
    if (!list) return;

    if (!Array.isArray(modpacks) || modpacks.length === 0) {
      list.textContent = "Nenhum modpack importado ainda.";
      return;
    }

    list.innerHTML = modpacks.map(item => {
      const name = typeof item === "string" ? item : (item.name || item.profile || item.title || "Modpack");
      const version = typeof item === "object" && item.version ? item.version : "";
      return `<div class="modpack-row"><strong>${escapeHtml(name)}</strong><span>${escapeHtml(version)}</span></div>`;
    }).join("");

    if (select) {
      const current = select.value;
      select.innerHTML = `<option value="vanilla">Vanilla / sem modpack</option>` + modpacks.map(item => {
        const name = typeof item === "string" ? item : (item.name || item.profile || item.title || "Modpack");
        return `<option value="${escapeHtml(name)}">${escapeHtml(name)}</option>`;
      }).join("");
      if ([...select.options].some(option => option.value === current)) select.value = current;
    }
  }

  function updateDisplay(content) {
    const display = $("#display-log");
    if (!display) return;
    display.textContent = Array.isArray(content) ? content.join("\n") : String(content);
    display.scrollTop = display.scrollHeight;
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  async function refreshStatus() {
    try {
      const data = await firstWorkingGet(ROUTES.status);
      applyStatus(data.status || data);
    } catch (_) {
      try {
        const data = await sendBackendAction("refresh_status");
        applyResult(data, "refresh_status");
      } catch (_) {
        writeLog("WARN", "Status será atualizado quando o backend responder.");
      }
    }
  }

  async function pollLogs() {
    try {
      const data = await firstWorkingGet(ROUTES.logs);
      if (data.display) updateDisplay(data.display);
      else if (data.logs) updateDisplay(data.logs);
    } catch (_) {}
  }

  const esc = escapeHtml;

  function setBusy(button, busy, label) {
    if (typeof busy === "string") {
      const orig = button.textContent;
      button.disabled = true;
      button.textContent = busy;
      return () => { button.disabled = false; button.textContent = orig; };
    }
    if (busy) {
      button.dataset.orig = button.dataset.orig || button.textContent;
      button.disabled = true;
      if (label) button.textContent = label;
    } else {
      button.textContent = button.dataset.orig || button.textContent;
      button.disabled = false;
    }
  }

  function bindEvents() {
    $$(".tab-link").forEach(btn => {
      btn.addEventListener("click", () => {
        activateTab(btn.dataset.tab);
        if (btn.dataset.tab === "vip") setTimeout(loadVipData, 100);
      });
    });

    $$("[data-tab-jump]").forEach(btn => {
      btn.addEventListener("click", () => activateTab(btn.dataset.tabJump));
    });

    $$("[data-action]").forEach(btn => {
      btn.addEventListener("click", () => runAction(btn.dataset.action));
    });

    $$(".toggle").forEach(toggle => {
      toggle.addEventListener("click", () => {
        toggle.classList.toggle("active");
        writeLog("ACTION", `Configuração alterada: ${toggle.dataset.toggle}`);
      });
    });

    const file = $("#modpack-file");
    const label = $("#modpack-file-label");
    if (file && label) {
      file.addEventListener("change", () => {
        label.textContent = file.files && file.files[0] ? file.files[0].name : "Clique para escolher ou arraste o arquivo aqui";
      });
    }
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
      const data = await fetchJson("/api/vip/status");
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
      const data = await fetchJson("/api/vip/plans");
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

      grid.querySelectorAll(".vip-checkout-btn").forEach(btn => {
        btn.addEventListener("click", () => {
          const planId = btn.dataset.vipPriceId;
          const parent = btn.closest(".vip-plan-card");
          const amountInput = parent?.querySelector(".doacao-input");
          vipCheckoutVIP(planId, btn, amountInput?.value || null);
        });
      });
      grid.querySelectorAll(".doacao-btn").forEach(btn => {
        btn.addEventListener("click", () => {
          const planId = btn.dataset.vipPriceId;
          const parent = btn.closest(".vip-plan-card");
          const amountInput = parent?.querySelector(".doacao-input");
          vipCheckoutVIP(planId, btn, amountInput?.value || null);
        });
      });
    } catch (error) {
      grid.innerHTML = `<span style="color:var(--muted);font-style:italic;">Erro ao carregar planos: ${esc(error.message)}</span>`;
    }
  }

  async function loadPendingPayments() {
    const section = document.getElementById("vip-pending-section");
    const list = document.getElementById("vip-pending-list");
    if (!section || !list) return;
    try {
      const data = await fetchJson("/api/vip/pix/status");
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
      const data = await postJson("/api/vip/pix/confirm", { payment_id: paymentId });
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
      const data = await postJson("/api/vip/pix/reject", { payment_id: paymentId });
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
      const data = await postJson("/api/vip/checkout", body);
      if (data.ok === false) { alert(data.error || "Erro ao processar checkout"); return; }
      showPixModal(data);
    } catch (error) {
      alert("Erro de rede: " + error.message);
    } finally {
      restore();
    }
  }

  /* ── PIX Modal ──────────────────────────────────── */

  let pixPollTimer = null;

  function copyPixCode() {
    const code = document.getElementById("pix-code-text");
    if (!code) return;
    navigator.clipboard.writeText(code.textContent).then(() => {
      const btn = document.getElementById("pix-copy-btn");
      if (btn) { btn.textContent = "✅ Copiado!"; setTimeout(() => { btn.textContent = "📋 Copiar"; }, 2000); }
    }).catch(() => alert("Copie manualmente: " + code.textContent));
  }

  function updatePixStatus(status) {
    const indicator = document.getElementById("pix-status-indicator");
    if (!indicator) return;
    if (status === "completed") {
      indicator.className = "pix-modal-status success";
      indicator.innerHTML = '<span class="pix-status-dot completed"></span> ✅ Pagamento confirmado!';
    } else {
      indicator.className = "pix-modal-status";
      indicator.innerHTML = '<span class="pix-status-dot pending"></span> Aguardando pagamento...';
    }
  }

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
        const data = await fetchJson("/api/vip/pix/status?payment_id=" + encodeURIComponent(paymentId));
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
      const data = await fetchJson("/api/vip/pix/status?payment_id=" + encodeURIComponent(paymentId));
      if (!data.ok) { alert(data.error || "Erro ao verificar status"); return; }
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
    if (!file) { statusEl.textContent = "Selecione um arquivo primeiro."; statusEl.className = "pix-receipt-status error"; return; }
    if (file.size > 10_485_760) { statusEl.textContent = "Arquivo muito grande. Máximo 10MB."; statusEl.className = "pix-receipt-status error"; return; }
    statusEl.textContent = "Enviando...";
    statusEl.className = "pix-receipt-status";
    const form = new FormData();
    form.append("payment_id", paymentId);
    form.append("receipt", file);
    try {
      const resp = await fetch("/api/vip/pix/receipt", { method: "POST", body: form });
      const data = await resp.json();
      if (!data.ok) { statusEl.textContent = data.error || "Erro ao enviar comprovante."; statusEl.className = "pix-receipt-status error"; return; }
      if (data.confirmed) {
        statusEl.textContent = data.message; statusEl.className = "pix-receipt-status success";
        updatePixStatus("completed");
        if (pixPollTimer) { clearInterval(pixPollTimer); pixPollTimer = null; }
        setTimeout(() => { closePixModal(); loadVipData(); }, 2000);
      } else {
        const ocrInfo = data.ocr ? ` (detectado: R$ ${data.ocr.amount || "?"} — ${data.ocr.sender || "?"})` : "";
        statusEl.textContent = data.message + ocrInfo; statusEl.className = "pix-receipt-status";
      }
    } catch (error) {
      statusEl.textContent = "Erro de rede: " + error.message; statusEl.className = "pix-receipt-status error";
    }
  }

  /* ── Auth ─────────────────────────────────────────── */

  async function checkAuth() {
    const overlay = document.getElementById('login-overlay');
    const prompt = document.getElementById('login-prompt');
    const loading = document.getElementById('login-loading');

    try {
      const data = await fetchJson('/api/auth/status');
      if (data.authenticated) {
        window._userRole = data.role;
        window._userData = data.user;
        if (overlay) overlay.style.display = 'none';
        applyRoleFilter(data.role);
        updateRoleBadge(data.role, data.user);
        updateSettingsUserInfo(data.user, data.role);
        updateMemberCardRole(data.role);
        return true;
      }
    } catch (_) {}

    if (loading) loading.style.display = 'none';
    if (overlay) overlay.style.display = 'flex';
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

  function updateMemberCardRole(role) {
    const el = document.getElementById('msc-member-role');
    if (!el) return;
    const labels = { admin: 'Admin', staff: 'Staff', player: 'Membro Ruby', member: 'Membro' };
    el.innerHTML = '<img src="' + roleBadgeUrl(role) + '" class="role-badge-img" alt=""> ' + (labels[role] || role);
  }

  async function loadDiscordInfo() {
    try {
      const data = await fetchJson('/api/discord/members');
      if (data.ok && data.members) {
        setText('discord-guild-name', data.members.guild_name || '---');
        setText('msc-guild-name', data.members.guild_name || 'RubyMC');
        setText('discord-member-count', data.members.members_count);
        setText('discord-online-count', data.members.presence_count);
        setText('home-discord-members', data.members.members_count);
      }
    } catch (_) {}
  }

  /* ── Verification ────────────────────────────────── */

  async function loadVerificationStatus() {
    try {
      const res = await fetchJson('/api/auth/verify/status');
      if (!res.ok) return;

      if (res.terms_accepted) {
        const st = document.getElementById('vstep-terms-status');
        if (st) { st.textContent = '✓ aceito'; st.style.color = '#00c853'; }
        const ds = document.getElementById('vstep-discord');
        if (ds) { ds.style.opacity = '1'; ds.style.pointerEvents = 'auto'; }
      }

      if (res.discord_verified) {
        const st = document.getElementById('vstep-discord-status');
        if (st) { st.textContent = '✓ verificado'; st.style.color = '#00c853'; }
      }

      if (res.overall_complete) {
        const btn = document.getElementById('complete-verification-btn');
        if (btn) btn.disabled = false;
      }
    } catch (_) {}
  }

  async function checkVerificationComplete() {
    try {
      const res = await fetchJson('/api/auth/verify/status');
      if (res.ok && res.overall_complete) {
        const btn = document.getElementById('complete-verification-btn');
        if (btn) btn.disabled = false;
      }
    } catch (_) {}
  }

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

    if (termsShowBtn) {
      termsShowBtn.addEventListener('click', (e) => {
        e.preventDefault();
        showTermsOverlay(true);
      });
    }

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

    if (termsCheckbox && termsAcceptBtn) {
      termsCheckbox.addEventListener('change', () => {
        termsAcceptBtn.disabled = !termsCheckbox.checked;
      });
    }

    if (termsAcceptBtn) {
      termsAcceptBtn.addEventListener('click', async () => {
        try {
          const res = await postJson('/api/auth/verify/accept-terms', {});
          if (res.ok) {
            const st = document.getElementById('vstep-terms-status');
            if (st) { st.textContent = '✓ aceito'; st.style.color = '#00c853'; }
            if (discordStep) {
              discordStep.style.opacity = '1';
              discordStep.style.pointerEvents = 'auto';
              const ds = document.getElementById('vstep-discord-status');
              if (ds) { ds.textContent = 'pendente'; ds.style.color = '#ffc107'; }
            }
          } else {
            setDiscordMsg(discordGuildMsg, res.error || 'Erro ao aceitar termos.', '#e74c3c');
          }
        } catch (e) {
          setDiscordMsg(discordGuildMsg, 'Erro de rede: ' + e.message, '#e74c3c');
        }
      });
    }

    if (discordJoinBtn) {
      discordJoinBtn.addEventListener('click', async () => {
        window.open('https://discord.gg/MnrSXTF4qx', '_blank');
        setDiscordMsg(discordGuildMsg, '🔗 Link do Discord aberto! Entre no servidor e depois clique em "Verificar presença".', '#ffc107');
      });
    }

    if (discordCheckGuildBtn) {
      discordCheckGuildBtn.addEventListener('click', async () => {
        discordCheckGuildBtn.disabled = true;
        discordCheckGuildBtn.textContent = 'Verificando...';
        try {
          const res = await postJson('/api/auth/verify/check-guild-membership', {});
          if (res.ok && res.in_guild) {
            setDiscordMsg(discordGuildMsg, '✅ Você está no servidor! Agora envie o código.', '#00c853');
            if (discordJoinDiv) discordJoinDiv.style.display = 'none';
            if (discordCodeDiv) discordCodeDiv.style.display = '';
            const ds = document.getElementById('vstep-discord-status');
            if (ds) { ds.textContent = 'pendente'; ds.style.color = '#ffc107'; }
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

    if (discordSendBtn) {
      discordSendBtn.addEventListener('click', async () => {
        discordSendBtn.disabled = true;
        discordSendBtn.textContent = 'Enviando...';
        try {
          const res = await postJson('/api/auth/verify/send-discord-code', {});
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
          const res = await postJson('/api/auth/verify/confirm-discord-code', { code: code });
          if (res.ok) {
            const ds = document.getElementById('vstep-discord-status');
            if (ds) { ds.textContent = '✓ verificado'; ds.style.color = '#00c853'; }
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

    if (completeBtn) {
      completeBtn.addEventListener('click', async () => {
        completeBtn.disabled = true;
        completeBtn.textContent = 'Processando...';
        try {
          const res = await postJson('/api/auth/verify/complete', {});
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
            writeLog('OK', '🎉 Parabéns! Você agora é Membro Ruby!');
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

  /* ── Expose global handlers for inline onclick ── */

  window.confirmPendingPayment = confirmPendingPayment;
  window.rejectPendingPayment = rejectPendingPayment;
  window.closePixModal = closePixModal;

  window.handleDiscordServerJoin = function() {
    window.open('https://discord.gg/MnrSXTF4qx', '_blank');
  };

  window.refreshServerLiveStatus = refreshStatus;

  document.addEventListener("DOMContentLoaded", () => {
    bindEvents();
    writeLog("SYSTEM", "Correção de lógica e imagens carregada. Interface pronta.");
    refreshStatus();
    updateModpacks(false).catch(() => {});

    const logoutBtn = document.getElementById("logout-btn");
    if (logoutBtn) {
      logoutBtn.addEventListener("click", async () => {
        try {
          await postJson("/api/auth/logout", {});
          location.reload();
        } catch (e) {
          writeLog("ERROR", "Logout: " + e.message);
        }
      });
    }

    const loginBtn = document.getElementById('login-discord-btn');
    if (loginBtn) {
      loginBtn.addEventListener('click', () => { window.location.href = '/api/auth/discord/login'; });
    }

    checkAuth().then((authenticated) => {
      if (!authenticated) return;
      document.body.dataset.currentTab = document.body.dataset.currentTab || 'home';
      initVerification();
      setTimeout(loadDiscordInfo, 600);
    });

    setInterval(pollLogs, 4000);
  });
})();
