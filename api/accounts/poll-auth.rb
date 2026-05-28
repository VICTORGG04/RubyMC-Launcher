# =============================================================================
# PATCH para a rota /api/accounts/poll-auth
#
# Use este bloco para substituir a rota atual no arquivo principal do backend
# Sinatra/RubyMC. Ele pressupõe que MicrosoftAuth e AccountBank já foram
# carregados com require_relative.
# =============================================================================

post "/api/accounts/poll-auth" do
  content_type :json

  payload = JSON.parse(request.body.read.to_s)
  device_code = payload["device_code"].to_s
  edition = payload["edition"].to_s.downcase == "bedrock" ? "bedrock" : "java"

  if device_code.empty?
    status 400
    return {
      ok: false,
      complete: false,
      restart_required: true,
      error: "device_code ausente. Gere um novo código de login."
    }.to_json
  end

  token = MicrosoftAuth.check_token(device_code: device_code)

  case token[:status]
  when :pending
    return {
      ok: true,
      complete: false
    }.to_json

  when :declined
    status 400
    return {
      ok: false,
      complete: false,
      error: token[:message] || "Login recusado pelo usuário."
    }.to_json

  when :expired
    status 400
    return {
      ok: false,
      complete: false,
      restart_required: true,
      error: token[:message] || "Código expirado. Inicie o login novamente."
    }.to_json

  when :used
    status 400
    return {
      ok: false,
      complete: false,
      restart_required: true,
      error: token[:message] || "Este código de autenticação já foi usado. Inicie o login novamente."
    }.to_json

  when :success
    begin
      auth_result =
        if edition == "bedrock"
          MicrosoftAuth.full_bedrock_flow(token[:access_token])
        else
          MicrosoftAuth.full_auth_flow(token[:access_token])
        end

      # Se sua rota atual já usa uma instância global, substitua esta linha
      # pelo objeto existente, por exemplo: settings.account_bank ou $account_bank.
      bank = defined?(ACCOUNT_BANK) ? ACCOUNT_BANK : AccountBank.new

      # O fluxo device code legacy não retorna e-mail diretamente.
      # Usamos uma chave estável por edição + uuid para evitar email nil.
      account_key = "#{edition}:#{auth_result[:uuid]}"

      saved = bank.save_account(
        email: account_key,
        username: auth_result[:username],
        uuid: auth_result[:uuid],
        edition: edition,
        ms_access_token: token[:access_token],
        ms_refresh_token: token[:refresh_token],
        ms_expires_in: token[:expires_in],
        mc_access_token: auth_result[:mc_access_token],
        mc_expires_in: auth_result[:mc_expires_in]
      )

      return {
        ok: true,
        complete: true,
        edition: edition,
        account: {
          email: saved[:email],
          username: saved[:username],
          uuid: saved[:uuid],
          edition: saved[:edition]
        }
      }.to_json
    rescue MicrosoftAuth::AuthError => e
      status 500
      return {
        ok: false,
        complete: false,
        restart_required: true,
        error: e.message,
        type: e.class.name
      }.to_json
    end

  else
    status 500
    return {
      ok: false,
      complete: false,
      restart_required: true,
      error: token[:message] || "Erro inesperado no login Microsoft."
    }.to_json
  end
rescue JSON::ParserError => e
  status 400
  {
    ok: false,
    complete: false,
    restart_required: true,
    error: "JSON inválido recebido pelo backend: #{e.message}",
    type: e.class.name
  }.to_json
rescue StandardError => e
  status 500
  {
    ok: false,
    complete: false,
    restart_required: true,
    error: e.message,
    type: e.class.name
  }.to_json
end