# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'timeout'
require 'yaml'
require 'shellwords'
require 'tmpdir'
require 'open-uri'
require 'net/http'

module RubyMC
  class ServerManager
    SETTINGS_PATH = File.expand_path('../../config/settings.yml', __dir__)
    STORE_PATH = File.join(Dir.home, '.minecraft_ruby_launcher', 'servers')

    class << self
      def start(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg
        return { ok: false, error: 'Já está rodando' } if running?(key)

        install_if_needed(key, cfg)

        settings = load_settings
        ensure_server_dir(cfg)
        ensure_eula(cfg) unless cfg[:type] == 'bedrock'
        ensure_server_properties(cfg, settings) unless cfg[:type] == 'bedrock'

        Dir.chdir(cfg[:dir]) do
          pid = if cfg[:type] == 'bedrock'
                  spawn_bedrock(cfg)
                else
                  spawn_java(cfg)
                end
          write_pid(key, pid)
          sleep(1)
          return { ok: true, pid: pid, key: key, status: 'started' }
        end
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def stop(key)
        pid = read_pid(key)
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

        delete_pid(key)
        { ok: true, key: key, status: 'stopped' }
      rescue Errno::ESRCH
        delete_pid(key)
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
        pid = read_pid(key)
        pid ? process_alive?(pid) : false
      end

      def status(key)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg

        running = running?(key)
        pid = read_pid(key) if running

        { ok: true, key: key, name: cfg[:name], running: running, pid: pid, port: cfg[:port], address: cfg[:address], type: cfg[:type], loader: cfg[:loader], version: cfg[:version] }
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def all_status
        servers = load_servers_list
        servers.map { |s| status(s) }
      end

      def set_version(key, new_version)
        settings = load_settings
        servers = settings['discord']&.dig('servers') || []
        entry = servers.find { |s| s['id'] == key.to_s }
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless entry

        entry['version'] = new_version.to_s
        save_settings(settings)

        cfg = server_config(key)
        if cfg[:auto_install] && cfg[:loader] == :vanilla && cfg[:type] != 'bedrock'
          jar_path = File.join(cfg[:dir], cfg[:jar])
          FileUtils.mkdir_p(cfg[:dir])
          begin
            download_vanilla_jar(jar_path, new_version)
            return { ok: true, version: new_version, downloaded: true, message: "Versão alterada para #{new_version} e server.jar baixado." }
          rescue StandardError => e
            return { ok: true, version: new_version, downloaded: false, message: "Versão alterada para #{new_version}, mas download falhou: #{e.message}" }
          end
        end

        { ok: true, version: new_version, downloaded: false, message: "Versão alterada para #{new_version}. O download será feito na próxima inicialização." }
      end

      def console(key, lines: 20)
        cfg = server_config(key)
        return { ok: false, error: "Servidor '#{key}' não encontrado" } unless cfg

        log_path = File.join(cfg[:dir], 'logs', 'latest.log')
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

      private

      def server_config(key)
        settings = load_settings
        servers = settings.dig('discord', 'servers') || []
        entry = servers.find { |s| s['id'] == key.to_s }
        return nil unless entry

        dir = expand_path(entry['dir'] || File.join(Dir.home, 'Servidores', "Ruby#{entry['name']}"))

        {
          id: entry['id'],
          name: entry['name'],
          address: entry['address'],
          type: entry['type'] || 'java',
          loader: (entry['loader'] || 'vanilla').to_sym,
          version: entry['version'] || nil,
          dir: dir,
          jar: entry['jar'] || 'server.jar',
          binary: entry['binary'] || 'bedrock_server',
          java: entry['java'] || default_java,
          memory: entry['memory'] || '-Xmx2G -Xms1G',
          port: parse_port(entry['address']),
          motd: entry['motd'] || "RubyMC #{entry['name']}",
          online_mode: entry['online_mode'] != false,
          max_players: entry['max_players'] || 20,
          auto_install: entry['auto_install'] != false
        }
      end

      def load_servers_list
        settings = load_settings
        (settings.dig('discord', 'servers') || []).map { |s| s['id'] }
      end

      def install_if_needed(key, cfg)
        return unless cfg[:auto_install]
        return if cfg[:type] == 'bedrock'
        return unless cfg[:loader] == :vanilla

        jar_path = File.join(cfg[:dir], cfg[:jar])
        return if File.file?(jar_path)

        FileUtils.mkdir_p(cfg[:dir])
        download_vanilla_jar(jar_path, cfg[:version])
      end

      def download_vanilla_jar(jar_path, version = nil)
        manifest_uri = URI('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json')
        manifest = JSON.parse(Net::HTTP.get(manifest_uri))
        target = version || manifest['latest']['release']
        version_entry = manifest['versions'].find { |v| v['id'] == target }
        unless version_entry
          fallback = manifest['latest']['release']
          log('WARN', "Versão #{target} não encontrada no manifest, usando #{fallback}")
          target = fallback
          version_entry = manifest['versions'].find { |v| v['id'] == target }
        end
        raise "Versão #{target} não encontrada no manifest" unless version_entry

        version_uri = URI(version_entry['url'])
        version_data = JSON.parse(Net::HTTP.get(version_uri))
        jar_url = version_data['downloads']['server']['url']
        raise 'URL do server.jar não encontrada' unless jar_url

        jar_uri = URI(jar_url)
        log('OK', "Baixando server.jar da versão #{target}...")
        IO.copy_stream(URI.open(jar_uri), jar_path)
        log('OK', "server.jar salvo em #{jar_path}")
      rescue StandardError => e
        log('ERROR', "Falha ao baixar server.jar: #{e.message}")
        raise
      end

      def spawn_java(cfg)
        java_bin = cfg[:java]
        memory = cfg[:memory]
        args = Shellwords.split(memory) + ['-jar', cfg[:jar], 'nogui']
        Process.spawn(java_bin, *args, pgroup: true, out: ['log.txt', 'a'], err: [:child, :out])
      end

      def spawn_bedrock(cfg)
        binary = File.join(cfg[:dir], cfg[:binary])
        Process.spawn(binary, pgroup: true, out: ['log.txt', 'a'], err: [:child, :out])
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

      def parse_port(address)
        return 25565 unless address
        parts = address.to_s.split(':')
        parts[1] ? Integer(parts[1]) : 25565
      rescue
        25565
      end

      def pid_path(key)
        File.join(STORE_PATH, "#{key}.pid")
      end

      def write_pid(key, pid)
        FileUtils.mkdir_p(STORE_PATH)
        File.write(pid_path(key), pid.to_s)
      end

      def read_pid(key)
        path = pid_path(key)
        return nil unless File.file?(path)

        pid = File.read(path).strip.to_i
        pid.positive? ? pid : nil
      rescue StandardError
        nil
      end

      def delete_pid(key)
        path = pid_path(key)
        File.delete(path) if File.file?(path)
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
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

        props['online-mode'] = cfg[:online_mode].to_s
        props['server-port'] = cfg[:port].to_s
        props['enable-status'] ||= 'true'
        props['motd'] = cfg[:motd] || props['motd'] || 'RubyMC Server'
        props['max-players'] = cfg[:max_players].to_s

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

      def save_settings(data)
        File.write(SETTINGS_PATH, YAML.dump(data))
      rescue StandardError => e
        log('ERROR', "Falha ao salvar settings: #{e.message}")
      end

      def expand_path(path)
        File.expand_path(path.to_s.gsub(/\A~/, Dir.home))
      end

      def log(level, msg)
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        $stdout.puts "[#{timestamp}] [#{level}] #{msg}"
      end
    end
  end
end