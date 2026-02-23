# Learning guide: k3d, Helm, and CronJobs

This doc explains the concepts used in this setup so you can tweak things and add more cron jobs.

---

## 1. What is k3d?

**k3d** runs [K3s](https://k3s.io/) (a lightweight Kubernetes) inside Docker containers. So you get a real Kubernetes API and behaviour on your laptop without VMs or a cloud.

- **Cluster** = one or more Docker containers acting as the control plane + nodes.
- **`k3d cluster create`** creates the cluster; **`k3d image import`** makes your local Docker image available inside that cluster (so you don’t need a registry for local dev).
- **kubectl** talks to the cluster via the kubeconfig that k3d updates (e.g. `kubectl config use-context k3d-todo-cluster`).

Useful commands:

```bash
k3d cluster list
k3d cluster start todo-cluster   # after a reboot
kubectl get nodes
kubectl get pods -A
```

---

## 2. What is Helm?

You already know that Kubernetes uses **Pods**, **Deployments**, **Services**, **CronJobs**, etc. You define them in YAML and apply them with `kubectl apply`. Helm doesn’t replace that: **Helm produces the YAML and then applies it for you.** The extra part is: it uses **templates** plus **values** so one set of files can drive many environments or versions without copy-pasting.

### The problem Helm solves

Without Helm, you might have:

- `deployment.yaml`, `service.yaml`, `cronjob.yaml` …
- For **staging** you want 1 replica and image `todo-app:staging`; for **production** you want 3 replicas and `todo-app:v1.2`. You either maintain separate YAML files per environment or do lots of search-replace.
- When you change the app name or add a new resource, you have to touch several files and keep names/labels in sync.

Helm gives you **one package (a “chart”)** that describes your app in terms of **templates** and **configuration (values)**. You change config in one place; Helm generates the final YAML and applies it. So: same chart, different values → different Deployment/Service/CronJob YAML.

### Chart vs release

- **Chart** = the package. It’s the folder (e.g. `helm/todo-app/`) containing:
  - **`Chart.yaml`** — name and version of the chart (the package itself).
  - **`values.yaml`** — default configuration (image name/tag, replicas, schedules, feature flags like “enable backup cron”).
  - **`templates/`** — Kubernetes YAML files with **placeholders** (e.g. `{{ .Values.replicaCount }}`, `{{ include "todo-app.fullname" . }}`). These are the same kinds of resources you already know: Deployment, Service, CronJob, etc.

- **Release** = one **installed instance** of that chart. When you run `helm upgrade --install todo ./helm/todo-app`, the release **name** is `todo`. That name is used in the generated resource names (e.g. `todo-todo-app`) and so that Helm can track “what did I last apply?” for upgrades and rollbacks.

So: one **chart** can be installed multiple times as different **releases** (e.g. `todo-staging`, `todo-prod`) with different values.

### What actually happens when you run Helm

When you run:

```bash
helm upgrade --install todo ./helm/todo-app
```

1. Helm reads **`values.yaml`** (and any `-f other-values.yaml` or `--set key=value` you pass).
2. It **renders** every file in `templates/`: it replaces each `{{ ... }}` with the right value (e.g. `{{ .Values.replicaCount }}` → `1`, `{{ .Release.Name }}` → `todo`). The result is **plain Kubernetes YAML** (the same kind you’d write by hand or apply with `kubectl`).
3. Helm sends that YAML to the Kubernetes API (same as `kubectl apply` would). So the cluster ends up with the same Pods, Deployments, Services, CronJobs you’re used to.
4. Helm stores **release state** (what it applied, which version) so that the next time you run `helm upgrade`, it can compute a diff and only change what’s different, and so you can do `helm rollback`.

So in short: **Helm = template engine + values + “apply to the cluster” + release history.** The cluster still runs the same Kubernetes resources; Helm is a better way to generate and manage them.

### A concrete example (template → rendered YAML)

In our chart, the Deployment uses the replica count from values. In the template you have something like:

```yaml
spec:
  replicas: {{ .Values.replicaCount }}
```

If `values.yaml` has `replicaCount: 1`, Helm renders that to:

```yaml
spec:
  replicas: 1
```

That’s the YAML that actually gets applied. So the **templates** are the shape of your resources; **values** are the knobs (replicas, image tag, schedule, “enable cron or not”). Change the value, run Helm again, and the Deployment (or CronJob, etc.) is updated without editing the template.

### Why “upgrade --install”

- **`helm install`** — “Create a new release.” Fails if a release with that name already exists.
- **`helm upgrade`** — “Change an existing release to match this chart and these values.”
- **`helm upgrade --install`** — “If the release doesn’t exist, install it; if it does, upgrade it.” One command to “make the cluster look like this chart with these values.”

So you typically use `helm upgrade --install todo ./helm/todo-app` every time: first run installs, later runs upgrade (e.g. after you change `values.yaml` or the chart).

### Useful Helm commands

```bash
# See the exact YAML Helm would apply (no cluster changes)
helm template todo ./helm/todo-app

# See what values are in use for an installed release
helm get values todo

# Apply or update the release (what you run after editing values or templates)
helm upgrade --install todo ./helm/todo-app

# List releases
helm list

# Roll back to the previous release revision
helm rollback todo
```

Once you run Helm, you inspect the cluster with the same **kubectl** commands you’d use for Pods, Deployments, Services, CronJobs—because that’s exactly what Helm created.

---

## 3. What we deploy

| Resource    | Role |
|------------|------|
| **Deployment** | Runs the todo app (Node) as one or more Pods. |
| **Service**    | Stable DNS name and port for those Pods (e.g. `todo-todo-app:80`). Other things in the cluster (e.g. the CronJob) call this. |
| **CronJob**    | Creates a **Job** on a schedule. Each Job runs a Pod (here: `curl` hitting the app). |
| **Ingress**    | Optional; only created if `ingress.enabled: true`. Exposes HTTP from outside the cluster. |

The app listens on port **3000** inside the container. The **Service** exposes that as port **80** inside the cluster so the CronJob uses `http://todo-todo-app:80/api/export`.

---

## 4. How the backup CronJob works

- **CronJob** = “run this Pod on a schedule.”
- **Schedule** is standard cron: `minute hour day month weekday`. Example: `*/5 * * * *` = every 5 minutes; `0 2 * * *` = daily at 2:00.
- When the schedule fires, Kubernetes creates a **Job**, which runs a **Pod**. Our Pod runs `curl` and calls the todo-app **Service** by name. Kubernetes DNS resolves `todo-todo-app` (in the same namespace) to the Service IP.

So the “backup” is simply: “every N minutes, a container runs and GETs `/api/export`.” The response could later be written to a volume or sent to S3; for learning, we just run curl so you can see the Job in `kubectl get jobs` and `kubectl logs job/<name>`.

---

## 5. Adding more cron jobs (e.g. another backup)

You have two main options.

### Option A: Second CronJob in the same chart

1. **Add a new section in `values.yaml`**, e.g.:

   ```yaml
   backupCron2:
     enabled: true
     schedule: "0 3 * * *"   # 3am daily
     image:
       repository: curlimages/curl
       tag: latest
   ```

2. **Copy `templates/cronjob-backup.yaml`** to e.g. `templates/cronjob-backup2.yaml` and change:
   - The condition to `{{- if .Values.backupCron2.enabled }}`
   - The CronJob name to e.g. `{{ include "todo-app.fullname" . }}-backup2`
   - All `.Values.backupCron` to `.Values.backupCron2`

That gives you a second CronJob with its own schedule.

### Option B: Separate Helm chart for “backup jobs”

Create another chart (e.g. `helm/backup-jobs/`) that only contains CronJob templates and values. Install it next to the app:

```bash
helm upgrade --install backup-jobs ./helm/backup-jobs
```

That chart would need the **Service name** of the todo-app (e.g. `todo-todo-app`) in its values so the curl (or script) knows where to call.

---

## 6. Quick reference: cron schedule

| Schedule      | Meaning        |
|---------------|----------------|
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *`   | Every hour      |
| `0 2 * * *`   | Daily at 2:00   |
| `0 0 * * 0`   | Weekly (Sunday midnight) |

---

## 7. Useful kubectl commands

```bash
# Pods for the app
kubectl get pods -l app.kubernetes.io/name=todo-app

# Logs of the app
kubectl logs -l app.kubernetes.io/name=todo-app -f

# CronJobs and their Jobs
kubectl get cronjobs
kubectl get jobs
kubectl logs job/todo-todo-app-backup-28392847  # replace with actual job name
```

You can use this setup to experiment with schedules, add a second CronJob, or point the backup at a real endpoint/volume and learn from the results.
