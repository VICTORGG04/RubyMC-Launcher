/* RubyMC Emergency UI Restore */
(function () {
  function detectTabName(panel) {
    if (!panel || !panel.id) return "home";
    return panel.id.replace(/^tab-/, "").replace(/^section-/, "") || "home";
  }

  function setCurrentTab(name) {
    document.body.dataset.currentTab = name || "home";
    document.body.classList.add("rubymc-ui-restored");
  }

  function syncActiveTab() {
    var activePanel =
      document.querySelector(".tab-panel.active") ||
      document.querySelector(".page-panel.active") ||
      document.querySelector("[id^='tab-'].active");

    setCurrentTab(detectTabName(activePanel));
  }

  function bindTabs() {
    document.querySelectorAll("[data-tab], .tab-link").forEach(function (btn) {
      if (btn.dataset.rubymcBound === "1") return;
      btn.dataset.rubymcBound = "1";

      btn.addEventListener("click", function () {
        var tab = btn.dataset.tab || btn.getAttribute("href") || "";
        tab = tab.replace("#", "").replace(/^tab-/, "");
        if (tab) {
          setTimeout(function () { setCurrentTab(tab); }, 20);
          setTimeout(syncActiveTab, 80);
        }
      });
    });
  }

  function fixBrokenInlineStyles() {
    document.querySelectorAll("font, center").forEach(function (el) {
      el.style.fontFamily = "";
      el.style.fontSize = "";
    });
  }

  function boot() {
    bindTabs();
    syncActiveTab();
    fixBrokenInlineStyles();

    var observer = new MutationObserver(function () {
      bindTabs();
      syncActiveTab();
    });

    observer.observe(document.body, {
      subtree: true,
      attributes: true,
      attributeFilter: ["class"]
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
