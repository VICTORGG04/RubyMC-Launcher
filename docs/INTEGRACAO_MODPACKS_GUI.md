# Integração: Modpacks + Servidor Público + GUI Glimmer DSL for Tk

Este patch adiciona uma camada nova ao launcher sem remover o fluxo atual de terminal.

## 1. Dependências

No `Gemfile`, adicione:

```ruby
gem 'glimmer-dsl-tk', '~> 0.0', require: false
gem 'rubyzip', '~> 2.3'
```

Depois rode:

```bash
bundle install
```

No Linux, se o Tk não estiver instalado no sistema:

```bash
sudo apt install ruby-tk tcl tk -y
```

## 2. Arquivos novos

Copie estes arquivos para o projeto:

```text
launcher_gui.rb
lib/modpack_manager.rb
lib/community_server.rb
lib/launcher_gui.rb
lib/launcher_extensions.rb
config/settings.yml.additions
```

Depois copie o conteúdo de `config/settings.yml.additions` para dentro do seu `config/settings.yml`.

## 3. Como abrir a interface gráfica

```bash
bundle exec ruby launcher_gui.rb
```

A janela permite:

- importar `.mrpack` do Modrinth;
- importar `.zip` genérico;
- importar manifesto CurseForge com `overrides/`;
- listar/remover modpacks instalados;
- abrir o launcher normal com o modpack selecionado;
- abrir o launcher já com o servidor público da comunidade selecionado.

## 4. Como ligar com o `MinecraftManager`

Como cada projeto pode montar o comando Java de um jeito diferente, a ponte foi isolada em `lib/launcher_extensions.rb`.

No ponto onde o launcher decide versão/diretório/argumentos do jogo, adicione:

```ruby
require_relative 'lib/launcher_extensions'

launch_options = MinecraftRubyLauncher::LauncherExtensions.merge_launch_options(
  {
    minecraft_version: selected_version,
    extra_game_args: []
  },
  settings
)
```

Depois use estes campos ao chamar o seu `MinecraftManager`:

```ruby
minecraft_version = launch_options[:minecraft_version] || launch_options[:version]
game_directory   = launch_options[:game_directory]
extra_game_args  = launch_options[:extra_game_args]
loader           = launch_options[:loader]
loader_version   = launch_options[:loader_version]
```

O comando final do Minecraft precisa receber:

```ruby
extra_game_args # exemplo: ["--server", "play.seuservidor.com", "--port", "25565"]
game_directory  # diretório isolado do modpack
```

## 5. Observação importante sobre loaders

O patch registra o loader (`fabric`, `forge`, `quilt`, `neoforge` ou `vanilla`) e a versão do loader, mas a instalação automática do loader depende do que o seu `minecraft_manager.rb` já faz hoje.

Para o suporte ficar completo, o `MinecraftManager` deve:

1. baixar a versão base do Minecraft;
2. detectar o loader do perfil;
3. instalar/usar a versão correspondente do Fabric, Forge, Quilt ou NeoForge;
4. iniciar usando o `game_directory` isolado do modpack.

## 6. CurseForge

Modpacks CurseForge normalmente trazem `projectID` e `fileID`, mas não trazem links diretos de download dos mods no manifesto. Por isso este patch:

- importa a pasta `overrides/`;
- salva a lista de mods pendentes em `curseforge_manual_downloads.json`;
- deixa pronto o ponto de integração para API CurseForge, caso você adicione uma chave depois.

## 7. Variáveis usadas pela GUI

A GUI abre o launcher principal com estas variáveis:

```bash
MCRUBY_MODPACK_ID=<id_do_modpack>
MCRUBY_JOIN_COMMUNITY_SERVER=1
```

A classe `MinecraftRubyLauncher::LauncherExtensions` lê essas variáveis e devolve as opções de lançamento.
