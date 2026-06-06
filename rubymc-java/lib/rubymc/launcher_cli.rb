# frozen_string_literal: true

require "tty-prompt"
require "tty-spinner"
require "tty-box"
require "pastel"
require "securerandom"
require "yaml"

require_relative "microsoft_auth"
require_relative "minecraft_manager"
require_relative "../account_bank"
require_relative "auto_updater"
require_relative "../discord_integration"

class LauncherCLI
  def initialize
    @prompt           = TTY::Prompt.new(interrupt: :exit)
    @pastel           = Pastel.new
    @bank             = AccountBank.new
    @config           = YAML.load_file(File.join(__dir__, "../config/settings.yml")) rescue {}
    @discord          = DiscordIntegration::Manager.new(@config)
    @minecraft        = MinecraftManager.new
    @selected_version = nil
    @current_user     = nil
    @discord_target   = nil
  end

  def run
    show_welcome_banner
    @discord.start_async

    @selected_version = select_minecraft_version
    @current_user     = handle_authentication_flow
    @discord_target   = collect_discord_target

    launch_game
  end

  private

  # ---------------------------------------------------------------------------
  # Banner de boas-vindas
  # ---------------------------------------------------------------------------
  def show_welcome_banner
    box = TTY::Box.frame(
      width: 50,
      height: 5,
      align: :center,
      border: :thick,
      style: { border: { fg: :green } }
    ) do
      "MINECRAFT RUBY LAUNCHER\n#{@pastel.dim('Versão 1.0.0 — Puro Ruby')}"
    end
    puts box
  end

  # ---------------------------------------------------------------------------
  # Seleção de versão
  # ---------------------------------------------------------------------------
  def select_minecraft_version
    if @discord.presence_connected?
      @discord.presence.update(state: "Escolhendo versão...", details: "No Menu")
    end

    local_versions = @minecraft.list_local_versions
    choices = {}

    local_versions.each { |v| choices["#{v} (Instalada localmente)"] = v }
    choices["✨ Baixar última versão estável oficial"] = :latest
    choices["🔍 Digitar uma versão específica (ex: 1.20.4)"] = :custom

    answer = @prompt.select("Escolha a versão do Minecraft que deseja jogar:", choices)

    case answer
    when :latest
      spinner = TTY::Spinner.new("[:spinner] Buscando última versão na Mojang...", format: :dots)
      spinner.auto_spin
      version = AutoUpdater.new(@config).latest_minecraft_version || "1.20.4"
      spinner.success("(Disponível: #{version})")
      version
    when :custom
      @prompt.ask("Digite o ID exato da versão (ex: 1.16.5):") do |q|
        q.required true
        q.modify :strip
      end
    else
      answer
    end
  end

  # ---------------------------------------------------------------------------
  # Fluxo de autenticação
  # ---------------------------------------------------------------------------
  def handle_authentication_flow
    if @config.dig("launcher", "offline_mode") == true
      return setup_offline_session
    end

    choices = {}

    unless @bank.empty?
      @bank.all.each do |acc|
        choices["👤 Jogar como #{acc[:username]} (#{acc[:email]})"] = { type: :saved, data: acc }
      end
    end

    choices["🔑 Adicionar nova conta Microsoft (Online)"] = { type: :new_ms }
    choices["🔌 Jogar Offline (Sem conta / Pirata)"]      = { type: :offline }

    action = @prompt.select("Como você deseja entrar no jogo?", choices)

    case action[:type]
    when :saved   then auth_saved_account(action[:data])
    when :new_ms  then auth_new_microsoft_account
    when :offline then setup_offline_session
    end
  end

  # Conta já salva — renova tokens se necessário
  def auth_saved_account(account)
    if @bank.mc_token_valid?(account)
      @bank.touch(account[:email])
      puts @pastel.green("✔ Sessão local válida para #{account[:username]}!")
      return account
    end

    spinner = TTY::Spinner.new("[:spinner] Renovando sessão com a Microsoft...", format: :dots)
    spinner.auto_spin

    begin
      # Renova o MS token via refresh_token
      ms = MicrosoftAuth.refresh_token(account[:ms_refresh_token])
      # Refaz o fluxo Xbox/Minecraft com o novo MS token
      mc = MicrosoftAuth.full_auth_flow(ms[:access_token])

      updated = @bank.update_tokens(
        email:            account[:email],
        ms_access_token:  ms[:access_token],
        ms_refresh_token: ms[:refresh_token],
        ms_expires_in:    ms[:expires_in],
        mc_access_token:  mc[:mc_access_token],
        mc_expires_in:    mc[:mc_expires_in],
        username:         mc[:username],
        uuid:             mc[:uuid]
      )
      spinner.success("(Sessão renovada!)")
      updated
    rescue MicrosoftAuth::AuthError => e
      spinner.error("(Falha: #{e.message})")
      puts @pastel.red("Sessão expirou. Faça login novamente.")
      auth_new_microsoft_account
    end
  end

  # Login completo via Microsoft Device Code Flow
  def auth_new_microsoft_account
    device = MicrosoftAuth.request_device_code

    puts "\n"
    puts TTY::Box.frame(
      width: 60,
      align: :center,
      border: :light,
      style: { border: { fg: :yellow } }
    ) do
      "Acesse: #{device[:verification_uri]}\n" \
        "Digite o código: #{@pastel.bold(device[:user_code])}"
    end
    puts "\n"

    spinner = TTY::Spinner.new("[:spinner] Aguardando aprovação no navegador...", format: :dots)
    spinner.auto_spin

    begin
      ms = MicrosoftAuth.poll_for_token(
        device_code: device[:device_code],
        interval:    device[:interval],
        expires_in:  device[:expires_in]
      ) { }  # bloco vazio — o spinner já indica a espera

      mc = MicrosoftAuth.full_auth_flow(ms[:access_token])
      spinner.success("(Autenticado com sucesso!)")

      email = @prompt.ask("Digite o e-mail da conta para identificação local:") do |q|
        q.required true
        q.validate(/\A[^@\s]+@[^@\s]+\z/, "E-mail inválido")
      end

      @bank.save_account(
        email:            email,
        username:         mc[:username],
        uuid:             mc[:uuid],
        ms_access_token:  ms[:access_token],
        ms_refresh_token: ms[:refresh_token],
        ms_expires_in:    ms[:expires_in],
        mc_access_token:  mc[:mc_access_token],
        mc_expires_in:    mc[:mc_expires_in]
      )
    rescue MicrosoftAuth::AuthError => e
      spinner.error("(#{e.message})")
      exit(1)
    end
  end

  # Sessão offline / pirata
  def setup_offline_session
    username = @config.dig("launcher", "offline_username").to_s.strip
    if username.empty?
      username = @prompt.ask("Digite o apelido (Username) para o jogo:") do |q|
        q.required true
        q.modify :strip
        q.validate(/\A\w{3,16}\z/, "Nome deve ter 3–16 caracteres (letras, números, _)")
      end
    end

    {
      username:        username,
      uuid:            SecureRandom.uuid.gsub("-", ""),
      mc_access_token: "0",
      is_offline:      true
    }
  end

  # ---------------------------------------------------------------------------
  # Usuário Discord para envio do convite por DM
  # ---------------------------------------------------------------------------
  def collect_discord_target
    return nil unless @discord.bot.enabled?

    existing_id   = @current_user[:discord_user_id].to_s
    existing_name = @current_user[:discord_username].to_s

    if valid_discord_user_id?(existing_id)
      label = existing_name.empty? ? existing_id : "#{existing_name} (#{existing_id})"
      choice = @prompt.select("Enviar convite Discord para qual usuário?", {
        "Usar #{label}" => :use_existing,
        "Informar outro usuário Discord" => :change,
        "Gerar link para enviar manualmente" => :manual,
        "Não enviar DM agora" => :skip
      })
      return build_discord_target(existing_id, existing_name) if choice == :use_existing
      return build_manual_discord_target if choice == :manual
      return nil if choice == :skip
    else
      choice = @prompt.select("Como deseja convidar o usuário para o Discord?", {
        "Enviar DM usando ID/menção Discord" => :dm,
        "Gerar link para enviar manualmente" => :manual,
        "Não usar Discord agora" => :skip
      })
      return build_manual_discord_target if choice == :manual
      return nil if choice == :skip
    end

    user_id = ask_discord_user_id
    return nil unless user_id

    username = @prompt.ask("Nome do usuário Discord para identificação local (opcional):") do |q|
      q.modify :strip
    end

    persist_discord_target(user_id, username)
    build_discord_target(user_id, username)
  end

  def build_manual_discord_target
    username = @prompt.ask("Nome do usuário Discord para identificação local (opcional):") do |q|
      q.modify :strip
    end

    {
      mode: :manual,
      username: username.to_s.empty? ? nil : username
    }
  end

  def ask_discord_user_id
    answer = @prompt.ask("ID do usuário Discord ou menção <@id>:") do |q|
      q.required true
      q.modify :strip
      q.validate(->(value) { valid_discord_user_id?(extract_discord_user_id(value)) },
                 "Informe um ID Discord válido, com 17 a 20 dígitos.")
    end
    extract_discord_user_id(answer)
  end

  def persist_discord_target(user_id, username)
    email = @current_user[:email].to_s
    return if email.empty?

    updated = @bank.update_discord_user(
      email: email,
      discord_user_id: user_id,
      discord_username: username.to_s.empty? ? nil : username
    )
    @current_user = updated if updated
  end

  def build_discord_target(user_id, username)
    {
      mode: :dm,
      user_id: user_id,
      username: username.to_s.empty? ? nil : username
    }
  end

  def extract_discord_user_id(value)
    DiscordIntegration::Bot.extract_user_id(value)
  end

  def valid_discord_user_id?(value)
    value.to_s.match?(/\A\d{17,20}\z/)
  end

  # ---------------------------------------------------------------------------
  # Lançamento do jogo
  # ---------------------------------------------------------------------------
  def launch_game
    ram = @prompt.slider(
      "Aloque a memória RAM máxima para o Minecraft (GB):",
      min: 2, max: 16, step: 1, default: 4
    )

    puts "\n #{@pastel.cyan('Preparando ambiente para inicialização...')}"

    @minecraft.ensure_version_dependencies(@selected_version)

    @discord.on_game_start(
      username: @current_user[:username],
      version:  @selected_version,
      server:   @current_user[:is_offline] ? "Modo Offline" : nil
    )

    if @discord_target&.dig(:mode) == :manual
      result = @discord.create_server_invite
      if result[:success]
        target = @discord_target[:username] ? " para #{@discord_target[:username]}" : ""
        puts @pastel.dim("  \u2192 Link de convite Discord#{target}: #{result[:url]}")
      else
        puts @pastel.dim("  \u2192 Discord: #{result[:reason]}")
      end
    elsif @discord_target || !@current_user[:is_offline]
      result = @discord.invite_to_server(
        username:         @current_user[:username],
        version:          @selected_version,
        server_address:   @config.dig("discord", "server_address"),
        discord_user_id:  @discord_target&.dig(:user_id),
        discord_username: @discord_target&.dig(:username)
      )
      if result[:success]
        if result[:delivery] == :dm
          puts @pastel.dim("  \u2192 Convite enviado no Discord para <@#{result[:discord_user_id]}>.")
        else
          puts @pastel.dim("  \u2192 Convite postado no canal Discord.")
        end
      else
        puts @pastel.dim("  \u2192 Discord: #{result[:reason]}")
      end
    end

    puts @pastel.green("🚀 Iniciando o Minecraft #{@selected_version}. Bom jogo!")
    @discord.stop if @current_user[:is_offline]

    @minecraft.execute_launch(
      version:  @selected_version,
      username: @current_user[:username],
      uuid:     @current_user[:uuid],
      token:    @current_user[:mc_access_token],
      ram_gb:   ram
    )
  end
end
