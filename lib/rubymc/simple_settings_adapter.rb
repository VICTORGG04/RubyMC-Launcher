# frozen_string_literal: true

require "yaml"
require "fileutils"

module RubyMC
  # Adaptador simples para config/settings.yml.
  # Ele fornece a mesma interface esperada por ServerVersionManager:
  # - data
  # - dig(...)
  # - save(data)
  class SimpleSettingsAdapter
    attr_reader :path, :data

    def initialize(path)
      @path = path
      FileUtils.mkdir_p(File.dirname(@path))
      @data = load_data
    end

    def dig(*keys)
      @data.dig(*keys)
    end

    def save(new_data = @data)
      @data = stringify_keys(new_data || {})
      File.write(@path, YAML.dump(@data))
      @data
    end

    private

    def load_data
      return {} unless File.exist?(@path)

      parsed = YAML.safe_load(File.read(@path), permitted_classes: [Time, Symbol], aliases: true)
      stringify_keys(parsed || {})
    rescue StandardError
      {}
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), output|
          output[key.to_s] = stringify_keys(item)
        end
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
    end
  end
end
