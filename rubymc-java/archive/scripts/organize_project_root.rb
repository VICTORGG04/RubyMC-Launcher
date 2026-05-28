#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

ROOT = File.expand_path('..', __dir__)
APPLY = ARGV.include?('--apply')

MOVES = {
  'setup_channels.rb' => 'scripts/setup_channels.rb',
  'setup_discord_forum.rb' => 'scripts/setup_discord_forum.rb',
  'setup_discord_welcome.rb' => 'scripts/setup_discord_welcome.rb',
  'test_discord_bot.rb' => 'test/test_discord_bot.rb',
  'test_discord_invite.rb' => 'test/test_discord_invite.rb',
  'PATCH_SUMMARY.md' => 'docs/PATCH_SUMMARY.md'
}.freeze

DIRS = %w[bin docs scripts test web web/assets web/assets/css web/assets/js].freeze

puts APPLY ? '== Organizando raiz do projeto ==' : '== Simulação de organização da raiz =='
puts "Raiz: #{ROOT}"
puts

DIRS.each do |dir|
  path = File.join(ROOT, dir)
  if Dir.exist?(path)
    puts "OK   pasta existe: #{dir}/"
  else
    puts "MAKE pasta: #{dir}/"
    FileUtils.mkdir_p(path) if APPLY
  end
end
puts

MOVES.each do |from, to|
  src = File.join(ROOT, from)
  dst = File.join(ROOT, to)

  unless File.exist?(src)
    puts "SKIP não existe: #{from}"
    next
  end

  if File.exist?(dst)
    puts "SKIP destino já existe: #{to}"
    next
  end

  puts "MOVE #{from} -> #{to}"
  if APPLY
    FileUtils.mkdir_p(File.dirname(dst))
    FileUtils.mv(src, dst)
  end
end

puts
puts 'Mantidos na raiz por serem entrada/configuração principal:'
%w[launcher.rb launcher_gui.rb bot_daemon.rb Gemfile Gemfile.lock README.md .gitignore config.ru].each do |file|
  puts "- #{file}" if File.exist?(File.join(ROOT, file))
end

puts
puts APPLY ? 'Organização concluída.' : 'Simulação concluída. Use --apply para mover.'
