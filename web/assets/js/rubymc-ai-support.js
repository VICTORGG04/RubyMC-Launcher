(function() {
  let chatHistory = [];
  let isWaiting = false;
  let lastContext = null;

  const BOT_AVATAR = '\u{1F916}';
  const USER_AVATAR = '\u{1F464}';

  function log(msg) {
    window.log("AI", msg);
  }

  function renderMarkdown(text) {
    let html = esc(text);
    html = html.replace(/```(\w*)\n([\s\S]*?)```/g, '<pre><code>$2</code></pre>');
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    html = html.replace(/\n/g, '<br>');
    return html;
  }

  function addMessage(role, content) {
    chatHistory.push({ role: role, content: content });
    renderMessages();
  }

  function renderMessages() {
    const container = $('#ai-chat-messages');
    if (!container) return;

    container.innerHTML = chatHistory.map(function(msg) {
      var isBot = msg.role === 'bot' || msg.role === 'assistant';
      var avatar = isBot ? BOT_AVATAR : USER_AVATAR;
      var cls = isBot ? 'ai-bot-message' : 'ai-user-message';
      var bubbleContent = isBot ? renderMarkdown(msg.content) : esc(msg.content);
      return (
        '<div class="ai-message ' + cls + '">' +
          '<div class="ai-avatar">' + avatar + '</div>' +
          '<div class="ai-bubble">' + bubbleContent + '</div>' +
        '</div>'
      );
    }).join('');

    container.scrollTop = container.scrollHeight;
  }

  function showTyping() {
    const container = $('#ai-chat-messages');
    if (!container) return;

    const typingEl = document.createElement('div');
    typingEl.className = 'ai-message ai-bot-message ai-typing';
    typingEl.id = 'ai-typing-indicator';
    typingEl.innerHTML =
      '<div class="ai-avatar">' + BOT_AVATAR + '</div>' +
      '<div class="ai-bubble">IA está pensando...</div>';
    container.appendChild(typingEl);
    container.scrollTop = container.scrollHeight;
  }

  function hideTyping() {
    const el = $('#ai-typing-indicator');
    if (el) el.remove();
  }

  async function sendMessage() {
    if (isWaiting) return;

    const input = $('#ai-chat-input');
    if (!input) return;

    var text = input.value.trim();
    if (!text) return;

    input.value = '';
    input.style.height = 'auto';

    addMessage('user', text);
    isWaiting = true;
    showTyping();
    log('Pergunta: ' + text.substring(0, 80));

    try {
      var payload = { message: text };
      if (lastContext) {
        payload.context = lastContext;
      }

      var resp = await fetch('/api/ai/support', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(payload)
      });
      var data = await resp.json();

      hideTyping();

      if (data.answer) {
        addMessage('bot', data.answer);
        log('Resposta recebida (' + (data.model || '?') + ')');
      } else {
        addMessage('bot', data.message || 'Sem resposta.');
        log('ERRO: ' + (data.message || 'Sem resposta'));
      }
    } catch (err) {
      hideTyping();
      addMessage('bot', 'Erro ao consultar a IA: ' + err.message);
      log('ERRO: ' + err.message);
    } finally {
      isWaiting = false;
    }
  }

  function updateContextDisplay(data) {
    var el = $('#ai-context-display');
    if (!el) return;

    if (!data || !data.ok) {
      el.innerHTML = '<span style="color:#ff6b8f">Contexto indisponível</span>';
      return;
    }

    lastContext = data;
    var lines = [];

    var dc = data.discord;
    if (dc) {
      var botState = dc.bot_enabled ? '\u2705' : '\u274C';
      lines.push(botState + ' Discord: ' + (dc.channels_configured || '?') + '/' + (dc.channels_total || '?') + ' canais, ' + (dc.roles_configured || '?') + '/' + (dc.roles_total || '?') + ' cargos');
    } else {
      lines.push('\u274C Discord: não configurado');
    }

    var mods = data.modpacks;
    if (mods && mods.length > 0) {
      lines.push('\u{1F4E6} Modpacks: ' + mods.length + ' (' + mods.map(function(m) { return m.name || m.id; }).join(', ') + ')');
    } else {
      lines.push('\u{1F4E6} Modpacks: nenhum');
    }

    var srv = data.server;
    if (srv && srv.address && srv.address !== 'não configurado') {
      lines.push('\uD83C\uDF10 Servidor: ' + srv.address);
    } else {
      lines.push('\uD83C\uDF10 Servidor: não configurado');
    }

    var logs = data.logs;
    if (logs && logs.length > 0) {
      var errors = logs.filter(function(l) { return l.indexOf('ERROR') >= 0 || l.indexOf('WARN') >= 0; });
      if (errors.length > 0) {
        lines.push('\u26A0\uFE0F ' + errors.length + ' avisos/erros no display');
        errors.slice(0, 3).forEach(function(e) {
          e = e.replace(/\[.*?\]/, '').trim();
          if (e.length > 60) e = e.substring(0, 60) + '...';
          lines.push('  ' + e);
        });
      } else {
        lines.push('\u2705 Nenhum erro recente');
      }
    } else {
      lines.push('\u2705 Nenhum erro recente');
    }

    el.innerHTML = lines.join('<br>');
  }

  async function refreshContext() {
    var el = $('#ai-context-display');
    if (el) el.innerHTML = '<span style="color:#8a9abc">Atualizando...</span>';

    try {
      var resp = await fetch('/api/ai/context?t=' + Date.now(), {
        headers: { 'Accept': 'application/json' }
      });
      var data = await resp.json();
      updateContextDisplay(data);
    } catch (err) {
      if (el) el.innerHTML = '<span style="color:#ff6b8f">Erro ao carregar contexto: ' + err.message + '</span>';
    }
  }

  function setupAIHandlers() {
    var sendBtn = $('#ai-chat-send');
    var input = $('#ai-chat-input');
    var refreshBtn = $('#ai-refresh-context');
    var messages = $('#ai-chat-messages');

    if (sendBtn) sendBtn.addEventListener('click', sendMessage);
    if (refreshBtn) refreshBtn.addEventListener('click', refreshContext);

    if (input) {
      input.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          sendMessage();
        }
      });

      input.addEventListener('input', function() {
        this.style.height = 'auto';
        this.style.height = Math.min(this.scrollHeight, 120) + 'px';
      });
    }

    if (messages && messages.children.length === 0) {
      addMessage('bot', 'Ol\u00E1! Sou o assistente IA do RubyMC. Pergunte sobre Discord, modpacks, servidor ou configura\u00E7\u00F5es do projeto.');
    }
  }

  var tabCheckInterval = setInterval(function() {
    var aiTab = $('#tab-ai');
    if (aiTab) {
      setupAIHandlers();
      refreshContext();
      clearInterval(tabCheckInterval);
    }
  }, 200);

  setTimeout(function() { clearInterval(tabCheckInterval); }, 10000);

  var originalActivateTab = window.activateTab || null;
  var origBind = document.addEventListener;
  document.addEventListener('tab-changed', function(e) {
    if (e.detail === 'ai') {
      refreshContext();
    }
  });

  var tabObserver = new MutationObserver(function() {
    var aiPanel = $('#tab-ai');
    if (aiPanel && aiPanel.classList.contains('active')) {
      refreshContext();
    }
  });
  document.addEventListener('DOMContentLoaded', function() {
    var aiPanel = $('#tab-ai');
    if (aiPanel) {
      tabObserver.observe(aiPanel, { attributes: true, attributeFilter: ['class'] });
    }
  });
})();
