/* RubyMC Force Layout Runtime Fix */
(function () {
  function removeBadInlineScale() {
    document.documentElement.style.zoom = "1";
    document.body.style.zoom = "1";
    document.documentElement.style.transform = "none";
    document.body.style.transform = "none";

    document.querySelectorAll("[style]").forEach(function (el) {
      var s = el.getAttribute("style") || "";
      if (/zoom\s*:\s*0|zoom\s*:\s*\./i.test(s) || /scale\s*\(\s*0|scale\s*\(\s*\./i.test(s)) {
        el.style.zoom = "1";
        el.style.transform = "none";
      }
      if (/font-size\s*:\s*0/i.test(s)) {
        el.style.fontSize = "";
      }
    });
  }

  function ensureShell() {
    var shell =
      document.querySelector(".rubymc-shell") ||
      document.querySelector(".launcher-shell") ||
      document.querySelector(".launcher-root") ||
      document.querySelector("#app") ||
      document.querySelector(".app");

    if (shell) {
      shell.classList.add("rubymc-force-shell");
    }

    var win =
      document.querySelector(".launcher-window") ||
      document.querySelector(".app-window") ||
      document.querySelector(".main-window") ||
      document.querySelector(".window");

    if (win) {
      win.classList.add("rubymc-force-window");
    }
  }

  function syncCurrentTab() {
    var active =
      document.querySelector(".tab-panel.active") ||
      document.querySelector(".page-panel.active") ||
      document.querySelector("section.active[id]");

    if (active && active.id) {
      document.body.dataset.currentTab = active.id.replace(/^tab-/, "");
    }
  }

  function boot() {
    removeBadInlineScale();
    ensureShell();
    syncCurrentTab();

    document.body.classList.add("rubymc-force-layout-fix");

    document.addEventListener("click", function (ev) {
      var target = ev.target.closest("[data-tab], .tab-link, .nav-item");
      if (!target) return;
      setTimeout(syncCurrentTab, 40);
      setTimeout(removeBadInlineScale, 60);
    });

    var observer = new MutationObserver(function () {
      removeBadInlineScale();
      ensureShell();
      syncCurrentTab();
    });

    observer.observe(document.body, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["style", "class"]
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
