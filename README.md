# 🧠 MLRun CE Comprehensive Installation Guide (Air-Gapped / Offline)

This guide documents all the steps, scripts, and commands required to install a **comprehensive MLRun CE environment** on an **offline K3s Kubernetes cluster** using images saved from Harbor or locally. The setup includes monitoring, notebook, object storage, streaming, orchestration tools, and interactive querying via Spark and Trino.

---

## 📁 Project Structure

```
mlopsDev/adsk3dev/
├── charts/                  # Contains mlrun-ce Helm charts
├── offline-images/          # Pulled and saved Docker images
├── scripts/                 # Bash automation scripts
├── values/                  # Custom values and ingress configurations
├── .env                     # Environment configuration
```

---

## 📋 .env File (Required)

Place the following in `.env` file:

```env
HARBOR_DOMAIN=core.harbor.domain
HARBOR_PROJECT=mlops-images
HARBOR_USER=admin
HARBOR_PASS=Harbor12345
MLRUN_VERSION=0.9.0
INSTALL_MODE=local   # Options: local | harbor
```

> 📝 **Note:** You can later switch INSTALL_MODE to `harbor` when large image push issues are resolved.

---

## 🚀 Step-by-Step Installation

### 1️⃣ Prepare MLRun Images

```bash
./scripts/07-prepare-mlrun-images.sh
```

This script performs:

-   Cloning the `mlrun/ce` repository
-   Extracting image list from Helm chart
-   Pulling and saving Docker images to `offline-images/`

### 2️⃣ [Optional] Push to Harbor

Enable the push function in the script when ready:

```bash
# ./scripts/07-prepare-mlrun-images.sh
```

It will:

-   Tag & push images to Harbor registry
-   Save mapping in `images-list.txt`

### 3️⃣ Install MLRun from Images

```bash
./scripts/08-install-mlrun.sh
```

This script:

-   Creates `mlrun` namespace
-   Loads images from tarballs (if `INSTALL_MODE=local`)
-   Deploys MLRun components using Helm with values

### 4️⃣ Apply Ingress Rules

```bash
kubectl apply -f values/mlrun-ingress.yaml
```

This exposes components via Traefik Ingress:

> 💡 Ensure these domains are resolvable locally via `/etc/hosts` or internal DNS.

Example `/etc/hosts`:

```
192.168.0.21 mlrun.core.harbor.domain jupyter.mlrun.core.harbor.domain...
```

---

## 📈 Scripts

### ✅ `07-prepare-mlrun-images.sh`

-   Mode 1: Save images locally (default)
-   Mode 2: Push images to Harbor (optional)

### ✅ `08-install-mlrun.sh`

-   Reads `.env`
-   Supports `local` and `harbor` mode
-   Uses Helm to deploy from `charts/mlrun-ce`

### ✅ `09-install-spark.sh`

Installs Apache Spark via Helm:

```bash
./scripts/09-install-spark.sh
```

Ingress exposed: `https://spark.mlrun.core.harbor.domain`

### ✅ `10-install-trino.sh`

Installs Trino via Helm:

```bash
./scripts/10-install-trino.sh
```

## Ingress exposed: `https://trino.mlrun.core.harbor.domain`

## ⚠️ Warnings & Notes

-   Use `networking.k8s.io/v1` for `Ingress` in K3s
-   Replace deprecated `kubernetes.io/ingress.class` with `ingressClassName`
-   Ingress `404` means service is running but path or port is wrong — check `svc` and correct ingress `path`
-   Traefik must be configured to recognize custom ingress class if you renamed it

---

## 🔜 Next Steps

-   Add Keycloak auth integration (already scaffolded)
-   Add health-check & service validation script
-   Add user-friendly UI installer (optional)

---

> Maintained by: George
> Version: August 2025
