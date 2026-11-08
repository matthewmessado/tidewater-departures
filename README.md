# Tidewater Tours Departures API

A small API for **Tidewater Tours** (a made-up client) that serves the upcoming departures
for each tour, with how many seats are left. Every push to `main` is tested, built into a
Docker image tagged with the commit, pushed to GitHub Container Registry and deployed to
a Linux VM on Azure, where a health check confirms it is serving. Rolling back to the
previous image is one click.

> Apex Projects solo project "Ship one service", by Mathew.
> Runbook: [docs/RUNBOOK.md](docs/RUNBOOK.md). Nine-step notes: [docs/NINE-STEP-NOTES.md](docs/NINE-STEP-NOTES.md).
> Hand-in checklist: [docs/HAND-IN.md](docs/HAND-IN.md).

**Live health check:** `http://<vm-ip>:8081/health` (replace with the VM's public IP once it exists)

## What is in the box

```
src/            Express API (app.js = routes, departures.js = data, server.js = listen + graceful shutdown)
test/           Integration tests using Node's built-in test runner (no extra deps)
Dockerfile      Multi-stage build -> small, non-root, with a HEALTHCHECK
deploy/         Scripts that run on the VM: deploy.sh, rollback.sh, common.sh, vps-setup.sh,
                plus local-demo.sh to rehearse a rollback on your own machine
.github/
  workflows/ci-cd.yml      test -> build & push -> deploy (push to main)
  workflows/rollback.yml   manual "Run workflow" button -> previous image
docs/           Runbook, nine-step notes, hand-in checklist, screenshots
```

### Endpoints

| Route                 | Purpose                                                                                      |
|-----------------------|----------------------------------------------------------------------------------------------|
| `GET /health`         | `{status, version, uptimeSeconds, timestamp}`; `version` is the git SHA baked into the image |
| `GET /departures`     | List all departures with `seatsLeft` and `soldOut`. Optional filter: `?tour=sunset-harbour-cruise` |
| `GET /departures/:id` | One departure, for example `/departures/dep-102` (sold out), or a JSON 404                   |
| `GET /`               | Service name, version and the route list                                                     |

## Run it locally

```bash
npm ci
npm test            # boots the app on a random port and calls it over HTTP
npm start           # http://localhost:8080/health
```

With Docker:

```bash
docker build -t tidewater-departures --build-arg APP_VERSION=local .
docker run --rm -p 8080:8080 tidewater-departures
curl localhost:8080/health
```

Inside the container the app always listens on 8080. The `-p` flag decides which port on
the host reaches it. On the Azure VM that host port is 8081 (`-p 8081:8080`).

## How the pipeline works

```
 push to main
     |
     v
 +-----------+  needs  +------------------------+  needs  +----------------------------+
 |   test    | ------> |  build & push image    | ------> |  deploy to Azure VM (SSH)  |
 |  npm test |         |  ghcr.io/...:<sha>     |         |  pull -> run -> /health    |
 +-----------+         |  ghcr.io/...:latest    |         |  unhealthy? auto-rollback  |
     x red             +------------------------+         +----------------------------+
     |
     +--> build and deploy jobs are skipped. Nothing is pushed or deployed.
```

* **Tests gate everything.** `build-and-push` has `needs: test` and `deploy` has
  `needs: build-and-push`. A failing test leaves the registry and the VM untouched.
* **Tag = commit.** The image is tagged with the full `github.sha` (and `latest` for
  convenience). The same SHA is passed in as the `APP_VERSION` build arg, so
  `GET /health` on the VM tells you exactly which commit is live.
* **Deploy = pull and swap.** The runner copies `deploy/*.sh` to the VM and runs
  `deploy.sh <image>`. The script records the currently running image as `previous`,
  starts the new one, polls `/health` for up to 20 s, and if the new container never
  becomes healthy it puts the previous image straight back.
* **Secrets never touch the repo.** The three values the deploy needs live in GitHub
  Actions secrets. The registry login on the VM uses the job's short-lived
  `GITHUB_TOKEN`, piped over stdin and logged out again afterwards.
* **Clear failures.** Before deploying, the job checks the secrets, the key, that the VM
  answers, that the login works, that Docker is usable, that the VM is x86_64 and that
  the server folder exists. Each failure has its own plain-English error.

## Where it runs: an Azure Linux VM

The brief offers AWS free tier, a shared sandbox or LocalStack. This project uses the
same idea on Azure: a small Ubuntu VM from the Azure free account, which includes
750 hours a month of the B1s, B2ats v2 and B2pts v2 sizes for 12 months. It is a real
environment with a real network, Docker daemon, health check and rollback, and the
same scripts would run unchanged on AWS EC2.

| Setting                  | Value                       | Why                                                        |
|--------------------------|-----------------------------|------------------------------------------------------------|
| Image                    | Ubuntu Server 24.04 LTS, x64 | The pipeline builds x86_64 images                         |
| Size                     | `Standard_B2ats_v2` (or `Standard_B1s`) | Free-account x64 sizes. **Not** B2pts v2: that one is Arm and cannot run the image |
| Admin user               | `azureuser`, with the VM creator's SSH key | Sets the VM up once; never given to GitHub     |
| Mathew's account         | `mathew`: a normal account with a password (for sudo) and two SSH keys | Mathew logs in with his own key; GitHub logs in with the pipeline's key |
| Network security group   | Allow 22 and 8081 inbound from any source | 22 for GitHub's runners (they use many IPs), 8081 for the app |
| Container / folder / port | `tidewater-departures` / `/opt/tidewater-departures` / `8081` | Set once at the top of both workflow files |

The GitHub secrets are called `VPS_HOST`, `VPS_USER` and `VPS_SSH_KEY`. Here "VPS"
simply means the Linux server the pipeline SSHes into, which is the Azure VM.

## One-time setup

### 1. Create two SSH keys on your laptop

In PowerShell (on macOS or Linux, run the same commands with `~/.ssh/...` paths):

```powershell
mkdir $HOME\.ssh -Force | Out-Null

# Your personal login key for the VM
ssh-keygen -t ed25519 -C "mathew-azure" -f $HOME\.ssh\azure-mathew

# GitHub Actions' key. Press Enter twice at the passphrase prompt: it must have none,
# because GitHub's runner has nobody to type one.
ssh-keygen -t ed25519 -C "tidewater-departures-deploy" -f $HOME\.ssh\tidewater-departures-deploy

# The public halves (.pub) are safe to share with whoever sets up the VM
Get-Content $HOME\.ssh\azure-mathew.pub
Get-Content $HOME\.ssh\tidewater-departures-deploy.pub
```

Both keys log in as `mathew`, but they stay separate. To cut GitHub off, delete the
pipeline key's line from `authorized_keys`; your own login keeps working. The private
halves (the files without `.pub`) stay on your laptop, except the pipeline key, which
goes into GitHub's secrets in step 5.

### 2. Create the VM in the Azure portal

portal.azure.com -> **Create a resource** -> **Virtual machine**, then on **Basics**:

* **Resource group:** create new, `tidewater-rg`. **VM name:** `tidewater-vm`. **Region:** one near you.
* **Image:** Ubuntu Server 24.04 LTS - **x64** Gen2.
* **Size:** `Standard_B2ats_v2` (or `Standard_B1s` if offered). Avoid `B2pts v2` (Arm).
* **Authentication:** SSH public key. **Username:** `azureuser`.
  **SSH public key source:** use existing public key, and paste the public key of whoever
  administers the VM (that can be `azure-mathew.pub` if it is you).
* **Public inbound ports:** allow selected ports, **SSH (22)**.

**Review + create**, check the price shown, then **Create**. When it finishes, open the
resource and copy its **Public IP address**. That IP is `<vm-ip>` everywhere below.

Then open the app port: the VM's **Networking** page -> add an **inbound port rule** ->
destination port `8081`, protocol TCP, action Allow, name `allow-app-8081`.

Leave the SSH rule's source as **Any**. If it is limited to "My IP", GitHub's runners
cannot reach the VM. Key-only login keeps that safe.

Make sure the IP cannot change: the VM's **Public IP address** -> **Configuration** ->
assignment **Static**. New Standard IPs usually are already; if it were dynamic, stopping
the VM could give it a new address and break both your login and the pipeline.

<details>
<summary>Prefer the Azure CLI? The same VM in three commands</summary>

```bash
az group create --name tidewater-rg --location eastus
az vm create --resource-group tidewater-rg --name tidewater-vm \
  --image Canonical:ubuntu-24_04-lts:server:latest --size Standard_B2ats_v2 \
  --admin-username azureuser --ssh-key-values ~/.ssh/azure-mathew.pub --public-ip-sku Standard
az vm open-port --resource-group tidewater-rg --name tidewater-vm --port 8081 --priority 1010
```

`az vm create` prints `publicIpAddress` and opens SSH (22) by default.
</details>

### 3. Prepare the VM (as `azureuser`, once)

Log in with `ssh azureuser@<vm-ip>`, then:

```bash
# Update, then install Docker. Node is not needed on the VM: it runs inside the container.
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
sudo docker run --rm hello-world            # prints "Hello from Docker!"

# Mathew's account. Set a password when asked (it is for sudo); press Enter through the rest.
sudo adduser mathew
sudo usermod -aG docker mathew              # lets mathew (and the pipeline) run docker
sudo usermod -aG sudo mathew                # optional: only if Mathew should be an admin too

# Both public keys from step 1, one full line each
sudo install -d -m 700 -o mathew -g mathew /home/mathew/.ssh
echo "ssh-ed25519 AAAA... mathew-azure" | sudo tee -a /home/mathew/.ssh/authorized_keys
echo "ssh-ed25519 AAAA... tidewater-departures-deploy" | sudo tee -a /home/mathew/.ssh/authorized_keys
sudo chown mathew:mathew /home/mathew/.ssh/authorized_keys
sudo chmod 600 /home/mathew/.ssh/authorized_keys

# The folder the deploy scripts use
sudo mkdir -p /opt/tidewater-departures/bin /opt/tidewater-departures/state
sudo chown -R mathew:mathew /opt/tidewater-departures

# Check SSH password login is off (Azure turns it off for key-based VMs)
sudo sshd -T | grep -i '^passwordauthentication'   # should say: passwordauthentication no
```

If the upgrade says a reboot is needed, run `sudo reboot`, wait a minute and log back in.
Leave `ufw` off: Azure's port rules already do the firewall's job. If you ever turn it on,
run `sudo ufw allow OpenSSH` and `sudo ufw allow 8081/tcp` first, or you lock yourself out.

`mathew`'s password only unlocks sudo; with password login off, SSH accepts keys only.
(Shortcut: after `sudo adduser mathew`, `deploy/vps-setup.sh` does the Docker, group, key
and folder steps in one go, one public key per run. See the top of that file.)

### 4. Check both keys (from your laptop)

```powershell
ssh -i $HOME\.ssh\azure-mathew mathew@<vm-ip> docker ps
ssh -i $HOME\.ssh\tidewater-departures-deploy mathew@<vm-ip> docker ps
```

Both should print an empty table without asking for a password. The second one is
exactly how GitHub will log in.

### 5. Create the GitHub repo and add the secrets

Create an empty **public** repository called `tidewater-departures` on GitHub, with no README.
Then Settings -> Secrets and variables -> Actions -> **Secrets** tab -> **New repository secret**,
once per row. Use Secrets, not Variables: variables are stored and shown in plain text.

| Secret        | Value                                                                                         |
|---------------|-----------------------------------------------------------------------------------------------|
| `VPS_HOST`    | The VM's public IP                                                                            |
| `VPS_USER`    | `mathew`                                                                                      |
| `VPS_SSH_KEY` | The whole private key file `~/.ssh/tidewater-departures-deploy`, including the BEGIN and END lines |

To copy the private key without opening it:

* Windows PowerShell: `Get-Content $HOME\.ssh\tidewater-departures-deploy -Raw | Set-Clipboard`
* macOS: `pbcopy < ~/.ssh/tidewater-departures-deploy`

Then paste into the secret's value box. `GITHUB_TOKEN` is provided automatically and is
what pushes to and pulls from `ghcr.io`.

### 6. Push

From this project folder (PowerShell or Git Bash):

```bash
git init -b main
git add -A
git commit -m "Tidewater Tours Departures API with CI/CD"
git remote add origin https://github.com/<your-github-username>/tidewater-departures.git
git push -u origin main
```

`-b main` matters: the pipeline only runs for the `main` branch. Watch the **Actions**
tab: Test -> Build & push image -> Deploy to Azure VM. When all three are green, open
`http://<vm-ip>:8081/health` and the `version` is your commit.

## Rolling back

**One step:** Actions -> **Rollback** -> *Run workflow* -> leave the image blank -> *Run workflow*.

The job SSHes in and runs `rollback.sh`, which starts the image recorded in
`/opt/tidewater-departures/state/previous`, waits for `/health`, and swaps the
`current`/`previous` pointers so a second run rolls forward again. Pass a specific image
reference in the input box to pin any earlier commit.

From the VM itself: `/opt/tidewater-departures/bin/rollback.sh`.

## How the "done means" checks are met

| Check                                                | Where                                                                     |
|------------------------------------------------------|---------------------------------------------------------------------------|
| A failing test stops the pipeline before any deploy  | `needs:` chain in `ci-cd.yml`; build and deploy are skipped on red       |
| No secrets in the repository                         | Only `VPS_*` secrets + automatic `GITHUB_TOKEN`; `.gitignore` blocks keys |
| Health check passes after deploy                     | `deploy.sh` polls `/health`; job fails (and auto-rolls-back) otherwise    |
| Previous version runs after rollback                 | `rollback.sh` restores `previous`; `/health` shows the older SHA          |
| Image is small enough to explain                     | Multi-stage build below; `deploy.sh` logs the size on every deploy        |

### Image size

The Dockerfile has two stages. The first runs `npm ci --omit=dev` and is thrown away.
The second starts again from `node:22-alpine` and copies in only `node_modules`,
`package.json` and `src/`, so npm's cache, the lockfile, tests, docs and `.git` never
reach the image. It runs as the non-root `node` user and ships a `HEALTHCHECK`, so
`docker ps` shows `(healthy)`.

The image is about 233 MB. Roughly 228 MB of that is the `node:22-alpine` base; Express
and its dependencies are under 5 MB and the app code is tens of kilobytes. The Node
runtime is the floor for any Node image. `deploy.sh` prints the exact size
("image size: NN MB") in every deploy log.

## Producing the evidence (screenshots)

See [docs/screenshots/README.md](docs/screenshots/README.md) for the three screenshots
the brief asks for and the exact steps that produce each one.

## Limitations and next steps

* **SSH is open to the internet.** GitHub's hosted runners use many IP addresses, so the
  network security group allows port 22 from anywhere. Key-only login makes that
  acceptable; a self-hosted runner or Azure's own deploy tooling would avoid it.
* **Cost and uptime.** The free account covers 750 VM hours a month for 12 months, about
  one small VM running all month. Stopping the VM saves hours but takes the app offline.
* **Brief downtime.** A deploy swaps one container, so there is a second or two of
  downtime. A reverse proxy with two containers would make it zero-downtime.
* **Trust on first use.** `ssh-keyscan` trusts the VM's host key the first time the
  runner sees it. Pinning the host key in a secret would close that window.
