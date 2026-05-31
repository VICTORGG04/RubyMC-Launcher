# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open-uri'
require 'resolv'
require 'ipaddr'
require 'securerandom'
require 'time'
require 'yaml'
require 'zip'

module MinecraftRubyLauncher
  # Instala e registra modpacks locais para o Minecraft Ruby Launcher.
  #
  # Suporte implementado:
  # - Modrinth .mrpack: baixa os arquivos listados em modrinth.index.json
  # - CurseForge zip: importa overrides/ e registra a lista de mods que exigem download manual/API
  # - Zip genérico: extrai como game directory isolado
  #
  # O launcher principal deve usar #launch_options para repassar game_directory,
  # minecraft_version e extra_game_args ao MinecraftManager.
  class ModpackManager
    DEFAULT_ROOT = File.expand_path('~/.minecraft_ruby_launcher/modpacks')
    PROFILE_FILE = 'profile.yml'

    Profile = Struct.new(
      :id,
      :name,
      :minecraft_version,
      :loader,
      :loader_version,
      :game_dir,
      :mods_dir,
      :source,
      :created_at,
      :notes,
      keyword_init: true
    ) do
      def to_h
        {
          'id' => id,
          'name' => name,
          'minecraft_version' => minecraft_version,
          'loader' => loader,
          'loader_version' => loader_version,
          'game_dir' => game_dir,
          'mods_dir' => mods_dir,
          'source' => source,
          'created_at' => created_at,
          'notes' => notes
        }
      end
    end

    attr_reader :root

    def initialize(settings = {})
      @settings = stringify_keys(settings || {})
      configured_path = dig_config(@settings, 'modpacks', 'path')
      @root = File.expand_path(configured_path.to_s.empty? ? DEFAULT_ROOT : configured_path)
      FileUtils.mkdir_p(@root)
    end

    def list_profiles
      Dir.glob(File.join(@root, '*', PROFILE_FILE)).sort.map do |profile_file|
        profile_from_hash(YAML.load_file(profile_file) || {})
      rescue StandardError => e
        warn "Ignorando perfil inválido #{profile_file}: #{e.message}"
        nil
      end.compact
    end
    alias list list_profiles

    def find(profile_id)
      list_profiles.find { |profile| profile.id == profile_id.to_s }
    end

    def install_zip(zip_path, name: nil)
      zip_path = File.expand_path(zip_path)
      raise ArgumentError, "Arquivo não encontrado: #{zip_path}" unless File.file?(zip_path)

      zip_type = detect_zip_type(zip_path)

      case zip_type
      when :modrinth
        install_modrinth(zip_path, name: name)
      when :curseforge
        install_curseforge(zip_path, name: name)
      else
        install_generic_zip(zip_path, name: name)
      end
    end

    def install_folder(folder_path, name: nil, minecraft_version: nil, loader: 'vanilla', loader_version: nil)
      folder_path = File.expand_path(folder_path)
      raise ArgumentError, "Pasta não encontrada: #{folder_path}" unless Dir.exist?(folder_path)

      id = unique_profile_id(name || File.basename(folder_path))
      pack_dir = File.join(@root, id)
      game_dir = File.join(pack_dir, 'game')
      FileUtils.mkdir_p(game_dir)
      FileUtils.cp_r(Dir.glob(File.join(folder_path, '*')), game_dir)

      profile = Profile.new(
        id: id,
        name: name || File.basename(folder_path),
        minecraft_version: minecraft_version || default_minecraft_version,
        loader: loader,
        loader_version: loader_version,
        game_dir: game_dir,
        mods_dir: File.join(game_dir, 'mods'),
        source: 'folder',
        created_at: Time.now.utc.iso8601,
        notes: 'Importado de pasta local.'
      )
      save_profile(profile)
      profile
    end

    def remove(profile_id)
      profile = find(profile_id)
      return false unless profile

      pack_dir = File.dirname(File.dirname(profile.game_dir))
      FileUtils.rm_rf(pack_dir) if pack_dir.start_with?(@root)
      true
    end

    def launch_options(profile_id, community_server: nil)
      profile = find(profile_id)
      raise ArgumentError, "Modpack não encontrado: #{profile_id}" unless profile

      game_args = []
      game_args.concat(community_server.game_args) if community_server&.enabled?

      {
        minecraft_version: profile.minecraft_version,
        loader: profile.loader,
        loader_version: profile.loader_version,
        game_directory: profile.game_dir,
        extra_game_args: game_args
      }
    end

    private

    def install_modrinth(zip_path, name: nil)
      Zip::File.open(zip_path) do |zip|
        index = JSON.parse(read_zip_entry(zip, 'modrinth.index.json'))
        pack_name = name || index['name'] || File.basename(zip_path, '.*')
        id = unique_profile_id(pack_name)
        pack_dir = File.join(@root, id)
        game_dir = File.join(pack_dir, 'game')
        mods_dir = File.join(game_dir, 'mods')
        FileUtils.mkdir_p(mods_dir)

        extract_prefix(zip, 'overrides/', game_dir)
        extract_prefix(zip, 'client-overrides/', game_dir)

        missing = []
        Array(index['files']).each do |file_entry|
          relative_path = file_entry['path'].to_s
          download_url = Array(file_entry['downloads']).compact.first
          if relative_path.empty? || download_url.to_s.empty?
            missing << file_entry
            next
          end

          target = safe_join(game_dir, relative_path)
          download_file(download_url, target, sha1: file_entry.dig('hashes', 'sha1'))
        end

        File.write(File.join(pack_dir, 'missing_files.json'), JSON.pretty_generate(missing)) unless missing.empty?

        deps = index['dependencies'] || {}
        loader, loader_version = detect_loader_from_dependencies(deps)
        profile = Profile.new(
          id: id,
          name: pack_name,
          minecraft_version: deps['minecraft'] || default_minecraft_version,
          loader: loader,
          loader_version: loader_version,
          game_dir: game_dir,
          mods_dir: mods_dir,
          source: 'modrinth',
          created_at: Time.now.utc.iso8601,
          notes: missing.empty? ? 'Modpack Modrinth instalado com downloads verificados.' : "Instalado com #{missing.size} arquivo(s) pendente(s)."
        )
        save_profile(profile)
        profile
      end
    end

    def install_curseforge(zip_path, name: nil)
      Zip::File.open(zip_path) do |zip|
        manifest = JSON.parse(read_zip_entry(zip, 'manifest.json'))
        pack_name = name || manifest['name'] || File.basename(zip_path, '.*')
        id = unique_profile_id(pack_name)
        pack_dir = File.join(@root, id)
        game_dir = File.join(pack_dir, 'game')
        mods_dir = File.join(game_dir, 'mods')
        FileUtils.mkdir_p(mods_dir)

        extract_prefix(zip, 'overrides/', game_dir)

        minecraft = manifest['minecraft'] || {}
        loader_entry = Array(minecraft['modLoaders']).find { |entry| entry['primary'] } || Array(minecraft['modLoaders']).first || {}
        loader, loader_version = parse_loader_id(loader_entry['id'])

        manual_files = Array(manifest['files'])
        unless manual_files.empty?
          File.write(
            File.join(pack_dir, 'curseforge_manual_downloads.json'),
            JSON.pretty_generate(manual_files)
          )
        end

        profile = Profile.new(
          id: id,
          name: pack_name,
          minecraft_version: minecraft['version'] || default_minecraft_version,
          loader: loader || 'forge',
          loader_version: loader_version,
          game_dir: game_dir,
          mods_dir: mods_dir,
          source: 'curseforge',
          created_at: Time.now.utc.iso8601,
          notes: manual_files.empty? ? 'CurseForge importado.' : "Overrides importados. #{manual_files.size} mod(s) exigem download manual ou integração com API CurseForge."
        )
        save_profile(profile)
        profile
      end
    end

    def install_generic_zip(zip_path, name: nil)
      id = unique_profile_id(name || File.basename(zip_path, '.*'))
      pack_dir = File.join(@root, id)
      game_dir = File.join(pack_dir, 'game')
      FileUtils.mkdir_p(game_dir)

      Zip::File.open(zip_path) do |zip|
        zip.each do |entry|
          next if entry.directory?

          target = safe_join(game_dir, entry.name)
          FileUtils.mkdir_p(File.dirname(target))
          entry.extract(target) { true }
        end
      end

      profile = Profile.new(
        id: id,
        name: name || File.basename(zip_path, '.*'),
        minecraft_version: default_minecraft_version,
        loader: 'vanilla',
        loader_version: nil,
        game_dir: game_dir,
        mods_dir: File.join(game_dir, 'mods'),
        source: 'zip',
        created_at: Time.now.utc.iso8601,
        notes: 'Zip genérico extraído como diretório isolado do jogo.'
      )
      save_profile(profile)
      profile
    end

    def detect_zip_type(zip_path)
      Zip::File.open(zip_path) do |zip|
        return :modrinth if zip.find_entry('modrinth.index.json')
        return :curseforge if zip.find_entry('manifest.json') && read_zip_entry(zip, 'manifest.json').include?('modLoaders')
      end
      :generic
    end

    def read_zip_entry(zip, name)
      entry = zip.find_entry(name)
      raise ArgumentError, "Arquivo #{name} não encontrado dentro do modpack" unless entry

      entry.get_input_stream.read
    end

    def extract_prefix(zip, prefix, destination)
      zip.each do |entry|
        next unless entry.name.start_with?(prefix)
        next if entry.directory?

        relative = entry.name.delete_prefix(prefix)
        next if relative.empty?

        target = safe_join(destination, relative)
        FileUtils.mkdir_p(File.dirname(target))
        entry.extract(target) { true }
      end
    end

    def safe_validate_url!(url)
      parsed = URI.parse(url)
      raise "URL scheme must be http or https" unless %w[http https].include?(parsed.scheme)
      raise "URL host cannot be empty" if parsed.host.nil? || parsed.host.empty?
      return if parsed.host == 'localhost' || parsed.host == '127.0.0.1' || parsed.host == '::1'

      ip = IPAddr.new(Resolv.getaddress(parsed.host))
      private_ranges = [
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('172.16.0.0/12'),
        IPAddr.new('192.168.0.0/16'),
        IPAddr.new('127.0.0.0/8'),
        IPAddr.new('::1/128'),
        IPAddr.new('fc00::/7'),
        IPAddr.new('169.254.0.0/16')
      ]
      private_ranges.each do |range|
        if range.include?(ip)
          raise "URL resolves to a private or internal IP: #{ip}"
        end
      end
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError => e
      raise "Invalid URL: #{e.message}"
    end

    def download_file(url, target, sha1: nil)
      if File.file?(target) && sha1 && Digest::SHA1.file(target).hexdigest.casecmp?(sha1)
        return target
      end

      safe_validate_url!(url)

      FileUtils.mkdir_p(File.dirname(target))
      temp = "#{target}.download"
      URI.open(url, read_timeout: 90, open_timeout: 20) do |remote|
        File.open(temp, 'wb') { |file| IO.copy_stream(remote, file) }
      end

      if sha1
        actual = Digest::SHA1.file(temp).hexdigest
        unless actual.casecmp?(sha1)
          FileUtils.rm_f(temp)
          raise "SHA1 inválido para #{File.basename(target)}: esperado #{sha1}, recebido #{actual}"
        end
      end

      FileUtils.mv(temp, target)
      target
    ensure
      FileUtils.rm_f(temp) if defined?(temp) && File.exist?(temp)
    end

    def save_profile(profile)
      profile_dir = File.join(@root, profile.id)
      FileUtils.mkdir_p(profile_dir)
      File.write(File.join(profile_dir, PROFILE_FILE), profile.to_h.to_yaml)
      profile
    end

    def profile_from_hash(hash)
      Profile.new(
        id: hash['id'],
        name: hash['name'],
        minecraft_version: hash['minecraft_version'],
        loader: hash['loader'],
        loader_version: hash['loader_version'],
        game_dir: hash['game_dir'],
        mods_dir: hash['mods_dir'],
        source: hash['source'],
        created_at: hash['created_at'],
        notes: hash['notes']
      )
    end

    def unique_profile_id(name)
      base = sanitize_id(name)
      candidate = base
      candidate = "#{base}-#{SecureRandom.hex(3)}" while Dir.exist?(File.join(@root, candidate))
      candidate
    end

    def sanitize_id(value)
      value.to_s.downcase.gsub(/[^a-z0-9\-_]+/, '-').gsub(/^-|-$/, '')[0, 48].then do |id|
        id.empty? ? "modpack-#{SecureRandom.hex(3)}" : id
      end
    end

    def safe_join(base, *parts)
      expanded_base = File.expand_path(base)
      path = File.expand_path(File.join(expanded_base, *parts))
      unless path == expanded_base || path.start_with?(expanded_base + File::SEPARATOR)
        raise SecurityError, "Caminho inseguro dentro do modpack: #{parts.join('/')}"
      end
      path
    end

    def detect_loader_from_dependencies(dependencies)
      %w[fabric-loader quilt-loader forge neoforge].each do |key|
        return [key.sub('-loader', ''), dependencies[key]] if dependencies[key]
      end
      ['vanilla', nil]
    end

    def parse_loader_id(loader_id)
      return ['vanilla', nil] if loader_id.to_s.empty?

      loader, version = loader_id.split('-', 2)
      [loader || 'vanilla', version]
    end

    def default_minecraft_version
      dig_config(@settings, 'minecraft', 'default_version') || '1.21.4'
    end

    def dig_config(hash, *keys)
      keys.reduce(hash) { |current, key| current.is_a?(Hash) ? current[key] : nil }
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify_keys(item) }
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
    end
  end
end
