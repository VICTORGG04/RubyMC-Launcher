# frozen_string_literal: true

require "httparty"
require "json"
require "securerandom"
require "uri"

# =============================================================================
# MicrosoftAuth — Autenticação completa Microsoft → Xbox → Minecraft
#
# Fluxo:
#   1. Device Code Flow (sem servidor local, sem redirect URI)
#   2. Microsoft Access Token
#   3. Xbox Live Token (XBL)
#   4. XSTS Token
#   5. Minecraft Bearer Token / Perfil Xbox
#   6. Perfil Minecraft Java ou perfil Xbox Bedrock
# =============================================================================
module MicrosoftAuth
  # Client ID público usado pelo launcher oficial do Minecraft.
  CLIENT_ID = "00000000402b5328"

  # Escopo necessário para autenticação Xbox Live no fluxo legacy do Minecraft.
  SCOPE = "service::user.auth.xboxlive.com::MBI_SSL"

  # Endpoints Microsoft / Xbox / Minecraft.
  DEVICE_CODE_URL  = "https://login.live.com/oauth20_connect.srf"
  TOKEN_URL        = "https://login.live.com/oauth20_token.srf"
  XBL_AUTH_URL     = "https://user.auth.xboxlive.com/user/authenticate"
  XSTS_AUTH_URL    = "https://xsts.auth.xboxlive.com/xsts/authorize"
  MC_AUTH_URL      = "https://api.minecraftservices.com/authentication/login_with_xbox"
  MC_PROFILE_URL   = "https://api.minecraftservices.com/minecraft/profile"
  XBOX_PROFILE_URL = "https://profile.xboxlive.com/users/me/profile/settings"

  # ---------------------------------------------------------------------------
  # Erro customizado de autenticação
  # ---------------------------------------------------------------------------
  class AuthError < StandardError; end

  # ---------------------------------------------------------------------------
  # Parser JSON seguro para respostas HTTP.
  # Não deixa JSON::ParserError cru estourar no backend.
  # ---------------------------------------------------------------------------
  def self.parse_json_response!(response, context)
    body = response.body.to_s

    if body.strip.empty?
      raise AuthError, "#{context}: resposta vazia do servidor remoto (HTTP #{response.code})"
    end

    JSON.parse(body)
  rescue JSON::ParserError => e
    preview = body.to_s[0, 300]
    raise AuthError, "#{context}: JSON inválido recebido (HTTP #{response.code}): #{e.message}. Body: #{preview}"
  end

  # ---------------------------------------------------------------------------
  # Parser flexível para erro: retorna {} quando o corpo vier vazio ou inválido.
  # Usado em tentativas/fallbacks onde não queremos abortar antes da próxima opção.
  # ---------------------------------------------------------------------------
  def self.try_parse_json(response)
    body = response.body.to_s
    return {} if body.strip.empty?

    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  # ---------------------------------------------------------------------------
  # Gera mensagem amigável para falhas HTTP.
  # ---------------------------------------------------------------------------
  def self.http_error_message(response, context)
    body = response.body.to_s.strip
    suffix = body.empty? ? " — corpo vazio" : " — #{body[0, 500]}"
    "#{context}: HTTP #{response.code} #{response.message}#{suffix}"
  end

  # ---------------------------------------------------------------------------
  # Normaliza mensagens de erro Microsoft OAuth.
  # ---------------------------------------------------------------------------
  def self.oauth_error_message(data)
    description = data["error_description"].to_s.strip
    error = data["error"].to_s.strip

    return description unless description.empty?
    return error unless error.empty?

    "Erro OAuth desconhecido."
  end

  # ---------------------------------------------------------------------------
  # Detecta erro de device_code reutilizado.
  # ---------------------------------------------------------------------------
  def self.device_code_already_used?(description)
    text = description.to_s.downcase
    text.include?("device_code") && text.include?("already been used")
  end

  # ---------------------------------------------------------------------------
  # Variantes de RpsTicket para Xbox Live.
  #
  # No fluxo legacy do Minecraft Launcher:
  #   CLIENT_ID = "00000000402b5328"
  #   SCOPE     = "service::user.auth.xboxlive.com::MBI_SSL"
  # o XBL costuma aceitar o token Microsoft sem prefixo.
  #
  # Em fluxos Azure/customizados, muitos exemplos usam "d=<token>".
  # Por isso tentamos os dois formatos para evitar HTTP 401 com corpo vazio.
  # ---------------------------------------------------------------------------
  def self.xbl_rps_ticket_variants(ms_access_token)
    raw = ms_access_token.to_s.strip.sub(/\Ad=/, "")

    [
      ["token sem prefixo", raw],
      ["token com prefixo d=", "d=#{raw}"]
    ]
  end

  # ---------------------------------------------------------------------------
  # Faz uma tentativa de autenticação XBL.
  # ---------------------------------------------------------------------------
  def self.post_xbl_authenticate(rps_ticket)
    HTTParty.post(
      XBL_AUTH_URL,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "x-xbl-contract-version" => "1"
      },
      body: {
        Properties: {
          AuthMethod: "RPS",
          SiteName: "user.auth.xboxlive.com",
          RpsTicket: rps_ticket
        },
        RelyingParty: "http://auth.xboxlive.com",
        TokenType: "JWT"
      }.to_json
    )
  end

  # ---------------------------------------------------------------------------
  # Inicia o Device Code Flow.
  # Retorna: { device_code:, user_code:, verification_uri:, interval:, expires_in: }
  # ---------------------------------------------------------------------------
  def self.request_device_code
    response = HTTParty.post(
      DEVICE_CODE_URL,
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: URI.encode_www_form(
        client_id: CLIENT_ID,
        scope: SCOPE,
        response_type: "device_code"
      )
    )

    raise AuthError, http_error_message(response, "Falha ao obter device code") unless response.success?

    data = parse_json_response!(response, "Device Code Microsoft")

    {
      device_code: data["device_code"],
      user_code: data["user_code"],
      verification_uri: data["verification_uri"] || data["verification_url"],
      interval: (data["interval"] || 5).to_i,
      expires_in: (data["expires_in"] || 900).to_i
    }
  end

  # ---------------------------------------------------------------------------
  # Polling bloqueante: aguarda o usuário fazer login no navegador.
  # Retorna o Microsoft Access Token quando aprovado.
  # ---------------------------------------------------------------------------
  def self.poll_for_token(device_code:, interval:, expires_in:, &on_waiting)
    deadline = Time.now + expires_in.to_i

    loop do
      raise AuthError, "Tempo de login expirado. Tente novamente." if Time.now > deadline

      sleep(interval.to_i)

      response = HTTParty.post(
        TOKEN_URL,
        headers: { "Content-Type" => "application/x-www-form-urlencoded" },
        body: URI.encode_www_form(
          client_id: CLIENT_ID,
          grant_type: "urn:ietf:params:oauth:grant-type:device_code",
          device_code: device_code
        )
      )

      data = parse_json_response!(response, "Polling do token Microsoft")
      error = data["error"]
      message = oauth_error_message(data)

      case error
      when nil
        return {
          access_token: data["access_token"],
          refresh_token: data["refresh_token"],
          expires_in: data["expires_in"].to_i
        }
      when "authorization_pending"
        on_waiting&.call
        next
      when "authorization_declined"
        raise AuthError, "Login recusado pelo usuário."
      when "expired_token"
        raise AuthError, "Código expirado. Reinicie o processo."
      when "invalid_grant"
        raise AuthError, "Este código de autenticação já foi usado. Inicie o login novamente." if device_code_already_used?(message)

        raise AuthError, message
      else
        raise AuthError, message
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Verificação única non-blocking — usada pelo poll via HTTP.
  # Retorna { status: :success/:pending/:declined/:expired/:used/:error, ... }
  # ---------------------------------------------------------------------------
  def self.check_token(device_code:)
    response = HTTParty.post(
      TOKEN_URL,
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: URI.encode_www_form(
        client_id: CLIENT_ID,
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
        device_code: device_code
      )
    )

    data = parse_json_response!(response, "Polling do token Microsoft")
    error = data["error"]
    message = oauth_error_message(data)

    case error
    when nil
      {
        status: :success,
        access_token: data["access_token"],
        refresh_token: data["refresh_token"],
        expires_in: data["expires_in"].to_i
      }
    when "authorization_pending"
      { status: :pending }
    when "authorization_declined"
      { status: :declined, message: "Login recusado pelo usuário." }
    when "expired_token"
      { status: :expired, message: "Código expirado. Inicie o login novamente." }
    when "invalid_grant"
      if device_code_already_used?(message)
        { status: :used, message: "Este código de autenticação já foi usado. Inicie o login novamente." }
      else
        { status: :error, message: message }
      end
    else
      { status: :error, message: message }
    end
  rescue AuthError => e
    { status: :error, message: e.message }
  rescue StandardError => e
    { status: :error, message: "#{e.class}: #{e.message}" }
  end

  # ---------------------------------------------------------------------------
  # Renova o Access Token usando o Refresh Token salvo.
  # ---------------------------------------------------------------------------
  def self.refresh_token(refresh_token)
    response = HTTParty.post(
      TOKEN_URL,
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: URI.encode_www_form(
        client_id: CLIENT_ID,
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        scope: SCOPE
      )
    )

    data = parse_json_response!(response, "Renovação do token Microsoft")

    unless response.success?
      raise AuthError, "Falha ao renovar token: #{oauth_error_message(data)}"
    end

    {
      access_token: data["access_token"],
      refresh_token: data["refresh_token"],
      expires_in: data["expires_in"].to_i
    }
  end

  # ---------------------------------------------------------------------------
  # Passo 2: Microsoft Token → Xbox Live Token (XBL)
  #
  # IMPORTANTE:
  #   - XBL usa RelyingParty: "http://auth.xboxlive.com"
  #   - XSTS Bedrock/Xbox Profile usa: "http://xboxlive.com"
  # ---------------------------------------------------------------------------
  def self.authenticate_xbl(ms_access_token)
    errors = []

    xbl_rps_ticket_variants(ms_access_token).each do |label, ticket|
      response = post_xbl_authenticate(ticket)
      body = response.body.to_s
      data = body.strip.empty? ? {} : parse_json_response!(response, "Autenticação XBL")

      if response.success?
        token = data["Token"]
        user_hash = data.dig("DisplayClaims", "xui", 0, "uhs")

        if token.to_s.empty?
          errors << "#{label}: HTTP #{response.code}, resposta sem Token"
          next
        end

        if user_hash.to_s.empty?
          errors << "#{label}: HTTP #{response.code}, resposta sem user hash (uhs)"
          next
        end

        return {
          token: token,
          user_hash: user_hash
        }
      end

      parsed_error = try_parse_json(response)
      message =
        parsed_error["Message"] ||
        parsed_error["error_description"] ||
        parsed_error["error"] ||
        body.strip

      errors << if message.to_s.empty?
                  "#{label}: HTTP #{response.code} com corpo vazio"
                else
                  "#{label}: HTTP #{response.code} — #{message}"
                end
    end

    raise AuthError, "Falha na autenticação XBL. Tentativas: #{errors.join(' | ')}"
  end

  # ---------------------------------------------------------------------------
  # Passo 3: XBL Token → XSTS Token.
  #
  # Java/Minecraft Services:
  #   relying_party padrão: "rp://api.minecraftservices.com/"
  #
  # Bedrock/Xbox Profile:
  #   usar: "http://xboxlive.com"
  # ---------------------------------------------------------------------------
  def self.authenticate_xsts(xbl_token, relying_party = "rp://api.minecraftservices.com/")
    response = HTTParty.post(
      XSTS_AUTH_URL,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      },
      body: {
        Properties: {
          SandboxId: "RETAIL",
          UserTokens: [xbl_token]
        },
        RelyingParty: relying_party,
        TokenType: "JWT"
      }.to_json
    )

    data = parse_json_response!(response, "Autenticação XSTS")

    if data["XErr"]
      case data["XErr"].to_i
      when 2_148_916_233
        raise AuthError, "Conta Microsoft sem Xbox Live associado. Crie uma conta Xbox em xbox.com."
      when 2_148_916_238
        raise AuthError, "Conta de menor de idade — requer aprovação de conta familiar Xbox."
      else
        raise AuthError, "Erro XSTS (#{data["XErr"]}): #{data["Message"] || "sem mensagem"}"
      end
    end

    unless response.success?
      raise AuthError, "Falha XSTS: #{data["Message"] || data["error_description"] || response.body}"
    end

    token = data["Token"]
    user_hash = data.dig("DisplayClaims", "xui", 0, "uhs")

    raise AuthError, "Autenticação XSTS não retornou Token." if token.to_s.empty?
    raise AuthError, "Autenticação XSTS não retornou user hash (uhs)." if user_hash.to_s.empty?

    {
      token: token,
      user_hash: user_hash
    }
  end

  # ---------------------------------------------------------------------------
  # Passo 4: XSTS → Minecraft Bearer Token.
  # ---------------------------------------------------------------------------
  def self.authenticate_minecraft(xsts_token, user_hash)
    response = HTTParty.post(
      MC_AUTH_URL,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      },
      body: {
        identityToken: "XBL3.0 x=#{user_hash};#{xsts_token}"
      }.to_json
    )

    data = parse_json_response!(response, "Autenticação Minecraft")

    unless response.success?
      raise AuthError, "Falha na autenticação Minecraft: #{data["errorMessage"] || data["error"] || response.body}"
    end

    access_token = data["access_token"]
    raise AuthError, "Autenticação Minecraft não retornou access_token." if access_token.to_s.empty?

    {
      access_token: access_token,
      expires_in: data["expires_in"].to_i
    }
  end

  # ---------------------------------------------------------------------------
  # Passo 5: Busca o perfil Minecraft Java (UUID + username).
  # ---------------------------------------------------------------------------
  def self.fetch_profile(mc_access_token)
    response = HTTParty.get(
      MC_PROFILE_URL,
      headers: {
        "Authorization" => "Bearer #{mc_access_token}",
        "Accept" => "application/json"
      }
    )

    if response.code.to_i == 404
      raise AuthError, "Perfil não encontrado — conta não possui Minecraft Java Edition. Use login Bedrock se essa conta não tem Java."
    end

    data = parse_json_response!(response, "Perfil Minecraft")

    unless response.success?
      raise AuthError, "Falha ao buscar perfil Minecraft: #{data["errorMessage"] || data["error"] || response.body}"
    end

    uuid = data["id"]
    username = data["name"]

    raise AuthError, "Perfil Minecraft não retornou UUID." if uuid.to_s.empty?
    raise AuthError, "Perfil Minecraft não retornou username." if username.to_s.empty?

    {
      uuid: uuid,
      username: username
    }
  end

  # ---------------------------------------------------------------------------
  # Passo 5b (Bedrock): XSTS → Perfil Xbox (gamertag + xuid).
  # ---------------------------------------------------------------------------
  def self.fetch_xbox_profile(xsts_token, user_hash)
    response = HTTParty.get(
      XBOX_PROFILE_URL,
      headers: {
        "Authorization" => "XBL3.0 x=#{user_hash};#{xsts_token}",
        "x-xbl-contract-version" => "2",
        "Accept" => "application/json"
      },
      query: {
        settings: "Gamertag,GameDisplayName,PublicGamerpic,Gamerscore"
      }
    )

    data = parse_json_response!(response, "Perfil Xbox")

    unless response.success?
      raise AuthError, "Falha ao buscar perfil Xbox: #{data["Message"] || data["error"] || response.body}"
    end

    profile_user = data["profileUsers"]&.first
    settings = profile_user&.dig("settings") || []

    gamertag =
      settings.find { |setting| setting["id"] == "Gamertag" }&.dig("value") ||
      settings.find { |setting| setting["id"] == "GameDisplayName" }&.dig("value") ||
      "Unknown"

    xuid = profile_user&.dig("id") || SecureRandom.uuid

    {
      username: gamertag,
      uuid: xuid
    }
  end

  # ---------------------------------------------------------------------------
  # Fluxo COMPLETO Bedrock: Microsoft Token → Perfil Xbox.
  # ---------------------------------------------------------------------------
  def self.full_bedrock_flow(ms_access_token)
    xbl = authenticate_xbl(ms_access_token)

    # Para Xbox Profile API, o XSTS precisa ser emitido para http://xboxlive.com.
    xsts = authenticate_xsts(xbl[:token], "http://xboxlive.com")
    profile = fetch_xbox_profile(xsts[:token], xsts[:user_hash])

    {
      mc_access_token: xsts[:token],
      mc_expires_in: 86_400,
      uuid: profile[:uuid],
      username: profile[:username]
    }
  end

  # ---------------------------------------------------------------------------
  # Fluxo COMPLETO Java: Microsoft Token → Perfil Minecraft.
  # ---------------------------------------------------------------------------
  def self.full_auth_flow(ms_access_token)
    xbl = authenticate_xbl(ms_access_token)
    xsts = authenticate_xsts(xbl[:token])
    mc = authenticate_minecraft(xsts[:token], xsts[:user_hash])
    profile = fetch_profile(mc[:access_token])

    {
      mc_access_token: mc[:access_token],
      mc_expires_in: mc[:expires_in],
      uuid: profile[:uuid],
      username: profile[:username]
    }
  end
end