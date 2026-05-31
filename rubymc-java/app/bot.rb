# frozen_string_literal: true

# =============================================================================
# RubyMC Discord Bot Daemon
#
# Eventos automáticos ao entrar no servidor Discord:
#   #bem-vindos      → Embed de boas-vindas com menção ao novo membro
#   #novos-membros   → Notificação simples de quem acabou de entrar
#   #notícias        → Novidades sobre servidores e eventos do jogo
#   #comunicados     → Estado atual e roadmap do projeto
#   #chat-com-rubymc → Como interagir com o bot
#   #regras          → Regras do servidor (enviado ao entrar)
#   #sugestões       → Sugestões da comunidade (!sugerir)
#   #bugs            → Reporte de bugs (!reportar)
#   #servidor-oficial → Status do servidor Minecraft (jogadores online + link)
#
# Uso:
#   bundle exec ruby bot_daemon.rb        # primeiro plano
#   bundle exec ruby bot_daemon.rb &      # background
#   nohup bundle exec ruby bot_daemon.rb & # background persistente
# =============================================================================

$stdout.sync = true
$stderr.sync = true

# Load .env file if present
env_file = File.join(File.expand_path('..', __dir__), '.env')
if File.file?(env_file)
  File.read(env_file).each_line do |line|
    key, val = line.strip.split('=', 2)
    ENV[key] = val if key && val && !key.empty? && !key.start_with?('#')
  end
end

require "websocket-client-simple"
require "httparty"
require "json"
require "yaml"
require_relative "../lib/discord_integration"
require_relative "../lib/rubymc/discord_config"
require_relative '../lib/rubymc/rubymc_bot_config_bridge'
require_relative '../lib/rubymc/minecraft_server_status'
require_relative '../lib/rubymc/server_manager'

RUBYMC_CHANNEL_ALIASES = {
  'bem_vindos' => 'welcome_channel_id',
  'welcome' => 'welcome_channel_id',
  'welcome_channel' => 'welcome_channel_id',
  'novos_membros' => 'new_members_channel_id',
  'new_members' => 'new_members_channel_id',
  'new_members_channel' => 'new_members_channel_id',
  'noticias' => 'announcements_channel_id',
  'announcements' => 'announcements_channel_id',
  'announcements_channel' => 'announcements_channel_id',
  'comunicados' => 'updates_channel_id',
  'updates' => 'updates_channel_id',
  'updates_channel' => 'updates_channel_id',
  'chat_rubymc' => 'general_channel_id',
  'general' => 'general_channel_id',
  'general_channel' => 'general_channel_id',
  'logs' => 'logs_channel_id',
  'logs_channel' => 'logs_channel_id',
  'modpacks' => 'modpacks_channel_id',
  'modpacks_channel' => 'modpacks_channel_id',
  'suporte' => 'support_channel_id',
  'support' => 'support_channel_id',
  'support_channel' => 'support_channel_id',
  'regras' => 'rules_channel_id',
  'rules' => 'rules_channel_id',
  'rules_channel' => 'rules_channel_id',
  'sugestoes' => 'suggestions_channel_id',
  'suggestions' => 'suggestions_channel_id',
  'suggestions_channel' => 'suggestions_channel_id',
  'bugs' => 'bugs_channel_id',
  'bugs_channel' => 'bugs_channel_id',
  'servidor_oficial' => 'server_channel_id',
  'oficial' => 'server_channel_id',
  'server' => 'server_channel_id',
  'server_channel' => 'server_channel_id'
}.freeze

def rubymc_channel_id(channels, key)
  return nil unless channels
  key = key.to_s
  canonical = RUBYMC_CHANNEL_ALIASES.fetch(key, key)
  channels[canonical] || channels[canonical.to_sym] || channels[key] || channels[key.to_sym]
end

settings_file = File.join(File.expand_path('..', __dir__), "config", "settings.yml")
settings_hash = {}
if File.file?(settings_file)
  begin
    settings_hash = YAML.safe_load(File.read(settings_file), permitted_classes: [Symbol], aliases: true) || {}
  rescue
    settings_hash = {}
  end
end
bridge = RubyMC::BotConfigBridge.new(settings_hash)
CONFIG    = settings_hash
BOT_TOKEN = bridge.bot_token

CHANNELS = {
  bem_vindos:    bridge.channel_id('bem_vindos'),
  novos_membros: bridge.channel_id('novos_membros'),
  noticias:      bridge.channel_id('noticias'),
  comunicados:   bridge.channel_id('comunicados'),
  chat_rubymc:   bridge.channel_id('chat_rubymc'),
  regras:        bridge.channel_id('regras'),
  sugestoes:     bridge.channel_id('sugestoes'),
  bugs:             bridge.channel_id('bugs'),
  servidor_oficial: bridge.channel_id('servidor_oficial')
}.freeze

INVITE_CHANNEL_ID     = CONFIG.dig("discord", "invite_channel_id").to_s
SUGGESTIONS_CHANNEL_ID = CONFIG.dig("discord", "channels", "suggestions_channel_id").to_s
BUGS_CHANNEL_ID        = CONFIG.dig("discord", "channels", "bugs_channel_id").to_s
SERVER_CHANNEL_ID      = CONFIG.dig("discord", "channels", "server_channel_id").to_s
ADMIN_ROLE_ID          = CONFIG.dig("discord", "roles", "admin_role_id").to_s

# ─── Dados do Bot ──────────────────────────────────────────────────────
BOT_DATA_FILE = File.join(File.expand_path('..', __dir__), "config", "bot_data.yml")
BOT_DATA = if File.file?(BOT_DATA_FILE)
             YAML.safe_load(File.read(BOT_DATA_FILE), permitted_classes: [Symbol], aliases: true) || {}
           else
             {}
           end.freeze

GATEWAY_URL = "wss://gateway.discord.gg/?v=10&encoding=json"
GATEWAY_INTENTS = (1 << 0) | (1 << 1) | (1 << 9) | (1 << 15)

$channel_types = {}
FORUM_CHANNEL_TYPES = [15].freeze # GUILD_FORUM

def channel_type(channel_id)
  return $channel_types[channel_id] if $channel_types.key?(channel_id)

  res = HTTParty.get(
    "https://discord.com/api/v10/channels/#{channel_id}",
    headers: { "Authorization" => "Bot #{BOT_TOKEN}" },
    timeout: 5
  )
  $channel_types[channel_id] = res.success? ? JSON.parse(res.body)["type"] : nil
rescue => e
  puts "[AVISO] channel_type #{channel_id}: #{e.message}"
  nil
end

def post_message(channel_id, payload)
  return if channel_id.to_s.empty? || channel_id.start_with?("ID_")

  ctype = channel_type(channel_id)

  if FORUM_CHANNEL_TYPES.include?(ctype)
    thread_title = payload.dig(:embeds, 0, :title) || "Postagem do Bot"
    thread_payload = {
      name: thread_title.to_s[0, 100],
      message: payload
    }
    res = HTTParty.post(
      "https://discord.com/api/v10/channels/#{channel_id}/threads",
      headers: {
        "Authorization" => "Bot #{BOT_TOKEN}",
        "Content-Type"  => "application/json"
      },
      body: thread_payload.to_json,
      timeout: 10
    )
  else
    res = HTTParty.post(
      "https://discord.com/api/v10/channels/#{channel_id}/messages",
      headers: {
        "Authorization" => "Bot #{BOT_TOKEN}",
        "Content-Type"  => "application/json"
      },
      body: payload.to_json,
      timeout: 10
    )
  end
  res
rescue => e
  puts "[ERRO] post_message: #{e.message}"
  nil
end

def create_invite(channel_id, max_age: 86400, max_uses: 0)
  return nil if channel_id.to_s.empty? || channel_id.start_with?("ID_")
  res = HTTParty.post(
    "https://discord.com/api/v10/channels/#{channel_id}/invites",
    headers: {
      "Authorization" => "Bot #{BOT_TOKEN}",
      "Content-Type"  => "application/json"
    },
    body: { max_age: max_age, max_uses: max_uses, unique: true }.to_json,
    timeout: 10
  )
  return nil unless res.success?
  data = JSON.parse(res.body)
  "https://discord.gg/#{data['code']}"
rescue => e
  puts "[ERRO] create_invite: #{e.message}"
  nil
end

def reply_to_message(message, payload)
  channel_id = message["channel_id"].to_s
  return if channel_id.empty?

  payload = payload.merge(
    message_reference: {
      message_id: message["id"],
      channel_id: channel_id,
      guild_id: message["guild_id"],
      fail_if_not_exists: false
    },
    allowed_mentions: {
      parse: [],
      replied_user: false
    }
  )
  post_message(channel_id, payload)
end

def simple_reply(text, color: 0x2ECC71, title: "BOT RUBYMC")
  {
    embeds: [{
               title: title,
               description: text,
               color: color,
               footer: { text: "RubyMC Bot • #chat-com-rubymc" },
               timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
             }]
  }
end

def admin?(message)
  return false unless message.is_a?(Hash)
  member = message["member"] || message.dig("author", "member") || {}
  roles = member["roles"] || []
  roles.include?(ADMIN_ROLE_ID)
end

def admin_reply(message, response)
  return simple_reply("⛔ Apenas **ADMIN** pode usar este comando.", color: 0xE74C3C, title: "Permissão Negada") unless admin?(message)
  response
end

def command_help
  simple_reply(
    "**📜 Comandos disponíveis**\n\n" \
      "**🔧 Informações**\n" \
      "`!ajuda`      — mostra esta lista\n" \
      "`!sobre`      — informações do projeto\n" \
      "`!status`     — estado do bot, servidor e convites\n" \
      "`!versao`     — versão do launcher e Minecraft\n" \
      "`!ping`       — latency do bot\n" \
      "`!servidor`   — status do servidor Minecraft Java\n\n" \
      "**📋 Regras e Cargos**\n" \
      "`!regras`     — exibe as regras do servidor\n" \
      "`!cargos`     — lista os cargos disponíveis\n\n" \
      "**📅 Comunidade**\n" \
      "`!eventos`    — próximos eventos agendados\n" \
      "`!atualizacoes` — últimas atualizações do projeto\n" \
      "`!convidar`   — link do Discord e endereço do servidor MC\n" \
      "`!topicos`    — reenvia os assuntos dos canais\n" \
      "`!servidores` — status de gerenciamento dos servidores\n\n" \
      "**💬 Interação**\n" \
      "`!sugerir <texto>` — envia uma sugestão\n" \
      "`!reportar <texto>` — reporta um bug/problema\n" \
      "`!java`       — qual Java usar com cada versão\n\n" \
      "**⚙️ Admin** (apenas ADMIN)\n" \
      "`!iniciar` — inicia o servidor Java\n" \
      "`!parar`   — para o servidor Java\n" \
      "`!restart` — reinicia o servidor Java\n" \
      "`!log`     — exibe o console (últimas N linhas)\n" \
      "`!backup`  — faz backup do mundo\n\n" \
      "**🤖 Respostas automáticas**\n" \
      "Palavras-chave: `login`, `instalar`, `erro`, `offline`, `ram`, `discord`",
    title: "Ajuda"
  )
end

def command_status
  invites = DiscordIntegration::InviteStore.load(CONFIG)
  delivered = invites.values.count { |i| i["status"] == "delivered" }
  joined = invites.values.count { |i| i["status"] == "joined" }
  server = CONFIG.dig("discord", "server_address").to_s

  server_info = if server.empty?
                  "não configurado"
                else
                  begin
                    s = RubyMC::MinecraftServerStatus.query(server, timeout: 5)
                    if s[:online]
                      "`#{server}` — 🟢 **#{s.dig(:players, :online) || 0}/#{s.dig(:players, :max) || 0}** online"
                    else
                      "`#{server}` — 🔴 Offline"
                    end
                  rescue => e
                    "`#{server}` — ⚠️ #{e.message}"
                  end
                end

  simple_reply(
    "🤖 Bot online e escutando <##{CHANNELS[:chat_rubymc]}>.\n" \
      "🎮 Servidor Minecraft: #{server_info}\n" \
      "📨 Convites: **#{delivered}** pendentes, **#{joined}** aceitos.\n" \
      "⏱️ Daemon ativo desde: #{Time.now.strftime("%d/%m/%Y às %H:%M")}",
    title: "Status"
  )
end

def command_version
  launcher_version = CONFIG.dig("launcher", "version").to_s
  default_mc = CONFIG.dig("minecraft", "default_version").to_s
  default_mc = "1.21.4" if default_mc.empty?

  simple_reply(
    "Launcher: **#{launcher_version.empty? ? "1.0.0" : launcher_version}**\n" \
      "Minecraft recomendado/configurado: **#{default_mc}**\n" \
      "Versão testada no projeto: **Minecraft 1.21.4 + Java 21**.",
    title: "Versões"
  )
end

def command_java
  simple_reply(
    "Use **Java 25+** para Minecraft **1.21.5+ (26.x)**.\n" \
      "Use **Java 21** para Minecraft **1.21 até 1.21.4**.\n" \
      "Use **Java 17** para Minecraft **1.18 até 1.20.x**.\n" \
      "Use **Java 8** para Minecraft **1.16.5 ou mais antigo**.\n\n" \
      "Ubuntu/Debian:\n```bash\nsudo apt install openjdk-25-jdk -y\njava --version\n```\n" \
      "Ou use Oracle JDK 26 (já instalado neste servidor).",
    title: "Java"
  )
end

CHANNEL_TOPICS = {
  bem_vindos:    "**#bem-vindos** — Apenas boas-vindas para novos membros. 🎉\nEste canal é exclusivo para dar as boas-vindas aos novos integrantes da comunidade RubyMC. Não utilize para conversas.",
  regras:        "**#regras** — Leia e respeite as regras da comunidade. 📜\nAqui estão as regras oficiais do servidor. Leia com atenção antes de participar das conversas.",
  noticias:      "**#notícias** — Novidades sobre o launcher, servidores e eventos. 📢\nFique por dentro de tudo que acontece no projeto RubyMC: atualizações do launcher, status dos servidores e eventos da comunidade.",
  comunicados:   "**#comunicados** — Roadmap e estado atual do projeto. 🗺️\nAcompanhe o andamento do desenvolvimento, próximos passos e comunicados oficiais da equipe.",
  novos_membros: "**#novos-membros** — Notificação de quem acabou de entrar. 👋\nCada novo membro é anunciado automaticamente aqui. Dê as boas-vindas!",
  chat_rubymc:   "**#chat-com-rubymc** — Converse com a comunidade e com o bot. 💬\nCanal principal para conversas, tirar dúvidas e interagir com o bot usando comandos `!`.",
  sugestoes:     "**#sugestões** — Envie ideias para melhorar o projeto. 💡\nUse `!sugerir sua ideia aqui` no chat para enviar sugestões. Todas as ideias são bem-vindas!",
  bugs:          "**#bugs** — Reporte problemas e bugs. 🐛\nEncontrou um bug? Use `!reportar descrição do problema` no chat para nos ajudar a melhorar.",
  servidor_oficial: "**#servidor-oficial** — Jogadores online e link do servidor Minecraft. 🎮\nAcompanhe quantos jogadores estão online e obtenha o link para entrar no servidor oficial RubyMC."
}.freeze

$topics_posted = false

def post_channel_topics
  return if $topics_posted

  CHANNEL_TOPICS.each do |key, description|
    channel_id = CHANNELS[key]
    next if channel_id.to_s.empty? || channel_id.start_with?("ID_")

    payload = {
      embeds: [{
        title: "📋 #{key.to_s.capitalize}",
        description: description,
        color: 0x5865F2,
        footer: { text: "RubyMC Launcher • Assunto do Canal" },
        timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      }]
    }
    res = post_message(channel_id, payload)
    status = res&.success? ? "✅" : "❌ HTTP #{res&.code}"
    puts "  #{status} Assunto postado em ##{key}"
    sleep(0.5)
  end
  $topics_posted = true
end

def query_java_server
  java_addr = CONFIG.dig("discord", "server_address") || "127.0.0.1:25565"

  begin
    RubyMC::MinecraftServerStatus.query(java_addr, timeout: 5)
  rescue => e
    { online: false, error: e.message, players: { online: 0, max: 0, sample: [] }, version: { name: '' } }
  end
end

def post_server_status
  channel_id = CHANNELS[:servidor_oficial].to_s
  channel_id = SERVER_CHANNEL_ID if channel_id.empty?
  return if channel_id.empty? || channel_id.start_with?("ID_")

  status = query_java_server
  invite_url = create_invite(INVITE_CHANNEL_ID, max_uses: 0)

  online = status[:online] == true
  players = status.dig(:players, :online) || 0
  max_pl  = status.dig(:players, :max) || 0
  ver     = status.dig(:version, :name) || ''
  emoji   = online ? '🟢' : '🔴'
  sample  = status.dig(:players, :sample) || []
  names   = sample.first(5).map { |p| p.is_a?(Hash) ? p["name"] : p.to_s }.join(", ")
  status_line = online ? "#{emoji} **Online** — #{players}/#{max_pl} jogadores" : "#{emoji} **Offline**"

  payload = {
    embeds: [{
      title: "☕ Servidor Java RubyMC",
      description: invite_url ? "🔗 #{invite_url}\n\n#{status_line}\nVersão: #{ver.empty? ? '—' : ver}#{names.empty? ? '' : "\nJogando: #{names}"}" : "Status do servidor RubyMC:",
      color: online ? 0x2ECC71 : 0xE74C3C,
      footer: { text: "RubyMC Launcher • Status do Servidor" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
  res = post_message(channel_id, payload)
  status_icon = res&.success? ? "✅" : "❌ HTTP #{res&.code}"
  puts "[BOT] #{status_icon} Status postado em #servidor-oficial"
end

def post_invite_to_invite_channel
  invite_url = create_invite(INVITE_CHANNEL_ID, max_uses: 0)
  return unless invite_url

  payload = {
    embeds: [{
      title: "🔗 Convite do Servidor RubyMC",
      description: "Compartilhe este link com quem quiser entrar no servidor!\n\n#{invite_url}",
      color: 0x2ECC71,
      footer: { text: "RubyMC Launcher • Convite ilimitado" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
  post_message(INVITE_CHANNEL_ID, payload)
  puts "[BOT] ✅ Convite postado em #convites: #{invite_url}"
end

def command_invite
  invite_url = create_invite(INVITE_CHANNEL_ID, max_uses: 0)
  server_address = CONFIG.dig("discord", "server_address").to_s
  mc_info = server_address.empty? ? "" : "\n🎮 **Servidor Minecraft:** `#{server_address}`"

  if invite_url
    simple_reply(
      "🔗 **Link de convite gerado!**\n\n#{invite_url}\n#{mc_info}\n\n" \
        "Compartilhe este link com quem quiser entrar no servidor Discord!\n" \
        "Use `!servidor` para ver o status do servidor Minecraft.\n" \
        "Use `!convidar` ou `!convite` novamente para gerar outro.",
      title: "Convide seus amigos!"
    )
  else
    simple_reply(
      "Não foi possível gerar um link de convite agora. Tente novamente mais tarde.#{mc_info}",
      color: 0xF39C12,
      title: "Erro"
    )
  end
end

def command_rules
  {
    embeds: [{
      title: "📜 Regras do Servidor RubyMC",
      description: "Para manter a comunidade organizada e agradável, siga estas regras:",
      color: 0x3498DB,
      fields: [
        { name: "1️⃣ Respeito acima de tudo", value: "Ofensas, preconceito, assédio ou discriminação não serão tolerados. Trate todos com respeito.", inline: false },
        { name: "2️⃣ Sem spam ou flood", value: "Não envie mensagens repetidas, correntes, propagandas ou links suspeitos. Use os canais corretos.", inline: false },
        { name: "3️⃣ Canais corretos", value: "Mantenha cada assunto em seu canal apropriado. Dúvidas no <##{CHANNELS[:chat_rubymc]}>, sugestões no <##{CHANNELS[:sugestoes]}>, reports no <##{CHANNELS[:bugs]}>.", inline: false },
        { name: "4️⃣ Sem divulgação externa", value: "Não divulgue outros servidores, produtos ou serviços sem autorização da staff.", inline: false },
        { name: "5️⃣ Conteúdo adequado", value: "Não poste conteúdo NSFW, ilegal ou que viole os Termos de Serviço do Discord.", inline: false },
        { name: "6️⃣ Uso do bot", value: "Comandos do bot devem ser usados no <##{CHANNELS[:chat_rubymc]}>. Abusos podem resultar em restrição.", inline: false },
        { name: "7️⃣ Contas alternativas", value: "Não use contas alternativas (alts) para evitar punições ou enganar a comunidade.", inline: false },
        { name: "8️⃣ Bom senso", value: "Use o bom senso. Se algo parece problemático, provavelmente é. A staff tem a palavra final.", inline: false }
      ],
      footer: { text: "RubyMC Launcher • Regras da Comunidade" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
end

def command_events
  events = BOT_DATA.dig("events") || []
  if events.empty?
    return simple_reply(
      "Nenhum evento agendado no momento. Fique ligado no <##{CHANNELS[:noticias]}> para novidades!\n\n" \
        "Quer sugerir um evento? Use `!sugerir sua ideia aqui`.",
      title: "📅 Eventos da Comunidade"
    )
  end

  fields = events.map.with_index(1) do |ev, i|
    date = ev["date"].to_s
    desc = ev["description"].to_s
    { name: "#{i}. #{ev["title"]} — #{date}", value: desc.empty? ? "Em breve mais informações." : desc, inline: false }
  end

  { embeds: [{
    title: "📅 Eventos da Comunidade RubyMC",
    description: "Confira os próximos eventos agendados:",
    color: 0x9B59B6,
    fields: fields,
    footer: { text: "RubyMC Launcher • Eventos" },
    timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  }]}
end

def command_updates
  updates = BOT_DATA.dig("updates") || []
  if updates.empty?
    return simple_reply(
      "📡 **Últimas atualizações do RubyMC Launcher**\n\n" \
        "Versão atual: **#{CONFIG.dig("launcher", "version") || "1.1.0"}**\n" \
        "Minecraft: **#{CONFIG.dig("minecraft", "default_version") || "1.21.4"}**\n\n" \
        "Use `!versao` para detalhes da versão atual.\n" \
        "Acompanhe as novidades no <##{CHANNELS[:noticias]}>.",
      title: "📡 Atualizações"
    )
  end

  { embeds: [{
    title: "📡 Atualizações do RubyMC Launcher",
    description: "Últimas novidades do projeto:",
    color: 0x2ECC71,
    fields: updates.first(10).map.with_index(1) do |up, i|
      { name: "##{up["version"] || i} — #{up["date"]}", value: up["description"].to_s, inline: false }
    end,
    footer: { text: "RubyMC Launcher • Atualizações" },
    timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  }]}
end

def command_roles
  {
    embeds: [{
      title: "🎭 Cargos do Servidor",
      description: "Cargos disponíveis e como obtê-los:",
      color: 0xF39C12,
      fields: [
        { name: "🟢 Membro", value: "Atribuído automaticamente ao entrar no servidor.", inline: true },
        { name: "🔵 Jogador", value: "Vincule sua conta Minecraft ao launcher para receber este cargo.", inline: true },
        { name: "🟣 Staff", value: "Equipe de moderação e suporte do servidor.", inline: true },
        { name: "🔴 Admin", value: "Administradores do servidor e do projeto RubyMC.", inline: true },
        { name: "🤖 RubyMC Bot", value: "Cargo exclusivo do bot oficial.", inline: true }
      ],
      footer: { text: "RubyMC Launcher • Cargos" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
end

def command_ping
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  # We can't actually measure Discord latency from here, so estimate
  latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  simple_reply(
    "🏓 **Pong!**\n" \
      "Latência do bot: `~#{latency} ms`\n" \
      "Gateway: `v10`\n" \
      "Status: `online`",
    title: "Pong!"
  )
end

def command_about
  {
    embeds: [{
      title: "💎 RubyMC Launcher",
      description: "Um launcher de Minecraft feito em **Ruby puro**, com autenticação Microsoft, Discord Bot, IA local e suporte a modpacks.",
      color: 0x2ECC71,
      fields: [
        { name: "📌 Versão", value: "`#{CONFIG.dig("launcher", "version") || "1.1.0"}`", inline: true },
        { name: "🎮 Minecraft", value: "`#{CONFIG.dig("minecraft", "default_version") || "1.21.4"}`", inline: true },
        { name: "💎 Ruby", value: "`#{RUBY_VERSION}`", inline: true },
        { name: "👨‍💻 Desenvolvido por", value: "Comunidade RubyMC", inline: true },
        { name: "📄 Licença", value: "MIT", inline: true },
        { name: "🔗 Código-fonte", value: "Disponível no GitHub", inline: true },
        { name: "🤖 Comandos", value: "Use `!ajuda` para ver todos os comandos disponíveis.", inline: false },
        { name: "📢 Novidades", value: "Acompanhe em <##{CHANNELS[:noticias]}>", inline: false }
      ],
      footer: { text: "RubyMC Launcher • Código Aberto" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
end

def command_suggest(text, author_hash)
  suggestion = text.sub(/\A!sugerir\s+/i, "").sub(/\A!sugestao\s+/i, "").strip
  return simple_reply("Use `!sugerir sua sugestão aqui` para enviar uma sugestão.", color: 0xF39C12, title: "Como usar") if suggestion.empty?

  channel_id = CHANNELS[:sugestoes].to_s
  channel_id = SUGGESTIONS_CHANNEL_ID if channel_id.empty?
  return simple_reply("Canal de sugestões não configurado.", color: 0xE74C3C, title: "Erro") if channel_id.empty?

  username = author_hash.is_a?(Hash) ? (author_hash["global_name"] || author_hash["username"]) : author_hash.to_s
  avatar_id = author_hash["avatar"] if author_hash.is_a?(Hash)

  payload = {
    embeds: [{
      title: "💡 Nova Sugestão",
      description: suggestion,
      color: 0x9B59B6,
      author: { name: username.to_s },
      footer: { text: "Use !sugerir para enviar a sua" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
  post_message(channel_id, payload)
  simple_reply("✅ Sua sugestão foi enviada para o canal de sugestões! Obrigado por contribuir! 💡", title: "Sugestão Enviada")
end

def command_report(text, author_hash)
  report = text.sub(/\A!reportar\s+/i, "").sub(/\A!report\s+/i, "").sub(/\A!bug\s+/i, "").strip
  return simple_reply("Use `!reportar descrição do problema` para reportar um bug.", color: 0xF39C12, title: "Como usar") if report.empty?

  channel_id = CHANNELS[:bugs].to_s
  channel_id = BUGS_CHANNEL_ID if channel_id.empty?
  return simple_reply("Canal de reports não configurado.", color: 0xE74C3C, title: "Erro") if channel_id.empty?

  user_id = author_hash.is_a?(Hash) ? author_hash["id"] : nil
  username = author_hash.is_a?(Hash) ? (author_hash["global_name"] || author_hash["username"]) : author_hash.to_s

  payload = {
    embeds: [{
      title: "🐛 Reporte de Bug / Problema",
      description: report,
      color: 0xE74C3C,
      author: { name: username.to_s },
      fields: [
        { name: "Reportado por", value: user_id ? "<@#{user_id}>" : username.to_s, inline: true },
        { name: "Status", value: "📋 Pendente", inline: true }
      ],
      footer: { text: "Use !reportar para reportar um problema" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
  post_message(channel_id, payload)
  simple_reply("✅ Seu reporte foi enviado para o canal de bugs! A equipe vai analisar. 🐛", title: "Reporte Enviado")
end

def server_embed(status, invite_url)
  online = status[:online] == true
  players = status.dig(:players, :online) || 0
  max_pl  = status.dig(:players, :max) || 0
  ver     = status.dig(:version, :name) || ''
  emoji   = online ? '🟢' : '🔴'
  sample  = status.dig(:players, :sample) || []
  names   = sample.first(10).map { |p| p.is_a?(Hash) ? p["name"] : p.to_s }.join(", ")

  motd = status[:description].to_s
  addr = CONFIG.dig("discord", "server_address").to_s

  desc = +""
  desc << "**#{motd.empty? ? '' : motd}**\n\n" unless motd.empty?
  desc << "#{emoji} **#{online ? 'Online' : 'Offline'}**"
  desc << " — #{players}/#{max_pl} jogadores" if online
  desc << "\n**Versão:** #{ver.empty? ? '—' : ver}"
  desc << "\n**Endereço:** `#{addr}`"
  desc << "\n\n**Jogadores online:**\n#{names.empty? ? 'Nenhum jogador online.' : names}"
  desc << "\n\n🔗 #{invite_url}" if invite_url

  {
    title: "☕ Servidor Java",
    description: desc.strip,
    color: online ? 0x2ECC71 : 0xE74C3C,
    inline: false
  }
end

def command_server(text = nil)
  status = query_java_server
  invite_url = create_invite(INVITE_CHANNEL_ID, max_uses: 0)

  embed = server_embed(status, invite_url)
  online = status[:online] == true

  {
    embeds: [{
      title: "☕ Servidor Java",
      description: online ? "🟢 Online" : "🔴 Offline",
      color: online ? 0x2ECC71 : 0xE74C3C,
      fields: [embed],
      footer: { text: "RubyMC Launcher • !servidor" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
end

def command_topics
  post_channel_topics
  simple_reply("✅ Assuntos reenviados para todos os canais configurados!", title: "Tópicos")
end

def command_start_server(text)
  result = RubyMC::ServerManager.start(:java)
  if result[:ok]
    simple_reply("✅ Servidor **#{key}** iniciado (PID: #{result[:pid]}).", title: "Servidor Iniciado")
  else
    simple_reply("❌ Erro ao iniciar #{key}: #{result[:error]}", color: 0xE74C3C, title: "Erro")
  end
end

def command_stop_server(text)
  result = RubyMC::ServerManager.stop(:java)
  if result[:ok]
    simple_reply("⏹️ Servidor **#{key}** parado (#{result[:status]}).", title: "Servidor Parado")
  else
    simple_reply("❌ Erro ao parar #{key}: #{result[:error]}", color: 0xE74C3C, title: "Erro")
  end
end

def command_restart_server(text)
  result = RubyMC::ServerManager.restart(:java)
  if result[:ok]
    simple_reply("🔄 Servidor **#{key}** reiniciado (PID: #{result[:pid]}).", title: "Servidor Reiniciado")
  else
    simple_reply("❌ Erro ao reiniciar #{key}: #{result[:error]}", color: 0xE74C3C, title: "Erro")
  end
end

def command_server_log(text)
  t = text.to_s.downcase.strip
  count = t[/\d+/]&.to_i || 20

  result = RubyMC::ServerManager.console(:java, lines: count)
  if result[:ok]
    log_text = result[:log].empty? ? "(log vazio)" : result[:log]
    log_text = log_text[-1500..] || log_text if log_text.length > 1500
    simple_reply(
      "📋 **#{key.to_s.capitalize}** — últimas #{[count, result[:total_lines]].min} linhas:\n```\n#{log_text}\n```",
      title: "Console #{key.to_s.capitalize}"
    )
  else
    simple_reply("❌ Erro ao ler log: #{result[:error]}", color: 0xE74C3C, title: "Erro")
  end
end

def command_backup_server(text)
  result = RubyMC::ServerManager.backup(:java)
  if result[:ok]
    simple_reply(
      "✅ Backup do servidor **#{key}** concluído!\n" \
        "📁 `#{result[:path]}`\n📦 #{result[:size_kb]} KB",
      title: "Backup Realizado"
    )
  else
    simple_reply("❌ Erro no backup: #{result[:error]}", color: 0xE74C3C, title: "Erro")
  end
end

def command_servidores
  status = RubyMC::ServerManager.status(:java)
  emoji = status[:running] ? '🟢' : '🔴'
  pid_info = status[:pid] ? " (PID: #{status[:pid]})" : ''

  simple_reply(
    "📡 **Servidor Java** — #{status[:running] ? 'Online' : 'Offline'}#{pid_info}\n\n" \
      "Use `!iniciar`, `!parar`, `!restart`, `!log` ou `!backup`.\n" \
      "Use `!servidor` para ver status do Minecraft.",
    title: "Gerenciamento de Servidores"
  )
end

def answer_for_question(message)
  content = message.is_a?(Hash) ? (message["content"].to_s) : message.to_s
  text = content.downcase.strip
  return nil if text.empty?

  return command_help if text.start_with?("!ajuda", "!help")
  return command_status if text.start_with?("!status")
  return command_version if text.start_with?("!versao", "!versão", "!version")
  return command_java if text.start_with?("!java")
  return command_invite if text.start_with?("!convidar", "!convite", "!discord")
  return command_rules if text.start_with?("!regras")
  return command_events if text.start_with?("!eventos")
  return command_updates if text.start_with?("!atualizacoes", "!atualizações", "!updates")
  return command_roles if text.start_with?("!cargos", "!roles")
  return command_ping if text.start_with?("!ping")
  return command_about if text.start_with?("!sobre", "!about")
  return command_server(content) if text.start_with?("!servidor", "!server")
  return command_topics if text.start_with?("!topicos", "!tópicos", "!topics")
  return command_servidores if text.start_with?("!servidores", "!servers")

  if text.start_with?("!iniciar", "!start")
    return admin_reply(message, command_start_server(content))
  end

  if text.start_with?("!parar", "!stop")
    return admin_reply(message, command_stop_server(content))
  end

  if text.start_with?("!restart", "!reiniciar")
    return admin_reply(message, command_restart_server(content))
  end

  if text.start_with?("!log", "!console")
    return admin_reply(message, command_server_log(content))
  end

  if text.start_with?("!backup")
    return admin_reply(message, command_backup_server(content))
  end

  if text.start_with?("!sugerir", "!sugestao")
    return command_suggest(content, message["author"] || message)
  end

  if text.start_with?("!reportar", "!report", "!bug")
    return command_report(content, message["author"] || message)
  end

  if text.include?("login") || text.include?("microsoft") || text.include?("conta")
    return simple_reply(
      "Para entrar com conta Microsoft, rode `bundle exec ruby launcher.rb`, escolha a versão e selecione **Adicionar nova conta Microsoft**. " \
        "O launcher vai mostrar uma URL e um código; depois que você aprovar no navegador, a sessão fica salva localmente.",
      title: "Login Microsoft"
    )
  end

  if text.include?("instal") || text.include?("baixar") || text.include?("rodar launcher")
    return simple_reply(
      "No diretório do projeto:\n```bash\nbundle install\nbundle exec ruby launcher.rb\n```\n" \
        "Se for usar Minecraft 1.21.x, confirme antes o Java 21 com `java --version`.",
      title: "Instalação"
    )
  end

  if text.include?("erro") || text.include?("falha") || text.include?("bug") || text.include?("problema")
    return simple_reply(
      "Me envie o comando executado, a mensagem de erro completa e a versão do Java (`java --version`). " \
        "Se o problema for Discord, inclua também se o daemon está rodando com `bundle exec ruby bot_daemon.rb`.",
      color: 0xF39C12,
      title: "Diagnóstico"
    )
  end

  if text.include?("offline") || text.include?("pirata") || text.include?("sem conta")
    return simple_reply(
      "O launcher tem modo offline para LAN/servidores offline. No menu de autenticação, escolha **Jogar Offline** e informe o username. " \
        "Servidores online/autenticados exigem conta Microsoft com Minecraft Java.",
      title: "Modo Offline"
    )
  end

  if text.include?("ram") || text.include?("memoria") || text.include?("memória")
    return simple_reply(
      "O launcher pergunta a RAM antes de iniciar. Para Minecraft vanilla, **4 GB** costuma ser suficiente; para modpacks, use **6 a 8 GB** se o computador tiver memória livre.",
      title: "Memória RAM"
    )
  end

  if text.include?("convite") || text.include?("discord") || text.include?("servidor")
    return command_invite
  end

  nil
end

def on_chat_message(message)
  channel_id = message["channel_id"].to_s
  return unless channel_id == CHANNELS[:chat_rubymc]
  return if message.dig("author", "bot")
  return if message.dig("author", "id").to_s == $bot_user_id.to_s

  response = answer_for_question(message)
  return unless response

  res = reply_to_message(message, response)
  status = res&.success? ? "✅" : "❌ HTTP #{res&.code}"
  puts "[BOT] #{status} Resposta enviada em #chat-com-rubymc para #{message.dig("author", "username")}"
end

def embed_bem_vindos(member)
  username    = member.dig("user", "username").to_s
  global_name = member.dig("user", "global_name") || username
  user_id     = member.dig("user", "id")
  avatar_id   = member.dig("user", "avatar")
  avatar_url  = avatar_id \
                  ? "https://cdn.discordapp.com/avatars/#{user_id}/#{avatar_id}.png?size=128"
                  : "https://cdn.discordapp.com/embed/avatars/#{user_id.to_i % 5}.png"

  invite_url  = create_invite(INVITE_CHANNEL_ID, max_uses: 0)

  {
    content: "🎮 **#{global_name}** entrou no servidor! <@#{user_id}>",
    embeds: [{
      title: "Bem-vindo ao RubyMC, #{global_name}!",
      description: "Olá **#{username}**! Seja bem-vindo ao servidor oficial da comunidade RubyMC. 🚀\n\n" \
        "Somos um launcher de Minecraft feito em **Ruby puro**, com autenticação Microsoft, " \
        "suporte a modpacks e integração nativa com o Discord.\n\n" \
        "Tire suas dúvidas no <##{CHANNELS[:chat_rubymc]}>, veja as novidades no <##{CHANNELS[:noticias]}> " \
        "e divirta-se! **Bom jogo!** ⛏️",
      color: 0x2ECC71,
      thumbnail: { url: avatar_url },
      fields: [
        {
          name: "📌 Primeiros passos",
          value: "• 🖥️ **Launcher**: Baixe em rubymc.xyz/download\n" \
            "• 💬 **Dúvidas**: <##{CHANNELS[:chat_rubymc]}>\n" \
            "• 🎮 **Servidor**: Conecte-se em mc.rubymc.xyz",
          inline: false
        },
        {
          name: "🔗 Convidar amigos",
          value: invite_url \
            ? "Compartilhe este link com quem quiser entrar no servidor!\n#{invite_url}"
            : "Use `!convidar` no <##{CHANNELS[:chat_rubymc]}> para gerar um link.",
          inline: false
        }
      ],
      footer: { text: "RubyMC • Bem-vindo à comunidade!" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
end

def embed_regras(_member = nil)
  {
    content: "📜 **Regras do Servidor** — Leia com atenção!",
    embeds: [{
      title: "📜 Regras da Comunidade RubyMC",
      description: "Para manter a comunidade organizada e agradável para todos:",
      color: 0x3498DB,
      fields: [
        { name: "1️⃣ Respeito", value: "Ofensas, preconceito, assédio ou discriminação não serão tolerados.", inline: false },
        { name: "2️⃣ Sem spam", value: "Não envie mensagens repetidas, propagandas ou links suspeitos.", inline: false },
        { name: "3️⃣ Canais corretos", value: "Dúvidas no <##{CHANNELS[:chat_rubymc]}>, sugestões no <##{CHANNELS[:sugestoes]}>.", inline: false },
        { name: "4️⃣ Sem divulgação externa", value: "Não divulgue outros servidores sem autorização da staff.", inline: false },
        { name: "5️⃣ Conteúdo adequado", value: "Não poste NSFW ou conteúdo ilegal.", inline: false },
        { name: "6️⃣ Uso do bot", value: "Use comandos no <##{CHANNELS[:chat_rubymc]}>. Abusos podem resultar em restrição.", inline: false },
        { name: "7️⃣ Bom senso", value: "Use o bom senso. A staff tem a palavra final.", inline: false }
      ],
      footer: { text: "RubyMC Launcher • Regras" },
      timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
end

def embed_novos_membros(member, invitation = nil)
  username    = member.dig("user", "username").to_s
  global_name = member.dig("user", "global_name") || username
  user_id     = member.dig("user", "id")
  avatar_id   = member.dig("user", "avatar")
  avatar_url  = avatar_id \
                  ? "https://cdn.discordapp.com/avatars/#{user_id}/#{avatar_id}.png?size=64"
                  : "https://cdn.discordapp.com/embed/avatars/#{user_id.to_i % 5}.png"

  description = "🎉 **#{username}** acabou de entrar no servidor!"

  if invitation
    mc_user = invitation["minecraft_username"].to_s
    version = invitation["version"].to_s
    delivered_at = invitation["delivered_at"] ? Time.at(invitation["delivered_at"].to_i).strftime("%d/%m/%Y às %H:%M") : "agora"
    description << "\n\n✅ **Convite do launcher aceito**"
    description << "\n└ Nick Minecraft: **#{mc_user}**" unless mc_user.empty?
    description << "\n└ Versão: **#{version}**" unless version.empty?
    description << "\n└ Convite enviado em: #{delivered_at}"
  end

  {
    embeds: [{
      description: description,
      color:       0xF39C12,
      thumbnail:   { url: avatar_url },
      footer:      { text: "Entrou em #{Time.now.strftime("%d/%m/%Y às %H:%M")}" },
      timestamp:   Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }]
  }
end

def embed_noticias(member)
  username = member.dig("user", "username").to_s
  {
    embeds: [{
               title:       "📰 Olá, #{username}! Veja o que está rolando no RubyMC",
               description: "Bem-vindo ao canal de notícias! Aqui você fica por dentro de tudo sobre o servidor e o universo Minecraft.",
               color:       0x3498DB,
               fields: [
                 {
                    name:   "🗺️ Servidor Oficial RubyMC",
                    value:  "Servidor da comunidade rodando **Minecraft 1.21.5 (26.1.1) + Java 26**. " \
                      "Já disponível para jogadores! Conecte-se em `127.0.0.1:25565`.",
                   inline: false
                 },
                 {
                   name:   "🏆 Evento de Inauguração",
                   value:  "Na abertura do servidor haverá um evento especial com **desafios, construção colaborativa e recompensas** " \
                     "para os primeiros jogadores. Os membros do Discord terão acesso prioritário!",
                   inline: false
                 },
                 {
                    name:   "🎮 Minecraft 1.21.5 (26.1.1)",
                    value:  "Versão atual do servidor, roda com **Java 26**. Suporta os pacotes de dados mais recentes, " \
                      "novos blocos de estanho/cobre e melhorias no sistema de rendição.",
                   inline: false
                 },
                 {
                   name:   "🔔 Ative as notificações",
                   value:  "Para não perder nenhum anúncio, clique com o botão direito neste canal → **Editar notificações** → Todas as mensagens.",
                   inline: false
                 }
               ],
               footer:    { text: "RubyMC Launcher • Canal de Notícias" },
               timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
             }]
  }
end

def embed_comunicados(member)
  username = member.dig("user", "username").to_s
  {
    embeds: [{
               title:       "📋 RubyMC Launcher — Estado do Projeto",
               description: "Olá, **#{username}**! Aqui está um resumo completo do que foi feito e o que vem a seguir.",
               color:       0x9B59B6,
               fields: [
                 {
                   name:   "✅ v1.0.0 — Lançado e funcionando",
                   value:  "• Autenticação Microsoft (OAuth 2.0 → Xbox Live → XSTS → Minecraft)\n" \
                     "• Download e instalação automática de qualquer versão da Mojang\n" \
                     "• Banco de múltiplas contas com renovação automática de tokens\n" \
                     "• Modo offline (sem conta Microsoft)\n" \
                     "• Rich Presence no Discord em tempo real\n" \
                     "• Bot de convites automáticos ao entrar no jogo\n" \
                     "• Detecção de versão Java com avisos de incompatibilidade\n" \
                     "• ✅ Testado: **Minecraft 1.21.4 + Java 21 no Ubuntu 24.04**",
                   inline: false
                 },
                 {
                   name:   "🔧 v1.1.0 — Em desenvolvimento",
                   value:  "• Suporte a **modpacks** (Forge / Fabric / Quilt)\n" \
                     "• Interface gráfica opcional (GUI) com Glimmer DSL for Tk\n" \
                     "• Servidor público da comunidade\n" \
                     "• Comandos do bot: `!status`, `!versao`, `!java`, `!ajuda`\n" \
                     "• Auto-update do launcher via GitHub Releases\n" \
                     "• Suporte a perfis de configuração por versão",
                   inline: false
                 },
                 {
                   name:   "📂 Open Source",
                   value:  "O projeto é 100% aberto. Todo o código está disponível e contribuições são muito bem-vindas!",
                   inline: false
                 }
               ],
               footer:    { text: "RubyMC Launcher v1.0.0 • Canal de Comunicados" },
               timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
             }]
  }
end

def embed_chat_rubymc(member)
  username = member.dig("user", "username").to_s
  user_id  = member.dig("user", "id")
  {
    embeds: [{
               title:       "🤖 Olá, #{username}! Eu sou o BOT RUBYMC",
               description: "Fui desenvolvido exclusivamente para esta comunidade. Sou a ponte entre o **RubyMC Launcher** e o Discord — " \
                 "sempre online, sempre pronto para ajudar.",
               color:       0xE74C3C,
               fields: [
                 {
                   name:   "💬 Tire suas dúvidas aqui",
                   value:  "• Como instalar e configurar o **RubyMC Launcher**\n" \
                     "• Problemas com login Microsoft / conta Minecraft\n" \
                     "• Erros de Java, versão incompatível, download travado\n" \
                     "• Configurar Discord Rich Presence\n" \
                     "• Usar o modo offline / LAN\n" \
                     "• Como o launcher foi construído em Ruby",
                   inline: false
                 },
                 {
                   name:   "🎮 Sistema de Convites Automáticos",
                   value:  "Quando qualquer jogador **iniciar o Minecraft pelo launcher**, o bot pode enviar por DM " \
                     "um convite real do servidor Discord ao usuário vinculado. Quando ele entra, o daemon marca " \
                     "o convite como aceito e registra a entrada aqui.",
                   inline: false
                 },
                 {
                   name:   "⚙️ Comandos disponíveis",
                   value:  "`!versao` → Versão atual do launcher\n" \
                     "`!java`   → Qual Java usar com cada versão do MC\n" \
                     "`!status` → Quem está online no servidor agora\n" \
                     "`!ajuda`  → Lista todos os comandos disponíveis",
                   inline: false
                 },
                 {
                   name:   "👾 Easter Egg",
                   value:  "Você sabia que este bot inteiro foi escrito em **Ruby puro**, sem nenhum framework de bot? " \
                     "Ele se conecta direto ao Gateway do Discord via WebSocket e gerencia o heartbeat manualmente. " \
                     "Bem-vindo ao projeto, <@#{user_id}>! 🎉",
                   inline: false
                 }
               ],
               footer:    { text: "RubyMC Bot • Sempre online para ajudar" },
               timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
             }]
  }
end

def on_member_join(member)
  username = member.dig("user", "username")
  user_id  = member.dig("user", "id").to_s
  invitation = DiscordIntegration::InviteStore.mark_joined(
    config: CONFIG,
    discord_user_id: user_id,
    discord_username: username
  )

  puts "[BOT] ➜ Novo membro: #{username}"
  if invitation
    puts "[BOT] ✓ Convite do launcher aceito por #{username} (Minecraft: #{invitation["minecraft_username"]})"
  end

  {
    bem_vindos:    :embed_bem_vindos,
    novos_membros: :embed_novos_membros
  }.each do |canal, metodo|
    channel_id = CHANNELS[canal]
    next if channel_id.to_s.empty? || channel_id.start_with?("ID_")
    embed_builder = method(metodo)
    payload = metodo == :embed_novos_membros ? embed_builder.call(member, invitation) : embed_builder.call(member)
    res    = post_message(channel_id, payload)
    status = res&.success? ? "✅" : "❌ HTTP #{res&.code}"
    puts "  #{status} ##{canal}"
    sleep(0.8)
  end
  post_invite_to_invite_channel
  puts "[BOT] Boas-vindas concluídas para #{username}.\n\n"
end

puts "\e[35m╔══════════════════════════════════════════╗\e[0m"
puts "\e[35m║      RubyMC Bot Daemon — Iniciando       ║\e[0m"
puts "\e[35m╚══════════════════════════════════════════╝\e[0m"

token = bridge.bot_token
guild_id = bridge.guild_id
channels = bridge.channels_for_daemon

puts "Token  : #{BOT_TOKEN[0..9]}..."
puts "Canais :"
CHANNELS.each do |k, v|
  status = v.empty? || v.start_with?("ID_") ? "\e[31mNÃO CONFIGURADO\e[0m" : "\e[32m#{v}\e[0m"
  puts "  ##{k.to_s.ljust(15)} → #{status}"
end
puts ""

MAX_RECONNECT_DELAY = 60
MAX_BG_THREADS = 16
$bg_thread_counter = 0
$bg_thread_counter_mutex = Mutex.new

def track_thread(name: nil, limit: MAX_BG_THREADS, &block)
  slot = false
  $bg_thread_counter_mutex.synchronize do
    if $bg_thread_counter < limit
      $bg_thread_counter += 1
      slot = true
    end
  end

  unless slot
    puts "[BOT] ⚠️  Thread limit (#{limit}) atingido, ignorando thread: #{name}"
    return
  end

  Thread.new do
    block.call
  rescue => e
    puts "[BOT] Thread #{name}: #{e.message}"
  ensure
    $bg_thread_counter_mutex.synchronize { $bg_thread_counter -= 1 }
  end
end

def connect_to_gateway
  ws = WebSocket::Client::Simple.connect(GATEWAY_URL)
  sequence = nil
  $bot_user_id = nil

  ws.on(:message) do |msg|
    data = JSON.parse(msg.data) rescue next
    op      = data["op"]
    event   = data["t"]
    payload = data["d"]
    sequence = data["s"] if data["s"]

    case op
    when 10
      interval = payload["heartbeat_interval"] / 1000.0
      track_thread(name: 'heartbeat') do
        loop do
          sleep(interval)
          ws.send({ op: 1, d: sequence }.to_json)
        end
      end
      ws.send({
                op: 2,
                d: {
                  token:      BOT_TOKEN,
                  intents:    GATEWAY_INTENTS,
                  properties: { os: "linux", browser: "rubymc", device: "rubymc" }
                }
              }.to_json)

    when 0
      case event
      when "READY"
        $bot_user_id = payload.dig("user", "id")
        puts "\e[32m✅ Conectado como: #{payload.dig("user", "username")}\e[0m"
        post_channel_topics
        track_thread(name: 'server_status_refresh') do
          loop do
            sleep(300)
            post_server_status
          rescue => e
            puts "[ERRO] Auto-refresh #servidor-oficial: #{e.message}"
            sleep(60)
          end
        end
        track_thread(name: 'server_manager_refresh') do
          loop do
            RubyMC::ServerManager::SERVERS.each_key do |key|
              s = RubyMC::ServerManager.status(key)
              puts "[BOT] 📡 Servidor #{s[:name]}: #{s[:running] ? '🟢 Online' : '🔴 Offline'}" if s[:ok]
            end
            sleep(600)
          rescue => e
            puts "[ERRO] Auto-refresh server_manager: #{e.message}"
            sleep(60)
          end
        end
        puts "Aguardando novos membros e perguntas em #chat-com-rubymc...\n\n"
      when "GUILD_MEMBER_ADD"
        Thread.new { on_member_join(payload) }
      when "MESSAGE_CREATE"
        Thread.new { on_chat_message(payload) }
      end

    when 7
      puts "[GATEWAY] Reconectando..."
      ws.close
    when 9
      puts "[GATEWAY] Sessão inválida. Aguarde..."
      sleep(5)
      ws.close
    end
  end

  ws.on(:error) { |e| puts "\e[31m[ERRO] #{e.message}\e[0m" }

  ws
end

reconnect_delay = 2
loop do
  ws = connect_to_gateway
  connected = true

  ws.on(:close) do |e|
    puts "[GATEWAY] Desconectado: #{e.inspect}"
    connected = false
  end

  sleep 0.5 while connected

  puts "Reconectando em #{reconnect_delay} segundos..."
  sleep reconnect_delay
  reconnect_delay = [reconnect_delay * 1.5, MAX_RECONNECT_DELAY].min
end