# frozen_string_literal: true

require 'socket'

module MinecraftRubyLauncher
  # Configuração do servidor público da comunidade.
  # Usado pela CLI e pela GUI para iniciar o Minecraft já conectado no servidor.
  class CommunityServer
    DEFAULT_PORT = 25_565

    attr_reader :name, :address, :description, :discord_url, :website_url

    def initialize(settings = {})
      settings = stringify_keys(settings || {})
      config = settings['community_server'] || settings.dig('minecraft', 'community_server') || {}

      @enabled = truthy?(config.fetch('enabled', true))
      @name = config['name'].to_s.empty? ? 'Servidor Público da Comunidade' : config['name'].to_s
      @address = (config['address'] || settings.dig('discord', 'server_address') || 'play.seuservidor.com:25565').to_s
      @description = config['description'].to_s
      @discord_url = config['discord_url'].to_s
      @website_url = config['website_url'].to_s
    end

    def enabled?
      @enabled && !host.empty?
    end

    def host
      parse_address.first
    end

    def port
      parse_address.last
    end

    def game_args
      return [] unless enabled?

      ['--server', host, '--port', port.to_s]
    end

    def status(timeout: 2)
      return :disabled unless enabled?

      Socket.tcp(host, port, connect_timeout: timeout) { true }
      :online
    rescue StandardError
      :offline
    end

    def online?(timeout: 2)
      status(timeout: timeout) == :online
    end

    def summary
      parts = [name, address]
      parts << description unless description.empty?
      parts.join(' — ')
    end

    private

    def parse_address
      raw = @address.strip
      return ['', DEFAULT_PORT] if raw.empty?

      if raw.start_with?('[') && raw.include?(']')
        # IPv6 no formato [::1]:25565
        host_part, port_part = raw.match(/\A\[(.+)\](?::(\d+))?\z/)&.captures
        return [host_part.to_s, (port_part || DEFAULT_PORT).to_i]
      end

      host_part, port_part = raw.split(':', 2)
      [host_part.to_s, (port_part || DEFAULT_PORT).to_i]
    end

    def truthy?(value)
      [true, 'true', '1', 1, 'yes', 'sim', 'on'].include?(value)
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify_keys(item) }
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
    end
  end
end
