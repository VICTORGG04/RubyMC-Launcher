# frozen_string_literal: true

module RubyMC
  # Normaliza e valida a configuração Discord em config/settings.yml.
  # Esta classe não envia requests para o Discord; ela só verifica presença/formato.
  class DiscordConfig
    CHANNEL_LABELS = {
      'welcome_channel_id' => 'Boas-vindas',
      'rules_channel_id' => 'Regras',
      'announcements_channel_id' => 'Anúncios / Notícias',
      'updates_channel_id' => 'Atualizações / Comunicados',
      'new_members_channel_id' => 'Novos membros',
      'general_channel_id' => 'Chat geral / chat-com-rubymc',
      'rubymc_channel_id' => 'Canal RubyMC principal',
      'community_channel_id' => 'Comunidade RubyMC',
      'forum_channel_id' => 'Discussão / Fórum',
      'bugs_channel_id' => 'Reporte de bugs',
      'ban_channel_id' => 'Reporte de banimento',
      'suggestions_channel_id' => 'Sugestões',
      'support_channel_id' => 'Suporte',
      'logs_channel_id' => 'Logs do bot',
      'modpacks_channel_id' => 'Modpacks ativos'
    }.freeze

    ROLE_LABELS = {
      'member_role_id' => 'Membro',
      'player_role_id' => 'Jogador',
      'staff_role_id' => 'Staff',
      'admin_role_id' => 'Admin',
      'bot_role_id' => 'RubyMC Bot'
    }.freeze

    PLACEHOLDER_PATTERN = /\A(?:\$\{|ID_DO_|COLE_AQUI|SEU_|TOKEN|APPLICATION|GUILD|CANAL|CARGO)/i
    DISCORD_ID_PATTERN = /\A\d{15,25}\z/

    attr_reader :settings

    def initialize(settings)
      @settings = settings || {}
    end

    def discord
      settings.fetch('discord', {}) || {}
    end

    def channels
      discord.fetch('channels', {}) || {}
    end

    def roles
      discord.fetch('roles', {}) || {}
    end

    def bot_enabled?
      value = discord['bot_enabled']
      return true if value == true
      %w[true 1 yes sim on ativo enabled].include?(value.to_s.strip.downcase)
    end

    def raw_token
      env_token = ENV['RUBYMC_DISCORD_BOT_TOKEN'].to_s.strip
      return env_token unless env_token.empty?

      resolve_env_reference(discord['bot_token']).to_s.strip
    end

    def resolve_env_reference(value)
      text = value.to_s.strip
      match = text.match(/\A\$\{([A-Z0-9_]+)\}\z/)
      return text unless match

      ENV[match[1]].to_s.strip
    end

    def bot_token
      raw_token.sub(/\ABot\s+/i, '').strip
    end

    def token_configured?
      present_value?(bot_token)
    end

    def client_id
      discord['client_id'].to_s.strip
    end

    def guild_id
      discord['guild_id'].to_s.strip
    end

    # Busca primeiro em discord.channels e depois no nível direto de discord.
    # Isso mantém compatibilidade com invite_channel_id, que já existia fora de channels.
    def channel_id(key)
      key = key.to_s
      nested = channels[key].to_s.strip
      return nested unless nested.empty?
      discord[key].to_s.strip
    end

    def role_id(key)
      roles[key.to_s].to_s.strip
    end

    def valid_id?(value)
      value.to_s.match?(DISCORD_ID_PATTERN)
    end

    def present_value?(value)
      text = value.to_s.strip
      !text.empty? && !text.match?(PLACEHOLDER_PATTERN)
    end

    def configured_channels
      CHANNEL_LABELS.keys.select { |key| valid_id?(channel_id(key)) }
    end

    def configured_roles
      ROLE_LABELS.keys.select { |key| valid_id?(role_id(key)) }
    end

    def missing_channels
      CHANNEL_LABELS.keys.reject { |key| valid_id?(channel_id(key)) }
    end

    def missing_roles
      ROLE_LABELS.keys.reject { |key| valid_id?(role_id(key)) }
    end

    def log_channel_id
      %w[logs_channel_id support_channel_id rubymc_channel_id general_channel_id].map { |key| channel_id(key) }.find { |id| valid_id?(id) }
    end

    def summary
      {
        bot_enabled: bot_enabled?,
        client_id_configured: valid_id?(client_id),
        guild_id_configured: valid_id?(guild_id),
        token_configured: token_configured?,
        channels_configured: configured_channels.size,
        channels_total: CHANNEL_LABELS.size,
        roles_configured: configured_roles.size,
        roles_total: ROLE_LABELS.size,
        logs_channel_configured: valid_id?(channel_id('logs_channel_id')),
        fallback_log_channel_configured: valid_id?(log_channel_id),
        bot_role_configured: valid_id?(role_id('bot_role_id'))
      }
    end

    def validation_report
      warnings = []
      errors = []

      errors << 'discord.guild_id não está configurado com um ID válido.' unless valid_id?(guild_id)
      warnings << 'discord.client_id não está configurado com um ID válido. Rich Presence pode não funcionar.' unless valid_id?(client_id)

      if bot_enabled?
        errors << 'discord.bot_token está vazio, inválido ou ainda usa placeholder.' unless token_configured?
        warnings << 'discord.channels.logs_channel_id não está configurado; será usado fallback para suporte/RubyMC se existir.' unless valid_id?(channel_id('logs_channel_id'))
        warnings << 'discord.roles.bot_role_id não foi configurado; confirme a hierarquia do cargo do bot.' unless valid_id?(role_id('bot_role_id'))
      else
        warnings << 'discord.bot_enabled está false/inativo; ações reais do bot, como enviar log ou validar token remoto, não serão executadas.'
      end

      CHANNEL_LABELS.each do |key, label|
        value = channel_id(key)
        next if value.empty?
        errors << "Canal #{label} (#{key}) tem ID inválido: #{value}" unless valid_id?(value)
      end

      ROLE_LABELS.each do |key, label|
        value = role_id(key)
        next if value.empty?
        errors << "Cargo #{label} (#{key}) tem ID inválido: #{value}" unless valid_id?(value)
      end

      {
        ok: errors.empty?,
        errors: errors,
        warnings: warnings,
        summary: summary,
        channels: CHANNEL_LABELS.keys.to_h { |key| [key, { label: CHANNEL_LABELS[key], id: channel_id(key), configured: valid_id?(channel_id(key)) }] },
        roles: ROLE_LABELS.keys.to_h { |key| [key, { label: ROLE_LABELS[key], id: role_id(key), configured: valid_id?(role_id(key)) }] }
      }
    end

    def bot_action_errors
      errors = []
      errors << 'discord.bot_enabled está false. Altere para true para usar ações reais do bot.' unless bot_enabled?
      errors << 'discord.bot_token não está configurado ou ainda usa placeholder.' unless token_configured?
      errors << 'discord.guild_id não está configurado com ID válido.' unless valid_id?(guild_id)
      errors
    end
  end
end
