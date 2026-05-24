# frozen_string_literal: true

require "socket"
require "json"
require "fileutils"

# =============================================================================
# DiscordIntegration — Rich Presence + Bot para Multiplayer
#
# Rich Presence: usa o protocolo IPC local do Discord (sem gem discordrb)
#   → Mostra "Jogando Minecraft" com versão, username e tempo jogando
#
# Bot Multiplayer: usa a API HTTP do Discord para gerar convite e enviar por DM
# =============================================================================
module DiscordIntegration
  # ===========================================================================
  # InviteStore — Registro local dos convites enviados por DM
  # ===========================================================================
  module InviteStore
    DEFAULT_DIR  = File.join(Dir.home, ".minecraft_ruby_launcher")
    DEFAULT_FILE = File.join(DEFAULT_DIR, "discord_invites.json")

    module_function

    def path(config)
      configured = config.dig("discord", "invite_store_path").to_s
      configured.strip.empty? ? DEFAULT_FILE : File.expand_path(configured)
    end

    def record_pending(config:, discord_user_id:, discord_username:, minecraft_username:,
                       version:, invite_code:, invite_url:, dm_channel_id:, message_id:)
      now = Time.now.to_i
      data = load(config)
      data[discord_user_id] = {
        "discord_user_id"    => discord_user_id,
        "discord_username"   => discord_username,
        "minecraft_username" => minecraft_username,
        "version"            => version,
        "invite_code"        => invite_code,
        "invite_url"         => invite_url,
        "dm_channel_id"      => dm_channel_id,
        "message_id"         => message_id,
        "status"             => "delivered",
        "delivered_at"       => now,
        "joined_at"          => nil
      }
      save(config, data)
      data[discord_user_id]
    end

    def mark_joined(config:, discord_user_id:, discord_username:)
      data = load(config)
      invitation = data[discord_user_id]
      return nil unless invitation

      invitation["status"]           = "joined"
      invitation["discord_username"] = discord_username if discord_username.to_s.strip != ""
      invitation["joined_at"]        = Time.now.to_i
      save(config, data)
      invitation
    end

    def load(config)
      file = path(config)
      return {} unless File.exist?(file)

      JSON.parse(File.read(file))
    rescue JSON::ParserError
      {}
    end

    def save(config, data)
      file = path(config)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, JSON.pretty_generate(data))
      File.chmod(0o600, file)
    end
  end

  # ===========================================================================
  # RichPresence — Protocolo IPC local (pipe Unix / named pipe Windows)
  # Comunica direto com o cliente Discord instalado na máquina
  # ===========================================================================
  class RichPresence
    OP_HANDSHAKE = 0
    OP_FRAME     = 1
    OP_CLOSE     = 2

    def initialize(client_id)
      @client_id  = client_id
      @socket     = nil
      @start_time = nil
      @connected  = false
    end

    # Conecta ao Discord via IPC
    def connect
      return false if @client_id.to_s.strip.empty? || @client_id.include?("SEU_")

      if Gem.win_platform?
        # Windows: Comunicação via Named Pipes
        10.times do |i|
          path = "\\\\.\\pipe\\discord-ipc-#{i}"
          @socket = File.open(path, "r+") rescue nil
          break if @socket
        end
      else
        # Linux/macOS: Comunicação via UNIX Sockets
        pipe_path = find_pipe
        @socket = UNIXSocket.new(pipe_path) if pipe_path
      end

      return false unless @socket

      send_packet(OP_HANDSHAKE, { v: 1, client_id: @client_id })
      read_packet  # Lê resposta do handshake
      @connected  = true
      @start_time = Time.now.to_i
      true
    rescue
      @connected = false
      false
    end

    # Atualiza o status no Discord
    def update(state:, details:, version: nil, username: nil)
      return false unless @connected

      payload = {
        cmd: "SET_ACTIVITY",
        args: {
          pid: Process.pid,
          activity: {
            state:   state,
            details: details,
            timestamps: { start: @start_time },
            assets: {
              large_image: "minecraft_logo",
              large_text:  version ? "Minecraft #{version}" : "Minecraft",
              small_image: "ruby_icon",
              small_text:  "Ruby Launcher"
            },
            instance: true
          }
        },
        nonce: Time.now.to_f.to_s
      }

      send_packet(OP_FRAME, payload)
      true
    rescue
      @connected = false
      false
    end

    # Define status "Em jogo"
    def set_playing(username:, version:, server: nil)
      details = "Jogando Minecraft #{version}"
      state   = server ? "Servidor: #{server}" : "Modo Single Player"
      update(state: state, details: details, version: version, username: username)
    end

    # Define status "No launcher"
    def set_in_launcher
      update(
        state:   "Escolhendo versão...",
        details: "No Launcher"
      )
    end

    def disconnect
      return unless @connected
      send_packet(OP_CLOSE, {})
      @socket&.close
      @connected = false
    rescue
      nil
    end

    def connected?
      @connected
    end

    private

    def find_pipe
      # Linux/macOS: busca em /tmp e $XDG_RUNTIME_DIR
      dirs = [
        ENV["XDG_RUNTIME_DIR"],
        ENV["TMPDIR"],
        "/tmp",
        "/run/user/#{Process.uid}"
      ].compact

      dirs.each do |dir|
        10.times do |i|
          path = File.join(dir, "discord-ipc-#{i}")
          return path if File.exist?(path)
        end
      end
      nil
    end

    # Empacota e envia: [opcode u32le][length u32le][json payload]
    def send_packet(opcode, data)
      json = data.to_json
      payload = [opcode, json.bytesize].pack("VV") + json
      @socket.write(payload)
      @socket.flush if @socket.respond_to?(:flush)
    end

    # Lê resposta do Discord
    # Lê resposta do Discord
    def read_packet
      header = @socket.read(8)
      return nil unless header&.length == 8
      _op, length = header.unpack("VV")
      body = @socket.read(length)
      JSON.parse(body) rescue nil
    end
  end

  # ===========================================================================
  # Bot — Envia convites do servidor Discord por DM e mantém fallback em canal
  # ===========================================================================
  class Bot
    def initialize(config)
      @config          = config
      @bot_token       = config.dig("discord", "bot_token").to_s
      @channel_id      = config.dig("discord", "invite_channel_id").to_s
      @server_address  = config.dig("discord", "server_address").to_s
      @invite_max_age  = (config.dig("discord", "invite_max_age_seconds") || 86_400).to_i
      @invite_max_uses = (config.dig("discord", "invite_max_uses") || 1).to_i
      @enabled         = config.dig("discord", "bot_enabled") &&
                         !@bot_token.empty? && !@bot_token.include?("SEU_")
    end

    def enabled?
      @enabled
    end

    def create_server_invite
      return { success: false, reason: "Bot não habilitado." } unless @enabled
      return { success: false, reason: "Canal de convite Discord não configurado." } if invalid_id?(@channel_id)

      create_channel_invite(@channel_id)
    end

    # Envia por DM um convite real do servidor Discord para o jogador.
    def send_discord_invite(username:, version:, discord_user_id:, discord_username: nil,
                            server_address: nil)
      return { success: false, reason: "Bot não habilitado." } unless @enabled

      user_id = self.class.extract_user_id(discord_user_id)
      return { success: false, reason: "ID do usuário Discord inválido." } unless user_id
      return { success: false, reason: "Canal de convite Discord não configurado." } if invalid_id?(@channel_id)

      user = fetch_user(user_id)
      return user unless user[:success]

      invite = create_channel_invite(@channel_id)
      return invite unless invite[:success]

      dm = create_dm_channel(user_id)
      return dm unless dm[:success]

      address = server_address || @server_address
      payload = direct_invite_payload(
        minecraft_username: username,
        version: version,
        discord_user_id: user_id,
        invite_url: invite[:url],
        server_address: address
      )

      message = post_to_channel(dm[:channel_id], payload)
      unless message.is_a?(Hash) && message[:success]
        return { success: false, reason: "Falha ao enviar DM com convite Discord." }
      end

      InviteStore.record_pending(
        config: @config,
        discord_user_id: user_id,
        discord_username: discord_username,
        minecraft_username: username,
        version: version,
        invite_code: invite[:code],
        invite_url: invite[:url],
        dm_channel_id: dm[:channel_id],
        message_id: message[:message_id]
      )

      {
        success: true,
        delivery: :dm,
        discord_user_id: user_id,
        invite_url: invite[:url],
        delivered_at: Time.now
      }
    end

    # Posta convite de servidor Minecraft no canal Discord configurado.
    # Mantido como fallback e compatibilidade com os scripts antigos.
    def post_server_invite(username:, version:, server_address: nil)
      return false unless @enabled

      address = server_address || @server_address
      return false if address.empty?

      message = {
        embeds: [{
                   title:       "🎮 Partida de Minecraft!",
                   description: "**#{username}** está jogando e convida você para jogar junto!",
                   color:       0x2ECC71,
                   fields: [
                     { name: "🗺️ Servidor",  value: "`#{address}`",  inline: true },
                     { name: "📦 Versão",    value: version,           inline: true },
                     { name: "🚀 Launcher",  value: "Ruby Launcher",   inline: true }
                   ],
                   footer: { text: "Minecraft Ruby Launcher" },
                   timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
                 }]
      }

      post_to_channel(@channel_id, message)
    end

    # Posta mensagem de texto simples no canal
    def post_message(channel_id, text)
      return false unless @enabled
      post_to_channel(channel_id, { content: text })
    end

    def self.extract_user_id(value)
      text = value.to_s.strip
      match = text.match(/\A<@!?(\d{17,20})>\z/) || text.match(/\A(\d{17,20})\z/)
      match && match[1]
    end

    private

    def create_channel_invite(channel_id)
      res = discord_post(
        "https://discord.com/api/v10/channels/#{channel_id}/invites",
        {
          max_age: @invite_max_age,
          max_uses: @invite_max_uses,
          temporary: false,
          unique: true
        }
      )

      unless res&.success?
        return {
          success: false,
          reason: "Falha ao criar convite Discord (HTTP #{res&.code}): #{discord_error_detail(res)}"
        }
      end

      code = res["code"].to_s
      return { success: false, reason: "Discord não retornou o código do convite." } if code.empty?

      { success: true, code: code, url: "https://discord.gg/#{code}" }
    rescue => e
      { success: false, reason: "Falha ao criar convite Discord: #{e.message}" }
    end

    def fetch_user(user_id)
      res = discord_get("https://discord.com/api/v10/users/#{user_id}")

      unless res&.success?
        return {
          success: false,
          reason: "Usuário Discord não encontrado/acessível (HTTP #{res&.code}): #{discord_error_detail(res)}"
        }
      end

      { success: true, user_id: user_id, username: res["username"].to_s }
    rescue => e
      { success: false, reason: "Falha ao consultar usuário Discord: #{e.message}" }
    end

    def create_dm_channel(user_id)
      res = discord_post(
        "https://discord.com/api/v10/users/@me/channels",
        { recipient_id: user_id }
      )

      unless res&.success?
        return {
          success: false,
          reason: "Falha ao abrir DM com o usuário Discord (HTTP #{res&.code}): #{discord_error_detail(res)}"
        }
      end

      channel_id = res["id"].to_s
      return { success: false, reason: "Discord não retornou o canal de DM." } if channel_id.empty?

      { success: true, channel_id: channel_id }
    rescue => e
      { success: false, reason: "Falha ao abrir DM: #{e.message}" }
    end

    def direct_invite_payload(minecraft_username:, version:, discord_user_id:, invite_url:, server_address:)
      fields = [
        { name: "Jogador Minecraft", value: minecraft_username, inline: true },
        { name: "Versão", value: version, inline: true },
        { name: "Convite Discord", value: invite_url, inline: false }
      ]

      unless server_address.to_s.strip.empty?
        fields << { name: "Servidor Minecraft", value: "`#{server_address}`", inline: false }
      end

      {
        content: "<@#{discord_user_id}>",
        embeds: [{
                   title: "Convite para entrar no Discord RubyMC",
                   description: "#{minecraft_username} iniciou o Minecraft pelo RubyMC Launcher. Use o convite abaixo para entrar no servidor Discord.",
                   color: 0x2ECC71,
                   fields: fields,
                   footer: { text: "Minecraft Ruby Launcher" },
                   timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
                 }]
      }
    end

    def post_to_channel(channel_id, payload)
      return false if invalid_id?(channel_id)

      res = discord_post("https://discord.com/api/v10/channels/#{channel_id}/messages", payload)
      return false unless res&.success?

      return true unless res.respond_to?(:parsed_response)

      { success: true, message_id: res["id"].to_s }
    rescue => e
      false
    end

    def discord_post(url, payload)
      require "httparty"
      HTTParty.post(
        url,
        headers: {
          "Authorization" => "Bot #{@bot_token}",
          "Content-Type"  => "application/json"
        },
        body: payload.to_json,
        timeout: 10
      )
    end

    def discord_get(url)
      require "httparty"
      HTTParty.get(
        url,
        headers: {
          "Authorization" => "Bot #{@bot_token}",
          "Content-Type"  => "application/json"
        },
        timeout: 10
      )
    end

    def discord_error_detail(res)
      return "sem resposta da API" unless res

      body = res.body.to_s.strip
      parsed = JSON.parse(body) rescue nil
      if parsed.is_a?(Hash)
        parts = []
        parts << parsed["message"].to_s unless parsed["message"].to_s.empty?
        parts << "code #{parsed["code"]}" unless parsed["code"].to_s.empty?
        parts << JSON.generate(parsed["errors"]) if parsed["errors"]
        return parts.join(" | ") unless parts.empty?
      end

      body.empty? ? "sem detalhes" : body[0, 500]
    end

    def invalid_id?(id)
      id.to_s.strip.empty? || id.to_s.include?("ID_DO") || id.to_s.start_with?("ID_")
    end
  end

  # ===========================================================================
  # Manager — Facade que gerencia RichPresence + Bot juntos
  # ===========================================================================
  class Manager
    attr_reader :presence, :bot

    def initialize(config)
      @config   = config
      @presence = RichPresence.new(config.dig("discord", "client_id").to_s)
      @bot      = Bot.new(config)
      @enabled  = config.dig("discord", "rich_presence")
    end

    # Inicializa conexões Discord em background (não bloqueia)
    def start_async
      return unless @enabled
      Thread.new do
        @presence.connect
        @presence.set_in_launcher if @presence.connected?
      rescue
        nil
      end
    end

    # Chamado quando o Minecraft é iniciado
    def on_game_start(username:, version:, server: nil)
      Thread.new do
        if @presence.connected?
          @presence.set_playing(username: username, version: version, server: server)
        end
      rescue
        nil
      end
    end

    # Convite multiplayer no Discord
    def invite_to_server(username:, version:, server_address: nil,
                         discord_user_id: nil, discord_username: nil)
      return { success: false, reason: "Bot não habilitado." } unless @bot.enabled?

      if discord_user_id.to_s.strip != ""
        return @bot.send_discord_invite(
          username: username,
          version: version,
          discord_user_id: discord_user_id,
          discord_username: discord_username,
          server_address: server_address
        )
      end

      ok = @bot.post_server_invite(username: username, version: version, server_address: server_address)
      ok ? { success: true, delivery: :channel } : { success: false, reason: "Falha ao postar no Discord." }
    end

    def create_server_invite
      @bot.create_server_invite
    end

    def stop
      @presence.disconnect
    rescue
      nil
    end

    def presence_connected?
      @presence.connected?
    end
  end
end
