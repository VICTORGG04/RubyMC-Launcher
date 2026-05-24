#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/web_launcher_app'

root = File.expand_path(__dir__)
port = Integer(ENV.fetch('RUBYMC_PORT', '4567'))
host = ENV.fetch('RUBYMC_HOST', '127.0.0.1')

RubyMC::WebLauncherApp.new(root: root, host: host, port: port).start
