# frozen_string_literal: true

require 'json'
require 'shellwords'
require 'webrick'
require 'open3'
require 'fileutils'
require 'rbconfig'
require 'socket'
require 'timeout'
require 'yaml'
require 'open-uri'
require 'zip'
require 'digest'
require 'cgi'

begin
  require_relative 'rubymc/bedrock_server_downloader'
rescue LoadError => e
  $stderr.puts "[AVISO] Não foi possível carregar bedrock_server_downloader: #{e.message}"
end

begin
  require_relative 'rubymc/server_manager'
rescue LoadError => e
  $stderr.puts "[AVISO] Não foi possível carregar server_manager: #{e.message}"
end

begin
  require 'securerandom'
rescue LoadError
  # noop
end

begin
  require_relative 'rubymc/rubymc_settings'
rescue LoadError => e
  $stderr.puts "[AVISO] Não foi possível carregar rubymc_settings: #{e.message}"
end

begin
  require_relative 'rubymc/server_version_manager'
rescue LoadError => e
  $stderr.puts "[AVISO] Não foi possível carregar server_version_manager: #{e.message}"
end

begin
  require_relative 'rubymc/microsoft_auth'
rescue LoadError => e
  $stderr.puts "[AVISO] Não foi possível carregar microsoft_auth: #{e.message}"
end

begin
  require_relative 'account_bank'
rescue LoadError => e
  $stderr.puts "[AVISO] Não foi possível carregar account_bank: #{e.message}"
end

begin
  require_relative 'rubymc/minecraft_manager'
rescue LoadError => e
  $stderr.puts "[AVISO] Não foi possível carregar minecraft_manager: #{e.message}"
end

begin
  require_relative 'rubymc/minecraft_server_status'
rescue LoadError
end

begin
  require_relative 'rubymc/bedrock_server_status'
rescue LoadError
end

begin
  require_relative 'rubymc/server_manager'
rescue LoadError
  # Gerenciamento de processo do servidor fica indisponível.
end
require 'securerandom'

begin
  require_relative 'rubymc/rubymc_settings'
  require_relative 'rubymc/discord_config'
  require_relative 'rubymc/discord_bot_service'
rescue LoadError
  # O launcher web continua funcionando mesmo sem os módulos avançados do Discord.
end

begin
  require_relative 'rubymc/modpack_manager'
rescue LoadError
  # O launcher continua funcionando mesmo sem o gerenciador avançado de modpacks.
end

begin
  require_relative 'rubymc/ai_support_service'
rescue LoadError => e
  warn "RubyMC AI support não carregado: #{e.message}"
end

begin
  require_relative 'rubymc/rubymc_discord_panel_actions'
rescue LoadError => e
  warn "RubyMC Discord panel actions não carregado: #{e.message}"
end

begin
  require_relative 'rubymc/server_version_manager'
rescue LoadError => e
  warn "RubyMC Server Version Manager não carregado: #{e.message}"
end

begin
  require_relative 'rubymc/microsoft_auth'
  require_relative 'account_bank'
  require_relative 'rubymc/minecraft_manager'
rescue LoadError => e
  warn "RubyMC módulos de autenticação/launch não carregados: #{e.message}"
end

module RubyMC
  class WebLauncherApp
    MIME_TYPES = {
      '.html' => 'text/html; charset=utf-8',
      '.css' => 'text/css; charset=utf-8',
      '.js' => 'application/javascript; charset=utf-8',
      '.json' => 'application/json; charset=utf-8',
      '.png' => 'image/png',
      '.jpg' => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.svg' => 'image/svg+xml',
      '.ico' => 'image/x-icon'
    }.freeze

    attr_reader :root, :host, :port, :log_file

    # Alias para compatibilidade com rubymc_backend_actions.rb e helpers inline
    # que chamam project_root — ambos apontam para o mesmo diretório raiz.
    alias project_root root

    def initialize(root:, host: '127.0.0.1', port: 4567, simulate: false)
      @root = File.expand_path(root)
      @host = host
      @port = Integer(port)
      @simulate = simulate
      @log_file = File.join(@root, 'tmp', 'rubymc-display.log')
      FileUtils.mkdir_p(File.dirname(@log_file))
      FileUtils.touch(@log_file)
      @last_server_online = nil
      @server_action_mutex = Mutex.new
      @server_action_busy = {}
      @pending_auths = {}
    end

    def simulate?
      @simulate
    end

    def start
      log('SYSTEM', 'RubyMC Web Launcher inicializando...')
      log('SYSTEM', "Projeto: #{root}")
      log('SYSTEM', "Servidor local: http://#{host}:#{port}")

      server = WEBrick::HTTPServer.new(
        BindAddress: host,
        Port: port,
        DocumentRoot: File.join(root, 'web'),
        AccessLog: [],
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
      )

      trap('INT') { server.shutdown }
      trap('TERM') { server.shutdown }

      server.mount_proc('/') { |req, res| route(req, res) }

      puts "[RubyMC] Launcher Web rodando em http://#{host}:#{port}"
      puts '[RubyMC] Pressione Ctrl+C para parar.'
      server.start
    end

    private

    def route(req, res)
      case req.path
      when '/'
        serve_file(res, File.join(root, 'web', 'index.html'))
      when %r{\A/assets/}
        serve_asset(req, res)
      when '/api/ping'
        json(res, { ok: true, message: 'pong', time: Time.now.strftime('%H:%M:%S') })
      when '/api/status'
        json(res, status_payload)
      when '/api/logs'
        json(res, { ok: true, logs: read_logs })
      when '/api/server/status', '/api/server/live'
        handle_bedrock_server_status(req, res)
      when '/api/action'
        handle_action(req, res)
      when '/api/accounts'
        handle_accounts(req, res)
      when '/api/accounts/start-auth'
        handle_start_auth(req, res)
      when '/api/accounts/poll-auth'
        handle_poll_auth(req, res)
      when '/api/accounts/remove'
        handle_account_remove(req, res)
      when '/api/bedrock/check'
        handle_bedrock_check(req, res)
      when '/api/bedrock/launch'
        handle_bedrock_launch(req, res)
      when '/api/bedrock/servers/available'
        handle_bedrock_server_available(req, res)
      when '/api/bedrock/servers/status'
        handle_bedrock_server_status(req, res)
      when '/api/bedrock/servers/download'
        handle_bedrock_server_download(req, res)
      when '/api/bedrock/servers/installed'
        handle_bedrock_server_installed(req, res)
      when '/api/bedrock/servers/start'
        handle_bedrock_server_start(req, res)
      when '/api/bedrock/servers/stop'
        handle_bedrock_server_stop(req, res)
      when '/api/bedrock/servers/restart'
        handle_bedrock_server_restart(req, res)
      when '/api/bedrock/servers/remove'
        handle_bedrock_server_remove(req, res)
      when '/api/bedrock/servers/logs'
        handle_bedrock_server_logs(req, res)
      when '/api/bedrock/bds/available'
        handle_bedrock_server_available(req, res)
      when '/api/bedrock/bds/status'
        handle_bedrock_server_status(req, res)
      when '/api/bedrock/bds/download'
        handle_bedrock_server_download(req, res)
      when '/api/bedrock/bds/installed'
        handle_bedrock_server_installed(req, res)
      when '/api/bedrock/bds/start'
        handle_bedrock_server_start(req, res)
      when '/api/bedrock/bds/stop'
        handle_bedrock_server_stop(req, res)
      when '/api/bedrock/bds/restart'
        handle_bedrock_server_restart(req, res)
      when '/api/bedrock/bds/remove'
        handle_bedrock_server_remove(req, res)
      when '/api/bedrock/bds/logs'
        handle_bedrock_server_logs(req, res)
      when '/api/bedrock/open-manager'
        handle_bedrock_open_manager(req, res)
      when '/api/bedrock/import-apk'
        handle_bedrock_import_apk(req, res)
      when '/api/server/bedrock/status'
        handle_bedrock_server_status(req, res)
      when '/api/server/bedrock/test'
        handle_bedrock_server_status(req, res)
      else
        res.status = 404
        json(res, { ok: false, error: 'Rota não encontrada', path: req.path })
      end
    rescue StandardError => e
      log('ERROR', "#{e.class}: #{e.message}")
      res.status = 500
      json(res, { ok: false, error: e.message, type: e.class.name })
    end

    def serve_asset(req, res)
      relative = req.path.sub(%r{\A/assets/}, '')
      clean = relative.split('/').reject { |part| part == '..' || part.empty? }.join('/')
      file = File.join(root, 'web', 'assets', clean)

      if File.file?(file)
        serve_file(res, file)
      else
        res.status = 404
        json(res, { ok: false, error: "Asset não encontrado: #{relative}" })
      end
    end

    def serve_file(res, file)
      unless File.file?(file)
        res.status = 404
        res['Content-Type'] = 'text/plain; charset=utf-8'
        res.body = "Arquivo não encontrado: #{file}"
        return
      end

      ext = File.extname(file).downcase
      res['Content-Type'] = MIME_TYPES.fetch(ext, 'application/octet-stream')
      res['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
      res.body = File.binread(file)
    end

    def handle_action(req, res)
      data = parse_json(req.body)
      action = (data['action'] || req.query['action'] || req.query['name']).to_s

      log('ACTION', "Botão recebido pelo backend: #{action}") unless action == 'clear_logs'

      case action

        # ── Log interno ───────────────────────────────────────────────────────
      when 'clear_logs'
        File.write(log_file, '')
        log('SYSTEM', 'Display limpo. Aguardando novos eventos...')
        json(res, { ok: true, message: 'Display limpo.' })

        # ── Status e modpacks ─────────────────────────────────────────────────
      when 'refresh_status'
        log('ACTION', 'Status atualizado pelo painel.')
        json(res, { ok: true, message: 'Status atualizado.', status: status_payload })

        # ── Testes e organização ──────────────────────────────────────────────
      when 'run_tests'
        run_async('Rodar testes') { run_project_checks }
        json(res, { ok: true, message: 'Testes iniciados. Veja o Display.' })

      when 'organize_project', 'organize'
        run_async('Organizar raiz') { organize_project }
        json(res, { ok: true, message: 'Organização iniciada.' })

      when 'open_project_folder', 'project_folder'
        target = project_root
        log('ACTION', "Abrindo pasta do projeto: #{target}")
        system('xdg-open', target, out: File::NULL, err: File::NULL)
        log('OK', 'Pasta do projeto aberta.')
        json(res, { ok: true, message: 'Pasta do projeto aberta.', path: target })

        # ── Launcher Bedrock (via /api/bedrock/launch) ─────────────────────────
      when 'play_bedrock', 'play_bedrock_server'
        params = parse_json(req.body) || {}
        server_address = params.dig('settings', 'server_address') || params['server_address']
        server_mode = (action == 'play_bedrock_server')

        if server_mode && server_address.to_s.strip.empty?
          # fallback: pegar do settings salvo
          server_address = settings['server_address']
        end

        bedrock_version = params['bedrock_version'].to_s.strip

        launch_params = {}
        launch_params['server_address'] = server_address if server_address && !server_address.to_s.strip.empty?
        launch_params['version'] = bedrock_version unless bedrock_version.empty?

        result = handle_bedrock_launch_inner(launch_params)
        if result[:ok]
          json(res, { ok: true, message: "Bedrock iniciado (PID #{result[:pid]})", pid: result[:pid] })
        else
          json(res, { ok: false, error: result[:error] })
        end

      when 'start_server', 'server_start'
        run_async('Iniciar servidor') do
          result = with_server_mutex('start') { RubyMC::ServerManager.start(:bedrock) }
          if result[:ok]
            log('OK', "Servidor Bedrock iniciado (PID #{result[:pid]})")
          else
            log('ERROR', "Falha ao iniciar servidor: #{result[:error]}")
          end
        end
        json(res, { ok: true, message: 'Iniciando servidor Bedrock...' })

      when 'stop_server', 'server_stop'
        run_async('Parar servidor') do
          result = with_server_mutex('stop') { RubyMC::ServerManager.stop(:bedrock) }
          if result[:ok]
            log('OK', 'Servidor Bedrock parado.')
          else
            log('ERROR', "Falha ao parar servidor: #{result[:error]}")
          end
        end
        json(res, { ok: true, message: 'Parando servidor Bedrock...' })

      when 'restart_server', 'server_restart'
        run_async('Reiniciar servidor') do
          result = with_server_mutex('restart') { RubyMC::ServerManager.restart(:bedrock) }
          if result[:ok]
            log('OK', 'Servidor Bedrock reiniciado.')
          else
            log('ERROR', "Falha ao reiniciar servidor: #{result[:error]}")
          end
        end
        json(res, { ok: true, message: 'Reiniciando servidor Bedrock...' })

        # ── Gerenciamento de Versões do Servidor ────────────────────────────
      when 'version_list_installed'
        json(res, { ok: true, installed: version_manager.list_installed })

      when 'version_list_available'
        params = parse_json(req.body) || {}
        loader = (params['loader'] || req.query['loader'] || 'vanilla').to_sym
        limit = (params['limit'] || req.query['limit'] || 50).to_i
        result = version_manager.list_available(loader: loader, limit: limit)
        json(res, { ok: true, loader: loader, versions: result })

      when 'version_install'
        params = parse_json(req.body) || {}
        vid = params['version_id'] || req.query['version_id']
        loader = (params['loader'] || req.query['loader'] || 'vanilla').to_sym
        java_bin = params['java_bin'] || req.query['java_bin']

        unless vid
          return json(res, { ok: false, error: 'Informe version_id.' })
        end

        run_async("Instalar #{loader} #{vid}") do
          result = version_manager.install(vid, loader: loader, java_bin: java_bin)
          if result[:ok]
            log('OK', "Versão '#{vid}' (#{loader}) instalada.")
          else
            log('ERROR', "Falha ao instalar '#{vid}': #{result[:error]}")
          end
        end
        json(res, { ok: true, message: "Instalação de '#{vid}' (#{loader}) iniciada." })

      when 'version_remove'
        params = parse_json(req.body) || {}
        vid = params['version_id'] || req.query['version_id']
        return json(res, { ok: false, error: 'Informe version_id.' }) unless vid

        result = version_manager.remove(vid)
        if result[:ok]
          log('OK', "Versão '#{vid}' removida.")
        else
          log('ERROR', "Falha ao remover '#{vid}': #{result[:error]}")
        end
        json(res, result)

      when 'version_activate'
        params = parse_json(req.body) || {}
        vid = params['version_id'] || req.query['version_id']
        return json(res, { ok: false, error: 'Informe version_id.' }) unless vid

        result = version_manager.activate(vid)
        if result[:ok]
          log('OK', "Versão '#{vid}' ativada.")
        else
          log('ERROR', "Falha ao ativar '#{vid}': #{result[:error]}")
        end
        json(res, result)

      when 'version_active'
        mgr = version_manager
        unless mgr
          return json(res, { ok: false, error: 'Gerenciador de versões não disponível.' })
        end
        json(res, { ok: true, active: mgr.active_version })

      when 'profile_select', 'activate_profile'
        mgr = version_manager
        unless mgr
          return json(res, { ok: false, error: 'Gerenciador de versões não disponível.' })
        end
        params = parse_json(req.body) || {}
        vid = params['version_id'] || req.query['version_id']
        unless vid
          return json(res, { ok: false, error: 'Informe version_id.' })
        end
        result = mgr.activate(vid)
        if result[:ok]
          log('OK', "Perfil alterado para versão '#{vid}'.")
        else
          log('ERROR', "Falha ao ativar perfil '#{vid}': #{result[:error]}")
        end
        json(res, result.merge(active: mgr.active_version))

      when 'profile_current'
        mgr = version_manager
        unless mgr
          return json(res, { ok: false, error: 'Gerenciador de versões não disponível.' })
        end
        json(res, { ok: true, active: mgr.active_version })

        # ── Ação desconhecida ─────────────────────────────────────────────────
      else
        discord_panel_result = rubymc_handle_discord_panel_action(action) if respond_to?(:rubymc_handle_discord_panel_action)
        return json(res, discord_panel_result) if discord_panel_result

        log('WARN', "Ação desconhecida recebida: #{action.inspect}")
        json(res, { ok: false, error: "Ação desconhecida: #{action}" })
      end
    end

    def parse_json(body)
      return {} if body.to_s.strip.empty?
      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def json(res, payload)
      res['Content-Type'] = 'application/json; charset=utf-8'
      res['Cache-Control'] = 'no-store'
      res.body = JSON.pretty_generate(payload)
    end

    def status_payload
      {
        ok: true,
        display_connected: true,
        ruby_version: RUBY_VERSION,
        server: server_info,
        project_root: root,
        time: Time.now.strftime('%H:%M:%S')
      }
    end

    def version_manager
      return nil
    end

    def java_version
      ''
    end

    def modpacks_count
      list_modpack_payloads.size
    end

    def list_modpack_payloads
      []
    end

    def modpack_manager
      nil
    end

    def discord_config
      nil
    end

    def discord_members_payload
      []
    end

    def discord_status_payload
      { connected: false }
    end

    def live_server_status_payload
      { ok: false, error: 'Bedrock project - use /api/bedrock/servers/status' }
    end


    def server_info
      settings = load_settings
      # Prioridade: discord.server_address é onde o settings.yml padrão armazena o endereço.
      address = settings.dig('discord', 'server_address') ||
                settings.dig('community_server', 'address') ||
                settings.dig('minecraft', 'server_address') ||
                'não configurado'

      { address: address, status: address == 'não configurado' ? 'pendente' : 'configurado' }
    end

    def load_settings
      if defined?(RubyMC::Settings)
        return RubyMC::Settings.new(root).data
      end

      file = File.join(root, 'config', 'settings.yml')
      return {} unless File.file?(file)

      YAML.safe_load(File.read(file), permitted_classes: [Symbol], aliases: true) || {}
    rescue StandardError => e
      log('WARN', "Não foi possível ler config/settings.yml: #{e.message}")
      {}
    end

    def read_logs
      return [] unless File.file?(log_file)

      File.readlines(log_file, chomp: true).last(250)
    end

    def log(type, message)
      FileUtils.mkdir_p(File.dirname(log_file))
      File.open(log_file, 'a') do |file|
        file.puts("[#{Time.now.strftime('%H:%M:%S')}] #{type.to_s.upcase.ljust(7)} #{message}")
      end
    end

    def with_server_mutex(action)
      key = action.to_s
      @server_action_mutex.synchronize do
        if @server_action_busy[key]
          return { ok: false, error: "Ação '#{action}' já está em execução." }
        end
        @server_action_busy[key] = true
      end
      yield
    rescue => e
      { ok: false, error: e.message }
    ensure
      @server_action_mutex.synchronize { @server_action_busy.delete(key) }
    end

    def run_async(label)
      log('ACTION', "#{label} iniciado...")
      Thread.new do
        begin
          yield
          log('OK', "#{label} concluído.")
        rescue StandardError => e
          log('ERROR', "#{label} falhou: #{e.class}: #{e.message}")
        end
      end
    end

    def handle_accounts(req, res)
      bank = AccountBank.new
      accounts = bank.all.map do |a|
        {
          email: a[:email], username: a[:username], uuid: a[:uuid],
          edition: a[:edition] || 'java',
          last_used: a[:last_used], is_valid: a[:mc_access_token] && a[:mc_expires_at] && a[:mc_expires_at] > Time.now.to_i
        }
      end
      json(res, { ok: true, accounts: accounts })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def handle_start_auth(req, res)
      device = MicrosoftAuth.request_device_code
      dc = device[:device_code]
      @pending_auths[dc] = {
        device_code: dc, interval: device[:interval],
        expires_at: Time.now + device[:expires_in]
      }
      json(res, {
        ok: true,
        user_code: device[:user_code],
        verification_uri: device[:verification_uri],
        device_code: dc,
        interval: device[:interval]
      })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def handle_poll_auth(req, res)
      params = parse_json(req.body) || {}
      dc = params['device_code'].to_s
      edition = params['edition'].to_s
      edition = 'java' unless %w[java bedrock].include?(edition)
      pending = @pending_auths[dc]
      return json(res, { ok: false, error: 'Código expirado ou inválido.' }) unless pending

      result = MicrosoftAuth.check_token(device_code: dc)

      case result[:status]
      when :success
        ms = { access_token: result[:access_token], refresh_token: result[:refresh_token], expires_in: result[:expires_in] }
        profile = edition == 'bedrock' ? MicrosoftAuth.full_bedrock_flow(ms[:access_token]) : MicrosoftAuth.full_auth_flow(ms[:access_token])

        bank = AccountBank.new
        email = "#{profile[:username]}@microsoft"
        bank.save_account(
          email: email, username: profile[:username], uuid: profile[:uuid],
          ms_access_token: ms[:access_token], ms_refresh_token: ms[:refresh_token],
          ms_expires_in: ms[:expires_in],
          mc_access_token: profile[:mc_access_token], mc_expires_in: profile[:mc_expires_in],
          edition: edition
        )
        @pending_auths.delete(dc)
        log('OK', "Conta #{edition.upcase} adicionada: #{profile[:username]}")
        json(res, { ok: true, complete: true, edition: edition, account: { email: email, username: profile[:username], uuid: profile[:uuid] } })
      when :pending
        json(res, { ok: true, complete: false })
      when :declined
        @pending_auths.delete(dc)
        json(res, { ok: false, error: 'Login recusado pelo usuário.' })
      when :expired
        @pending_auths.delete(dc)
        json(res, { ok: false, error: 'Código expirado. Reinicie o processo.' })
      else
        @pending_auths.delete(dc)
        json(res, { ok: false, error: result[:message] || 'Falha na autenticação.' })
      end
    end

    def handle_account_remove(req, res)
      params = parse_json(req.body) || {}
      email = params['email'] || req.query['email']
      return json(res, { ok: false, error: 'Informe o email da conta.' }) unless email

      bank = AccountBank.new
      bank.remove(email)
      log('OK', "Conta removida: #{email}")
      json(res, { ok: true })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    # ── Bedrock (mcpelauncher) ──────────────────────────────────────────────
    def handle_bedrock_check(req, res)
      mcp_path = detect_mcpelauncher
      versions = list_bedrock_versions

      json(res, {
        ok: true,
        installed: !mcp_path.nil?,
        path: mcp_path,
        versions: versions
      })
    end

    def handle_bedrock_launch(req, res)
      params = parse_json(req.body) || {}
      launch_params = {}
      server_address = params['server_address'].to_s.strip
      launch_params['server_address'] = server_address unless server_address.empty?
      bedrock_version = params['bedrock_version'].to_s.strip
      launch_params['version'] = bedrock_version unless bedrock_version.empty?
      result = handle_bedrock_launch_inner(launch_params)
      if result[:ok]
        json(res, { ok: true, pid: result[:pid] })
      else
        json(res, { ok: false, error: result[:error] })
      end
    end

    def handle_bedrock_launch_inner(params)
      mcp_path = detect_mcpelauncher
      return { ok: false, error: 'mcpelauncher não encontrado.' } unless mcp_path

      cmd = mcp_path.dup

      # Add version directory if provided
      version = params['version'].to_s.strip
      unless version.empty?
        version_dir = resolve_bedrock_version_dir(version)
        if version_dir
          cmd << '-dg' << version_dir
        else
          log('WARN', "Diretório da versão Bedrock #{version} não encontrado")
        end
      end

      # Add server address if provided
      server_address = params['server_address'].to_s.strip
      unless server_address.empty?
        host, port = server_address.split(':')
        port ||= '19132'
        cmd << '--server' << host << '--port' << port
      end

      pid = spawn(*cmd, pgroup: true)
      Process.detach(pid)
      log('OK', "Bedrock (mcpelauncher) iniciado (PID #{pid})")
      { ok: true, pid: pid }
    rescue => e
      { ok: false, error: e.message }
    end

    def resolve_bedrock_version_dir(version)
      base = File.expand_path('~/.local/share/mcpelauncher')
      candidates = [
        File.join(base, 'versions', version),
        File.join(base, 'apps', version),
        File.join(base, 'arms', version)
      ]
      candidates.find { |d| Dir.exist?(d) }
    end

    def detect_mcpelauncher
      # 1. PATH
      path = `which mcpelauncher-ui-qt 2>/dev/null`.strip
      return path unless path.empty?
      # 2. Flatpak
      flatpak_check = `flatpak info io.mrarm.mcpelauncher 2>/dev/null`
      return 'flatpak run io.mrarm.mcpelauncher' unless flatpak_check.empty?
      nil
    end

    def list_bedrock_versions
      dirs = []
      base = File.expand_path('~/.local/share/mcpelauncher')
      %w[versions arms apps].each do |sub|
        dir = File.join(base, sub)
        next unless Dir.exist?(dir)
        dirs += Dir.children(dir).select { |f| File.directory?(File.join(dir, f)) }
      end
      dirs.uniq.sort.reverse
    end

    # ── Bedrock Server (BDS) Management ──────────────────────────────────────
    #
    # Estes endpoints rodam dentro do WebLauncherApp/WEBrick, sem Sinatra.
    # Eles atendem tanto a UI antiga (/api/bedrock/servers/*) quanto a UI nova
    # (/api/bedrock/bds/*).
    #
    # Observação:
    # - Cliente Bedrock: use mcpelauncher-ui-qt ou importação de APK.
    # - Servidor Bedrock: este bloco baixa, inicia, para, reinicia e remove BDS Linux.

    def bds_downloader
      @bds_downloader ||= RubyMC::BedrockServerDownloader.new(
        project_root: root,
        servers_dir: File.expand_path('~/.minecraft_ruby_launcher/bedrock_servers')
      )
    end

    def bedrock_server_port(params = {})
      direct = params['port'] || params[:port]
      return direct.to_i if direct && direct.to_i.positive?

      cfg = load_settings.dig('servers', 'bedrock') || {}
      port = cfg['port'] || cfg[:port]

      port.to_i.positive? ? port.to_i : 19_132
    rescue StandardError
      19_132
    end

    def bedrock_server_host
      info = server_info
      address = info[:address].to_s.strip

      return '127.0.0.1' if address.empty? || address == 'não configurado'

      host = address.split(':', 2).first.to_s.strip
      host.empty? ? '127.0.0.1' : host
    end

    def handle_bedrock_server_available(_req, res)
      result = bds_downloader.available
      json(res, result)
    end

    def handle_bedrock_server_download(req, res)
      params = parse_json(req.body) || {}

      version = (
        params['version'] ||
        params['bedrock_version'] ||
        params['server_version'] ||
        req.query['version']
      ).to_s.strip

      url = (
        params['url'] ||
        params['download_url'] ||
        req.query['url']
      ).to_s.strip

      force = params['force'] == true || params['force'].to_s == 'true'

      result = bds_downloader.download(
        version: version.empty? ? nil : version,
        url: url.empty? ? nil : url,
        force: force
      )

      res.status = 422 unless result[:ok]
      json(res, result)
    rescue StandardError => e
      res.status = 422
      json(res, { ok: false, error: "#{e.class}: #{e.message}", version: version })
    end

    def handle_bedrock_server_installed(_req, res)
      result = bds_downloader.installed
      json(res, result)
    end

    def handle_bedrock_server_start(req, res)
      params = parse_json(req.body) || {}

      version = (
        params['version'] ||
        params['bedrock_version'] ||
        params['server_version'] ||
        req.query['version']
      ).to_s.strip

      if version.empty?
        res.status = 422
        return json(res, { ok: false, error: 'Versão não informada.' })
      end

      port = bedrock_server_port(params)
      result = bds_downloader.start(version: version, port: port)

      if result[:ok]
        log('OK', "Servidor Bedrock #{version} iniciado.")
      else
        log('ERROR', "Falha ao iniciar Bedrock #{version}: #{result[:error]}")
        res.status = 422
      end

      json(res, result)
    rescue StandardError => e
      res.status = 422
      json(res, { ok: false, error: "#{e.class}: #{e.message}" })
    end

    def handle_bedrock_server_stop(req, res)
      params = parse_json(req.body) || {}

      version = (
        params['version'] ||
        params['bedrock_version'] ||
        params['server_version'] ||
        req.query['version']
      ).to_s.strip

      result = bds_downloader.stop(version: version.empty? ? nil : version)

      if result[:ok]
        log('OK', version.empty? ? 'Servidor(es) Bedrock parado(s).' : "Servidor Bedrock #{version} parado.")
      else
        log('ERROR', "Falha ao parar Bedrock: #{result[:error]}")
        res.status = 422
      end

      json(res, result)
    rescue StandardError => e
      res.status = 422
      json(res, { ok: false, error: "#{e.class}: #{e.message}" })
    end

    def handle_bedrock_server_restart(req, res)
      params = parse_json(req.body) || {}

      version = (
        params['version'] ||
        params['bedrock_version'] ||
        params['server_version'] ||
        req.query['version']
      ).to_s.strip

      if version.empty?
        res.status = 422
        return json(res, { ok: false, error: 'Versão não informada.' })
      end

      port = bedrock_server_port(params)

      bds_downloader.stop(version: version)
      result = bds_downloader.start(version: version, port: port)

      if result[:ok]
        log('OK', "Servidor Bedrock #{version} reiniciado.")
      else
        log('ERROR', "Falha ao reiniciar Bedrock #{version}: #{result[:error]}")
        res.status = 422
      end

      json(res, result)
    rescue StandardError => e
      res.status = 422
      json(res, { ok: false, error: "#{e.class}: #{e.message}" })
    end

    def handle_bedrock_server_remove(req, res)
      params = parse_json(req.body) || {}

      version = (
        params['version'] ||
        params['bedrock_version'] ||
        params['server_version'] ||
        req.query['version']
      ).to_s.strip

      if version.empty?
        res.status = 422
        return json(res, { ok: false, error: 'Versão não informada.' })
      end

      result = bds_downloader.remove(version: version)

      if result[:ok]
        log('OK', "Servidor Bedrock #{version} removido.")
      else
        log('ERROR', "Falha ao remover Bedrock #{version}: #{result[:error]}")
        res.status = 422
      end

      json(res, result)
    rescue StandardError => e
      res.status = 422
      json(res, { ok: false, error: "#{e.class}: #{e.message}" })
    end

    def handle_bedrock_server_logs(req, res)
      params = parse_json(req.body) || {}

      version = (
        params['version'] ||
        params['bedrock_version'] ||
        params['server_version'] ||
        req.query['version']
      ).to_s.strip

      lines = (params['lines'] || req.query['lines'] || 120).to_i
      result = bds_downloader.logs(version: version.empty? ? nil : version, lines: lines.positive? ? lines : 120)

      res.status = 422 unless result[:ok]
      json(res, result)
    rescue StandardError => e
      res.status = 422
      json(res, { ok: false, error: "#{e.class}: #{e.message}" })
    end

    def handle_bedrock_server_status(_req, res)
      bedrock_port = bedrock_server_port
      host = bedrock_server_host
      bedrock_addr = "#{host}:#{bedrock_port}"

      process_running = false
      pid = nil
      running_version = nil

      begin
        installed = bds_downloader.installed
        servers = installed[:servers] || installed['servers'] || []
        running = servers.find { |s| s[:running] || s['running'] }

        if running
          process_running = true
          pid = running[:pid] || running['pid']
          running_version = running[:version] || running['version']
        end
      rescue StandardError
        # Status degradado se a listagem falhar.
      end

      live = if defined?(RubyMC::BedrockServerStatus)
               RubyMC::BedrockServerStatus.query(bedrock_addr, timeout: 5)
             else
               {
                 ok: false,
                 online: false,
                 address: bedrock_addr,
                 players: { online: 0, max: 0, sample: [] },
                 error: 'RubyMC::BedrockServerStatus não carregado.'
               }
             end

      online = live[:online] == true

      json(res, {
        ok: process_running,
        online: online,
        running: process_running,
        process_running: process_running,
        port_open: online,
        address: bedrock_addr,
        host: host,
        port: bedrock_port,
        latency_ms: live[:latency_ms],
        version: live.dig(:version, :name) || live[:version] || running_version || '',
        pid: pid,
        players: live[:players] || { online: 0, max: 0, sample: [] },
        description: live[:description] || live[:motd] || '',
        message: online ? "Servidor Bedrock online (#{live[:latency_ms]} ms)" : (process_running ? 'Processo ativo, mas sem resposta UDP' : 'Servidor Bedrock offline'),
        error: live[:error],
        checked_at: Time.now.strftime('%H:%M:%S')
      })
    end

    def handle_bedrock_open_manager(req, res)
      mcp_path = detect_mcpelauncher
      unless mcp_path
        return json(res, { ok: false, error: 'mcpelauncher não encontrado. Instale via Flatpak: flatpak install io.mrarm.mcpelauncher' })
      end

      begin
        cmd = Shellwords.split(mcp_path)
        pid = spawn(*cmd, pgroup: true)
        Process.detach(pid)
        log('OK', "mcpelauncher-ui-qt aberto (PID #{pid})")
        json(res, { ok: true, message: 'Gerenciador de versões aberto.' })
      rescue => e
        json(res, { ok: false, error: "Falha ao abrir gerenciador: #{e.message}" })
      end
    end

    # ── Bedrock: Import APK ─────────────────────────────────────────────────

    def handle_bedrock_import_apk(req, res)
      extract_path = `which mcpelauncher-extract 2>/dev/null`.strip
      unless File.exist?(extract_path)
        return json(res, { ok: false, error: 'mcpelauncher-extract não encontrado no PATH. Use o Gerenciador de Versões (mcpelauncher-ui-qt) para baixar versões via Google Play.' })
      end

      upload = req.query['apk']
      unless upload
        return json(res, { ok: false, error: 'Envie um arquivo .apk no campo "apk".' })
      end

      filename = upload_filename(upload)
      body = upload_body(upload)

      unless body && body.bytesize > 1000
        return json(res, { ok: false, error: 'Arquivo APK inválido ou vazio.' })
      end

      temp_apk = File.join(Dir.tmpdir, "bedrock_apk_#{Time.now.to_i}_#{safe_basename(filename)}")
      File.binwrite(temp_apk, body)

      version = req.query['version'].to_s.strip
      if version.empty?
        version = detect_apk_version(temp_apk) || filename.sub(/\.apk$/i, '').strip
      end

      if version.empty?
        FileUtils.rm_f(temp_apk)
        return json(res, { ok: false, error: 'Não foi possível detectar a versão. Informe o parâmetro "version".' })
      end

      target_dir = File.expand_path("~/.local/share/mcpelauncher/versions/#{version}")
      if Dir.exist?(target_dir) && Dir.children(target_dir).any?
        FileUtils.rm_f(temp_apk)
        return json(res, { ok: false, error: "Versão #{version} já existe em #{target_dir}." })
      end

      FileUtils.mkdir_p(File.dirname(target_dir))

      begin
        log('BDS', "Extraindo #{filename} para versão #{version}...")
        stdout, stderr, status = Open3.capture3(extract_path, temp_apk, target_dir)
        unless status.success?
          raise "mcpelauncher-extract falhou: #{stderr.strip}"
        end
        log('OK', "APK #{filename} extraído como versão #{version}")
        json(res, { ok: true, message: "Versão #{version} instalada com sucesso!" })
      rescue => e
        FileUtils.rm_rf(target_dir) if Dir.exist?(target_dir)
        json(res, { ok: false, error: "Falha ao extrair APK: #{e.message}" })
      ensure
        FileUtils.rm_f(temp_apk)
      end
    end

    def detect_apk_version(apk_path)
      aapt = `which aapt 2>/dev/null`.strip
      if File.exist?(aapt)
        output = `#{aapt} dump badging #{apk_path} 2>/dev/null`
        match = output.match(/versionName='([^']+)'/)
        return match[1] if match
      end

      begin
        manifest_xml = `unzip -p #{apk_path} AndroidManifest.xml 2>/dev/null | strings`
        match = manifest_xml.match(/versionName[[:space:]]*=[[:space:]]*"([^"]+)"/)
        return match[1] if match
      rescue
      end

      nil
    end
  end
end

if __FILE__ == $0
  port = ENV['RUBYMC_PORT']&.to_i || 4567
  host = ENV['RUBYMC_HOST'] || '127.0.0.1'
  simulate = ARGV.include?('--simulate')
  app = RubyMC::WebLauncherApp.new(
    root: File.expand_path('../..', __FILE__),
    host: host,
    port: port,
    simulate: simulate
  )
  app.start
end