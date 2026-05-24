# Importação de Modpacks pela Interface Web

Este patch adiciona a opção **Importar Modpack** dentro da aba **Modpacks** do RubyMC Launcher Web.

## O que foi adicionado

- Campo para nome do perfil do modpack.
- Seletor de arquivo `.mrpack` ou `.zip`.
- Botão **Importar modpack**.
- Lista de modpacks importados.
- Atualização automática do contador de modpacks.
- Atualização automática do seletor de perfil na aba **Início**.
- Logs da importação no **Display interno**.
- Endpoint backend `POST /api/modpacks/import`.
- Endpoint backend `GET /api/modpacks`.

## Formatos suportados

- `.mrpack` — Modrinth.
- `.zip` — CurseForge ou pacote genérico.

Quando `lib/modpack_manager.rb` estiver disponível, o backend usa o gerenciador avançado de modpacks do projeto. Se houver algum problema, o backend salva o arquivo em modo fallback dentro de `~/.minecraft_ruby_launcher/modpacks`.

## Como testar

```bash
./rubymc restart
```

Abra:

```text
http://127.0.0.1:4567/?v=modpack-import-1
```

Acesse a aba **Modpacks**, selecione um arquivo `.mrpack` ou `.zip` e clique em **Importar modpack**.
