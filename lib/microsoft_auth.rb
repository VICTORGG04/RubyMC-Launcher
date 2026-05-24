# frozen_string_literal: true

require "httparty"
require "json"

# =============================================================================
# MicrosoftAuth — Autenticação completa Microsoft → Xbox → Minecraft
#
# Fluxo:
#   1. Device Code Flow (sem servidor local, sem redirect URI)
#   2. Microsoft Access Token
#   3. Xbox Live Token (XBL)
#   4. XSTS Token
#   5. Minecraft Bearer Token
#   6. Perfil Minecraft (UUID + username)
# =============================================================================
module MicrosoftAuth
  # Client ID do aplicativo Azure AD público da Microsoft
  # Este é o Client ID oficial usado pelo launcher do Minecraft (público/open)
  CLIENT_ID = "00000000402b5328"

  # Escopos necessários para autenticação Xbox Live
  SCOPE = "service::user.auth.xboxlive.com::MBI_SSL"

  # Endpoints
  DEVICE_CODE_URL  = "https://login.live.com/oauth20_connect.srf"
  TOKEN_URL        = "https://login.live.com/oauth20_token.srf"
  XBL_AUTH_URL     = "https://user.auth.xboxlive.com/user/authenticate"
  XSTS_AUTH_URL    = "https://xsts.auth.xboxlive.com/xsts/authorize"
  MC_AUTH_URL      = "https://api.minecraftservices.com/authentication/login_with_xbox"
  MC_PROFILE_URL   = "https://api.minecraftservices.com/minecraft/profile"

  # ---------------------------------------------------------------------------
  # Inicia o Device Code Flow
  # Retorna: { device_code:, user_code:, verification_uri:, interval:, expires_in: }
  # ---------------------------------------------------------------------------
  def self.request_device_code
    response = HTTParty.post(
      DEVICE_CODE_URL,
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: URI.encode_www_form(
        client_id:  CLIENT_ID,
        scope:      SCOPE,
        response_type: "device_code"
      )
    )

    raise AuthError, "Falha ao obter device code: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    {
      device_code:      data["device_code"],
      user_code:        data["user_code"],
      verification_uri: data["verification_uri"],
      interval:         (data["interval"] || 5).to_i,
      expires_in:       (data["expires_in"] || 900).to_i
    }
  end

  # ---------------------------------------------------------------------------
  # Polling: aguarda o usuário fazer login no navegador
  # Retorna o Microsoft Access Token quando aprovado
  # ---------------------------------------------------------------------------
  def self.poll_for_token(device_code:, interval:, expires_in:, &on_waiting)
    deadline = Time.now + expires_in

    loop do
      raise AuthError, "Tempo de login expirado. Tente novamente." if Time.now > deadline

      sleep(interval)

      response = HTTParty.post(
        TOKEN_URL,
        headers: { "Content-Type" => "application/x-www-form-urlencoded" },
        body: URI.encode_www_form(
          client_id:   CLIENT_ID,
          grant_type:  "urn:ietf:params:oauth:grant-type:device_code",
          device_code: device_code
        )
      )

      data = JSON.parse(response.body)

      case data["error"]
      when nil
        # Sucesso!
        return {
          access_token:  data["access_token"],
          refresh_token: data["refresh_token"],
          expires_in:    data["expires_in"].to_i
        }
      when "authorization_pending"
        on_waiting&.call
        next
      when "authorization_declined"
        raise AuthError, "Login recusado pelo usuário."
      when "expired_token"
        raise AuthError, "Código expirado. Reinicie o processo."
      else
        raise AuthError, "Erro inesperado: #{data["error_description"]}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Renova o Access Token usando o Refresh Token salvo
  # ---------------------------------------------------------------------------
  def self.refresh_token(refresh_token)
    response = HTTParty.post(
      TOKEN_URL,
      headers: { "Content-Type" => "application/x-www-form-urlencoded" },
      body: URI.encode_www_form(
        client_id:     CLIENT_ID,
        grant_type:    "refresh_token",
        refresh_token: refresh_token,
        scope:         SCOPE
      )
    )

    raise AuthError, "Falha ao renovar token: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    {
      access_token:  data["access_token"],
      refresh_token: data["refresh_token"],
      expires_in:    data["expires_in"].to_i
    }
  end

  # ---------------------------------------------------------------------------
  # Passo 2: Microsoft Token → Xbox Live Token (XBL)
  # ---------------------------------------------------------------------------
  def self.authenticate_xbl(ms_access_token)
    response = HTTParty.post(
      XBL_AUTH_URL,
      headers: {
        "Content-Type" => "application/json",
        "Accept"       => "application/json"
      },
      body: {
        Properties: {
          AuthMethod: "RPS",
          SiteName:   "user.auth.xboxlive.com",
          RpsTicket:  ms_access_token
        },
        RelyingParty: "http://auth.xboxlive.com",
        TokenType:    "JWT"
      }.to_json
    )

    raise AuthError, "Falha na autenticação XBL: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    {
      token:       data["Token"],
      user_hash:   data.dig("DisplayClaims", "xui", 0, "uhs")
    }
  end

  # ---------------------------------------------------------------------------
  # Passo 3: XBL Token → XSTS Token
  # ---------------------------------------------------------------------------
  def self.authenticate_xsts(xbl_token)
    response = HTTParty.post(
      XSTS_AUTH_URL,
      headers: {
        "Content-Type" => "application/json",
        "Accept"       => "application/json"
      },
      body: {
        Properties: {
          SandboxId:  "RETAIL",
          UserTokens: [xbl_token]
        },
        RelyingParty: "rp://api.minecraftservices.com/",
        TokenType:    "JWT"
      }.to_json
    )

    data = JSON.parse(response.body)

    # Erros conhecidos XSTS
    if data["XErr"]
      case data["XErr"]
      when 2148916233
        raise AuthError, "Conta Microsoft sem Xbox Live associado. Crie uma conta Xbox em xbox.com."
      when 2148916238
        raise AuthError, "Conta de menor de idade — requer aprovação de conta familiar Xbox."
      else
        raise AuthError, "Erro XSTS (#{data["XErr"]}): #{data["Message"]}"
      end
    end

    raise AuthError, "Falha XSTS: #{response.body}" unless response.success?

    {
      token:     data["Token"],
      user_hash: data.dig("DisplayClaims", "xui", 0, "uhs")
    }
  end

  # ---------------------------------------------------------------------------
  # Passo 4: XSTS → Minecraft Bearer Token
  # ---------------------------------------------------------------------------
  def self.authenticate_minecraft(xsts_token, user_hash)
    response = HTTParty.post(
      MC_AUTH_URL,
      headers: {
        "Content-Type" => "application/json",
        "Accept"       => "application/json"
      },
      body: {
        identityToken: "XBL3.0 x=#{user_hash};#{xsts_token}"
      }.to_json
    )

    raise AuthError, "Falha na autenticação Minecraft: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    {
      access_token: data["access_token"],
      expires_in:   data["expires_in"].to_i
    }
  end

  # ---------------------------------------------------------------------------
  # Passo 5: Busca o perfil Minecraft (UUID + username)
  # ---------------------------------------------------------------------------
  def self.fetch_profile(mc_access_token)
    response = HTTParty.get(
      MC_PROFILE_URL,
      headers: {
        "Authorization" => "Bearer #{mc_access_token}"
      }
    )

    raise AuthError, "Perfil não encontrado — conta não possui Minecraft Java Edition." if response.code == 404
    raise AuthError, "Falha ao buscar perfil: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    {
      uuid:     data["id"],
      username: data["name"]
    }
  end

  # ---------------------------------------------------------------------------
  # Fluxo COMPLETO: Microsoft Token → Perfil Minecraft
  # Retorna tudo que o launcher precisa
  # ---------------------------------------------------------------------------
  def self.full_auth_flow(ms_access_token)
    xbl  = authenticate_xbl(ms_access_token)
    xsts = authenticate_xsts(xbl[:token])
    mc   = authenticate_minecraft(xsts[:token], xsts[:user_hash])
    profile = fetch_profile(mc[:access_token])

    {
      mc_access_token: mc[:access_token],
      mc_expires_in:   mc[:expires_in],
      uuid:            profile[:uuid],
      username:        profile[:username]
    }
  end

  # ---------------------------------------------------------------------------
  # Erro customizado de autenticação
  # ---------------------------------------------------------------------------
  class AuthError < StandardError; end
end
