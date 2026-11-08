# Runbook: Tidewater Tours Departures API

**Service:** container `tidewater-departures` on the Azure VM `tidewater-vm` (Ubuntu 24.04, x64), port 8081, Linux user `mathew`.
**Registry:** `ghcr.io/<owner>/tidewater-departures:<commit-sha>`.
**Health:** `curl http://<vm-ip>:8081/health` → `{"status":"ok","version":"<sha>",...}`. The `version` is the git commit that is live.

## Deploy

1. Merge or push to `main`. Nothing else is needed.
2. Watch **Actions → CI/CD**. Three jobs run in order: **Test → Build & push image → Deploy to Azure VM**.
   If Test is red, the other two are skipped and the VM is untouched.
3. The Deploy log ends with `health check passed: {...}` and `DEPLOYED ghcr.io/...:<sha>`.
   Confirm from outside: `curl http://<vm-ip>:8081/health` shows the new SHA.
4. If the new container never answers `/health` within 20 s, `deploy.sh` restarts the
   previous image automatically and the job fails red. Nothing more to undo.

**Re-deploy the same commit:** Actions → CI/CD → the run → *Re-run all jobs*.

## Roll back

**One step:** Actions → **Rollback** → *Run workflow* → leave *image* blank → *Run workflow*.

* It starts the image recorded as `previous` on the VM, waits for `/health`, and swaps
  the `current`/`previous` pointers. Running it a second time rolls forward again.
* To go to a specific build, paste its image reference (from the Build job's summary or
  the `ghcr.io` packages page) into the *image* box.
* Verify: `curl http://<vm-ip>:8081/health` shows the older SHA.

**From the VM** (if GitHub is unreachable):
`ssh -i ~/.ssh/tidewater-departures-deploy mathew@<vm-ip> /opt/tidewater-departures/bin/rollback.sh`

## Where things live

| What                       | Where                                                                            |
|----------------------------|----------------------------------------------------------------------------------|
| Live / previous image refs | `/opt/tidewater-departures/state/current`, `/opt/tidewater-departures/state/previous` |
| Deploy scripts             | `/opt/tidewater-departures/bin/` (copied by the pipeline on every deploy)        |
| Container logs             | `docker logs --tail 100 tidewater-departures`                                    |
| Service name and port      | `APP_NAME` / `APP_PORT` at the top of both workflow files                        |
| Secrets                    | GitHub repo → Settings → Secrets: `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`          |
| VM, firewall, metrics      | Azure portal → `tidewater-vm` (Networking for port rules, Monitoring for CPU/network) |

## If something is off

The deploy job stops with a named error. What each one means:

* **Missing secrets:** add the secrets it names.
* **Bad SSH key:** `VPS_SSH_KEY` must be the whole private key file, with no passphrase.
* **VM unreachable:** the VM is stopped, `VPS_HOST` is not its public IP, or the network
  security group does not allow SSH (22) from **any** source.
* **SSH login refused:** the pipeline's public key is not in `/home/mathew/.ssh/authorized_keys`,
  or that file's permissions are wrong. Redo README step 3's key lines as `azureuser`.
* **Docker not usable:** `mathew` is not in the `docker` group. As `azureuser`:
  `sudo usermod -aG docker mathew`.
* **Server not prepared:** `/opt/tidewater-departures` is missing or not owned by `mathew`.
  As `azureuser`: `sudo mkdir -p /opt/tidewater-departures/bin /opt/tidewater-departures/state`
  then `sudo chown -R mathew:mathew /opt/tidewater-departures`.
* **Wrong CPU type:** the VM is Arm. Recreate it with an x64 size such as `Standard_B2ats_v2`.
* **Health check failed:** the Actions log already shows the container's last 30 log lines.
* **Deploy is green but the browser cannot load the page:** port 8081 is not open in the
  VM's network security group. The health check runs on the VM itself, so it passes anyway.
