# frozen_string_literal: true

require 'json'
require 'webrick'
require 'open3'
require 'fileutils'
require 'rbconfig'
require 'socket'
require 'timeout'
require 'yaml'
require 'securerandom'

begin
  require_relative 'rubymc_settings'
  require_relative 'discord_config'
  require_relative 'discord_bot_service'
rescue LoadError
  # O launcher web continua funcionando mesmo sem os módulos avançados do Discord.
end

begin
  require_relative 'modpack_manager'
rescue LoadError
  # O launcher continua funcionando mesmo sem o gerenciador avançado de modpacks.
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

    def initialize(root:, host: '127.0.0.1', port: 4567)
      @root = File.expand_path(root)
      @host = host
      @port = Integer(port)
      @log_file = File.join(@root, 'tmp', 'rubymc-display.log')
      FileUtils.mkdir_p(File.dirname(@log_file))
      FileUtils.touch(@log_file)
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
      when '/api/action'
        handle_action(req, res)
      when '/api/modpacks'
        json(res, { ok: true, modpacks: list_modpack_payloads })
      when '/api/modpacks/import'
        handle_modpack_import(req, res)
      when '/api/discord/status'
        json(res, { ok: true, discord: discord_status_payload })
      when '/api/discord/validate'
        handle_discord_validate(req, res)
      when '/api/discord/test-log'
        handle_discord_test_log(req, res)
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
      when 'clear_logs'
        File.write(log_file, '')
        log('SYSTEM', 'Display limpo. Aguardando novos eventos...')
        json(res, { ok: true, message: 'Display limpo.' })
      when 'refresh_status'
        log('ACTION', 'Status atualizado pelo painel.')
        json(res, { ok: true, message: 'Status atualizado.', status: status_payload })
      when 'refresh_modpacks'
        log('ACTION', 'Lista de modpacks atualizada pelo painel.')
        json(res, { ok: true, message: 'Modpacks atualizados.', modpacks: list_modpack_payloads })
      when 'run_tests'
        run_async('Rodar testes') { run_project_checks }
        json(res, { ok: true, message: 'Testes iniciados. Veja o Display.' })
      when 'launch_classic', 'play'
        pid = open_classic_launcher
        json(res, { ok: true, message: "Launcher clássico aberto em terminal externo. PID: #{pid}", pid: pid })
      when 'enter_server'
        pid = open_classic_launcher(extra_env: { 'RUBYMC_HINT' => 'server' })
        json(res, { ok: true, message: "Launcher clássico aberto para entrar no servidor. PID: #{pid}", pid: pid })
      when 'test_server'
        run_async('Testar servidor') { test_community_server }
        json(res, { ok: true, message: 'Teste do servidor iniciado.' })
      when 'organize_project'
        run_async('Organizar raiz') { organize_project }
        json(res, { ok: true, message: 'Organização iniciada.' })
      when 'validate_discord_config'
        report = validate_discord_config(remote: true)
        json(res, { ok: report[:errors].empty?, message: report[:errors].empty? ? 'Validação Discord concluída.' : 'Discord precisa de ajustes.', report: report })
      when 'test_discord_log'
        result = test_discord_log
        json(res, { ok: true, message: 'Teste de log enviado ao Discord.', result: result })
      else
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
      {
        ok: true,
        display_connected: true,
        ruby_version: RUBY_VERSION,
        java_version: java_version,
        modpacks_count: modpacks.size,
        modpacks: modpacks,
        server: server_info,
        discord: discord_status_payload,
        project_root: root,
        time: Time.now.strftime('%H:%M:%S')
      }
    end

    def java_version
      out, err, = Open3.capture3('java', '-version')
      first = [err, out].join("\n").lines.first.to_s.strip
      first.empty? ? 'não encontrado' : first
    rescue Errno::ENOENT
      'não encontrado'
    end

    def modpacks_count
      list_modpack_payloads.size
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
      address = settings.dig('community_server', 'address') ||
                settings.dig('minecraft', 'server_address') ||
                settings.dig('discord', 'server_address') ||
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

    def discord_config
      if defined?(RubyMC::DiscordConfig)
        RubyMC::DiscordConfig.new(load_settings)
      else
        nil
      end
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

    def run_project_checks
      ruby_files = Dir.glob(File.join(root, '{lib,bin,scripts,test}', '**', '*.rb')) +
                   [File.join(root, 'launcher.rb'), File.join(root, 'launcher_gui.rb'), File.join(root, 'bot_daemon.rb')]
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
          remote_report = RubyMC::DiscordBotService.new(load_settings).validate_remote!
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

      service = RubyMC::DiscordBotService.new(load_settings)
      result = service.send_log_message("💎 RubyMC Launcher: teste de log enviado pelo painel web às #{Time.now.strftime('%H:%M:%S')}.")
      log('OK', "Mensagem de teste enviada ao Discord no canal #{result[:channel_id]}.")
      result
    rescue StandardError => e
      log('ERROR', "Falha ao enviar log para o Discord: #{e.class}: #{e.message}")
      log('WARN', 'Confira: bot_enabled true, bot_token válido, guild_id correto, canal de logs configurado e permissão Enviar Mensagens.')
      raise
    end

    def open_classic_launcher(extra_env: {})
      launcher = File.join(root, 'launcher.rb')
      raise 'launcher.rb não encontrado na raiz do projeto.' unless File.file?(launcher)

      ruby = RbConfig.ruby
      env_part = extra_env.map { |k, v| "#{k}=#{shell_escape(v)}" }.join(' ')
      command = %(cd #{shell_escape(root)} && #{env_part} #{shell_escape(ruby)} #{shell_escape(launcher)}; echo; read -p "Pressione ENTER para fechar...")

      terminal_cmd = terminal_command(command)
      log('COMMAND', terminal_cmd.join(' '))

      pid = Process.spawn(*terminal_cmd, out: File::NULL, err: File::NULL)
      Process.detach(pid)
      log('OK', "Launcher clássico iniciado em terminal externo. PID: #{pid}")
      pid
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
  end
end
