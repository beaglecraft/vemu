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
    attr_accessor :offline_mode
    attr_accessor :vsock_mode

    attr_accessor :host_info
    attr_accessor :network_cards
    attr_accessor :guestagent_enabled

    include VmStart
    include VmNetworking
    include VmPreparation
    include VmCommand

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
      @vsock_mode = :host
      @offline_mode = false
      @host_info = HostInfo.new

      @context = context
      host_name = "vemu-#{name}"
      @cloud_init = cloud_init || CloudInit.new(context:, host_name:)
      @cloud_init_user_data_hooks = nil
      @cloud_init.prepend_user_data_hook do |ci_data|
        @cloud_init_user_data_hooks.each { |fun| fun.call(ci_data) }
      end

      @cloud_init_network_config_hooks = nil
      @cloud_init.prepend_network_config_hook do |data|
        @cloud_init_network_config_hooks.each { |fun| fun.call(data) }
      end

      # The path where we store all temporary files and stuff for this particular VM
      @vm_path = context.path_for_vm(name)
      FileUtils.mkdir_p(vm_path)

      @network_cards = []
    end

    def qemu_system_bin = @host_info.qemu_system_bin(@arch)

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
