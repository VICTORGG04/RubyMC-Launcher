# Minecraft Ruby Launcher — Web + Raiz organizada

Este patch troca a GUI desktop experimental por uma **interface Web local** com HTML, CSS e JavaScript, servida pelo próprio Ruby usando `WEBrick`.

A interface abre em:

```bash
http://127.0.0.1:4567
```

## Como aplicar

Na raiz do projeto:

```bash
unzip minecraft_ruby_launcher_web_organized_patch.zip
cp -r minecraft_ruby_launcher_web_organized_patch/* .
```

Edite o `Gemfile` e remova qualquer linha com:

```ruby
gem 'glimmer-dsl-tk'
gem 'glimmer-dsl-libui'
```

Mantenha/adicone:

```ruby
gem 'rubyzip', '~> 2.3'
```

Depois rode:

```bash
rm -rf vendor/bundle Gemfile.lock
bundle install
bundle exec ruby launcher_gui.rb
```

## Estrutura recomendada

```text
MinecraftLauncher/
├── bin/
│   ├── launcher-web
│   └── run_launcher_checks.rb
├── config/
│   └── settings.yml
├── docs/
│   └── WEB_LAUNCHER_ORGANIZACAO.md
├── lib/
│   ├── web_launcher_app.rb
│   ├── modpack_manager.rb
│   ├── community_server.rb
│   └── ...
├── scripts/
│   └── organize_project_root.rb
├── test/
├── web/
│   ├── index.html
│   └── assets/
│       ├── css/launcher.css
│       └── js/launcher.js
├── launcher.rb
├── launcher_gui.rb
├── Gemfile
└── README.md
```

## Display interno

O display fica na aba **Display**. Ele recebe:

- logs do launcher;
- resultado de testes;
- erros Ruby;
- saída de comandos;
- resultado de importação de modpacks;
- teste do servidor;
- organização da raiz.

## Organizar raiz

Você pode clicar em **Projeto → Organizar raiz** ou rodar:

```bash
ruby scripts/organize_project_root.rb --apply
```

O script move:

```text
setup_channels.rb          -> scripts/setup_channels.rb
setup_discord_forum.rb     -> scripts/setup_discord_forum.rb
setup_discord_welcome.rb   -> scripts/setup_discord_welcome.rb
test_discord_bot.rb        -> test/test_discord_bot.rb
test_discord_invite.rb     -> test/test_discord_invite.rb
PATCH_SUMMARY.md           -> docs/PATCH_SUMMARY.md
```

Ele mantém na raiz os arquivos principais:

```text
launcher.rb
launcher_gui.rb
bot_daemon.rb
Gemfile
Gemfile.lock
README.md
.gitignore
```

## CSS

O tema fica em:

```text
web/assets/css/launcher.css
```

Você pode alterar cores, layout, fontes, botões, sidebar, cards e display sem mexer no Ruby.
