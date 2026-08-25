# Agent guide

This repository contains two dependency-free Ruby TCP-to-vsock bridges. Read
both scripts and `README.md` before changing behavior.

## Scripts and transports

- `host-vsock.rb` opens a native Linux `AF_VSOCK` stream to a guest CID and
  port. Use it with QEMU's `vhost-vsock-pci` device.
- `user-vsock.rb` opens the host-facing Unix socket created by
  `vhost-device-vsock`, sends its `CONNECT PORT\n` handshake, waits for
  `OK PORT\n`, and then forwards bytes. Use it with QEMU's
  `vhost-user-vsock-pci` device.

Do not merge or substitute these transport implementations. In particular, do
not add the Unix-socket handshake to `host-vsock.rb`, and do not require native
host vsock support in `user-vsock.rb`.

## Shared runtime behavior

- The known-good runtime is Ruby 4.0.5 on Linux.
- Traffic is copied in both directions. A completed direction half-closes the
  destination socket so SSH shutdown can complete normally.
- Each client is isolated in a worker thread. Guest or backend connection
  failures must be handled inside that worker and must never terminate the main
  TCP accept loop.
- Both scripts intentionally run in the foreground and exit cleanly on Ctrl-C.
- There are no gems or other third-party Ruby dependencies.

## CLI invariants

Shared options:

- `--bind` is required and accepts exactly these forms:
  - `PORT`, which must bind to the safe default address `127.0.0.1`.
  - `IPV4_ADDRESS:PORT`, which binds to the explicit IPv4 address.
- `--port` is the guest service port and defaults to 22.
- Host TCP ports are in `1..65535`.
- Guest ports are in `1..4294967295`.
- Invalid or missing arguments must fail before opening the TCP listener and
  print useful usage information.

Script-specific options:

- `host-vsock.rb` requires `--cid`, with no default. CIDs fit in an unsigned
  32-bit integer.
- `user-vsock.rb` requires a non-empty `--uds-path`, with no default. It does not
  accept a CID because the backend owns that configuration.

Preserve loopback as the implicit bind address. Never silently change the
port-only form to `0.0.0.0`.

## Transport details

`host-vsock.rb` packs the Linux `sockaddr_vm` as `S S L L x4`. This is a
16-byte native-endian structure containing the address family, reserved field,
port, CID, and zero padding. Change it only with a clear understanding of the
Linux ABI.

`user-vsock.rb` implements the `vhost-device-vsock` host-side protocol. Its
handshake response is bounded and must match the requested port before client
traffic is forwarded. A missing socket, refused guest port, malformed response,
or disconnected peer must affect only the current client.

## Validation

Start with syntax and CLI checks:

```bash
ruby -c host-vsock.rb
ruby -c user-vsock.rb
./host-vsock.rb --help
./user-vsock.rb --help
```

Check malformed and missing arguments when changing CLI parsing. Confirm the
port-only bind listens on `127.0.0.1` and an explicit bind listens on the
requested IPv4 address; use `ss -ltnp` to inspect listeners.

The local native-vsock test configuration is:

```bash
./host-vsock.rb --bind 0.0.0.0:41600 --cid 24 --port 22
```

The local vhost-user test configuration is:

```bash
./user-vsock.rb --bind 0.0.0.0:41600 --uds-path /tmp/vm24.sock --port 22
```

With one bridge running, a generic non-interactive SSH test is:

```bash
ssh -i ~/.ssh/vm_guest \
  -o ControlMaster=no \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=5 \
  -p 41600 vmuser@127.0.0.1 true
```

For lifecycle validation, test this sequence:

1. Start one bridge and confirm SSH works while QEMU and its backend are
   running.
2. Ask the user to stop QEMU or the relevant backend; do not stop or start their
   processes yourself.
3. Attempt SSH and confirm it fails while the same bridge process remains alive
   and listening.
4. Ask the user to restore the guest transport.
5. Confirm SSH recovers through that same bridge process.

Only stop bridge processes started during the current task. Do not terminate an
existing bridge, QEMU, or `vhost-device-vsock` process unless the user explicitly
requests it.

