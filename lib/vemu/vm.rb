module Vemu
  class VM
    attr_reader :name, :vm_path
    attr_accessor :cpus, :threads_per_core
    attr_accessor :memory
    attr_accessor :arch
    attr_accessor :disk
    attr_accessor :cloud_init
    attr_accessor :distro
    attr_accessor :vsock_cid

    attr_accessor :host_info
    attr_accessor :network_cards
    attr_accessor :guestagent_enabled

    def initialize(name, context: Context.default, cloud_init: nil, distro: 'ubuntu')
      @name = name
      @arch = 'amd64'
      @memory = '3072'
      @cpus = 2
      @threads_per_core = 1
      @disk = '21474836480'
      @guestagent_enabled = true
      @distro = distro
      @vsock_cid = nil
      @host_info = HostInfo.new

      @context = context
      host_name = "vemu-#{name}"
      @cloud_init = cloud_init || CloudInit.new(context:, host_name:)

      # The path where we store all temporary files and stuff for this particular VM
      @vm_path = context.path_for_vm(name)
      FileUtils.mkdir_p(vm_path)

      @network_cards = []
    end

    def cloud_init_img_create!
      if @guestagent_enabled
        guest_support_path = File.expand_path(File.join(__dir__, '../../guest-support'))
        cloud_init.include_file(guest_support_path)
      end

      cloud_init.create_isodisk(output_path: File.join(@vm_path, 'cidata.iso'))
      File.write(File.join(@vm_path, 'cloud-init.yaml'), cloud_init.user_data)
    end

    # Resetting will delete disk files and regenerate everything.
    # Can be called before vm_start* so that the machine will be brand-new.
    def reset_machine!
      unlink_paths = []

      unlink_paths << cloud_init_img_path if cloud_init_img_present?
      unlink_paths << diffdisk_path if diffdisk_present?

      FileUtils.rm_f(unlink_paths) unless unlink_paths.empty?
    end

    def diffdisk_create!
      base_image_path = @context.base_image_path(name: @distro, arch:)
      FileUtils.rm(diffdisk_path) if diffdisk_present?

      `qemu-img create -f qcow2 -F qcow2 -b '#{base_image_path}' '#{diffdisk_path}' #{@disk}`

      unless File.file?(diffdisk_path)
        raise "Error: expected diffdisk of size '#{@disk}' to exist at #{diffdisk_path}"
      end
    end

    def prepare_vm_files
      FileUtils.mkdir_p(@vm_path)

      # XXX: always recreate the cloud init image. It has caused a few headaches already.
      # cloud_init_img_create! unless cloud_init_img_present?
      cloud_init_img_create!

      diffdisk_create! unless diffdisk_present?
    end

    def qemu_system_bin = @host_info.qemu_system_bin(@arch)

    def vm_start_exec
      cmd_args = qemu_cmd_arguments

      exec({}, qemu_system_bin, *cmd_args, {
        chdir: @vm_path,
      })
    end

    def vm_start
      prepare_vm_files

      full_command = "#{qemu_system_bin} \\\n"

      qemu_cmd_arguments.each_slice(2) do |lines|
        full_command += "\t#{lines.join(' ')} \\\n"
      end
      full_command += ";"

      File.write("/tmp/run_image.sh", <<~BASH)
        #!/usr/bin/env bash
        set -eux

        #{full_command}

      BASH
    end

    def qemu_cmd_arguments
      ## Machine

      machine_args = [
        "-m", @memory,
        "-smp", "#{@cpus},sockets=1,cores=#{@cpus},threads=#{@threads_per_core}",
      ]

      if @arch == 'amd64'
        machine_args += [
          "-machine", "q35,accel=kvm,pflash0=uefi_code",
          "-cpu", "host",

          "-blockdev", "driver=file,filename=#{@host_info.ovmf_code_path},node-name=uefi_code,read-only=on",

          # "-drive", "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd",
          # "-boot", "order=c,splash-time=0,menu=on",
          "-boot", "menu=on",
        ]
      elsif @arch == 'arm64'
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
          "-chardev", "socket,path=#{ga_socket_path},server=on,wait=off,id=qga0",
          "-device", "virtio-serial",
          "-device", "virtserialport,chardev=qga0,name=io.vemu.guest_agent.0",
        ]
      end

      extra_args = []

      if @vsock_cid
        extra_args += [
          "-device", "vhost-vsock-pci,id=vhost-vsock-pci0,guest-cid=#{@vsock_cid}",
        ]
      end

      other_args = [
        "-device", "virtio-rng-pci",
        "-display", "none",
        # "-device", "virtio-gpu-pci", # "-device", "virtio-vga",
        # "-device", "virtio-keyboard-pci",
        # "-device", "virtio-mouse-pci",
        "-device", "qemu-xhci,id=usb-bus",
        "-parallel", "none",

        # serial.log
        "-chardev", "socket,id=char-serial,path=#{serial_socket_path},server=on,wait=off,logfile=#{serial_log_path}",
        "-serial", "chardev:char-serial",

        # serialv.log
        "-chardev", "socket,id=char-serial-virtio,path=#{serial_v_socket_path},server=on,wait=off,logfile=#{serial_v_log_path}",
        # "-device", "virtio-serial-pci,id=virtio-serial0,max_ports=1",
        "-device", "virtio-serial-pci,id=virtio-serial0",
        "-device", "virtconsole,chardev=char-serial-virtio,id=console0",

        # QMP
        "-chardev", "socket,id=char-qmp,path=#{qmp_socket_path},server=on,wait=off",
        "-qmp", "chardev:char-qmp",

        "-name", @name,
        "-pidfile", qemu_pid_path
      ]

      (machine_args + storage_args + cloudinit_args + network_args + guestagent_args + extra_args + other_args).map(&:to_s)
    end

    def add_tap_netdev(net_device, mac:, host_tap:)
      @network_cards << {
        mode: 'tap',
        mac_address: mac,
        net_device:,
        tap_device: host_tap
        # -device virtio-net-pci,netdev=eth0,mac= \
        # -netdev tap,id=eth0,ifname=tap0,script=no,downscript=no \
      }
    end

    def add_user_netdev(net_device, mac:)
      @network_cards << {
        mode: 'user',
        net_device:,
        mac_address: mac
      }
    end

    # def generate_ssh_config
    #   # FIXME: not working at all
    #   conf = <<~SSHCONF
    #     IdentityFile "#{File.join @context.vemu_folder, 'user_identity'}"
    #     StrictHostKeyChecking no
    #     UserKnownHostsFile /dev/null
    #     NoHostAuthenticationForLocalhost yes
    #     PreferredAuthentications publickey
    #     Compression no
    #     BatchMode yes
    #     IdentitiesOnly yes
    #     GSSAPIAuthentication no
    #     Ciphers "^aes128-gcm@openssh.com,aes256-gcm@openssh.com"
    #     User lime
    #     Hostname 192.168.1.221
    #   SSHCONF
    #
    #   lines = [
    #     '# Use in ssh -F',
    #     "Host #{@name}",
    #   ]
    #   lines += conf.split("\n").map{ |line| "\t#{line}" }
    #
    #   lines.join("\n")
    # end

    def cloud_init_img_present? = File.file?(cloud_init_img_path)
    def diffdisk_present? = File.file?(diffdisk_path)

    def cloud_init_img_path = File.join(@vm_path, 'cidata.iso')
    def diffdisk_path = File.join(@vm_path, 'diffdisk')
    def serial_socket_path = File.join(@vm_path, 'serial.sock')
    def serial_v_socket_path = File.join(@vm_path, 'serialv.sock')
    def serial_log_path = File.join(@vm_path, 'serial.log')
    def serial_v_log_path = File.join(@vm_path, 'serialv.log')
    def qmp_socket_path = File.join(@vm_path, 'qmp.sock')
    def qemu_pid_path = File.join(@vm_path, 'qemu.pid')

    def ga_socket_path
      return unless @guestagent_enabled

      File.join(@vm_path, "ga.sock")
    end
  end
end
