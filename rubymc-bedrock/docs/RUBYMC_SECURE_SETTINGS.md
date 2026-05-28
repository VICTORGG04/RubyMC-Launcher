# RubyMC Secure settings.yml

Este patch aplica o `settings.yml` com os IDs informados e deixa o token do Discord fora do GitHub.

## Aplicar

```bash
cd ~/RubymineProjects/MinecraftLauncher

unzip -o ~/Downloads/rubymc_settings_apply_secure_patch.zip
cp -rf rubymc_settings_apply_secure_patch/* .

chmod +x scripts/apply_secure_settings.sh
./scripts/apply_secure_settings.sh
```

## Definir token localmente

Gere um token novo no Discord Developer Portal e rode:

```bash
export RUBYMC_DISCORD_BOT_TOKEN='COLE_SEU_TOKEN_NOVO_AQUI'
```

Depois:

```bash
bundle exec ruby bot_daemon.rb
```

## Importante

O token antigo foi exposto e deve ser regenerado.
