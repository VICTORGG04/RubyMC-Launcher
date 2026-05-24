# Aplicar atualização de canais e cargos Discord

```bash
cd ~/RubymineProjects/MinecraftLauncher

./rubymc stop 2>/dev/null || true
sudo fuser -k 4567/tcp 2>/dev/null || true

unzip -o ~/Downloads/rubymc_discord_roles_channels_update.zip
cp -rf rubymc_discord_roles_channels_update/* .

chmod +x scripts/validate_discord_settings.rb
ruby scripts/validate_discord_settings.rb

./rubymc restart
```

Abra:

```text
http://127.0.0.1:4567/?v=discord-roles-1
```

Na aba **Discord**, use **Validar Discord** e depois **Testar canal de logs**.
```
