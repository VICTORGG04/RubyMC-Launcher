# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'timeout'
require 'yaml'
require 'shellwords'
require 'tmpdir'

module RubyMC
  class ServerManager
    SETTINGS_PATH = File.expand_path('../../config/settings.yml', __dir__)
    DEFAULT_SERVER_DIR = File.join(Dir.home, 'Servidores', 'ServidorMinecraftJava')
    DEFAULT_BACKUP_DIR = File.join(Dir.home, 'Servidores', 'backups')

    class << self
      def start(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg
        return { ok: false, error: 'Já está rodando' } if running?(key)

        settings = load_settings
        ensure_server_dir(cfg)
        ensure_eula(cfg)
        ensure_server_properties(cfg, settings)

        java_bin, args = build_cmd_parts(key)
        return { ok: false, error: 'Comando de inicialização não disponível' } unless java_bin

        Dir.chdir(cfg[:dir]) do
          pid = Process.spawn(java_bin, *args, pgroup: true, out: ['log.txt', 'a'], err: [:child, :out])
          File.write(cfg[:pidfile], pid.to_s)
          sleep(1)
          return { ok: true, pid: pid, key: key, status: 'started' }
        end
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def stop(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg

        pid = read_pid(cfg)
        return { ok: false, error: 'Não está rodando' } unless pid && process_alive?(pid)

        Process.kill('TERM', pid)

        begin
          Timeout.timeout(15) do
            loop do
              break unless process_alive?(pid)
              sleep(1)
            end
          end
        rescue Timeout::Error
          Process.kill('KILL', pid) rescue nil
        end

        File.delete(cfg[:pidfile]) if File.file?(cfg[:pidfile])
        { ok: true, key: key, status: 'stopped' }
      rescue Errno::ESRCH
        File.delete(cfg[:pidfile]) if cfg && File.file?(cfg[:pidfile])
        { ok: true, key: key, status: 'stopped' }
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def restart(key)
        stop(key)
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
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def backup(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg

        world_dir = File.join(cfg[:dir], cfg[:world])
        return { ok: false, error: "Diretório world não encontrado: #{world_dir}" } unless Dir.exist?(world_dir)

        backup_dir = load_settings.dig('servers', 'java', 'backup_dir') || DEFAULT_BACKUP_DIR
        FileUtils.mkdir_p(backup_dir)

        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        backup_name = "#{key}_world_#{timestamp}.tar.gz"
        backup_path = File.join(backup_dir, backup_name)

        Dir.chdir(File.dirname(world_dir)) do
          system('tar', 'czf', backup_path, File.basename(world_dir))
        end

        size_kb = File.size(backup_path) / 1024
        { ok: true, key: key, path: backup_path, size_kb: size_kb, timestamp: timestamp }
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def status(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg

        running = running?(key)
        pid = read_pid(cfg) if running
        log_info = console(key, lines: 3)
        last_log = log_info[:ok] ? log_info[:log].lines.last(3).join.strip : ''

        { ok: true, key: key, name: cfg[:name], running: running, pid: pid, port: cfg[:port], dir: cfg[:dir], last_log: last_log }
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def all_status
        { java: status(:java) }
      end

      private

      def server_config(key)
        return nil unless key.to_s.to_sym == :java

        settings = load_settings
        java = settings.dig('servers', 'java') || {}

        {
          name: 'Java',
          dir: expand_path(java['path'] || DEFAULT_SERVER_DIR),
          world: java['world'] || 'world',
          log_rel: java['log_rel'] || 'logs/latest.log',
          pidfile: java['pidfile'] || File.join(Dir.tmpdir, 'rubymc_java.pid'),
          port: Integer(java['port'] || 25_565),
          protocol: :java
        }
      end

      def build_cmd_parts(key)
        return nil unless key.to_s.to_sym == :java

        settings = load_settings
        java_bin = settings.dig('servers', 'java', 'active_java')
        java_bin = default_java if java_bin.to_s.strip.empty?
        memory = settings.dig('servers', 'java', 'memory') || '-Xmx2G -Xms1G'
        args = Shellwords.split(memory) + ['-jar', 'server.jar', 'nogui']

        [java_bin, args]
      rescue StandardError
        [default_java, ['-Xmx2G', '-Xms1G', '-jar', 'server.jar', 'nogui']]
      end

      def default_java
        candidates = [
          ENV['JAVA_HOME'] && File.join(ENV['JAVA_HOME'], 'bin', 'java'),
          '/usr/lib/jvm/jdk-26-oracle-x64/bin/java',
          '/usr/lib/jvm/java-25-openjdk-amd64/bin/java',
          '/usr/lib/jvm/java-21-openjdk-amd64/bin/java',
          '/usr/lib/jvm/java-17-openjdk-amd64/bin/java',
          '/usr/bin/java',
          'java'
        ].compact

        candidates.find { |p| p == 'java' || File.executable?(p) } || 'java'
      end

      def ensure_server_dir(cfg)
        FileUtils.mkdir_p(cfg[:dir])
      end

      def ensure_eula(cfg)
        path = File.join(cfg[:dir], 'eula.txt')
        return if File.file?(path) && File.read(path).include?('eula=true')

        File.write(path, "eula=true\n")
      end

      def ensure_server_properties(cfg, settings)
        path = File.join(cfg[:dir], 'server.properties')
        props = {}

        if File.exist?(path)
          File.read(path, encoding: 'ISO-8859-1').each_line do |line|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?('#')

            key, value = stripped.split('=', 2)
            props[key] = value.to_s if key
          end
        end

        props['online-mode'] ||= settings.dig('servers', 'java', 'online_mode').to_s
        props['online-mode'] = 'false' if props['online-mode'].empty?
        props['server-port'] = cfg[:port].to_s
        props['enable-status'] ||= 'true'
        props['motd'] = settings.dig('servers', 'java', 'motd') || props['motd'] || 'RubyMC JAVA'
        props['max-players'] ||= (settings.dig('servers', 'java', 'max_players') || 20).to_s

        content = props.map { |k, v| "#{k}=#{v}" }.join("\n") + "\n"
        File.open(path, 'w:ISO-8859-1') { |f| f.write(latin1_escape(content)) }
      end

      def latin1_escape(str)
        str.each_char.map { |c| c.ord <= 0xFF ? c : format('\\u%04x', c.ord) }.join
      end

      def load_settings
        return {} unless File.file?(SETTINGS_PATH)

        YAML.safe_load(File.read(SETTINGS_PATH), permitted_classes: [Symbol], aliases: true) || {}
      rescue StandardError
        {}
      end

      def expand_path(path)
        File.expand_path(path.to_s.gsub(/\A~/, Dir.home))
      end

      def read_pid(cfg)
        return nil unless File.file?(cfg[:pidfile])

        pid = File.read(cfg[:pidfile]).strip.to_i
        pid.positive? ? pid : nil
      rescue StandardError
        nil
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end
    end
  end
end
