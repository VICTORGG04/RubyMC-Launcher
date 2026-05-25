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
#
# Uso:
#   bundle exec ruby bot_daemon.rb        # primeiro plano
#   bundle exec ruby bot_daemon.rb &      # background
#   nohup bundle exec ruby bot_daemon.rb & # background persistente
# =============================================================================

require "websocket-client-simple"
require "httparty"
require "json"
require "yaml"
require_relative "lib/discord_integration"
require_relative "lib/discord_config"
require_relative 'lib/rubymc_bot_config_bridge'
# RubyMC Discord channel aliases
# Compatibilidade entre nomes antigos do bot_daemon.rb e nomes novos do settings.yml.
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
  'support_channel' => 'support_channel_id'
}.freeze

def rubymc_channel_id(channels, key)
  return nil unless channels
  key = key.to_s
  canonical = RUBYMC_CHANNEL_ALIASES.fetch(key, key)
  channels[canonical] || channels[canonical.to_sym] || channels[key] || channels[key.to_sym]
end


CONFIG    = YAML.load_file(File.join(__dir__, "config/settings.yml"))
BOT_TOKEN = CONFIG.dig("discord", "bot_token").to_s

CHANNELS = {
  bem_vindos:    CONFIG.dig("discord", "welcome_channel_id").to_s,
  novos_membros: CONFIG.dig("discord", "new_members_channel_id").to_s,
  noticias:      CONFIG.dig("discord", "channel_noticias").to_s,
  comunicados:   CONFIG.dig("discord", "channel_comunicados").to_s,
  chat_rubymc:   CONFIG.dig("discord", "channel_chat_rubymc").to_s
}.freeze

GATEWAY_URL = "wss://gateway.discord.gg/?v=10&encoding=json"
GATEWAY_INTENTS = (1 << 0) | (1 << 1) | (1 << 9) | (1 << 15)
# GUILDS + GUILD_MESSAGES + GUILD_MEMBERS + MESSAGE_CONTENT

# ── REST helper ───────────────────────────────────────────────────────────────
def post_message(channel_id, payload)
  return if channel_id.to_s.empty? || channel_id.start_with?("ID_")
  res = HTTParty.post(
    "https://discord.com/api/v10/channels/#{channel_id}/messages",
    headers: {
      "Authorization" => "Bot #{BOT_TOKEN}",
      "Content-Type"  => "application/json"
    },
    body: payload.to_json,
    timeout: 10
  )
  res
rescue => e
  puts "[ERRO] #{e.message}"
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

def command_help
  simple_reply(
    "**Comandos disponíveis**\n" \
      "`!ajuda` - mostra esta lista\n" \
      "`!status` - estado do bot, servidor e convites\n" \
      "`!versao` - versão do launcher e Minecraft recomendado\n" \
      "`!java` - qual Java usar com cada versão\n" \
      "`!convite` - como funciona o convite Discord pelo launcher\n\n" \
      "Também respondo perguntas com palavras como `login`, `instalar`, `erro`, `offline`, `discord`, `convite` e `ram`.",
    title: "Ajuda"
  )
end

def command_status
  invites = DiscordIntegration::InviteStore.load(CONFIG)
  delivered = invites.values.count { |i| i["status"] == "delivered" }
  joined = invites.values.count { |i| i["status"] == "joined" }
  server = CONFIG.dig("discord", "server_address").to_s

  simple_reply(
    "Bot online e escutando <##{CHANNELS[:chat_rubymc]}>.\n" \
      "Servidor Minecraft configurado: `#{server.empty? ? "não configurado" : server}`\n" \
      "Convites enviados: **#{delivered}** pendentes, **#{joined}** aceitos.\n" \
      "Daemon ativo desde: #{Time.now.strftime("%d/%m/%Y às %H:%M")}",
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
    "Use **Java 21** para Minecraft **1.21.x**.\n" \
      "Use **Java 17** para Minecraft **1.18 até 1.20.x**.\n" \
      "Use **Java 8** para Minecraft **1.16.5 ou mais antigo**.\n\n" \
      "No Ubuntu/Debian:\n```bash\nsudo apt install openjdk-21-jdk -y\njava --version\n```",
    title: "Java"
  )
end

def command_invite
  simple_reply(
    "O launcher pode convidar de duas formas:\n" \
      "1. **DM automática**: informe o ID/menção Discord do usuário.\n" \
      "2. **Link manual**: se você só tem o nome do usuário, o launcher gera o link para enviar manualmente.\n\n" \
      "O Discord não permite que bots encontrem ou adicionem pessoas ao servidor apenas pelo nome de usuário.",
    title: "Convite Discord"
  )
end

def answer_for_question(content)
  text = content.to_s.downcase.strip
  return nil if text.empty?

  return command_help if text.start_with?("!ajuda", "!help")
  return command_status if text.start_with?("!status")
  return command_version if text.start_with?("!versao", "!versão", "!version")
  return command_java if text.start_with?("!java")
  return command_invite if text.start_with?("!convite", "!discord")

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

  response = answer_for_question(message["content"])
  return unless response

  res = reply_to_message(message, response)
  status = res&.success? ? "✅" : "❌ HTTP #{res&.code}"
  puts "[BOT] #{status} Resposta enviada em #chat-com-rubymc para #{message.dig("author", "username")}"
end

# ── #bem-vindos — Embed principal com menção ──────────────────────────────────
def embed_bem_vindos(member)
  username    = member.dig("user", "username").to_s
  global_name = member.dig("user", "global_name") || username
  user_id     = member.dig("user", "id")
  avatar_id   = member.dig("user", "avatar")
  avatar_url  = avatar_id \
                  ? "https://cdn.discordapp.com/avatars/#{user_id}/#{avatar_id}.png?size=128"
                  : "https://cdn.discordapp.com/embed/avatars/#{user_id.to_i % 5}.png"

  {
    content: "👋 Ei, <@#{user_id}>! Que bom ter você aqui!",
    embeds: [{
               title:       "Bem-vindo ao LanServer RubyMC, #{global_name}! 💎",
               description: <<~DESC,
        Este é o servidor oficial do **RubyMC Launcher** — o launcher de Minecraft feito em Ruby puro, com autenticação real Microsoft e integração Discord nativa.

        Explore os canais, tire dúvidas no <##{CHANNELS[:chat_rubymc]}> e aproveite! **Bom jogo! 🎮**
      DESC
               color:     0x2ECC71,
               thumbnail: { url: avatar_url },
               fields: [
                 {
                   name:   "📌 Por onde começar?",
                   value:  "• <##{CHANNELS[:comunicados]}> — veja o que já está pronto no projeto\n" \
                     "• <##{CHANNELS[:noticias]}> — fique por dentro de eventos e servidores\n" \
                     "• <##{CHANNELS[:chat_rubymc]}> — tire dúvidas e converse com o bot",
                   inline: false
                 }
               ],
               footer:    { text: "RubyMC Launcher • Bem-vindo à comunidade!" },
               timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
             }]
  }
end

# ── #novos-membros — Notificação simples de entrada ───────────────────────────
def embed_novos_membros(member, invitation = nil)
  username    = member.dig("user", "username").to_s
  global_name = member.dig("user", "global_name") || username
  user_id     = member.dig("user", "id")
  avatar_id   = member.dig("user", "avatar")
  avatar_url  = avatar_id \
                  ? "https://cdn.discordapp.com/avatars/#{user_id}/#{avatar_id}.png?size=64"
                  : "https://cdn.discordapp.com/embed/avatars/#{user_id.to_i % 5}.png"

  description = "**<@#{user_id}>** (`#{username}`) acabou de entrar no servidor! 🎉\n" \
    "Somos agora mais um na comunidade RubyMC. Bem-vindo!"

  if invitation
    mc_user = invitation["minecraft_username"].to_s
    version = invitation["version"].to_s
    delivered_at = invitation["delivered_at"] ? Time.at(invitation["delivered_at"].to_i).strftime("%d/%m/%Y às %H:%M") : "agora"
    description << "\n\n✅ Convite aceito pelo launcher"
    description << "\nJogador Minecraft: **#{mc_user}**" unless mc_user.empty?
    description << "\nVersão: **#{version}**" unless version.empty?
    description << "\nConvite enviado em: #{delivered_at}"
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

# ── #notícias — Novidades do servidor e do jogo ───────────────────────────────
def embed_noticias(member)
  username = member.dig("user", "username").to_s
  {
    embeds: [{
               title:       "📰 Olá, #{username}! Veja o que está rolando no RubyMC",
               description: "Bem-vindo ao canal de notícias! Aqui você fica por dentro de tudo sobre o servidor e o universo Minecraft.",
               color:       0x3498DB,
               fields: [
                 {
                   name:   "🗺️ Servidor Público — Em breve",
                   value:  "Estamos finalizando o servidor público da comunidade para **Minecraft 1.21.4 + Java 21**. " \
                     "Será o primeiro servidor oficial do RubyMC Launcher. Fique ligado!",
                   inline: false
                 },
                 {
                   name:   "🏆 Evento de Inauguração",
                   value:  "Na abertura do servidor haverá um evento especial com **desafios, construção colaborativa e recompensas** " \
                     "para os primeiros jogadores. Os membros do Discord terão acesso prioritário!",
                   inline: false
                 },
                 {
                   name:   "🎮 Minecraft 1.21.4 — O que há de novo",
                   value:  "A versão atual testada e suportada pelo launcher traz melhorias de performance, novos biomas subaquáticos " \
                     "e ajustes no sistema de combate. Totalmente compatível com Java 21 LTS.",
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

# ── #comunicados — Estado e roadmap do projeto ────────────────────────────────
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

# ── #chat-com-rubymc — Apresentação do bot ───────────────────────────────────
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

# ── Dispara as 5 mensagens em sequência ───────────────────────────────────────
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
    novos_membros: :embed_novos_membros,
    noticias:      :embed_noticias,
    comunicados:   :embed_comunicados,
    chat_rubymc:   :embed_chat_rubymc
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
  puts "[BOT] Boas-vindas concluídas para #{username}.\n\n"
end

# ── Gateway WebSocket ─────────────────────────────────────────────────────────
puts "\e[35m╔══════════════════════════════════════════╗\e[0m"
puts "\e[35m║      RubyMC Bot Daemon — Iniciando       ║\e[0m"
puts "\e[35m╚══════════════════════════════════════════╝\e[0m"

# RubyMC BotConfigBridge safe settings fix
rubymc_settings =
  if defined?(settings) && settings
    settings
  elsif defined?(@settings) && @settings
    @settings
  elsif defined?(config) && config.is_a?(Hash)
    config
  elsif defined?(discord) && discord.is_a?(Hash)
    { 'discord' => discord }
  else
    RubyMC::BotConfigBridge.load_settings(Dir.pwd)
  end

rubymc_bot_config = RubyMC::BotConfigBridge.new(rubymc_settings)
token = rubymc_bot_config.bot_token
guild_id = rubymc_bot_config.guild_id
channels = rubymc_bot_config.channels_for_daemon
# End RubyMC BotConfigBridge safe settings fix

puts "Token  : #{BOT_TOKEN[0..9]}..."
puts "Canais :"
CHANNELS.each do |k, v|
  status = v.empty? || v.start_with?("ID_") ? "\e[31mNÃO CONFIGURADO\e[0m" : "\e[32m#{v}\e[0m"
  puts "  ##{k.to_s.ljust(15)} → #{status}"
end
puts ""

sequence = nil
$bot_user_id = nil

ws = WebSocket::Client::Simple.connect(GATEWAY_URL)

ws.on(:message) do |msg|
  data = JSON.parse(msg.data) rescue next

  op      = data["op"]
  event   = data["t"]
  payload = data["d"]
  sequence = data["s"] if data["s"]

  case op
  when 10
    interval = payload["heartbeat_interval"] / 1000.0
    Thread.new do
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
ws.on(:close) { |e| puts "[GATEWAY] Desconectado: #{e.inspect}" }

loop { sleep(1) }
