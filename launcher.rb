#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# Minecraft Ruby Launcher — Entry Point
#
# Uso:
#   ruby launcher.rb
#
# Pré-requisitos:
#   gem install bundler
#   bundle install
# =============================================================================

require_relative "lib/launcher_cli"

# Captura Ctrl+C com mensagem amigável
trap("INT") do
  puts "\n\n  \e[32mAté mais! o/\e[0m\n\n"
  exit(0)
end

LauncherCLI.new.run
