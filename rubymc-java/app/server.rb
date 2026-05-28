# frozen_string_literal: true

root = File.expand_path("..", __dir__)

$LOAD_PATH.unshift(File.join(root, "lib"))

require "bundler/setup"
require_relative "../lib/web_launcher_app"

host = ENV.fetch("RUBYMC_HOST", "127.0.0.1")
port = ENV.fetch("RUBYMC_PORT", "4567").to_i
simulate = ARGV.include?("--simulate") || ENV["RUBYMC_SIMULATE"] == "1"

RubyMC::WebLauncherApp.new(
  root: root,
  host: host,
  port: port,
  simulate: simulate
).start
