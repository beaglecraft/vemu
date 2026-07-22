module Vemu
  class HostInfo
    CONFIGMAP = {
      debian:  {
        ovmf_code_path: '/usr/share/OVMF/OVMF_CODE_4M.fd'
      },
      rhel: {
        ovmf_code_path: '/usr/share/edk2/ovmf/OVMF_CODE.fd'
      }
    }.tap do |x|
      x[:ubuntu] = x[:debian]
    end.freeze

    def ovmf_code_path
      CONFIGMAP.fetch(os)[:ovmf_code_path]
    end

    def qemu_system_bin(arch = nil)
      return '/usr/libexec/qemu-kvm' if os == :rhel

      mapping = {
        'amd64' => '/usr/bin/qemu-system-x86_64',
        'arm64' => '/usr/bin/qemu-system-aarch64',
      } # TODO: we can likely just use qemu-kvm

      bin = mapping[arch]

      return bin if bin

      supported = mapping.keys.join(', ')

      raise "Arch '#{arch}' is not supported. Must be one of: #{supported}"
    end

    def os
      os_msg = "Not found: /etc/os-release - cannot detect host OS."

      raise os_msg unless File.exist?('/etc/os-release')

      os_info = File.read('/etc/os-release').scan(/^([^=]+)=(.*)$/).to_h
      id = os_info['ID']&.tr('"', '')&.strip&.downcase

      case id
      when 'debian'
        :debian
      when 'ubuntu'
        :ubuntu
      when 'rhel', 'centos', 'rocky', 'almalinux'
        :rhel
      when 'arch'
        :arch
      else
        raise os_msg
      end
    end
  end
end
