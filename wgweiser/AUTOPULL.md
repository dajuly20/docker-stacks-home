# Autopull — keeping this Homer deployment in sync with git

This stack's `config.yml` is maintained in git. Instead of manually pulling
after every edit, set up `autopull.sh` as a recurring systemd user timer on
whichever host runs the `homer` container (`docker-compose.yaml` in this
folder).

## How it works

- `autopull.sh` — runs `git pull --ff-only` in this repo checkout.
- `autopull.service` — a oneshot systemd unit that runs the script once.
- `autopull.timer` — triggers the service 1 minute after boot, then every
  5 minutes.

Homer itself picks up the change automatically: `docker-compose.yaml` sets
`WATCH=true`, so the container reloads the dashboard as soon as
`assets/config.yml` changes on disk — no restart needed.

> **Monorepo note:** this folder (`wgweiser/`) lives inside the
> `home-docker-stacks` repo, which has multiple branches (`main`,
> `feature/homer-restructure`, `hosts/julianwde`, ...). `autopull.sh` pulls
> `main` by default. If the checkout on your deploy host tracks a different
> branch, set `AUTOPULL_BRANCH` in the systemd service (`Environment=`) or
> export it before running the script manually.

## Setup (systemd user timer)

Run these on the host that has this repo checked out and runs
`docker compose up -d` for the `homer` service.

```bash
REPO_DIR="$(pwd)"   # run this from inside wgweiser/

mkdir -p ~/.config/systemd/user
sed "s#__REPO_DIR__#${REPO_DIR}#g" autopull.service > ~/.config/systemd/user/autopull.service
cp autopull.timer ~/.config/systemd/user/autopull.timer

systemctl --user daemon-reload
systemctl --user enable --now autopull.timer
```

If this checkout doesn't track `main`, add a branch override before
`daemon-reload`:

```bash
sed -i '/^\[Service\]/a Environment=AUTOPULL_BRANCH=feature/homer-restructure' ~/.config/systemd/user/autopull.service
```

### Survive reboot without an active login session

User systemd units normally only run while you're logged in. To let the
timer run in the background even after a reboot with nobody logged in,
enable linger for your user (one-time, needs root):

```bash
sudo loginctl enable-linger "$USER"
```

## Verify

```bash
systemctl --user list-timers autopull.timer --no-pager
systemctl --user start autopull.service   # trigger a run immediately
journalctl --user -u autopull.service -n 20 --no-pager
```

A successful run logs `pulled ok` (or "already up to date" if there was
nothing new).

## Uninstall

```bash
systemctl --user disable --now autopull.timer
rm ~/.config/systemd/user/autopull.service ~/.config/systemd/user/autopull.timer
systemctl --user daemon-reload
```
