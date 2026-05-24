# Correção de botões e integração frontend/backend

Este patch corrige o problema em que o painel web carregava visualmente, mas os botões não executavam ações.

## O que foi corrigido

- `web/assets/js/launcher.js` passou a usar delegação global de eventos.
- Todos os botões do `web/index.html` receberam `type="button"`, evitando submissão acidental de formulário.
- O botão de importação de modpack continua sendo `type="submit"` e usa o formulário correto.
- O backend `lib/web_launcher_app.rb` recebeu rota `/api/ping` para diagnóstico.
- A rota `/api/action` agora aceita ação por JSON e por query string.
- O Display interno registra quando o JavaScript conectou e quando uma ação foi enviada.

## Como testar

```bash
./rubymc restart
```

Abra:

```text
http://127.0.0.1:4567/?v=buttons-fix-1
```

Pressione `Ctrl + F5`.

Na aba Display deve aparecer algo como:

```text
JS conectado. Botões habilitados.
```
