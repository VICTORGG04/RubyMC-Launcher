# frozen_string_literal: true

require 'fileutils'
require 'httparty'
require 'json'
require 'time'
require 'set'
require 'shellwords'

module RubyMC
  class ServerVersionManager
    MOJANG_MANIFEST_URL = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
    PAPER_API_URL = 'https://api.papermc.io/v2/projects/paper'
    FABRIC_META_URL = 'https://meta.fabricmc.net/v2/versions'
    FORGE_MAVEN_URL = 'https://maven.minecraftforge.net/net/minecraftforge/forge'
    TIMEOUT = 15
    DOWNLOAD_TIMEOUT = 120

    LOADERS = %i[vanilla paper fabric forge].freeze
    LOADER_LABELS = {
      vanilla: 'Vanilla',
      paper: 'Paper',
      fabric: 'Fabric',
      forge: 'Forge'
    }.freeze

    # Minecraft version formats:
    #   New: "26.1.1" (major=26)  → MC 1.21.5+
    #   Old: "1.21.5" (major=1)   → check second component
    #
    # Retorno padrão:
    #   {
    #     java_version: '21',
    #     java_path: '/usr/bin/java',
    #     label: 'MC 1.21–1.21.4'
    #   }
    JAVA_VERSION_MAP = [
      {
        match: ->(parts) { parts[0].to_i >= 26 },
        java_version: '25+',
        java_path: '/usr/lib/jvm/jdk-26-oracle-x64/bin/java',
        label: 'MC 1.21.5+'
      },
      {
        match: ->(parts) { parts[0].to_i == 1 && parts[1].to_i >= 21 && parts.fetch(2, 0).to_i >= 5 },
        java_version: '25+',
        java_path: '/usr/lib/jvm/jdk-26-oracle-x64/bin/java',
        label: 'MC 1.21.5+'
      },
      {
        match: ->(parts) { parts[0].to_i == 1 && parts[1].to_i == 21 },
        java_version: '21',
        java_path: '/usr/bin/java',
        label: 'MC 1.21–1.21.4'
      },
      {
        match: ->(parts) { parts[0].to_i == 1 && parts[1].to_i >= 18 && parts[1].to_i <= 20 },
        java_version: '17',
        java_path: '/usr/lib/jvm/java-17-openjdk-amd64/bin/java',
        label: 'MC 1.18–1.20'
      },
      {
        match: ->(parts) { parts[0].to_i == 1 && parts[1].to_i == 17 },
        java_version: '16',
        java_path: 'java',
        label: 'MC 1.17'
      },
      {
        match: ->(parts) { parts[0].to_i == 1 && parts[1].to_i <= 16 },
        java_version: '8',
        java_path: 'java',
        label: 'MC ≤ 1.16'
      },
      {
        match: ->(_) { true },
        java_version: '21',
        java_path: '/usr/bin/java',
        label: 'Versão desconhecida'
      }
    ].freeze

    # -------------------------------------------------------------------------
    # MÉTODOS DE CLASSE
    #
    # Estes métodos corrigem o erro:
    #   undefined method `recommended_java' for RubyMC::ServerVersionManager:Class
    #
    # Alguma parte do backend chama:
    #   RubyMC::ServerVersionManager.recommended_java(...)
    #
    # então o método precisa existir também como método de classe.
    # -------------------------------------------------------------------------

    def self.recommended_java(version_id)
      parts = normalize_version_parts(version_id)
      rec = JAVA_VERSION_MAP.find { |rule| rule[:match].call(parts) } || JAVA_VERSION_MAP.last
      rec = rec.dup

      rec[:java_path] = resolve_java_path(rec[:java_path])
      rec
    end

    def self.recommended_java_command(version_id)
      recommended_java(version_id)[:java_path]
    end

    def self.recommended_java_version(version_id)
      recommended_java(version_id)[:java_version]
    end

    def self.java_command(version_id)
      recommended_java_command(version_id)
    end

    def self.normalize_version_parts(version_id)
      raw = extract_version_id(version_id)

      # Captura versões como:
      #   1.21.4
      #   26.1.2
      #   fabric-loader-1.21.4
      clean = raw[/\d+(?:\.\d+){0,2}/].to_s
      parts = clean.split('.').map(&:to_i)
      parts = [1, 21, 0] if parts.empty?

      parts << 0 while parts.length < 3
      parts
    end
    private_class_method :normalize_version_parts

    def self.extract_version_id(version)
      return '' if version.nil?

      if version.is_a?(Hash)
        return (
          version[:id] ||
            version['id'] ||
            version[:version] ||
            version['version'] ||
            version[:name] ||
            version['name'] ||
            ''
        ).to_s
      end

      return version.id.to_s if version.respond_to?(:id)
      return version.version.to_s if version.respond_to?(:version)
      return version.name.to_s if version.respond_to?(:name)

      version.to_s
    end
    private_class_method :extract_version_id

    def self.resolve_java_path(preferred_path)
      preferred_path = preferred_path.to_s.strip

      return preferred_path if preferred_path == 'java'
      return preferred_path if !preferred_path.empty? && File.executable?(preferred_path)

      java_home = ENV['JAVA_HOME'].to_s.strip
      java_home_bin = File.join(java_home, 'bin', 'java')
      return java_home_bin if !java_home.empty? && File.executable?(java_home_bin)

      common_candidates = [
        preferred_path,
        '/usr/lib/jvm/jdk-26-oracle-x64/bin/java',
        '/usr/lib/jvm/java-21-openjdk-amd64/bin/java',
        '/usr/lib/jvm/java-17-openjdk-amd64/bin/java',
        '/usr/bin/java'
      ].compact.uniq

      common_candidates.find { |path| !path.empty? && File.executable?(path) } || 'java'
    end
    private_class_method :resolve_java_path

    # -------------------------------------------------------------------------
    # INSTÂNCIA
    # -------------------------------------------------------------------------

    def initialize(server_dir, settings)
      @server_dir = server_dir
      @settings = settings
      @versions_dir = File.join(server_dir, 'versions')
      FileUtils.mkdir_p(@versions_dir)
    end

    def list_available(loader: :vanilla, limit: 50)
      case loader.to_sym
      when :vanilla then list_vanilla_versions(limit)
      when :paper then list_paper_versions(limit)
      when :fabric then list_fabric_versions
      when :forge then list_forge_versions
      else []
      end
    rescue StandardError => e
      [{ error: "Falha ao listar versões: #{e.message}" }]
    end

    def list_installed
      return [] unless Dir.exist?(@versions_dir)

      Dir.children(@versions_dir).filter_map do |entry|
        next if entry.start_with?('.')

        vdir = File.join(@versions_dir, entry)
        next unless File.directory?(vdir)

        # Prefer the bundled jar (Vanilla) over cached server-*.jar inner jars.
        jars = Dir.glob(File.join(vdir, '*.jar'))
                  .reject { |j| j.include?('installer') || j.end_with?("server-#{entry}.jar") }

        # If only cached inner jar remains, still include it.
        jars = Dir.glob(File.join(vdir, "server-#{entry}.jar")) if jars.empty?
        next if jars.empty?

        jar = jars.first
        loader = detect_loader(jar)

        {
          id: entry,
          path: jar,
          loader: loader,
          loader_label: LOADER_LABELS[loader] || loader.to_s,
          size_kb: File.size(jar) / 1024,
          modified: File.mtime(jar).iso8601
        }
      end.sort_by { |v| v[:id] }.reverse
    end

    def install(version_id, loader: :vanilla, java_bin: nil)
      vdir = File.join(@versions_dir, version_id)
      FileUtils.mkdir_p(vdir)

      case loader.to_sym
      when :vanilla then install_vanilla(version_id, vdir)
      when :paper then install_paper(version_id, vdir)
      when :fabric then install_fabric(version_id, vdir, java_bin)
      when :forge then install_forge(version_id, vdir, java_bin)
      else { ok: false, error: "Loader desconhecido: #{loader}" }
      end
    end

    def remove(version_id)
      vdir = File.join(@versions_dir, version_id)
      return { ok: false, error: "Versão '#{version_id}' não instalada" } unless Dir.exist?(vdir)

      active_id = @settings.dig('servers', 'java', 'active_version')
      if active_id == version_id
        return { ok: false, error: "Versão '#{version_id}' está ativa. Desative primeiro." }
      end

      FileUtils.rm_rf(vdir)
      { ok: true, message: "Versão '#{version_id}' removida." }
    end

    def activate(version_id)
      installed = list_installed
      ver = installed.find { |v| v[:id] == version_id }
      return { ok: false, error: "Versão '#{version_id}' não instalada." } unless ver

      data = @settings.data
      data['servers'] ||= {}
      data['servers']['java'] ||= {}
      data['servers']['java']['active_version'] = version_id
      data['servers']['java']['active_loader'] = ver[:loader].to_s
      data['servers']['java']['active_jar'] = ver[:path]

      rec = recommended_java(version_id)
      data['servers']['java']['active_java'] = rec[:java_path]
      data['servers']['java']['active_java_version'] = rec[:java_version]
      data['servers']['java']['active_java_label'] = rec[:label]

      @settings.save(data)

      # Copy (not symlink) to server.jar so the Vanilla bundler can safely
      # extract its inner jar without overwriting itself.
      server_jar = File.join(@server_dir, 'server.jar')
      FileUtils.rm_f(server_jar)
      FileUtils.cp(ver[:path], server_jar)

      {
        ok: true,
        message: "Versão '#{version_id}' (#{ver[:loader]}) ativada.",
        loader: ver[:loader],
        java: rec
      }
    end

    def active_version
      id = @settings.dig('servers', 'java', 'active_version')
      return nil unless id

      loader = @settings.dig('servers', 'java', 'active_loader') || 'vanilla'
      jar = @settings.dig('servers', 'java', 'active_jar')
      java = @settings.dig('servers', 'java', 'active_java')

      {
        id: id,
        loader: loader,
        label: LOADER_LABELS[loader.to_sym] || loader,
        jar: jar,
        java: java
      }
    end

    # Mantém compatibilidade com o código existente que chama:
    #   manager.recommended_java(...)
    def recommended_java(version_id)
      self.class.recommended_java(version_id)
    end

    def recommended_java_command(version_id)
      self.class.recommended_java_command(version_id)
    end

    def recommended_java_version(version_id)
      self.class.recommended_java_version(version_id)
    end

    def java_command(version_id)
      self.class.java_command(version_id)
    end

    private

    def list_vanilla_versions(limit)
      manifest = get_json(MOJANG_MANIFEST_URL)
      manifest['versions']
        .select { |v| v['type'] == 'release' }
        .first(limit)
        .map do |v|
        {
          id: v['id'],
          type: v['type'],
          loader: :vanilla,
          release_time: v['releaseTime']
        }
      end
    end

    def list_paper_versions(limit)
      data = get_json(PAPER_API_URL)
      data['versions'].last(limit).map do |v|
        {
          id: v,
          type: 'release',
          loader: :paper
        }
      end
    end

    def list_fabric_versions
      data = get_json("#{FABRIC_META_URL}/game")
      (data || []).map do |v|
        {
          id: v['version'],
          type: v['stable'] ? 'release' : 'snapshot',
          loader: :fabric
        }
      end
    end

    def list_forge_versions
      data = get_json('https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json')
      promos = data['promos'] || {}
      versions = Set.new

      promos.each_key do |key|
        version = key.split('-').first
        versions << version if version
      end

      versions.to_a.sort.reverse.map do |version|
        {
          id: version,
          type: 'release',
          loader: :forge
        }
      end
    end

    def install_vanilla(version_id, vdir)
      manifest = get_json(MOJANG_MANIFEST_URL)
      entry = manifest['versions'].find { |v| v['id'] == version_id }
      return { ok: false, error: "Versão '#{version_id}' não encontrada." } unless entry

      meta = get_json(entry['url'])
      url = meta.dig('downloads', 'server', 'url')
      return { ok: false, error: "Server.jar indisponível para '#{version_id}'." } unless url

      # Save with 'vanilla-' prefix so list_installed skips the cached server-*.jar inner jar.
      jar = File.join(vdir, "vanilla-#{version_id}.jar")

      # Remove cached inner jar from previous runs so it gets re-extracted.
      cached = File.join(vdir, "server-#{version_id}.jar")
      FileUtils.rm_f(cached) if File.exist?(cached)

      download_file(url, jar)
      return { ok: false, error: 'Download falhou.' } unless File.exist?(jar) && File.size(jar) > 1000

      {
        ok: true,
        path: jar,
        loader: :vanilla,
        version: version_id
      }
    end

    def install_paper(version_id, vdir)
      builds = get_json("#{PAPER_API_URL}/versions/#{version_id}/builds")
      latest = builds['builds']&.select { |b| b['channel'] == 'default' }&.max_by { |b| b['build'] }
      return { ok: false, error: "Nenhum build estável do Paper para '#{version_id}'." } unless latest

      build_number = latest['build']
      download = latest.dig('downloads', 'application')
      return { ok: false, error: 'Paper build não tem application download.' } unless download

      url = "#{PAPER_API_URL}/versions/#{version_id}/builds/#{build_number}/downloads/#{download['name']}"
      jar = File.join(vdir, "paper-#{version_id}.jar")

      download_file(url, jar)
      return { ok: false, error: 'Download falhou.' } unless File.exist?(jar) && File.size(jar) > 1000

      {
        ok: true,
        path: jar,
        loader: :paper,
        version: version_id,
        build: build_number
      }
    end

    def install_fabric(version_id, vdir, java_bin = nil)
      loaders = get_json("#{FABRIC_META_URL}/loader/#{version_id}")
      return { ok: false, error: "Fabric não suporta '#{version_id}'." } if loaders.empty?

      loader_version = loaders.first['loader']['version']
      installer_url = "https://maven.fabricmc.net/net/fabricmc/fabric-installer/#{loader_version}/fabric-installer-#{loader_version}.jar"
      installer_jar = File.join(vdir, 'fabric-installer.jar')

      download_file(installer_url, installer_jar)
      return { ok: false, error: 'Download do Fabric installer falhou.' } unless File.exist?(installer_jar)

      java = java_bin || recommended_java(version_id)[:java_path]
      out_jar = File.join(vdir, "fabric-server-#{version_id}.jar")
      cmd = [
        Shellwords.escape(java),
        '-jar',
        Shellwords.escape(installer_jar),
        'server',
        '-mcversion',
        Shellwords.escape(version_id),
        '-loader',
        Shellwords.escape(loader_version),
        '-downloadMinecraft'
      ].join(' ')

      Dir.chdir(vdir) do
        output = `#{cmd} 2>&1`
        unless $?.success?
          FileUtils.rm_f(installer_jar)
          return { ok: false, error: "Fabric installer falhou: #{output.lines.last(5).join.strip}" }
        end
      end

      tmp_jar = File.join(vdir, 'fabric-server-launch.jar')
      FileUtils.mv(tmp_jar, out_jar) if File.exist?(tmp_jar)

      FileUtils.rm_f(installer_jar)
      return { ok: false, error: 'Fabric não gerou server jar.' } unless File.exist?(out_jar)

      {
        ok: true,
        path: out_jar,
        loader: :fabric,
        version: version_id,
        loader_version: loader_version
      }
    end

    def install_forge(version_id, vdir, java_bin = nil)
      data = get_json('https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json')
      promos = data['promos'] || {}

      recommended_key = promos.keys.find { |k| k.start_with?("#{version_id}-") && k.end_with?('-recommended') }
      latest_key = promos.keys.find { |k| k.start_with?("#{version_id}-") && k.end_with?('-latest') }
      forge_key = recommended_key || latest_key

      return { ok: false, error: "Forge não disponível para '#{version_id}'." } unless forge_key

      forge_version = forge_key.split('-', 2).last
      forge_url = "#{FORGE_MAVEN_URL}/#{version_id}-#{forge_version}/forge-#{version_id}-#{forge_version}-installer.jar"
      installer_jar = File.join(vdir, 'forge-installer.jar')

      download_file(forge_url, installer_jar)
      return { ok: false, error: 'Download do Forge installer falhou.' } unless File.exist?(installer_jar)

      java = java_bin || recommended_java(version_id)[:java_path]
      cmd = [
        Shellwords.escape(java),
        '-jar',
        Shellwords.escape(installer_jar),
        '--installServer'
      ].join(' ')

      Dir.chdir(vdir) do
        output = `#{cmd} 2>&1`
        unless $?.success?
          FileUtils.rm_f(installer_jar)
          return { ok: false, error: "Forge installer falhou: #{output.lines.last(5).join.strip}" }
        end
      end

      jars = Dir.glob(File.join(vdir, 'forge-*.jar')).reject do |jar|
        jar.include?('installer') || jar.include?('universal')
      end

      jar = jars.first || Dir.glob(File.join(vdir, '**/*.jar')).reject { |j| j.include?('installer') }.first

      FileUtils.rm_f(installer_jar)
      return { ok: false, error: 'Forge não gerou server jar.' } unless jar && File.exist?(jar)

      {
        ok: true,
        path: jar,
        loader: :forge,
        version: version_id,
        forge_version: forge_version
      }
    end

    def get_json(url)
      response = HTTParty.get(url, timeout: TIMEOUT)
      raise "HTTP #{response.code} para #{url}" unless response.success?

      body = response.body.to_s
      raise "Resposta vazia para #{url}" if body.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise "JSON inválido para #{url}: #{e.message}"
    end

    def download_file(url, path)
      File.open(path, 'wb') do |file|
        response = HTTParty.get(url, stream_body: true, timeout: DOWNLOAD_TIMEOUT) do |chunk|
          file.write(chunk)
        end

        raise "HTTP #{response.code}" unless response.success?
      end
    rescue StandardError => e
      FileUtils.rm_f(path)
      raise "Download falhou: #{e.message}"
    end

    def detect_loader(jar_path)
      base = File.basename(jar_path).downcase
      return :paper if base.start_with?('paper')
      return :fabric if base.include?('fabric')
      return :forge if base.include?('forge')
      return :vanilla if base.start_with?('vanilla')

      :vanilla
    end
  end
end