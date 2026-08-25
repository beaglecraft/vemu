module Vemu
  module VmCommand
    def qemu_cmd_arguments
      ## Machine

      machine_args = [
        "-m", @memory,
        "-smp", "#{@cpus},sockets=1,cores=#{@cpus},threads=#{@threads_per_core}",
      ]

      if @arch == 'amd64'
        mem_backend = (@vsock_mode == :user ? ',memory-backend=mem0' : nil)
        uefi = ',pflash0=uefi_code,pflash1=uefi_vars'

        machine_args += [
          "-machine", "q35,usb=off,accel=kvm#{uefi}#{mem_backend}",
          "-cpu", "host",
          "-vga", "none",

          "-blockdev", "driver=file,filename=#{@host_info.ovmf_code_path},node-name=uefi_code,read-only=on",
          "-blockdev", "driver=file,filename=#{ovmf_vars_path},node-name=uefi_vars",

          # "-drive", "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd",
          # "-boot", "order=c,splash-time=0,menu=on",
          "-boot", "menu=on",
        ]
      elsif @arch == 'arm64'
        # TODO: arm64 hasn't been tested quite well, no expectations that it actually works.
        #
        # cp /usr/share/AAVMF/AAVMF_VARS.fd /home/masterapp/.vemu/vms/early/kvm_vars.fd

        raise "must copy the /usr/share/AAVMF/AAVMF_VARS.fd file"

        machine_args += [
          "-machine", "virt",
          "-accel", "tcg,thread=multi",
          "-cpu", "cortex-a57", # "max",
          # "-drive", "if=pflash,format=raw,readonly=on,file=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd",

          "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd",
          "-drive", "if=pflash,format=raw,unit=1,file=/home/masterapp/.vemu/vms/early/kvm_vars.fd",
        ]
      end

      ## Storage

      # # docs on the -drive option:
      # #   https://www.heiko-sieger.info/qemu-system-x86_64-drive-options/
      # #   https://qemu.weilnetz.de/doc/6.0/system/invocation.html
      # #
      # #   It's more user-friendly than the newer -blockdev + -device combination, but the latter is recommended for scripting due to better stability guarantees.
      # storage_args = [
      #   "-drive", "file=#{diffdisk_path},if=virtio,discard=on,cache=unsafe"
      #   # -blockdev driver=raw,node-name=drive0,file.driver=file,file.filename=~/lime/ubu-virt/diffdisk,discard=unmap,cache.direct=off,cache.no-flush=on
      #   # -device virtio-blk-pci,drive=drive0
      # ]

      # Talking to AI: https://gemini.google.com/app/81067894fa87ef58
      # The `-drive` option above is considered legacy and/or not as flexible as the one below.

      # storage_args = [
      #   "-blockdev", "driver=qcow2,node-name=disk0,discard=unmap,cache.direct=on,cache.no-flush=off,file.driver=file,file.filename=#{diffdisk_path}",
      #   "-device", "virtio-blk-pci,drive=disk0"
      # ]

      storage_args = [
        # 1. Create the SCSI Controller device - this controller is also used by cloudinit_args below.
        "-device", "virtio-scsi-pci,id=scsi_ctrl0",

        # 2. Define the block backend with caching and discard properties
        "-blockdev", "driver=qcow2,node-name=disk0_backend,discard=unmap,cache.direct=on,cache.no-flush=off,file.driver=file,file.filename=#{diffdisk_path}",
        # 3. Attach a SCSI hard drive frontend to the controller and link it to the backend
        "-device", "scsi-hd,bus=scsi_ctrl0.0,scsi-id=0,drive=disk0_backend,id=disk0,bootindex=0"
      ]

      # CloudInit disk

      # cloudinit_args = [
      #   "-drive", "id=cdrom0,if=none,format=raw,readonly=on,file=#{cloud_init_img_path}",
      #   "-device", "virtio-scsi-pci,id=scsi0",
      #   "-device", "scsi-cd,bus=scsi0.0,drive=cdrom0",
      # ]
      cloudinit_args = [

        "-blockdev", "driver=file,filename=#{cloud_init_img_path},node-name=cdrom0,read-only=on",
        "-device", "scsi-cd,bus=scsi_ctrl0.0,scsi-id=1,drive=cdrom0,id=cdrom_dev0"

        # 3. CD-ROM Backend & Frontend (Targeting the SAME controller, different SCSI ID)
        # "-drive", "id=cdrom0,if=none,format=raw,readonly=on,file=#{cloud_init_img_path}",
        # "-device", "scsi-cd,bus=scsi_ctrl0.0,scsi-id=1,drive=cdrom0,id=cdrom_dev0"
      ]

      ## Networking
      # https://wiki.qemu.org/Documentation/Networking

      network_args = []

      # If no network config is provided, qemu will provide a network implicitly.
      # We don't want that, Instead we want no network/internet connection.
      if @offline_mode && !@network_cards.empty?
        raise "Invalid: offline mode was requested but network card list is non-empty. Aborting."
      end
      if @network_cards.empty? || @offline_mode
        network_args += [
          "-nic", "none"
        ]
      end

      @network_cards.each do |card|
        if card[:mode] == 'tap'
          network_args += [
            "-device", "virtio-net-pci,netdev=#{card[:net_device]},mac=#{card[:mac_address]}",
            "-netdev", "tap,id=#{card[:net_device]},ifname=#{card[:tap_device]},script=no,downscript=no",
          ]
        elsif card[:mode] == 'user'
          network_args += [
            # ,hostfwd=tcp:127.0.0.1:44647-:22
            "-netdev", "user,id=#{card[:net_device]},net=192.168.5.0/24,dhcpstart=192.168.5.15",
            "-device", "virtio-net-pci,netdev=#{card[:net_device]},mac=#{card[:mac_address]}",
          ]
        else
          raise "Unrecognized device mode: '#{card[:mode]}'"
        end
      end

      guestagent_args = []
      if @guestagent_enabled
        guestagent_args += [
          # Guest Agent port
          "-chardev", "socket,path=#{ga_socket_path},server=on,wait=off,id=vemu-ga",
          "-device", "virtserialport,bus=virtio-serial0.0,chardev=vemu-ga,name=io.vemu.guest_agent.0",
        ]
      end

      extra_args = []

      if @vsock_cid
        if @vsock_mode == :host
          extra_args += [
            "-device", "vhost-vsock-pci,id=vhost-vsock-pci0,guest-cid=#{@vsock_cid}",
          ]
        elsif @vsock_mode == :user
          # vhost-device-vsock --vm guest-cid=24,socket=/tmp/vhost24.sock,uds-path=/tmp/vm24.sock
          extra_args += [
            "-chardev", "socket,id=vsock-user,path=/tmp/vhost#{@vsock_cid}.sock",
            "-device", "vhost-user-vsock-pci,chardev=vsock-user",
            "-object", "memory-backend-memfd,id=mem0,size=#{@memory}M,share=on",
          ]
        else
          raise "vsock_cid specified but vsock_mode has invalid value: '#{@vsock_mode}'"
        end
      end

      serial_args = [
        # serial.log
        "-chardev", "socket,id=char-serial,path=#{serial_socket_path},server=on,wait=off,logfile=#{serial_log_path}",
        "-serial", "chardev:char-serial",

        # serialv.log
        "-device", "virtio-serial-pci,id=virtio-serial0",
        "-chardev", "socket,id=char-serial-virtio,path=#{serial_v_socket_path},server=on,wait=off,logfile=#{serial_v_log_path}",
        # "-device", "virtio-serial-pci,id=virtio-serial0,max_ports=1",
        # "-device", "virtio-serial-pci,id=virtio-serial0",
        "-device", "virtconsole,bus=virtio-serial0.0,chardev=char-serial-virtio,id=console0",
      ]

      other_args = [
        "-device", "virtio-rng-pci",
        "-display", "none",
        # "-device", "virtio-gpu-pci", # "-device", "virtio-vga",
        # "-device", "virtio-keyboard-pci",
        # "-device", "virtio-mouse-pci",
        "-device", "qemu-xhci,id=usb-bus",
        "-parallel", "none",

        # QMP
        "-chardev", "socket,id=char-qmp,path=#{qmp_socket_path},server=on,wait=off",
        "-qmp", "chardev:char-qmp",

        "-name", @name,
        "-pidfile", qemu_pid_path
      ]

      (machine_args + storage_args + cloudinit_args + network_args + serial_args + guestagent_args + extra_args + other_args).map(&:to_s)
    end
  end
end
