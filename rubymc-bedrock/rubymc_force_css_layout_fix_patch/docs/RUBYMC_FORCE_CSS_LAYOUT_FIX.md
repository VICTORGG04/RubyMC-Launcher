# RubyMC Force CSS Layout Fix

Correção forte para layout espremido/quebrado.

## Aplica

```bash
cd ~/RubymineProjects/MinecraftLauncher/rubymc-bedrock

unzip -o ~/Downloads/rubymc_force_css_layout_fix_patch.zip
cp -rf rubymc_force_css_layout_fix_patch/* .

chmod +x scripts/apply_force_css_layout_fix.sh
./scripts/apply_force_css_layout_fix.sh

sudo fuser -k 4567/tcp 2>/dev/null || true
./rubymc restart
```

Depois recarregue a página com `Ctrl + Shift + R`.

Se o navegador estiver em zoom 50%, volte para 100% com `Ctrl + 0`.
