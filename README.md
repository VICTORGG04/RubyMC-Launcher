# 💎 RubyMC Launcher

<div align="center">

![Ruby](https://img.shields.io/badge/Ruby-3.2+-CC342D?style=for-the-badge\&logo=ruby\&logoColor=white)
![Minecraft](https://img.shields.io/badge/Minecraft-Ecosystem-62B47A?style=for-the-badge\&logo=minecraft\&logoColor=white)
![Java](https://img.shields.io/badge/Java-Launcher-FF9800?style=for-the-badge\&logo=openjdk\&logoColor=white)
![Bedrock](https://img.shields.io/badge/Bedrock-BDS-00AEEF?style=for-the-badge\&logo=minecraft\&logoColor=white)
![Discord](https://img.shields.io/badge/Discord-Integration-5865F2?style=for-the-badge\&logo=discord\&logoColor=white)
![IA](https://img.shields.io/badge/IA-Ollama-009688?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Development-00E0FF?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)

Ecossistema Ruby para gerenciamento de servidores Minecraft Java e Minecraft Bedrock Dedicated Server.

</div>

---

# 🖼️ Showcase do Projeto

<div align="center">

| 🏠 Bedrock Início                                                   | 🌐 Servidor BDS                                                       |
| ------------------------------------------------------------------- | --------------------------------------------------------------------- |
| <img src="docs/assets/bedrock/bedrock-home-panel.png" width="100%"> | <img src="docs/assets/bedrock/bedrock-server-panel.png" width="100%"> |

| 📦 Versões BDS                                                          | 📜 Display                                                             |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| <img src="docs/assets/bedrock/bedrock-versions-panel.png" width="100%"> | <img src="docs/assets/bedrock/bedrock-display-panel.png" width="100%"> |

| 📁 Projeto                                                             | ⚙️ Configurações                                                        |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| <img src="docs/assets/bedrock/bedrock-project-panel.png" width="100%"> | <img src="docs/assets/bedrock/bedrock-settings-panel.png" width="100%"> |

</div>

---

# 🚀 Visão geral

O **RubyMC Launcher** é um ecossistema dividido em dois ambientes principais:

| Projeto               | Objetivo                                                             |
| --------------------- | -------------------------------------------------------------------- |
| 💎 RubyMC Java        | Launcher Minecraft Java com modpacks, Discord, IA local e painel web |
| 💎 RubyMC Bedrock BDS | Gerenciador visual para Minecraft Bedrock Dedicated Server           |

O objetivo é fornecer:

* gerenciamento visual;
* interface dark/neon;
* integração Discord;
* IA local;
* gerenciamento de servidores;
* monitoramento em tempo real;
* suporte operacional;
* organização modular em Ruby.

---

# 🏗️ Estrutura do repositório

```text id="2qzj1x"
RubyMC-Launcher/
├── README.md
├── docs/
│   └── assets/
│       └── bedrock/
│
├── rubymc-java/
│   ├── README.md
│   ├── bot_daemon.rb
│   ├── launcher.rb
│   ├── launcher_gui.rb
│   ├── config/
│   ├── lib/
│   ├── scripts/
│   └── web/
│
├── rubymc-bedrock/
│   ├── README.md
│   ├── config/
│   ├── lib/
│   ├── scripts/
│   ├── web/
│   └── docs/
│
└── scripts/
```

---

# 💎 RubyMC Java

O **RubyMC Java** é o launcher voltado para Minecraft Java Edition.

## Recursos

* launcher web;
* sistema de modpacks;
* Discord Bot;
* Rich Presence;
* IA local;
* display de logs;
* gerenciamento de perfis;
* ambiente RubyMC.

## Módulos principais

```text id="l1r7u9"
Início
Modpacks
Servidor
Discord
IA
Display
Projeto
Configurações
```

## Modpacks

O sistema suporta:

* `.mrpack`
* `.zip`

Fluxo operacional:

```text id="7krg4n"
Selecionar arquivo
→ Validar formato
→ Importar modpack
→ Criar perfil
→ Atualizar launcher
→ Executar instância
```

## IA Local

Modelo utilizado:

```text id="jz4z5r"
qwen3.5:9b
```

A IA pode:

* interpretar logs;
* explicar erros;
* auxiliar configuração;
* responder dúvidas;
* apoiar suporte técnico.

---

# 💎 RubyMC Bedrock BDS

O **RubyMC Bedrock BDS** é o ambiente administrativo do Minecraft Bedrock Dedicated Server.

## Recursos

* instalação de versões BDS;
* gerenciamento de instâncias;
* monitoramento UDP;
* controle de processos;
* gerenciamento Linux;
* monitor ativo;
* logs em tempo real;
* painel operacional.

## Páginas principais

```text id="1dbz0j"
Início
Servidor BDS
Versões BDS
Display
Projeto
Configurações
```

---

# 🌐 Servidor BDS

A aba Servidor fornece:

* IP/porta;
* validação UDP;
* status online;
* PID ativo;
* capacidade;
* ping;
* ações rápidas.

## Ações disponíveis

```text id="b7fx2s"
Iniciar
Parar
Reiniciar
Logs
Remover
```

---

# 📦 Versões BDS

O sistema permite:

* instalar versões oficiais;
* atualizar lista;
* selecionar versões;
* iniciar versões instaladas;
* remover instâncias;
* visualizar diretórios físicos.

---

# 📜 Display

O Display funciona como console operacional.

## Recursos

* logs em tempo real;
* atualização dinâmica;
* limpeza rápida;
* monitoramento interno;
* depuração do backend.

---

# 💬 Discord

O ecossistema RubyMC possui integração completa com Discord.

## Recursos

* Discord Bot;
* Rich Presence;
* validação de canais;
* logs operacionais;
* suporte automatizado;
* geração de convites;
* gerenciamento de cargos.

## Configuração

```yaml id="0m0smv"
discord:
  rich_presence: true
  bot_enabled: true
  bot_token: '${RUBYMC_DISCORD_BOT_TOKEN}'
  guild_id: 'DISCORD_GUILD_ID'
```

## Segurança

Nunca publique tokens reais.

Use variável de ambiente:

```bash id="m4d5sh"
export RUBYMC_DISCORD_BOT_TOKEN='SEU_TOKEN'
```

---

# 🧠 IA Local

O projeto suporta IA local usando Ollama.

## Instalação

```bash id="f6l1o6"
ollama pull qwen3.5:9b
ollama serve
```

## Configuração

```yaml id="g8l7x4"
ai_support:
  enabled: true
  provider: ollama
  host: 'http://127.0.0.1:11434'
  model: 'qwen3.5:9b'
```

---

# ⚙️ Instalação

Clone o repositório:

```bash id="3sh8ph"
git clone https://github.com/VICTORGG04/RubyMC-Launcher.git
```

Entre na pasta:

```bash id="31o0d2"
cd RubyMC-Launcher
```

Instale dependências:

```bash id="l8tl8m"
bundle install
```

---

# 💎 Executar RubyMC Java

```bash id="kwzpk6"
cd rubymc-java
./rubymc restart
```

Painel:

```text id="w1c3h2"
http://127.0.0.1:4567
```

---

# 💎 Executar RubyMC Bedrock

```bash id="lq7xsy"
cd rubymc-bedrock
./rubymc restart
```

Painel:

```text id="i7q4oe"
http://127.0.0.1:4567
```

---

# 🧩 Dependências

## Ruby

```text id="8m2gpr"
Ruby 3.x
```

## Gems principais

* sinatra
* puma
* yaml
* json
* discordrb
* websocket-client-simple
* fileutils

---

# 🛠️ Validação

## Ruby

```bash id="w5xmx4"
ruby -c bot_daemon.rb
ruby -c lib/web_launcher_app.rb
```

## Bundler

```bash id="q5f8l2"
bundle check
```

## Porta do painel

```bash id="3k7d7u"
ss -ltnp | grep 4567
```

---

# 🗺️ Roadmap

## RubyMC Java

* melhorias no launcher;
* sistema avançado de modpacks;
* integração IA completa;
* sincronização multiplayer;
* marketplace RubyMC.

## RubyMC Bedrock

* auto-update BDS;
* monitoramento avançado;
* integração IA;
* painel multiusuário;
* gerenciamento remoto;
* backup automático.

---

# 📄 Licença

Este projeto está licenciado sob a **MIT License** — consulte o arquivo [LICENSE](LICENSE) para detalhes.

---

# 👨‍💻 Autor

Desenvolvido por **Victor Marcial**.
