#!/usr/bin/env ruby
# frozen_string_literal: true

# Simulates a Minecraft server with 20 fake players for testing the RubyMC web panel.
# Listens on 0.0.0.0:25566 and responds to Server List Ping with fake data.
#
# Usage:
#   ruby bin/simulate_mc_players.rb
#   ruby bin/simulate_mc_players.rb --port 25567
#   ruby bin/simulate_mc_players.rb --players 50 --max 100

require 'json'
require 'socket'

def arg_value(flag, default)
  idx = ARGV.index(flag)
  idx ? Integer(ARGV[idx + 1]) : default
rescue ArgumentError, TypeError
  default
end

PORT = arg_value('--port', 25_566).freeze
PLAYERS_ONLINE = arg_value('--players', 20).freeze
MAX_PLAYERS = arg_value('--max', 100).freeze

SERVER_VERSION = 'RubyMC 1.0 (MC: 1.21.4)'
MOTD = '{"text":"RubyMC Launcher","color":"red","bold":true},{"text":" — ","color":"white"},{"text":"Servidor da Comunidade","color":"cyan"}'

PLAYER_NAMES = %w[
  Steve Alex Notch Herobrine Dinnerbone Jeb_ Grum Searge C_P_Luffy
  ZecaUrubu NinjaBR MinecraftBR L33T_H4x0r Noob_Master Xx_King_xX
  RainbowDash Poney_FF BuildMaster Redstone_God Enderman_Fan
]

def write_varint(value)
  out = +''
  loop do
    temp = value & 0x7F
    value >>= 7
    temp |= 0x80 unless value.zero?
    out << temp.chr
    break if value.zero?
  end
  out
end

def read_varint(socket)
  num_read = 0
  result = 0
  loop do
    byte = socket.getbyte
    break unless byte
    result |= (byte & 0x7F) << (7 * num_read)
    num_read += 1
    break if (byte & 0x80).zero? || num_read > 5
  end
  result
end

def build_status_response
  sample = PLAYER_NAMES.first(PLAYERS_ONLINE).each_with_index.map do |name, i|
    { 'id' => format('00000000-0000-0000-0000-%012d', i + 1), 'name' => name }
  end

  data = {
    'version' => { 'name' => SERVER_VERSION, 'protocol' => 767 },
    'players' => { 'online' => PLAYERS_ONLINE, 'max' => MAX_PLAYERS, 'sample' => sample },
    'description' => [{ 'text' => '', 'extra' => JSON.parse("[#{MOTD}]") }],
    'favicon' => nil,
    'enforcesSecureChat' => false
  }

  JSON.generate(data)
end

puts <<~BANNER
  \e[36m╔══════════════════════════════════════════╗
  ║   RubyMC Minecraft Server Simulator    ║
  ║   #{PLAYERS_ONLINE}/#{MAX_PLAYERS} players online              ║
  ║   Listening on port #{PORT.to_s.ljust(5)}                    ║
  ╚══════════════════════════════════════════╝\e[0m
BANNER

server = TCPServer.new('0.0.0.0', PORT)
status_payload = nil

loop do
  Thread.start(server.accept) do |client|
    begin
      client.binmode
      packet_len = read_varint(client)
      handshake_body = client.read(packet_len) rescue ''
      next if handshake_body.nil? || handshake_body.bytesize < 2

      handshake = +''
      handshake << write_varint(packet_len)
      handshake << handshake_body

      next_state = handshake_body.bytes.last

      if next_state == 1
        # Status request
        req_len = read_varint(client)
        req_data = client.read(req_len) rescue ''

        status_payload ||= build_status_response
        json_bytes = status_payload.b
        response = +''
        response << write_varint(0)
        response << write_varint(json_bytes.bytesize)
        response << json_bytes
        client.write(write_varint(response.bytesize) + response)

        # Ping (optional)
        ping_len = read_varint(client)
        ping_data = client.read(ping_len) rescue ''
        client.write(write_varint(ping_len) + ping_data) if ping_data
      end
    rescue => e
      $stderr.puts "  \e[31m[ERROR]\e[0m #{e.message}"
    ensure
      client.close rescue nil
    end
  end
end
