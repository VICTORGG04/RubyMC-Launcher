# RubyMC — Comando único

Este patch adiciona o comando `./rubymc` na raiz do projeto.

## Uso principal

```bash
./rubymc
```

Esse comando faz automaticamente:

1. verifica o `Gemfile`;
2. remove dependências gráficas antigas que causavam conflito (`glimmer-dsl-tk`, `glimmer-dsl-libui`, `tk`, `libui`);
3. garante as gems do launcher web (`webrick`, `rubyzip`, `httparty`, etc.);
4. roda `bundle install` se necessário;
5. libera a porta `4567` se ficou presa;
6. inicia o launcher web;
7. abre o navegador em `http://127.0.0.1:4567`.

## Subcomandos

```bash
./rubymc web        # inicia o launcher web
./rubymc restart    # reinicia o launcher web
./rubymc stop       # para o launcher web
./rubymc status     # mostra PID/porta
./rubymc logs       # acompanha logs
./rubymc classic    # abre o launcher clássico no terminal atual
./rubymc bot        # inicia o bot Discord
./rubymc test       # roda checagens do projeto
./rubymc organize   # organiza arquivos soltos da raiz
./rubymc install    # só instala/corrige dependências
```

## Porta alternativa

```bash
RUBYMC_PORT=4568 ./rubymc
```

## Observação

O launcher web continua usando `launcher_gui.rb`, mas agora o jeito recomendado é iniciar por `./rubymc`.
