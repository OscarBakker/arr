# k3d local Kubernetes setup

Run a **Node.js todo app** on [k3d](https://k3d.io/) (Kubernetes in Docker) with **Helm** and **CronJobs** for backups. Use this to learn k3d, Helm, and Kubernetes basics.

## What's in here


| Path             | Purpose                                               |
| ---------------- | ----------------------------------------------------- |
| `cluster.sh`     | Create or delete the k3d cluster                      |
| `app/`           | Simple Node.js Express todo app (source + Dockerfile) |
| `helm/todo-app/` | Helm chart: web app + optional backup CronJob         |
| `LEARNING.md`    | Concepts and how to experiment                        |


## Prerequisites

- **Docker** running
- **k3d** installed: `brew install k3d` (or [install](https://k3d.io/v5.x/docs/installation/))
- **kubectl**: `brew install kubectl`
- **Helm 3**: `brew install helm`

Check:

```bash
k3d version
kubectl version --client
helm version
```

## Quick start

All commands below are from the `**k3d**` directory. If needed: `chmod +x cluster.sh`

### 1. Create the cluster

```bash
./cluster.sh create
```

This creates a cluster named `todo-cluster` and loads images from your local Docker into it.

### 2. Build and load the app image

```bash
docker build -t todo-app:local ./app
k3d image import todo-app:local -c todo-cluster
```

### 3. Install the Helm chart

```bash
helm upgrade --install todo ./helm/todo-app \
  --set image.repository=todo-app \
  --set image.tag=local \
  --set backupCron.enabled=true
```

### 4. Access the app

Port-forward the service:

```bash
kubectl port-forward svc/todo-todo-app 3000:80
```

Then open [http://localhost:3000](http://localhost:3000) — add todos and use “Export” to see JSON. Backups run on the schedule you set (default: every 5 minutes).

### 5. Tear down

```bash
./cluster.sh delete
```

## Backup CronJob

The chart includes an optional **CronJob** that calls the app’s `/api/export` endpoint and saves the result. Enable/disable and set the schedule in `helm/todo-app/values.yaml` under `backupCron`. See `LEARNING.md` for how it works and how to add more cron jobs.

## Next steps

- Read `LEARNING.md` for k3d, Helm, and CronJob concepts.
- Change `helm/todo-app/values.yaml` and run `helm upgrade --install ...` again to see how values drive the chart.
- Add a second CronJob (e.g. different schedule or backup target) by copying the CronJob template and adding a new key under `backupCron` or a new section.

