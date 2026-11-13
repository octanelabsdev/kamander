# Running Kamander on a shared box

How Kamander runs on a shared CI box: as its own Unix user, under
systemd, reached through Cloudflare Access and Tailscale.

## Why it looks like this

- **Its own user, no `docker`, `sudo` or `lxd`.** The fleet SSH key lives in
  this user's home, which `ci` (every branch's CI) can't read, and the user
  has no path to root.
- **No open port for other local users.** Unix permissions don't cover a
  loopback port, and Kamander has no login. Puma listens on a Unix socket in a
  0700 directory, which cloudflared uses, and on `127.0.0.1:3100` for
  `tailscale serve`, which only proxies to TCP. A firewall rule lets only root
  (tailscaled) and `kamander` connect to 3100.
- **No app secrets on the box.** `kamal app boot` uploads each app's production
  secrets from the machine running it, so reboot/start/stop stay on a machine
  that holds them. Turn off "Reboot, start and stop from here" in Settings.
  Restart is docker over SSH and still works.
- **Fail-closed Access check.** Kamander has no login. Any request that came
  through Cloudflare needs a valid Access JWT (`lib/middleware/cloudflare_access_gate.rb`).

## Environment (`~/.config/kamander.env`, mode 600)

```sh
KAMANDER_HOSTS=<public hostname>,<tailnet hostname>
CF_ACCESS_HOSTS=<public hostname>
CF_ACCESS_TEAM_DOMAIN=https://<team>.cloudflareaccess.com
CF_ACCESS_AUD=<Access application AUD tag>
```

`config/master.key` is copied in by hand; it is Kamander's only secret besides the fleet key.

Production sets `assume_ssl` because both proxies terminate TLS. A form posted
to plain `http://127.0.0.1:3100` directly, without a proxy, fails the CSRF
origin check; use the tailnet URL.

## First install (as the admin user, then as `kamander`)

```sh
# admin user
sudo useradd -m -s /bin/bash kamander
sudo loginctl enable-linger kamander
id kamander                                  # expect only the kamander group

# as kamander (sudo -iu kamander)
curl https://mise.run | sh && echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C kamander-fleet -N ""
git clone https://github.com/octanelabsdev/kamander.git ~/kamander
cd ~/kamander && mise install && bundle install
mkdir -p ~/repos   # clone each managed app here (read-only GitHub access)
install -m 600 /dev/null ~/.config/kamander.env   # then fill in the variables above
mkdir -p ~/.config/systemd/user && cp config/box/kamander.service ~/.config/systemd/user/
RAILS_ENV=production bin/rails db:prepare assets:precompile
systemctl --user daemon-reload && systemctl --user enable --now kamander
curl -fsS http://127.0.0.1:3100/up
```

Firewall (admin user), so `ci` and other local users can't reach the TCP port:

```sh
sudo nft add table inet kamander
sudo nft add chain inet kamander out '{ type filter hook output priority 0; }'
sudo nft add rule inet kamander out oifname lo tcp dport 3100 meta skuid != '{ 0, kamander }' reject
# persist it: add the table to /etc/nftables.conf and enable nftables.service
```

Cloudflare Tunnel ingress (cloudflared runs as root, so it can open the socket):

```yaml
ingress:
  - hostname: <public hostname>
    service: unix:/home/kamander/kamander/tmp/sockets/puma.sock
  - service: http_status:404
```

Tailscale: `sudo tailscale serve --bg 3100`.

Then in Kamander's Settings: scan root `~/repos`, pull before scan on,
kamal verbs off, CI host `localhost`, CI user `ci`.

- Fleet access: add `~/.ssh/id_ed25519.pub` to `authorized_keys` of the deploy user on each server.
- CI access: add the same key to `~ci/.ssh/authorized_keys` (reads and cancels run as `ci`).

## Updates

```sh
sudo -iu kamander ~/kamander/bin/box-update
```

## Checks

```sh
sudo -u ci cat ~kamander/.ssh/id_ed25519      # Permission denied
sudo -u ci curl -m 3 http://127.0.0.1:3100/up # refused by the firewall rule
sudo -u ci curl -m 3 --unix-socket ~kamander/kamander/tmp/sockets/puma.sock http://x/up  # Permission denied
curl -sI https://<public hostname> | head -1   # Access login, not Kamander
```
