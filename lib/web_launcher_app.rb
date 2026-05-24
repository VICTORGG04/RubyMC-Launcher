# frozen_string_literal: true

require 'json'
require 'webrick'
require 'open3'
require 'fileutils'
require 'rbconfig'
require 'socket'
require 'timeout'
require 'yaml'

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
      when '/api/status'
        json(res, status_payload)
      when '/api/logs'
        json(res, { ok: true, logs: read_logs })
      when '/api/action'
        handle_action(req, res)
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
      action = data['action'].to_s

      case action
      when 'clear_logs'
        File.write(log_file, '')
        log('SYSTEM', 'Display limpo. Aguardando novos eventos...')
        json(res, { ok: true, message: 'Display limpo.' })
      when 'refresh_status'
        log('ACTION', 'Status atualizado pelo painel.')
        json(res, { ok: true, message: 'Status atualizado.', status: status_payload })
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
      else
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
        java_version: java_version,
        modpacks_count: modpacks_count,
        server: server_info,
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
      paths = [
        File.join(root, 'modpacks'),
        File.expand_path('~/.minecraft_ruby_launcher/modpacks')
      ]
      paths.sum do |path|
        Dir.exist?(path) ? Dir.children(path).count { |entry| File.directory?(File.join(path, entry)) || entry.end_with?('.mrpack', '.zip') } : 0
      end
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

    def open_classic_launcher(extra_env: {})
      launcher = File.join(root, 'launcher.rb')
      raise 'launcher.rb não encontrado na raiz do projeto.' unless File.file?(launcher)

      ruby = RbConfig.ruby
      command = %(cd #{shell_escape(root)} && #{extra_env.map { |k, v| "#{k}=#{shell_escape(v)}" }.join(' ')} #{shell_escape(ruby)} #{shell_escape(launcher)}; echo; read -p "Pressione ENTER para fechar...")

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

    def shell_escape(value)
      "'" + value.to_s.gsub("'", "'\\\\''") + "'"
    end
  end
end
