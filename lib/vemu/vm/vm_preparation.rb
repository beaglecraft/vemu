module Vemu
  module VmPreparation
    def cloud_init_img_create!
      if @guestagent_enabled
        guest_support_path = File.join(Vemu.root, 'guest-support')
        cloud_init.include_file(guest_support_path)

        # In offline mode, we tell OS not to expect any network config. Without this,
        # the machine could hang during boot in something like:
        #   [  OK  ] Reached target network-pre.target - Preparation for Network.
        #            Starting systemd-networkd.service - Network Configuration...
        #   [  OK  ] Started systemd-networkd.service - Network Configuration.
        #   [  OK  ] Reached target network.target - Network.
        #            Starting systemd-networkd-wait-onl…ait for Network to be Configured...
        if @offline_mode
          @cloud_init_network_config_hooks << proc do |conf|
            conf[:ethernets] = {}
          end
          # @cloud_init_user_data_hooks << proc do |ci_data|
          #   # intentionally overwrite the 'network' key.
          #   ci_data[:network] = { config: 'disabled' }
          #
          #   if %w[ubuntu debian].include?(@distro)
          #     ci_data[:runcmd].unshift('systemctl mask systemd-networkd-wait-online.service')
          #     ci_data[:write_files] << {
          #       path: '/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg',
          #       permissions: '0644',
          #       content: Psych.dump({ network: { config: 'disabled' } }, stringify_names: true)
          #     }
          #   end
          # end
        end

        @cloud_init_user_data_hooks << proc do |ci_data|
          ci_data[:write_files] ||= []
          ci_data[:write_files] << {
            owner: 'root:root',
            path: '/etc/systemd/system/vemu-guest-agent.service',
            permissions: '0644',
            content: <<~SYSTEMD_UNIT
              [Unit]
              Description=VEMU Guest Agent
              After=network.target

              [Service]
              Type=simple
              WorkingDirectory=/opt/vemu-init
              ExecStart=/opt/vemu-init/localruby/bin/ruby /opt/vemu-init/ga_init.rb
              Restart=always
              RestartSec=5
              User=root
              Group=root

              [Install]
              WantedBy=multi-user.target
            SYSTEMD_UNIT
          }

          ci_data[:write_files] << {
            owner: 'root:root',
            path: '/var/lib/cloud/scripts/per-boot/00-vemu.boot.sh',
            permissions: '0755',
            content: <<~BASH,
              #!/bin/sh
              set -eux
              VEMU_CIDATA_MNT="/mnt/lima-cidata"
              VEMU_CIDATA_DEV="/dev/disk/by-label/cidata"
              mkdir -p -m 700 "${VEMU_CIDATA_MNT}"
              mount -o ro,mode=0700,dmode=0700,overriderockperm,exec,uid=0 "${VEMU_CIDATA_DEV}" "${VEMU_CIDATA_MNT}"
              export VEMU_CIDATA_MNT
              cd $VEMU_CIDATA_MNT
              # exec ga_init.sh
              exec "${VEMU_CIDATA_MNT}"/ga_init.sh
            BASH
          }

        end
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
      @cloud_init_user_data_hooks = []
      @cloud_init_network_config_hooks = []

      FileUtils.mkdir_p(@vm_path)

      # XXX: always recreate the cloud init image. It has caused a few headaches already.
      # cloud_init_img_create! unless cloud_init_img_present?
      cloud_init_img_create!

      diffdisk_create! unless diffdisk_present?
    end
  end
end
