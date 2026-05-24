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
#   - email      : identificador visual (informado pelo usuário)
#   - username   : nome Minecraft (vem da API)
#   - uuid       : UUID Minecraft
#   - ms_refresh_token : para renovar sem logar de novo
#   - mc_access_token  : token atual do Minecraft
#   - ms_expires_at / mc_expires_at : timestamps de expiração
  #   - discord_user_id / discord_username : destino para convite via bot
  #   - last_used  : quando foi usada pela última vez
# =============================================================================
class AccountBank
  ACCOUNTS_DIR  = File.join(Dir.home, ".minecraft_ruby_launcher")
  ACCOUNTS_FILE = File.join(ACCOUNTS_DIR, "accounts.json")

  def initialize
    FileUtils.mkdir_p(ACCOUNTS_DIR)
    @accounts = load_all
  end

  # ---------------------------------------------------------------------------
  # Salva ou atualiza uma conta pelo e-mail
  # ---------------------------------------------------------------------------
  def save_account(email:, username:, uuid:,
                   ms_access_token:, ms_refresh_token:, ms_expires_in:,
                   mc_access_token:, mc_expires_in:,
                   discord_user_id: nil, discord_username: nil)
    @accounts[email] = {
      email:             email,
      username:          username,
      uuid:              uuid,
      discord_user_id:   discord_user_id || @accounts.dig(email, :discord_user_id),
      discord_username:  discord_username || @accounts.dig(email, :discord_username),
      ms_access_token:   ms_access_token,
      ms_refresh_token:  ms_refresh_token,
      mc_access_token:   mc_access_token,
      ms_expires_at:     (Time.now + ms_expires_in).to_i,
      mc_expires_at:     (Time.now + mc_expires_in).to_i,
      last_used:         Time.now.to_i,
      added_at:          @accounts.dig(email, :added_at) || Time.now.to_i
    }
    persist!
    @accounts[email]
  end

  # ---------------------------------------------------------------------------
  # Atualiza apenas os tokens de uma conta existente
  # ---------------------------------------------------------------------------
  def update_tokens(email:, ms_access_token:, ms_refresh_token:, ms_expires_in:,
                    mc_access_token:, mc_expires_in:, username: nil, uuid: nil)
    return nil unless @accounts[email]
    @accounts[email].merge!(
      ms_access_token:  ms_access_token,
      ms_refresh_token: ms_refresh_token,
      mc_access_token:  mc_access_token,
      ms_expires_at:    (Time.now + ms_expires_in).to_i,
      mc_expires_at:    (Time.now + mc_expires_in).to_i,
      last_used:        Time.now.to_i
    )
    @accounts[email][:username] = username if username
    @accounts[email][:uuid]     = uuid     if uuid
    persist!
    @accounts[email]
  end

  # ---------------------------------------------------------------------------
  # Marca conta como usada agora
  # ---------------------------------------------------------------------------
  def touch(email)
    return unless @accounts[email]
    @accounts[email][:last_used] = Time.now.to_i
    persist!
  end

  # ---------------------------------------------------------------------------
  # Vincula a conta Minecraft ao usuário Discord que receberá convites por DM
  # ---------------------------------------------------------------------------
  def update_discord_user(email:, discord_user_id:, discord_username: nil)
    return nil unless @accounts[email]

    @accounts[email][:discord_user_id]  = discord_user_id
    @accounts[email][:discord_username] = discord_username
    @accounts[email][:last_used]        = Time.now.to_i
    persist!
    @accounts[email]
  end

  # ---------------------------------------------------------------------------
  # Remove uma conta
  # ---------------------------------------------------------------------------
  def remove(email)
    @accounts.delete(email)
    persist!
  end

  # ---------------------------------------------------------------------------
  # Busca conta por e-mail
  # ---------------------------------------------------------------------------
  def find(email)
    @accounts[email]
  end

  # ---------------------------------------------------------------------------
  # Lista todas as contas ordenadas por last_used (mais recente primeiro)
  # ---------------------------------------------------------------------------
  def all
    @accounts.values.sort_by { |a| -(a[:last_used] || 0) }
  end

  # ---------------------------------------------------------------------------
  # Conta mais recentemente usada
  # ---------------------------------------------------------------------------
  def last_used
    all.first
  end

  # ---------------------------------------------------------------------------
  # Verifica se o MC token ainda é válido (margem 5 min)
  # ---------------------------------------------------------------------------
  def mc_token_valid?(account)
    return false unless account&.dig(:mc_expires_at)
    Time.now.to_i < (account[:mc_expires_at] - 300)
  end

  # ---------------------------------------------------------------------------
  # Verifica se o MS token ainda é válido (margem 5 min)
  # ---------------------------------------------------------------------------
  def ms_token_valid?(account)
    return false unless account&.dig(:ms_expires_at)
    Time.now.to_i < (account[:ms_expires_at] - 300)
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
    # Normaliza chaves para symbols nos valores internos
    data.transform_values do |acc|
      acc.transform_keys(&:to_sym)
    end
  rescue JSON::ParserError
    {}
  end

  def persist!
    # Serializa com chaves string para JSON
    serializable = @accounts.transform_values do |acc|
      acc.transform_keys(&:to_s)
    end
    File.write(ACCOUNTS_FILE, JSON.pretty_generate(serializable))
    File.chmod(0o600, ACCOUNTS_FILE)
  end
end
