# Screenshots to hand in

Save the PNGs in this folder with these names. They also serve as the Step 6
(Logs and Observability) evidence in the nine-step notes. `<vm-ip>` is the Azure VM's
public IP.

## 1. `green-run.png`: a passing pipeline

1. Push any commit to `main` (the first push after setup is fine).
2. Actions → CI/CD → open the run. Wait for all three jobs to be green.
3. Capture the run page showing **Test → Build & push image → Deploy to Azure VM** all green.
4. Open the Deploy job log and capture the last lines (`health check passed: {...}` and
   `DEPLOYED ghcr.io/...`). Save it as `green-run-health.png`.

## 2. `red-run.png`: a failing test stops the pipeline

1. Break one test on purpose. In `test/api.test.js` change
   `assert.equal(body.count, 5);` to `assert.equal(body.count, 6);`
2. Commit and push to `main` with a message like `test: break a test to prove the gate`.
3. Actions → CI/CD → open the run. **Test** is red; **Build & push image** and
   **Deploy to Azure VM** show as skipped (grey). Capture that.
4. Confirm nothing deployed: `http://<vm-ip>:8080/health` still shows the previous SHA.
5. Undo it and push again. That run deploys, so the VM now has a previous version:

   ```bash
   git revert --no-edit HEAD
   git push
   ```

## 3. `rollback.png`: one-step rollback

**Rehearse it first on your own machine** (Docker Desktop running, from the project folder):

```bash
bash deploy/local-demo.sh
```

It builds two versions, deploys v1, deploys v2, then runs the same `rollback.sh` the
pipeline uses. Open http://localhost:9081/health and it shows `"version":"demo-v1"`.
This is a fallback screenshot if the VM is not ready in time; the real one below is better evidence.

**The real one, on the VM** (needs the two green deploys from steps 1 and 2):

1. Note the live version: `http://<vm-ip>:8080/health` → `"version":"<sha-B>"`.
2. Actions → **Rollback** → *Run workflow* → leave the image blank → *Run workflow*.
3. Open the run → *Roll back on Azure VM* job log. Capture the lines
   `rolling back: ...:<sha-B> -> ...:<sha-A>`, `health check passed` and `ROLLED BACK to ...`.
4. Refresh `http://<vm-ip>:8080/health`. It now shows `"version":"<sha-A>"`.
   Capture that as `rollback-health.png`: it proves the previous version is running.
