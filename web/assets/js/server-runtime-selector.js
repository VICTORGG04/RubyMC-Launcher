/* =========================================================
   RubyMC Server Runtime Selector
   - Adiciona seletor Java / Bedrock na Página Servidor
   - Carrega versões Java instaladas e servidores Bedrock instalados
   - Inicia / para / reinicia / testa somente o tipo escolhido
   - Remove data-action dos botões da aba Servidor para evitar chamada duplicada
   ========================================================= */
(() => {
  "use strict";

  const STORAGE_TYPE_KEY = "rubymc.server.runtime.type";
  const STORAGE_JAVA_VERSION_KEY = "rubymc.server.runtime.java.version";
  const STORAGE_BEDROCK_VERSION_KEY = "rubymc.server.runtime.bedrock.version";

  const DEFAULT_JAVA_PORT = 25565;
  const DEFAULT_BEDROCK_PORT = 19132;

  const inFlight = new Set();
  let cachedJavaVersions = [];
  let cachedBedrockServers = [];

  function currentType() {
    const select = $("#server-runtime-type");
    return (select?.value || localStorage.getItem(STORAGE_TYPE_KEY) || "java").toLowerCase();
  }

  function selectedVersion() {
    const select = $("#server-runtime-version");
    return select?.value || "";
  }

  function selectedLoader() {
    const option = $("#server-runtime-version")?.selectedOptions?.[0];
    return option?.dataset?.loader || "vanilla";
  }

  function saveCurrentSelection() {
    const type = currentType();
    const version = selectedVersion();
    localStorage.setItem(STORAGE_TYPE_KEY, type);
    if (type === "java") localStorage.setItem(STORAGE_JAVA_VERSION_KEY, version);
    if (type === "bedrock") localStorage.setItem(STORAGE_BEDROCK_VERSION_KEY, version);
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
          <small>Tipo de servidor</small>
          <strong>Escolha Java ou Bedrock</strong>
        </div>
        <span id="server-runtime-badge" class="server-runtime-badge">Java</span>
      </div>

      <div class="server-runtime-grid">
        <label class="server-runtime-field" for="server-runtime-type">
          <small>Servidor</small>
          <select id="server-runtime-type">
            <option value="java">Minecraft Java</option>
            <option value="bedrock">Minecraft Bedrock</option>
          </select>
        </label>

        <label class="server-runtime-field" for="server-runtime-version">
          <small id="server-runtime-version-label">Versão Java instalada</small>
          <select id="server-runtime-version">
            <option value="">Carregando...</option>
          </select>
        </label>

        <button class="btn btn-dark btn-sm server-runtime-refresh" type="button" id="server-runtime-refresh">Atualizar</button>
      </div>

      <em id="server-runtime-help" class="server-runtime-help">
        Java usa TCP 25565. Bedrock usa UDP 19132.
      </em>
    `;

    if (address) address.insertAdjacentElement("afterend", box);
    else actions.insertAdjacentElement("beforebegin", box);

    const typeSelect = document.getElementById("server-runtime-type");
    typeSelect.value = localStorage.getItem(STORAGE_TYPE_KEY) || "java";

    typeSelect.addEventListener("change", async () => {
      saveCurrentSelection();
      updateRuntimeLabels();
      await loadVersionsForCurrentType();
    });

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
    const type = currentType();
    const isBedrock = type === "bedrock";

    const badge = document.getElementById("server-runtime-badge");
    const versionLabel = document.getElementById("server-runtime-version-label");
    const help = document.getElementById("server-runtime-help");

    if (badge) {
      badge.textContent = isBedrock ? "Bedrock" : "Java";
      badge.classList.toggle("is-bedrock", isBedrock);
    }

    if (versionLabel) {
      versionLabel.textContent = isBedrock ? "Versão Bedrock/BDS instalada" : "Versão Java instalada";
    }

    if (help) {
      help.textContent = isBedrock
        ? "Bedrock usa a porta UDP 19132. Escolha uma versão BDS instalada para iniciar."
        : "Java usa a porta TCP 25565. Escolha uma versão Java instalada para iniciar.";
    }

    const start = document.getElementById("server-start-btn");
    const stop = document.getElementById("server-stop-btn");
    const restart = document.getElementById("server-restart-btn");
    const test = $("[data-rubymc-runtime-action='test']");

    if (start) start.textContent = isBedrock ? "▶ Iniciar Bedrock" : "▶ Iniciar Java";
    if (stop) stop.textContent = isBedrock ? "⏹ Parar Bedrock" : "⏹ Parar Java";
    if (restart) restart.textContent = isBedrock ? "🔄 Reiniciar Bedrock" : "🔄 Reiniciar Java";
    if (test) test.textContent = isBedrock ? "Testar Bedrock" : "Testar Java";

    setText("server-live-version", selectedVersion() || "--");
  }

  async function loadJavaVersions() {
    const data = await apiGet("/api/versions");
    if (data.ok === false) throw new Error(data.error || "Falha ao carregar versões Java.");

    const installed = data.installed || [];
    const active = data.active || null;
    cachedJavaVersions = installed;

    return { installed, active };
  }

  async function loadBedrockVersions() {
    const data = await apiGet("/api/bedrock/servers/installed");
    if (data.ok === false) throw new Error(data.error || "Falha ao carregar servidores Bedrock.");

    const servers = data.servers || [];
    cachedBedrockServers = servers;
    const running = servers.find((server) => server.running);

    return { servers, active: running || servers[0] || null };
  }

  async function loadVersionsForCurrentType() {
    ensureServerSelectorBox();
    const select = document.getElementById("server-runtime-version");
    const help = document.getElementById("server-runtime-help");
    if (!select) return;

    const type = currentType();
    const previous = type === "bedrock"
      ? localStorage.getItem(STORAGE_BEDROCK_VERSION_KEY)
      : localStorage.getItem(STORAGE_JAVA_VERSION_KEY);

    select.innerHTML = '<option value="">Carregando...</option>';

    try {
      if (type === "bedrock") {
        const { servers, active } = await loadBedrockVersions();
        if (!servers.length) {
          select.innerHTML = '<option value="">Nenhum servidor Bedrock instalado</option>';
          if (help) help.textContent = "Baixe uma versão BDS na seção Bedrock antes de iniciar.";
          updateRuntimeLabels();
          return;
        }

        select.innerHTML = servers.map((server) => {
          const version = server.version || server.id || "";
          const selected = previous === version || (!previous && active && active.version === version) ? "selected" : "";
          const state = server.running ? "online" : "instalado";
          return `<option value="${esc(version)}" data-loader="bedrock" ${selected}>${esc(version)} (${state})</option>`;
        }).join("");

        if (help) {
          help.textContent = active?.running
            ? `Bedrock ativo: ${active.version} — PID ${active.pid || "?"}.`
            : "Escolha uma versão Bedrock/BDS instalada para iniciar.";
        }
      } else {
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
      port: DEFAULT_JAVA_PORT,
      wait_timeout: 60
    };
  }

  function bedrockPayload() {
    const version = selectedVersion();

    return {
      version,
      version_id: version,
      server_version_id: version,
      bedrock_version: version,
      start_only_server: true,
      host: "0.0.0.0",
      port: DEFAULT_BEDROCK_PORT,
      wait_timeout: 45
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

  async function runBedrockAction(action) {
    const payload = bedrockPayload();
    const version = payload.version;

    if ((action === "start" || action === "restart") && !version) {
      throw new Error("Escolha uma versão Bedrock/BDS antes de iniciar.");
    }

    if (action === "start") {
      return firstSuccessful([
        () => apiPost("/api/server/bedrock/start", payload),
        () => apiPost("/api/bedrock/servers/start", { version })
      ]);
    }

    if (action === "stop") {
      return firstSuccessful([
        () => apiPost("/api/server/bedrock/stop", payload),
        () => apiPost("/api/bedrock/servers/stop", { version })
      ]);
    }

    if (action === "restart") {
      return firstSuccessful([
        () => apiPost("/api/server/bedrock/restart", payload),
        async () => {
          await apiPost("/api/bedrock/servers/stop", { version }).catch(() => {});
          await sleep(1200);
          return apiPost("/api/bedrock/servers/start", { version });
        }
      ]);
    }

    if (action === "test" || action === "status") {
      return firstSuccessful([
        () => action === "test" ? apiPost("/api/server/bedrock/test", payload) : apiGet("/api/server/bedrock/status"),
        async () => {
          const data = await loadBedrockVersions();
          const running = data.servers.find((server) => server.running && (!version || server.version === version));
          if (running) {
            return {
              ok: true,
              running: true,
              version: running.version,
              pid: running.pid,
              message: `Servidor Bedrock ${running.version} está com processo ativo${running.pid ? ` (PID ${running.pid})` : ""}.`
            };
          }

          return {
            ok: false,
            running: false,
            message: "Nenhum servidor Bedrock ativo foi encontrado."
          };
        }
      ]);
    }

    throw new Error(`Ação Bedrock desconhecida: ${action}`);
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

  function applyResult(data, action, type) {
    const ok = data && data.ok !== false;
    const label = type === "bedrock" ? "Bedrock" : "Java";
    const message = data?.message || data?.error || `${label}: ${action} concluído.`;

    log(ok ? "OK" : "ERROR", message);

    setText("server-test-state", ok ? "OK" : "Erro");
    setText("server-test-detail", message);

    if (type === "bedrock") {
      // Bedrock UI is updated by refreshInstalledBedrockServers — do not touch shared elements
      if (data.log_tail) logBlock("LOG", data.log_tail);
      if (data.stdout_tail) logBlock("STDOUT", data.stdout_tail);
      return;
    }

    // Java-only: update shared elements
    setText("server-state", ok ? (data.running === false ? "Offline" : "Online") : "Erro");
    setText("server-live-version", data.version_id || data.active_version || selectedVersion() || "Java");
    setText("server-live-latency", data.port_open ? "TCP 25565 OK" : "TCP 25565");
    setText("server-players", "Java Server");
    if (data.pid) setText("server-live-checked", `PID ${data.pid}`);
    if (data.log_tail) logBlock("LOG", data.log_tail);
    if (data.stdout_tail) logBlock("STDOUT", data.stdout_tail);
  }

  async function runRuntimeAction(action, options = {}) {
    const type = currentType();
    const key = `${type}:${action}`;

    if (inFlight.has(key)) {
      if (!options.silent) log("WARN", `Ação ${action} do servidor ${type} já está em execução.`);
      return null;
    }

    inFlight.add(key);

    const labels = {
      java: {
        start: "Iniciando servidor Java...",
        stop: "Parando servidor Java...",
        restart: "Reiniciando servidor Java...",
        test: "Testando servidor Java...",
        status: "Consultando servidor Java..."
      },
      bedrock: {
        start: "Iniciando servidor Bedrock...",
        stop: "Parando servidor Bedrock...",
        restart: "Reiniciando servidor Bedrock...",
        test: "Testando servidor Bedrock...",
        status: "Consultando servidor Bedrock..."
      }
    };

    if (!options.silent) setBusy(labels[type]?.[action] || action, true);

    try {
      const data = type === "bedrock"
        ? await runBedrockAction(action)
        : await runJavaAction(action);

      if (!options.silent) applyResult(data, action, type);
      return data;
    } catch (error) {
      const data = error.data || {};
      const payload = { ok: false, message: error.message, ...data };
      if (!options.silent) applyResult(payload, action, type);
      throw error;
    } finally {
      inFlight.delete(key);
      if (!options.silent) setBusy("", false);
      if (["start", "stop", "restart"].includes(action)) {
        setTimeout(loadVersionsForCurrentType, 800);
        if (type === "bedrock") {
          setTimeout(() => window.dispatchEvent(new Event("bedrock-versions-changed")), 1000);
        } else {
          setTimeout(() => window.refreshServerLiveStatus?.(), 1500);
        }
      } else if (type === "bedrock" && ["test", "status"].includes(action)) {
        setTimeout(() => window.dispatchEvent(new Event("bedrock-versions-changed")), 500);
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

    window.addEventListener("bedrock-versions-changed", () => {
      if (currentType() === "bedrock") loadVersionsForCurrentType();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  window.currentType = currentType;
})();
