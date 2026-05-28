# RubyMC Discord Channels/Roles Documented Model

Este patch documenta e padroniza a sessão:

```yaml
discord:
  channels:
  roles:
```

## Onde fica

```text
config/settings.yml
```

## Aplicar

```bash
cd ~/RubymineProjects/MinecraftLauncher

unzip -o ~/Downloads/rubymc_discord_channels_roles_documented_patch.zip
cp -rf rubymc_discord_channels_roles_documented_patch/* .

chmod +x scripts/apply_discord_channels_roles_documented.sh
./scripts/apply_discord_channels_roles_documented.sh
```

Depois reinicie:

```bash
./rubymc restart
```

E o bot:

```bash
bundle exec ruby bot_daemon.rb
```

## Mapeamento antigo → novo

```text
bem_vindos      -> welcome_channel_id
novos_membros   -> new_members_channel_id
noticias        -> announcements_channel_id
comunicados     -> updates_channel_id
chat_rubymc     -> general_channel_id
logs            -> logs_channel_id
modpacks        -> modpacks_channel_id
suporte         -> support_channel_id
```

## Commit

```bash
git add config/settings.yml config/discord_channels_roles.reference.yml bot_daemon.rb scripts/apply_discord_channels_roles_documented.sh docs/RUBYMC_DISCORD_CHANNELS_ROLES_DOCUMENTED.md

git commit -m "fix: documenta canais e cargos Discord do RubyMC"

git push
```
