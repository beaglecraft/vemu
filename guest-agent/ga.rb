require 'socket'
require 'json'
require 'debug'

# path = "/dev/virtio-ports/io.vemu.guest_agent.0"
# fd = File.open(path, File::RDWR)

#
# IOCTL_VM_SOCKETS_GET_LOCAL_CID = 0x7b9
# fd = File.open('/dev/vsock', 'r')
# cid_out = String.new
# fd.ioctl(IOCTL_VM_SOCKETS_GET_LOCAL_CID, cid_out)
# cid = cid_out.unpack('I').first

# socket_path = Dir['/dev/vport*'].first
socket = Socket.new(Socket::AF_VSOCK, Socket::SOCK_STREAM)

# addr = Addrinfo.new([Socket::AF_VSOCK, 0, 6, cid, 0].pack('SSIII'))
# # addr = Addrinfo.new(6, Socket::AF_VSOCK, Socket::SOCK_STREAM)
#
# # addr = Addrinfo.new([cid, 6].pack('II'), Socket::AF_VSOCK, Socket::SOCK_STREAM)
# addr = Addrinfo.new([cid, 6].pack('II'), Socket::AF_VSOCK)

addr = Addrinfo.new([Socket::AF_VSOCK, 0,
    3030, # Port
    -1, # CID
    0 # zero padding
  ].pack('SSIII'))

socket.bind(addr)
socket.listen(1)
ga_socket, ga_addr = socket.accept
ga_sockaddr = ga_addr.to_sockaddr.unpack('SSIIx4')

puts "Got a client on CID #{ga_sockaddr[3]} port #{ga_sockaddr[2]}"

# debugger

data = JSON.parse(ga_socket.readline(chomp: true))
info = data['info']
return if info == '--finished--'

puts "Info from VM: #{info}"
