# frozen_string_literal: true

require "cgi"
require "fileutils"
require "httparty"
require "json"
require "open3"
require "securerandom"
require "time"
require "uri"

module RubyMC
  class BedrockServerDownloader
    OFFICIAL_PAGE = "https://www.minecraft.net/en-us/download/server/bedrock"
    USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) RubyMC-Launcher/1.0"

    attr_reader :project_root, :servers_dir, :cache_dir

    def initialize(project_root: nil, servers_dir: nil)
      @project_root = project_root || ENV["RUBYMC_PROJECT_ROOT"] || File.expand_path("../..", __dir__)
      @servers_dir = servers_dir || File.join(@project_root, "servers", "bedrock")
      @cache_dir = File.join(@project_root, "tmp", "bedrock_downloads")
      FileUtils.mkdir_p(@servers_dir)
      FileUtils.mkdir_p(@cache_dir)
    end

    def available
      links = fetch_official_download_links
      stable = links.select { |item| item[:platform] == "linux" && item[:channel] == "stable" }
      preview = links.select { |item| item[:platform] == "linux" && item[:channel] == "preview" }

      {
        ok: true,
        source: OFFICIAL_PAGE,
        versions: stable,
        preview_versions: preview,
        latest: stable.first,
        message: stable.empty? ? "Nenhum link Linux encontrado na página oficial." : "Versões Bedrock BDS carregadas."
      }
    rescue StandardError => e
      {
        ok: false,
        source: OFFICIAL_PAGE,
        versions: [],
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

      { ok: true, servers: servers.sort_by { |item| item[:version].to_s }.reverse }
    end

    def download(version: nil, url: nil, channel: "stable", force: false)
      selected = resolve_download(version: version, url: url, channel: channel)
      version = selected[:version]
      url = selected[:url]
      channel = selected[:channel] || channel || "stable"

      raise "Não foi possível resolver a versão Bedrock para download." if version.to_s.strip.empty?
      raise "URL de download vazia." if url.to_s.strip.empty?

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

      FileUtils.mkdir_p(target_dir)
      zip_path = File.join(@cache_dir, "bedrock-server-#{safe_name(version)}-#{SecureRandom.hex(4)}.zip")

      download_zip(url, zip_path)
      verify_zip!(zip_path)

      FileUtils.rm_rf(target_dir) if force
      FileUtils.mkdir_p(target_dir)
      unzip(zip_path, target_dir)
      FileUtils.rm_f(zip_path)

      raise "O arquivo bedrock_server não foi encontrado após extrair o ZIP." unless File.exist?(executable)

      FileUtils.chmod("+x", executable)
      ensure_server_properties(target_dir)

      meta = {
        version: version,
        channel: channel,
        platform: "linux",
        source_url: url,
        installed_at: Time.now.utc.iso8601
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
      { ok: false, error: "#{e.class}: #{e.message}", version: version, url: url }
    end

    def start(version:, port: 19_132)
      data = installed
      server = data[:servers].find { |item| item[:version].to_s == version.to_s || item[:id].to_s == version.to_s }
      raise "Versão Bedrock #{version} não instalada." unless server

      if server[:running]
        return { ok: true, running: true, pid: server[:pid], message: "Bedrock #{server[:version]} já está rodando." }
      end

      dir = server[:path]
      executable = server[:executable]
      log_file = File.join(dir, "rubymc-bds.log")
      pid_file = File.join(dir, "rubymc-bds.pid")
      env = { "LD_LIBRARY_PATH" => "." }

      pid = spawn(env, executable, chdir: dir, out: [log_file, "a"], err: [log_file, "a"], pgroup: true)
      Process.detach(pid)
      File.write(pid_file, pid.to_s)

      wait = wait_for_udp_port(port: port, timeout: 18)

      {
        ok: true,
        pid: pid,
        version: server[:version],
        udp_ready: wait[:ok],
        message: wait[:ok] ? "Bedrock #{server[:version]} iniciado na porta UDP #{port}." : "Bedrock iniciou processo, mas a porta UDP #{port} ainda não respondeu.",
        log_tail: tail(log_file, 40)
      }
    rescue StandardError => e
      { ok: false, error: "#{e.class}: #{e.message}" }
    end

    def stop(version: nil)
      targets = installed[:servers]
      targets = targets.select { |item| item[:version].to_s == version.to_s || item[:id].to_s == version.to_s } if version

      stopped = []

      targets.each do |server|
        next unless server[:pid]
        begin
          Process.kill("TERM", -server[:pid])
        rescue Errno::ESRCH
          begin
            Process.kill("TERM", server[:pid])
          rescue Errno::ESRCH
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
      response = HTTParty.get(OFFICIAL_PAGE, timeout: 20, headers: request_headers)
      raise "HTTP #{response.code} ao acessar #{OFFICIAL_PAGE}" unless response.success?

      html = normalize_html(response.body.to_s)

      urls = []
      urls.concat(html.scan(%r{https?://[^"'\s<>]+bedrock-server-[^"'\s<>]+?\.zip}i).flatten)
      urls.concat(html.scan(/href=["']([^"']+bedrock-server-[^"']+?\.zip)["']/i).flatten)
      urls.concat(html.scan(%r{(\/bedrockdedicatedserver\/[^"'\s<>]+bedrock-server-[^"'\s<>]+?\.zip)}i).flatten)
      urls = urls.map { |u| absolute_url(CGI.unescapeHTML(u)) }.uniq

      urls.filter_map do |download_url|
        next unless download_url =~ /bedrock-server-([0-9]+(?:\.[0-9]+){2,3})\.zip/i
        version = Regexp.last_match(1)
        platform = if download_url.include?("bin-linux")
                     "linux"
                   elsif download_url.include?("bin-win")
                     "windows"
                   else
                     "unknown"
                   end
        channel = download_url.downcase.include?("preview") ? "preview" : "stable"
        { version: version, channel: channel, platform: platform, url: download_url }
      end.sort_by { |item| version_sort_key(item[:version]) }.reverse
    end

    def resolve_download(version:, url:, channel:)
      if url && !url.to_s.strip.empty?
        return { version: extract_version_from_url(url) || version, channel: channel, url: url }
      end

      available_data = available

      if version && !version.to_s.strip.empty?
        from_page = (available_data[:versions] + available_data[:preview_versions]).find do |item|
          item[:version].to_s == version.to_s && item[:platform] == "linux"
        end
        return from_page if from_page

        return { version: version, channel: channel || "stable", platform: "linux", url: direct_linux_url(version) }
      end

      latest = available_data[:latest]
      return latest if latest

      raise available_data[:error] || "Não foi possível encontrar o último BDS Linux na página oficial."
    end

    def direct_linux_url(version)
      "https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-#{version}.zip"
    end

    def download_zip(url, path)
      FileUtils.mkdir_p(File.dirname(path))
      response = nil
      File.open(path, "wb") do |file|
        response = HTTParty.get(url, timeout: 180, stream_body: true, headers: request_headers.merge("Referer" => OFFICIAL_PAGE)) do |fragment|
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
      path = File.join(dir, "server.properties")
      return if File.exist?(path)

      File.write(path, [
        "server-name=RubyMC Bedrock",
        "gamemode=survival",
        "difficulty=easy",
        "allow-cheats=false",
        "max-players=10",
        "online-mode=true",
        "server-port=19132",
        "server-portv6=19133",
        "view-distance=32",
        "tick-distance=4",
        ""
      ].join("\n"))
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
        "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.9,pt-BR;q=0.8",
        "Connection" => "close"
      }
    end

    def normalize_html(html)
      html.gsub("\\u002F", "/").gsub("\\/", "/").gsub("&amp;", "&")
    end

    def absolute_url(url)
      return url if url.start_with?("http://", "https://")
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
