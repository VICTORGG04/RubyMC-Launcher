# frozen_string_literal: true

require 'socket'
require 'timeout'

module RubyMC
  module BedrockServerStatus
    module_function

    DEFAULT_PORT = 19_132
    DEFAULT_TIMEOUT = 5
    MAGIC = ["00ffff00fefefefefdfdfdfd12345678"].pack('H*').freeze

    def query(address, timeout: DEFAULT_TIMEOUT)
      parsed = parse_address(address)
      return offline_payload(address, 'Servidor não configurado.') unless parsed[:host]

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Timeout.timeout(timeout) do
        socket = UDPSocket.new
        socket.connect(parsed[:host], parsed[:port])

        ping_id = [Time.now.to_i].pack('Q<')
        client_guid = [0].pack('Q<')
        request = "\x01" + ping_id + MAGIC + client_guid
        socket.send(request, 0)

        raw, _ = socket.recvfrom(2048)
        socket.close

        raise 'Resposta muito curta' if raw.bytesize < 35

        response_type = raw.getbyte(0)
        raise "Tipo inesperado: #{response_type}" unless response_type == 0x1c

        magic_offset = raw.index(MAGIC)
        raise 'MAGIC não encontrado na resposta' unless magic_offset

        len_offset = magic_offset + MAGIC.bytesize
        server_data_len = raw.byteslice(len_offset, 2)&.unpack1('n') || 0
        raise 'Dados do servidor vazios' if server_data_len <= 0

        server_data = raw.byteslice(len_offset + 2, server_data_len)
        raise 'server_data é nil' if server_data.nil?
        parts = server_data.force_encoding('UTF-8').split(';').map(&:strip)

        latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        edition  = parts[0] || 'MCPE'
        motd     = parts[1] || ''
        protocol = parts[2] || ''
        version  = parts[3] || ''
        players  = parts[4].to_i
        max_players = parts[5].to_i
        gamemode = parts[8] || ''
        level    = parts[7] || ''

        {
          ok: true,
          online: true,
          address: address.to_s,
          host: parsed[:host],
          port: parsed[:port],
          status: 'online',
          latency_ms: latency_ms,
          edition: edition,
          version: {
            name: version.to_s,
            protocol: protocol.to_s
          },
          players: {
            online: players,
            max: max_players,
            sample: []
          },
          description: motd,
          gamemode: gamemode,
          level_name: level,
          checked_at: Time.now.strftime('%H:%M:%S')
        }
      end
    rescue StandardError => e
      offline_payload(address, e.message)
    end

    def parse_address(address)
      clean = address.to_s.strip
      clean = clean.sub(%r{\Audp://}i, '')
      clean = clean.sub(%r{\Araknet://}i, '')
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

    def offline_payload(address, error)
      {
        ok: false,
        online: false,
        address: address.to_s,
        host: nil,
        port: DEFAULT_PORT,
        status: 'offline',
        latency_ms: nil,
        edition: '',
        version: { name: '', protocol: '' },
        players: { online: 0, max: 0, sample: [] },
        description: '',
        gamemode: '',
        level_name: '',
        checked_at: Time.now.strftime('%H:%M:%S'),
        error: error.to_s
      }
    end
  end
end
