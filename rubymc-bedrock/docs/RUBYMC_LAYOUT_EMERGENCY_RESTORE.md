# RubyMC Layout Emergency Restore

Este patch corrige o layout quebrado após a substituição indevida do `web/index.html`.

## O que ele faz

1. Restaura o backup `web/index.html.bak.discord-panel-bg-*`.
2. Não substitui novamente o HTML original.
3. Adiciona CSS seguro para estabilizar sidebar, grid, cards e abas.
4. Adiciona JS leve para sincronizar `data-current-tab`.
5. Mantém transição suave de fundos entre abas.

## Aplicar

```bash
cd ~/RubymineProjects/MinecraftLauncher/rubymc-bedrock

unzip -o ~/Downloads/rubymc_layout_emergency_restore_patch.zip
cp -rf rubymc_layout_emergency_restore_patch/* .

chmod +x scripts/apply_layout_emergency_restore.sh
./scripts/apply_layout_emergency_restore.sh

sudo fuser -k 4567/tcp 2>/dev/null || true
./rubymc restart
```
