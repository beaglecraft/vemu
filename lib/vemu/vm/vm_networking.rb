module Vemu
  module VmNetworking
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

    def offline_mode!
      @offline_mode = true
    end
  end
end
