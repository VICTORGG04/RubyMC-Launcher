# 🎮 Minecraft Ruby Launcher — RubyMC

<div align="center">

![Ruby](https://img.shields.io/badge/Ruby-3.2+-CC342D?style=for-the-badge&logo=ruby&logoColor=white)
![Minecraft](https://img.shields.io/badge/Minecraft-Java%20Edition-62B47A?style=for-the-badge&logo=minecraft&logoColor=white)
![Discord](https://img.shields.io/badge/Discord-Bot%20Integration-5865F2?style=for-the-badge&logo=discord&logoColor=white)
![Status](https://img.shields.io/badge/status-em%20desenvolvimento-00E0FF?style=for-the-badge)

</div>

Launcher para **Minecraft Java Edition** desenvolvido em **Ruby**, com interface Web local, tema visual **RubyMC Neon**, suporte a modpacks, servidor público/comunidade, integração com Discord Bot, Display interno de logs e automação por comando único.

> Projeto focado em criar um launcher próprio, visual, organizado e extensível para jogar Minecraft, gerenciar modpacks, validar servidor da comunidade e integrar ações com Discord.

---

## 📌 Status atual

✅ Launcher clássico em Ruby funcionando  
✅ Launcher Web local funcionando em `http://127.0.0.1:4567`  
✅ Tema RubyMC Neon com CSS e imagens  
✅ Display interno com logs, testes, erros e ações do backend  
✅ Comando único `./rubymc` para iniciar/parar/reiniciar/testar  
✅ Suporte inicial a importação de modpacks `.mrpack` e `.zip`  
✅ Aba de servidor da comunidade  
✅ Validação backend de Discord Bot  
✅ Validação de canais e cargos do Discord  
✅ Teste de envio para canal de logs do Discord  
✅ Organização da raiz do projeto com `scripts/organize_project_root.rb`

---

## 🖼️ Interface do RubyMC Launcher

O RubyMC Launcher possui uma interface Web local com tema visual **RubyMC Neon**, painel lateral, display interno de logs, integração com Discord, suporte a modpacks e gerenciamento do servidor da comunidade.

### 🏠 Tela inicial

A tela inicial concentra o status do launcher, versão do Ruby, status do servidor, seletor de perfil e atalhos principais.

<p align="center">
  <img src="https://raw.githubusercontent.com/VICTORGG04/RubyMC-Launcher/main/docs/assets/screenshots/rubymc-inicio.png" alt="Tela inicial do RubyMC Launcher" width="900">
</p>

---

### 📦 Importação de Modpacks

A aba **Modpacks** permite importar arquivos `.mrpack` e `.zip`, registrar perfis e atualizar a lista de modpacks disponíveis no launcher.

<p align="center">
  <img src="https://raw.githubusercontent.com/VICTORGG04/RubyMC-Launcher/main/docs/assets/screenshots/rubymc-modpacks.png" alt="Aba de modpacks do RubyMC Launcher" width="900">
</p>

---

### 🌍 Servidor da comunidade

A aba **Servidor** permite visualizar o endereço configurado do servidor Minecraft, testar conexão e iniciar entrada no servidor.

<p align="center">
  <img src="https://raw.githubusercontent.com/VICTORGG04/RubyMC-Launcher/main/docs/assets/screenshots/rubymc-servidor.png" alt="Aba de servidor da comunidade do RubyMC Launcher" width="900">
</p>

---

### 🤖 Integração Discord Bot

A aba **Discord** valida os canais, cargos, token do bot, servidor Discord e canal de logs usando backend Ruby integrado à Discord API.

<p align="center">
  <img src="https://raw.githubusercontent.com/VICTORGG04/RubyMC-Launcher/main/docs/assets/screenshots/rubymc-discord.png" alt="Aba Discord Bot do RubyMC Launcher" width="900">
</p>

---

### 🖥️ Display interno de logs

O **Display interno** mostra ações do backend, testes, erros, comandos executados, validações do Discord e status do servidor sem sair do launcher.

<p align="center">
  <img src="https://raw.githubusercontent.com/VICTORGG04/RubyMC-Launcher/main/docs/assets/screenshots/rubymc-display.png" alt="Display interno de logs do RubyMC Launcher" width="900">
</p>

---

### 🗂️ Organização do projeto

A aba **Projeto** centraliza ações de organização da raiz e abertura do launcher clássico.

<p align="center">
  <img src="https://raw.githubusercontent.com/VICTORGG04/RubyMC-Launcher/main/docs/assets/screenshots/rubymc-projeto.png" alt="Aba de projeto do RubyMC Launcher" width="900">
</p>

---

## 🚀 Funcionalidades principais

### 🎮 Minecraft

- Escolha de perfil para jogar.
- Execução do launcher clássico pelo painel Web.
- Modo offline com nickname.
- Alocação de memória RAM.
- Uso de versão padrão configurada em `config/settings.yml`.
- Verificação básica de ambiente.
- Entrada no servidor da comunidade pelo painel.

### 🌐 Launcher Web

- Interface Web local.
- CSS real.
- Tema RubyMC Neon.
- Abas organizadas:
  - Início
  - Modpacks
  - Servidor
  - Discord
  - Display
  - Projeto
- Backend Ruby com WEBrick.
- Comunicação frontend/backend via rotas HTTP.
- Display interno para acompanhar tudo sem sair do painel.

### 📦 Modpacks

- Aba própria para modpacks.
- Importação de modpack pelo navegador.
- Suporte inicial a:
  - `.mrpack`
  - `.zip`
- Lista de modpacks instalados.
- Atualização do seletor de perfil.
- Registro de ações no Display interno.

### 🌍 Servidor da comunidade

- Configuração de servidor Minecraft público ou local.
- Teste de conexão TCP.
- Botão para entrar no servidor.
- Endereço configurável em `config/settings.yml`.

### 🤖 Discord Bot

- Configuração por `config/settings.yml`.
- Validação local dos IDs.
- Validação remota com Discord API.
- Teste de autenticação do bot.
- Teste do servidor Discord.
- Teste de envio de mensagem no canal de logs.
- Suporte a canais e cargos configurados.
- Display interno com logs reais da integração.

### 🖥️ Display interno

O Display interno mostra eventos como:

```text
[00:57:21] COMMAND $ bundle check
[00:57:21] OK      Rodar testes concluído.
[00:57:37] ACTION  Validação Discord solicitada pelo painel.
[00:57:38] OK      Bot autenticado: BOT RUBYMC
[00:57:38] OK      Servidor Discord validado: LanServer
[00:58:59] OK      Mensagem de teste enviada ao Discord no canal configurado.
```

---

## 🧰 Tecnologias utilizadas

| Tecnologia | Uso |
|---|---|
| Ruby | Linguagem principal do launcher |
| WEBrick | Servidor Web local |
| HTTParty | Requisições HTTP para APIs |
| RubyZip | Importação e leitura de modpacks `.zip` / `.mrpack` |
| YAML | Configurações do projeto |
| HTML | Estrutura do launcher Web |
| CSS | Tema RubyMC Neon |
| JavaScript | Eventos da interface Web |
| Discord API | Validação do bot, canais, cargos e envio de logs |
| Java | Execução do Minecraft Java Edition |

---

## 📋 Pré-requisitos

### Sistema

- Linux, macOS ou Windows com Ruby configurado.
- Testado em Ubuntu 24.04.

### Ruby

```bash
ruby -v
```

Recomendado:

```text
Ruby 3.2+
```

### Bundler

```bash
gem install bundler
```

### Java

Para Minecraft moderno, use Java compatível com a versão escolhida.

Para Minecraft 1.21.4, recomenda-se Java 21+:

```bash
java -version
```

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install openjdk-21-jdk -y
```

---

## 📦 Instalação

Clone o projeto:

```bash
git clone https://github.com/VICTORGG04/RubyMC-Launcher.git
cd RubyMC-Launcher
```

Instale as dependências:

```bash
bundle install
```

---

## ⚡ Comando único

O projeto possui o comando principal:

```bash
./rubymc
```

Ele automatiza:

- Verificação do `Gemfile`.
- Instalação de dependências.
- Liberação da porta `4567`.
- Inicialização do launcher Web.
- Abertura do navegador.
- Registro de logs e PID.

### Comandos disponíveis

```bash
./rubymc start      # inicia o launcher Web
./rubymc stop       # para o launcher Web
./rubymc restart    # reinicia o launcher Web
./rubymc status     # mostra status, PID e porta
./rubymc logs       # acompanha logs do servidor Web
./rubymc test       # roda testes básicos
./rubymc classic    # abre o launcher clássico
./rubymc organize   # organiza a raiz do projeto
```

Atalho equivalente:

```bash
bin/rubymc
```

---

## 🌐 Como iniciar o Launcher Web

Use:

```bash
./rubymc
```

Ou:

```bash
./rubymc restart
```

Depois abra:

```text
http://127.0.0.1:4567
```

Para forçar atualização de CSS/JS:

```text
Ctrl + F5
```

Ou abra com parâmetro de cache:

```text
http://127.0.0.1:4567/?v=latest-update
```

---

## 🖥️ Launcher clássico

O launcher clássico continua disponível em:

```bash
bundle exec ruby launcher.rb
```

Ou pelo comando:

```bash
./rubymc classic
```

Ele é usado para executar o fluxo tradicional no terminal:

- Escolha de versão.
- Login/modo offline.
- Nickname.
- Memória RAM.
- Inicialização do Minecraft.

---

## ⚙️ Configuração principal

O arquivo principal de configuração é:

```text
config/settings.yml
```

> Por segurança, `config/settings.yml` não deve ser enviado para o GitHub se contiver `bot_token` ou dados privados. Use `config/settings.example.yml` como modelo público.

Caso ele não exista, crie:

```bash
mkdir -p config
cp config/settings.example.yml config/settings.yml
nano config/settings.yml
```

Exemplo completo:

```yaml
launcher:
  name: "Minecraft Ruby Launcher"
  version: "1.0.0"
  update_url: "https://api.github.com/repos/VICTORGG04/RubyMC-Launcher/releases/latest"
  web_host: "127.0.0.1"
  web_port: 4567

minecraft:
  default_version: "1.21.4"
  ram_mb: 2048
  java_path: ""
  game_dir: "~/.minecraft"

modpacks:
  enabled: true
  directory: "~/.minecraft_ruby_launcher/modpacks"
  profiles_path: "~/.minecraft_ruby_launcher/modpacks/profiles.json"
  imports_path: "~/.minecraft_ruby_launcher/modpacks/imports"
  allow_mrpack: true
  allow_zip: true

community_server:
  enabled: true
  name: "LanServer"
  address: "127.0.0.1"
  port: 25565
  auto_connect: false

discord:
  rich_presence: true
  client_id: "COLE_AQUI_O_APPLICATION_ID"

  bot_enabled: true
  bot_token: "COLE_AQUI_O_BOT_TOKEN"
  guild_id: "COLE_AQUI_O_ID_DO_SERVIDOR"

  server_address: "127.0.0.1:25565"

  invite_channel_id: "COLE_AQUI_O_ID_DO_CANAL_DE_CONVITE"
  invite_max_age_seconds: 86400
  invite_max_uses: 1
  invite_store_path: "~/.minecraft_ruby_launcher/discord_invites.json"

  channels:
    welcome_channel_id: ""
    rules_channel_id: ""
    announcements_channel_id: ""
    updates_channel_id: ""
    new_members_channel_id: ""

    general_channel_id: ""
    rubymc_channel_id: ""
    community_channel_id: ""
    forum_channel_id: ""

    bugs_channel_id: ""
    ban_channel_id: ""
    suggestions_channel_id: ""

    support_channel_id: ""
    logs_channel_id: ""

    modpacks_channel_id: ""

  roles:
    member_role_id: ""
    player_role_id: ""
    staff_role_id: ""
    admin_role_id: ""
    bot_role_id: ""

web:
  theme: "rubymc-neon"
  display_enabled: true
  auto_open_browser: true
```

---

## 🔐 Importante sobre tokens

Não suba `bot_token` no GitHub público.

Recomendação no `.gitignore`:

```gitignore
config/settings.yml
```

Mantenha um exemplo versionado:

```text
config/settings.example.yml
```

Também é possível usar variável de ambiente:

```bash
export RUBYMC_DISCORD_BOT_TOKEN="SEU_TOKEN_DO_BOT"
./rubymc restart
```

---

## 🌍 Configurando o servidor Minecraft

O campo:

```yaml
community_server:
  address: "..."
  port: 25565
```

deve ser o endereço que o jogador colocaria no Minecraft em:

```text
Multiplayer → Add Server → Server Address
```

### Servidor local na mesma máquina

```yaml
community_server:
  enabled: true
  name: "LanServer"
  address: "127.0.0.1"
  port: 25565

discord:
  server_address: "127.0.0.1:25565"
```

### Servidor na rede local

Descubra o IP local:

```bash
hostname -I
```

Exemplo:

```yaml
community_server:
  address: "192.168.1.50"
  port: 25565

discord:
  server_address: "192.168.1.50:25565"
```

### Servidor público

Use domínio, IP público ou túnel:

```yaml
community_server:
  address: "play.rubymc.com"
  port: 25565

discord:
  server_address: "play.rubymc.com:25565"
```

Não use:

```text
http://
https://
minecraft://
```

Correto:

```yaml
address: "play.rubymc.com"
```

---

## 🤖 Configurando o Discord Bot

### 1. Ativar modo desenvolvedor no Discord

No Discord:

```text
Configurações do usuário
→ Avançado
→ Modo desenvolvedor
→ Ativar
```

### 2. Onde pegar cada ID

| Campo | Onde pegar |
|---|---|
| `client_id` | Discord Developer Portal → Aplicação → General Information → Application ID |
| `bot_token` | Discord Developer Portal → Aplicação → Bot → Token |
| `guild_id` | Botão direito no servidor → Copiar ID do servidor |
| `invite_channel_id` | Botão direito no canal de convite → Copiar ID do canal |
| `logs_channel_id` | Botão direito no canal de logs → Copiar ID do canal |
| `welcome_channel_id` | Botão direito no canal de boas-vindas → Copiar ID |
| `rules_channel_id` | Botão direito no canal de regras → Copiar ID |
| `announcements_channel_id` | Botão direito no canal de notícias/anúncios → Copiar ID |
| `updates_channel_id` | Botão direito no canal de comunicados/atualizações → Copiar ID |
| `general_channel_id` | Botão direito no canal geral/chat → Copiar ID |
| `rubymc_channel_id` | Botão direito no canal RubyMC → Copiar ID |
| `community_channel_id` | Botão direito no canal comunidade → Copiar ID |
| `forum_channel_id` | Botão direito no fórum → Copiar ID |
| `bugs_channel_id` | Botão direito no canal de bugs → Copiar ID |
| `ban_channel_id` | Botão direito no canal de banimentos → Copiar ID |
| `suggestions_channel_id` | Botão direito no canal de sugestões → Copiar ID |
| `modpacks_channel_id` | Botão direito no canal de modpacks → Copiar ID |

### 3. Onde pegar IDs de cargos

```text
Configurações do servidor
→ Cargos
→ botão direito no cargo
→ Copiar ID
```

---

## 🧩 Cargos do Discord

No `settings.yml`:

```yaml
roles:
  member_role_id: ""
  player_role_id: ""
  staff_role_id: ""
  admin_role_id: ""
  bot_role_id: ""
```

### `member_role_id`

Cargo de membro comum.

Permissões recomendadas:

- Ver canais públicos.
- Enviar mensagens.
- Ler histórico de mensagens.
- Adicionar reações.
- Entrar em canais de voz.
- Falar em canais de voz.

Não recomendado:

- Administrador.
- Gerenciar servidor.
- Gerenciar canais.
- Gerenciar cargos.
- Banir membros.
- Expulsar membros.

### `player_role_id`

Cargo de jogador.

Uso:

- Liberar áreas de Minecraft.
- Liberar canais de modpacks.
- Liberar canais do servidor.
- Identificar quem joga no RubyMC.

Permissões:

- Tudo que o membro comum tem.
- Acesso a categorias/canais de Minecraft.
- Acesso a modpacks e voz do jogo.

### `staff_role_id`

Cargo de equipe.

Uso:

- Suporte.
- Moderação.
- Acesso a canais privados.
- Acesso a logs.

Permissões recomendadas:

- Ver canais privados de staff.
- Gerenciar mensagens.
- Silenciar membros.
- Mover membros em voz.
- Gerenciar apelidos.
- Responder suporte.
- Ver canal de logs.

Evite dar `Administrador` para staff comum.

### `admin_role_id`

Cargo de administrador.

Uso:

- Controle total do servidor.
- Configuração de canais.
- Configuração de cargos.
- Permissões administrativas.

Permissões:

- Administrador.
- Gerenciar servidor.
- Gerenciar canais.
- Gerenciar cargos.
- Banir/expulsar membros.
- Gerenciar webhooks.
- Ver logs de auditoria.

### `bot_role_id`

Cargo do bot RubyMC.

Uso:

- Permitir que o bot envie mensagens.
- Criar convites.
- Escrever logs.
- Futuramente atribuir cargos automaticamente.

Permissões recomendadas:

- Ver canais.
- Enviar mensagens.
- Ler histórico.
- Incorporar links.
- Anexar arquivos.
- Criar convites.
- Usar comandos de aplicativo.
- Criar threads.
- Gerenciar cargos, se o bot for entregar cargos.

O cargo do bot deve ficar acima dos cargos que ele vai entregar.

Ordem recomendada:

```text
👑 Admin
🧑‍💻 Staff
🤖 RubyMC Bot
🎮 Jogador
👤 Membro
@everyone
```

---

## ✅ Validando Discord pelo Launcher

Inicie:

```bash
./rubymc restart
```

Abra:

```text
http://127.0.0.1:4567
```

Vá em:

```text
Discord → Validar Discord
```

O Display deve mostrar algo como:

```text
CHECK   Discord bot_enabled=true guild=true token=true
CHECK   Canais configurados: 15/15
CHECK   Cargos configurados: 5/5
OK      Bot autenticado: BOT RUBYMC
OK      Servidor Discord validado: LanServer
OK      Discord remoto: 21 canais e 6 cargos encontrados.
```

Para testar canal de logs:

```text
Discord → Testar canal de logs
```

Resultado esperado:

```text
OK Mensagem de teste enviada ao Discord no canal ...
```

---

## 📦 Modpacks

A aba **Modpacks** permite importar modpacks.

Formatos aceitos:

```text
.mrpack
.zip
```

Fluxo:

1. Abra o launcher Web.
2. Vá na aba **Modpacks**.
3. Informe o nome do perfil.
4. Selecione o arquivo `.mrpack` ou `.zip`.
5. Clique em **Importar modpack**.
6. Acompanhe o Display interno.
7. Volte à aba Início e escolha o perfil.

Pastas usadas:

```text
~/.minecraft_ruby_launcher/modpacks
~/.minecraft_ruby_launcher/modpacks/imports
~/.minecraft_ruby_launcher/modpacks/profiles.json
```

---

## 🧪 Testes

Pelo painel:

```text
Rodar testes
```

Pelo terminal:

```bash
./rubymc test
```

O teste básico verifica:

- Sintaxe Ruby.
- `launcher_gui.rb`.
- `launcher.rb`.
- `lib/web_launcher_app.rb`.
- `bundle check`.

---

## 🧹 Organização da raiz

Use:

```bash
./rubymc organize
```

Ou:

```bash
ruby scripts/organize_project_root.rb --apply
```

Estrutura recomendada:

```text
MinecraftLauncher/
├── bin/
│   ├── launcher-web
│   ├── rubymc
│   └── run_launcher_checks.rb
├── config/
│   ├── settings.yml
│   └── settings.example.yml
├── docs/
├── lib/
├── scripts/
├── test/
├── tmp/
├── web/
├── launcher.rb
├── launcher_gui.rb
├── rubymc
├── Gemfile
├── Gemfile.lock
├── README.md
└── .gitignore
```

---

## 📁 Estrutura do projeto

```text
MinecraftLauncher/
├── launcher.rb                    # launcher clássico no terminal
├── launcher_gui.rb                # entrada do launcher Web
├── rubymc                         # comando único
├── Gemfile                        # dependências Ruby
├── config.ru                      # integração Rack/opcional
├── config/
│   ├── settings.yml               # configuração local privada
│   └── settings.example.yml       # exemplo público
├── lib/
│   ├── web_launcher_app.rb        # backend Web
│   ├── discord_config.rb          # leitura/validação config Discord
│   ├── discord_bot_service.rb     # integração Discord API
│   ├── rubymc_settings.rb         # helper de configuração
│   ├── modpack_manager.rb         # gerenciamento de modpacks
│   ├── community_server.rb        # servidor da comunidade
│   ├── minecraft_manager.rb       # lógica Minecraft
│   ├── microsoft_auth.rb          # autenticação Microsoft
│   ├── account_bank.rb            # contas salvas
│   ├── session_manager.rb         # sessão ativa
│   ├── auto_updater.rb            # atualização
│   └── discord_integration.rb     # integração Discord antiga/base
├── web/
│   ├── index.html
│   └── assets/
│       ├── css/launcher.css
│       ├── js/launcher.js
│       └── img/
├── docs/
│   └── assets/
│       └── screenshots/
├── scripts/
│   ├── organize_project_root.rb
│   ├── validate_discord_settings.rb
│   ├── setup_channels.rb
│   ├── setup_discord_forum.rb
│   └── setup_discord_welcome.rb
├── test/
│   ├── test_discord_bot.rb
│   └── test_discord_invite.rb
└── docs/
```

---

## 🧯 Solução de problemas

### Porta 4567 ocupada

Erro:

```text
Address already in use - bind(2) for 127.0.0.1:4567
```

Corrija:

```bash
./rubymc stop
sudo fuser -k 4567/tcp
./rubymc restart
```

Ou:

```bash
sudo lsof -nP -iTCP:4567 -sTCP:LISTEN
```

### Botões não funcionam

Aplique cache novo:

```text
Ctrl + F5
```

Ou abra:

```text
http://127.0.0.1:4567/?v=buttons-fix
```

Veja logs:

```bash
./rubymc logs
```

### CSS não atualizou

Force cache:

```text
Ctrl + F5
```

Ou altere o parâmetro:

```text
http://127.0.0.1:4567/?v=novo-css
```

Confirme o CSS:

```bash
grep -n "RUBYMC" web/assets/css/launcher.css
```

### Imagem de fundo sumiu

Verifique se existe:

```bash
ls web/assets/img/rubymc-discord-panel.png
```

Se existir, confira se o CSS usa:

```css
url("/assets/img/rubymc-discord-panel.png")
```

### WEBrick duplicado no Gemfile

Erro:

```text
You cannot specify the same gem twice
```

Corrija:

```bash
sed -i '/webrick/d' Gemfile
echo 'gem "webrick", "~> 1.9"' >> Gemfile
bundle install
```

### Java incompatível

Erro:

```text
UnsupportedClassVersionError
```

Significa que a versão do Minecraft/modpack exige Java mais novo.

Verifique:

```bash
java -version
```

Configure:

```yaml
minecraft:
  java_path: "/caminho/para/java/bin/java"
```

### Servidor não respondeu

Erro:

```text
Servidor não respondeu: execution expired
```

Verifique:

```yaml
community_server:
  address: "ENDERECO_REAL"
  port: 25565
```

Teste no Minecraft usando:

```text
ENDERECO_REAL:25565
```

---

## 🔒 Segurança

Não versionar:

```text
config/settings.yml
.rubymc/
tmp/
vendor/
.bundle/
.idea/
```

Exemplo de `.gitignore`:

```gitignore
.bundle/
vendor/
tmp/
.rubymc/
.idea/
*.log
*.pid
config/settings.yml
```

Versionar apenas:

```text
config/settings.example.yml
```

---

## 🧾 Commit recomendado para esta atualização

```bash
git add .
git commit -m "docs: adiciona capturas de tela e documentação completa do RubyMC"
```

Ou:

```bash
git commit -m "feat: integra Discord, modpacks e painel web RubyMC"
```

---

## 🛣️ Roadmap

Próximos passos sugeridos:

- Autenticação Microsoft integrada ao painel Web.
- Seleção visual de contas salvas.
- Instalação completa de modpacks Modrinth.
- Suporte avançado a CurseForge.
- Auto-detecção de Java por versão do Minecraft.
- Tela de configuração dentro do launcher.
- Editor visual do `settings.yml`.
- Integração completa com Discord Slash Commands.
- Sistema de atualização automática do launcher.
- Empacotamento para `.deb`, `.AppImage` e Windows.

---

## 📄 Licença

MIT — livre para estudar, modificar e distribuir.

---

## 💎 RubyMC

Projeto desenvolvido para criar um launcher Minecraft próprio, com Ruby, Web UI, Discord, modpacks, servidor da comunidade e automação.

```text
Ruby + Minecraft + Discord + Web UI = RubyMC Launcher
```
