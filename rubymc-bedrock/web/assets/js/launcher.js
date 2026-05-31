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
    $$(".side-link").forEach(btn => btn.classList.toggle("active", btn.dataset.tab === tab));
    $$(".tab-panel").forEach(panel => panel.classList.toggle("active", panel.id === `tab-${tab}`));
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
        ram: $("#settings-ram")?.value || ""
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

  function bindEvents() {
    $$(".side-link").forEach(btn => {
      btn.addEventListener("click", () => activateTab(btn.dataset.tab));
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

  document.addEventListener("DOMContentLoaded", () => {
    bindEvents();
    writeLog("SYSTEM", "Correção de lógica e imagens carregada. Interface pronta.");
    refreshStatus();
    updateModpacks(false).catch(() => {});
    setInterval(pollLogs, 4000);
  });
})();
