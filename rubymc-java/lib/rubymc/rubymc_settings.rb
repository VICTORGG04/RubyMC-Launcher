# frozen_string_literal: true

require 'yaml'

module RubyMC
  # Leitura centralizada do config/settings.yml.
  # Mantém compatibilidade com Hash comum e evita espalhar YAML.load_file pelo projeto.
  class Settings
    attr_reader :root, :path, :data

    def initialize(root)
      @root = File.expand_path(root)
      @path = File.join(@root, 'config', 'settings.yml')
      @data = load
    end

    def load
      return {} unless File.file?(path)

      YAML.safe_load(File.read(path), permitted_classes: [Symbol], aliases: true) || {}
    rescue StandardError
      {}
    end

    def [](key)
      data[key.to_s]
    end

    def dig(*keys)
      data.dig(*keys.map(&:to_s))
    end

    def discord
      data.fetch('discord', {}) || {}
    end

    def community_server
      data.fetch('community_server', {}) || {}
    end

    def save(new_data = nil)
      @data = new_data if new_data
      File.write(@path, YAML.dump(@data))
    rescue StandardError => e
      puts "[ERRO] Falha ao salvar settings: #{e.message}"
    end
  end
end
