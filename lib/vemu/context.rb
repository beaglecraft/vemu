module Vemu
  class Context
    BASE_IMAGES = {
      ubuntu: [
        {
          url: 'https://cloud-images.ubuntu.com/releases/noble/release-20260518/ubuntu-24.04-server-cloudimg-amd64.img',
          arch: 'amd64',
          digest: 'sha256:53fdde898feed8b027d94baa9cfe8229867f330a1d9c49dc7d84465ee7f229f7',
        },
        {
          url: 'https://cloud-images.ubuntu.com/releases/noble/release-20260518/ubuntu-24.04-server-cloudimg-arm64.img',
          arch: 'arm64',
          digest: 'sha256:6a61b967ba4a27dd1966f835a67643073ed55c2860ce3dc1cb0517282e6b8bec',
        }
      ],
      debian: [
        {
          url: 'https://cloudfront.debian.net/cdimage/cloud/trixie/20260615-2510/debian-13-generic-amd64-20260615-2510.qcow2',
          arch: 'amd64',
          digest: 'sha256:5b24e472a1a7cf7c963bb62d8ad68243200bf5fe083409a5946a228d68481c12',
        }
      ],
      alpine: [
        {
          url: 'https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/generic_alpine-3.23.4-x86_64-uefi-cloudinit-r0.qcow2',
          arch: 'amd64',
          digest: 'sha256:b90cee9ac846decb54667b55dfad3dd1f6df5edd3c653f107327dfba274d3e24',
        }
      ],
    }

    def self.default
      @default_context ||= new
    end

    attr_accessor :vemu_folder

    def initialize
      @vemu_folder = File.expand_path(File.join(ENV['HOME'], '.vemu'))
    end

    def path_for_vm(vm_name)
      File.join(@vemu_folder, 'vms', vm_name)
    end

    def base_image_path(name:, arch: 'amd64')
      img = find_image(name, arch)
      # File.join(@vemu_folder, 'base-images', "#{name}-#{arch}.img")
      file_name = File.basename(img.fetch(:url))
      File.join(@vemu_folder, 'base-images', file_name)
    end

    def find_image(name, arch)
      BASE_IMAGES[name.to_sym].find { |img| img[:arch] == arch  }
    end
  end
end
