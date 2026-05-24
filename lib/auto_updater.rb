# frozen_string_literal: true

require "httparty"
require "json"
require "fileutils"
require "open3"

# =============================================================================
# AutoUpdater — Atualização automática do launcher e do Minecraft
#
# Launcher: compara versão local com última release do GitHub
# Minecraft: compara versão instalada com última release da Mojang
# =============================================================================
class AutoUpdater
  VERSION_MANIFEST = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
  LAUNCHER_DIR     = File.dirname(__dir__)

  def initialize(config)
    @config = config
  end

  # ---------------------------------------------------------------------------
  # Checa e aplica atualização do LAUNCHER via GitHub Releases
  # Retorna: { updated: bool, from:, to:, message: }
  # ---------------------------------------------------------------------------
  def check_launcher_update
    update_url = @config.dig("launcher", "update_url").to_s.strip
    return { updated: false, message: "URL de update não configurada." } if update_url.empty? || update_url.include?("SEU_")

    current = @config.dig("launcher", "version").to_s.strip
    res = HTTParty.get(update_url,
                       headers: { "User-Agent" => "MinecraftRubyLauncher/#{current}" },
                       timeout: 8
    )
    return { updated: false, message: "Falha ao checar GitHub: #{res.code}" } unless res.success?

    release = JSON.parse(res.body)
    latest  = release["tag_name"].to_s.gsub(/\Av/, "")
    return { updated: false, message: "Launcher já está na versão mais recente (#{current})." } if latest == current || latest.empty?

    # Baixa o zip/tarball da release
    asset = release["assets"]&.find { |a| a["name"].end_with?(".zip") || a["name"].end_with?(".tar.gz") }
    download_url = asset ? asset["browser_download_url"] : release["zipball_url"]

    apply_launcher_update(download_url, latest)
    { updated: true, from: current, to: latest, message: "Launcher atualizado de #{current} para #{latest}!" }
  rescue => e
    { updated: false, message: "Erro no update do launcher: #{e.message}" }
  end

  # ---------------------------------------------------------------------------
  # Checa nova versão RELEASE do Minecraft
  # Retorna: { available: bool, latest:, current_installed: }
  # ---------------------------------------------------------------------------
  def check_minecraft_update(current_version_id = nil)
    res = HTTParty.get(VERSION_MANIFEST, timeout: 8)
    return { available: false, message: "Falha ao buscar versões." } unless res.success?

    manifest = JSON.parse(res.body)
    latest   = manifest.dig("latest", "release")
    return { available: false, message: "Não foi possível detectar versão mais recente." } unless latest

    if current_version_id && current_version_id == latest
      { available: false, latest: latest, message: "Minecraft #{latest} já é a versão mais recente." }
    else
      { available: true, latest: latest, current: current_version_id,
        message: "Nova versão do Minecraft disponível: #{latest}" }
    end
  rescue => e
    { available: false, message: "Erro ao checar Minecraft: #{e.message}" }
  end

  # ---------------------------------------------------------------------------
  # Retorna a versão mais recente do Minecraft (release)
  # ---------------------------------------------------------------------------
  def latest_minecraft_version
    res = HTTParty.get(VERSION_MANIFEST, timeout: 8)
    return nil unless res.success?
    JSON.parse(res.body).dig("latest", "release")
  rescue
    nil
  end

  private

  def apply_launcher_update(download_url, new_version)
    tmp_dir  = File.join(Dir.tmpdir, "mc_launcher_update_#{new_version}")
    tmp_file = "#{tmp_dir}.zip"
    FileUtils.mkdir_p(tmp_dir)

    # Baixa o arquivo
    res = HTTParty.get(download_url, timeout: 60, follow_redirects: true)
    File.binwrite(tmp_file, res.body)

    # Extrai
    if tmp_file.end_with?(".zip")
      system("unzip -o -q #{tmp_file} -d #{tmp_dir}")
    else
      system("tar -xzf #{tmp_file} -C #{tmp_dir} --strip-components=1")
    end

    # Copia arquivos Ruby para o diretório do launcher
    extracted = Dir.glob("#{tmp_dir}/**/*.rb")
    extracted.each do |src|
      rel  = src.sub("#{tmp_dir}/", "")
      dest = File.join(LAUNCHER_DIR, rel)
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(src, dest)
    end

    FileUtils.rm_rf([tmp_file, tmp_dir])
  rescue => e
    raise "Falha ao aplicar update: #{e.message}"
  end
end