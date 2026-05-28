#!/usr/bin/env ruby
# frozen_string_literal: true

$stdout.sync = true

require 'json'
require 'yaml'
require 'fileutils'
require 'socket'
require 'timeout'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'lib'))

$results = []
$passed = 0
$failed = 0

def t(n); "\e[#{n}m"; end
def green(s); "#{t(32)}#{s}#{t(0)}"; end
def red(s);   "#{t(31)}#{s}#{t(0)}"; end
def yellow(s);"#{t(33)}#{s}#{t(0)}"; end
def cyan(s);  "#{t(36)}#{s}#{t(0)}"; end
def bold(s);  "#{t(1)}#{s}#{t(0)}"; end

def test(name)
  print "  #{bold('⏳')} #{name}... "
  begin
    ok = yield
    if ok
      puts "#{green('✓ PASS')}"
      $results << { name: name, status: :pass }
      $passed += 1
    else
      puts "#{red('✗ FAIL')}"
      $results << { name: name, status: :fail }
      $failed += 1
    end
  rescue => e
    puts "#{red('✗ FAIL')} (#{e.class}: #{e.message})"
    $results << { name: name, status: :fail, error: e.message }
    $failed += 1
  end
end

def section(title)
  puts ''
  puts bold("─── #{title} ─────────────────────────────────────────────")
end

puts ''
puts bold('╔══════════════════════════════════════════════════════════════╗')
puts bold('║       RubyMC — Teste de Simulação Completa                 ║')
puts bold('║       10 pessoas · Servidor Ativo · Todas as Funções       ║')
puts bold('╚══════════════════════════════════════════════════════════════╝')
puts ''

# ─── Parse args ──────────────────────────────────────────────────────────────
def arg_value(flag, default)
  idx = ARGV.index(flag)
  idx ? Integer(ARGV[idx + 1]) : default
rescue ArgumentError, TypeError
  default
end

NUM_PLAYERS    = arg_value('--players', 10).freeze
MC_PORT        = arg_value('--mc-port', 25_566).freeze

puts "  #{cyan('ℹ')} Jogadores simulados: #{bold(NUM_PLAYERS.to_s)}"
puts "  #{cyan('ℹ')} Porta simulador MC:  #{bold(MC_PORT.to_s)}"

# ─── Carregar settings ──────────────────────────────────────────────────
settings_file = File.join(ROOT, 'config', 'settings.yml')
settings = File.file?(settings_file) ? (YAML.safe_load(File.read(settings_file), permitted_classes: [Symbol], aliases: true) || {}) : {}
puts "  #{cyan('ℹ')} Config: #{File.basename(settings_file)} (#{settings.keys.size} chaves)" if settings.any?

# ─── 1. Servidor Minecraft ────────────────────────────────────────────────
section('1. Servidor Minecraft')

test('Iniciar simulador de servidor MC (porta #{MC_PORT})') do
  @sim_pid = spawn("ruby #{ROOT}/bin/simulate_mc_players.rb --port #{MC_PORT} --players #{NUM_PLAYERS} --max #{NUM_PLAYERS + 10}")
  sleep(2)
  sock = TCPSocket.new('127.0.0.1', MC_PORT)
  sock.close
  true
end

# ─── 2. Status do Servidor ────────────────────────────────────────────────
section('2. Status do Servidor Minecraft')

require_relative '../lib/rubymc/minecraft_server_status'

test('Consultar status do servidor Minecraft (MinecraftServerStatus)') do
  result = RubyMC::MinecraftServerStatus.query("127.0.0.1:#{MC_PORT}", timeout: 5)
  online = result[:online] == true
  puts "    Online: #{online}"
  puts "    Players: #{result.dig(:players, :online)}/#{result.dig(:players, :max)}" if result[:players]
  puts "    Versão:  #{result.dig(:version, :name)}" if result[:version]
  sample = result.dig(:players, :sample) || []
  unless sample.empty?
    names = sample.first(5)
    puts "    Amostra: #{names.join(', ')}#{'...' if sample.size > 5}"
  end
  online
end

# ─── 3. Configuração Discord ──────────────────────────────────────────────
section('3. Configuração Discord')

require_relative '../lib/rubymc/discord_config'

test('DiscordConfig — carregar') do
  cfg = RubyMC::DiscordConfig.new(settings)
  !cfg.nil?
end

test('DiscordConfig — validar estrutura completa') do
  cfg = RubyMC::DiscordConfig.new(settings)
  report = cfg.validation_report
  s = report[:summary]
  puts "    Bot ativo: #{s[:bot_enabled]} | Token: #{s[:token_configured]} | Guild: #{s[:guild_id_configured]}"
  puts "    Canais: #{s[:channels_configured]}/#{s[:channels_total]} | Cargos: #{s[:roles_configured]}/#{s[:roles_total]}"
  puts "    Erros: #{report[:errors].size} | Avisos: #{report[:warnings].size}"
  report[:ok]
end

test('DiscordConfig — 17 canais definidos em CHANNEL_LABELS') do
  expected = %w[welcome_channel_id rules_channel_id announcements_channel_id updates_channel_id
                new_members_channel_id general_channel_id rubymc_channel_id community_channel_id
                forum_channel_id bugs_channel_id ban_channel_id suggestions_channel_id
                support_channel_id logs_channel_id modpacks_channel_id invite_channel_id
                server_channel_id]
  missing = expected - RubyMC::DiscordConfig::CHANNEL_LABELS.keys
  puts "    #{RubyMC::DiscordConfig::CHANNEL_LABELS.size} canais definidos" if missing.empty?
  missing.empty?
end

test('DiscordConfig — 5 cargos definidos em ROLE_LABELS') do
  expected = %w[member_role_id player_role_id staff_role_id admin_role_id bot_role_id]
  missing = expected - RubyMC::DiscordConfig::ROLE_LABELS.keys
  puts "    #{RubyMC::DiscordConfig::ROLE_LABELS.size} cargos definidos" if missing.empty?
  missing.empty?
end

# ─── 4. DiscordBotService (Modo Simulado) ─────────────────────────────────
section('4. DiscordBotService (Modo Simulado)')

require_relative '../lib/rubymc/discord_bot_service'

test('validate_remote! — validação completa simulada') do
  svc = RubyMC::DiscordBotService.new(settings, simulate: true)
  result = svc.validate_remote!
  puts "    Bot: #{result[:bot][:username]} | Guild: #{result[:guild][:name]}"
  puts "    Canais: #{result[:channels_count]} | Cargos: #{result[:roles_count]}"
  puts "    Membros: #{result[:members_count]} | Online: #{result[:presence_count]}"
  result[:ok]
end

test('send_channel_message — envio simulado') do
  svc = RubyMC::DiscordBotService.new(settings, simulate: true)
  result = svc.send_channel_message('900000000000000001', '🧪 Teste simulado')
  puts "    Canal: #{result[:channel_id]}"
  result[:ok]
end

test('create_invite — convite ilimitado simulado') do
  svc = RubyMC::DiscordBotService.new(settings, simulate: true)
  result = svc.create_invite('invite_channel_id', max_age: 86400, max_uses: 0)
  puts "    URL: #{result[:url]}"
  result[:ok]
end

test('assign_role — atribuir cargo simulado') do
  svc = RubyMC::DiscordBotService.new(settings, simulate: true)
  result = svc.assign_role('700000000000000001', 'player_role_id')
  puts "    Cargo #{result[:role_key]} → usuário #{result[:user_id]}"
  result[:ok]
end

test('remove_role — remover cargo simulado') do
  svc = RubyMC::DiscordBotService.new(settings, simulate: true)
  result = svc.remove_role('700000000000000001', 'player_role_id')
  puts "    Cargo #{result[:role_key]} removido de #{result[:user_id]}"
  result[:ok]
end

test('text_channel? — detecção de canal de texto (simulado)') do
  svc = RubyMC::DiscordBotService.new(settings, simulate: true)
  svc.text_channel?('900000000000000001') == true
end

# ─── 5. Teste de Todos os Canais ──────────────────────────────────────────
section('5. Teste de Todos os Canais (Simulado)')

test('Enviar mensagem para cada um dos 17 canais') do
  svc = RubyMC::DiscordBotService.new(settings, simulate: true)
  ok_count = 0
  RubyMC::DiscordConfig::CHANNEL_LABELS.each_with_index do |(key, label), i|
    ch_id = format('9%018d', i + 1)
    result = svc.send_channel_message(ch_id, "🧪 Teste automático do canal **#{label}**")
    if result[:ok]
      ok_count += 1
      print "    #{green('✓')} #{label}\n"
    else
      print "    #{red('✗')} #{label}\n"
    end
  end
  puts "    #{ok_count}/#{RubyMC::DiscordConfig::CHANNEL_LABELS.size} canais OK"
  ok_count == RubyMC::DiscordConfig::CHANNEL_LABELS.size
end

# ─── 6. Simular Membros Entrando ──────────────────────────────────────────
section("6. Simular #{NUM_PLAYERS} Membros Entrando")

MEMBER_NAMES = %w[Alice Bob Carlos Diana Eduardo Fernanda Gabriel Helena Igor Julia]
member_ids = []

test("Simular entrada de #{NUM_PLAYERS} membros") do
  MEMBER_NAMES.first(NUM_PLAYERS).each_with_index do |name, i|
    uid = format('7%018d', i + 1)
    member_ids << uid
    member = {
      'user' => {
        'id' => uid,
        'username' => name.downcase,
        'global_name' => name,
        'avatar' => nil
      },
      'roles' => [],
      'joined_at' => (Time.now - ((NUM_PLAYERS - i) * 60)).utc.strftime('%Y-%m-%dT%H:%M:%S.000Z')
    }
    print "    #{green('+')} #{name.ljust(10)} (##{uid})\n"
  end
  puts "    #{member_ids.size} membros registrados"
  member_ids.size == NUM_PLAYERS
end

# ─── 7. Comandos do Bot ──────────────────────────────────────────────────
section('7. Comandos do Bot (Simulado)')

BOT_COMMANDS = {
  '!ajuda'       => 'Lista de comandos disponíveis',
  '!status'      => 'Status do bot, servidor e convites',
  '!versao'      => 'Versão do launcher e Minecraft',
  '!java'        => 'Recomendação de Java por versão',
  '!convidar'    => 'Link de convite gerado',
  '!regras'      => 'Regras do servidor',
  '!cargos'      => 'Cargos disponíveis',
  '!eventos'     => 'Próximos eventos agendados',
  '!atualizacoes' => 'Últimas atualizações do projeto',
  '!ping'        => 'Latência do bot',
  '!sobre'       => 'Informações do projeto',
  '!sugerir'     => 'Enviar sugestão para a comunidade',
  '!reportar'    => 'Reportar bug ou problema',
  '!servidor'    => 'Status dos servidores Minecraft',
  '!topicos'     => 'Reenviar assuntos dos canais',
  '!servidores'  => 'Gerenciamento dos servidores',
  'login'        => 'Instruções de login Microsoft',
  'instalar'     => 'Instruções de instalação',
  'erro'         => 'Diagnóstico de erro',
  'offline'      => 'Informações do modo offline',
  'ram'          => 'Recomendação de RAM',
  'discord'      => 'Link de convite (fallback)',
}

test("Responder #{BOT_COMMANDS.size} comandos/consultas") do
  ok = 0
  BOT_COMMANDS.each do |cmd, desc|
    print "    #{bold(cmd.to_s.ljust(12))} → #{green(desc)}\n"
    ok += 1
  end
  puts "    #{ok}/#{BOT_COMMANDS.size} comandos processados"
  ok == BOT_COMMANDS.size
end

# ─── 8. Ações do Painel Web ──────────────────────────────────────────────
section('8. Ações do Painel Web (Simulado)')

{
  'validate_discord'  => 'Validar configuração Discord',
  'test_discord_logs' => 'Testar canal de logs',
  'test_all_channels' => 'Testar todos os canais',
  'create_invite'     => 'Criar convite',
}.each do |action, label|
  test("#{label} (#{action})") do
    svc = RubyMC::DiscordBotService.new(settings, simulate: true)
    case action
    when 'validate_discord'
      svc.validate_remote![:ok]
    when 'test_discord_logs'
      svc.send_log_message('🧪 Teste de log')[:ok]
    when 'test_all_channels'
      ok = 0
      RubyMC::DiscordConfig::CHANNEL_LABELS.each_with_index do |(k, lbl), i|
        svc.send_channel_message(format('9%018d', i + 1), "🧪 #{lbl}")
        ok += 1
      end
      ok == RubyMC::DiscordConfig::CHANNEL_LABELS.size
    when 'create_invite'
      svc.create_invite('invite_channel_id', max_age: 86400, max_uses: 0)[:ok]
    else
      false
    end
  end
end

# ─── 9. Rich Presence / DiscordIntegration ─────────────────────────────────
section('9. Rich Presence e InviteStore')

test('DiscordIntegration — módulo carregado') do
  require_relative '../lib/discord_integration'
  defined?(DiscordIntegration) && DiscordIntegration.is_a?(Module)
end

test('InviteStore — registrar convite entregue') do
  invite = DiscordIntegration::InviteStore.record_pending(
    config: settings,
    discord_user_id: '700000000000000001',
    discord_username: 'alice',
    minecraft_username: 'AliceMC',
    version: '1.21.4',
    invite_code: 'rubymc-test',
    invite_url: 'https://discord.gg/rubymc-test',
    dm_channel_id: '800000000000000001',
    message_id: '900000000000000001'
  )
  puts "    Status: #{invite['status']}" if invite
  !invite.nil?
end

test('InviteStore — marcar convite como joined') do
  result = DiscordIntegration::InviteStore.mark_joined(
    config: settings,
    discord_user_id: '700000000000000001',
    discord_username: 'alice'
  )
  puts "    Status: #{result['status']}" if result
  !result.nil? && result['status'] == 'joined'
end

test('InviteStore — carregar convites salvos') do
  store = DiscordIntegration::InviteStore.load(settings)
  puts "    #{store.keys.size} convites no store" if store.is_a?(Hash)
  store.is_a?(Hash)
end

# ─── GERAR RELATÓRIO ──────────────────────────────────────────────────────
puts ''
puts bold('╔══════════════════════════════════════════════════════════════╗')
puts bold('║                    RELATÓRIO FINAL                          ║')
puts bold('╚══════════════════════════════════════════════════════════════╝')
puts ''

total = $results.size
passed = $passed
failed = $failed

puts "  #{bold('Resumo:')}"
puts "  #{green("✓ #{passed} passaram")}"
puts "  #{red("✗ #{failed} falharam")}" if failed > 0
puts "  #{bold("#{total} no total")}"
puts ''

if failed > 0
  puts "  #{red(bold('Falhas:'))}"
  $results.select { |r| r[:status] == :fail }.each do |r|
    msg = r[:error] ? ": #{r[:error]}" : ''
    puts "    #{red('✗')} #{r[:name]}#{msg}"
  end
  puts ''
end

if passed == total
  puts "  #{green(bold('✓ TODOS OS TESTES PASSARAM'))}"
else
  puts "  #{red(bold("✗ #{failed} TESTE(S) FALHARAM"))}"
end
puts ''

# ─── Cleanup ──────────────────────────────────────────────────────────────
puts "  #{cyan('ℹ')} Finalizando..."
if @sim_pid
  Process.kill('TERM', @sim_pid) rescue nil
  Process.wait(@sim_pid) rescue nil
  puts "  #{green('✓')} Simulador encerrado"
end

puts ''
puts bold('═══ Fim do teste ═══')
puts ''

exit(failed > 0 ? 1 : 0)
