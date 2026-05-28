# frozen_string_literal: true

require "json"
require "fileutils"

# =============================================================================
# AccountBank — Banco de contas salvas localmente
#
# Armazena múltiplas contas Microsoft/Minecraft em:
#   ~/.minecraft_ruby_launcher/accounts.json
#
# Cada conta tem:
#   - email              : identificador visual
#   - username           : nome Minecraft ou gamertag Xbox
#   - uuid               : UUID Minecraft Java ou XUID Bedrock
#   - edition            : "java" ou "bedrock"
#   - ms_access_token    : token Microsoft atual
#   - ms_refresh_token   : refresh token Microsoft
#   - mc_access_token    : token Minecraft Java ou token XSTS Bedrock
#   - ms_expires_at      : expiração do token Microsoft
#   - mc_expires_at      : expiração do token Minecraft/XSTS salvo
#   - discord_user_id    : destino para convite via bot
#   - discord_username   : nome do usuário Discord vinculado
#   - last_used          : timestamp da última utilização
# =============================================================================
class AccountBank
  ACCOUNTS_DIR  = File.join(Dir.home, ".minecraft_ruby_launcher")
  ACCOUNTS_FILE = File.join(ACCOUNTS_DIR, "accounts.json")

  def initialize
    FileUtils.mkdir_p(ACCOUNTS_DIR)
    @accounts = load_all
  end

  # ---------------------------------------------------------------------------
  # Salva ou atualiza uma conta pelo e-mail.
  # ---------------------------------------------------------------------------
  def save_account(email:, username:, uuid:,
                   ms_access_token:, ms_refresh_token:, ms_expires_in:,
                   mc_access_token:, mc_expires_in:,
                   discord_user_id: nil, discord_username: nil,
                   edition: "java")
    normalized_email = normalize_email(email, username, uuid, edition)
    previous = @accounts[normalized_email] || {}

    @accounts[normalized_email] = {
      email: normalized_email,
      username: username,
      uuid: uuid,
      edition: normalize_edition(edition),
      discord_user_id: discord_user_id || previous[:discord_user_id],
      discord_username: discord_username || previous[:discord_username],
      ms_access_token: ms_access_token,
      ms_refresh_token: ms_refresh_token,
      mc_access_token: mc_access_token,
      ms_expires_at: (Time.now + ms_expires_in.to_i).to_i,
      mc_expires_at: (Time.now + mc_expires_in.to_i).to_i,
      last_used: Time.now.to_i,
      added_at: previous[:added_at] || Time.now.to_i
    }

    persist!
    @accounts[normalized_email]
  end

  # ---------------------------------------------------------------------------
  # Atualiza apenas os tokens de uma conta existente.
  # ---------------------------------------------------------------------------
  def update_tokens(email:, ms_access_token:, ms_refresh_token:, ms_expires_in:,
                    mc_access_token:, mc_expires_in:, username: nil, uuid: nil,
                    edition: nil)
    key = find_key(email)
    return nil unless key

    @accounts[key].merge!(
      ms_access_token: ms_access_token,
      ms_refresh_token: ms_refresh_token,
      mc_access_token: mc_access_token,
      ms_expires_at: (Time.now + ms_expires_in.to_i).to_i,
      mc_expires_at: (Time.now + mc_expires_in.to_i).to_i,
      last_used: Time.now.to_i
    )

    @accounts[key][:username] = username if present?(username)
    @accounts[key][:uuid] = uuid if present?(uuid)
    @accounts[key][:edition] = normalize_edition(edition) if present?(edition)

    persist!
    @accounts[key]
  end

  # ---------------------------------------------------------------------------
  # Marca conta como usada agora.
  # ---------------------------------------------------------------------------
  def touch(email)
    key = find_key(email)
    return nil unless key

    @accounts[key][:last_used] = Time.now.to_i
    persist!
    @accounts[key]
  end

  # ---------------------------------------------------------------------------
  # Vincula a conta Minecraft/Xbox ao usuário Discord que receberá convites por DM.
  # ---------------------------------------------------------------------------
  def update_discord_user(email:, discord_user_id:, discord_username: nil)
    key = find_key(email)
    return nil unless key

    @accounts[key][:discord_user_id] = discord_user_id
    @accounts[key][:discord_username] = discord_username
    @accounts[key][:last_used] = Time.now.to_i

    persist!
    @accounts[key]
  end

  # ---------------------------------------------------------------------------
  # Remove uma conta.
  # ---------------------------------------------------------------------------
  def remove(email)
    key = find_key(email)
    return nil unless key

    removed = @accounts.delete(key)
    persist!
    removed
  end

  # ---------------------------------------------------------------------------
  # Busca conta por e-mail/chave.
  # ---------------------------------------------------------------------------
  def find(email)
    key = find_key(email)
    key ? @accounts[key] : nil
  end

  # ---------------------------------------------------------------------------
  # Lista todas as contas ordenadas por last_used, mais recente primeiro.
  # ---------------------------------------------------------------------------
  def all
    @accounts.values.sort_by { |account| -(account[:last_used] || 0).to_i }
  end

  # ---------------------------------------------------------------------------
  # Conta mais recentemente usada.
  # ---------------------------------------------------------------------------
  def last_used
    all.first
  end

  # ---------------------------------------------------------------------------
  # Verifica se o token Minecraft/XSTS ainda é válido, com margem de 5 min.
  # ---------------------------------------------------------------------------
  def mc_token_valid?(account)
    return false unless account&.dig(:mc_expires_at)

    Time.now.to_i < (account[:mc_expires_at].to_i - 300)
  end

  # ---------------------------------------------------------------------------
  # Verifica se o token Microsoft ainda é válido, com margem de 5 min.
  # ---------------------------------------------------------------------------
  def ms_token_valid?(account)
    return false unless account&.dig(:ms_expires_at)

    Time.now.to_i < (account[:ms_expires_at].to_i - 300)
  end

  def count
    @accounts.size
  end

  def empty?
    @accounts.empty?
  end

  private

  def load_all
    return {} unless File.exist?(ACCOUNTS_FILE)

    data = JSON.parse(File.read(ACCOUNTS_FILE), symbolize_names: false)

    data.each_with_object({}) do |(key, account), normalized|
      next unless account.is_a?(Hash)

      symbolized = account.transform_keys(&:to_sym)
      symbolized[:edition] = normalize_edition(symbolized[:edition] || "java")
      symbolized[:email] = key if symbolized[:email].to_s.strip.empty?
      normalized[symbolized[:email].to_s] = symbolized
    end
  rescue JSON::ParserError
    {}
  end

  def persist!
    serializable = @accounts.transform_values do |account|
      account.transform_keys(&:to_s)
    end

    FileUtils.mkdir_p(ACCOUNTS_DIR)
    File.write(ACCOUNTS_FILE, JSON.pretty_generate(serializable))
    File.chmod(0o600, ACCOUNTS_FILE)
  end

  def find_key(email)
    value = email.to_s.strip
    return nil if value.empty?
    return value if @accounts.key?(value)

    @accounts.keys.find { |key| key.casecmp(value).zero? }
  end

  def normalize_email(email, username, uuid, edition)
    value = email.to_s.strip
    return value unless value.empty?

    # Em alguns fluxos Bedrock/Xbox a API não retorna e-mail. Cria uma chave estável.
    base = username.to_s.strip.empty? ? uuid.to_s.strip : username.to_s.strip
    base = SecureRandom.uuid if base.empty?
    "#{normalize_edition(edition)}:#{base}"
  end

  def normalize_edition(edition)
    edition.to_s.downcase == "bedrock" ? "bedrock" : "java"
  end

  def present?(value)
    !value.nil? && !value.to_s.strip.empty?
  end
end