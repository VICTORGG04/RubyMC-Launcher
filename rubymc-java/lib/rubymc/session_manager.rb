# frozen_string_literal: true

require "json"
require "fileutils"

class SessionManager
  SESSION_DIR  = File.join(Dir.home, ".minecraft_ruby_launcher")
  SESSION_FILE = File.join(SESSION_DIR, "session.json")

  def initialize
    FileUtils.mkdir_p(SESSION_DIR)
  end

  def save(data)
    session = {
      ms_access_token:  data[:ms_access_token],
      ms_refresh_token: data[:ms_refresh_token],
      mc_access_token:  data[:mc_access_token],
      uuid:             data[:uuid],
      username:         data[:username],
      ms_expires_at:    (Time.now + (data[:ms_expires_in] || 3600)).to_i,
      mc_expires_at:    (Time.now + (data[:mc_expires_in] || 86400)).to_i,
      saved_at:         Time.now.to_i
    }
    File.write(SESSION_FILE, JSON.pretty_generate(session))
    File.chmod(0o600, SESSION_FILE)
    session
  end

  def load
    return nil unless File.exist?(SESSION_FILE)
    JSON.parse(File.read(SESSION_FILE), symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  def ms_token_valid?(session)
    return false unless session&.dig(:ms_expires_at)
    Time.now.to_i < (session[:ms_expires_at] - 300)
  end

  def mc_token_valid?(session)
    return false unless session&.dig(:mc_expires_at)
    Time.now.to_i < (session[:mc_expires_at] - 300)
  end

  def clear
    File.delete(SESSION_FILE) if File.exist?(SESSION_FILE)
  end

  def session_dir
    SESSION_DIR
  end
end
