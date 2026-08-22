#!/usr/bin/env ruby

require "ipaddr"
require "optparse"
require "socket"

UINT32_MAX = (1 << 32) - 1
HANDSHAKE_LIMIT = 128

class HandshakeError < StandardError; end

def parse_integer(value, name, range)
  number = Integer(value, 10)
  return number if range.cover?(number)

  raise OptionParser::InvalidArgument, "#{name} must be in #{range}"
rescue ArgumentError
  raise OptionParser::InvalidArgument, "#{name} must be an integer"
end

def parse_bind(value)
  if value.match?(/\A\d+\z/)
    address = "127.0.0.1"
    port_text = value
  elsif (match = value.match(/\A([^:]+):(\d+)\z/))
    address, port_text = match.captures
  else
    raise OptionParser::InvalidArgument,
      "--bind must be PORT or IPV4_ADDRESS:PORT"
  end

  ip = IPAddr.new(address)
  unless ip.ipv4?
    raise OptionParser::InvalidArgument, "--bind address must be IPv4"
  end

  [ip.to_s, parse_integer(port_text, "--bind port", 1..65_535)]
rescue IPAddr::InvalidAddressError
  raise OptionParser::InvalidArgument, "--bind address must be a valid IPv4 address"
end

options = { guest_port: 22 }
parser = OptionParser.new do |arguments|
  arguments.banner = "Usage: #{File.basename($PROGRAM_NAME)} --bind BIND --uds-path PATH [--port PORT]"
  arguments.on("--bind BIND", "Listen on PORT at 127.0.0.1, or on IPV4_ADDRESS:PORT") do |value|
    options[:bind] = value
  end
  arguments.on("--uds-path PATH", "vhost-device-vsock Unix socket (required)") do |value|
    options[:uds_path] = value
  end
  arguments.on("--port PORT", "Guest vsock port (default: 22)") do |value|
    options[:guest_port] = parse_integer(value, "--port", 1..UINT32_MAX)
  end
end

begin
  parser.parse!
  raise OptionParser::InvalidArgument, "unexpected argument: #{ARGV.first}" unless ARGV.empty?

  missing = []
  missing << "--bind" unless options.key?(:bind)
  missing << "--uds-path" unless options.key?(:uds_path)
  unless missing.empty?
    raise OptionParser::MissingArgument, missing.join(", ")
  end
  if options[:uds_path].empty?
    raise OptionParser::InvalidArgument, "--uds-path must not be empty"
  end

  bind_address, bind_port = parse_bind(options[:bind])
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 1
end

def copy(source, destination)
  IO.copy_stream(source, destination)
rescue IOError, SystemCallError
  # Either peer may disconnect first.
ensure
  begin
    destination.shutdown(Socket::SHUT_WR)
  rescue IOError, SystemCallError
    nil
  end
end

def connect_to_guest(uds_path, guest_port)
  guest = UNIXSocket.new(uds_path)
  guest.write("CONNECT #{guest_port}\n")

  response = guest.gets("\n", HANDSHAKE_LIMIT)
  expected = "OK #{guest_port}\n"
  unless response == expected
    raise HandshakeError, "unexpected backend response: #{response.inspect}"
  end

  guest
rescue StandardError
  guest&.close
  raise
end

def handle(client, uds_path, guest_port)
  guest = connect_to_guest(uds_path, guest_port)

  client_to_guest = Thread.new { copy(client, guest) }
  copy(guest, client)
  client_to_guest.join
rescue HandshakeError, IOError, SystemCallError => error
  warn "connection failed: #{error.message}"
ensure
  guest&.close
  client.close
end

server = TCPServer.new(bind_address, bind_port)

begin
  loop do
    client = server.accept
    Thread.new { handle(client, options[:uds_path], options[:guest_port]) }
  end
rescue Interrupt
  # Exit cleanly when run in the foreground and interrupted with Ctrl-C.
ensure
  server.close
end
