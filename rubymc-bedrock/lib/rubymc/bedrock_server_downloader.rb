# frozen_string_literal: true

require "cgi"
require "fileutils"
require "httparty"
require "json"
require "open3"
require "securerandom"
require "time"
require "uri"
require "yaml"

module RubyMC
  class BedrockServerDownloader
    OFFICIAL_PAGE = "https://www.minecraft.net/en-us/download/server/bedrock"
    COMMUNITY_INDEX_URL = "https://raw.githubusercontent.com/kittizz/bedrock-server-downloads/main/bedrock-server-downloads.json"
    USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) RubyMC-BDS/1.0"
    SETTINGS_PATH = File.expand_path("../../config/settings.yml", __dir__)

    attr_reader :project_root, :servers_dir, :cache_dir

    def initialize(project_root: nil, servers_dir: nil)
      @project_root = project_root || ENV["RUBYMC_PROJECT_ROOT"] || File.expand_path("../..", __dir__)
      @servers_dir = servers_dir || File.join(@project_root, "servers", "bedrock")
      @cache_dir = File.join(@project_root, "tmp", "bedrock_downloads")

      FileUtils.mkdir_p(@servers_dir)
      FileUtils.mkdir_p(@cache_dir)
    end

    # Lista versões disponíveis do BDS.
    #
    # Estratégia:
    # 1. Tenta a página oficial da Minecraft.
    # 2. Se a página oficial mudar/quebrar o scraping, usa um índice comunitário
    #    em JSON que rastreia os links oficiais e mantém histórico.
    # 3. Mescla com versões já instaladas para nunca deixar o seletor vazio
    #    quando houver servidores locais.
    def available
      official_links = fetch_official_download_links
      community_links = official_links.any? ? [] : fetch_community_download_links
      installed_links = installed_versions_as_links

      links = dedupe_links(official_links + community_links + installed_links)

      stable = links.select { |item| item[:platform] == "linux" && item[:channel] != "preview" }
      preview = links.select { |item| item[:platform] == "linux" && item[:channel] == "preview" }

      {
        ok: true,
        source: official_links.any? ? OFFICIAL_PAGE : COMMUNITY_INDEX_URL,
        official_page: OFFICIAL_PAGE,
        fallback_source: COMMUNITY_INDEX_URL,
        used_fallback: official_links.empty? && community_links.any?,
        versions: stable,
        preview_versions: preview,
        latest: stable.first,
        message: if stable.any?
                   "Versões Bedrock BDS carregadas."
                 elsif preview.any?
                   "Apenas versões preview encontradas."
                 else
                   "Nenhuma versão BDS Linux encontrada automaticamente."
                 end
      }
    rescue StandardError => e
      {
        ok: false,
        source: OFFICIAL_PAGE,
        fallback_source: COMMUNITY_INDEX_URL,
        versions: installed_versions_as_links,
        preview_versions: [],
        latest: nil,
        error: "#{e.class}: #{e.message}"
      }
    end

    def installed
      FileUtils.mkdir_p(@servers_dir)

      servers = Dir.children(@servers_dir).filter_map do |entry|
        next if entry.start_with?(".")

        dir = File.join(@servers_dir, entry)
        executable = File.join(dir, "bedrock_server")
        meta_file = File.join(dir, "rubymc-bds.json")

        next unless File.directory?(dir)
        next unless File.exist?(executable)

        meta = read_json(meta_file) || {}
        pid_file = File.join(dir, "rubymc-bds.pid")
        pid = read_pid(pid_file)
        running = pid && process_alive?(pid)

        unless running
          FileUtils.rm_f(pid_file) if pid
          pid = nil
        end

        {
          id: entry,
          version: meta["version"] || entry,
          channel: meta["channel"] || "stable",
          platform: "linux",
          path: dir,
          executable: executable,
          pid: pid,
          running: running,
          installed_at: meta["installed_at"],
          source_url: meta["source_url"]
        }
      end

      { ok: true, servers: servers.sort_by { |item| version_sort_key(item[:version]) }.reverse }
    end

    def download(version: nil, url: nil, channel: "stable", force: false)
      selected = resolve_download(version: version, url: url, channel: channel)

      version = selected[:version].to_s.strip
      url = selected[:url].to_s.strip
      channel = selected[:channel] || channel || "stable"

      raise "Não foi possível resolver a versão Bedrock para download." if version.empty?
      raise "URL de download vazia." if url.empty?

      target_dir = File.join(@servers_dir, safe_name(version))
      executable = File.join(target_dir, "bedrock_server")

      if File.exist?(executable) && !force
        return {
          ok: true,
          already_installed: true,
          version: version,
          path: target_dir,
          message: "Bedrock BDS #{version} já está instalado."
        }
      end

      FileUtils.rm_rf(target_dir) if force
      FileUtils.mkdir_p(target_dir)

      zip_path = File.join(@cache_dir, "bedrock-server-#{safe_name(version)}-#{SecureRandom.hex(4)}.zip")

      download_zip_with_fallbacks(url, zip_path, version: version)
      verify_zip!(zip_path)
      unzip(zip_path, target_dir)
      FileUtils.rm_f(zip_path)

      raise "O arquivo bedrock_server não foi encontrado após extrair o ZIP." unless File.exist?(executable)

      FileUtils.chmod("+x", executable)
      props = ensure_server_properties(target_dir)

      meta = {
        version: version,
        channel: channel,
        platform: "linux",
        source_url: url,
        installed_at: Time.now.utc.iso8601,
        server_port: props[:port]
      }

      File.write(File.join(target_dir, "rubymc-bds.json"), JSON.pretty_generate(meta))

      {
        ok: true,
        version: version,
        channel: channel,
        path: target_dir,
        executable: executable,
        message: "Bedrock BDS #{version} baixado e instalado com sucesso."
      }
    rescue StandardError => e
      FileUtils.rm_f(zip_path) if defined?(zip_path) && zip_path
      { ok: false, error: "#{e.class}: #{e.message}", version: version, url: url }
    end

    def remove(version:)
      data = installed
      server = data[:servers].find { |item| item[:version].to_s == version.to_s || item[:id].to_s == version.to_s }
      raise "Versão Bedrock #{version} não encontrada." unless server

      stop(version: version)

      dir = server[:path].to_s
      raise "Diretório inválido para remoção." if dir.empty?
      raise "Diretório fora da pasta de servidores: #{dir}" unless File.expand_path(dir).start_with?(File.expand_path(@servers_dir))

      FileUtils.rm_rf(dir)

      { ok: true, version: version, message: "Bedrock BDS #{version} removido com sucesso." }
    rescue StandardError => e
      { ok: false, error: "#{e.class}: #{e.message}", version: version }
    end

    def start(version:, port: nil)
      data = installed
      server = data[:servers].find { |item| item[:version].to_s == version.to_s || item[:id].to_s == version.to_s }
      raise "Versão Bedrock #{version} não instalada." unless server

      if server[:running]
        return { ok: true, running: true, pid: server[:pid], message: "Bedrock #{server[:version]} já está rodando." }
      end

      dir = server[:path]
      props = ensure_server_properties(dir)
      selected_port = (port || props[:port] || 19_132).to_i

      executable = server[:executable]
      log_file = File.join(dir, "rubymc-bds.log")
      pid_file = File.join(dir, "rubymc-bds.pid")
      env = { "LD_LIBRARY_PATH" => "." }

      pid = spawn(env, executable, chdir: dir, out: [log_file, "a"], err: [log_file, "a"], pgroup: true)
      Process.detach(pid)
      File.write(pid_file, pid.to_s)

      wait = wait_for_udp_port(port: selected_port, timeout: 22)

      {
        ok: true,
        pid: pid,
        version: server[:version],
        port: selected_port,
        udp_ready: wait[:ok],
        message: wait[:ok] ? "Bedrock #{server[:version]} iniciado na porta UDP #{selected_port}." : "Bedrock iniciou processo, mas a porta UDP #{selected_port} ainda não respondeu.",
        log_tail: tail(log_file, 40)
      }
    rescue StandardError => e
      { ok: false, error: "#{e.class}: #{e.message}" }
    end

    def stop(version: nil)
      targets = installed[:servers]
      targets = targets.select { |item| item[:version].to_s == version.to_s || item[:id].to_s == version.to_s } if version && !version.to_s.strip.empty?

      stopped = []

      targets.each do |server|
        next unless server[:pid]

        begin
          Process.kill("TERM", -server[:pid])
        rescue Errno::ESRCH, Errno::EPERM
          begin
            Process.kill("TERM", server[:pid])
          rescue Errno::ESRCH, Errno::EPERM
          end
        end

        FileUtils.rm_f(File.join(server[:path], "rubymc-bds.pid"))
        stopped << server[:version]
      end

      { ok: true, stopped: stopped, message: stopped.empty? ? "Nenhum servidor Bedrock em execução." : "Servidor(es) Bedrock parado(s): #{stopped.join(', ')}" }
    rescue StandardError => e
      { ok: false, error: "#{e.class}: #{e.message}" }
    end

    private

    def fetch_official_download_links
      response = HTTParty.get(OFFICIAL_PAGE, timeout: 25, headers: request_headers)
      raise "HTTP #{response.code} ao acessar #{OFFICIAL_PAGE}" unless response.success?

      extract_download_links_from_text(response.body.to_s, source: OFFICIAL_PAGE)
    rescue StandardError
      []
    end

    def fetch_community_download_links
      response = HTTParty.get(COMMUNITY_INDEX_URL, timeout: 25, headers: request_headers.merge("Accept" => "application/json"))
      raise "HTTP #{response.code} ao acessar #{COMMUNITY_INDEX_URL}" unless response.success?

      body = response.body.to_s
      links = extract_download_links_from_text(body, source: COMMUNITY_INDEX_URL)

      begin
        json = JSON.parse(body)
        links.concat(collect_download_links_from_json(json))
      rescue JSON::ParserError
      end

      dedupe_links(links)
    rescue StandardError
      []
    end

    def extract_download_links_from_text(text, source:)
      html = normalize_html(text)

      urls = []
      urls.concat(html.scan(%r{https?://[^"'\s<>\\]+bedrock-server-[^"'\s<>\\]+?\.zip}i).flatten)
      urls.concat(html.scan(/href=["']([^"']+bedrock-server-[^"']+?\.zip)["']/i).flatten)
      urls.concat(html.scan(%r{(\/bedrockdedicatedserver\/[^"'\s<>\\]+bedrock-server-[^"'\s<>\\]+?\.zip)}i).flatten)
      urls.concat(html.scan(%r{(\/bin-linux\/bedrock-server-[^"'\s<>\\]+?\.zip)}i).flatten)
      urls.concat(html.scan(%r{(\/bin-win\/bedrock-server-[^"'\s<>\\]+?\.zip)}i).flatten)

      urls.map { |url| url_to_item(url, source: source) }.compact
    end

    def collect_download_links_from_json(obj, links = [])
      case obj
      when Hash
        url_values = obj.values.select { |v| v.is_a?(String) && v.match?(/bedrock-server-.*?\.zip/i) }
        url_values.each { |url| links << url_to_item(url, source: COMMUNITY_INDEX_URL, object: obj) }

        obj.each_value { |value| collect_download_links_from_json(value, links) }
      when Array
        obj.each { |value| collect_download_links_from_json(value, links) }
      when String
        links << url_to_item(obj, source: COMMUNITY_INDEX_URL) if obj.match?(/bedrock-server-.*?\.zip/i)
      end

      links.compact
    end

    def url_to_item(url, source:, object: nil)
      url = absolute_url(CGI.unescapeHTML(CGI.unescape(url.to_s.strip)))
      return nil unless url =~ /bedrock-server-([0-9]+(?:\.[0-9]+){2,3})\.zip/i

      version = Regexp.last_match(1)
      lower = url.downcase

      platform =
        if lower.include?("bin-linux") || lower.include?("linux")
          "linux"
        elsif lower.include?("bin-win") || lower.include?("windows")
          "windows"
        else
          object_platform(object) || "unknown"
        end

      channel =
        if lower.include?("preview") || object_channel(object) == "preview"
          "preview"
        else
          "stable"
        end

      {
        version: version,
        channel: channel,
        platform: platform,
        url: url,
        source: source
      }
    end

    def object_platform(object)
      return nil unless object.is_a?(Hash)

      text = object.values_at("platform", :platform, "os", :os, "name", :name).compact.join(" ").downcase
      return "linux" if text.include?("linux") || text.include?("ubuntu")
      return "windows" if text.include?("windows") || text.include?("win")

      nil
    end

    def object_channel(object)
      return nil unless object.is_a?(Hash)

      text = object.values_at("channel", :channel, "type", :type, "name", :name).compact.join(" ").downcase
      text.include?("preview") ? "preview" : "stable"
    end

    def dedupe_links(links)
      links
        .compact
        .select { |item| item[:version].to_s.match?(/\A[0-9]+(?:\.[0-9]+){2,3}\z/) }
        .uniq { |item| [item[:version], item[:platform], item[:channel]] }
        .sort_by { |item| version_sort_key(item[:version]) }
        .reverse
    end

    def installed_versions_as_links
      installed[:servers].map do |server|
        {
          version: server[:version],
          channel: server[:channel] || "stable",
          platform: "linux",
          url: server[:source_url].to_s,
          installed: true,
          source: "installed"
        }
      end
    rescue StandardError
      []
    end

    def resolve_download(version:, url:, channel:)
      if url && !url.to_s.strip.empty?
        return { version: extract_version_from_url(url) || version, channel: channel, url: url }
      end

      available_data = available
      all = Array(available_data[:versions]) + Array(available_data[:preview_versions])

      if version && !version.to_s.strip.empty?
        found = all.find { |item| item[:version].to_s == version.to_s && item[:platform].to_s == "linux" }
        return found if found && found[:url].to_s.strip != ""

        return { version: version, channel: channel || "stable", platform: "linux", url: direct_linux_url(version) }
      end

      latest = available_data[:latest]
      return latest if latest && latest[:url].to_s.strip != ""

      raise "Não foi possível encontrar o último BDS Linux na página oficial."
    end

    def direct_linux_url(version)
      "https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-#{version}.zip"
    end

    def candidate_urls_for_version(version, preferred_url)
      urls = []
      urls << preferred_url if preferred_url && !preferred_url.to_s.strip.empty?
      urls << "https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-#{version}.zip"
      urls << "https://minecraft.azureedge.net/bin-linux/bedrock-server-#{version}.zip"
      urls << "https://www.minecraft.net/bedrockdedicatedserver/bin-linux-preview/bedrock-server-#{version}.zip"
      urls << "https://minecraft.azureedge.net/bin-linux-preview/bedrock-server-#{version}.zip"
      urls.uniq
    end

    def download_zip_with_fallbacks(url, path, version:)
      errors = []

      candidate_urls_for_version(version, url).each do |candidate|
        begin
          download_zip(candidate, path)
          return true
        rescue StandardError => e
          errors << "#{candidate}: #{e.message}"
          FileUtils.rm_f(path)
        end
      end

      raise "Falha ao baixar BDS #{version}. Tentativas: #{errors.join(' | ')}"
    end

    def download_zip(url, path)
      FileUtils.mkdir_p(File.dirname(path))

      response = nil
      File.open(path, "wb") do |file|
        response = HTTParty.get(
          url,
          timeout: 240,
          stream_body: true,
          headers: request_headers.merge("Referer" => OFFICIAL_PAGE)
        ) do |fragment|
          file.write(fragment)
        end
      end

      unless response&.success?
        FileUtils.rm_f(path)
        raise "HTTP #{response&.code || 'desconhecido'} ao baixar #{url}"
      end

      if File.size(path) < 10_000
        content = File.read(path, 500) rescue ""
        FileUtils.rm_f(path)
        raise "Download inválido ou muito pequeno. Conteúdo inicial: #{content.inspect}"
      end

      true
    end

    def verify_zip!(path)
      File.open(path, "rb") do |file|
        magic = file.read(2)
        raise "Arquivo baixado não parece ser ZIP." unless magic == "PK"
      end
    end

    def unzip(zip_path, target_dir)
      stdout, stderr, status = Open3.capture3("unzip", "-oq", zip_path, "-d", target_dir)
      return if status.success?

      raise "Falha ao extrair ZIP: #{stderr.empty? ? stdout : stderr}"
    rescue Errno::ENOENT
      raise "Comando 'unzip' não encontrado. Instale com: sudo apt install unzip"
    end

    def ensure_server_properties(dir)
      cfg = bedrock_settings

      port = integer_setting(cfg, "port", 19_132)
      portv6 = integer_setting(cfg, "portv6", 19_133)

      properties = {
        "server-name" => string_setting(cfg, "motd", "RubyMC Bedrock"),
        "gamemode" => string_setting(cfg, "gamemode", "survival"),
        "difficulty" => string_setting(cfg, "difficulty", "easy"),
        "allow-cheats" => bool_setting(cfg, "allow_cheats", false),
        "max-players" => integer_setting(cfg, "max_players", 10),
        "online-mode" => bool_setting(cfg, "online_mode", true),
        "server-port" => port,
        "server-portv6" => portv6,
        "view-distance" => integer_setting(cfg, "view_distance", 32),
        "tick-distance" => integer_setting(cfg, "tick_distance", 4)
      }

      path = File.join(dir, "server.properties")
      File.write(path, properties.map { |key, value| "#{key}=#{value}" }.join("\n") + "\n")

      { path: path, port: port, portv6: portv6, properties: properties }
    end

    def settings
      return @__settings if defined?(@__settings)

      @__settings =
        if File.file?(SETTINGS_PATH)
          YAML.safe_load(File.read(SETTINGS_PATH), permitted_classes: [Symbol], aliases: true) || {}
        else
          {}
        end
    rescue StandardError
      @__settings = {}
    end

    def bedrock_settings
      data = settings
      servers = data["servers"] || data[:servers] || {}
      servers["bedrock"] || servers[:bedrock] || {}
    end

    def string_setting(cfg, key, default)
      value = cfg[key] || cfg[key.to_sym]
      value.nil? || value.to_s.strip.empty? ? default : value.to_s
    end

    def integer_setting(cfg, key, default)
      value = cfg[key] || cfg[key.to_sym]
      value.nil? || value.to_s.strip.empty? ? default : value.to_i
    end

    def bool_setting(cfg, key, default)
      value = cfg[key] || cfg[key.to_sym]
      return default if value.nil?
      return value if value == true || value == false

      %w[true yes sim 1 on].include?(value.to_s.downcase)
    end

    def wait_for_udp_port(port:, timeout:)
      deadline = Time.now + timeout

      loop do
        listening = system("sh", "-lc", "ss -lun | grep -q ':#{port} '")
        return { ok: true } if listening
        return { ok: false } if Time.now > deadline

        sleep 1
      end
    end

    def read_json(path)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def read_pid(path)
      return nil unless File.exist?(path)

      pid = File.read(path).to_i
      pid.positive? ? pid : nil
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def tail(path, lines)
      return "" unless File.exist?(path)

      File.readlines(path).last(lines).join
    rescue StandardError
      ""
    end

    def request_headers
      {
        "User-Agent" => USER_AGENT,
        "Accept" => "text/html,application/xhtml+xml,application/xml,application/json;q=0.9,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.9,pt-BR;q=0.8",
        "Connection" => "close"
      }
    end

    def normalize_html(html)
      html
        .gsub("\\u002F", "/")
        .gsub("\\/", "/")
        .gsub("%2F", "/")
        .gsub("%3A", ":")
        .gsub("&amp;", "&")
    end

    def absolute_url(url)
      url = url.to_s.strip
      return url if url.start_with?("http://", "https://")

      if url.start_with?("/bin-linux", "/bin-win")
        return URI.join("https://minecraft.azureedge.net", url).to_s
      end

      URI.join("https://www.minecraft.net", url).to_s
    end

    def extract_version_from_url(url)
      url.to_s[/bedrock-server-([0-9]+(?:\.[0-9]+){2,3})\.zip/i, 1]
    end

    def safe_name(value)
      value.to_s.gsub(/[^0-9A-Za-z_.-]/, "_")
    end

    def version_sort_key(version)
      version.to_s.split(".").map(&:to_i)
    end
  end
end
