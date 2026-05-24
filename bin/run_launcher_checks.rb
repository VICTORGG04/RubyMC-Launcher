#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'rbconfig'

ROOT = File.expand_path('..', __dir__)
IGNORE_DIRS = %w[.git .bundle vendor tmp log node_modules].freeze

puts '== Minecraft Ruby Launcher :: checks =='
puts "Raiz: #{ROOT}"
puts "Ruby: #{RUBY_VERSION}"
puts

required_files = %w[
  Gemfile
  launcher.rb
  launcher_gui.rb
  lib/web_launcher_app.rb
  lib/modpack_manager.rb
  lib/community_server.rb
  web/index.html
  web/assets/css/launcher.css
  web/assets/js/launcher.js
  config/settings.yml
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

exit(syntax_errors.empty? ? 0 : 1)
