# TCP-to-vsock SSH bridges

These small Ruby programs expose a service inside a QEMU virtual machine as a
TCP listener on the host. They are primarily intended to make a guest SSH server
reachable by an ordinary SSH client.

```text
ssh client -> host TCP listener -> vsock transport -> guest sshd
```

Choose the script that matches the QEMU vsock transport:

| Script | Host transport | Use when |
| --- | --- | --- |
| `host-vsock.rb` | Native `AF_VSOCK` | QEMU uses `vhost-vsock-pci` and the host exposes real vsock sockets. |
| `user-vsock.rb` | Unix socket | QEMU uses `vhost-user-vsock-pci` with `vhost-device-vsock`. |

Both bridges run in the foreground, handle each connection in its own Ruby
thread, and stop cleanly with Ctrl-C.

## Common options

Both scripts require `--bind`. A bare port listens only on the safe loopback
default:

```text
--bind 41600             -> 127.0.0.1:41600
--bind 0.0.0.0:41600     -> 0.0.0.0:41600
```

Both also accept `--port PORT` for the service inside the guest. It defaults to
SSH port 22.

Binding to `0.0.0.0` exposes the listener on every host network interface. Only
use it when remote access is intended and controlled by an appropriate
firewall. These bridges provide no authentication or encryption themselves;
they pass bytes through to the guest service.

## Native host vsock

Use `host-vsock.rb` when the Linux host and QEMU provide native vsock support.
Ruby must expose `Socket::AF_VSOCK`; Ruby 4.0.5 is known to work.

An example QEMU device configuration is:

```text
-device vhost-vsock-pci,guest-cid=24
```

The guest CID is required on the bridge command line:

```text
Usage: host-vsock.rb --bind BIND --cid CID [--port PORT]
        --bind BIND                  Listen on PORT at 127.0.0.1, or on IPV4_ADDRESS:PORT
        --cid CID                    Guest vsock CID (required)
        --port PORT                  Guest vsock port (default: 22)
```

For example:

```bash
./host-vsock.rb --bind 41600 --cid 24
```

## Vhost-user vsock through a Unix socket

Use `user-vsock.rb` where real host vsock is unavailable. QEMU can attach a
vhost-user vsock device backed by shared memory:

```text
-machine ...,memory-backend=mem0
-chardev socket,id=vsock-user,path=/tmp/vhost24.sock
-device vhost-user-vsock-pci,chardev=vsock-user
-object memory-backend-memfd,id=mem0,size=8192M,share=on
```

Run `vhost-device-vsock` separately to provide the backend and its host-facing
Unix socket:

```bash
vhost-device-vsock \
  --vm guest-cid=24,socket=/tmp/vhost24.sock,uds-path=/tmp/vm24.sock
```

Pass that host-facing socket to the bridge:

```text
Usage: user-vsock.rb --bind BIND --uds-path PATH [--port PORT]
        --bind BIND                  Listen on PORT at 127.0.0.1, or on IPV4_ADDRESS:PORT
        --uds-path PATH              vhost-device-vsock Unix socket (required)
        --port PORT                  Guest vsock port (default: 22)
```

For example:

```bash
./user-vsock.rb --bind 0.0.0.0:41600 --uds-path /tmp/vm24.sock
```

The CID belongs to the `vhost-device-vsock` configuration, so this bridge does
not need a `--cid` option.

## Connecting

With either bridge listening on host TCP port 41600:

```bash
ssh -i ~/.ssh/vm_guest -o ControlMaster=no -p 41600 vmuser@127.0.0.1
```

## When the VM or backend is unavailable

Every incoming TCP connection gets a new guest-side connection. If the VM or
the selected vsock backend is unavailable, that client connection is closed and
an error is written to standard error. The bridge itself keeps listening and
works again automatically when the guest transport returns.

