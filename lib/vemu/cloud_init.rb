
module Vemu
  #
  # https://cloudinit.readthedocs.io/en/latest/reference/examples.html
  #
  class CloudInit
    attr_accessor :users
    attr_accessor :host_name
    attr_accessor :instance_id
    attr_accessor :apt_mirror

    attr_accessor :user_data_hooks
    attr_accessor :meta_data_hooks
    attr_accessor :network_config_hooks
    attr_accessor :use_network_config

    def initialize(host_name:, instance_id: nil, context: Context.default)
      @timezone = 'Etc/UTC'
      @next_user_uid = 1001
      @users = []
      @instance_id = instance_id || host_name
      @host_name = host_name
      @included_files = []
      @apt_mirror = nil
      @use_network_config = false
      @context = context

      @user_data_hooks = []
      @meta_data_hooks = []
      @network_config_hooks = []
    end

    def set_apt_mirror(primary:, security: nil)
      @apt_mirror = { primary:, security: }
    end

    def add_user(user_name, sudoer: false, ssh_keys: nil, uid: nil)
      unless uid
        uid = @next_user_uid
        @next_user_uid += 1
      end

      {
        name: user_name.to_s,
        uid: uid,
        homedir: "/home/#{user_name}",
        shell: '/bin/bash',
        lock_passwd: true,
      }.tap do |user|
        user[:sudo] = 'ALL=(ALL) NOPASSWD:ALL' if sudoer
        user[:ssh_authorized_keys] = Array(ssh_keys) if ssh_keys
        @users << user
      end
    end

    attr_accessor :included_files

    def include_file(path)
      @included_files << path
    end

    def create_isodisk(output_path:)
      # TODO: add dependency check => genisoimage --version
      #                            genisoimage 1.1.11 (Linux)
      temp_folder = File.join('/tmp/vemu-temp/', SecureRandom.alphanumeric(22))
      ci_path = File.join(temp_folder, 'cidata')
      FileUtils.mkdir_p(ci_path)

      File.write(File.join(ci_path, 'user-data'), user_data)
      File.write(File.join(ci_path, 'meta-data'), meta_data)
      File.write(File.join(ci_path, 'network-config'), network_config) if @use_network_config

      all_files = [
        "#{ci_path}/user-data",
        "#{ci_path}/meta-data",
        @use_network_config ? "#{ci_path}/network-config" : nil,
      ].compact + @included_files

      command = "genisoimage -r -J -V cidata -input-charset utf-8 -o #{output_path} #{all_files.join(' ')}"
      `#{command}`

      FileUtils.rm_rf(temp_folder)

      true
    end

    def meta_data
      data = {
        'instance-id' => @instance_id,
        'local-hostname' => @host_name,
      }

      @meta_data_hooks.each do |blk|
        blk.call(data)
      end

      yaml_data = Psych.dump(data, stringify_names: true)
      "#{yaml_data.split("\n")[1..].join("\n")}\n"
    end

    def network_config
      data = {
        version: 2
      }

      @network_config_hooks.each do |blk|
        blk.call(data)
      end

      yaml_data = Psych.dump(data, stringify_names: true)
      "#{yaml_data.split("\n")[1..].join("\n")}\n"
    end

    def user_data
      ci_data = {
        growpart: {
          mode: 'auto',
          devices: ['/'],
        },

        swap: {
          filename: '/swapfile',
          size: '4G',
          maxsize: '4G',
        },

        #runcmd: [
          # fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
          # "echo '/swapfile none swap sw 0 0' >> /etc/fstab",
        #],
        timezone: @timezone,

        users:,

        write_files: [],
        runcmd: [],

        final_message: <<~INFO,
          cloud-init has finished
          version: $version
          timestamp: $timestamp
          datasource: $datasource
          uptime: $uptime
        INFO
      }

      if @apt_mirror
        ci_data[:apt] = {
          primary: [
            {
              arches: ['default'],
              uri: @apt_mirror[:primary]
            }
          ],
          security: [
            {
              arches: ['default'],
              uri: @apt_mirror[:security]
            }
          ],
        }
      end

      @user_data_hooks.each do |blk|
        blk.call(ci_data)
      end

      yaml_data = Psych.dump(ci_data, stringify_names: true)

      "\#cloud-config\n#{yaml_data.split("\n")[1..].join("\n")}\n"
    end

    def prepend_user_data_hook(&blk) = @user_data_hooks.unshift(blk)
    def append_user_data_hook(&blk) = @user_data_hooks << blk

    def prepend_meta_data_hook(&blk) = @meta_data_hooks.unshift(blk)
    def append_meta_data_hook(&blk) = @meta_data_hooks << blk

    def prepend_network_config_hook(&blk) = @network_config_hooks.unshift(blk)
    def append_network_config_hook(&blk) = @network_config_hooks << blk
  end
end
