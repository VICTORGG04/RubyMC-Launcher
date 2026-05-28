# frozen_string_literal: true

require_relative 'rubymc_settings'
require_relative 'discord_config'

module RubyMC
  class BotConfigBridge
    CHANNEL_ALIASES = {
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

    attr_reader :data

    def initialize(settings_hash)
      @data = settings_hash || {}
      @discord_cfg = nil
    end

    def discord_config
      @discord_cfg ||= RubyMC::DiscordConfig.new(@data)
    end

    def bot_token
      dc = discord_config
      raw = dc.raw_token
      raw.sub(/\ABot\s+/i, '').strip
    end

    def guild_id
      discord_config.guild_id
    end

    def channels_for_daemon
      dc = discord_config
      {
        bem_vindos: dc.channel_id('welcome_channel_id'),
        novos_membros: dc.channel_id('new_members_channel_id'),
        noticias: dc.channel_id('announcements_channel_id'),
        comunicados: dc.channel_id('updates_channel_id'),
        chat_rubymc: dc.channel_id('general_channel_id'),
        regras: dc.channel_id('rules_channel_id'),
        sugestoes: dc.channel_id('suggestions_channel_id'),
        bugs: dc.channel_id('bugs_channel_id'),
        logs: dc.channel_id('logs_channel_id'),
        modpacks: dc.channel_id('modpacks_channel_id'),
        suporte: dc.channel_id('support_channel_id'),
        servidor_oficial: dc.channel_id('server_channel_id')
      }
    end

    def channel_id(key)
      dc = discord_config
      canonical = CHANNEL_ALIASES.fetch(key.to_s, key.to_s)
      dc.channel_id(canonical)
    end

    def legacy_channel_hash
      {
        bem_vindos: channel_id('bem_vindos'),
        novos_membros: channel_id('novos_membros'),
        noticias: channel_id('noticias'),
        comunicados: channel_id('comunicados'),
        chat_rubymc: channel_id('chat_rubymc'),
        regras: channel_id('regras'),
        sugestoes: channel_id('sugestoes'),
        bugs: channel_id('bugs'),
        logs: channel_id('logs'),
        modpacks: channel_id('modpacks'),
        suporte: channel_id('suporte'),
        servidor_oficial: channel_id('servidor_oficial')
      }
    end
  end
end