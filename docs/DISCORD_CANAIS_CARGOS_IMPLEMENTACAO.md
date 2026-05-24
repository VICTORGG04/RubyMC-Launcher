# Discord: canais, cargos e permissões no RubyMC

Este patch implementa leitura e validação dos blocos `discord.channels` e `discord.roles` do `config/settings.yml`.

## Arquivos adicionados

- `lib/rubymc_settings.rb` — leitura centralizada do `config/settings.yml`.
- `lib/discord_config.rb` — valida IDs de canais, cargos, guild, client e token sem expor segredo.
- `lib/discord_bot_service.rb` — cliente REST para validar bot, enviar log ao Discord, criar convite e aplicar/remover cargo.
- `scripts/validate_discord_settings.rb` — validador via terminal.

## Painel Web

A interface ganhou a aba **Discord**, com botões:

- **Validar Discord**: valida configuração local e, se `bot_enabled: true`, tenta autenticar o bot na API do Discord.
- **Testar canal de logs**: envia uma mensagem de teste para `logs_channel_id`; se não existir, tenta `support_channel_id` ou `rubymc_channel_id`.

## Uso no terminal

```bash
ruby scripts/validate_discord_settings.rb
./rubymc restart
```

## Permissões esperadas do bot

Para envio de logs e convites:

- Ver canais
- Enviar mensagens
- Ler histórico de mensagens
- Incorporar links
- Criar convites

Para aplicar cargo de jogador automaticamente:

- Gerenciar cargos

O cargo do bot precisa estar acima dos cargos `Membro` e `Jogador` na hierarquia do Discord.

## Segurança

Não envie `config/settings.yml` com `bot_token` real para repositório público. Prefira versionar um exemplo e colocar o arquivo real no `.gitignore`.
