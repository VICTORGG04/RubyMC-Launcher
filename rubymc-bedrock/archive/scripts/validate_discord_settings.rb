#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative '../lib/rubymc_settings'
require_relative '../lib/discord_config'

root = File.expand_path('..', __dir__)
settings = RubyMC::Settings.new(root).data
config = RubyMC::DiscordConfig.new(settings)
report = config.validation_report

puts 'RubyMC Discord Settings Validator'
puts '================================'
puts "Status: #{report[:ok] ? 'OK' : 'PENDENTE'}"
puts

summary = report[:summary]
puts "Bot ativo: #{summary[:bot_enabled]}"
puts "Client ID configurado: #{summary[:client_id_configured]}"
puts "Guild ID configurado: #{summary[:guild_id_configured]}"
puts "Token configurado: #{summary[:token_configured]}"
puts "Canais: #{summary[:channels_configured]}/#{summary[:channels_total]}"
puts "Cargos: #{summary[:roles_configured]}/#{summary[:roles_total]}"
puts

unless report[:warnings].empty?
  puts 'Avisos:'
  report[:warnings].each { |warning| puts "  - #{warning}" }
  puts
end

unless report[:errors].empty?
  puts 'Erros:'
  report[:errors].each { |error| puts "  - #{error}" }
  puts
end

puts 'Canais:'
report[:channels].each do |key, value|
  status = value[:configured] ? 'OK' : 'pendente'
  puts "  #{status.ljust(8)} #{key}: #{value[:id]}"
end
puts

puts 'Cargos:'
report[:roles].each do |key, value|
  status = value[:configured] ? 'OK' : 'pendente'
  puts "  #{status.ljust(8)} #{key}: #{value[:id]}"
end

exit(report[:ok] ? 0 : 1)
