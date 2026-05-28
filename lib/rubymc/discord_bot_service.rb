# frozen_string_literal: true

require 'json'
require 'httparty'
require_relative 'discord_config'

module RubyMC
  # Cliente mínimo para ações do bot Discord via REST API.
  # Usado pelo painel para validar token, enviar logs e preparar automações de cargo.
  class DiscordBotService
    API_BASE = 'https://discord.com/api/v10'
    TEXT_CHANNEL_TYPES = [0, 5].freeze # GUILD_TEXT, GUILD_ANNOUNCEMENT
    FORUM_CHANNEL_TYPES = [15].freeze # GUILD_FORUM

    SIMULATED_CHANNELS = (1..20).map do |i|
      { 'id' => format('9%018d', i), 'name' => "canal-#{i}", 'type' => i <= 3 ? 0 : 5, 'position' => i }
    end.freeze

    SIMULATED_ROLES = [
      { 'id' => '800000000000000001', 'name' => '@everyone', 'color' => 0, 'position' => 0 },
      { 'id' => '800000000000000002', 'name' => 'Membro', 'color' => 5_798_139, 'position' => 1 },
      { 'id' => '800000000000000003', 'name' => 'Jogador', 'color' => 5_791_383, 'position' => 2 },
      { 'id' => '800000000000000004', 'name' => 'Staff', 'color' => 15_063_766, 'position' => 3 },
      { 'id' => '800000000000000005', 'name' => 'Admin', 'color' => 15_115_297, 'position' => 4 },
      { 'id' => '800000000000000006', 'name' => 'RubyMC Bot', 'color' => 15_112_579, 'position' => 5 },
      { 'id' => '800000000000000007', 'name' => 'VIP', 'color' => 16_770_816, 'position' => 6 },
      { 'id' => '800000000000000008', 'name' => 'Moderador', 'color' => 15_063_766, 'position' => 7 }
    ].freeze

    SIMULATED_MEMBERS = (1..20).map do |i|
      {
        'user' => {
          'id' => format('7%018d', i),
          'username' => "Jogador#{i}",
          'global_name' => "Jogador #{i}",
          'discriminator' => '0',
          'avatar' => nil
        },
        'roles' => i <= 2 ? ['800000000000000005'] : (i <= 5 ? ['800000000000000004'] : []),
        'joined_at' => (Time.now - (i * 86_400)).utc.strftime('%Y-%m-%dT%H:%M:%S.000Z')
      }
    end.freeze

    attr_reader :config

    def initialize(settings, simulate: false)
      @config = DiscordConfig.new(settings)
      @simulate = simulate
    end

    def simulate?
      @simulate
    end

    def validate_remote!
      return simulate_validate! if simulate?

      ensure_bot_ready!

      bot = request(:get, '/users/@me')
      guild = request(:get, "/guilds/#{config.guild_id}")
      channels = request(:get, "/guilds/#{config.guild_id}/channels")
      roles = request(:get, "/guilds/#{config.guild_id}/roles")
      guild_counts = request(:get, "/guilds/#{config.guild_id}?with_counts=true")

      {
        ok: true,
        bot: { id: bot['id'], username: bot['username'], discriminator: bot['discriminator'] },
        guild: { id: guild['id'], name: guild['name'] },
        channels_count: channels.is_a?(Array) ? channels.size : 0,
        roles_count: roles.is_a?(Array) ? roles.size : 0,
        members_count: guild_counts['approximate_member_count'] || 0,
        presence_count: guild_counts['approximate_presence_count'] || 0
      }
    end

    def simulate_validate!
      {
        ok: true,
        bot: { id: '123456789012345678', username: 'RubyMC Bot (Simulado)', discriminator: '0' },
        guild: { id: config.guild_id.to_s, name: 'RubyMC Community (Simulado)' },
        channels: SIMULATED_CHANNELS,
        roles: SIMULATED_ROLES,
        channels_count: 20,
        roles_count: 8,
        members_count: 20,
        presence_count: 5,
        members: SIMULATED_MEMBERS
      }
    end

    def send_log_message(message)
      return { ok: true, simulated: true, channel_id: '900000000000000001' } if simulate?

      ensure_bot_ready!

      channel_id = config.log_channel_id
      raise 'Nenhum canal de logs/suporte/RubyMC foi configurado para envio de mensagem.' unless config.valid_id?(channel_id)

      payload = {
        content: message.to_s[0, 1900],
        allowed_mentions: { parse: [] }
      }
      request(:post, "/channels/#{channel_id}/messages", payload)
      { ok: true, channel_id: channel_id }
    end

    def send_channel_message(channel_id, message)
      return { ok: true, simulated: true, channel_id: channel_id } if simulate?

      ensure_bot_ready!
      ch = request(:get, "/channels/#{channel_id}")

      if FORUM_CHANNEL_TYPES.include?(ch['type'])
        payload = {
          name: "Postagem do Bot",
          message: {
            content: message.to_s[0, 1900],
            allowed_mentions: { parse: [] }
          }
        }
        request(:post, "/channels/#{channel_id}/threads", payload)
      else
        payload = {
          content: message.to_s[0, 1900],
          allowed_mentions: { parse: [] }
        }
        request(:post, "/channels/#{channel_id}/messages", payload)
      end

      { ok: true, channel_id: channel_id }
    end

    def assign_role(discord_user_id, role_key = 'player_role_id')
      return { ok: true, simulated: true, user_id: discord_user_id, role_id: '800000000000000003', role_key: role_key } if simulate?

      ensure_bot_ready!
      user_id = discord_user_id.to_s.strip
      role_id = config.role_id(role_key)

      raise 'ID do usuário Discord inválido.' unless config.valid_id?(user_id)
      raise "Cargo #{role_key} não configurado." unless config.valid_id?(role_id)

      request(:put, "/guilds/#{config.guild_id}/members/#{user_id}/roles/#{role_id}")
      { ok: true, user_id: user_id, role_id: role_id, role_key: role_key }
    end

    def remove_role(discord_user_id, role_key = 'player_role_id')
      return { ok: true, simulated: true, user_id: discord_user_id, role_id: '800000000000000003', role_key: role_key } if simulate?

      ensure_bot_ready!
      user_id = discord_user_id.to_s.strip
      role_id = config.role_id(role_key)

      raise 'ID do usuário Discord inválido.' unless config.valid_id?(user_id)
      raise "Cargo #{role_key} não configurado." unless config.valid_id?(role_id)

      request(:delete, "/guilds/#{config.guild_id}/members/#{user_id}/roles/#{role_id}")
      { ok: true, user_id: user_id, role_id: role_id, role_key: role_key }
    end

    def create_invite(channel_key = 'invite_channel_id', max_age: nil, max_uses: nil)
      return { ok: true, simulated: true, code: 'rubymc-simulado', url: 'https://discord.gg/rubymc-simulado', channel_id: '900000000000000001' } if simulate?

      ensure_bot_ready!
      channel_id = config.channel_id(channel_key)
      raise "Canal #{channel_key} não configurado." unless config.valid_id?(channel_id)

      payload = {
        max_age: Integer(max_age || config.discord['invite_max_age_seconds'] || 86_400),
        max_uses: Integer(max_uses || config.discord['invite_max_uses'] || 1),
        temporary: false,
        unique: true
      }

      response = request(:post, "/channels/#{channel_id}/invites", payload)
      { ok: true, code: response['code'], url: "https://discord.gg/#{response['code']}", channel_id: channel_id }
    end

    def text_channel?(channel_id)
      return true if simulate?

      ensure_bot_ready!
      ch = request(:get, "/channels/#{channel_id}")
      TEXT_CHANNEL_TYPES.include?(ch['type']) || FORUM_CHANNEL_TYPES.include?(ch['type'])
    end

    private

    def ensure_bot_ready!
      errors = config.bot_action_errors
      raise errors.join(' | ') unless errors.empty?
    end

    def request(method, path, payload = nil)
      options = {
        headers: {
          'Authorization' => "Bot #{config.bot_token}",
          'Content-Type' => 'application/json',
          'User-Agent' => 'RubyMC-Launcher/1.0'
        }
      }
      options[:body] = JSON.generate(payload) unless payload.nil?

      response = HTTParty.send(method, "#{API_BASE}#{path}", options)
      return parse_response(response) if response.code.between?(200, 299)

      body = parse_response(response)
      message = body.is_a?(Hash) ? (body['message'] || body['error'] || body.inspect) : body.to_s
      raise "Discord API HTTP #{response.code}: #{message}"
    end

    def parse_response(response)
      text = response.body.to_s
      text.empty? ? {} : JSON.parse(text)
    rescue JSON::ParserError
      response.body.to_s
    end
  end
end
