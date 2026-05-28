# frozen_string_literal: true

require_relative 'rubymc_settings'
require_relative 'discord_config'
require_relative 'discord_bot_service'

module RubyMC
  class DiscordPanelActions
    def initialize(root:)
      @root = File.expand_path(root)
      @settings_data = RubyMC::Settings.new(@root).data
      @discord_config = RubyMC::DiscordConfig.new(@settings_data)
    end

    def validate
      report = @discord_config.validation_report
      {
        ok: report[:ok],
        message: report[:ok] ? 'Configuração Discord validada com sucesso.' : 'Discord precisa de ajustes.',
        problems: report[:errors] + report[:warnings],
        summary: report[:summary],
        channels: report[:channels],
        roles: report[:roles]
      }
    end

    def test_logs_channel
      ensure_discord_bot_service!

      service = RubyMC::DiscordBotService.new(@settings_data)
      result = service.send_log_message("💎 RubyMC Launcher: teste de canal de logs enviado pelo painel web às #{Time.now.strftime('%H:%M:%S')}.")
      { ok: true, message: "Mensagem de teste enviada ao canal de logs Discord (#{result[:channel_id]})." }
    rescue => e
      retry_with_inline_bot(e)
    end

    def bot_status
      summary = @discord_config.summary
      {
        ok: summary[:bot_enabled] && summary[:token_configured] && summary[:guild_id_configured],
        message: status_message(summary),
        summary: summary
      }
    end

    private

    def ensure_discord_bot_service!
      raise 'RubyMC::DiscordBotService não está disponível.' unless defined?(RubyMC::DiscordBotService)
    end

    def retry_with_inline_bot(original_error)
      raise original_error unless defined?(DiscordIntegration::Bot)

      if @discord_config.bot_enabled? && @discord_config.token_configured?
        bot = DiscordIntegration::Bot.new(@settings_data)
        msg = bot.post_message(@discord_config.log_channel_id, "💎 RubyMC Launcher: teste de log enviado pelo painel web (fallback) às #{Time.now.strftime('%H:%M:%S')}.")
        if msg
          { ok: true, message: 'Mensagem de teste enviada via fallback (DiscordIntegration::Bot).' }
        else
          raise original_error
        end
      else
        raise original_error
      end
    end

    def status_message(summary)
      if !summary[:bot_enabled]
        'Bot Discord está desabilitado (bot_enabled: false).'
      elsif !summary[:token_configured]
        'Token do bot não configurado.'
      elsif !summary[:guild_id_configured]
        'ID do servidor Discord (guild_id) não configurado.'
      else
        "Bot configurado: #{summary[:channels_configured]}/#{summary[:channels_total]} canais, #{summary[:roles_configured]}/#{summary[:roles_total]} cargos."
      end
    end
  end
end