#!/usr/bin/env ruby
# frozen_string_literal: true

# CLI wrapper for RubyMC AI — used by ./rubymc ai and ./rubymc ai-chat

require_relative 'ai_support_service'
require_relative 'rubymc_settings'
require_relative 'discord_config'
require_relative 'modpack_manager'

ROOT = File.expand_path('..', __dir__)

def load_context
  settings = RubyMC::Settings.new(ROOT).data rescue {}
  discord_cfg = RubyMC::DiscordConfig.new(settings)
  summary = discord_cfg.summary rescue {}

  modpacks = []
  begin
    if defined?(MinecraftRubyLauncher::ModpackManager)
      manager = MinecraftRubyLauncher::ModpackManager.new(settings)
      modpacks = manager.list_profiles.map { |p| { name: p.respond_to?(:name) ? p.name : p.to_s } }
    end
  rescue StandardError
    modpacks = []
  end

  server_addr = settings.dig('discord', 'server_address') || settings.dig('minecraft', 'server_address') || 'não configurado'

  {
    discord: summary,
    modpacks: modpacks,
    server: { address: server_addr }
  }
end

mode = ARGV[0] # 'ask' or 'chat'
question = ARGV[1..].join(' ')

service = RubyMC::AISupportService.new(root: ROOT)
health = service.health

unless health[:ok]
  warn_msg = "\e[33m[IA] #{health[:message]}\e[0m"
  warn_msg += "\n\e[33m[IA] #{health[:error]}\e[0m" if health[:error]
  warn_msg += "\n\e[33m[IA] Certifique-se de que o Ollama está rodando e o modelo foi baixado.\e[0m"

  if mode == 'ask'
    puts warn_msg
    exit 1
  else
    puts warn_msg
    puts "\e[33m[IA] Entrando em modo chat mesmo assim. As respostas podem falhar.\e[0m"
  end
end

case mode
when 'ask'
  if question.empty?
    puts "\e[31m[ERRO] Use: ./rubymc ai \"sua pergunta\"\e[0m"
    exit 1
  end
  context = load_context
  result = service.support_answer(question, context: context)
  if result[:ok]
    puts result[:answer]
  else
    puts "\e[33m#{result[:answer]}\e[0m"
    exit 1
  end

when 'chat'
  puts "\e[35m╔══════════════════════════════════════════╗\e[0m"
  puts "\e[35m║       RubyMC IA — Modo Chat            ║\e[0m"
  puts "\e[35m╚══════════════════════════════════════════╝\e[0m"
  puts "\e[32mDigite sua pergunta ou 'sair' para encerrar.\e[0m"
  puts

  loop do
    print "\e[36m❯\e[0m "
    input = $stdin.gets
    break unless input
    input = input.strip
    break if input.empty?
    break if %w[sair exit quit q].include?(input.downcase)

    context = load_context
    result = service.support_answer(input, context: context)
    if result[:ok]
      puts
      puts result[:answer]
    else
      puts "\e[33m#{result[:answer]}\e[0m"
    end
    puts
  end
  puts "\e[35mChat encerrado.\e[0m"

else
  puts "\e[31m[ERRO] Modo desconhecido: #{mode}\e[0m"
  exit 1
end
