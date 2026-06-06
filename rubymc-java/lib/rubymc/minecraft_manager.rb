# frozen_string_literal: true

require "httparty"
require "json"
require "fileutils"
require "open3"
require "digest"
require "zip"

# =============================================================================
# MinecraftManager — Download, instalação e launch do Minecraft Java Edition
# =============================================================================
class MinecraftManager
  VERSION_MANIFEST_URL = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
  RESOURCES_URL        = "https://resources.download.minecraft.net"
  FABRIC_META_URL      = "https://meta.fabricmc.net/v2/versions"
  QUILT_META_URL       = "https://meta.quiltmc.org/v3/versions"
  QUILT_MAVEN_URL      = "https://maven.quiltmc.org/repository/release/org/quiltmc"
  NEOFORGE_API_URL     = "https://api.neoforged.net/api/v1/versions/minecraft"
  NEOFORGE_MAVEN_URL   = "https://maven.neoforged.net/releases/net/neoforged/neoforge"

  MC_DIR = File.join(Dir.home, ".minecraft")

  def initialize(mc_dir: MC_DIR)
    @mc_dir        = mc_dir
    @versions_dir  = File.join(@mc_dir, "versions")
    @libraries_dir = File.join(@mc_dir, "libraries")
    @assets_dir    = File.join(@mc_dir, "assets")
    @natives_dir   = File.join(@mc_dir, "natives")
    FileUtils.mkdir_p([@versions_dir, @libraries_dir, @assets_dir, @natives_dir])
  end

  def fetch_version_manifest
    res = HTTParty.get(VERSION_MANIFEST_URL, timeout: 10)
    raise "Falha ao buscar versões: #{res.code}" unless res.success?
    JSON.parse(res.body)
  end

  def list_versions(tipo: :release, limit: 20)
    manifest = fetch_version_manifest
    versions = manifest["versions"]
    versions = versions.select { |v| v["type"] == tipo.to_s } unless tipo == :all
    versions.first(limit).map { |v| { id: v["id"], type: v["type"], url: v["url"] } }
  end

  def list_loader_versions(loader)
    case loader.to_sym
    when :fabric
      data = fetch_json("#{FABRIC_META_URL}/game")
      (data || []).map { |v| { id: v["version"], type: v["stable"] ? "release" : "snapshot" } }
    when :quilt
      data = fetch_json("#{QUILT_META_URL}/game")
      (data || []).map { |v| { id: v["version"], type: v["stable"] ? "release" : "snapshot" } }
    when :neoforge
      data = fetch_json(NEOFORGE_API_URL)
      (data || []).map { |v| { id: v["version"], type: "release" } }
    else
      []
    end
  end

  def latest_release
    fetch_version_manifest.dig("latest", "release")
  rescue
    nil
  end

  def install_version(version_id, &cb)
    version_dir = File.join(@versions_dir, version_id)
    FileUtils.mkdir_p(version_dir)
    json_path = File.join(version_dir, "#{version_id}.json")

    unless File.exist?(json_path)
      cb&.call("Baixando metadados da versão #{version_id}...")
      manifest = fetch_version_manifest
      entry = manifest["versions"].find { |v| v["id"] == version_id }
      raise "Versão '#{version_id}' não encontrada." unless entry
      meta_res = HTTParty.get(entry["url"], timeout: 15)
      raise "Falha: #{meta_res.code}" unless meta_res.success?
      File.write(json_path, meta_res.body)
    end

    meta = JSON.parse(File.read(json_path))
    download_client(version_id, meta, version_dir, &cb)
    download_libraries(meta, &cb)
    download_natives(meta, version_id, &cb)
    download_assets(meta, &cb)
    meta
  end

  def install_loader(version_id, loader, &cb)
    loader = loader.to_sym

    # 1. Always install the base vanilla version first
    cb&.call("Preparando Minecraft #{version_id}...")
    install_version(version_id, &cb)

    case loader
    when :fabric
      install_fabric_client(version_id, &cb)
    when :quilt
      install_quilt_client(version_id, &cb)
    when :neoforge
      install_neoforge_client(version_id, &cb)
    else
      raise "Loader desconhecido: #{loader}"
    end
  end

  def version_installed?(version_id)
    dir = File.join(@versions_dir, version_id)
    File.exist?(File.join(dir, "#{version_id}.jar")) || File.exist?(File.join(dir, "#{version_id}.json"))
  end

  # Lista versões já instaladas localmente em ~/.minecraft/versions
  def list_local_versions
    return [] unless Dir.exist?(@versions_dir)
    Dir.children(@versions_dir).select do |entry|
      dir = File.join(@versions_dir, entry)
      File.directory?(dir) && (File.exist?(File.join(dir, "#{entry}.jar")) || File.exist?(File.join(dir, "#{entry}.json")))
    end.sort.reverse.map do |entry|
      json_path = File.join(@versions_dir, entry, "#{entry}.json")
      info = { id: entry }
      if File.exist?(json_path)
        meta = JSON.parse(File.read(json_path)) rescue {}
        info[:type] = meta["type"] || (meta["inheritsFrom"] ? "loader" : "unknown")
        info[:inheritsFrom] = meta["inheritsFrom"] if meta["inheritsFrom"]
        if meta["mainClass"]
          info[:loader] = "fabric" if meta["mainClass"].include?("fabric")
          info[:loader] = "quilt" if meta["mainClass"].include?("quilt")
          info[:loader] = "forge" if meta["mainClass"].include?("forge")
        end
        jar_path = File.join(@versions_dir, entry, "#{entry}.jar")
        info[:size_kb] = (File.size(jar_path) / 1024) rescue 0
      end
      info
    end
  end

  # Garante que a versão e suas dependências estejam instaladas,
  # baixando o necessário com progresso no terminal.
  def ensure_version_dependencies(version_id)
    # Instalar Fabric/Quilt automaticamente se for uma versão fabric-loader-*
    if version_id =~ /\A(fabric|quilt)-loader-(\d+\.\d+\.\d+)-(.*)\z/
      loader_type = $1
      loader_ver = $2
      base_version = $3
      loader_json = File.join(@versions_dir, version_id, "#{version_id}.json")
      unless File.exist?(loader_json)
        puts "  #{loader_type.capitalize} #{loader_ver} para #{base_version} não instalado. Instalando..."
        if loader_type == 'fabric'
          install_fabric_client(base_version, loader_version: loader_ver) { |msg| print "\r  #{msg}#{" " * 20}" }
        else
          install_quilt_client(base_version, loader_version: loader_ver) { |msg| print "\r  #{msg}#{" " * 20}" }
        end
        puts "\n  Instalação #{loader_type.capitalize} concluída."
      end
    end

    json_path = File.join(@versions_dir, version_id, "#{version_id}.json")
    return unless File.exist?(json_path)

    meta = JSON.parse(File.read(json_path))

    # If inheritsFrom, ensure base version is installed
    if meta["inheritsFrom"]
      base_id = meta["inheritsFrom"]
      unless version_installed?(base_id)
        puts "  Versão base #{base_id} necessária. Instalando..."
        install_version(base_id) { |msg| print "\r  #{msg}#{" " * 20}" }
        puts "\n  Download concluído."
      end
    end

    # Download any missing libraries (only those with download URLs)
    unless version_installed?(version_id)
      puts "  Baixando Minecraft #{version_id} e dependências..."
      install_version(version_id) { |msg| print "\r  #{msg}#{" " * 20}" }
      puts "\n  Download concluído."
    end
  end

  # Fachada chamada pelo LauncherCLI — converte ram_gb → ram_mb e delega ao launch
  def execute_launch(version:, username:, uuid:, token:, ram_gb: 4, java_path: nil, server_address: nil)
    launch(
      version_id:      version,
      username:        username,
      uuid:            uuid,
      mc_access_token: token,
      java_path:       java_path,
      ram_mb:          (ram_gb * 1024).to_i,
      server_address:  server_address
    )
  end

  def launch(version_id:, username:, uuid:, mc_access_token:, java_path: nil, ram_mb: 2048, server_address: nil, game_directory: nil, loader: nil, loader_version: nil)
    json_path = File.join(@versions_dir, version_id, "#{version_id}.json")
    raise "Versão #{version_id} não instalada." unless File.exist?(json_path)

    meta  = JSON.parse(File.read(json_path))
    java  = java_path.to_s.strip.empty? ? detect_java : java_path
    raise "Java não encontrado. Instale Java 17+." unless java

    classpath = build_classpath(version_id, meta)
    
    # Usar game_directory customizado se fornecido (para modpacks)
    effective_game_dir = game_directory || @mc_dir
    
    args      = build_launch_args(
      version_meta: meta, version_id: version_id,
      username: username, uuid: uuid, mc_access_token: mc_access_token,
      classpath: classpath, ram_mb: ram_mb,
      server_address: server_address,
      game_directory: effective_game_dir
    )

    log_path = File.join(@mc_dir, "logs", "launch-#{version_id}-#{Time.now.to_i}.log")
    FileUtils.mkdir_p(File.dirname(log_path))
    log_file = File.open(log_path, 'w')
    log_file.sync = true
    pid = spawn(*([java] + args), chdir: effective_game_dir, out: log_file, err: log_file)
    log_file.close
    Process.detach(pid)
    pid
  end

  def detect_java
    # 1. JAVA_HOME
    if ENV["JAVA_HOME"]
      candidate = File.join(ENV["JAVA_HOME"], "bin", "java")
      return candidate if File.executable?(candidate)
    end
    # 2. which java
    path = `which java 2>/dev/null`.strip
    return path unless path.empty?
    # 3. fallback
    _, _, status = Open3.capture3("java", "-version")
    status.success? ? "java" : nil
  rescue
    nil
  end

  attr_reader :mc_dir

  def fetch_json(url)
    res = HTTParty.get(url, timeout: 15)
    raise "HTTP #{res.code}: #{url}" unless res.success?
    JSON.parse(res.body)
  end

  def install_fabric_client(version_id, loader_version: nil, &cb)
    cb&.call("Buscando versão do Fabric loader...")
    loader_data = fetch_json("#{FABRIC_META_URL}/loader/#{version_id}")
    raise "Fabric não suporta '#{version_id}'." if loader_data.empty?

    if loader_version
      match = loader_data.find { |entry| entry["loader"]["version"] == loader_version }
      if match
        loader_ver = loader_version
      else
        cb&.call("Versão #{loader_version} não encontrada, usando a mais recente.")
        loader_ver = loader_data.first["loader"]["version"]
      end
    else
      loader_ver = loader_data.first["loader"]["version"]
    end

    installer_data = fetch_json("#{FABRIC_META_URL}/installer")
    installer_ver = installer_data.first["version"]
    installer_url = "https://maven.fabricmc.net/net/fabricmc/fabric-installer/#{installer_ver}/fabric-installer-#{installer_ver}.jar"

    tmp_dir = File.join(@mc_dir, "tmp")
    FileUtils.mkdir_p(tmp_dir)
    installer_path = File.join(tmp_dir, "fabric-installer.jar")

    cb&.call("Baixando Fabric installer...")
    download_file(installer_url, installer_path)

    java = detect_java
    args = [java, "-jar", installer_path, "client", "-dir", @mc_dir,
            "-mcversion", version_id, "-loader", loader_ver, "-downloadMinecraft"]

    cb&.call("Executando Fabric installer...")
    out, err, status = Open3.capture3(*args)
    FileUtils.rm_f(installer_path)
    loader_id = "fabric-loader-#{loader_ver}-#{version_id}"
    unless status.success?
      loader_json = File.join(@versions_dir, loader_id, "#{loader_id}.json")
      if File.exist?(loader_json)
        cb&.call("Fabric #{loader_id} instalado (com avisos).")
        return loader_id
      end
      detail = err.lines.last(5).map(&:strip).reject(&:empty?)
      detail = out.lines.last(5).map(&:strip).reject(&:empty?) if detail.empty?
      raise "Fabric installer falhou (#{status.exitstatus}): #{detail.last(3).join(' | ')}"
    end

    cb&.call("Fabric #{loader_id} instalado.")
    loader_id
  end

  def install_quilt_client(version_id, &cb)
    cb&.call("Buscando versão do Quilt loader...")
    loader_data = fetch_json("#{QUILT_META_URL}/loader/#{version_id}")
    raise "Quilt não suporta '#{version_id}'." if loader_data.empty?

    loader_ver = loader_data.first["loader"]["version"]

    installer_data = fetch_json("#{QUILT_META_URL}/installer")
    installer_ver = installer_data.first["version"]
    installer_url = "#{QUILT_MAVEN_URL}/quilt-installer/#{installer_ver}/quilt-installer-#{installer_ver}.jar"

    tmp_dir = File.join(@mc_dir, "tmp")
    FileUtils.mkdir_p(tmp_dir)
    installer_path = File.join(tmp_dir, "quilt-installer.jar")

    cb&.call("Baixando Quilt installer...")
    download_file(installer_url, installer_path)

    java = detect_java
    args = [java, "-jar", installer_path, "install", "client", version_id,
            "--loader=#{loader_ver}", "--download-minecraft", "--install-dir=#{@mc_dir}"]

    cb&.call("Executando Quilt installer...")
    out, err, status = Open3.capture3(*args)
    FileUtils.rm_f(installer_path)
    loader_id = "quilt-loader-#{loader_ver}-#{version_id}"
    unless status.success?
      loader_json = File.join(@versions_dir, loader_id, "#{loader_id}.json")
      if File.exist?(loader_json)
        cb&.call("Quilt #{loader_id} instalado (com avisos).")
        return loader_id
      end
      detail = err.lines.last(5).map(&:strip).reject(&:empty?)
      detail = out.lines.last(5).map(&:strip).reject(&:empty?) if detail.empty?
      raise "Quilt installer falhou (#{status.exitstatus}): #{detail.last(3).join(' | ')}"
    end

    cb&.call("Quilt #{loader_id} instalado.")
    loader_id
  end

  def install_neoforge_client(version_id, &cb)
    cb&.call("Buscando versão do NeoForge...")
    data = fetch_json(NEOFORGE_API_URL)
    entry = data.find { |v| v["version"] == version_id }
    raise "NeoForge não suporta '#{version_id}'." unless entry

    nf_ver = entry["recommended"] || entry["latest"]
    raise "Nenhuma versão NeoForge para '#{version_id}'." unless nf_ver

    fullver = "#{version_id}-#{nf_ver}"
    loader_id = "neoforge-#{fullver}"

    # Check if already installed
    if File.exist?(File.join(@versions_dir, loader_id, "#{loader_id}.json"))
      cb&.call("NeoForge #{fullver} já instalado.")
      return loader_id
    end

    installer_url = "#{NEOFORGE_MAVEN_URL}/#{fullver}/neoforge-#{fullver}-installer.jar"

    tmp_dir = File.join(@mc_dir, "tmp")
    FileUtils.mkdir_p(tmp_dir)
    installer_path = File.join(tmp_dir, "neoforge-#{fullver}-installer.jar")

    cb&.call("Baixando NeoForge installer...")
    download_file(installer_url, installer_path)

    # Extract version.json from the installer (it's a ZIP/JAR)
    cb&.call("Extraindo metadados NeoForge...")
    version_json = nil
    client_jar_data = nil
    libraries = []

    Zip::File.open(installer_path) do |zip|
      # Find and extract version.json
      ve = zip.find { |e| e.name == "version.json" }
      if ve
        version_json = JSON.parse(ve.get_input_stream.read)
      else
        # Fallback: look for install_profile.json
        ve = zip.find { |e| e.name == "install_profile.json" }
        raise "version.json não encontrado no instalador NeoForge" unless ve
        profile = JSON.parse(ve.get_input_stream.read)
        version_json = profile["versionInfo"] || profile["version"]
        raise "versionInfo não encontrado no install_profile.json" unless version_json
      end

      # Try to extract the client jar from maven path
      client_path = "maven/net/neoforged/neoforge/#{fullver}/neoforge-#{fullver}-client.jar"
      ce = zip.find { |e| e.name == client_path }
      if ce
        client_jar_data = ce.get_input_stream.read
      end

      # Collect library paths from the maven directory structure
      zip.each do |e|
        libraries << e.name if e.name.start_with?("maven/") && e.name.end_with?(".jar")
      end
    end

    # Create the loader version directory
    loader_dir = File.join(@versions_dir, loader_id)
    FileUtils.mkdir_p(loader_dir)

    # Save version.json
    version_json["id"] = loader_id
    File.write(File.join(loader_dir, "#{loader_id}.json"), JSON.pretty_generate(version_json))

    # Save client jar (or symlink to vanilla)
    jar_path = File.join(loader_dir, "#{loader_id}.jar")
    if client_jar_data
      File.binwrite(jar_path, client_jar_data)
    else
      # Fallback: copy vanilla client jar
      vanilla_jar = File.join(@versions_dir, version_id, "#{version_id}.jar")
      FileUtils.cp(vanilla_jar, jar_path) if File.exist?(vanilla_jar)
    end

    # Install libraries from the extracted maven directory
    cb&.call("Instalando bibliotecas NeoForge (#{libraries.size})...")
    lib_count = 0
    libraries.each do |lib_path|
      dest = File.join(@libraries_dir, lib_path.sub(%r{^maven/}, ""))
      next if File.exist?(dest)

      Zip::File.open(installer_path) do |zip|
        entry = zip.find { |e| e.name == lib_path }
        next unless entry
        FileUtils.mkdir_p(File.dirname(dest))
        File.open(dest, "wb") { |f| f.write(entry.get_input_stream.read) }
        lib_count += 1
        cb&.call("Bibliotecas: #{lib_count}/#{libraries.size}") if (lib_count % 50).zero? || lib_count == 1
      end
    end

    FileUtils.rm_f(installer_path)
    cb&.call("NeoForge #{loader_id} instalado.")
    loader_id
  end

  private

  def download_client(version_id, meta, version_dir, &cb)
    jar = File.join(version_dir, "#{version_id}.jar")
    return if File.exist?(jar)
    url = meta.dig("downloads", "client", "url")
    raise "URL do client.jar não encontrada." unless url
    cb&.call("Baixando Minecraft #{version_id} (client.jar)...")
    download_file(url, jar)
  end

  def download_libraries(meta, &cb)
    libs = meta["libraries"] || []
    libs.each_with_index do |lib, i|
      next unless should_install_library?(lib)
      artifact = lib.dig("downloads", "artifact")
      next unless artifact
      path = File.join(@libraries_dir, artifact["path"])
      next if File.exist?(path)
      cb&.call("Biblioteca #{i + 1}/#{libs.size}: #{lib["name"].split(":").last}")
      FileUtils.mkdir_p(File.dirname(path))
      download_file(artifact["url"], path)
    end
  end

  def download_assets(meta, &cb)
    info = meta["assetIndex"]
    return unless info
    index_path = File.join(@assets_dir, "indexes", "#{info["id"]}.json")
    unless File.exist?(index_path)
      cb&.call("Baixando índice de assets...")
      FileUtils.mkdir_p(File.dirname(index_path))
      download_file(info["url"], index_path)
    end
    objs  = JSON.parse(File.read(index_path))["objects"] || {}
    total = objs.size
    count = 0
    failed = 0
    objs.each_value do |obj|
      hash   = obj["hash"]
      prefix = hash[0..1]
      dest   = File.join(@assets_dir, "objects", prefix, hash)
      next if File.exist?(dest)

      count += 1
      cb&.call("Assets: #{count}/#{total}") if count == 1 || (count % 100).zero?
      FileUtils.mkdir_p(File.dirname(dest))
      begin
        download_file("#{RESOURCES_URL}/#{prefix}/#{hash}", dest)
      rescue => e
        failed += 1
        cb&.call("Assets #{count}/#{total} — pulando (#{e.message})") if (count % 50).zero?
      end
    end
    cb&.call("Assets concluído (#{failed} falhas, #{count} baixados).") if count > 0
  end

  def download_natives(meta, version_id, &cb)
    natives_path = File.join(@natives_dir, version_id)
    FileUtils.mkdir_p(natives_path)

    (meta["libraries"] || []).each_with_index do |lib, i|
      next unless should_install_library?(lib)

      classifiers = lib.dig("downloads", "classifiers") || {}
      native = classifiers["natives-linux"]
      next unless native

      path = File.join(@libraries_dir, native["path"])
      unless File.exist?(path)
        cb&.call("Native #{i + 1}: #{File.basename(native["path"])}")
        FileUtils.mkdir_p(File.dirname(path))
        download_file(native["url"], path)
      end

      extract_native_archive(path, natives_path)
    end
  end

  def extract_native_archive(archive_path, natives_path)
    Zip::File.open(archive_path) do |zip|
      zip.each do |entry|
        name = entry.name.to_s
        next if name.end_with?("/")
        next if name.start_with?("META-INF/")
        next unless name.end_with?(".so")

        target = File.join(natives_path, File.basename(name))
        entry.extract(target) { true }
      end
    end
  rescue => e
    raise "Erro ao extrair natives de #{File.basename(archive_path)}: #{e.message}"
  end

  def build_classpath(version_id, meta)
    paths = []
    seen = Set.new
    resolve_classpath_chain(version_id, meta, paths, seen)
    paths.join(":")
  end

  def resolve_classpath_chain(version_id, meta, paths, seen)
    return unless meta
    return unless seen.add?(version_id)

    # Add libraries from this version
    (meta["libraries"] || []).each do |lib|
      next unless should_install_library?(lib)

      a = lib.dig("downloads", "artifact")
      if a && a["path"]
        path = File.join(@libraries_dir, a["path"])
        paths << path if File.exist?(path)
      elsif lib["name"]
        # Resolve Maven coordinate (group:artifact:version)
        maven_rel = maven_coord_to_path(lib["name"])
        full_path = File.join(@libraries_dir, maven_rel)
        paths << full_path if File.exist?(full_path)
      end
    end

    # Add this version's JAR if it exists
    jar = File.join(@versions_dir, version_id, "#{version_id}.jar")
    paths << jar if File.exist?(jar)

    # Follow inheritsFrom chain (Fabric/Quilt loaders point to base MC version)
    if meta["inheritsFrom"]
      base_id = meta["inheritsFrom"]
      base_json = File.join(@versions_dir, base_id, "#{base_id}.json")
      if File.exist?(base_json)
        base_meta = JSON.parse(File.read(base_json)) rescue nil
        resolve_classpath_chain(base_id, base_meta, paths, seen)
      end
    end
  end

  def maven_coord_to_path(coord)
    parts = coord.split(":")
    group = parts[0]
    artifact = parts[1]
    version = parts[2]
    classifier = parts[3]
    group_path = group.tr(".", "/")
    filename = classifier ? "#{artifact}-#{version}-#{classifier}.jar" : "#{artifact}-#{version}.jar"
    File.join(group_path, artifact, version, filename)
  end

  def build_launch_args(version_meta:, version_id:, username:, uuid:, mc_access_token:, classpath:, ram_mb:, server_address: nil, java_path_for_detection: "java", game_directory: nil)
    natives_path = File.join(@natives_dir, version_id)
    FileUtils.mkdir_p(natives_path)

    effective_game_dir = game_directory || @mc_dir

    r = {
      "${auth_player_name}"  => username,
      "${version_name}"      => version_id,
      "${game_directory}"    => effective_game_dir,
      "${assets_root}"       => @assets_dir,
      "${assets_index_name}" => version_meta.dig("assetIndex", "id") || version_id,
      "${auth_uuid}"         => uuid,
      "${auth_access_token}" => mc_access_token,
      "${user_type}"         => "msa",
      "${version_type}"      => version_meta["type"] || "release",
      "${natives_directory}" => natives_path,
      "${launcher_name}"     => "MinecraftRubyLauncher",
      "${launcher_version}"  => "1.0",
      "${classpath}"         => classpath
    }

    jvm = ["-Xmx#{ram_mb}M", "-Xms512M", "-XX:+UseG1GC",
           "-Djava.library.path=#{natives_path}", "-Dfile.encoding=UTF-8"]

    java_ver = java_major_version(java_path: java_path_for_detection)

      if version_meta.dig("arguments", "jvm")
        version_meta["arguments"]["jvm"].each do |a|
          next unless a.is_a?(String)
          arg = apply_r(a, r)
          # --sun-misc-unsafe-memory-access requer Java 23+; ignora em versões antigas
          next if arg.start_with?("--sun-misc-unsafe-memory-access") && java_ver < 23
          jvm << arg
        end
      end

      # Garantir que -cp esteja presente (Fabric/Quilt JSON omitem -cp nos arguments.jvm)
      unless jvm.any? { |a| a == '-cp' || a == '-classpath' }
        jvm << '-cp' << classpath
      end

      main = version_meta["mainClass"]
    raise "mainClass não encontrada." unless main

    game = []
    if version_meta.dig("arguments", "game")
      version_meta["arguments"]["game"].each { |a| game << apply_r(a, r) if a.is_a?(String) }
    elsif version_meta["minecraftArguments"]
      game = version_meta["minecraftArguments"].split.map { |a| apply_r(a, r) }
    end

    if server_address
      host, port = server_address.to_s.split(':')
      port ||= '25565'
      game << '--server' << host << '--port' << port
    end

    jvm + [main] + game
  end

  def apply_r(str, map)
    map.reduce(str) { |s, (k, v)| s.gsub(k, v.to_s) }
  end

  # Detecta a versão major do Java em uso (ex: 17, 21, 23)
  # Retorna 0 se não conseguir detectar (comportamento seguro: filtra o arg)
  def java_major_version(java_path: "java")
    out, = Open3.capture2e(java_path.to_s, "-version")
    # "java version \"21.0.3\"" ou "openjdk version \"17.0.11\""
    match = out.match(/version "(?:1\.)?(\d+)/)
    match ? match[1].to_i : 0
  rescue
    0
  end

  def should_install_library?(lib)
    rules = lib["rules"]
    return true unless rules&.any?
    allowed = false
    rules.each do |rule|
      os      = rule["os"]
      matches = os ? os["name"] == "linux" : true
      allowed = (rule["action"] == "allow") if matches
    end
    allowed
  end

  def download_file(url, dest)
    res = HTTParty.get(url, timeout: 30)
    raise "HTTP #{res.code}: #{url}" unless res.success?
    File.binwrite(dest, res.body)
  rescue => e
    raise "Erro ao baixar #{File.basename(dest)}: #{e.message}"
  end
end