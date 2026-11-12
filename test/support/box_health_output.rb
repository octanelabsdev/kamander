# What the CI box prints for Kamander::Ci::BoxHealth::SCRIPT, every value present.
BOX_HEALTH_OUTPUT = <<~OUT.freeze
  cpus=32
  load=3.21 2.50 1.75
  uptime=93784.5
  MemTotal=65536000
  MemAvailable=40960000
  SwapTotal=16384000
  SwapFree=12288000
  disk /=214748364 524288000
  disk /data=104857600 1048576000
  gpu_temp=54
  postgres=up
  ollama=down
  tailscale=up
  battery=80 Not charging
  battery_limit=80
OUT
