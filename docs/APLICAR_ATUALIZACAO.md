# Aplicar atualização completa RubyMC

Use estes arquivos após recuperar o commit bom do projeto.

```bash
cd ~/RubymineProjects/MinecraftLauncher

# pare o launcher antigo, se houver
./rubymc stop 2>/dev/null || true
sudo fuser -k 4567/tcp 2>/dev/null || true

# copie esta pasta para a raiz do projeto, sobrescrevendo os arquivos antigos
cp -rf rubymc_latest_project_update/* .
cp -rf rubymc_latest_project_update/.gitignore .

chmod +x rubymc bin/rubymc bin/launcher-web bin/run_launcher_checks.rb scripts/organize_project_root.rb

./rubymc restart
```

Abra:

```text
http://127.0.0.1:4567/?v=latest-update
```

Depois confira:

```bash
./rubymc status
./rubymc test
```
