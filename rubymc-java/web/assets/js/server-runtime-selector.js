(() => {
  "use strict";

  const STORAGE_VERSION_KEY = "rubymc.server.java.version";

  const inFlight = new Set();

  function selectedVersion() {
    const select = $("#server-runtime-version");
    return select?.value || "";
  }

  function selectedLoader() {
    const option = $("#server-runtime-version")?.selectedOptions?.[0];
    return option?.dataset?.loader || "vanilla";
  }

  function saveCurrentSelection() {
    const version = selectedVersion();
    localStorage.setItem(STORAGE_VERSION_KEY, version);
    localStorage.setItem("rubymc.server.runtime.type", "java");
  }

  function ensureServerSelectorBox() {
    const tab = document.getElementById("tab-server");
    if (!tab || document.getElementById("server-runtime-selector")) return;

    const address = document.getElementById("server-address");
    const actions = tab.querySelector(".actions");
    if (!address && !actions) return;

    const box = document.createElement("div");
    box.id = "server-runtime-selector";
    box.className = "server-runtime-selector field-box";
    box.innerHTML = `
      <div class="server-runtime-header">
        <div>
          <small>Servidor Java</small>
          <strong>Controle do servidor Minecraft Java</strong>
        </div>
        <span id="server-runtime-badge" class="server-runtime-badge">Java</span>
      </div>

      <div class="server-runtime-grid">
        <label class="server-runtime-field" for="server-runtime-version">
          <small>Versão Java instalada</small>
          <select id="server-runtime-version">
            <option value="">Carregando...</option>
          </select>
        </label>

        <button class="btn btn-dark btn-sm server-runtime-refresh" type="button" id="server-runtime-refresh">Atualizar</button>
      </div>

      <em id="server-runtime-help" class="server-runtime-help">
        Java usa a porta TCP 25565. Escolha uma versão Java instalada para iniciar.
      </em>
    `;

    if (address) address.insertAdjacentElement("afterend", box);
    else actions.insertAdjacentElement("beforebegin", box);

    document.getElementById("server-runtime-version")?.addEventListener("change", saveCurrentSelection);
    document.getElementById("server-runtime-refresh")?.addEventListener("click", loadVersionsForCurrentType);
  }

  function claimServerButtons() {
    const mappings = [
      { selector: "#server-start-btn, [data-action='start_server']", action: "start" },
      { selector: "#server-stop-btn, [data-action='stop_server']", action: "stop" },
      { selector: "#server-restart-btn, [data-action='restart_server']", action: "restart" },
      { selector: "[data-action='test_server']", action: "test" }
    ];

    mappings.forEach(({ selector, action }) => {
      $$(selector).forEach((button) => {
        if (button.dataset.rubymcRuntimeBound === "true") return;

        button.dataset.rubymcRuntimeBound = "true";
        button.dataset.rubymcRuntimeAction = action;
        button.dataset.rubymcOldAction = button.dataset.action || "";
        button.removeAttribute("data-action");

        button.addEventListener("click", (event) => {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();
          runRuntimeAction(action).catch(() => {});
        }, true);
      });
    });

    updateRuntimeLabels();
  }

  function updateRuntimeLabels() {
    const help = document.getElementById("server-runtime-help");
    if (help) help.textContent = "Java usa a porta TCP 25565. Escolha uma versão Java instalada para iniciar.";

    setText("server-live-version", selectedVersion() || "--");
  }

  async function loadJavaVersions() {
    const data = await apiGet("/api/versions");
    if (data.ok === false) throw new Error(data.error || "Falha ao carregar versões Java.");

    const installed = data.installed || [];
    const active = data.active || null;

    return { installed, active };
  }

  async function loadVersionsForCurrentType() {
    ensureServerSelectorBox();
    const select = document.getElementById("server-runtime-version");
    const help = document.getElementById("server-runtime-help");
    if (!select) return;

    const previous = localStorage.getItem(STORAGE_VERSION_KEY);

    select.innerHTML = '<option value="">Carregando...</option>';

    try {
      const { installed, active } = await loadJavaVersions();
      if (!installed.length) {
        select.innerHTML = '<option value="">Nenhuma versão Java instalada</option>';
        if (help) help.textContent = "Instale uma versão na aba Versões antes de iniciar o servidor Java.";
        updateRuntimeLabels();
        return;
      }

      select.innerHTML = installed.map((version) => {
        const id = version.id || "";
        const loader = version.loader_label || version.loader || "vanilla";
        const selected = previous === id || (!previous && active && active.id === id) ? "selected" : "";
        return `<option value="${esc(id)}" data-loader="${esc(version.loader || "vanilla")}" ${selected}>${esc(id)} (${esc(loader)})</option>`;
      }).join("");

      if (help) {
        help.textContent = active
          ? `Java ativo: ${active.id}. Você pode escolher outra versão para iniciar.`
          : "Escolha uma versão Java instalada para iniciar.";
      }

      saveCurrentSelection();
      updateRuntimeLabels();
    } catch (error) {
      select.innerHTML = `<option value="">Erro: ${esc(error.message)}</option>`;
      if (help) help.textContent = "Não foi possível carregar as versões.";
      log("ERROR", error.message);
    }
  }

  function javaPayload() {
    const version = selectedVersion();
    const loader = selectedLoader();

    return {
      action: "",
      version_id: version,
      server_version_id: version,
      loader,
      server_loader: loader,
      start_only_server: true,
      host: "127.0.0.1",
      port: 25565,
      wait_timeout: 60
    };
  }

  async function runJavaAction(action) {
    const payload = javaPayload();
    const version = payload.version_id;

    if ((action === "start" || action === "restart") && !version) {
      throw new Error("Escolha uma versão Java antes de iniciar.");
    }

    const runtimeCalls = {
      start: [
        () => apiPost("/api/server/java/start", payload),
        async () => {
          await apiPost("/api/action", { ...payload, action: "version_activate" });
          return apiPost("/api/action", { ...payload, action: "start_server" });
        }
      ],
      stop: [
        () => apiPost("/api/server/java/stop", payload),
        () => apiPost("/api/action", { ...payload, action: "stop_server" })
      ],
      restart: [
        () => apiPost("/api/server/java/restart", payload),
        async () => {
          await apiPost("/api/action", { ...payload, action: "version_activate" });
          return apiPost("/api/action", { ...payload, action: "restart_server" });
        }
      ],
      test: [
        () => apiPost("/api/server/java/test", payload),
        () => apiPost("/api/action", { ...payload, action: "test_server" })
      ],
      status: [
        () => apiGet("/api/server/java/status")
      ]
    };

    return firstSuccessful(runtimeCalls[action] || []);
  }

  function setBusy(action, busy) {
    ["server-start-btn", "server-stop-btn", "server-restart-btn"].forEach((id) => {
      const btn = document.getElementById(id);
      if (!btn) return;
      btn.disabled = busy;
      btn.classList.toggle("is-loading", busy);
    });

    const test = $("[data-rubymc-runtime-action='test']");
    if (test) test.disabled = busy;

    const refresh = document.getElementById("server-runtime-refresh");
    if (refresh) refresh.disabled = busy;

    if (busy) {
      setText("server-test-state", "Processando...");
      setText("server-test-detail", action);
    }
  }

  function applyResult(data, action) {
    const ok = data && data.ok !== false;
    const message = data?.message || data?.error || `Java: ${action} concluído.`;

    log(ok ? "OK" : "ERROR", message);

    setText("server-test-state", ok ? "OK" : "Erro");
    setText("server-test-detail", message);
    setText("server-state", ok ? (data.running === false ? "Offline" : "Online") : "Erro");
    setText("server-live-version", data.version_id || data.active_version || selectedVersion() || "Java");
    setText("server-live-latency", data.port_open ? "TCP 25565 OK" : "TCP 25565");
    setText("server-players", "Java Server");
    if (data.pid) setText("server-live-checked", `PID ${data.pid}`);
    if (data.log_tail) logBlock("LOG", data.log_tail);
    if (data.stdout_tail) logBlock("STDOUT", data.stdout_tail);
  }

  async function runRuntimeAction(action, options = {}) {
    const key = `java:${action}`;

    if (inFlight.has(key)) {
      if (!options.silent) log("WARN", `Ação ${action} do servidor Java já está em execução.`);
      return null;
    }

    inFlight.add(key);

    const labels = {
      start: "Iniciando servidor Java...",
      stop: "Parando servidor Java...",
      restart: "Reiniciando servidor Java...",
      test: "Testando servidor Java...",
      status: "Consultando servidor Java..."
    };

    if (!options.silent) setBusy(labels[action] || action, true);

    try {
      const data = await runJavaAction(action);

      if (!options.silent) applyResult(data, action);
      return data;
    } catch (error) {
      const data = error.data || {};
      const payload = { ok: false, message: error.message, ...data };
      if (!options.silent) applyResult(payload, action);
      throw error;
    } finally {
      inFlight.delete(key);
      if (!options.silent) setBusy("", false);
      if (["start", "stop", "restart"].includes(action)) {
        setTimeout(loadVersionsForCurrentType, 800);
        setTimeout(() => window.refreshServerLiveStatus?.(), 1500);
      }
    }
  }

  function initOnServerTabOpen() {
    document.querySelectorAll('[data-tab="server"]').forEach((button) => {
      button.addEventListener("click", () => {
        setTimeout(() => {
          ensureServerSelectorBox();
          claimServerButtons();
          loadVersionsForCurrentType();
          runRuntimeAction("status", { silent: true }).catch(() => {});
        }, 150);
      });
    });
  }

  function init() {
    ensureServerSelectorBox();
    claimServerButtons();
    updateRuntimeLabels();
    loadVersionsForCurrentType();
    initOnServerTabOpen();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

})();
