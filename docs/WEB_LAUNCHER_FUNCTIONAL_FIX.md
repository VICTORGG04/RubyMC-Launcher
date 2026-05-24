# Correção funcional do RubyMC Web Launcher

Este patch corrige o problema em que a tela Web carregava, mas ficava presa em
`Conectando display...` ou botões não executavam ações.

## Arquivos alterados

- `launcher_gui.rb`
- `lib/web_launcher_app.rb`
- `web/index.html`
- `web/assets/js/launcher.js`
- `web/assets/css/launcher.css`
- `rubymc`
- `bin/rubymc`

## Como aplicar

```bash
cd ~/RubymineProjects/MinecraftLauncher
unzip -o ~/Downloads/rubymc_web_functional_fix.zip
cp -rf rubymc_web_functional_fix/* .
chmod +x rubymc bin/rubymc
./rubymc restart
```

Abra:

```text
http://127.0.0.1:4567/?v=functional-fix-1
```
