# RubyMC AI Support — Qwen 3.5 9B

Implementa suporte IA local no RubyMC usando Ollama:

```text
qwen3.5:9b
6488c96fa5fa
```

## Instalar modelo

```bash
ollama pull qwen3.5:9b
ollama serve
```

## Aplicar

```bash
cd ~/RubymineProjects/MinecraftLauncher

./rubymc stop 2>/dev/null || true
sudo fuser -k 4567/tcp 2>/dev/null || true

unzip -o ~/Downloads/rubymc_ai_support_qwen_patch.zip
cp -rf rubymc_ai_support_qwen_patch/* .

chmod +x scripts/apply_ai_support_qwen.sh
./scripts/apply_ai_support_qwen.sh

./rubymc restart
```

Abra:

```text
http://127.0.0.1:4567/?v=rubymc-ai-support-qwen-1
```

## Endpoints

```text
GET  /api/ai/health
POST /api/ai/support
```

## Teste

```bash
curl http://127.0.0.1:4567/api/ai/health
```

```bash
curl -X POST http://127.0.0.1:4567/api/ai/support \
  -H "Content-Type: application/json" \
  -d '{"message":"Como configuro o Discord no RubyMC?"}'
```

## Commit

```bash
git add lib/ai_support_service.rb lib/web_launcher_app.rb web/assets/js/launcher.js web/assets/js/rubymc-ai-support.js web/assets/css/launcher.css web/assets/css/rubymc-ai-support.css web/index.html scripts/apply_ai_support_qwen.sh docs/RUBYMC_AI_SUPPORT_QWEN.md config/ai_support.settings.yml config/settings.yml

git commit -m "feat: adiciona suporte IA local com Qwen no RubyMC"

git push
```
