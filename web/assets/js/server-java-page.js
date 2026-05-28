/* =========================================================
   RubyMC Java Server Page Patch
   - Adiciona seletor de versão na Página Servidor
   - Inicia/reinicia somente a versão escolhida
   - Evita chamadas duplicadas dos botões start/stop/restart/test
   - Mostra tail do latest.log quando o servidor não abre a porta 25565
   ========================================================= */
(() => {
  "use strict";

  const inFlight = new Set();

  function ensureServerVersionBox() {
    const tab = document.getElementById("tab-server");
    if (!tab || document.getElementById("server-version-select")) return;

    const address = document.getElementById("server-address");
    const actions = tab.querySelector(".actions");
    if (!actions) return;

    const box = document.createElement("div");
    box.className = "server-version-control";
    box.innerHTML = `
      <div class="field-box server-version-box">
        <small>Versão do servidor para iniciar</small>
        <div class="server-version-row">
          <select id="server-version-select">
            <option value="">Carregando versões instaladas...</option>
          </select>
          <button class="btn btn-dark btn-sm" type="button" id="server-version-refresh">Atualizar</button>
        </div>
        <em id="server-version-help">Escolha uma versão instalada antes de iniciar ou reiniciar o servidor.</em>
      </div>
    `;

    if (address) address.insertAdjacentElement("afterend", box);
    else actions.insertAdjacentElement("beforebegin", box);

    const refresh = document.getElementById("server-version-refresh");
    if (refresh) refresh.addEventListener("click", loadServerVersions);
  }

  async function loadServerVersions() {
    const select = document.getElementById("server-version-select");
    const help = document.getElementById("server-version-help");
    if (!select) return;

    select.innerHTML = '<option value="">Carregando...</option>';

    try {
      const data = await apiGet("/api/versions");
      if (!data.ok) throw new Error(data.error || "Falha ao carregar versões");

      const installed = data.installed || [];
      const active = data.active || null;

      if (!installed.length) {
        select.innerHTML = '<option value="">Nenhuma versão instalada</option>';
        if (help) help.textContent = "Instale uma versão na aba Versões antes de iniciar o servidor.";
        return;
      }

      select.innerHTML = installed.map((version) => {
        const id = version.id;
        const loader = version.loader_label || version.loader || "vanilla";
        const selected = active && active.id === id ? "selected" : "";
        return `<option value="${esc(id)}" data-loader="${esc(version.loader || "vanilla")}" ${selected}>${esc(id)} (${esc(loader)})</option>`;
      }).join("");

      if (help) {
        help.textContent = active
          ? `Versão ativa atual: ${active.id}. Você pode escolher outra para iniciar o servidor.`
          : "Escolha uma versão instalada para iniciar o servidor.";
      }
    } catch (error) {
      select.innerHTML = `<option value="">Erro: ${esc(error.message)}</option>`;
      if (help) help.textContent = "Não foi possível carregar as versões instaladas.";
    }
  }

  function selectedServerVersionPayload() {
    const select = document.getElementById("server-version-select");
    const option = select?.selectedOptions?.[0];
    const versionId = select?.value || "";
    const loader = option?.dataset?.loader || "vanilla";

    return {
      version_id: versionId,
      server_version_id: versionId,
      loader,
      server_loader: loader,
      host: "127.0.0.1",
      port: 25565,
      wait_timeout: 60
    };
  }

  function setServerBusy(action, busy) {
    const ids = ["server-start-btn", "server-stop-btn", "server-restart-btn"];
    ids.forEach((id) => {
      const btn = document.getElementById(id);
      if (!btn) return;
      btn.disabled = busy;
      btn.classList.toggle("is-loading", busy);
    });

    const test = document.querySelector('[data-action="test_server"]');
    if (test) test.disabled = busy;

    if (busy) setText("server-test-state", "Processando...");
    if (action) setText("server-test-detail", action);
  }

  function applyServerResult(data, actionLabel) {
    const ok = data.ok !== false;
    const message = data.message || data.error || `${actionLabel} concluído.`;

    log(ok ? "OK" : "ERROR", message);
    setText("server-test-state", ok ? "OK" : "Erro");
    setText("server-test-detail", message);

    if (data.port_open === true) setText("server-state", "Online");
    if (data.port_open === false && data.running) setText("server-state", "Inicializando");
    if (data.running === false) setText("server-state", "Offline");

    if (data.active_version || data.version_id) setText("server-live-version", data.active_version || data.version_id);
    if (data.pid) log("PID", `Servidor Java PID ${data.pid}`);

    if (data.log_tail && !ok) logBlock("SERVER", data.log_tail);
    if (data.stdout_tail && !ok) logBlock("STDOUT", data.stdout_tail);

    refreshServerStatusSoon();
  }

  function refreshServerStatusSoon() {
    setTimeout(() => runJavaServerAction("status", { silent: true }).catch(() => {}), 1500);
    setTimeout(() => runJavaServerAction("status", { silent: true }).catch(() => {}), 5000);
  }

  async function runJavaServerAction(action, options = {}) {
    const key = `java:${action}`;
    if (inFlight.has(key)) {
      if (!options.silent) log("WARN", `Ação ${action} já está em execução.`);
      return;
    }

    inFlight.add(key);

    const labels = {
      start: "Iniciando servidor Java...",
      stop: "Parando servidor Java...",
      restart: "Reiniciando servidor Java...",
      test: "Testando servidor Java...",
      status: "Consultando servidor Java..."
    };

    if (!options.silent) setServerBusy(labels[action] || action, true);

    try {
      let data;

      if (action === "status") {
        data = await apiGet("/api/server/java/status");
      } else if (action === "test") {
        data = await apiPost("/api/server/java/test", selectedServerVersionPayload());
      } else {
        data = await apiPost(`/api/server/java/${action}`, selectedServerVersionPayload());
      }

      if (!options.silent) applyServerResult(data, labels[action] || action);
      else updateServerStatusCard(data);

      return data;
    } catch (error) {
      const data = error.data || {};
      if (!options.silent) {
        applyServerResult({ ok: false, message: error.message, ...data }, labels[action] || action);
      }
      throw error;
    } finally {
      inFlight.delete(key);
      if (!options.silent) setServerBusy("", false);
    }
  }

  function updateServerStatusCard(data) {
    if (!data) return;

    if (data.running && data.port_open) {
      setText("server-state", "Online");
      setText("server-test-state", "Online");
      setText("server-test-detail", data.message || "Servidor online.");
    } else if (data.running) {
      setText("server-state", "Inicializando");
      setText("server-test-state", "Processo ativo");
      setText("server-test-detail", data.message || "Processo ativo, aguardando porta.");
    } else {
      setText("server-state", "Offline");
      setText("server-test-state", "Offline");
      setText("server-test-detail", data.message || "Servidor parado.");
    }

    if (data.active_version) setText("server-live-version", data.active_version);
    if (data.port_open !== undefined) setText("server-live-latency", data.port_open ? "porta aberta" : "porta fechada");
  }

  function interceptServerButtons() {
    document.addEventListener("click", (event) => {
      const button = event.target.closest('[data-action="start_server"], [data-action="stop_server"], [data-action="restart_server"], [data-action="test_server"]');
      if (!button) return;

      const action = button.dataset.action;
      const map = {
        start_server: "start",
        stop_server: "stop",
        restart_server: "restart",
        test_server: "test"
      };

      const runtimeAction = map[action];
      if (!runtimeAction) return;

      // Impede o listener antigo do launcher.js de enviar /api/action junto.
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      runJavaServerAction(runtimeAction).catch(() => {});
    }, true);
  }

  function init() {
    ensureServerVersionBox();
    loadServerVersions();
    interceptServerButtons();

    document.querySelectorAll('[data-tab="server"]').forEach((btn) => {
      btn.addEventListener("click", () => {
        setTimeout(() => {
          ensureServerVersionBox();
          loadServerVersions();
          runJavaServerAction("status", { silent: true }).catch(() => {});
        }, 150);
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
