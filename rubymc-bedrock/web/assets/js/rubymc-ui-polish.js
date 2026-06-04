/* RubyMC UI Polish: abas + transição suave de fundos */
(() => {
  "use strict";

  const BG_BY_TAB = {
    home: "/assets/img/rubymc-tela-inicio.png",
    modpacks: "/assets/img/rubymc-modpacks.png",
    server: "/assets/img/rubymc-servidor-comunidade.png",
    discord: "/assets/img/rubymc-discord-bot.png",
    display: "/assets/img/rubymc-display-logs.png",
    project: "/assets/img/rubymc-projeto.png",
    settings: "/assets/img/rubymc-configuracoes.png"
  };

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  let currentLayer = 0;

  function ensureLayers() {
    const content = $(".app-content");
    if (!content) return null;

    let a = $(".rubymc-bg-layer-a", content);
    let b = $(".rubymc-bg-layer-b", content);

    if (!a) {
      a = document.createElement("div");
      a.className = "rubymc-bg-layer rubymc-bg-layer-a is-visible";
      content.prepend(a);
    }

    if (!b) {
      b = document.createElement("div");
      b.className = "rubymc-bg-layer rubymc-bg-layer-b";
      content.prepend(b);
    }

    return [a, b];
  }

  function setBackground(tab, instant = false) {
    const layers = ensureLayers();
    if (!layers) return;

    const image = BG_BY_TAB[tab] || BG_BY_TAB.home;
    const active = layers[currentLayer];
    const next = layers[1 - currentLayer];

    if (instant) {
      active.style.backgroundImage = `url("${image}")`;
      active.classList.add("is-visible");
      next.classList.remove("is-visible");
      document.body.dataset.currentTab = tab;
      return;
    }

    next.style.backgroundImage = `url("${image}")`;
    next.classList.add("is-visible");
    active.classList.remove("is-visible");
    currentLayer = 1 - currentLayer;
    document.body.dataset.currentTab = tab;
  }

  function activateTab(tab, instant = false) {
    if (!tab) return;

    $$(".side-link, .tab-link").forEach((button) => {
      button.classList.toggle("active", button.dataset.tab === tab);
    });

    $$(".tab-panel").forEach((panel) => {
      const isActive = panel.id === `tab-${tab}`;
      panel.classList.toggle("active", isActive);
      panel.setAttribute("aria-hidden", isActive ? "false" : "true");
    });

    setBackground(tab, instant);
  }

  function bindTabs() {
    $$(".side-link, .tab-link").forEach((button) => {
      if (button.dataset.rubymcPolishBound === "1") return;
      button.dataset.rubymcPolishBound = "1";
      button.addEventListener("click", (event) => {
        event.preventDefault();
        activateTab(button.dataset.tab);
      });
    });

    $$("[data-tab-jump]").forEach((button) => {
      if (button.dataset.rubymcPolishJumpBound === "1") return;
      button.dataset.rubymcPolishJumpBound = "1";
      button.addEventListener("click", (event) => {
        event.preventDefault();
        activateTab(button.dataset.tabJump);
      });
    });
  }

  function syncDiscordHealth() {
    const health = $("#discord-panel-health");
    const botState = $("#discord-bot-state");
    const channelCount = $("#discord-channel-count");
    const roleCount = $("#discord-role-count");

    const update = () => {
      if (!health) return;
      const bot = botState ? botState.textContent.trim().toLowerCase() : "";
      const channels = channelCount ? channelCount.textContent.trim() : "";
      const roles = roleCount ? roleCount.textContent.trim() : "";

      const hasData = (bot && bot !== "inativo" && bot !== "--") || (channels && channels !== "--/--") || (roles && roles !== "--/--");
      health.textContent = hasData ? "Online" : "Aguardando";
    };

    update();
    const observer = new MutationObserver(update);
    [botState, channelCount, roleCount].filter(Boolean).forEach((node) => {
      observer.observe(node, { childList: true, characterData: true, subtree: true });
    });
  }

  function init() {
    bindTabs();
    const activePanel = $(".tab-panel.active");
    activateTab(activePanel ? activePanel.id.replace(/^tab-/, "") : "home", true);
    syncDiscordHealth();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();

  window.RubyMCUI = { activateTab, setBackground };
})();
