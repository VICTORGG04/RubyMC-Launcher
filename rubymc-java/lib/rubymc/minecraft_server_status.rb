# frozen_string_literal: true

require 'json'
require 'socket'
require 'timeout'

module RubyMC
  module MinecraftServerStatus
    module_function

    DEFAULT_PORT = 25_565
    DEFAULT_TIMEOUT = 5
    PROTOCOL_VERSION = 767

    def query(address, timeout: DEFAULT_TIMEOUT)
      parsed = parse_address(address)
      return offline_payload(address, 'Servidor não configurado.') unless parsed[:host]

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Timeout.timeout(timeout) do
        socket = TCPSocket.new(parsed[:host], parsed[:port])
        socket.binmode

        send_handshake(socket, parsed[:host], parsed[:port])
        send_status_request(socket)

        read_varint(socket)
        packet_id = read_varint(socket)
        raise "Resposta inválida do servidor: packet_id=#{packet_id}" unless packet_id == 0

        json_length = read_varint(socket)
        raw_json = socket.read(json_length).force_encoding('UTF-8')
        data = JSON.parse(raw_json)

        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        socket.close

        normalize_response(address, parsed, data, latency_ms)
      end
    rescue StandardError => e
      offline_payload(address, e.message)
    end

    def parse_address(address)
      clean = address.to_s.strip
      clean = clean.sub(%r{\Aminecraft://}i, '')
      clean = clean.sub(%r{\Atcp://}i, '')
      clean = clean.sub(%r{\Ahttps?://}i, '')
      clean = clean.split('/').first.to_s

      return { host: nil, port: DEFAULT_PORT, address: clean } if clean.empty? || clean =~ /ID_DO|não configurado/i

      if clean.start_with?('[') && clean.include?(']')
        host = clean[/\A\[([^\]]+)\]/, 1]
        port = clean[/\]:(\d+)\z/, 1]&.to_i || DEFAULT_PORT
        return { host: host, port: port, address: "#{host}:#{port}" }
      end

      host, port = clean.split(':', 2)
      { host: host, port: (port && !port.empty? ? port.to_i : DEFAULT_PORT), address: clean }
    end

    def send_handshake(socket, host, port)
      body = +''.b
      body << write_varint(0)
      body << write_varint(PROTOCOL_VERSION)
      body << write_string(host)
      body << [port].pack('n')
      body << write_varint(1)
      socket.write(write_varint(body.bytesize) + body)
    end

    def send_status_request(socket)
      body = write_varint(0)
      socket.write(write_varint(body.bytesize) + body)
    end

    def normalize_response(address, parsed, data, latency_ms)
      players = data['players'] || {}
      sample = Array(players['sample']).map { |player| player['name'].to_s }.reject(&:empty?)
      version = data['version'] || {}

      {
        ok: true,
        online: true,
        address: address.to_s,
        host: parsed[:host],
        port: parsed[:port],
        status: 'online',
        latency_ms: latency_ms,
        version: {
          name: version['name'].to_s,
          protocol: version['protocol']
        },
        players: {
          online: players['online'].to_i,
          max: players['max'].to_i,
          sample: sample
        },
        description: plain_description(data['description']),
        checked_at: Time.now.strftime('%H:%M:%S')
      }
    end

    def offline_payload(address, error)
      {
        ok: false,
        online: false,
        address: address.to_s,
        host: nil,
        port: DEFAULT_PORT,
        status: 'offline',
        latency_ms: nil,
        version: { name: '', protocol: nil },
        players: { online: 0, max: 0, sample: [] },
        description: '',
        checked_at: Time.now.strftime('%H:%M:%S'),
        error: error.to_s
      }
    end

    def plain_description(value)
      case value
      when String
        value
      when Hash
        text = value['text'].to_s
        extras = Array(value['extra']).map { |item| plain_description(item) }.join
        text + extras
      when Array
        value.map { |item| plain_description(item) }.join
      else
        value.to_s
      end.gsub(/\s+/, ' ').strip
    end

    def write_string(value)
      bytes = value.to_s.b
      (write_varint(bytes.bytesize) + bytes).force_encoding('BINARY')
    end

    def read_varint(io)
      num_read = 0
      result = 0

      loop do
        byte = io.read(1)
        raise 'Resposta incompleta do servidor.' unless byte

        value = byte.unpack1('C')
        result |= (value & 0x7F) << (7 * num_read)
        num_read += 1

        raise 'VarInt grande demais.' if num_read > 5
        break if (value & 0x80).zero?
      end

      result
    end

    def write_varint(value)
      value &= 0xFFFFFFFF
      out = +''.b
      loop do
        temp = value & 0x7F
        value >>= 7
        temp |= 0x80 unless value.zero?
        out << temp
        break if value.zero?
      end
      out
    end
  end
end
