# frozen_string_literal: true

require "fileutils"
require "json"
require "socket"
require "timeout"
require "shellwords"
require_relative "simple_settings_adapter"

begin
  require_relative "server_version_manager"
rescue LoadError
  # O arquivo pode já ter sido carregado pelo app/server.rb.
end

module RubyMC
  # Runtime completo para controlar o servidor Java do RubyMC.
  #
  # Recursos:
  # - iniciar/parar/reiniciar servidor Java;
  # - ativar versão escolhida antes de iniciar;
  # - aguardar a porta 25565 abrir;
  # - retornar tail do latest.log quando o servidor inicia processo mas não sobe;
  # - evitar "No child processes" e falhas quando o PID antigo já morreu;
  # - corrigir server.properties para LAN/dev.
  class JavaServerRuntime
    DEFAULT_PORT = 25_565
    DEFAULT_WAIT_TIMEOUT = 60

    attr_reader :root_dir, :server_dir, :settings, :run_dir, :pid_file, :stdout_log

    def self.build(root_dir: nil, server_dir: nil, settings: nil)
      root = root_dir || detect_project_root
      srv = server_dir || detect_server_dir(root)
      cfg = settings || SimpleSettingsAdapter.new(File.join(root, "config", "settings.yml"))
      new(root_dir: root, server_dir: srv, settings: cfg)
    end

    def self.detect_project_root
      # Quando carregado por app/server.rb, __dir__ tende a ser lib/rubymc.
      File.expand_path(File.join(__dir__, "..", ".."))
    end

    def self.detect_server_dir(root)
      env_dir = ENV["RUBYMC_JAVA_SERVER_DIR"].to_s.strip
      return File.expand_path(env_dir, root) unless env_dir.empty?

      candidates = [
        File.join(root, "server"),
        File.join(root, "servers", "java"),
        root
      ]

      existing = candidates.find do |path|
        File.exist?(File.join(path, "server.jar")) || File.directory?(File.join(path, "versions"))
      end

      existing || File.join(root, "server")
    end

    def initialize(root_dir:, server_dir:, settings:)
      @root_dir = File.expand_path(root_dir)
      @server_dir = File.expand_path(server_dir)
      @settings = settings
      @run_dir = File.join(@root_dir, "tmp", "rubymc")
      @pid_file = File.join(@run_dir, "java_server.pid")
      @stdout_log = File.join(@run_dir, "java_server.out.log")

      FileUtils.mkdir_p(@server_dir)
      FileUtils.mkdir_p(@run_dir)
    end

    def start(version_id: nil, loader: nil, host: "127.0.0.1", port: DEFAULT_PORT, wait_timeout: DEFAULT_WAIT_TIMEOUT)
      port = port.to_i <= 0 ? DEFAULT_PORT : port.to_i

      if running?
        return {
          ok: true,
          already_running: true,
          message: "Servidor Java já está rodando (PID #{current_pid}).",
          pid: current_pid,
          port_open: port_open?(host, port),
          log_tail: latest_log_tail
        }
      end

      activation = activate_version(version_id, loader)
      return activation unless activation[:ok]

      prepare_server_files(port: port)

      jar = active_jar_path
      return failure("server.jar não encontrado em #{server_dir}.") unless jar && File.exist?(jar)

      java = active_java_command
      ram = server_ram_mb
      command = [java, "-Xms#{ram}M", "-Xmx#{ram}M", "-jar", jar, "nogui"]

      FileUtils.mkdir_p(File.join(server_dir, "logs"))
      out = File.open(stdout_log, "ab")
      out.sync = true

      pid = Process.spawn(
        *command,
        chdir: server_dir,
        out: out,
        err: out,
        pgroup: true
      )

      write_pid(pid)

      wait_result = wait_for_server(host: host, port: port, timeout: wait_timeout, pid: pid)

      if wait_result[:ok]
        return {
          ok: true,
          message: "Servidor Java iniciado e aceitando conexões em #{host}:#{port}.",
          pid: pid,
          port: port,
          version_id: active_version_id,
          java: java,
          command: command.join(" ")
        }
      end

      {
        ok: false,
        message: wait_result[:message],
        pid: pid,
        port: port,
        process_alive: process_alive?(pid),
        log_tail: latest_log_tail,
        stdout_tail: file_tail(stdout_log, 80),
        command: command.join(" ")
      }
    end

    def stop(wait_timeout: 20)
      pid = current_pid

      unless pid && process_alive?(pid)
        delete_pid
        return {
          ok: true,
          message: "Servidor Java já estava parado.",
          pid: nil
        }
      end

      terminate_process_group(pid)
      stopped = wait_until(timeout: wait_timeout) { !process_alive?(pid) }

      unless stopped
        kill_process_group(pid)
        wait_until(timeout: 5) { !process_alive?(pid) }
      end

      delete_pid

      {
        ok: true,
        message: "Servidor Java parado.",
        pid: pid,
        log_tail: latest_log_tail
      }
    end

    def restart(version_id: nil, loader: nil, host: "127.0.0.1", port: DEFAULT_PORT, wait_timeout: DEFAULT_WAIT_TIMEOUT)
      stop
      sleep 1
      start(version_id: version_id, loader: loader, host: host, port: port, wait_timeout: wait_timeout)
    end

    def status(host: "127.0.0.1", port: DEFAULT_PORT)
      pid = current_pid
      alive = pid && process_alive?(pid)
      open = port_open?(host, port)

      {
        ok: true,
        running: alive,
        pid: alive ? pid : nil,
        port_open: open,
        host: host,
        port: port,
        active_version: active_version_id,
        active_jar: active_jar_path,
        latest_log: latest_log_path,
        message: status_message(alive, open, host, port)
      }
    end

    def test(host: "127.0.0.1", port: DEFAULT_PORT, timeout: 3)
      if port_open?(host, port, timeout: timeout)
        {
          ok: true,
          message: "Servidor respondeu em #{host}:#{port}.",
          host: host,
          port: port
        }
      else
        {
          ok: false,
          message: "Servidor não respondeu em #{host}:#{port}.",
          host: host,
          port: port,
          log_tail: latest_log_tail
        }
      end
    end

    def running?
      pid = current_pid
      pid && process_alive?(pid)
    end

    def current_pid
      return nil unless File.exist?(pid_file)

      value = File.read(pid_file).to_s.strip
      return nil if value.empty?

      value.to_i
    rescue StandardError
      nil
    end

    def latest_log_tail(lines = 80)
      file_tail(latest_log_path, lines)
    end

    def latest_log_path
      File.join(server_dir, "logs", "latest.log")
    end

    private

    def activate_version(version_id, loader)
      version = version_id.to_s.strip
      return { ok: true, skipped: true } if version.empty?

      unless defined?(RubyMC::ServerVersionManager)
        return failure("ServerVersionManager não está carregado; não foi possível ativar a versão #{version}.")
      end

      manager = RubyMC::ServerVersionManager.new(server_dir, settings)
      result = manager.activate(version)

      unless result[:ok] || result["ok"]
        return failure(result[:error] || result["error"] || "Falha ao ativar versão #{version}.")
      end

      { ok: true, activated: true, version_id: version, loader: loader || result[:loader] || result["loader"] }
    rescue StandardError => e
      failure("Falha ao ativar versão #{version}: #{e.message}")
    end

    def prepare_server_files(port:)
      File.write(File.join(server_dir, "eula.txt"), "eula=true\n")
      ensure_server_properties(port: port)
    end

    def ensure_server_properties(port:)
      path = File.join(server_dir, "server.properties")
      props = parse_properties(File.exist?(path) ? File.read(path) : "")

      # Para LAN/dev com contas não Java oficiais, evita erro de sessão inválida.
      props["online-mode"] = ENV.fetch("RUBYMC_ONLINE_MODE", "false")
      props["enforce-secure-profile"] = ENV.fetch("RUBYMC_ENFORCE_SECURE_PROFILE", "false")

      # Importante: vazio faz o servidor escutar em todas as interfaces.
      props["server-ip"] = ENV.fetch("RUBYMC_SERVER_IP", "")
      props["server-port"] = port.to_s
      props["enable-status"] ||= "true"
      props["motd"] ||= "A Minecraft Server"
      props["max-players"] ||= "20"

      content = props.map { |key, value| "#{key}=#{value}" }.join("\n") + "\n"
      File.write(path, content)
    end

    def parse_properties(content)
      props = {}
      content.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")
        key, value = stripped.split("=", 2)
        next if key.to_s.empty?
        props[key] = value.to_s
      end
      props
    end

    def active_jar_path
      configured = settings.dig("servers", "java", "active_jar").to_s.strip
      return configured if !configured.empty? && File.exist?(configured)

      fallback = File.join(server_dir, "server.jar")
      return fallback if File.exist?(fallback)

      nil
    end

    def active_version_id
      settings.dig("servers", "java", "active_version")
    rescue StandardError
      nil
    end

    def active_java_command
      configured = settings.dig("servers", "java", "active_java").to_s.strip
      return configured unless configured.empty?

      ENV.fetch("RUBYMC_JAVA", "java")
    rescue StandardError
      ENV.fetch("RUBYMC_JAVA", "java")
    end

    def server_ram_mb
      env_ram = ENV["RUBYMC_SERVER_RAM"].to_s.strip
      return env_ram.to_i if env_ram.match?(/\A\d+\z/) && env_ram.to_i.positive?

      candidates = [
        settings.dig("servers", "java", "ram"),
        settings.dig("minecraft", "ram"),
        settings.dig("settings", "ram")
      ].compact

      value = candidates.find { |item| item.to_s.match?(/\A\d+\z/) }
      value ? value.to_i : 2048
    rescue StandardError
      2048
    end

    def wait_for_server(host:, port:, timeout:, pid:)
      deadline = Time.now + timeout.to_i

      loop do
        return { ok: true } if port_open?(host, port, timeout: 1)

        unless process_alive?(pid)
          return {
            ok: false,
            message: "Servidor iniciou, mas o processo morreu antes de abrir a porta #{port}."
          }
        end

        if Time.now >= deadline
          return {
            ok: false,
            message: "Servidor iniciou processo, mas não abriu a porta #{port} em #{timeout}s."
          }
        end

        sleep 1
      end
    end

    def port_open?(host, port, timeout: 2)
      Timeout.timeout(timeout) do
        socket = TCPSocket.new(host, port)
        socket.close
        true
      end
    rescue StandardError
      false
    end

    def process_alive?(pid)
      return false unless pid && pid.to_i.positive?

      Process.kill(0, pid.to_i)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def write_pid(pid)
      File.write(pid_file, pid.to_s)
    end

    def delete_pid
      FileUtils.rm_f(pid_file)
    end

    def terminate_process_group(pid)
      Process.kill("TERM", -pid.to_i)
    rescue Errno::ESRCH, Errno::EPERM
      begin
        Process.kill("TERM", pid.to_i)
      rescue StandardError
        nil
      end
    end

    def kill_process_group(pid)
      Process.kill("KILL", -pid.to_i)
    rescue Errno::ESRCH, Errno::EPERM
      begin
        Process.kill("KILL", pid.to_i)
      rescue StandardError
        nil
      end
    end

    def wait_until(timeout:)
      deadline = Time.now + timeout.to_i
      until Time.now >= deadline
        return true if yield
        sleep 0.3
      end
      false
    end

    def file_tail(path, lines)
      return "#{path} não encontrado." unless path && File.exist?(path)

      File.readlines(path, chomp: true).last(lines).join("\n")
    rescue StandardError => e
      "Não foi possível ler #{path}: #{e.message}"
    end

    def status_message(alive, open, host, port)
      if alive && open
        "Servidor Java rodando e aceitando conexões em #{host}:#{port}."
      elsif alive
        "Servidor Java tem processo ativo, mas a porta #{port} ainda não respondeu."
      else
        "Servidor Java parado."
      end
    end

    def failure(message)
      { ok: false, message: message, error: message, log_tail: latest_log_tail }
    end
  end
end
