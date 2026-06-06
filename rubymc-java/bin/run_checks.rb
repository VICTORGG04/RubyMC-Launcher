#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'yaml'

ROOT = File.expand_path('..', __dir__)
IGNORE_DIRS = %w[.git .bundle vendor tmp log node_modules].freeze

puts '== Minecraft Ruby Launcher :: checks =='
puts "Raiz: #{ROOT}"
puts "Ruby: #{RUBY_VERSION}"
puts

required_files = %w[
  Gemfile
  app/server.rb
  app/console.rb
  lib/web_launcher_app.rb
  lib/rubymc/modpack_manager.rb
  lib/rubymc/community_server.rb
  web/index.html
  web/assets/css/launcher.css
  web/assets/js/launcher.js
  config/settings.yml
  bin/rubymc-player
]

missing = required_files.reject { |file| File.exist?(File.join(ROOT, file)) }
if missing.empty?
  puts '✅ Arquivos essenciais encontrados.'
else
  puts '⚠️ Arquivos ausentes:'
  missing.each { |file| puts "   - #{file}" }
end
puts

ruby_files = Dir.glob(File.join(ROOT, '**/*.rb')).reject do |path|
  relative = path.delete_prefix(ROOT + '/')
  IGNORE_DIRS.any? { |dir| relative.start_with?(dir + '/') }
end

syntax_errors = []
ruby_files.each do |file|
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-c', file)
  next if status.success?

  syntax_errors << [file.delete_prefix(ROOT + '/'), stdout + stderr]
end

if syntax_errors.empty?
  puts "✅ Sintaxe Ruby OK em #{ruby_files.size} arquivo(s)."
else
  puts '❌ Erros de sintaxe Ruby:'
  syntax_errors.each do |file, error|
    puts "--- #{file}"
    puts error
  end
end
puts

if File.file?(File.join(ROOT, 'Gemfile'))
  gemfile = File.read(File.join(ROOT, 'Gemfile'))
  if gemfile.include?('glimmer-dsl-tk')
    puts '⚠️ Gemfile ainda contém glimmer-dsl-tk. Remova para evitar erro com tk 0.4.0 no Ubuntu 24.04.'
  else
    puts '✅ Gemfile sem glimmer-dsl-tk.'
  end

  stdout, stderr, status = Open3.capture3('bundle', 'check', chdir: ROOT)
  if status.success?
    puts '✅ bundle check OK.'
  else
    puts '⚠️ bundle check ainda não passou:'
    puts stdout
    puts stderr
  end
end
puts

puts '== Verificação LM Studio =='
begin
  require_relative '../lib/rubymc/lm_studio_service'

  settings_path = File.join(ROOT, 'config', 'settings.yml')
  if File.exist?(settings_path)
    settings = YAML.safe_load(File.read(settings_path))
    lm_cfg = settings.dig("ai_support", "lm_studio")

    if lm_cfg
      host = lm_cfg.fetch("host", RubyMC::LMStudioService::LM_STUDIO_DEFAULTS[:host])
      model = lm_cfg.fetch("model", RubyMC::LMStudioService::LM_STUDIO_DEFAULTS[:model])
      enabled = lm_cfg["enabled"] == true

      puts "   Host: #{host}"
      puts "   Modelo: #{model}"
      puts "   Habilitado: #{enabled}"

      if enabled
        status = RubyMC::LMStudioService.status(settings)
        if status[:ok]
          puts "✅ LM Studio online (#{status[:models].size} modelo(s) disponível(is))."
        else
          error_msg = status[:error] || "Não foi possível conectar. Execute: lms server start"
          puts "⚠️  LM Studio offline: #{error_msg}"
        end
      else
        puts "⏭️  LM Studio desabilitado — teste de conectividade ignorado."
      end
    else
      puts "⚠️  Seção 'ai_support.lm_studio' não encontrada em config/settings.yml"
    end
  else
    puts "⚠️  config/settings.yml não encontrado"
  end
rescue => e
  puts "❌ Erro ao verificar LM Studio: #{e.message}"
end
puts

exit(syntax_errors.empty? ? 0 : 1)
