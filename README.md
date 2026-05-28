# RubyMC Launcher

<p align="center">
  <strong>RubyMC Launcher</strong><br>
  Ecossistema Ruby para gerenciamento de servidores Minecraft Java e Minecraft Bedrock Dedicated Server.
</p>

<p align="center">
  <a href="#visão-geral">Visão geral</a> •
  <a href="#rubymc-java">RubyMC Java</a> •
  <a href="#rubymc-bedrock-bds">RubyMC Bedrock</a> •
  <a href="#discord">Discord</a> •
  <a href="#ia-local">IA Local</a> •
  <a href="#instalação">Instalação</a>
</p>

---

## Visão geral

O **RubyMC Launcher** é um projeto organizado em dois ambientes principais:

1. **RubyMC Java** — launcher voltado para Minecraft Java, com interface web, modpacks, Discord, display de logs, configurações e suporte com IA local.
2. **RubyMC Bedrock BDS** — gerenciador dedicado ao **Minecraft Bedrock Dedicated Server**, com instalação de versões, controle de instâncias, conexão UDP, monitor ativo e painel operacional.

A proposta é manter uma base visual e técnica RubyMC para os dois modelos, usando Ruby no backend e uma interface web moderna em estilo dark/neon.

---

## Estrutura do repositório

```text
RubyMC-Launcher/
├── README.md
├── docs/
│   └── assets/
│       └── bedrock/
├── rubymc-java/
│   ├── bot_daemon.rb
│   ├── launcher.rb
│   ├── launcher_gui.rb
│   ├── config/
│   ├── lib/
│   ├── scripts/
│   └── web/
├── rubymc-bedrock/
│   ├── README.md
│   ├── config/
│   ├── lib/
│   ├── scripts/
│   ├── web/
│   └── docs/
└── scripts/
```

---

# RubyMC Java

O **RubyMC Java** é o modelo voltado para a experiência tradicional de launcher Minecraft.

## Recursos

- Painel web do launcher.
- Gerenciamento de perfis.
- Sistema de modpacks.
- Integração Discord.
- Rich Presence.
- Display interno de logs.
- Configurações gerais.
- Suporte com IA local via Ollama.
- Organização de scripts e documentação.

## Páginas principais

```text
RubyMC Java
├── Início
├── Modpacks
├── Servidor
├── Discord
├── Display
├── Projeto
└── Configurações
```

## Modpacks

O sistema de modpacks foi pensado para trabalhar com arquivos:

- `.mrpack`
- `.zip`

Fluxo esperado:

```text
Selecionar arquivo
→ Validar formato
→ Importar para pasta local
→ Criar perfil
→ Atualizar lista
→ Jogar com o perfil
```

## Discord no modelo Java

O painel Discord pode validar configurações, testar canal de logs, exibir status do bot e preparar integração com suporte por IA.

## IA no modelo Java

A IA local pode auxiliar com:

- explicação de erros;
- leitura de logs;
- orientação de instalação;
- suporte técnico;
- respostas para dúvidas do projeto.

---

# RubyMC Bedrock BDS

O **RubyMC Bedrock BDS** é o gerenciador operacional do **Minecraft Bedrock Dedicated Server** para Linux.

## Recursos

- Instalação de versões oficiais BDS.
- Listagem de versões instaladas.
- Inicialização de servidor.
- Parada de servidor.
- Reinício de instância.
- Abertura de logs.
- Remoção de instância.
- Validação de conexão UDP.
- Monitor ativo com PID.
- Link de entrada da comunidade.
- Mapeamento de diretórios físicos.

---

## Screenshots do RubyMC Bedrock BDS

### Início

![RubyMC Bedrock BDS - Início](docs/assets/bedrock/bedrock-home-panel.png)

### Servidor BDS

![RubyMC Bedrock BDS - Servidor](docs/assets/bedrock/bedrock-server-panel.png)

### Versões BDS

![RubyMC Bedrock BDS - Versões](docs/assets/bedrock/bedrock-versions-panel.png)

### Display

![RubyMC Bedrock BDS - Display](docs/assets/bedrock/bedrock-display-panel.png)

### Projeto

![RubyMC Bedrock BDS - Projeto](docs/assets/bedrock/bedrock-project-panel.png)

### Configurações

![RubyMC Bedrock BDS - Configurações](docs/assets/bedrock/bedrock-settings-panel.png)

---

## Páginas do Bedrock

### Início

Apresenta o ambiente Bedrock, status do processo, versão ativa e atalhos para atualizar status ou gerenciar o servidor.

### Servidor BDS

Controla a conexão UDP, endereço IP/porta, validação real do BDS, monitor ativo e instâncias disponíveis.

Ações por instância:

```text
Iniciar
Parar
Reiniciar
Logs
Remover
```

### Versões BDS

Permite carregar versões, instalar versões oficiais, atualizar lista, selecionar versão mais recente e administrar diretórios físicos.

### Display

Console de eventos em tempo real para acompanhar comandos, mensagens internas, erros e logs operacionais.

### Projeto

Área para acessar a raiz operacional, subpastas e binários executáveis nativos do BDS Linux.

### Configurações

Mostra ambiente, gerenciador core, binários do servidor, conexão de clientes e link de entrada da comunidade.

---

## Estrutura de instâncias Bedrock

```text
~/.minecraft_ruby_launcher/
└── bedrock_servers/
    ├── 1.26.23/
    ├── 1.26.23.1/
    └── 1.21.101.1/
```

Cada instância pode conter:

```text
bedrock_server
server.properties
permissions.json
allowlist.json
worlds/
logs/
```

---

## Conexão UDP

O Minecraft Bedrock usa UDP.

Exemplo:

```text
192.168.0.9:19132
```

Campos monitorados:

```text
ONLINE
CAPACIDADE
PING
VERSÃO
CHECK
```

Erros como `NetworkError when attempting to fetch resource` normalmente indicam falha entre frontend/backend, rota indisponível, bloqueio de rede ou API local indisponível.

---

# Discord

O projeto usa configuração por `settings.yml`.

```yaml
discord:
  rich_presence: true
  client_id: 'ID_DA_APLICACAO'
  bot_enabled: true
  bot_token: '${RUBYMC_DISCORD_BOT_TOKEN}'
  guild_id: 'ID_DO_SERVIDOR_DISCORD'

  channels:
    welcome_channel_id: '...'
    rules_channel_id: '...'
    announcements_channel_id: '...'
    updates_channel_id: '...'
    new_members_channel_id: '...'
    general_channel_id: '...'
    support_channel_id: '...'
    logs_channel_id: '...'
    modpacks_channel_id: '...'

  roles:
    member_role_id: '...'
    player_role_id: '...'
    staff_role_id: '...'
    admin_role_id: '...'
    bot_role_id: '...'
```

## Token seguro

Nunca publique token real no GitHub.

Use:

```bash
export RUBYMC_DISCORD_BOT_TOKEN='SEU_TOKEN_NOVO_AQUI'
bundle exec ruby bot_daemon.rb
```

---

# IA local

O projeto está preparado para usar IA local com Ollama.

## Modelo

```text
qwen3.5:9b
```

## Instalação

```bash
ollama pull qwen3.5:9b
ollama serve
```

## Configuração

```yaml
ai_support:
  enabled: true
  provider: ollama
  host: 'http://127.0.0.1:11434'
  model: 'qwen3.5:9b'
  model_hash: '6488c96fa5fa'
  timeout_seconds: 120
  temperature: 0.35
  num_ctx: 8192
```

---

# Instalação

```bash
git clone https://github.com/VICTORGG04/RubyMC-Launcher.git
cd RubyMC-Launcher
bundle install
```

---

# Executar RubyMC Java

```bash
cd rubymc-java
bundle install
./rubymc restart
```

Acesse:

```text
http://127.0.0.1:4567
```

---

# Executar RubyMC Bedrock

```bash
cd rubymc-bedrock
bundle install
./rubymc restart
```

Acesse:

```text
http://127.0.0.1:4567
```

Caso a porta esteja ocupada:

```bash
sudo fuser -k 4567/tcp
./rubymc restart
```

---

# Validação

## Ruby

```bash
ruby -c bot_daemon.rb
ruby -c lib/discord_config.rb
ruby -c lib/web_launcher_app.rb
```

## Bundler

```bash
bundle check
```

## Porta do painel

```bash
ss -ltnp | grep 4567
```

## Processos Bedrock

```bash
ps aux | grep bedrock_server
```

## UDP Bedrock

```bash
ss -lunp | grep 19132
```

---

# Boas práticas

- Não versionar tokens reais.
- Não subir `settings.yml` com credenciais.
- Usar variável de ambiente para Discord.
- Manter screenshots em `docs/assets`.
- Separar documentação Java e Bedrock.
- Validar sintaxe Ruby antes de commit.
- Testar painel local antes de publicar.

---

# Status atual

## RubyMC Java

- Interface web em evolução.
- Modpacks em estruturação.
- Discord integrado.
- IA local planejada/implementável.
- Logs e configurações em desenvolvimento.

## RubyMC Bedrock

- Painel BDS funcional.
- Instâncias listadas.
- Monitor ativo.
- Controle iniciar/parar/reiniciar.
- Versões BDS organizadas.
- Display operacional.
- Configurações visuais implementadas.

---

# Roadmap

## Java

- Melhorar sistema de versões.
- Finalizar fluxo de modpacks.
- Integrar IA ao painel.
- Melhorar login e perfis.
- Ampliar suporte Discord.

## Bedrock

- Corrigir carregamento remoto de versões oficiais quando houver falha de rede.
- Melhorar API de status.
- Exibir jogadores online reais.
- Criar backup automático.
- Adicionar agendamento de reinício.
- Permitir edição visual de `server.properties`.
- Integrar alertas Discord.
- Integrar diagnósticos por IA.

---

# Autor

Desenvolvido por **Victor Marcial**.

---

# Licença

Projeto RubyMC. Defina a licença conforme o uso pretendido do repositório.
