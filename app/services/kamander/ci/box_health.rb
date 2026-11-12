module Kamander
  module Ci
    # How the CI box is doing, from one SSH call as the ci user. ci has no
    # docker group, so Postgres and Ollama are checked by their ports.
    class BoxHealth
      SERVICES = %w[postgres ollama tailscale].freeze

      SCRIPT = <<~'SH'
        echo "cpus=$(nproc 2>/dev/null)"
        [ -r /proc/loadavg ] && echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
        [ -r /proc/uptime ] && echo "uptime=$(cut -d' ' -f1 /proc/uptime)"
        [ -r /proc/meminfo ] && awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/ { sub(":", "", $1); print $1 "=" $2 }' /proc/meminfo
        df -Pk / /data 2>/dev/null | awk 'NR > 1 { print "disk " $6 "=" $4 " " $2 }'
        t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n 1) && [ -n "$t" ] && echo "gpu_temp=$t"
        port() { if timeout 2 bash -c "</dev/tcp/127.0.0.1/$1" 2>/dev/null; then echo up; else echo down; fi; }
        echo "postgres=$(port 5432)"
        echo "ollama=$(port 11434)"
        if command -v tailscale >/dev/null; then tailscale status >/dev/null 2>&1 && echo tailscale=up || echo tailscale=down; fi
        for b in /sys/class/power_supply/BAT*; do
          [ -r "$b/capacity" ] || continue
          echo "battery=$(cat "$b/capacity") $(cat "$b/status" 2>/dev/null)"
          [ -r "$b/charge_control_end_threshold" ] && echo "battery_limit=$(cat "$b/charge_control_end_threshold")"
          break
        done
        true
      SH

      Report = Data.define(:values, :disks, :error) do
        def success? = error.nil?

        def cpus = values["cpus"]&.to_i
        def load = values["load"]&.split&.map(&:to_f)
        def uptime = values["uptime"]&.to_f
        def gpu_temp = values["gpu_temp"]&.to_i
        def battery = values["battery"]&.split&.first&.to_i
        def battery_status = values["battery"]&.split(" ", 2)&.last
        def battery_limit = values["battery_limit"]&.to_i

        def memory_used_ratio = used_ratio(values["MemTotal"], values["MemAvailable"])
        def swap_used_ratio = used_ratio(values["SwapTotal"], values["SwapFree"])

        def services = SERVICES.index_with { |name| values.fetch(name, "unknown") }

        private

          def used_ratio(total, free)
            return unless total && free && total.to_i.positive?

            (total.to_i - free.to_i).fdiv(total.to_i)
          end
      end

      def initialize(host:, user:, ssh_client: Kamander::Kamal.ssh_client)
        @host = host
        @user = user
        @ssh_client = ssh_client
      end

      def call
        result = @ssh_client.capture(host: @host, user: @user, command: SCRIPT)
        return Report.new(values: {}, disks: {}, error: result.error) unless result.success?

        parse(result.stdout)
      end

      private

        def parse(stdout)
          values = {}
          disks = {}
          stdout.each_line(chomp: true) do |line|
            key, value = line.split("=", 2)
            next if value.blank?

            if key.start_with?("disk ")
              disks[key.delete_prefix("disk ")] = value.split.map(&:to_i)
            else
              values[key] = value.strip
            end
          end
          Report.new(values: values, disks: disks, error: nil)
        end
    end
  end
end
