module Vemu
  module VmStart

    def vm_start_exec
      cmd_args = qemu_cmd_arguments

      exec({}, qemu_system_bin, *cmd_args, {
        chdir: @vm_path,
      })
    end

    def vm_start_attached
      fork do
        STDOUT.close
        STDERR.close
        STDIN.close

        vm_start_exec

        exit!(1)
      end
    end

    def vm_start_detached
      reader, writer = IO.pipe
      writer.close_on_exec = true

      intermediate_pid = fork do
        reader.close
        Process.setsid

        detached_pid = fork do
          begin
            redirect_standard_streams

            vm_start_exec
          ensure
            writer.close
          end
        end

        writer.write(detached_pid.to_s)
        writer.close

        exit!(0)
      end

      writer.close
      _pid, status = Process.waitpid2(intermediate_pid)

      pid = Integer(reader.read, 10)
      raise StartError, "could not detach QEMU process" unless status.success?
      pid
    rescue ArgumentError, SystemCallError => e
      raise StartError, "could not launch QEMU: #{e.message}", cause: e
    ensure
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
    end

    private

    def redirect_standard_streams
      null = File.open(File::NULL, "r+")
      STDIN.reopen(null)
      STDOUT.reopen(null)
      STDERR.reopen(null)
      null.close
    end
  end
end


# def launch_detached(vm)
#   reader, writer = IO.pipe
#   writer.close_on_exec = true
#
#   intermediate_pid = fork do
#     reader.close
#     Process.setsid
#     detached_pid = fork do
#       begin
#         redirect_standard_streams
#         vm.vm_start_exec
#       ensure
#         writer.close
#       end
#     end
#     writer.write(detached_pid.to_s)
#     writer.close
#     exit!(0)
#   end
#
#   writer.close
#   _pid, status = Process.waitpid2(intermediate_pid)
#   pid = Integer(reader.read, 10)
#   raise StartError, "could not detach QEMU process" unless status.success?
#   pid
# rescue ArgumentError, SystemCallError => e
#   raise StartError, "could not launch QEMU: #{e.message}", cause: e
# ensure
#   reader&.close unless reader&.closed?
#   writer&.close unless writer&.closed?
# end
