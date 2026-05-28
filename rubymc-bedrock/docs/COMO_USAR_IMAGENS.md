# Imagens RubyMC Launcher

Extraia este ZIP dentro da raiz do projeto:

```bash
cd ~/RubymineProjects/MinecraftLauncher
unzip -o rubymc_all_project_images.zip
```

Depois faça commit:

```bash
git add docs/assets web/assets/img
git commit -m "docs: adiciona imagens e banner do RubyMC Launcher"
git push
```

## Imagem de fundo no CSS

No `web/assets/css/launcher.css`, use:

```css
body {
  background:
    linear-gradient(90deg, rgba(2, 8, 18, 0.90), rgba(2, 8, 18, 0.60), rgba(2, 8, 18, 0.92)),
    url("/assets/img/rubymc-background-neon.png") center center / cover fixed no-repeat;
}
```
