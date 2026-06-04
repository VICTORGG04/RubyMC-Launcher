# frozen_string_literal: true

require 'fileutils'

module RubyMC
  class WebLauncherApp
    private

    def version_manager
      return @version_manager if defined?(@version_manager) && @version_manager
      return nil unless defined?(RubyMC::ServerVersionManager)
      return nil unless defined?(RubyMC::Settings)

      settings = RubyMC::Settings.new(root)
      java_settings = settings.dig('servers', 'java') || {}
      configured_dir = java_settings['path'].to_s.strip
      server_dir = configured_dir.empty? ? File.join(Dir.home, 'Servidores', 'ServidorMinecraftJava') : File.expand_path(configured_dir)

      FileUtils.mkdir_p(File.join(server_dir, 'versions'))
      @version_manager = RubyMC::ServerVersionManager.new(server_dir, settings)
    rescue StandardError => e
      log('ERROR', "Falha ao criar version manager Java: #{e.message}") if respond_to?(:log)
      nil
    end
  end
end
