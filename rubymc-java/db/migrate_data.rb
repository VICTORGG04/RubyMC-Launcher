require_relative '../lib/db_store'
require 'json'
require 'yaml'
require 'openssl'
require 'base64'
require 'digest'

module EncryptedVault
  ALGO = 'aes-256-gcm'.freeze

  def self.decrypt(payload_b64, key_hex)
    key = [key_hex].pack('H*')
    data = JSON.parse(Base64.strict_decode64(payload_b64))
    iv  = Base64.strict_decode64(data['iv'])
    ct  = Base64.strict_decode64(data['ct'])
    tag = Base64.strict_decode64(data['tag'])

    cipher = OpenSSL::Cipher.new(ALGO)
    cipher.decrypt
    cipher.key = key
    cipher.iv  = iv
    cipher.auth_tag = tag

    cipher.update(ct) + cipher.final
  end

  def self.derive_key(secret)
    salt = Digest::SHA256.hexdigest('RubyMC PIX Vault Salt')
    OpenSSL::PKCS5.pbkdf2_hmac_sha1(secret, salt, 20_000, 32).unpack1('H*')
  end
end

settings_file = File.join(__dir__, '..', 'config', 'settings.yml')
settings = YAML.safe_load(File.read(settings_file))
client_secret = settings.dig('discord', 'oauth', 'client_secret') || ''
encryption_key = EncryptedVault.derive_key(client_secret)

enc_file = File.join(__dir__, '..', 'tmp', 'vip_data.enc')
unless File.exist?(enc_file)
  puts "Arquivo vip_data.enc não encontrado em #{enc_file}. Nada a importar."
  exit 0
end

encrypted = File.read(enc_file)
begin
  decrypted = EncryptedVault.decrypt(encrypted, encryption_key)
  data = JSON.parse(decrypted, symbolize_names: true)
rescue => e
  puts "Erro ao decriptar vip_data.enc: #{e.message}"
  exit 1
end

count = DbStore.import_from_vip_data(data)
puts "Importação concluída: #{count} pagamentos importados para o PostgreSQL."
