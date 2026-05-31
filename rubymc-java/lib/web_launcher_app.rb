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
require 'zip'
require 'openssl'
require 'cgi'
require 'net/http'
require 'uri'
require 'set'

# Load .env file if present (must happen before any config loading)
env_file = File.join(File.dirname(__dir__), '.env')
if File.file?(env_file)
  File.read(env_file).each_line do |line|
    key, val = line.strip.split('=', 2)
    ENV[key] = val if key && val && !key.empty? && !key.start_with?('#')
  end
end

begin
  require_relative 'rubymc/minecraft_server_status'
rescue LoadError
  # Status live do servidor fica indisponível se o helper não estiver presente.
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

    DISCORD_CALLBACK_URL = 'http://127.0.0.1:4567/api/auth/discord/callback'.freeze

    attr_reader :root, :host, :port, :log_file

    # Alias para compatibilidade com rubymc_backend_actions.rb e helpers inline
    # que chamam project_root — ambos apontam para o mesmo diretório raiz.
    alias project_root root

    def initialize(root:, host: '0.0.0.0', port: 4567, simulate: false)
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
      @session_file = File.join(@root, 'tmp', 'sessions.json')
      @sessions_mutex = Mutex.new
      @sessions = {}
      load_sessions
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

    ADMIN_ONLY_PATHS = %w[
      /api/logs
      /api/modpacks/import /api/modpacks/remove
      /api/discord/status /api/discord/validate /api/discord/test-log
      /api/accounts /api/accounts/start-auth /api/accounts/poll-auth /api/accounts/remove
      /api/versions /api/versions/available
      /api/ai/context
    ].to_set.freeze

    def route(req, res)
      if ADMIN_ONLY_PATHS.include?(req.path)
        user = authenticated_user(req)
        unless user && user[:role] == :admin
          res.status = 401
          return json(res, { ok: false, error: 'Acesso restrito a administradores.' })
        end
      end

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
        json(res, live_server_status_payload)
      when '/api/ai/support'
        request_body = req.body.to_s
        payload = request_body.empty? ? {} : JSON.parse(request_body)
        service = RubyMC::AISupportService.new(root: project_root)
        json(res, service.support_answer(payload['message'], context: payload['context']))

      when '/api/ai/health'
        service = RubyMC::AISupportService.new(root: project_root)
        json(res, service.health)

      when '/api/ai/context'
        json(res, {
          ok: true,
          discord: discord_status_payload,
          modpacks: list_modpack_payloads.map { |mp| { name: mp[:name], id: mp[:id], version: mp[:minecraft_version] } },
          server: server_info,
          logs: read_logs.last(20)
        })

      when '/api/action'
        handle_action(req, res)
      when '/api/modpacks'
        json(res, { ok: true, modpacks: list_modpack_payloads })
      when '/api/modpacks/import'
        handle_modpack_import(req, res)
      when '/api/modpacks/remove'
        handle_modpack_remove(req, res)
      when '/api/discord/status'
        json(res, { ok: true, discord: discord_status_payload })
      when '/api/discord/members'
        json(res, { ok: true, members: discord_members_payload })
      when '/api/discord/validate'
        handle_discord_validate(req, res)
      when '/api/discord/test-log'
        handle_discord_test_log(req, res)
      when '/api/client/versions'
        json(res, client_versions_payload)
      when '/api/client/versions/available'
        tipo = (req.query['type'] || 'release').to_sym
        limit = (req.query['limit'] || 30).to_i
        client_mgr = MinecraftManager.new
        list = client_mgr.list_versions(tipo: tipo, limit: limit)
        installed = client_mgr.list_local_versions
        json(res, { ok: true, versions: list, installed: installed })
      when '/api/client/versions/install'
        params = parse_json(req.body) || {}
        version_id = (params['version_id'] || req.query['version_id']).to_s.strip
        if version_id.empty?
          return json(res, { ok: false, error: 'version_id é obrigatório.' })
        end
        with_thread_slot("install #{version_id}") do
          client_mgr = MinecraftManager.new
          client_mgr.install_version(version_id) { |msg| log('DOWNLOAD', msg) }
          log('OK', "Versão #{version_id} instalada com sucesso.")
        end
        json(res, { ok: true, message: "Instalação de #{version_id} iniciada." })
      when '/api/user/version-status'
        json(res, user_version_status_payload)
      when '/api/versions'
        json(res, versions_payload)
      when '/api/versions/available'
        params = parse_json(req.body) || {}
        loader = (params['loader'] || req.query['loader'] || 'vanilla').to_sym
        limit = (params['limit'] || req.query['limit'] || 50).to_i
        result = version_manager.list_available(loader: loader, limit: limit)
        json(res, { ok: true, loader: loader, versions: result })
      when '/api/launch'
        handle_launch(req, res)
      when '/api/accounts'
        handle_accounts(req, res)
      when '/api/accounts/start-auth'
        handle_start_auth(req, res)
      when '/api/accounts/poll-auth'
        handle_poll_auth(req, res)
      when '/api/accounts/remove'
        handle_account_remove(req, res)
      when '/api/vip/status'
        handle_vip_status(req, res)
      when '/api/vip/plans'
        handle_vip_plans(req, res)
      when '/api/vip/history'
        handle_vip_history(req, res)
      when '/api/vip/checkout'
        handle_vip_checkout(req, res)
      when '/api/auth/status'
        handle_auth_status(req, res)
      when '/api/auth/discord/login'
        handle_discord_login(req, res)
      when '/api/auth/discord/callback'
        handle_discord_callback(req, res)
      when '/api/auth/logout'
        handle_auth_logout(req, res)
      when '/api/auth/verify/status'
        handle_verify_status(req, res)
      when '/api/auth/verify/accept-terms'
        handle_verify_accept_terms(req, res)
      when '/api/auth/verify/check-guild-membership'
        handle_verify_check_guild(req, res)
      when '/api/auth/verify/send-discord-code'
        handle_verify_send_discord_code(req, res)
      when '/api/auth/verify/confirm-discord-code'
        handle_verify_confirm_discord_code(req, res)
      when '/api/auth/verify/complete'
        handle_verify_complete(req, res)
      when '/termos'
        serve_file(res, File.join(root, 'web', 'termos.html'))
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

    ROLE_HIERARCHY = { member: 0, player: 1, staff: 2, admin: 3 }.freeze

    def require_role(req, res, min_role)
      user = authenticated_user(req)
      role = user&.dig(:role)&.to_sym
      role_weight = ROLE_HIERARCHY[role] || -1
      min_weight = ROLE_HIERARCHY[min_role.to_sym] || 99
      return true if role_weight >= min_weight

      msg = if role == :member && min_role == :player
              'Sua conta precisa ser Membro Ruby para usar esta função. Complete a verificação no painel.'
            else
              "Acesso restrito. Função necessária: #{min_role}."
            end
      res.status = 401
      json(res, { ok: false, error: msg })
      false
    end

    def handle_action(req, res)
      data = parse_json(req.body)
      action = (data['action'] || req.query['action'] || req.query['name']).to_s

      log('ACTION', "Botão recebido pelo backend: #{action}") unless action == 'clear_logs'

      # ── Role-based permission ───────────────────────────────────────────
      player_actions = %w[
        play start_minecraft launch_minecraft enter_server
        profile_select activate_profile profile_current
      ].to_set.freeze

      admin_actions = %w[
        start_server server_start stop_server server_stop restart_server server_restart
        version_install version_remove version_activate
        organize_project organize run_tests
        open_project_folder project_folder
        validate_discord_config test_discord_log
        import_modpack remove_modpack
      ].to_set.freeze

      unless action == 'clear_logs'
        if admin_actions.include?(action)
          return unless require_role(req, res, :admin)
        elsif player_actions.include?(action)
          return unless require_role(req, res, :player)
        end
      end

      case action

        # ── Painel UI: ações inline (rubymc_handle_ui_action) ────────────────
      when 'join_server', 'server_join'
        user = authenticated_user(req)
        json(res, rubymc_handle_ui_action(action, discord_user_id: user&.dig(:user_id)))

      when 'clear_display', 'display_clear',
        'validate_discord', 'discord_validate', 'validate_discord_settings',
        'test_discord_logs', 'discord_test_logs', 'test_logs_channel',
        'test_all_channels', 'discord_test_channels', 'test_channels',
        'create_invite', 'discord_create_invite', 'generate_invite',
        'open_docs', 'open_documentation',
        'check_updates', 'update_check'
        json(res, rubymc_handle_ui_action(action))

        # ── Log interno ───────────────────────────────────────────────────────
      when 'clear_logs'
        File.write(log_file, '')
        log('SYSTEM', 'Display limpo. Aguardando novos eventos...')
        json(res, { ok: true, message: 'Display limpo.' })

        # ── Status e modpacks ─────────────────────────────────────────────────
      when 'refresh_status'
        log('ACTION', 'Status atualizado pelo painel.')
        json(res, { ok: true, message: 'Status atualizado.', status: status_payload })

      when 'refresh_modpacks', 'update_modpacks', 'list_modpacks'
        log('ACTION', 'Lista de modpacks atualizada pelo painel.')
        json(res, { ok: true, message: 'Modpacks atualizados.', modpacks: list_modpack_payloads })

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

        # ── Launcher Minecraft (via /api/launch) ─────────────────────────────
      when 'launch_classic', 'play', 'start_minecraft', 'launch_minecraft', 'enter_server'
        params = parse_json(req.body) || {}
        account_id = params.dig('settings', 'account') || params['account_id']
        server_mode = (action == 'enter_server')
        ram = (params.dig('settings', 'ram') || 2048).to_i

        if account_id && !account_id.to_s.empty?
          # Launch com conta Microsoft
          result = with_server_mutex('launch_minecraft') do
            launch_with_account(account_id: account_id, ram_mb: ram, server_mode: server_mode)
          end
        else
          # Launch offline — exige username
          username = params.dig('settings', 'username').to_s.strip
          if username.empty?
            return json(res, { ok: false, error: 'Username offline não preenchido. Vá em Configurações.' })
          end
          result = with_server_mutex('launch_minecraft') do
            launch_offline(username: username, ram_mb: ram, server_mode: server_mode)
          end
        end

        if result[:pid]
          json(res, { ok: true, message: "Minecraft iniciado (PID #{result[:pid]})", pid: result[:pid] })
        else
          json(res, { ok: false, error: result[:error] || 'Falha ao iniciar Minecraft.' })
        end

      when 'test_server', 'server_test', 'check_server'
        run_async('Testar servidor') { test_community_server }
        json(res, { ok: true, message: 'Teste do servidor iniciado. Veja o Display.' })

        # ── Gerenciamento do Servidor (start/stop/restart) ───────────────────
      when 'start_server', 'server_start'
        run_async('Iniciar servidor') do
          result = with_server_mutex('start') { RubyMC::ServerManager.start(:java) }
          if result[:ok]
            log('OK', "Servidor Java iniciado (PID #{result[:pid]})")
          else
            log('ERROR', "Falha ao iniciar servidor: #{result[:error]}")
          end
        end
        json(res, { ok: true, message: 'Iniciando servidor...' })

      when 'stop_server', 'server_stop'
        run_async('Parar servidor') do
          result = with_server_mutex('stop') { RubyMC::ServerManager.stop(:java) }
          if result[:ok]
            log('OK', 'Servidor Java parado.')
          else
            log('ERROR', "Falha ao parar servidor: #{result[:error]}")
          end
        end
        json(res, { ok: true, message: 'Parando servidor...' })

      when 'restart_server', 'server_restart'
        run_async('Reiniciar servidor') do
          result = with_server_mutex('restart') { RubyMC::ServerManager.restart(:java) }
          if result[:ok]
            log('OK', 'Servidor Java reiniciado.')
          else
            log('ERROR', "Falha ao reiniciar servidor: #{result[:error]}")
          end
        end
        json(res, { ok: true, message: 'Reiniciando servidor...' })

        # ── Discord: simulação (sempre mock, independente de --simulate) ──────
      when 'simular_discord', 'discord_simulate'
        json(res, rubymc_simular_discord)

        # ── Discord avançado (via módulos opcionais) ──────────────────────────
      when 'validate_discord', 'discord_validate', 'validate_discord_settings', 'validate_discord_config'
        report = validate_discord_config(remote: true)
        json(res, {
          ok: report[:errors].empty?,
          message: report[:errors].empty? ? 'Validação Discord concluída.' : 'Discord precisa de ajustes.',
          report: report
        })

      when 'test_discord_log'
        result = test_discord_log
        json(res, { ok: true, message: 'Teste de log enviado ao Discord.', result: result })

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

    def handle_modpack_import(req, res)
      unless req.request_method == 'POST'
        res.status = 405
        json(res, { ok: false, error: 'Use POST para importar modpacks.' })
        return
      end

      upload = req.query['modpack'] || req.query['file'] || req.query['pack']
      raise 'Nenhum arquivo foi enviado. Selecione um .mrpack ou .zip.' unless upload

      original_name = upload_filename(upload)
      raise 'Nome de arquivo inválido.' if original_name.to_s.strip.empty?

      ext = File.extname(original_name).downcase
      unless ['.mrpack', '.zip'].include?(ext)
        raise "Formato não suportado: #{ext}. Use .mrpack ou .zip."
      end

      body = upload_body(upload)
      raise 'Arquivo enviado está vazio.' if body.nil? || body.bytesize.zero?

      requested_name = req.query['name'].to_s.strip
      requested_name = nil if requested_name.empty?

      uploads_dir = File.join(root, 'tmp', 'rubymc-uploads')
      FileUtils.mkdir_p(uploads_dir)
      safe_name = "#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}-#{safe_basename(original_name)}"
      temp_path = File.join(uploads_dir, safe_name)
      File.binwrite(temp_path, body)

      log('ACTION', "Importação de modpack iniciada: #{original_name}")
      log('COMMAND', "Arquivo temporário: #{temp_path}")

      profile_payload = install_modpack_file(temp_path, name: requested_name)

      log('OK', "Modpack importado: #{profile_payload['name'] || profile_payload[:name] || original_name}")
      json(res, { ok: true, message: 'Modpack importado com sucesso.', profile: profile_payload, modpacks: list_modpack_payloads })
    rescue StandardError => e
      log('ERROR', "Falha ao importar modpack: #{e.class}: #{e.message}")
      res.status = 422
      json(res, { ok: false, error: e.message, type: e.class.name })
    end


    def handle_modpack_remove(req, res)
      unless req.request_method == 'POST'
        res.status = 405
        json(res, { ok: false, error: 'Use POST para remover modpacks.' })
        return
      end

      data = parse_json(req.body)
      profile_id = data['profile_id'].to_s.strip
      if profile_id.empty?
        res.status = 422
        json(res, { ok: false, error: 'profile_id é obrigatório.' })
        return
      end

      manager = modpack_manager
      if manager
        removed = manager.remove(profile_id)
        unless removed
          res.status = 404
          json(res, { ok: false, error: 'Modpack não encontrado.' })
          return
        end
      else
        dir = File.expand_path("~/.minecraft_ruby_launcher/modpacks/#{profile_id}")
        if Dir.exist?(dir)
          FileUtils.rm_rf(dir)
        else
          res.status = 404
          json(res, { ok: false, error: 'Modpack não encontrado.' })
          return
        end
      end

      log('OK', "Modpack removido: #{profile_id}")
      json(res, { ok: true, message: 'Modpack removido.', modpacks: list_modpack_payloads })
    rescue StandardError => e
      log('ERROR', "Falha ao remover modpack: #{e.class}: #{e.message}")
      res.status = 422
      json(res, { ok: false, error: e.message, type: e.class.name })
    end

    def handle_discord_validate(_req, res)
      log('ACTION', 'Validação Discord solicitada pelo painel.')
      report = validate_discord_config(remote: true)
      json(res, { ok: report[:errors].empty?, message: report[:errors].empty? ? 'Discord validado.' : 'Discord precisa de ajustes.', report: report })
    rescue StandardError => e
      log('ERROR', "Validação Discord falhou: #{e.class}: #{e.message}")
      res.status = 422
      json(res, { ok: false, error: e.message, type: e.class.name })
    end

    def handle_discord_test_log(_req, res)
      log('ACTION', 'Teste de canal de logs Discord solicitado pelo painel.')
      result = test_discord_log
      json(res, { ok: true, message: 'Teste de log enviado.', result: result })
    rescue StandardError => e
      log('ERROR', "Falha ao enviar teste no Discord: #{e.class}: #{e.message}")
      res.status = 422
      json(res, { ok: false, error: e.message, type: e.class.name })
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
      modpacks = list_modpack_payloads
      ver_mgr = version_manager
      {
        ok: true,
        display_connected: true,
        ruby_version: RUBY_VERSION,
        java_version: java_version,
        modpacks_count: modpacks.size,
        modpacks: modpacks,
        server: server_info,
        discord: discord_status_payload,
        versions: ver_mgr ? { active: ver_mgr.active_version, installed: ver_mgr.list_installed } : nil,
        project_root: root,
        time: Time.now.strftime('%H:%M:%S')
      }
    end

    def client_versions_payload
      client_mgr = MinecraftManager.new
      { ok: true, installed: client_mgr.list_local_versions }
    rescue => e
      { ok: false, error: e.message }
    end

    def user_version_status_payload
      mgr = version_manager
      return { ok: false, error: 'Version manager não disponível' } unless mgr
      { ok: true, active: mgr.active_version, installed: mgr.list_installed }
    end

    def versions_payload
      mgr = version_manager
      return { ok: false, error: 'Version manager não disponível' } unless mgr

      {
        ok: true,
        active: mgr.active_version,
        installed: mgr.list_installed,
        java_recommendations: RubyMC::ServerVersionManager::JAVA_VERSION_MAP.map { |r| { java_version: r[:java_version], java_path: r[:java_path], label: r[:label] } }
      }
    end

    def version_manager
      return @version_manager if @version_manager
      return nil unless defined?(RubyMC::ServerVersionManager)

      dir = '/home/victor/Servidores/ServidorMinecraftJava'
      unless Dir.exist?(dir)
        log('WARN', "Diretório do servidor não encontrado: #{dir}")
        return nil
      end

      settings = defined?(RubyMC::Settings) ? RubyMC::Settings.new(root) : nil
      @version_manager = RubyMC::ServerVersionManager.new(dir, settings)
    rescue => e
      log('ERROR', "Falha ao criar version manager: #{e.message}")
      nil
    end

    def java_version
      out, err, = Open3.capture3('java', '-version')
      first = [err, out].join("\n").lines.first.to_s.strip
      first.empty? ? 'não encontrado' : first
    rescue Errno::ENOENT
      'não encontrado'
    end

    def list_modpack_payloads
      manager = modpack_manager
      if manager
        return manager.list_profiles.map { |profile| normalize_profile(profile.respond_to?(:to_h) ? profile.to_h : profile) }
      end

      fallback_modpack_profiles
    rescue StandardError => e
      log('WARN', "Não foi possível listar modpacks: #{e.message}")
      fallback_modpack_profiles
    end

    def fallback_modpack_profiles
      roots = [File.join(root, 'modpacks'), File.expand_path('~/.minecraft_ruby_launcher/modpacks')]
      roots.flat_map do |base|
        next [] unless Dir.exist?(base)

        Dir.children(base).filter_map do |entry|
          dir = File.join(base, entry)
          profile_file = File.join(dir, 'profile.yml')
          if File.file?(profile_file)
            normalize_profile(YAML.safe_load(File.read(profile_file), aliases: true) || {})
          elsif File.directory?(dir)
            normalize_profile({ 'id' => entry, 'name' => entry, 'source' => 'local', 'game_dir' => dir })
          end
        rescue StandardError
          nil
        end
      end
    end

    def normalize_profile(profile)
      hash = profile.transform_keys(&:to_s)
      {
        id: hash['id'] || hash['name'],
        name: hash['name'] || hash['id'] || 'Modpack',
        minecraft_version: hash['minecraft_version'],
        loader: hash['loader'],
        loader_version: hash['loader_version'],
        game_dir: hash['game_dir'],
        mods_dir: hash['mods_dir'],
        source: hash['source'],
        notes: hash['notes'],
        created_at: hash['created_at']
      }
    end

    def install_modpack_file(path, name: nil)
      manager = modpack_manager
      if manager
        profile = manager.install_zip(path, name: name)
        return normalize_profile(profile.to_h)
      end

      fallback_import_modpack(path, name: name)
    end

    def modpack_manager
      return nil unless defined?(MinecraftRubyLauncher::ModpackManager)

      @modpack_manager ||= MinecraftRubyLauncher::ModpackManager.new(load_settings)
    rescue StandardError => e
      log('WARN', "Gerenciador avançado de modpacks indisponível: #{e.message}")
      nil
    end

    def fallback_import_modpack(path, name: nil)
      base = File.expand_path('~/.minecraft_ruby_launcher/modpacks')
      id = safe_profile_id(name || File.basename(path, '.*'))
      target_dir = File.join(base, id)
      FileUtils.mkdir_p(target_dir)

      target_file = File.join(target_dir, File.basename(path))
      FileUtils.cp(path, target_file)

      profile = {
        'id' => id,
        'name' => name || File.basename(path, '.*'),
        'minecraft_version' => load_settings.dig('minecraft', 'default_version') || '1.21.4',
        'loader' => 'desconhecido',
        'game_dir' => target_dir,
        'mods_dir' => File.join(target_dir, 'mods'),
        'source' => File.extname(path).delete_prefix('.'),
        'created_at' => Time.now.utc.iso8601,
        'notes' => 'Arquivo salvo em modo fallback. Instale rubyzip/modpack_manager para extração completa.'
      }

      File.write(File.join(target_dir, 'profile.yml'), profile.to_yaml)
      normalize_profile(profile)
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

    def discord_config
      if defined?(RubyMC::DiscordConfig)
        RubyMC::DiscordConfig.new(load_settings)
      else
        nil
      end
    end

    def discord_members_payload
      cfg = discord_config
      return { guild_name: '---', members_count: 0, presence_count: 0 } unless cfg
      return { guild_name: '---', members_count: 0, presence_count: 0 } unless defined?(RubyMC::DiscordBotService)

      service = RubyMC::DiscordBotService.new(load_settings, simulate: simulate?)
      result = service.validate_remote!
      {
        guild_name: result.dig(:guild, :name) || '---',
        members_count: result[:members_count] || 0,
        presence_count: result[:presence_count] || 0
      }
    rescue StandardError => e
      log('WARN', "discord_members_payload: #{e.message}")
      { guild_name: '---', members_count: 0, presence_count: 0 }
    end

    def discord_status_payload
      cfg = discord_config
      return { configured: false, status: 'indisponível' } unless cfg

      report = cfg.validation_report
      report[:summary].merge(
        configured: report[:ok],
        status: report[:ok] ? 'configurado' : 'pendente',
        warnings_count: report[:warnings].size,
        errors_count: report[:errors].size
      )
    rescue StandardError => e
      { configured: false, status: 'erro', error: e.message }
    end


    def live_server_status_payload
      info = server_info
      address = info[:address].to_s

      live = if defined?(RubyMC::MinecraftServerStatus)
               RubyMC::MinecraftServerStatus.query(address, timeout: 5)
             else
               {
                 ok: false, online: false, address: address, players: { online: 0, max: 0, sample: [] },
                 error: 'RubyMC::MinecraftServerStatus não carregado.'
               }
             end

      if live[:online]
        players = live.dig(:players, :online).to_i
        max_players = live.dig(:players, :max).to_i
        latency = live[:latency_ms] || '--'
        unless @last_server_online == true
          log('CHECK', "Servidor online: #{players}/#{max_players} jogadores | ping #{latency} ms")
        end
        @last_server_online = true
      else
        unless @last_server_online == false
          log('WARN', "Servidor offline/indisponível: #{live[:error]}")
        end
        @last_server_online = false
      end

      process_running = defined?(RubyMC::ServerManager) && RubyMC::ServerManager.running?(:java)

      {
        ok: live[:online] == true,
        server: info,
        server_live: live,
        process_running: process_running,
        process_status: process_running ? 'running' : 'stopped',
        server_status: live[:online] ? 'Online' : 'Offline',
        server_players: live[:online] ? "#{live.dig(:players, :online).to_i}/#{live.dig(:players, :max).to_i} jogadores" : '0 jogadores',
        time: Time.now.strftime('%H:%M:%S')
      }
    end




    # RubyMC Backend Actions Final Fix
    def rubymc_handle_ui_action(action, discord_user_id: nil)
      normalized = action.to_s.strip

      case normalized
      when 'clear_display', 'display_clear'
        @logs.clear if defined?(@logs) && @logs.respond_to?(:clear)
        log('OK', 'Display limpo pelo painel.') if respond_to?(:log)
        { ok: true, message: 'Display limpo.' }

      when 'validate_discord', 'discord_validate', 'validate_discord_settings'
        rubymc_validate_discord_final

      when 'test_discord_logs', 'discord_test_logs', 'test_logs_channel'
        rubymc_test_discord_logs_final

      when 'test_all_channels', 'discord_test_channels', 'test_channels'
        rubymc_test_all_channels_final

      when 'create_invite', 'discord_create_invite', 'generate_invite'
        rubymc_create_invite_final

      when 'open_docs', 'open_documentation'
        rubymc_open_docs_final

      when 'check_updates', 'update_check'
        rubymc_check_updates_final

      when 'join_server', 'server_join'
        rubymc_join_server_final(discord_user_id: discord_user_id)

      else
        nil
      end
    rescue StandardError => e
      log('ERROR', "#{e.class}: #{e.message}") if respond_to?(:log)
      { ok: false, message: e.message }
    end

    def rubymc_validate_discord_final
      log('ACTION', 'Validação Discord solicitada pelo painel.')
      cfg = discord_config
      unless cfg
        log('ERROR', 'RubyMC::DiscordConfig não carregado.')
        return { ok: false, message: 'DiscordConfig não disponível.' }
      end

      report = cfg.validation_report
      summary = report[:summary]

      log('CHECK', "Bot ativo: #{summary[:bot_enabled]} | Token: #{summary[:token_configured]} | Guild: #{summary[:guild_id_configured]}")
      log('CHECK', "Canais: #{summary[:channels_configured]}/#{summary[:channels_total]}")
      log('CHECK', "Cargos: #{summary[:roles_configured]}/#{summary[:roles_total]}")

      report[:channels].each do |key, value|
        status = value[:configured] ? 'OK' : 'pendente'
        log('CHANNEL', "#{status.ljust(7)} #{value[:label]}: #{value[:id].empty? ? '(vazio)' : value[:id]}")
      end

      report[:roles].each do |key, value|
        status = value[:configured] ? 'OK' : 'pendente'
        log('ROLE', "#{status.ljust(7)} #{value[:label]}: #{value[:id].empty? ? '(vazio)' : value[:id]}")
      end

      report[:warnings].each { |w| log('WARN', w) }
      report[:errors].each { |e| log('ERROR', e) }

      discord_payload = summary.merge(
        configured: report[:ok],
        status: report[:ok] ? 'configurado' : 'pendente',
        members_count: 0,
        presence_count: 0
      )

      if defined?(RubyMC::DiscordBotService) && cfg.bot_enabled? && cfg.token_configured?
        begin
          remote = RubyMC::DiscordBotService.new(load_settings, simulate: simulate?).validate_remote!
          discord_payload[:members_count] = remote[:members_count] || 0
          discord_payload[:presence_count] = remote[:presence_count] || 0
          log('OK', "Discord: #{remote[:members_count]} membros, #{remote[:presence_count]} online.")
        rescue StandardError => e
          log('WARN', "Não foi possível obter contagem de membros: #{e.message}")
        end
      end

      if report[:ok]
        log('OK', 'Configuração Discord validada com sucesso.')
        {
          ok: true,
          message: 'Configuração Discord validada com sucesso.',
          discord: discord_payload
        }
      else
        log('ERROR', 'Configuração Discord possui pendências.')
        {
          ok: false,
          message: 'Discord precisa de ajustes.',
          discord: discord_payload
        }
      end
    end

    def rubymc_test_discord_logs_final
      log('ACTION', 'Teste de canal de logs Discord solicitado pelo painel.') if respond_to?(:log)

      begin
        if defined?(RubyMC::DiscordBotService)
          service = RubyMC::DiscordBotService.new(load_settings, simulate: simulate?)
          result = service.send_log_message("💎 RubyMC Launcher: teste de log enviado pelo painel web às #{Time.now.strftime('%H:%M:%S')}.")
          log('OK', 'Mensagem de teste enviada ao canal de logs Discord.') if respond_to?(:log)
          return { ok: true, message: 'Mensagem de teste enviada ao canal de logs Discord.', result: result }
        end
      rescue StandardError => e
        log('ERROR', "Falha ao enviar mensagem ao canal de logs: #{e.message}") if respond_to?(:log)
        return { ok: false, message: e.message }
      end

      result = rubymc_validate_discord_final
      if result[:ok]
        log('WARN', 'Configuração Discord válida, mas serviço Discord não está disponível para envio de mensagens.') if respond_to?(:log)
      end
      result
    end

    def rubymc_test_all_channels_final
      log('ACTION', 'Teste de todos os canais Discord solicitado pelo painel.')
      cfg = discord_config
      unless cfg
        log('ERROR', 'DiscordConfig não carregado.')
        return { ok: false, message: 'DiscordConfig não disponível.' }
      end

      results = { ok: true, tested: 0, failed: 0, details: {} }

      if simulate?
        log('OK', 'Modo simulação: simulando teste de canais.')
        RubyMC::DiscordConfig::CHANNEL_LABELS.each do |key, label|
          log('CHANNEL', "✅ Simulado #{label} (#{key})")
          results[:details][key] = { label: label, ok: true }
          results[:tested] += 1
        end
        return {
          ok: true,
          message: "Teste simulado: #{results[:tested]} canais.",
          test_results: results
        }
      end

      service = RubyMC::DiscordBotService.new(load_settings, simulate: false)

      RubyMC::DiscordConfig::CHANNEL_LABELS.each do |key, label|
        ch_id = cfg.channel_id(key)
        unless cfg.valid_id?(ch_id)
          log('CHANNEL', "⚠ #{'PULANDO'.ljust(7)} #{label} (#{key}) — ID vazio ou inválido")
          next
        end
        begin
          unless service.text_channel?(ch_id)
            log('CHANNEL', "⏭️ #{'PULANDO'.ljust(7)} #{label} (#{key}) — canal não suporta mensagem de texto")
            results[:details][key] = { label: label, ok: true, skipped: 'non-text' }
            results[:tested] += 1
            next
          end
          service.send_channel_message(ch_id, "🧪 Teste automático do canal **#{label}** — RubyMC Launcher #{Time.now.strftime('%d/%m/%Y %H:%M:%S')}")
          log('CHANNEL', "✅ #{'OK'.ljust(7)} #{label} (#{key}): #{ch_id}")
          results[:details][key] = { label: label, ok: true }
          results[:tested] += 1
        rescue StandardError => e
          log('CHANNEL', "❌ #{'FALHA'.ljust(7)} #{label} (#{key}): #{e.message}")
          results[:details][key] = { label: label, ok: false, error: e.message }
          results[:failed] += 1
          results[:ok] = false
        end
        sleep(0.6)
      end

      if results[:failed].zero?
        log('OK', "Todos os #{results[:tested]} canais testados com sucesso.")
      else
        log('WARN', "#{results[:tested]} testados, #{results[:failed]} falhas.")
      end

      { ok: results[:ok], message: "Teste de canais: #{results[:tested]} ok, #{results[:failed]} falhas.", test_results: results, discord: discord_status_payload }
    rescue StandardError => e
      log('ERROR', "Falha ao testar canais: #{e.class}: #{e.message}")
      { ok: false, message: e.message }
    end

    def rubymc_create_invite_final
      log('ACTION', 'Geração de convite solicitada pelo painel.')
      begin
        if simulate?
          log('OK', 'Convite simulado: https://discord.gg/rubymc-simulado')
          return { ok: true, message: 'Convite simulado.', invite_url: 'https://discord.gg/rubymc-simulado' }
        end

        service = RubyMC::DiscordBotService.new(load_settings, simulate: false)
        result = service.create_invite('invite_channel_id', max_age: 86400, max_uses: 0)
        if result[:ok]
          log('OK', "Convite gerado: #{result[:url]}")
          return { ok: true, message: 'Convite gerado com sucesso.', invite_url: result[:url] }
        else
          log('ERROR', "Falha ao gerar convite: #{result[:reason] || result[:error] || 'desconhecida'}")
          return { ok: false, message: result[:reason] || result[:error] || 'Falha ao gerar convite.' }
        end
      rescue StandardError => e
        log('ERROR', "Falha ao gerar convite: #{e.class}: #{e.message}")
        { ok: false, message: e.message }
      end
    end

    def rubymc_simular_discord
      log('ACTION', 'Simulação Discord solicitada pelo painel.')
      cfg = discord_config
      discord_payload = if cfg
                          cfg.validation_report[:summary].merge(
                            configured: true, status: 'configurado'
                          )
                        else
                          { configured: false, status: 'indisponível' }
                        end

      service = RubyMC::DiscordBotService.new(load_settings, simulate: true)
      remote = service.validate_remote!
      discord_payload[:members_count] = remote[:members_count] || 0
      discord_payload[:presence_count] = remote[:presence_count] || 0
      log('OK', "Simulação Discord: #{discord_payload[:members_count]} membros, #{discord_payload[:presence_count]} online.")
      {
        ok: true,
        message: 'Simulação Discord ativada.',
        discord: discord_payload
      }
    rescue StandardError => e
      log('ERROR', "Simulação Discord falhou: #{e.class}: #{e.message}")
      { ok: false, message: e.message }
    end

    def rubymc_open_docs_final
      docs_path = File.join(project_root, 'docs')
      target = File.directory?(docs_path) ? docs_path : project_root
      log('ACTION', "Abrindo documentação: #{target}") if respond_to?(:log)
      system('xdg-open', target, out: File::NULL, err: File::NULL)
      log('OK', 'Comando para abrir documentação executado.') if respond_to?(:log)
      { ok: true, message: 'Documentação aberta.' }
    end

    def rubymc_check_updates_final
      log('ACTION', 'Verificação de atualizações solicitada pelo painel.') if respond_to?(:log)

      unless File.directory?(File.join(project_root, '.git'))
        log('WARN', 'Projeto não parece ser um repositório Git.') if respond_to?(:log)
        return { ok: false, message: 'Projeto não parece ser um repositório Git.' }
      end

      system('git', '-C', project_root, 'fetch', '--all', '--prune', out: File::NULL, err: File::NULL)
      status = `git -C #{Shellwords.escape(project_root)} status -sb 2>&1`.strip
      log('OK', "Status Git: #{status}") if respond_to?(:log)
      { ok: true, message: 'Atualizações verificadas.', git_status: status }
    end

    def rubymc_join_server_final(discord_user_id: nil)
      info = respond_to?(:server_info) ? server_info : {}
      address = (info[:address] || info['address'] || '').to_s.strip

      if address.empty? || address =~ /ID_DO_SERVIDOR|SERVIDOR_MINECRAFT|não configurado/i
        log('WARN', 'Servidor não configurado. Configure o endereço real em config/settings.yml.') if respond_to?(:log)
        return { ok: false, message: 'Servidor não configurado.' }
      end

      if discord_user_id
        begin
          require_relative 'rubymc/discord_bot_service'
          service = RubyMC::DiscordBotService.new(CONFIG, simulate: respond_to?(:simulate?) ? simulate? : false)
          link = "minecraft://?addExternalServer=RubyMC|#{address}"
          service.send_dm(discord_user_id, "🎮 Clique no link para entrar no servidor RubyMC!\n\n#{link}\n\nSe o link não abrir automaticamente, copie e cole no navegador.")
          log('OK', "Link do servidor enviado via DM para #{discord_user_id}") if respond_to?(:log)
          { ok: true, message: 'Link do servidor enviado no seu DM do Discord! Verifique suas mensagens.' }
        rescue => e
          log('WARN', "Falha ao enviar DM: #{e.message}") if respond_to?(:log)
          { ok: true, message: "Link: minecraft://?addExternalServer=RubyMC|#{address}", address: address }
        end
      else
        log('OK', "Endereço do servidor: #{address}") if respond_to?(:log)
        { ok: true, message: "Servidor: #{address}", address: address }
      end
    end



    # RubyMC Discord + IA Final Integration
    def rubymc_discord_panel_service
      RubyMC::DiscordPanelActions.new(root: project_root)
    end

    def rubymc_handle_discord_panel_action(action)
      case action.to_s
      when 'validate_discord', 'discord_validate', 'validate_discord_settings'
        result = rubymc_discord_panel_service.validate
        log(result[:ok] ? 'OK' : 'ERROR', result[:message]) if respond_to?(:log)
        Array(result[:problems]).each { |problem| log('WARN', problem) } if respond_to?(:log)
        result
      when 'test_discord_logs', 'discord_test_logs', 'test_logs_channel'
        result = rubymc_discord_panel_service.test_logs_channel
        log(result[:ok] ? 'OK' : 'ERROR', result[:message]) if respond_to?(:log)
        result
      when 'discord_bot_status', 'bot_status'
        result = rubymc_discord_panel_service.bot_status
        log(result[:ok] ? 'OK' : 'ERROR', result[:message]) if respond_to?(:log)
        result
      else
        nil
      end
    rescue StandardError => e
      log('ERROR', "#{e.class}: #{e.message}") if respond_to?(:log)
      { ok: false, message: e.message, error: e.class.name }
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

    MAX_BG_THREADS = 32

    def with_thread_slot(label)
      mtx = @bg_thread_mtx ||= Mutex.new
      ctr = @bg_thread_ctr ||= 0

      acquired = false
      mtx.synchronize do
        if ctr < MAX_BG_THREADS
          ctr += 1
          acquired = true
        end
      end

      unless acquired
        log('WARN', "Thread pool cheia (#{MAX_BG_THREADS}), ignorando: #{label}")
        return
      end

      Thread.new do
        begin
          yield
        rescue => e
          log('ERROR', "#{label} lançou exceção: #{e.message}")
        ensure
          mtx.synchronize { @bg_thread_ctr -= 1 }
        end
      end
    end

    def run_async(label)
      log('ACTION', "#{label} iniciado...")
      with_thread_slot(label) do
        yield
        log('OK', "#{label} concluído.")
      end
    end

    def run_project_checks
      ruby_files = Dir.glob(File.join(root, '{lib,bin,scripts,test}', '**', '*.rb')) +
                   [File.join(root, 'launcher.rb'), File.join(root, 'launcher_gui.rb'), File.join(root, 'app', 'bot.rb')]
      ruby_files.select! { |file| File.file?(file) }

      log('CHECK', "Verificando sintaxe de #{ruby_files.size} arquivos Ruby...")

      ruby_files.each do |file|
        run_command("#{RbConfig.ruby} -c #{shell_escape(file)}", timeout_seconds: 15)
      end

      run_command('bundle check', timeout_seconds: 60)
    end

    def organize_project
      script = File.join(root, 'scripts', 'organize_project_root.rb')
      unless File.file?(script)
        log('WARN', 'scripts/organize_project_root.rb não encontrado. Nada foi organizado.')
        return
      end

      run_command("#{RbConfig.ruby} #{shell_escape(script)} --apply", timeout_seconds: 60)
    end

    def test_community_server
      address = server_info[:address]
      if address == 'não configurado'
        log('WARN', 'Servidor não configurado em config/settings.yml.')
        return
      end

      host_part, port_part = address.split(':', 2)
      target_port = Integer(port_part || 25565)

      log('COMMAND', "Testando TCP #{host_part}:#{target_port}")
      Timeout.timeout(8) do
        socket = TCPSocket.new(host_part, target_port)
        socket.close
      end
      log('OK', "Servidor respondeu em #{host_part}:#{target_port}")
    rescue StandardError => e
      log('ERROR', "Servidor não respondeu: #{e.message}")
    end

    def validate_discord_config(remote: false)
      cfg = discord_config
      raise 'Módulo RubyMC::DiscordConfig não carregado.' unless cfg

      report = cfg.validation_report
      summary = report[:summary]
      log('CHECK', "Discord bot_enabled=#{summary[:bot_enabled]} guild=#{summary[:guild_id_configured]} token=#{summary[:token_configured]}")
      log('CHECK', "Canais configurados: #{summary[:channels_configured]}/#{summary[:channels_total]}")
      log('CHECK', "Cargos configurados: #{summary[:roles_configured]}/#{summary[:roles_total]}")

      report[:warnings].each { |warning| log('WARN', warning) }
      report[:errors].each { |error| log('ERROR', error) }

      if report[:errors].empty?
        log('OK', 'Configuração local de canais e cargos está válida.')
      else
        log('WARN', 'Configuração local do Discord ainda precisa de ajustes.')
      end

      report[:remote] = nil
      if remote
        if !defined?(RubyMC::DiscordBotService)
          log('WARN', 'Módulo RubyMC::DiscordBotService não carregado. Validação remota não executada.')
        elsif !cfg.bot_enabled?
          log('WARN', 'Bot está inativo. Para validar token e enviar mensagens, defina discord.bot_enabled: true.')
        elsif !cfg.token_configured?
          log('WARN', 'Bot token não configurado. Validação remota não executada.')
        else
          remote_report = RubyMC::DiscordBotService.new(load_settings, simulate: simulate?).validate_remote!
          report[:remote] = remote_report
          log('OK', "Bot autenticado: #{remote_report.dig(:bot, :username) || remote_report.dig('bot', 'username')}")
          log('OK', "Servidor Discord validado: #{remote_report.dig(:guild, :name) || remote_report.dig('guild', 'name')}")
          log('OK', "Discord remoto: #{remote_report[:channels_count]} canais e #{remote_report[:roles_count]} cargos encontrados.")
        end
      end

      report
    rescue StandardError => e
      log('ERROR', "Validação Discord falhou: #{e.class}: #{e.message}")
      { ok: false, errors: [e.message], warnings: [], summary: {}, channels: {}, roles: {} }
    end

    def test_discord_log
      raise 'Módulo RubyMC::DiscordBotService não carregado.' unless defined?(RubyMC::DiscordBotService)

      service = RubyMC::DiscordBotService.new(load_settings, simulate: simulate?)
      result = service.send_log_message("💎 RubyMC Launcher: teste de log enviado pelo painel web às #{Time.now.strftime('%H:%M:%S')}.")
      log('OK', "Mensagem de teste enviada ao Discord no canal #{result[:channel_id]}.")
      result
    rescue StandardError => e
      log('ERROR', "Falha ao enviar log para o Discord: #{e.class}: #{e.message}")
      log('WARN', 'Confira: bot_enabled true, bot_token válido, guild_id correto, canal de logs configurado e permissão Enviar Mensagens.')
      raise
    end

    def terminal_command(command)
      candidates = [
        ['gnome-terminal', '--', 'bash', '-lc', command],
        ['kgx', '--', 'bash', '-lc', command],
        ['konsole', '-e', 'bash', '-lc', command],
        ['xfce4-terminal', '--command', "bash -lc #{shell_escape(command)}"],
        ['x-terminal-emulator', '-e', 'bash', '-lc', command],
        ['xterm', '-e', 'bash', '-lc', command]
      ]

      found = candidates.find { |cmd| executable?(cmd.first) }
      return found if found

      log('WARN', 'Nenhum terminal externo encontrado; executando em segundo plano.')
      ['bash', '-lc', command]
    end

    def executable?(name)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, name)
        File.executable?(path) && !File.directory?(path)
      end
    end

    def run_command(command, timeout_seconds: 30)
      log('COMMAND', "$ #{command}")

      output = ''
      status = nil

      Timeout.timeout(timeout_seconds) do
        stdout, stderr, wait_status = Open3.capture3(command, chdir: root)
        output = [stdout, stderr].reject(&:empty?).join("\n")
        status = wait_status
      end

      output.lines.last(30).each { |line| log(status&.success? ? 'OUT' : 'ERR', line.chomp) }
      log(status&.success? ? 'OK' : 'ERROR', "Comando finalizado com status #{status&.exitstatus}: #{command}")
    rescue Timeout::Error
      log('ERROR', "Tempo esgotado após #{timeout_seconds}s: #{command}")
    end

    def upload_filename(upload)
      if upload.respond_to?(:filename)
        upload.filename.to_s
      elsif upload.respond_to?(:original_filename)
        upload.original_filename.to_s
      else
        'modpack.zip'
      end
    end

    def upload_body(upload)
      if upload.respond_to?(:body)
        upload.body.to_s.b
      elsif upload.respond_to?(:tempfile)
        upload.tempfile.rewind
        upload.tempfile.read.to_s.b
      elsif upload.respond_to?(:read)
        upload.read.to_s.b
      else
        upload.to_s.b
      end
    end

    def safe_basename(filename)
      File.basename(filename.to_s).gsub(/[^0-9A-Za-z._-]/, '_')
    end

    def safe_profile_id(name)
      base = name.to_s.downcase.gsub(/[^0-9a-z]+/, '-').gsub(/\A-|-\z/, '')
      base.empty? ? "modpack-#{SecureRandom.hex(4)}" : base
    end

    def shell_escape(value)
      "'" + value.to_s.gsub("'", "'\\\\''") + "'"
    end

    # ── Contas Microsoft ─────────────────────────────────────────────────
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

    # ── Launch Minecraft (Java) ─────────────────────────────────────────────
    def handle_launch(req, res)
      params = parse_json(req.body) || {}
      account_id = params['account_id'] || params.dig('settings', 'account')
      server_mode = params['server_mode'] == true
      ram = (params['ram_mb'] || params.dig('settings', 'ram') || 2048).to_i

      if account_id && !account_id.to_s.empty?
        result = with_server_mutex('launch_minecraft') { launch_with_account(account_id: account_id, ram_mb: ram, server_mode: server_mode) }
      else
        username = params['username'] || params.dig('settings', 'username').to_s.strip
        return json(res, { ok: false, error: 'Username não preenchido.' }) if username.empty?
        result = with_server_mutex('launch_minecraft') { launch_offline(username: username, ram_mb: ram, server_mode: server_mode) }
      end

      if result[:pid]
        json(res, { ok: true, message: "Minecraft iniciado (PID #{result[:pid]})", pid: result[:pid] })
      else
        json(res, { ok: false, error: result[:error] || 'Falha ao iniciar Minecraft.' })
      end
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def launch_with_account(account_id:, ram_mb: 2048, server_mode: false)
      bank = AccountBank.new
      account = bank.find(account_id)
      raise "Conta '#{account_id}' não encontrada." unless account

      token = account[:mc_access_token]
      username = account[:username]
      uuid = account[:uuid]

      # Renova se expirado
      if !bank.mc_token_valid?(account) && account[:ms_refresh_token]
        log('ACTION', "Renovando sessão Microsoft para #{username}...")
        ms = MicrosoftAuth.refresh_token(account[:ms_refresh_token])
        mc = MicrosoftAuth.full_auth_flow(ms[:access_token])
        bank.update_tokens(
          email: account[:email],
          ms_access_token: ms[:access_token], ms_refresh_token: ms[:refresh_token],
          ms_expires_in: ms[:expires_in],
          mc_access_token: mc[:mc_access_token], mc_expires_in: mc[:mc_expires_in],
          username: mc[:username], uuid: mc[:uuid]
        )
        token = mc[:mc_access_token]
        username = mc[:username]
        uuid = mc[:uuid]
      end

      bank.touch(account[:email])
      version_id = resolve_launch_version

      mc_mgr = MinecraftManager.new
      mc_mgr.ensure_version_dependencies(version_id)
      java = detect_java_for_client(version_id)
      raise "Java não encontrado para a versão #{version_id}" unless java

      server_address = server_mode ? load_settings.dig('discord', 'server_address') : nil

      pid = mc_mgr.launch(
        version_id: version_id, username: username, uuid: uuid,
        mc_access_token: token, java_path: java, ram_mb: ram_mb,
        server_address: server_address
      )
      Process.detach(pid)
      msg = server_mode ? "conectado ao servidor" : "com conta Microsoft"
      log('OK', "Minecraft #{version_id} #{msg} (PID #{pid}, #{username})")
      { pid: pid }
    rescue => e
      log('ERROR', "Falha ao lançar Minecraft: #{e.message}")
      { error: e.message }
    end

    def launch_offline(username:, ram_mb: 2048, server_mode: false)
      uuid = SecureRandom.uuid.gsub('-', '')
      token = '0'
      version_id = resolve_launch_version

      mc_mgr = MinecraftManager.new
      mc_mgr.ensure_version_dependencies(version_id)
      java = detect_java_for_client(version_id)
      raise "Java não encontrado para a versão #{version_id}" unless java

      server_address = server_mode ? load_settings.dig('discord', 'server_address') : nil

      pid = mc_mgr.launch(
        version_id: version_id, username: username, uuid: uuid,
        mc_access_token: token, java_path: java, ram_mb: ram_mb,
        server_address: server_address
      )
      Process.detach(pid)
      msg = server_mode ? "conectado ao servidor" : "offline"
      log('OK', "Minecraft #{version_id} #{msg} (PID #{pid}, #{username})")
      { pid: pid }
    rescue => e
      log('ERROR', "Falha ao lançar Minecraft: #{e.message}")
      { error: e.message }
    end

    def resolve_launch_version
      active = version_manager&.active_version
      return active[:id] if active&.dig(:id)
      '1.21.4'
    end

    def detect_java_for_client(version_id)
      if defined?(RubyMC::ServerVersionManager)
        rec = RubyMC::ServerVersionManager.recommended_java(version_id)
        return rec[:java_path] if rec && rec[:java_path] && File.executable?(rec[:java_path])
      end
      settings = load_settings rescue {}
      path = settings.dig('servers', 'java', 'active_java').to_s
      return path if File.executable?(path)
      if ENV['JAVA_HOME']
        candidate = File.join(ENV['JAVA_HOME'], 'bin', 'java')
        return candidate if File.executable?(candidate)
      end
      jvms = Dir.glob('/usr/lib/jvm/*/bin/java').select { |f| File.executable?(f) }
      return jvms.max_by { |f| extract_java_major_version(f) } unless jvms.empty?
      path = `which java 2>/dev/null`.strip
      return path unless path.empty?
      _, _, status = Open3.capture3('java', '-version')
      status.success? ? 'java' : nil
    end

    def extract_java_major_version(java_path)
      out, _, _ = Open3.capture3(java_path.to_s, '-version')
      match = out.match(/version "(?:1\.)?(\d+)/)
      match ? match[1].to_i : 0
    rescue
      0
    end

    def load_settings
      YAML.safe_load_file(File.join(root, 'config', 'settings.yml'), permitted_classes: [Symbol], aliases: true) || {}
    rescue
      {}
    end

    # ── VIP / Pagamentos ──────────────────────────────────
    def handle_vip_status(req, res)
      user = authenticated_user(req)
      if user
        current_role = refresh_user_role(user[:user_id])
        if current_role
          user[:role] = current_role
          @sessions.each { |_, v| v[:role] = current_role if v[:user_id] == user[:user_id] }
          save_sessions
        end
        if user[:role] == :admin
          return json(res, {
            ok: true, active: true,
            plan: 'vip_vitalicio',
            plan_label: 'VIP Vitalício (Gratuito pela Equipe)',
            role_granted: true,
            expires_at: nil
          })
        end
      end
      vip_data = load_vip_data
      if vip_data && vip_data[:active]
        json(res, {
          ok: true, active: true,
          plan: vip_data[:plan],
          plan_label: vip_data[:plan_label],
          expires_at: vip_data[:expires_at]
        })
      else
        json(res, { ok: true, active: false })
      end
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def handle_vip_plans(req, res)
      user = authenticated_user(req)
      plans = [
        { id: 'vip_mensal', name: 'VIP Mensal', price: '4,90', period: 'mês', description: 'Cargo VIP no servidor, comandos exclusivos e prioridade.' },
        { id: 'vip_trimestral', name: 'VIP Trimestral', price: '9,90', period: 'trimestre', description: 'Todos os benefícios VIP com 3 meses de duração.' },
        { id: 'vip_vitalicio', name: 'VIP Vitalício', price: '19,90', period: 'vitalício', description: 'Acesso VIP permanente com todos os benefícios.' }
      ]
      if user && user[:role] == :staff
        plans = plans.map do |p|
          discounted = format('%.2f', p[:price].sub(',', '.').to_f / 2).sub('.', ',')
          p.merge(price: discounted)
        end
      end
      json(res, { ok: true, plans: plans, staff_discount: user && user[:role] == :staff })
    end

    def handle_vip_history(_req, res)
      vip_data = load_vip_data
      payments = vip_data && vip_data[:payments] ? vip_data[:payments] : []
      json(res, { ok: true, payments: payments })
    rescue => e
      json(res, { ok: false, error: e.message, payments: [] })
    end

    def handle_vip_checkout(req, res)
      user = authenticated_user(req)
      if user && user[:role] == :admin
        return json(res, { ok: false, error: 'Administradores já possuem acesso VIP Vitalício gratuito.' })
      end

      params = parse_json(req.body) || {}
      price_id = params['price_id'] || req.query['price_id']
      unless price_id
        return json(res, { ok: false, error: 'price_id não informado.' })
      end

      cfg = load_settings.dig('stripe') || {}

      if cfg['secret_key'] && !cfg['secret_key'].empty? && defined?(Stripe)
        Stripe.api_key = cfg['secret_key']
        base = "http://#{request_host(req)}"
        session = Stripe::Checkout::Session.create({
          mode: 'payment',
          line_items: [{ price: price_id, quantity: 1 }],
          success_url: "#{base}/?vip=success",
          cancel_url: "#{base}/?vip=cancel"
        })
        return json(res, { ok: true, url: session.url })
      end

      json(res, { ok: true, url: "https://checkout.stripe.com/pay/#{price_id}", sandbox: true })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def load_vip_data
      file = File.join(root, 'tmp', 'vip_data.json')
      return nil unless File.exist?(file)
      JSON.parse(File.read(file), symbolize_names: true)
    rescue
      nil
    end

    # ── Auth / Sessão ────────────────────────────────────
    def authenticated_user(req)
      cookie = parse_cookie(req)
      session_id = cookie['rubymc_session']
      return nil unless session_id
      session = @sessions[session_id]
      return nil unless session
      if session[:expires_at] && Time.now > session[:expires_at]
        @sessions.delete(session_id)
        save_sessions
        return nil
      end
      session
    end

    def parse_cookie(req)
      return {} unless req['Cookie']
      req['Cookie'].split(';').each_with_object({}) do |pair, hash|
        k, v = pair.strip.split('=', 2)
        hash[k] = v if k && v
      end
    rescue
      {}
    end

    def set_session_cookie(res, session_id)
      res['Set-Cookie'] = "rubymc_session=#{session_id}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=86400"
    end

    def session_hmac_key
      @session_hmac_key ||= SecureRandom.random_bytes(32)
    end

    def compute_session_hmac(payload)
      OpenSSL::HMAC.hexdigest('SHA256', session_hmac_key, payload)
    end

    def save_sessions
      @sessions_mutex.synchronize do
        data = @sessions.transform_values do |s|
          s.merge(expires_at: s[:expires_at]&.iso8601)
        end
        json = JSON.generate(data)
        hmac = compute_session_hmac(json)
        File.write(@session_file, JSON.generate(data: json, hmac: hmac))
      end
    rescue StandardError => e
      log('WARN', "save_sessions: #{e.message}")
    end

    def load_sessions
      return unless File.exist?(@session_file)

      @sessions_mutex.synchronize do
        envelope = JSON.parse(File.read(@session_file))
        raw_json = envelope['data']
        stored_hmac = envelope['hmac']

        unless raw_json.is_a?(String) && stored_hmac.is_a?(String)
          return @sessions = {}
        end

        expected_hmac = compute_session_hmac(raw_json)
        unless OpenSSL.secure_compare(expected_hmac, stored_hmac)
          log('WARN', 'load_sessions: HMAC mismatch — session file tampered, resetting')
          return @sessions = {}
        end

        raw = JSON.parse(raw_json)
        @sessions = raw.transform_values do |s|
          s.transform_keys(&:to_sym).tap do |sym|
            sym[:expires_at] = Time.parse(sym[:expires_at]) if sym[:expires_at].is_a?(String)
          end
        end
      end
    rescue StandardError => e
      log('WARN', "load_sessions: #{e.message}")
      @sessions = {}
    end

    def clear_session_cookie(res)
      res['Set-Cookie'] = "rubymc_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
    end

    def launcher_role_for(discord_role_ids)
      settings = load_settings
      admin_ids = settings.dig('launcher', 'roles', 'admin_ids') || []
      staff_ids = settings.dig('launcher', 'roles', 'staff_ids') || []
      player_ids = settings.dig('launcher', 'roles', 'player_ids') || []
      member_ids = settings.dig('launcher', 'roles', 'member_ids') || []
      return :admin unless (discord_role_ids & admin_ids).empty?
      return :staff unless (discord_role_ids & staff_ids).empty?
      return :player unless (discord_role_ids & player_ids).empty?
      return :member unless (discord_role_ids & member_ids).empty?
      :member
    end

    def refresh_user_role(user_id)
      oauth = oauth_config
      guild_id = oauth[:guild_id]
      bot_token = oauth[:bot_token]
      return nil unless guild_id && bot_token
      uri = URI("https://discord.com/api/v10/guilds/#{guild_id}/members/#{user_id}")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bot #{bot_token}"
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      return nil unless resp.code.to_i == 200
      member_data = JSON.parse(resp.body)
      launcher_role_for(member_data['roles'] || [])
    rescue => e
      log('WARN', "refresh_user_role falhou: #{e.message}")
      nil
    end

    def dynamic_redirect_uri(req, oauth)
      configured = oauth['redirect_uri'].to_s.strip
      configured.empty? ? DISCORD_CALLBACK_URL : configured
    end

    def request_host(req)
      h = req['Host']
      h && !h.empty? ? h : "#{host}:#{port}"
    end

    def handle_auth_status(req, res)
      user = authenticated_user(req)
      if user
        json(res, {
          ok: true, authenticated: true,
          user: { id: user[:user_id], username: user[:username], avatar: user[:avatar] },
          role: user[:role]
        })
      else
        json(res, { ok: true, authenticated: false })
      end
    end

    def oauth_config
      @oauth_config ||= begin
        cfg = RubyMC::DiscordConfig.new(load_settings)
        {
          client_id: cfg.client_id,
          client_secret: cfg.client_secret,
          bot_token: cfg.bot_token,
          guild_id: cfg.guild_id,
          redirect_uri: cfg.discord.dig('oauth', 'redirect_uri').to_s.strip
        }
      end
    end

    def handle_discord_login(req, res)
      oauth = oauth_config
      state = SecureRandom.hex(16)
      (@oauth_states ||= {})[state] = Time.now + 300
      cb = oauth[:redirect_uri].to_s.strip
      cb = DISCORD_CALLBACK_URL if cb.empty?
      url = "https://discord.com/api/oauth2/authorize?client_id=#{oauth[:client_id]}&redirect_uri=#{CGI.escape(cb)}&response_type=code&scope=identify&state=#{state}"
      res.status = 302
      res['Location'] = url
    end

    def handle_discord_callback(req, res)
      code = req.query['code']
      error = req.query['error']
      state = req.query['state']
      if error || !code
        res.status = 302
        res['Location'] = "/?login=error&reason=#{CGI.escape(error || 'no_code')}"
        return
      end

      # Validate OAuth state parameter (CSRF protection)
      if state.nil? || !(@oauth_states ||= {}).key?(state) || @oauth_states[state] < Time.now
        res.status = 302
        res['Location'] = '/?login=error&reason=invalid_state'
        return
      end
      @oauth_states.delete(state)

      oauth = oauth_config
      unless oauth[:client_id] && oauth[:client_secret] && oauth[:guild_id] && oauth[:bot_token]
        res.status = 302
        res['Location'] = '/?login=error&reason=missing_config'
        return
      end

      # 1. Exchange code for token
      cb = oauth[:redirect_uri].to_s.strip
      cb = DISCORD_CALLBACK_URL if cb.empty?
      token_uri = URI('https://discord.com/api/v10/oauth2/token')
      token_resp = Net::HTTP.post_form(token_uri, {
        client_id: oauth[:client_id],
        client_secret: oauth[:client_secret],
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: cb
      })

      unless token_resp.code.to_i == 200
        res.status = 302
        res['Location'] = '/?login=error&reason=token_exchange_failed'
        return
      end

      token_data = JSON.parse(token_resp.body)
      access_token = token_data['access_token']

      # 2. Get user info
      user_uri = URI('https://discord.com/api/v10/users/@me')
      user_req = Net::HTTP::Get.new(user_uri)
      user_req['Authorization'] = "Bearer #{access_token}"
      user_resp = Net::HTTP.start(user_uri.hostname, user_uri.port, use_ssl: true) { |http| http.request(user_req) }

      unless user_resp.code.to_i == 200
        res.status = 302
        res['Location'] = '/?login=error&reason=userinfo_failed'
        return
      end

      user_data = JSON.parse(user_resp.body)
      user_id = user_data['id']

      # 3. Get guild member info (via bot token) — optional
      #     If user is not in the guild, they still get a :member session
      #     and must complete verification (enter server + DM code) to unlock features.
      member_uri = URI("https://discord.com/api/v10/guilds/#{oauth[:guild_id]}/members/#{user_id}")
      member_req = Net::HTTP::Get.new(member_uri)
      member_req['Authorization'] = "Bot #{oauth[:bot_token]}"

      begin
        member_resp = Net::HTTP.start(member_uri.hostname, member_uri.port, use_ssl: true) { |http| http.request(member_req) }
        if member_resp.code.to_i == 200
          member_data = JSON.parse(member_resp.body)
          discord_roles = member_data['roles'] || []
        else
          discord_roles = []
          puts "[LOGIN] #{user_data['username']} (#{user_id}) não está no servidor — acesso limitado a :member"
        end
      rescue => e
        discord_roles = []
        puts "[LOGIN] Erro ao verificar guild member para #{user_id}: #{e.message} — acesso limitado a :member"
      end

      # 4. Determine launcher role
      role = launcher_role_for(discord_roles)

      # 5. Create session
      session_id = SecureRandom.hex(32)
      @sessions[session_id] = {
        user_id: user_id,
        username: user_data['username'],
        avatar: user_data['avatar'],
        role: role,
        expires_at: Time.now + 86400
      }
      save_sessions

      set_session_cookie(res, session_id)
      res.status = 302
      res['Location'] = '/?login=success'
    end

    def handle_auth_logout(req, res)
      cookie = parse_cookie(req)
      session_id = cookie['rubymc_session']
      if session_id
        @sessions.delete(session_id)
        save_sessions
      end
      clear_session_cookie(res)
      json(res, { ok: true })
    end

    # ── Verificação (Membro → Membro Ruby) ────────────────
    def handle_verify_status(req, res)
      user = authenticated_user(req)
      unless user
        return json(res, { ok: false, error: 'Não autenticado.' })
      end

      vdata = load_verification_data
      uid = user[:user_id].to_s
      state = vdata[uid] || {}

      json(res, {
        ok: true,
        terms_accepted: state['terms_accepted'] == true,
        discord_verified: state['discord_verified'] == true,
        overall_complete: state['terms_accepted'] == true && state['discord_verified'] == true
      })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def handle_verify_accept_terms(req, res)
      user = authenticated_user(req)
      unless user
        return json(res, { ok: false, error: 'Não autenticado.' })
      end
      unless user[:role] == :member
        return json(res, { ok: false, error: 'Apenas Membros podem se verificar.' })
      end

      vdata = load_verification_data
      uid = user[:user_id].to_s
      vdata[uid] ||= {}
      vdata[uid]['terms_accepted'] = true
      save_verification_data(vdata)

      json(res, { ok: true, terms_accepted: true })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def handle_verify_check_guild(req, res)
      user = authenticated_user(req)
      unless user
        return json(res, { ok: false, error: 'Não autenticado.' })
      end

      uid = user[:user_id].to_s
      oauth = oauth_config
      guild_id = oauth[:guild_id]
      bot_token = oauth[:bot_token]

      unless guild_id && bot_token
        return json(res, { ok: false, error: 'Discord não configurado.' })
      end

      uri = URI("https://discord.com/api/v10/guilds/#{guild_id}/members/#{uid}")
      req_check = Net::HTTP::Get.new(uri)
      req_check['Authorization'] = "Bot #{bot_token}"
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req_check) }

      json(res, { ok: true, in_guild: resp.code.to_i == 200 })
    rescue => e
      json(res, { ok: true, in_guild: false })
    end

    def handle_verify_send_discord_code(req, res)
      user = authenticated_user(req)
      unless user
        return json(res, { ok: false, error: 'Não autenticado.' })
      end
      unless user[:role] == :member
        return json(res, { ok: false, error: 'Apenas Membros podem se verificar.' })
      end

      vdata = load_verification_data
      uid = user[:user_id].to_s
      unless vdata.dig(uid, 'terms_accepted')
        return json(res, { ok: false, error: 'Aceite os Termos de Uso primeiro.' })
      end

      # Verifica se o usuário está no servidor Discord
      oauth = oauth_config
      guild_id = oauth[:guild_id]
      bot_token = oauth[:bot_token]
      if guild_id && bot_token
        member_uri = URI("https://discord.com/api/v10/guilds/#{guild_id}/members/#{uid}")
        member_req = Net::HTTP::Get.new(member_uri)
        member_req['Authorization'] = "Bot #{bot_token}"
        member_resp = Net::HTTP.start(member_uri.hostname, member_uri.port, use_ssl: true) { |http| http.request(member_req) }
        unless member_resp.code.to_i == 200
          return json(res, { ok: false, error: 'Você precisa entrar no servidor Discord da RubyMC primeiro para receber o código.' })
        end
      end

      code = format('%06d', rand(1_000_00..999_999))
      expires = (Time.now + 300).to_i

      vdata[uid] ||= {}
      vdata[uid]['discord_code'] = code
      vdata[uid]['discord_code_expires'] = expires
      save_verification_data(vdata)

      if defined?(RubyMC::DiscordBotService)
        begin
          service = RubyMC::DiscordBotService.new(load_settings, simulate: simulate?)
          service.send_dm(uid, "🔐 Seu código de verificação RubyMC é: **#{code}**\nEle expira em 5 minutos. Insira-o no launcher para completar a verificação.")
        rescue => e
          log('WARN', "Falha ao enviar DM: #{e.message}")
          return json(res, { ok: false, error: "Falha ao enviar DM: #{e.message}" })
        end
      end

      json(res, { ok: true, message: 'Código enviado via DM no Discord.' })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def handle_verify_confirm_discord_code(req, res)
      user = authenticated_user(req)
      unless user
        return json(res, { ok: false, error: 'Não autenticado.' })
      end

      params = parse_json(req.body) || {}
      code = params['code'].to_s.strip

      vdata = load_verification_data
      uid = user[:user_id].to_s
      entry = vdata[uid] || {}

      unless entry['discord_code']
        return json(res, { ok: false, error: 'Nenhum código foi solicitado. Clique em "Verificar via Discord" primeiro.' })
      end

      if entry['discord_code_expires'].to_i < Time.now.to_i
        return json(res, { ok: false, error: 'Código expirado. Solicite um novo.' })
      end

      unless entry['discord_code'] == code
        return json(res, { ok: false, error: 'Código inválido. Tente novamente.' })
      end

      vdata[uid]['discord_verified'] = true
      save_verification_data(vdata)

      json(res, { ok: true, discord_verified: true })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def handle_verify_complete(req, res)
      user = authenticated_user(req)
      unless user
        return json(res, { ok: false, error: 'Não autenticado.' })
      end
      unless user[:role] == :member
        return json(res, { ok: false, error: 'Apenas Membros podem se verificar.' })
      end

      vdata = load_verification_data
      uid = user[:user_id].to_s
      state = vdata[uid] || {}

      unless state['terms_accepted'] && state['discord_verified']
        return json(res, { ok: false, error: 'Complete todas as etapas de verificação primeiro.' })
      end

      # Assign Membro Ruby role via bot
      if defined?(RubyMC::DiscordBotService)
        begin
          service = RubyMC::DiscordBotService.new(load_settings, simulate: simulate?)
          service.assign_role(uid, 'player_role_id')
        rescue => e
          log('ERROR', "Falha ao atribuir cargo Membro Ruby: #{e.message}")
          return json(res, { ok: false, error: "Falha ao atribuir cargo: #{e.message}" })
        end
      end

      # Update session
      @sessions.each { |_, v| v[:role] = :player if v[:user_id] == uid }
      save_sessions

      # Clean up verification data
      vdata.delete(uid)
      save_verification_data(vdata)

      json(res, { ok: true, role: 'player', message: 'Parabéns! Agora você é Membro Ruby.' })
    rescue => e
      json(res, { ok: false, error: e.message })
    end

    def verification_hmac_key
      @verification_hmac_key ||= SecureRandom.random_bytes(32)
    end

    def compute_vdata_hmac(payload)
      OpenSSL::HMAC.hexdigest('SHA256', verification_hmac_key, payload)
    end

    def load_verification_data
      file = File.join(root, 'tmp', 'verification_data.json')
      return {} unless File.exist?(file)

      envelope = JSON.parse(File.read(file))
      raw_json = envelope['data']
      stored_hmac = envelope['hmac']

      return {} unless raw_json.is_a?(String) && stored_hmac.is_a?(String)

      expected = compute_vdata_hmac(raw_json)
      return {} unless OpenSSL.secure_compare(expected, stored_hmac)

      JSON.parse(raw_json)
    rescue
      {}
    end

    def save_verification_data(data)
      file = File.join(root, 'tmp', 'verification_data.json')
      FileUtils.mkdir_p(File.dirname(file))
      json = JSON.generate(data)
      hmac = compute_vdata_hmac(json)
      File.write(file, JSON.generate(data: json, hmac: hmac))
    end

  end
end