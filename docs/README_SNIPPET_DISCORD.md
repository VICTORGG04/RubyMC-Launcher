## Discord: canais e cargos

O RubyMC lê os IDs do Discord em `config/settings.yml`:

```yaml
discord:
  channels:
    welcome_channel_id: "..."
    support_channel_id: "..."
    logs_channel_id: "..."
  roles:
    member_role_id: "..."
    player_role_id: "..."
    staff_role_id: "..."
    admin_role_id: "..."
    bot_role_id: "..."
```

Valide a configuração com:

```bash
ruby scripts/validate_discord_settings.rb
```

Ou pela aba **Discord** do launcher web.
