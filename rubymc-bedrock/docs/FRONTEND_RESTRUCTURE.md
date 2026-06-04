# RubyMC Frontend Restructure

Este pacote reestrutura o frontend do RubyMC para a versão atual do projeto.

## Arquivos atualizados

```text
web/index.html
web/termos.html
web/assets/css/launcher.css
web/assets/css/bedrock-download-fix.css
web/assets/css/server-java-page.css
web/assets/js/utils.js
web/assets/js/launcher.js
web/assets/js/server-runtime-selector.js
web/assets/js/rubymc-ai-support.js
```

## Correções principais

- HTML principal corrigido com fechamento adequado de `<head>` e abertura de `<body>`.
- CSS principal refeito e organizado por seções.
- Larguras padronizadas entre páginas.
- Grids corrigidos.
- Cards com tamanho consistente.
- Responsividade revisada.
- Fundos duplicados removidos.
- Aba Servidor usando fundo único.
- Aba Modpacks usando fundo único.
- Aba Versões reorganizada.
- Aba IA reorganizada.
- Aba Discord em grid responsivo.
- Aba Configurações padronizada.
- Overscroll/fundo branco corrigido.
- Seletores antigos de Server Runtime mantidos.

## Aplicação

```bash
cd ~/RubymineProjects/MinecraftLauncher

unzip -o ~/Downloads/rubymc_frontend_restructure_pack.zip
cp -rf rubymc_frontend_restructure_pack/* .

chmod +x scripts/apply_frontend_restructure.sh
./scripts/apply_frontend_restructure.sh
```

## Reiniciar

```bash
cd rubymc-bedrock
./rubymc restart
```

ou, se aplicado no projeto Java:

```bash
cd rubymc-java
./rubymc restart
```

## Cache

Abra:

```text
http://127.0.0.1:4567/?v=rubymc-layout-restructure-1
```
