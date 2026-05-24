# frozen_string_literal: true

require "httparty"
require "json"

# =============================================================================
# MicrosoftAuth — OAuth 2.0 Device Code Flow
# Microsoft → Xbox Live (XBL) → XSTS → Minecraft Bearer Token → Perfil
# =============================================================================
module MicrosoftAuth
  CLIENT_ID        = "00000000402b5328"
  SCOPE            = "service::user.auth.xboxlive.com::MBI_SSL"
  DEVICE_CODE_URL  = "https://login.live.com/oauth20_connect.srf"
  TOKEN_URL        = "https://login.live.com/oauth20_token.srf"
  XBL_AUTH_URL     = "https://user.auth.xboxlive.com/user/authenticate"
  XSTS_AUTH_URL    = "https://xsts.auth.xboxlive.com/xsts/authorize"
  MC_AUTH_URL      = "https://api.minecraftservices.com/authentication/login_with_xbox"
  MC_PROFILE_URL   = "https://api.minecraftservices.com/minecraft/profile"

  # Device Code — primeiro passo do login
  def self.request_device_code
    res = HTTParty.post(DEVICE_CODE_URL,
                        headers: { "Content-Type" => "application/x-www-form-urlencoded" },
                        body: URI.encode_www_form(client_id: CLIENT_ID, scope: SCOPE, response_type: "device_code")
    )
    raise AuthError, "Falha ao obter device code: #{res.body}" unless res.success?
    d = JSON.parse(res.body)
    { device_code: d["device_code"], user_code: d["user_code"],
      verification_uri: d["verification_uri"],
      interval: (d["interval"] || 5).to_i, expires_in: (d["expires_in"] || 900).to_i }
  end

  # Polling até o usuário confirmar no navegador
  def self.poll_for_token(device_code:, interval:, expires_in:, &on_waiting)
    deadline = Time.now + expires_in
    loop do
      raise AuthError, "Tempo de login expirado." if Time.now > deadline
      sleep(interval)
      res  = HTTParty.post(TOKEN_URL,
                           headers: { "Content-Type" => "application/x-www-form-urlencoded" },
                           body: URI.encode_www_form(client_id: CLIENT_ID,
                                                     grant_type: "urn:ietf:params:oauth:grant-type:device_code", device_code: device_code)
      )
      data = JSON.parse(res.body)
      case data["error"]
      when nil
        return { access_token: data["access_token"], refresh_token: data["refresh_token"],
                 expires_in: data["expires_in"].to_i }
      when "authorization_pending" then on_waiting&.call; next
      when "authorization_declined" then raise AuthError, "Login recusado."
      when "expired_token"          then raise AuthError, "Código expirado."
      else raise AuthError, "Erro: #{data["error_description"]}"
      end
    end
  end

  # Renovar via refresh token
  def self.refresh_token(refresh_token)
    res = HTTParty.post(TOKEN_URL,
                        headers: { "Content-Type" => "application/x-www-form-urlencoded" },
                        body: URI.encode_www_form(client_id: CLIENT_ID, grant_type: "refresh_token",
                                                  refresh_token: refresh_token, scope: SCOPE)
    )
    raise AuthError, "Falha ao renovar: #{res.body}" unless res.success?
    d = JSON.parse(res.body)
    { access_token: d["access_token"], refresh_token: d["refresh_token"], expires_in: d["expires_in"].to_i }
  end

  # XBL
  def self.authenticate_xbl(ms_token)
    res = HTTParty.post(XBL_AUTH_URL,
                        headers: { "Content-Type" => "application/json", "Accept" => "application/json" },
                        body: { Properties: { AuthMethod: "RPS", SiteName: "user.auth.xboxlive.com",
                                              RpsTicket: ms_token },
                                RelyingParty: "http://auth.xboxlive.com", TokenType: "JWT" }.to_json
    )
    raise AuthError, "Falha XBL: #{res.body}" unless res.success?
    d = JSON.parse(res.body)
    { token: d["Token"], user_hash: d.dig("DisplayClaims", "xui", 0, "uhs") }
  end

  # XSTS
  def self.authenticate_xsts(xbl_token)
    res = HTTParty.post(XSTS_AUTH_URL,
                        headers: { "Content-Type" => "application/json", "Accept" => "application/json" },
                        body: { Properties: { SandboxId: "RETAIL", UserTokens: [xbl_token] },
                                RelyingParty: "rp://api.minecraftservices.com/", TokenType: "JWT" }.to_json
    )
    d = JSON.parse(res.body)
    if d["XErr"]
      case d["XErr"]
      when 2148916233 then raise AuthError, "Conta sem Xbox Live. Crie em xbox.com."
      when 2148916238 then raise AuthError, "Conta de menor — requer aprovação familiar."
      else raise AuthError, "Erro XSTS #{d["XErr"]}: #{d["Message"]}"
      end
    end
    raise AuthError, "Falha XSTS: #{res.body}" unless res.success?
    { token: d["Token"], user_hash: d.dig("DisplayClaims", "xui", 0, "uhs") }
  end

  # Minecraft token
  def self.authenticate_minecraft(xsts_token, user_hash)
    res = HTTParty.post(MC_AUTH_URL,
                        headers: { "Content-Type" => "application/json", "Accept" => "application/json" },
                        body: { identityToken: "XBL3.0 x=#{user_hash};#{xsts_token}" }.to_json
    )
    raise AuthError, "Falha MC auth: #{res.body}" unless res.success?
    d = JSON.parse(res.body)
    { access_token: d["access_token"], expires_in: d["expires_in"].to_i }
  end

  # Perfil Minecraft
  def self.fetch_profile(mc_token)
    res = HTTParty.get(MC_PROFILE_URL, headers: { "Authorization" => "Bearer #{mc_token}" })
    raise AuthError, "Conta sem Minecraft Java Edition." if res.code == 404
    raise AuthError, "Falha no perfil: #{res.body}" unless res.success?
    d = JSON.parse(res.body)
    { uuid: d["id"], username: d["name"] }
  end

  # Fluxo completo: MS token → tudo
  def self.full_auth_flow(ms_access_token)
    xbl     = authenticate_xbl(ms_access_token)
    xsts    = authenticate_xsts(xbl[:token])
    mc      = authenticate_minecraft(xsts[:token], xsts[:user_hash])
    profile = fetch_profile(mc[:access_token])
    { mc_access_token: mc[:access_token], mc_expires_in: mc[:expires_in],
      uuid: profile[:uuid], username: profile[:username] }
  end

  class AuthError < StandardError; end
end