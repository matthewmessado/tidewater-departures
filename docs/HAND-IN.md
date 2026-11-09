# Hand-in checklist

Due: **Mon 9 Nov, 09:00**

| Item                                    | Where                                                                        |
|-----------------------------------------|------------------------------------------------------------------------------|
| Repository link with README             | `https://github.com/<your-github-username>/tidewater-departures`             |
| Screenshot: green run                   | `docs/screenshots/green-run.png`                                             |
| Screenshot: red run stopped by a test   | `docs/screenshots/red-run.png`                                               |
| Screenshot: rollback                    | `docs/screenshots/rollback.png` and `rollback-health.png`                    |
| Half-page runbook: deploy and roll back | `docs/RUNBOOK.md`                                                            |
| Nine-step notes on GitHub Actions       | `docs/NINE-STEP-NOTES.md`, all nine Apex steps, rewritten in your own words |

## Before you submit

- [ ] Personal key and pipeline key created on your laptop
- [ ] Azure VM created: Ubuntu 24.04 x64, `Standard_B2ats_v2` or `Standard_B1s`, SSH key login
- [ ] Inbound rules allow 22 and 8080 from any source
- [ ] VM prepared: Docker installed, `matthew` account created, both public keys added, `/opt/tidewater-departures` owned by `matthew`
- [ ] Both `ssh -i ... matthew@<vm-ip> docker ps` checks (personal key and pipeline key) work without a password
- [ ] Three secrets added to the repo (`VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`)
- [ ] First push to `main` is green end to end; `http://<vm-ip>:8080/health` shows the SHA
- [ ] Red run produced and reverted, so two green deploys now exist
- [ ] Rollback workflow run; `/health` shows the earlier SHA
- [ ] Screenshots saved in `docs/screenshots/` and committed
- [ ] Image size in your deploy log checked against the Limits section of the notes
- [ ] Nine-step notes rewritten in your own words, keeping examples from this project
- [ ] `<vm-ip>` and `<your-github-username>` placeholders replaced

## "Explains it" prep: why-questions to answer without notes

- Why does a red test stop the deploy? (`needs:` chain; skipped jobs never run their steps)
- Why tag the image with the commit SHA and not only `latest`? (immutable, traceable, a safe rollback target)
- Why does `/health` return the version? (it proves what is live after a deploy or rollback)
- Why two stages in the Dockerfile? (throw away npm's cache, the lockfile and tests; copy only runtime files)
- Why pipe `GITHUB_TOKEN` over stdin to the VM instead of storing a registry password? (short-lived, scoped, never on a command line or kept on disk)
- Why keep `previous` on the VM and not in GitHub? (rollback still works if GitHub is down)
- What happens if the new container never gets healthy? (`deploy.sh` restarts the previous one and fails the job)
- Why does GitHub get its own key instead of matthew's personal key? (it can be revoked on its own without locking matthew out, and his personal key never leaves his laptop)
- Why not let the pipeline log in as `azureuser`? (`azureuser` has passwordless sudo; the pipeline only needs Docker and its own folder)
- Why is SSH open to any source, and why is that acceptable? (GitHub's runners use many IPs; login is key-only, with no passwords)
- Why must the VM be x64? (the pipeline builds an x86_64 image; the free Arm size would fail with "exec format error")
- Why an Azure VM rather than LocalStack? (a real environment; the same scripts would run on AWS EC2)
