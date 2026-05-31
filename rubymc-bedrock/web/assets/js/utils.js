(function(global) {
  "use strict";

  // --- DOM helpers ---
  global.$ = (selector, root) => (root || document).querySelector(selector);
  global.$$ = (selector, root) => Array.from((root || document).querySelectorAll(selector));

  function esc(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }
  global.esc = esc;
  global.escapeHtml = esc;

  function time() {
    return new Date().toLocaleTimeString("pt-BR", { hour12: false });
  }
  global.time = time;

  function log(type, message) {
    const d = global.$("#display-log");
    if (!d) return;
    d.textContent += "\n[" + time() + "] " + String(type).padEnd(7) + " " + message;
    d.scrollTop = d.scrollHeight;
  }
  global.log = log;

  function logBlock(type, text) {
    if (!text) return;
    const d = global.$("#display-log");
    if (!d) return;
    d.textContent += "\n[" + time() + "] " + String(type).padEnd(7) + " \u2500\u2500 LOG DO SERVIDOR \u2500\u2500\n" + text;
    d.scrollTop = d.scrollHeight;
  }
  global.logBlock = logBlock;

  function setText(id, value) {
    if (value === undefined || value === null || value === "") return;
    const el = document.getElementById(id) || global.$("#" + id);
    if (el) el.textContent = String(value);
  }
  global.setText = setText;

  function setTextAll(ids, value) {
    ids.forEach((id) => setText(id, value));
  }
  global.setTextAll = setTextAll;

  function setValue(id, value) {
    if (value === undefined || value === null || value === "") return;
    const el = document.getElementById(id);
    if (el) el.value = String(value);
  }
  global.setValue = setValue;

  function setBusy(button, busy, label) {
    if (!button) return;
    button.disabled = busy;
    button.classList.toggle("is-loading", busy);
    if (label) button.textContent = busy ? "Processando..." : label;
  }
  global.setBusy = setBusy;

  function sleep(ms) {
    return new Promise(function(resolve) { setTimeout(resolve, ms); });
  }
  global.sleep = sleep;

  // --- API helpers ---

  async function safeJson(response, endpoint) {
    const text = await response.text();
    if (!text.trim()) throw new Error("Resposta vazia do servidor em " + endpoint);
    let data;
    try { data = JSON.parse(text); }
    catch (e) { throw new Error("JSON inv\u00e1lido de " + endpoint + ": " + e.message); }
    if (!response.ok || data.ok === false) {
      throw new Error(data.error || data.message || ("HTTP " + response.status + " em " + endpoint));
    }
    return data;
  }
  global.safeJson = safeJson;

  async function apiFetch(url, opts) {
    var r = await fetch(url, {
      headers: { Accept: "application/json" },
      ...(opts || {})
    });
    return safeJson(r, url);
  }
  global.apiFetch = apiFetch;

  async function apiPost(url, payload) {
    return apiFetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload || {})
    });
  }
  global.apiPost = apiPost;

  async function apiGet(url) {
    return apiFetch(url);
  }
  global.apiGet = apiGet;

  async function getJson(endpoint) {
    return safeJson(await fetch(endpoint, { headers: { Accept: "application/json" } }), endpoint);
  }
  global.getJson = getJson;

  async function postJson(endpoint, payload) {
    return safeJson(await fetch(endpoint, {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify(payload || {})
    }), endpoint);
  }
  global.postJson = postJson;

  async function firstGet(urls) {
    let lastError;
    for (const url of urls) {
      try {
        return await apiFetch(url);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }
  global.firstGet = firstGet;

  async function firstSuccessful(calls) {
    let lastError;
    for (const call of calls) {
      try {
        return await call();
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError || new Error("Nenhuma rota dispon\u00edvel.");
  }
  global.firstSuccessful = firstSuccessful;

  // --- Namespace ---
  global.RubyMC = global.RubyMC || {};
  Object.assign(global.RubyMC, {
    $: global.$, $$: global.$$, esc, time, log, logBlock,
    setText, setValue, setBusy, sleep,
    safeJson, apiFetch, apiPost, apiGet, getJson, postJson,
    firstGet, firstSuccessful
  });
})(window);
