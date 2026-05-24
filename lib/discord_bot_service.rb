# frozen_string_literal: true

require 'json'
require 'httparty'
require_relative 'discord_config'

module RubyMC
  # Cliente mínimo para ações do bot Discord via REST API.
  # Usado pelo painel para validar token, enviar logs e preparar automações de cargo.
  class DiscordBotService
    API_BASE = 'https://discord.com/api/v10'

    attr_reader :config

    def initialize(settings)
      @config = DiscordConfig.new(settings)
    end

    def validate_remote!
      ensure_bot_ready!

      bot = request(:get, '/users/@me')
      guild = request(:get, "/guilds/#{config.guild_id}")
      channels = request(:get, "/guilds/#{config.guild_id}/channels")
      roles = request(:get, "/guilds/#{config.guild_id}/roles")

      {
        ok: true,
        bot: { id: bot['id'], username: bot['username'], discriminator: bot['discriminator'] },
        guild: { id: guild['id'], name: guild['name'] },
        channels_count: channels.is_a?(Array) ? channels.size : 0,
        roles_count: roles.is_a?(Array) ? roles.size : 0
      }
    end

    def send_log_message(message)
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

    def assign_role(discord_user_id, role_key = 'player_role_id')
      ensure_bot_ready!
      user_id = discord_user_id.to_s.strip
      role_id = config.role_id(role_key)

      raise 'ID do usuário Discord inválido.' unless config.valid_id?(user_id)
      raise "Cargo #{role_key} não configurado." unless config.valid_id?(role_id)

      request(:put, "/guilds/#{config.guild_id}/members/#{user_id}/roles/#{role_id}")
      { ok: true, user_id: user_id, role_id: role_id, role_key: role_key }
    end

    def remove_role(discord_user_id, role_key = 'player_role_id')
      ensure_bot_ready!
      user_id = discord_user_id.to_s.strip
      role_id = config.role_id(role_key)

      raise 'ID do usuário Discord inválido.' unless config.valid_id?(user_id)
      raise "Cargo #{role_key} não configurado." unless config.valid_id?(role_id)

      request(:delete, "/guilds/#{config.guild_id}/members/#{user_id}/roles/#{role_id}")
      { ok: true, user_id: user_id, role_id: role_id, role_key: role_key }
    end

    def create_invite(channel_key = 'invite_channel_id', max_age: nil, max_uses: nil)
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
