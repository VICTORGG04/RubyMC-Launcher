# frozen_string_literal: true

require_relative 'community_server'
require_relative 'modpack_manager'

module MinecraftRubyLauncher
  # Ponte entre a GUI e o launcher existente.
  #
  # Uso esperado no fluxo de lançamento:
  #   context = MinecraftRubyLauncher::LauncherExtensions.context_from_env(settings)
  #   # Passe context[:minecraft_version], context[:game_directory] e
  #   # context[:extra_game_args] para o MinecraftManager ao iniciar o jogo.
  module LauncherExtensions
    module_function

    def context_from_env(settings = {})
      modpack_id = ENV['MCRUBY_MODPACK_ID'].to_s
      join_server = ENV['MCRUBY_JOIN_COMMUNITY_SERVER'].to_s == '1'

      context = {
        modpack_id: modpack_id.empty? ? nil : modpack_id,
        minecraft_version: nil,
        loader: nil,
        loader_version: nil,
        game_directory: nil,
        extra_game_args: []
      }

      if context[:modpack_id]
        manager = ModpackManager.new(settings)
        server = join_server ? CommunityServer.new(settings) : nil
        context.merge!(manager.launch_options(context[:modpack_id], community_server: server))
      elsif join_server
        context[:extra_game_args] = CommunityServer.new(settings).game_args
      end

      context
    end

    def merge_launch_options(base_options, settings = {})
      base_options = (base_options || {}).dup
      context = context_from_env(settings)

      base_options[:version] ||= context[:minecraft_version] if context[:minecraft_version]
      base_options[:minecraft_version] ||= context[:minecraft_version] if context[:minecraft_version]
      base_options[:game_directory] ||= context[:game_directory] if context[:game_directory]
      base_options[:extra_game_args] = Array(base_options[:extra_game_args]) + Array(context[:extra_game_args])
      base_options[:loader] ||= context[:loader] if context[:loader]
      base_options[:loader_version] ||= context[:loader_version] if context[:loader_version]

      base_options
    end
  end
end
