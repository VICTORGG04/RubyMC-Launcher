# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'yaml'

module RubyMC
  class AISupportService
    SYSTEM_PROMPT_BASE = <<~PROMPT
      Você é o assistente IA embarcado do RubyMC Launcher, um launcher Minecraft
      de código aberto escrito em Ruby com integração ao Discord.

      # Sobre o RubyMC Launcher
      - Escrito em Ruby 3.2.3, roda em Linux/Windows/macOS
      - Usa WEBrick como servidor web (porta 4567)
      - Integração com Ollama para IA local
      - Bot do Discord com gateway WebSocket para boas-vindas automáticas
      - Autenticação Microsoft OAuth para Minecraft
      - Gerenciamento de modpacks (.mrpack/.zip)
      - Servidor da comunidade Minecraft

      # Estrutura do projeto
      - config/settings.yml — configuração principal (Discord, IA, servidor)
      - lib/ — módulos Ruby (discord, modpacks, IA, auth)
      - web/ — frontend HTML/CSS/JS
      - app/bot.rb — bot Discord WebSocket
      - launcher_gui.rb — servidor web
      - ./rubymc — script CLI (start, stop, status, logs, test, install)

      # Como você deve responder
      - Responda de forma direta e útil em português.
      - Use formatação Markdown quando ajudar (código, listas, negrito).
      - Sugira comandos do projeto quando relevante (./rubymc start, etc).
      - Se não souber a resposta, diga que não tem essa informação.
      - Se o usuário pedir ajuda com Discord, verifique o contexto antes.

      # Comandos úteis do RubyMC
      - ./rubymc start — inicia o servidor web
      - ./rubymc stop — para o servidor
      - ./rubymc status — mostra status do servidor
      - ./rubymc logs — acompanha logs em tempo real
      - ./rubymc test — verifica sintaxe Ruby
      - bundle exec ruby launcher_gui.rb — inicia sem o script
      - bundle exec ruby app/bot.rb — inicia o bot Discord
      - ./rubymc bot start — inicia o bot Discord via CLI
    PROMPT

    def initialize(root:)
      @root = File.expand_path(root)
      @settings = load_ai_settings
    end

    def support_answer(message, context: nil)
      return unavailable_response unless @settings[:enabled]

      full_prompt = build_full_prompt(message, context)

      body = {
        model: @settings[:model],
        prompt: full_prompt,
        stream: false,
        options: {
          temperature: @settings[:temperature],
          num_ctx: @settings[:num_ctx]
        }
      }

      response = ollama_post(body)
      text = response.dig('response').to_s.strip
      return unavailable_response if text.empty?

      { ok: true, answer: text, model: @settings[:model] }
    rescue => e
      { ok: false, answer: "O serviço de IA está temporariamente indisponível: #{e.message}", error: e.message }
    end

    def health
      return { ok: false, enabled: false, message: 'IA desabilitada nas configurações.' } unless @settings[:enabled]

      response = ollama_get('/api/tags')
      raw_models = response.is_a?(Hash) ? (response['models'] || []) : (response.is_a?(Array) ? response : [])
      models = raw_models.map { |m| m['name'].to_s }
      model_available = models.any? { |m| m == @settings[:model] || m.start_with?(@settings[:model].sub(/:.*$/, '') + ':') }

      {
        ok: model_available,
        enabled: true,
        provider: @settings[:provider],
        host: @settings[:host],
        model: @settings[:model],
        model_available: model_available,
        available_models: models,
        message: model_available ? 'Conectado ao Ollama.' : "Modelo #{@settings[:model]} não encontrado no Ollama."
      }
    rescue => e
      { ok: false, enabled: true, message: "Ollama indisponível: #{e.message}", error: e.message }
    end

    private

    def load_ai_settings
      settings_path = File.join(@root, 'config', 'settings.yml')
      data = File.file?(settings_path) ? (YAML.safe_load(File.read(settings_path), permitted_classes: [Symbol], aliases: true) || {}) : {}
      ai = data.fetch('ai_support', {}) || {}
      {
        enabled: ai['enabled'] == true,
        provider: ai['provider'].to_s,
        host: ai['host'].to_s,
        model: ai['model'].to_s,
        timeout: (ai['timeout_seconds'] || 120).to_i,
        temperature: (ai['temperature'] || 0.35).to_f,
        num_ctx: (ai['num_ctx'] || 8192).to_i
      }
    rescue
      { enabled: false, provider: 'ollama', host: 'http://127.0.0.1:11434', model: '', timeout: 120, temperature: 0.35, num_ctx: 8192 }
    end

    def build_full_prompt(message, context)
      parts = []
      parts << SYSTEM_PROMPT_BASE

      if context.is_a?(Hash) && !context.empty?
        ctx_lines = []
        ctx_lines << "\n# Contexto atual do projeto RubyMC\n"

        discord = context['discord'] || context[:discord]
        if discord
          ctx_lines << "## Discord"
          ctx_lines << "- Bot ativo: #{discord['bot_enabled']}"
          ctx_lines << "- Guild configurada: #{discord['guild_id_configured']}"
          ctx_lines << "- Token configurado: #{discord['token_configured']}"
          ctx_lines << "- Canais: #{discord['channels_configured']}/#{discord['channels_total']}"
          ctx_lines << "- Cargos: #{discord['roles_configured']}/#{discord['roles_total']}"
          ctx_lines << "- Logs channel configurado: #{discord['logs_channel_configured']}"
          ctx_lines << ""
        end

        modpacks = context['modpacks'] || context[:modpacks]
        if modpacks.is_a?(Array) && !modpacks.empty?
          ctx_lines << "## Modpacks instalados"
          modpacks.each do |mp|
            name = mp.is_a?(Hash) ? (mp['name'] || mp[:name]) : mp.to_s
            ctx_lines << "- #{name}"
          end
          ctx_lines << ""
        end

        server = context['server'] || context[:server]
        if server
          ctx_lines << "## Servidor da comunidade"
          ctx_lines << "- Endereço: #{server['address'] || server[:address]}"
          ctx_lines << ""
        end

        logs = context['logs'] || context[:logs]
        if logs.is_a?(Array) && !logs.empty?
          ctx_lines << "## Eventos/erros recentes do display"
          logs.last(10).each do |line|
            ctx_lines << "- #{line}"
          end
          ctx_lines << ""
        end

        parts << ctx_lines.join("\n")
      end

      parts << "\n# Pergunta do usuário\n#{message}"
      parts << "\nResponda de forma útil e direta em português."
      parts.join("\n\n")
    end

    def ollama_post(body)
      uri = URI("#{@settings[:host]}/api/generate")
      http = build_http(uri)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)
      response = http.request(request)
      JSON.parse(response.body)
    end

    def ollama_get(path)
      uri = URI("#{@settings[:host]}#{path}")
      http = build_http(uri)
      request = Net::HTTP::Get.new(uri)
      response = http.request(request)
      JSON.parse(response.body)
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = @settings[:timeout]
      http
    end

    def unavailable_response
      { ok: false, answer: 'O serviço de IA não está disponível no momento. Verifique se o Ollama está rodando e se o modelo foi baixado.' }
    end
  end
end
