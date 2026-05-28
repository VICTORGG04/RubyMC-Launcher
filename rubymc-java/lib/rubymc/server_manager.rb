# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'timeout'
require 'yaml'

module RubyMC
  class ServerManager
    SETTINGS_PATH = File.join(File.dirname(__FILE__), '..', '..', 'config', 'settings.yml')

    SERVERS = {
      java: {
        name: 'Java',
        dir: '/home/victor/Servidores/ServidorMinecraftJava',
        world: 'world',
        log_rel: 'logs/latest.log',
        pidfile: '/tmp/rubymc_java.pid',
        port: 25_565,
        protocol: :java
      }
    }.freeze

    BACKUP_DIR = File.join(ENV['HOME'] || '/tmp', 'Servidores', 'backups')

    class << self
      def start(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg
        return { ok: false, error: 'Já está rodando' } if running?(key)

        cmd = build_cmd(key)
        return { ok: false, error: 'Comando de inicialização não disponível' } unless cmd

        Dir.chdir(cfg[:dir]) do
          pid = spawn(cmd, pgroup: true, out: ['log.txt', 'a'], err: [:child, :out])
          File.write(cfg[:pidfile], pid.to_s)
          sleep(1)
          return { ok: true, pid: pid, key: key, status: 'started' }
        end
      rescue => e
        { ok: false, error: e.message }
      end

      def stop(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg
        return { ok: false, error: 'Não está rodando' } unless running?(key)

        pid = read_pid(cfg)
        Process.kill('TERM', pid)
        Timeout.timeout(15) do
          loop do
            Process.wait(pid, Process::WNOHANG)
            break unless process_alive?(pid)
            sleep(1)
          end
        end
        File.delete(cfg[:pidfile]) if File.file?(cfg[:pidfile])
        { ok: true, key: key, status: 'stopped' }
      rescue Timeout::Error
        Process.kill('KILL', pid) rescue nil
        File.delete(cfg[:pidfile]) if File.file?(cfg[:pidfile])
        { ok: true, key: key, status: 'stopped (force kill)' }
      rescue => e
        { ok: false, error: e.message }
      end

      def restart(key)
        stop(key) # Tenta parar; ignora erro se já estava parado
        sleep(2)
        start(key)
      end

      def running?(key)
        cfg = server_config(key)
        return false unless cfg
        pid = read_pid(cfg)
        pid ? process_alive?(pid) : false
      end

      def console(key, lines: 20)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg

        log_path = File.join(cfg[:dir], cfg[:log_rel])
        unless File.file?(log_path)
          alt_path = File.join(cfg[:dir], 'log.txt')
          log_path = alt_path if File.file?(alt_path)
        end
        return { ok: false, error: 'Arquivo de log não encontrado' } unless File.file?(log_path)

        content = File.read(log_path)
        last_lines = content.lines.last(lines).join
        { ok: true, key: key, log: last_lines, total_lines: content.lines.size }
      rescue => e
        { ok: false, error: e.message }
      end

      def backup(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg

        world_dir = File.join(cfg[:dir], cfg[:world])
        return { ok: false, error: "Diretório world não encontrado: #{world_dir}" } unless Dir.exist?(world_dir)

        FileUtils.mkdir_p(BACKUP_DIR)
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        backup_name = "#{key}_world_#{timestamp}.tar.gz"
        backup_path = File.join(BACKUP_DIR, backup_name)

        Dir.chdir(File.dirname(world_dir)) do
          world_basename = File.basename(world_dir)
          system("tar czf #{backup_path} #{world_basename}")
        end

        size_kb = File.size(backup_path) / 1024
        { ok: true, key: key, path: backup_path, size_kb: size_kb, timestamp: timestamp }
      rescue => e
        { ok: false, error: e.message }
      end

      def status(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg

        running = running?(key)
        pid = read_pid(cfg) if running
        log_info = console(key, lines: 3)
        last_log = log_info[:ok] ? log_info[:log].lines.last(3).join.strip : ''

        { ok: true, key: key, name: cfg[:name], running: running, pid: pid, port: cfg[:port], last_log: last_log }
      rescue => e
        { ok: false, error: e.message }
      end

      def all_status
        SERVERS.keys.map { |k| [k, status(k)] }.to_h
      end

      private

      def server_config(key)
        SERVERS[key.to_s.to_sym]
      end

      def build_cmd(key)
        return nil unless key == :java

        settings = load_settings
        active_ver = settings.dig('servers', 'java', 'active_version')
        return default_java_cmd unless active_ver

        java_bin = settings.dig('servers', 'java', 'active_java')
        java_bin = default_java if java_bin.nil? || java_bin.empty?

        memory = settings.dig('servers', 'java', 'memory') || '-Xmx2G -Xms1G'

        "#{java_bin} #{memory} -jar server.jar nogui"
      end

      def default_java_cmd
        "#{default_java} -Xmx2G -Xms1G -jar server.jar nogui"
      end

      def default_java
        candidates = %w[/usr/lib/jvm/jdk-26-oracle-x64/bin/java /usr/lib/jvm/java-21-openjdk-amd64/bin/java java]
        candidates.find { |p| File.exist?(p) } || 'java'
      end

      def load_settings
        return {} unless File.file?(SETTINGS_PATH)
        YAML.safe_load(File.read(SETTINGS_PATH), permitted_classes: [Symbol], aliases: true) || {}
      rescue
        {}
      end

      def read_pid(cfg)
        return nil unless File.file?(cfg[:pidfile])
        pid = File.read(cfg[:pidfile]).strip.to_i
        pid > 0 ? pid : nil
      rescue
        nil
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end

      def spawn(cmd, opts = {})
        Process.spawn(cmd, opts)
      end
    end
  end
end
