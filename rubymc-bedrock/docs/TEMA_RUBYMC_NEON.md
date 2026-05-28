# Tema RubyMC Neon

Este patch troca a interface web do launcher para o padrão visual RubyMC das imagens enviadas:

- fundo escuro futurista;
- molduras metálicas com cantos chanfrados;
- rubis vermelhos nos cantos;
- brilho ciano/neon;
- pixel art central;
- painel estilo Discord Bot / Server Icon;
- display interno com aparência de terminal CRT.

## Arquivos principais

```text
web/index.html
web/assets/css/launcher.css
web/assets/js/launcher.js
web/assets/img/
```

## Como aplicar

Na raiz do projeto:

```bash
unzip minecraft_ruby_launcher_rubymc_neon_theme_patch.zip
cp -r minecraft_ruby_launcher_rubymc_neon_theme_patch/* .
```

Depois rode:

```bash
bundle exec ruby launcher_gui.rb
```

Se aparecer erro `cannot load such file -- webrick`, adicione ao `Gemfile`:

```ruby
gem 'webrick'
```

E rode:

```bash
bundle install
bundle exec ruby launcher_gui.rb
```

## Onde mudar o visual

Altere cores, brilho, sombras e fundo em:

```text
web/assets/css/launcher.css
```

As imagens ficam em:

```text
web/assets/img/
```
