# Nine-step notes: GitHub Actions

Tool: **GitHub Actions**, as used in this project to test, build, deploy and roll back the
Tidewater Tours Departures API on an Azure Linux VM. The structure follows the nine Apex steps.

---

## 1. Purpose: why does it exist?

Without a pipeline, someone builds the app by hand, copies it to the server and restarts
it, with no record of what ran and nothing stopping a broken change. GitHub Actions turns
every code change into a release that happens the same way every time: tests, build and
deploy run on a machine that refuses to carry on when a step fails. "I pushed" becomes
"the new version is live and healthy", with a log that proves it.

## 2. Use: what is it used for in real work?

Typical uses: run tests on every pull request, build and tag container images, deploy to
staging and production, run scheduled jobs such as nightly dependency scans, and give
people a button for rare operations such as a rollback.

**Example from this project.** A push to `main` triggers `ci-cd.yml`. Job `test` runs
`npm test`. Only if it passes does `build-and-push` build the Dockerfile, tag the image
`ghcr.io/<owner>/tidewater-departures:<commit-sha>` and push it. Only then does `deploy`
SSH to the Azure VM as `mathew`, run `deploy.sh`, and wait for `GET /health` on port 8081
to return the new SHA. A second workflow, `rollback.yml`, is a manual *Run workflow*
button that restores the previous image. Pull requests run only the `test` job, so
reviewers see red or green before merging.

## 3. Versions: what versions or types exist?

| Dimension | Options | What this project uses and why |
|---|---|---|
| Runner | **GitHub-hosted** (fresh VM per job) vs **self-hosted** (your own machine, persistent) | GitHub-hosted `ubuntu-latest`: no maintenance, Docker and Node pre-installed, clean state every run |
| Trigger | `push`, `pull_request`, `workflow_dispatch` (button), `schedule` (cron), `release` | `push` + `pull_request` for CI/CD, `workflow_dispatch` for rollback |
| Step type | `uses:` a published action vs `run:` a shell script | Published actions for checkout, Node and Docker; plain shell for SSH, so the deploy is readable |
| Deploy strategy | **Recreate** (stop old, start new), **rolling**, **blue/green**, **canary** | Recreate: one container swapped in place. A second or two of downtime, simple to reason about. Blue/green would need a proxy in front |
| Deploy target | **IaaS** VM (Azure VM, EC2) vs **PaaS** container host (Azure Container Apps, App Service) | An Azure VM: everything is visible and explainable, and the same scripts would run on EC2 |
| Registry | GitHub Container Registry (ghcr.io), Docker Hub, Azure ACR, AWS ECR | ghcr.io: free with the repo, `GITHUB_TOKEN` logs in, no extra account |
| Action versions | Pinned by major tag (`@v7`) vs by commit SHA | Major tags are readable and pick up patches. SHA pinning is stricter for supply-chain safety. Majors still need bumping by hand |

## 4. Alternatives: what else could solve the same problem?

| Option | Pick it when | Why not here |
|---|---|---|
| **GitHub Actions** | Code already on GitHub, small team, no CI server to run | Chosen |
| **Azure Pipelines (Azure DevOps)** | The organisation already uses Azure DevOps boards and repos; deep Azure service connections | The code is on GitHub, and Actions needs no extra service |
| **GitLab CI** | Code lives on GitLab; registry and environments wanted in one product | The repo is on GitHub |
| **Jenkins** | Full control, on-premises, complex plugins, long-lived agents | A server to patch and secure for a one-service project |
| **ArgoCD (GitOps)** | Deploying to Kubernetes; the cluster pulls its desired state from git | No Kubernetes, just one VM with Docker |
| **Manual runbook** | One-off deploys, no automation budget | It is the problem the brief asks to remove |

If the client later wants managed hosting, Actions can stay for CI and only the deploy
job changes (to Azure Container Apps or App Service). The test and build jobs stay as they are.

## 5. Limits: where does it fail or become risky?

**Failure mode 1: a green pipeline ships a broken service.** Tests can be thin or flaky,
and a container can pass `npm test` yet crash on start (wrong port, missing setting).
How it is caught: `deploy.sh` polls `/health` for 20 s after the swap. If it never
answers, the script restarts the previous image and the job fails red.

**Failure mode 2: a leaked secret.** The deploy needs an SSH private key and registry
access, and it is easy to paste a key into a file or print it in a log. How it is caught:
every value lives in Actions secrets and reaches the shell only through `env:`. The SSH
key is written to a file on the runner, which is destroyed with the VM. The registry
token is the job-scoped `GITHUB_TOKEN`, piped over stdin to `docker login` and logged
out afterwards. The pipeline has its own key, separate from Mathew's personal one, so
it can be revoked on its own; sudo still needs Mathew's password, which GitHub never has.
`.gitignore` blocks key files, and Actions masks secret values in logs.

Other limits:

* **Wrong CPU type.** The Azure free account offers an Arm size (B2pts v2) next to the
  x64 ones. The pipeline builds an x86_64 image, which fails on Arm with "exec format
  error". The deploy job checks `uname -m` first and stops with a named error.
* **SSH open to the internet.** GitHub's hosted runners use many IP addresses, so the
  network security group allows port 22 from anywhere. Key-only login makes that
  acceptable; a self-hosted runner inside the network would avoid it.
* **The platform moves underneath you.** GitHub removed Node 20 from its runners on
  23 September 2026. Workflows still on older action majors such as `actions/checkout@v4`
  started showing "Node.js 20 is deprecated" warnings. This project uses the Node 24
  majors (`checkout@v7`, `setup-node@v7`, `setup-buildx-action@v4`, `login-action@v4`,
  `build-push-action@v7`). Reading the annotations on every run, not just the green
  tick, is how this gets noticed.
* **Cost.** The free account covers 750 VM hours a month for 12 months, roughly one
  small VM running all month. A second VM, or a bigger size, starts costing money.
* **Nothing persists between jobs.** `deploy` cannot see the image `build-and-push`
  made; it must pull it from the registry. The registry is the source of truth.
* **Drift.** The VM is set up once, by hand. If someone changes it later,
  the pipeline does not know. Infrastructure as code (Terraform, or Bicep on Azure) is the next step.
* **Trust on first use.** `ssh-keyscan` accepts whatever host key the VM presents the
  first time. Pinning the host key in a secret closes that gap.
* **Image size: about 233 MB.** Roughly 228 MB is the `node:22-alpine` base; Express and
  its dependencies are under 5 MB and the app code is tens of kilobytes. The multi-stage
  build keeps npm's cache and the tests out, but the Node runtime is the floor.
  `deploy.sh` prints the exact size on every deploy.
* **One container.** Recreate deploys mean a short blip and no redundancy.

## 6. Logs and Observability: how do we know what is happening?

| Question | Where the answer is |
|---|---|
| Did the pipeline pass, and which job failed? | Actions tab: job graph per run, red/green/grey (skipped) per job, step logs expand on click |
| Why did it fail? | Named errors from the pre-flight checks (missing secrets, bad key, VM unreachable, login refused, Docker not usable, wrong CPU type, server not prepared) |
| What image was built, and is it live? | The run summary at the top of the run: "Image pushed" and "Deployed ... passed /health" |
| What is running on the VM right now? | `http://<vm-ip>:8081/health` returns `{"status":"ok","version":"<sha>"}`; `docker ps` shows `(healthy)` from the Dockerfile `HEALTHCHECK` |
| Deploy history | Repo → Environments → production lists every deployment with its commit |
| Why did the container fail its health check? | `deploy.sh` prints the last 30 container log lines into the Actions log |
| App logs on the VM | `docker logs --tail 100 tidewater-departures`; the app logs JSON lines such as `{"level":"info","msg":"listening",...}` |
| Is the VM itself healthy? | Azure portal → the VM → Monitoring: CPU, network and disk graphs; Boot diagnostics if it will not start |
| Which images are current and previous | `cat /opt/tidewater-departures/state/current` and `/opt/tidewater-departures/state/previous` |

There is no app metrics dashboard yet. After a deploy, the `/health` JSON, the
Environments page and the VM's Monitoring graphs are the dashboard. Prometheus scraping
`/health` plus a Grafana panel, or Azure Monitor alerts, would be the next step.

## 7. Configuration: what settings matter?

`.github/workflows/ci-cd.yml`:

| Setting | Value | Why it matters |
|---|---|---|
| `env.APP_NAME` / `env.APP_PORT` | `tidewater-departures` / `8081` | The container name, the folder on the VM and the public port |
| `on.push.branches` / `on.pull_request` | `main` | Pull requests get tests only; pushes to main get the full chain |
| `needs:` | `build-and-push` needs `test`; `deploy` needs `build-and-push` | The gate. A red test skips everything after it |
| `if:` on build | `github.event_name == 'push' && github.ref == 'refs/heads/main'` | Never build or deploy from a pull request |
| `permissions` | `packages: write` (build), `packages: read` (deploy) | Least privilege for the automatic `GITHUB_TOKEN` |
| `build-args` | `APP_VERSION=${{ github.sha }}` | Baked into the image; shown by `/health` |
| Image tags | `<sha>` and `latest` | The SHA tag never moves, so it is a safe rollback target; `latest` is convenience |
| `cache-from/to: type=gha` | on | The second build reuses unchanged layers |
| `environment: production` | on deploy and rollback | Deployment history; required reviewers can be added later |
| `concurrency.group` | `deploy-refs/heads/main` in both workflows | A deploy and a rollback never overlap on the VM |
| `timeout-minutes` | 10 on every job | Fail fast instead of burning minutes |

Secrets (repo → Settings → Secrets → Actions), none of which are in the repo:

| Secret | Purpose |
|---|---|
| `VPS_HOST` | The Azure VM's public IP |
| `VPS_USER` | `mathew`, Mathew's own account on the VM |
| `VPS_SSH_KEY` | Private half of a key made only for this pipeline; the public half is in `mathew`'s `authorized_keys` |
| `GITHUB_TOKEN` | Automatic, per job, revoked when the job ends; pushes and pulls the image |

Azure settings that matter:

| Setting | Value | Why it matters |
|---|---|---|
| Image | Ubuntu Server 24.04 LTS, x64 | Matches the x86_64 image the pipeline builds |
| Size | `Standard_B2ats_v2` or `Standard_B1s` | Free-account x64 sizes; enough memory for Docker and one small app |
| Admin login | `azureuser` with the VM creator's SSH key | Sets the VM up; never given to GitHub |
| Mathew's account | `mathew`: password for sudo, two keys in `authorized_keys`, in the `docker` group | His personal key for him, the pipeline key for GitHub |
| Inbound rules | 22 and 8081 from any source | 22 for the runners, 8081 for users of the API |

Server-side settings live in `deploy/common.sh` as overridable environment variables
(`APP_NAME`, `APP_PORT`, `APP_DIR`, `STATE_DIR`, `HEALTH_RETRIES`). Nothing there is secret.

## 8. Procedures: how do we run, test, deploy, roll back and troubleshoot it?

The full version is `docs/RUNBOOK.md`.

* **Run locally:** `npm ci && npm start`, then open http://localhost:8080/health.
* **Test:** `npm test` boots the app on a random port and calls every route. CI runs the same command.
* **Set up the VM once:** create it in the portal and open port 8081. Then, as `azureuser`,
  install Docker, create the `mathew` account, add both public keys and create
  `/opt/tidewater-departures` owned by `mathew`.
* **Deploy:** push or merge to `main` and watch Actions → CI/CD. It is done when the Deploy
  job prints `health check passed` and `http://<vm-ip>:8081/health` shows the new SHA.
* **Re-run a failed job:** open the run → *Re-run failed jobs*. Redeploying the same image
  is safe and keeps the `previous` record intact.
* **Roll back (one step):** Actions → Rollback → *Run workflow* with the image box blank.
  `rollback.sh` starts the `previous` image, waits for `/health`, and swaps the records, so
  running it again rolls forward. Pasting an image reference pins any earlier commit.
* **Rehearse a rollback locally:** `bash deploy/local-demo.sh` deploys two versions with
  real Docker and rolls back, on http://localhost:9081/health.
* **Prove the gate:** break a test, push, and watch build and deploy go grey. Then revert.
* **Troubleshoot:** the deploy job names the problem. See "If something is off" in the runbook.

## 9. Internals: how does it work underneath?

```
 developer               GitHub                                  GitHub-hosted runners (fresh Ubuntu VM per job)
 ─────────   git push   ──────────                              ─────────────────────────────────────────────────
 laptop  ─────────────▶ repo (main) ──▶ event: push ──▶ workflow ci-cd.yml
                                                            │
                                  ┌─────────────────────────┼──────────────────────────────┐
                                  ▼                         ▼  (needs: test)               ▼  (needs: build-and-push)
                          [job: test]               [job: build-and-push]            [job: deploy]
                          checkout, setup-node      checkout, buildx                  write SSH key from secret
                          npm ci, npm test          docker login ghcr.io (TOKEN)      pre-flight checks
                                                    docker build (2 stages)           scp deploy/*.sh ─────────┐
                                                      layers: alpine ▸ node ▸         ssh deploy.sh <image> ───┤
                                                      node_modules ▸ src              GITHUB_TOKEN ──stdin──▶  │
                                                    push :sha and :latest             docker login on VM       │
                                                            │                                                  │
                                                            ▼                                                  ▼
                                                 GitHub Container Registry          Azure ── network security group (allow 22, 8081)
                                                 ghcr.io/<owner>/tidewater-departures            │
                                                 image = manifest + layer blobs                  ▼
                                                 (unchanged layers are not re-uploaded)   VM tidewater-vm, Ubuntu 24.04 x64
                                                                                          dockerd ── docker pull :sha
                                                                                          container "tidewater-departures" :8081 → app :8080
                                                                                          user mathew, HEALTHCHECK → /health
                                                                                          state: /opt/tidewater-departures/state/{current,previous}
```

What the pieces are doing:

* **Event → workflow → jobs.** GitHub matches the `push` event against `on:` in every
  workflow file, then builds a job graph from `needs:`. Jobs with no unmet dependencies
  start in parallel; a failed job marks the jobs that need it as *skipped*.
* **Runners.** Each job is a new virtual machine. `actions/checkout` clones the repo into
  it and `actions/setup-node` installs Node. When the job ends the VM is destroyed, so
  anything worth keeping must go to a cache, an artifact or a registry.
* **`${{ }}` expressions** are substituted by GitHub into the YAML before the step runs.
  Secrets become environment variables inside the step and are masked in the log.
* **Image layers.** Each Dockerfile instruction makes a read-only layer identified by a
  content hash. Stage 1 produces `node_modules`; stage 2 starts again from
  `node:22-alpine` and copies only `node_modules`, `package.json` and `src`, so the npm
  cache and the tests never become layers. The build cache (`type=gha`) reuses layers
  whose inputs have not changed. The image is built for x86_64, the runner's own CPU type.
* **Registry.** A push uploads the manifest and any layer blobs the registry does not
  already have, then points the tags `<sha>` and `latest` at that manifest. Tags are
  pointers: `latest` moves, `<sha>` never does, which is what makes it a safe rollback target.
* **Azure networking.** Traffic reaches the VM through its public IP and the network
  security group, a firewall that sits outside the VM. Only ports 22 and 8081 are allowed in.
* **Deploy.** The runner never talks to Docker on the VM directly. It runs a shell script
  over SSH as `mathew`. That script asks `dockerd` to pull the manifest, download missing
  layers, remove the old `tidewater-departures` container and start a new one,
  publishing the VM's port 8081 to the app's port 8080 inside the container.
  `APP_VERSION` is already set inside the image, and `/health` returns it, which
  closes the loop between "what git says" and "what is serving".
