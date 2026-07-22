#!/usr/bin/env ruby
require 'socket'
require 'fcntl'
require 'json'
puts "Start vemu guestagent"

lsb_info = `lsb_release -a`
puts lsb_info

###### VSock version:
# socket = Socket.new(Socket::AF_VSOCK, Socket::SOCK_STREAM)
# addr = Addrinfo.new([Socket::AF_VSOCK, 0,
#     3030, # Port
#     2, # CID (2 = host)
#     0 # zero padding
#   ].pack('SSIII'))
#
# socket.connect(addr)
# socket.write("#{JSON.dump({ info: `ip link`, type: 'link' })}\n")
# socket.close

path = "/dev/virtio-ports/io.vemu.guest_agent.0"
fd = IO.sysopen(path, Fcntl::O_NOCTTY | Fcntl::O_RDWR)
fp = File.open(fd)
fp.sync = true

fp.write("#{JSON.dump({ info: `ip link`, type: 'link' })}\n")
fp.write("#{JSON.dump({ info: `ip addr`, type: 'addr' })}\n")

fp.write("#{JSON.dump({ info: lsb_info })}\n")
fp.write("#{JSON.dump({ info: '--finished--' })}\n")
