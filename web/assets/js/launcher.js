(()=>{const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>Array.from(r.querySelectorAll(s));let busy=false;const ROUTES={status:["/api/status","/status"],logs:["/api/logs","/logs"],modpackImport:["/api/modpacks/import","/api/import_modpack","/api/modpack/import"],modpacks:["/api/modpacks","/api/modpacks/list"]};const ACTION_ALIASES={play:["play","start_minecraft","launch_minecraft"],update_modpacks:["update_modpacks","refresh_modpacks","list_modpacks"],validate_discord:["validate_discord","discord_validate","validate_discord_settings"],test_discord_logs:["test_discord_logs","discord_test_logs","test_logs_channel"],test_server:["test_server","server_test","check_server"],join_server:["join_server","server_join"],clear_display:["clear_display","display_clear"],run_tests:["run_tests","test"],organize_project:["organize_project","organize"],open_project_folder:["open_project_folder","project_folder"],open_docs:["open_docs","docs"],check_updates:["check_updates","update_check"],refresh_status:["refresh_status","status"]};function time(){return new Date().toLocaleTimeString("pt-BR",{hour12:false})}function log(t,m){const d=$("#display-log");if(!d)return;d.textContent+=`\n[${time()}] ${String(t).padEnd(7)} ${m}`;d.scrollTop=d.scrollHeight}function activateTab(tab){document.body.dataset.currentTab=tab;$$('.tab-link').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));$$('.tab-panel').forEach(p=>p.classList.toggle('active',p.id===`tab-${tab}`));const p=$(`#tab-${tab}`);if(p)document.title=`RubyMC Launcher — ${p.dataset.panelTitle||tab}`}async function fetchJson(url,opt={}){const r=await fetch(url,{headers:{Accept:'application/json',...(opt.headers||{})},...opt});if(!r.ok){const b=await r.text().catch(()=>"");throw new Error(`${r.status} ${r.statusText}${b?` — ${b.slice(0,160)}`:""}`)}return r.json()}async function postJson(url,payload={}){return fetchJson(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)})}async function firstGet(urls){let e;for(const u of urls){try{return await fetchJson(u)}catch(err){e=err}}throw e}function payload(action){return{action,profile:$('#profile-select')?.value||'vanilla',modpack_name:$('#modpack-name')?.value||'',server_address:$('#server-address')?.value||'',settings:{version:$('#settings-version')?.value||'',ram:$('#settings-ram')?.value||''}}}async function backendAction(action){let e;for(const a of ACTION_ALIASES[action]||[action]){try{return await postJson('/api/action',payload(a))}catch(err){e=err}try{return await postJson(`/api/${a}`,payload(a))}catch(err){e=err}}throw e}async function runAction(action){if(!action||busy)return;busy=true;log('ACTION',`Executando: ${action}`);try{if(action==='import_modpack')await importModpack();else if(action==='update_modpacks')await updateModpacks();else if(action==='clear_display'){clearDisplay();try{applyResult(await backendAction(action),action)}catch(_){}}else applyResult(await backendAction(action),action)}catch(e){log('ERROR',`${action}: ${e.message}`)}finally{busy=false}}async function importModpack(){const input=$('#modpack-file'),nameInput=$('#modpack-name');if(!input?.files?.length){log('WARN','Selecione um arquivo .mrpack ou .zip.');activateTab('modpacks');return}const file=input.files[0],profileName=nameInput?.value?.trim()||file.name.replace(/\.(mrpack|zip)$/i,'');const form=new FormData();form.append('file',file);form.append('modpack',file);form.append('profile_name',profileName);form.append('name',profileName);let last;for(const url of ROUTES.modpackImport){try{applyResult(await fetchJson(url,{method:'POST',body:form}),'import_modpack');await updateModpacks(false);return}catch(e){last=e}}try{applyResult(await backendAction('import_modpack'),'import_modpack');await updateModpacks(false)}catch(_){throw last}}async function updateModpacks(show=true){if(show)log('ACTION','Atualizando lista de modpacks...');for(const url of ROUTES.modpacks){try{const r=await fetchJson(url),m=r.modpacks||r.data||r;renderModpacks(Array.isArray(m)?m:[]);if(show)log('OK','Lista de modpacks atualizada.');return}catch(_){}}applyResult(await backendAction('update_modpacks'),'update_modpacks')}function clearDisplay(){const d=$('#display-log');if(d)d.textContent=`[${time()}] SYSTEM  Display limpo. Aguardando novos eventos...`;activateTab('display')}function applyResult(r,action){if(!r){log('OK',`${action} concluído.`);return}if(typeof r==='string'){log('OK',r);return}if(r.message)log(r.ok===false?'ERROR':'OK',r.message);if(Array.isArray(r.logs))r.logs.forEach(i=>typeof i==='string'?log('LOG',i):log(i.type||'LOG',i.message||JSON.stringify(i)));if(r.display)updateDisplay(r.display);if(r.status)applyStatus(r.status);else applyStatus(r);if(r.modpacks)renderModpacks(r.modpacks);if(r.discord)applyStatus({discord:r.discord});if(action==='test_server'&&r.ok!==undefined){setText('server-test-state',r.ok?'Online':'Offline');setText('server-test-detail',r.message||'')}}function setText(id,v){const e=document.getElementById(id);if(e&&v!==undefined&&v!==null&&v!=='')e.textContent=v}function setValue(id,v){const e=document.getElementById(id);if(e&&v!==undefined&&v!==null&&v!=='')e.value=v}function applyStatus(s={}){setText('minecraft-version',s.minecraft_version||s.default_version||s.version);setText('active-profile',s.active_profile||s.profile);setText('server-state',s.server_status||s.server_state||s.server);setText('server-players',s.server_players||s.players);setText('launcher-state',s.launcher_status||s.status);setText('launcher-version',s.launcher_version||s.version);setValue('server-address',s.server_address||s.community_server||s.address);if(s.server_test){setText('server-test-state',s.server_test.ok?'Online':'Offline');setText('server-test-detail',s.server_test.message||'')}const d=s.discord||{};if(Object.keys(d).length){const on=d.bot_enabled===true||d.bot===true||d.status==='ativo'||d.bot_state==='ativo';setText('discord-bot-state',on?'Ativo':(d.bot_state||'Inativo'));setText('discord-channel-count',d.channels||d.channel_count||d.channels_count);setText('discord-role-count',d.roles||d.role_count||d.roles_count);setText('logs-channel-state',d.logs_channel||d.logs_channel_id?'configurado':'pendente');setText('discord-config-state',d.configured===false?'pendente':'configurado')}}function renderModpacks(m){const list=$('#modpack-list'),select=$('#profile-select');if(!list)return;if(!Array.isArray(m)||!m.length){list.textContent='Nenhum modpack importado ainda.';return}list.innerHTML=m.map(i=>{const n=typeof i==='string'?i:(i.name||i.profile||i.title||'Modpack'),v=typeof i==='object'&&i.version?i.version:'';return `<div class="modpack-row"><strong>${esc(n)}</strong><span>${esc(v)}</span></div>`}).join('');if(select){const cur=select.value;select.innerHTML='<option value="vanilla">Vanilla / sem modpack</option>'+m.map(i=>{const n=typeof i==='string'?i:(i.name||i.profile||i.title||'Modpack');return `<option value="${esc(n)}">${esc(n)}</option>`}).join('');if([...select.options].some(o=>o.value===cur))select.value=cur}}function updateDisplay(c){const d=$('#display-log');if(!d)return;d.textContent=Array.isArray(c)?c.join('\n'):String(c);d.scrollTop=d.scrollHeight}function esc(v){return String(v).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;')}async function refreshStatus(){try{applyStatus((await firstGet(ROUTES.status)).status||await firstGet(ROUTES.status))}catch(_){try{applyResult(await backendAction('refresh_status'),'refresh_status')}catch(_){log('WARN','Status será atualizado quando o backend responder.')}}}async function pollLogs(){try{const d=await firstGet(ROUTES.logs);if(d.display)updateDisplay(d.display);else if(d.logs)updateDisplay(d.logs)}catch(_){}}function bind(){ $$('.tab-link').forEach(b=>b.addEventListener('click',()=>activateTab(b.dataset.tab)));$$('[data-action]').forEach(b=>b.addEventListener('click',()=>runAction(b.dataset.action)));$$('.toggle').forEach(t=>t.addEventListener('click',()=>{t.classList.toggle('active');log('ACTION',`Configuração alterada: ${t.dataset.toggle}`)}));const f=$('#modpack-file'),l=$('#modpack-file-label');if(f&&l)f.addEventListener('change',()=>{l.textContent=f.files&&f.files[0]?f.files[0].name:'Clique para escolher ou arraste o arquivo aqui'})}document.addEventListener('DOMContentLoaded',()=>{document.body.dataset.currentTab='home';bind();log('SYSTEM','Aba Configurações atualizada no estilo RubyMC. Interface pronta.');refreshStatus();updateModpacks(false).catch(()=>{});setInterval(pollLogs,4000)})})();


/* =========================================================
   RubyMC Server Live Status Patch
   Consulta /api/server/status e atualiza a aba Servidor.
   ========================================================= */
(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const ROUTES = ["/api/server/status", "/api/server/live"];
  let serverPollTimer = null;

  function time() {
    return new Date().toLocaleTimeString("pt-BR", { hour12: false });
  }

  function log(type, message) {
    const display = $("#display-log");
    if (!display) return;
    display.textContent += `\n[${time()}] ${String(type).padEnd(7)} ${message}`;
    display.scrollTop = display.scrollHeight;
  }

  function setText(id, value) {
    const element = document.getElementById(id);
    if (element && value !== undefined && value !== null && value !== "") element.textContent = value;
  }

  function setClass(id, className, enabled) {
    const element = document.getElementById(id);
    if (element) element.classList.toggle(className, enabled);
  }

  async function fetchJson(url) {
    const response = await fetch(url, { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
    return response.json();
  }

  async function getServerLiveStatus() {
    let lastError;
    for (const route of ROUTES) {
      try {
        return await fetchJson(`${route}?t=${Date.now()}`);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  function normalize(payload) {
    const live = payload.server_live || payload.live || payload.status || payload;
    const players = live.players || {};
    return {
      ok: live.ok === true || live.online === true,
      online: live.online === true,
      address: live.address || payload.server?.address || "",
      latency: live.latency_ms,
      version: live.version?.name || live.version_name || "",
      description: live.description || "",
      checkedAt: live.checked_at || payload.time || time(),
      error: live.error || payload.error || "",
      playersOnline: Number(players.online || live.players_online || live.online_players || 0),
      playersMax: Number(players.max || live.players_max || live.max_players || 0),
      sample: Array.isArray(players.sample) ? players.sample : []
    };
  }

  function playerRatio(status) {
    if (!status.playersMax) return `${status.playersOnline || 0} jogadores`;
    return `${status.playersOnline}/${status.playersMax} jogadores`;
  }

  function renderPlayers(names) {
    const target = $("#server-player-tags");
    if (!target) return;
    if (!names || names.length === 0) {
      target.innerHTML = '<span class="server-player-tag">Nenhum nome público retornado</span>';
      return;
    }
    target.innerHTML = names.slice(0, 12).map(name => `<span class="server-player-tag">${escapeHtml(name)}</span>`).join("");
  }

  function updateServerUi(status) {
    const online = status.online;
    setText("server-test-state", online ? "Online" : "Offline");
    setText("server-test-detail", online
      ? `Servidor respondeu em ${status.latency ?? "--"} ms. ${playerRatio(status)}.`
      : (status.error || "Servidor não respondeu ou não está configurado.")
    );
    setText("server-live-online", online ? `${status.playersOnline}` : "0");
    setText("server-live-max", status.playersMax ? `${status.playersMax}` : "--");
    setText("server-live-latency", status.latency ? `${status.latency} ms` : "--");
    setText("server-live-version", status.version || "--");
    setText("server-live-checked", status.checkedAt || "--");
    setText("server-overlay-status", online ? "Online" : "Offline");
    setText("server-overlay-players", playerRatio(status));
    setText("server-overlay-ping", status.latency ? `${status.latency} ms` : "--");
    setText("server-state", online ? "Online" : "Offline");
    setText("server-players", playerRatio(status));
    setClass("server-test-state", "server-live-error", !online);

    const motd = $("#server-motd");
    if (motd) motd.textContent = status.description || (online ? "Servidor online." : "Sem descrição disponível.");

    renderPlayers(status.sample);

    if (online) {
      log("OK", `Servidor online: ${playerRatio(status)} | ping ${status.latency ?? "--"} ms`);
    } else {
      log("WARN", `Servidor offline/indisponível: ${status.error || "sem resposta"}`);
    }
  }

  function setLoading() {
    setText("server-test-state", "Consultando...");
    setText("server-test-detail", "Buscando status, versão, ping e jogadores online.");
  }

  async function refreshServerLiveStatus() {
    setLoading();
    try {
      const data = await getServerLiveStatus();
      updateServerUi(normalize(data));
    } catch (error) {
      updateServerUi({
        online: false,
        playersOnline: 0,
        playersMax: 0,
        sample: [],
        error: `API de status indisponível: ${error.message}`,
        checkedAt: time()
      });
    }
  }

  function isServerTabActive() {
    const activeButton = $(".side-link.active, .tab-link.active");
    return activeButton?.dataset?.tab === "server" || $("#tab-server")?.classList.contains("active");
  }

  function bindTabState() {
    $$(".side-link, .tab-link").forEach(button => {
      button.addEventListener("click", () => {
        if (button.dataset.tab) {
          document.body.dataset.currentTab = button.dataset.tab;
          if (button.dataset.tab === "server") setTimeout(refreshServerLiveStatus, 120);
        }
      });
    });

    const active = $(".side-link.active, .tab-link.active");
    if (active?.dataset?.tab) document.body.dataset.currentTab = active.dataset.tab;
  }

  function bindServerButtons() {
    $$('[data-action="test_server"]').forEach(button => {
      button.addEventListener("click", () => setTimeout(refreshServerLiveStatus, 500));
    });
  }

  function startPolling() {
    if (serverPollTimer) clearInterval(serverPollTimer);
    serverPollTimer = setInterval(() => {
      if (isServerTabActive()) refreshServerLiveStatus();
    }, 15000);
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  document.addEventListener("DOMContentLoaded", () => {
    bindTabState();
    bindServerButtons();
    startPolling();
    if (isServerTabActive()) setTimeout(refreshServerLiveStatus, 400);
  });
})();


/* =========================================================
   RubyMC Backend Unknown Actions Frontend Guard
   ========================================================= */
(() => {
  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-action='clear_display']");
    if (!button) return;

    const display = document.getElementById("display-log");
    if (display) {
      display.textContent = "[SYSTEM] Display limpo. Aguardando novos eventos...";
    }
  });
})();
