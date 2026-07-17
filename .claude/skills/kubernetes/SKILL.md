---
name: kubernetes
description: Use when creating, modifying, or reviewing Kubernetes manifests (Deployment, StatefulSet, Service, Ingress, ConfigMap, Secret, PVC, etc.), Helm charts, Kustomize overlays, kubectl commands, or any k8s-related task. Trigger on phrases like "deploy this", "fix the deployment", "update the helm chart", "configure the service", "set up ingress", "scale the pod", "k8s manifest", or any file path under k8s/, charts/, manifests/, kustomize/. Covers pod security, NetworkPolicy, RBAC, GitOps deployment, and zero-downtime patterns.
---

# Kubernetes

Extends `CLAUDE.md`. When this skill loads, its rules and Done criteria apply on top of the universal baseline.

## Workload manifests (production Deployments/StatefulSets/Jobs)

Dev and ephemeral environments may relax the resilience items (PDB, topology spread, anti-affinity) and NetworkPolicy — production manifests must never inherit that relaxation.

**Mandatory fields (production):**
- **Resource requests AND limits** for CPU and memory. Missing limits = noisy-neighbor risk; missing requests = unschedulable on full nodes.
- **All three probes** for slow-starting services: `livenessProbe`, `readinessProbe`, `startupProbe`.
  - `readinessProbe` must reflect dependency readiness (DB connection, cache warm), not just process up (canonical: observability skill).
  - `livenessProbe` triggers restart — keep it lightweight; never share with readiness.
  - `startupProbe` for apps with >10s init.
- **Image pinned by digest** in production manifests (`image: registry/app@sha256:...`), not by tag.
- **Dedicated `ServiceAccount`** per workload. Never use `default`.
- **`automountServiceAccountToken: false`** unless the pod calls the K8s API.

**`securityContext` (mandatory pod and container level):**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001          # non-zero
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
containers:
  - securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      # add capabilities only if absolutely required
```

**Resilience:**
- **PodDisruptionBudget** for any production workload with replicas >1 (`minAvailable` or `maxUnavailable`).
- **HorizontalPodAutoscaler** with sensible min/max and stabilization windows; consider `behavior` block for scale-down dampening.
- **TopologySpreadConstraints** across zones (`topology.kubernetes.io/zone`) for HA workloads.
- **PriorityClass** for critical workloads; system-cluster-critical never for app workloads.
- Anti-affinity to avoid co-scheduling replicas of the same Deployment on one node.

## Cluster-level rules

- **Namespaces** per environment, team, or bounded context. Never use `default` for real workloads.
- **NetworkPolicy default-deny** per namespace; explicit `Ingress`/`Egress` allows for required flows. Egress to DNS (kube-dns) and the API server must be allowed.
- **RBAC: least privilege.** No `cluster-admin` to humans or workloads. Prefer `Role` + `RoleBinding` over cluster-scoped.
- **Pod Security Standards: `restricted`** profile minimum at the namespace level via labels:
  ```yaml
  metadata:
    labels:
      pod-security.kubernetes.io/enforce: restricted
      pod-security.kubernetes.io/audit: restricted
      pod-security.kubernetes.io/warn: restricted
  ```
- **Admission control** via Kyverno or OPA Gatekeeper. Enforce policies as code.

## Forbidden in production

- `privileged: true`.
- `hostNetwork: true`, `hostPID: true`, `hostIPC: true`.
- `hostPath` mounts for application workloads.
- `emptyDir` for data that must survive pod restart.
- Capabilities `SYS_ADMIN`, `NET_ADMIN`, `NET_RAW` without explicit threat-model approval.
- Service `type: LoadBalancer` exposing the pod directly — use Ingress or Gateway with TLS.
- Storing kubeconfig with cluster-admin in any repo.

## Config & secrets

- **ConfigMap** for non-secret config; mount as files for large/structured config (env vars leak via process listings).
- **Never put secrets in plain `Secret` manifests in git.** Use:
  - External Secrets Operator (pulls from AWS/GCP/Vault).
  - Sealed Secrets (encrypted, decryptable only in-cluster).
  - SOPS with age/KMS.
- **Mount secrets as files**, not env vars, when possible. Environment variables are visible to anything that can read `/proc/<pid>/environ`.
- Rotate secret references via deployment annotation (`checksum/secret`) to force pod restart on change.

## Deployment & rollout

- **GitOps** (ArgoCD or Flux) for cluster state. No `kubectl apply` from laptops to production.
- **Rolling update** strategy:
  - `maxUnavailable: 0` for zero-downtime requirements.
  - `maxSurge: 1` (or 25%) to limit transient cost.
  - `minReadySeconds: 30` to catch crash-on-startup.
- **`Recreate` strategy** only for singletons that cannot run two instances (e.g., legacy migrations job).
- **Blue/green or canary** via Argo Rollouts or Flagger for high-risk services.

## Helm chart rules

- Values schema (`values.schema.json`) for every chart — fail early on bad input.
- No business logic in templates; use values + helpers (`_helpers.tpl`).
- `helm lint` and `helm template | kubeval` (or `kubeconform`) in CI.
- Pin chart versions; never `--version latest`.
- Don't render Secrets in `helm template` output; use external secret operators.
- Test charts with `helm test` and rendered manifest snapshots.

## kubectl & Operations

- `kubectl edit` on production resources is forbidden. All changes via PR + GitOps.
- `kubectl delete` on production: never without `--dry-run=client` first, then user confirmation.
- `kubectl exec` into production pods: read-only debugging only; never modify state.
- Use `kubectl auth can-i` to verify RBAC before claiming "permission issue".

## Validation in CI (must pass before merge)

- `kubeconform` (or `kubeval`) — schema validity.
- `kube-linter` — best practices (probes, limits, security context).
- `kyverno test` or `gatekeeper-conftest` — policy compliance.
- `trivy config` — IaC misconfigurations.
- `helm lint` and rendered-template diff for chart changes.

## Done criteria (in addition to CLAUDE.md §14)

- [ ] All workloads have requests AND limits for CPU and memory.
- [ ] All three probes defined where applicable; readiness reflects dependencies.
- [ ] `securityContext` enforces non-root, read-only root FS, dropped capabilities.
- [ ] Dedicated `ServiceAccount`, not `default`.
- [ ] Image pinned by digest in production manifests.
- [ ] PodDisruptionBudget present for replicated production workloads.
- [ ] No `privileged`, `hostNetwork`, `hostPath` (or explicit justification).
- [ ] NetworkPolicy in place for the workload's namespace (production; dev relaxation documented).
- [ ] Manifests pass `kubeconform`, `kube-linter`, and policy checks.
- [ ] No secrets in plain `Secret` manifests committed to git.
- [ ] Change deploys via GitOps, not `kubectl apply` from a laptop.
