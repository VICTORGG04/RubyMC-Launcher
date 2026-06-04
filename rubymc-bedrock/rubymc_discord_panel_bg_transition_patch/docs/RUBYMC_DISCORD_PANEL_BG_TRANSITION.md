# RubyMC Discord Panel + Background Transition

Implementa:

- Painel Discord mais completo.
- Card principal com status do bot, canais e cargos.
- Diagnóstico visual para token, guild, logs e configuração.
- Card de permissões/cargos.
- Transição suave de imagem de fundo ao trocar abas.
- Correção extra para navegação por `.side-link` e `.tab-link`.

## Aplicar

```bash
cd ~/RubymineProjects/MinecraftLauncher/rubymc-bedrock

unzip -o ~/Downloads/rubymc_discord_panel_bg_transition_patch.zip
cp -rf rubymc_discord_panel_bg_transition_patch/* .

chmod +x scripts/apply_discord_panel_bg_transition.sh
./scripts/apply_discord_panel_bg_transition.sh

./rubymc restart
```
