# Correção da lógica backend do Discord

Este patch corrige a integração real entre a aba **Discord** do launcher web e o backend Ruby.

## O que foi corrigido

- Botões **Validar Discord** e **Testar canal de logs** agora usam rotas backend dedicadas.
- Backend registra erros reais no Display interno.
- `bot_enabled` aceita `true`, `1`, `yes`, `sim`, `on`, `ativo` e `enabled`.
- `bot_token` pode vir de `config/settings.yml` ou da variável `RUBYMC_DISCORD_BOT_TOKEN`.
- Se o token for colado como `Bot xxxxx`, o backend remove automaticamente o prefixo duplicado.
- `logs_channel_id` tem fallback para `support_channel_id`, `rubymc_channel_id` e `general_channel_id`.
- Validação remota agora tenta autenticar o bot, ler guild, canais e cargos.
- Erros comuns agora aparecem claramente no Display.

## Checklist mínimo para funcionar

No `config/settings.yml`:

```yaml
discord:
  bot_enabled: true
  bot_token: "SEU_TOKEN_DO_BOT"
  guild_id: "ID_DO_SERVIDOR"
  channels:
    logs_channel_id: "ID_DO_CANAL_LOGS"
  roles:
    bot_role_id: "ID_DO_CARGO_DO_BOT"
```

O bot precisa ter permissão de **Ver canal**, **Enviar mensagens** e **Ler histórico de mensagens** no canal configurado em `logs_channel_id`.

Se for entregar cargos no futuro, o cargo do bot precisa ficar acima dos cargos `Membro` e `Jogador` na hierarquia do Discord.
