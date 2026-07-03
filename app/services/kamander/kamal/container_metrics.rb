module Kamander
  module Kamal
    ContainerMetrics = Data.define(:name, :host, :cpu_percent, :mem_usage, :mem_limit, :mem_percent, :net_io, :block_io, :pids)
  end
end
