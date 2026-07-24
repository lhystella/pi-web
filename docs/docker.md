# Running pi-web in Docker

pi-web can run as a container that shares your local pi installation. The web UI
runs the pi agent **in-process**, so the container needs access to:

1. Your pi data directory (`~/.pi`) — session history, auth (API keys / OAuth),
   `models.json`, skills.
2. Any project working directories you want the agent to read and edit.

## Quick start (docker compose)

```bash
docker compose up --build
```

Then open <http://localhost:30141>.

`docker-compose.yml` mounts everything at **identical absolute paths** and sets
the container `HOME` to match the host, which is what makes editing files from
existing sessions work (see below).

## The key rule: mount at identical paths

Session `.jsonl` files store the **absolute cwd** of each session. For the agent
to open and **edit** files from an existing session inside the container, two
things must line up:

1. The project is mounted at the **same absolute path** it has on the host.
2. The container's `HOME` equals the host's `HOME`, so `~/.pi`,
   `os.homedir()`, and the file-access allow-list resolve identically.

The provided `docker-compose.yml` already does this:

```yaml
environment:
  HOME: ${HOME}
volumes:
  - ${HOME}/.pi:${HOME}/.pi                                   # pi data, same path
  - /Volumes/Life/others/pi-web:/Volumes/Life/others/pi-web   # project, same path
```

### Adding your projects

Find the cwds your sessions use:

```bash
for d in "$HOME/.pi/agent/sessions"/*/; do
  f=$(ls "$d"*.jsonl 2>/dev/null | head -1)
  [ -n "$f" ] && head -1 "$f" | grep -o '"cwd":"[^"]*"'
done
```

Then add one `volumes` line per project, mapping the host path to the **same**
container path:

```yaml
volumes:
  - /Volumes/Life/others/pi-web:/Volumes/Life/others/pi-web
  - /Users/me/code/app:/Users/me/code/app
```

Edits the agent makes (via its bash/edit tools running in-process) write straight
through the bind mount to the real files on your host.

## Quick start (plain docker)

```bash
docker build -t pi-web:latest .

docker run -d --name pi-web \
  -p 30141:30141 \
  -e HOME="$HOME" \
  -e PI_WEB_NO_OPEN=1 \
  -v "$HOME/.pi:$HOME/.pi" \
  -v "/Volumes/Life/others/pi-web:/Volumes/Life/others/pi-web" \
  pi-web:latest
```

## Environment variables

| Variable                | Purpose                                                    |
| ----------------------- | ---------------------------------------------------------- |
| `HOME`                  | Set to the host `HOME` so `~/.pi` and cwds resolve the same |
| `PI_CODING_AGENT_DIR`   | Override the pi agent dir (defaults to `$HOME/.pi/agent`)   |
| `PORT`                  | Listen port (default `30141`)                              |
| `PI_WEB_NO_OPEN`        | Set to `1` — never try to open a browser in-container       |

The container always binds to `0.0.0.0` so the UI is reachable on the mapped port.

## Notes

- The runtime image includes `git`, `ripgrep`, `curl`, and `openssh-client` so the
  agent's tools work. Add more packages to the `runner` stage in the `Dockerfile`
  if your workflow needs them.
- Auth (API keys / OAuth tokens) lives in `~/.pi`. Because that directory is
  mounted, logins you do on the host are already available in the container and
  vice versa.
- The image runs as root so mounted host files stay writable. If you prefer a
  non-root user, add one in the `Dockerfile` and make sure file ownership on the
  mounts lines up.
```
