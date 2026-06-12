# 💎 RubyMC Launcher

<div align="center">

![Ruby](https://img.shields.io/badge/Ruby_3.2+-CC342D?style=for-the-badge&logo=ruby&logoColor=white)
![Minecraft](https://img.shields.io/badge/Minecraft_Java_%2B_Bedrock-62B47A?style=for-the-badge&logo=minecraft&logoColor=white)
![Discord](https://img.shields.io/badge/Discord_Bot-5865F2?style=for-the-badge&logo=discord&logoColor=white)
![Ollama](https://img.shields.io/badge/IA_Local_Ollama-009688?style=for-the-badge&logo=ollama&logoColor=white)
![Sinatra](https://img.shields.io/badge/Sinatra-Web-000000?style=for-the-badge&logo=ruby&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)

**Ecossistema Ruby para gerenciamento de servidores Minecraft Java Edition e Bedrock Dedicated Server**

</div>

---

## 📸 Showcase

<div align="center">

### 💎 RubyMC Java

| 🏠 Dashboard | 📦 Modpacks |
|---|---|
| <img src="rubymc-java/docs/assets/screenshots/rubymc-tela-inicio.png" width="100%"> | <img src="rubymc-java/docs/assets/screenshots/rubymc-modpacks.png" width="100%"> |

| 🌐 Servidor | 💬 Discord |
|---|---|
| <img src="rubymc-java/docs/assets/screenshots/rubymc-servidor-comunidade.png" width="100%"> | <img src="rubymc-java/docs/assets/screenshots/rubymc-discord-bot.png" width="100%"> |

| 🧠 IA | ⚙️ Configurações |
|---|---|
| <img src="rubymc-java/docs/assets/screenshots/rubymc-ia.png" width="100%"> | <img src="rubymc-java/docs/assets/screenshots/rubymc-configuracoes.png" width="100%"> |

| 🗄️ DB | 🖥️ Display |
|---|---|
| <img src="rubymc-java/docs/assets/screenshots/DB-rubymc.png" width="100%"> | <img src="rubymc-java/docs/assets/screenshots/display-rubymc.png" width="100%"> |

| 📋 Versões | 👑 VIP |
|---|---|
| <img src="rubymc-java/docs/assets/screenshots/versoes-rubymc.png" width="100%"> | <img src="rubymc-java/docs/assets/screenshots/VIP-rubymc.png" width="100%"> |

### 💎 RubyMC Bedrock

| 🏠 Início | 🌐 Servidor BDS |
|---|---|
| <img src="docs/assets/bedrock/bedrock-home-panel.png" width="100%"> | <img src="docs/assets/bedrock/bedrock-server-panel.png" width="100%"> |

</div>

---

## 🚀 Visão Geral

O **RubyMC Launcher** é um ecossistema completo dividido em dois projetos independentes:

| Projeto | Descrição |
|---|---|
| **💎 RubyMC Java** | Launcher Minecraft Java com painel web, modpacks, autenticação Microsoft, bot Discord, IA local via Ollama e gerenciamento de servidor |
| **💎 RubyMC Bedrock** | Gerenciador visual para Minecraft Bedrock Dedicated Server (BDS) com instalação de versões, monitoramento UDP e controle de instâncias |

### Destaques de Segurança

- ✅ **Proteção SSRF** — bloqueio de IPs privados em downloads de URL
- ✅ **Command Injection** — execução de comandos via array (`Open3.capture3`, `system` com args separados)
- ✅ **Rate Limiting** — limite de 16 threads simultâneas (bot) e 32 (web)
- ✅ **HMAC Sessions** — dados de sessão e verificação assinados com HMAC-SHA256 (chave derivada do `client_secret`)
- ✅ **OAuth State Parameter** — prevenção de CSRF no callback Microsoft/Discord
- ✅ **Validação de Scheme** — downloads rejeitam protocolos que não sejam `http://` ou `https://`

---

## 🏗️ Estrutura do Repositório

```
MinecraftLauncher/
├── README.md
├── docs/
│   └── assets/
│       └── bedrock/              # Screenshots do Bedrock
│
├── rubymc-java/
│   ├── README.md
│   ├── rubymc                    # CLI Admin (bash)
│   ├── Gemfile                   # Dependências Ruby
│   ├── app/                      # Entry points (server.rb, bot.rb, console.rb)
│   ├── lib/                      # Módulos Ruby
│   ├── bin/                      # Player CLI + ferramentas
│   ├── config/                   # settings.yml + exemplo
│   ├── web/                      # Frontend (HTML + CSS + JS)
│   ├── archive/scripts/          # Scripts auxiliares
│   └── docs/                     # Documentação + screenshots
│
├── rubymc-bedrock/
│   ├── README.md
│   ├── rubymc                    # CLI Admin (bash)
│   ├── Gemfile
│   ├── lib/
│   ├── config/
│   ├── web/                      # Frontend BDS
│   ├── scripts/
│   └── docs/
│
└── archive/                      # Scripts legados
```

---

## ⚡ Começo Rápido (Java)

```bash
# 1. Clone
git clone https://github.com/VICTORGG04/RubyMC-Launcher.git
cd RubyMC-Launcher/rubymc-java

# 2. Instale dependências
gem install bundler
bundle install

# 3. Configure
cp config/settings.example.yml config/settings.yml
# Edite config/settings.yml com seu token Discord e guild_id

# 4. Inicie
./rubymc start
```

Acesse o painel em **http://127.0.0.1:4567**

---

## 💎 RubyMC Java

### Comandos da CLI (`./rubymc`)

| Comando | Descrição |
|---|---|
| `./rubymc start` | Inicia servidor web + bot Discord + servidor Minecraft |
| `./rubymc start --simulate` | Modo simulação (20 jogadores + Discord mock) |
| `./rubymc start --no-servers` | Inicia sem servidor Minecraft |
| `./rubymc stop` | Para servidor Minecraft + web + bot |
| `./rubymc stop --keep-servers` | Para apenas web + bot, mantém servidor Minecraft |
| `./rubymc status` | Status do projeto, bot e servidor |
| `./rubymc logs` | Logs da **web** (não do jogo) |
| `./rubymc test` | Verifica sintaxe Ruby + bundle check |
| `./rubymc server start\|stop\|restart` | Controla servidor Minecraft |
| `./rubymc server status` | Status do servidor Minecraft |
| `./rubymc server logs` | Logs do servidor Minecraft |
| `./rubymc bot start\|stop\|restart\|logs\|status` | Gerencia bot Discord |
| `./rubymc ai "pergunta"` | Pergunta à IA local (Ollama) |
| `./rubymc ai-chat` | Chat interativo com IA |
| `./rubymc install` | Instala dependências manualmente |
| `./rubymc classic` | Abre console Ruby clássico |

### CLI Player (`bin/rubymc-player`)

| Comando | Descrição |
|---|---|
| `bin/rubymc-player` | Menu interativo |
| `bin/rubymc-player play` | Abre o launcher para jogar |
| `bin/rubymc-player modpacks` | Lista/instala modpacks |
| `bin/rubymc-player server` | Status do servidor |
| `bin/rubymc-player discord` | Link do servidor Discord |
| `bin/rubymc-player help` | Ajuda |

> Leia o README completo em [rubymc-java/README.md](rubymc-java/README.md)

---

## 💎 RubyMC Bedrock BDS

### Comandos da CLI (`./rubymc`)

| Comando | Descrição |
|---|---|
| `./rubymc start` | Inicia painel web + monitor BDS |
| `./rubymc stop` | Para painel + servidores |
| `./rubymc restart` | Reinicia tudo |
| `./rubymc status` | Status do projeto |
| `./rubymc logs` | Logs do painel |
| `./rubymc server start\|stop\|restart\|logs` | Controla servidor BDS |

> Leia o README completo em [rubymc-bedrock/README.md](rubymc-bedrock/README.md)

---

## 🧩 Pré-requisitos

### RubyMC Java

| Requisito | Versão | Verificação |
|---|---|---|
| **Ruby** | 3.0+ | `ruby --version` |
| **Bundler** | — | `gem install bundler` |
| **Java** | 21+ (Minecraft 1.21.x) | `java --version` |
| **Ollama** (opcional) | — | `ollama pull qwen2.5:3b` |

### RubyMC Bedrock

| Requisito | Versão | Verificação |
|---|---|---|
| **Ruby** | 3.0+ | `ruby --version` |
| **Bundler** | — | `gem install bundler` |
| **Linux** | Ubuntu/Debian x64 | — |
| **BDS** | — | Downloads automáticos pelo painel |

---

## 🛠️ Validação

```bash
# Verificar sintaxe de todos os arquivos Ruby
cd rubymc-java
ruby -c app/server.rb
ruby -c app/bot.rb
ruby -c lib/web_launcher_app.rb

# Verificar dependências
bundle check

# Teste completo (sintaxe + bundle)
./rubymc test

# Verificar porta do painel
ss -ltnp | grep 4567
```

---

## 🗺️ Roadmap

### RubyMC Java — v1.1 ✅
- [x] Autenticação Microsoft OAuth + banco de contas
- [x] Modo offline (LAN/servidores offline)
- [x] Modpacks (`.mrpack` / `.zip`)
- [x] Servidor da comunidade com status ao vivo
- [x] Discord Bot (boas-vindas, comandos, cargos, convites)
- [x] Rich Presence no Discord
- [x] IA local via Ollama (Qwen 2.5 3B)
- [x] Dashboard consolidado (glassmorphism + animações)
- [x] CLI Admin + Player
- [x] Modo simulação (20 jogadores + Discord mock)
- [x] Proteções de segurança (SSRF, HMAC, rate limiting, OAuth state, command injection)

### RubyMC Java — v1.2 🔜
- [ ] IA premium (OpenAI/Anthropic)
- [ ] Integração Modrinth/CurseForge API
- [ ] Autenticação de usuários no painel
- [ ] Auto-detect de Java
- [ ] Empacotamento `.deb` / `.AppImage`

### RubyMC Bedrock — Atual ✅
- [x] Gerenciamento de versões BDS (download + instalação)
- [x] Monitoramento UDP (PID, ping, capacidade)
- [x] Controle de instâncias (start/stop/restart/remove)
- [x] Display de logs em tempo real
- [x] Painel web dark neon

### RubyMC Bedrock — Futuro 🔜
- [ ] Auto-update BDS
- [ ] Backup automático
- [ ] Integração IA
- [ ] Painel multiusuário
- [ ] Gerenciamento remoto

---

## 📄 Licença

Este projeto está licenciado sob a **MIT License** — consulte o arquivo [LICENSE](LICENSE) para detalhes.

---

## 👨‍💻 Autor

Desenvolvido por **Victor Marcial**.
