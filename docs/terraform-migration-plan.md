# Terraform rewrite of `pulumi-eks-ml`

## Context

`pulumi-eks-ml` is a Python Pulumi component library (~6.3k LOC, 22 `ComponentResource`
classes) plus three reference projects that build multi-tenant, multi-region ML platforms
on EKS. The goal is a Terraform port of the whole surface area so the same architectures
can be deployed by teams standardised on Terraform.

Decisions already made (from discussion):

- **Side-by-side.** Nothing under `pulumi_eks_ml/`, `projects/`, or `tests/` is deleted or
  modified. All new work lands under a new top-level `terraform/` directory. Both stacks
  stay maintained through the transition.
- **Hybrid modules.** Hand-roll the VPC (its subnet layout is bespoke and no upstream
  module expresses it); build the cluster on `terraform-aws-modules/eks/aws`.
- **Two-layer split** for multi-region, not Terragrunt — see below.
- **Full surface area**: VPC + peering, EKS + Karpenter, all 7 addons, Tailscale, and the
  complete SkyPilot multi-tenant stack.

## The two-layer split

Terraform cannot `for_each` over provider configurations. Two facts shape the layout:

1. **AWS resources don't need aliases any more.** AWS provider v6 added a top-level
   `region` argument to nearly every resource. The Pulumi code already depends on this —
   `pulumi_eks_ml/vpc/multi_region.py:70` passes `region=vpc_a.region` straight to
   `VpcPeeringConnection` (pulumi-aws 7 wraps TF AWS provider 6). So the entire AWS layer
   can live in one root with a single default provider and `for_each` over a **dynamic**
   region list, exactly like today.
2. **`kubernetes`/`helm` providers genuinely cannot be looped.** Each needs a distinct
   endpoint + token per cluster.

So:

- **Layer 1 (`aws/`)** — one root, one apply, dynamic regions: VPCs, peering mesh, EKS
  control planes, OIDC providers, Fargate profiles, all IAM/IRSA roles, EFS filesystems,
  Cognito, Route53. Outputs everything layer 2 needs.
- **Layer 2 (`k8s/`)** — one root **per cluster**, its own `kubernetes`/`helm` provider
  built from layer 1's outputs: Helm releases, Karpenter CRs, namespaces, RBAC, secrets.

This also sidesteps Terraform's worst chronic problem — a provider configured from a
resource created in the same apply, which fails on the first run and produces
"provider configuration not known until apply" errors.

A consequence worth stating up front: today's `EKSCluster` component mixes both layers
(it builds the k8s provider, the `aws-observability` namespace, the `aws-logging`
ConfigMap, and Karpenter). The port cleaves it along the AWS/k8s line.

## Target layout

```
terraform/
├── modules/
│   ├── vpc/                     # vpc/core.py + vpc/utils.py       (hand-rolled)
│   ├── vpc-peering/             # vpc/multi_region.py
│   ├── irsa/                    # eks/irsa.py
│   ├── eks-cluster/             # eks/cluster.py (AWS half)        (wraps upstream module)
│   ├── cluster-bootstrap/       # eks/cluster.py (k8s half)
│   ├── karpenter-iam/           # eks/karpenter.py (AWS half)
│   ├── karpenter/               # eks/karpenter.py (k8s half)
│   ├── addons/{alb-controller,ebs-csi,efs-csi,external-dns,
│   │           fluent-bit,metrics-server,nvidia-device-plugin}/
│   ├── cluster-addons/          # aggregator ≈ EKSClusterAddonInstaller
│   ├── tailscale-subnet-router/
│   └── skypilot/{cognito-idp,service-discovery,data-plane,
│                 user-identity,api-server}/
└── examples/
    ├── starter/                 # single region → single root, one apply
    ├── multi-region/{aws,k8s}/
    └── skypilot-multi-tenant/{aws,dataplanes,hub}/
```

Modules stay plain Terraform with no wrapper tooling, so they can be consumed from git or
a registry the way the Python package is consumed from PyPI.

## Module-by-module notes

Full source inventory is in the repo; these are the parts where a literal translation is
wrong or impossible.

### `modules/vpc` — from `vpc/core.py`, `vpc/utils.py`

13 resources: 1 VPC, N private subnets, 1 `/28` public subnet, 2 route tables, N+1
associations, IGW, EIP, single NAT gateway, 2 routes.

`calculate_subnets` (`vpc/utils.py:54`) reserves the **last** `/28` for public and packs
maximal equal private subnets at the front. Port to `locals` — and note the Python's
overlap check is redundant: because the public block is always the last `/28`, the first
`num_azs` subnets avoid it exactly when `2^(p - vpc_prefix) > num_azs`. Both conditions
collapse into one:

```hcl
locals {
  vpc_prefix     = tonumber(split("/", var.cidr_block)[1])
  public_cidr    = cidrsubnet(var.cidr_block, 28 - local.vpc_prefix, pow(2, 28 - local.vpc_prefix) - 1)
  private_prefix = [for p in range(local.vpc_prefix + 1, 29) : p if pow(2, p - local.vpc_prefix) > var.num_azs][0]
  private_cidrs  = [for i in range(var.num_azs) : cidrsubnet(var.cidr_block, local.private_prefix - local.vpc_prefix, i)]
}
```

`/16` + 3 AZs must yield three `/18` + one `/28`, matching `tests/unit/test_vpc.py`.

**`region_to_cidr` needs a behaviour change.** Its fallback hashes the region name and
takes `int(sha1_digest, 16) % 100` over the *full* 40-hex-char digest — a bignum HCL
cannot represent, so unknown regions are not reproducible. Rather than silently drifting
CIDRs, expand the static map to cover all current AWS regions and make an unmapped region
a `validation` error, with a `var.region_cidrs` override for custom mappings.

No resource in this component sets tags today. Add `default_tags` at the provider level in
the examples.

### `modules/vpc-peering` — from `vpc/multi_region.py`

5 resources per region pair: 1 `aws_vpc_peering_connection`, 2
`aws_vpc_peering_connection_accepter` (accepter-side auto-accept + DNS, requester-side
DNS), 2 `aws_route`. Build the pair list in `locals` (`combinations` → nested `for` with
`a < b`; hub-and-spoke → hub × spokes), keep the alphabetical ordering that today
stabilises names, and `for_each` with `region = each.value.region_a` per resource. No
provider aliases needed.

### `modules/eks-cluster` — from `eks/cluster.py` (AWS half)

Wraps `terraform-aws-modules/eks/aws`. Settings to reproduce from `_create_eks_cluster`
(`eks/cluster.py:125`):

- `cluster_version = "1.35"`, `enable_irsa = true`, private **and** public endpoint access,
  `cluster_enabled_log_types` = the 5 in `config.CLUSTER_LOG_TYPES`,
  `authentication_mode = "API_AND_CONFIG_MAP"`, `bootstrap_self_managed_addons = false`.
- No node groups at all — Fargate + Karpenter only.
- `create_cluster_security_group = false`, `create_node_security_group = false`; reference
  the EKS-managed primary SG (`skip_default_security_groups=True` in Pulumi means the
  component adds none of its own).
- `vpc-cni` and `kube-proxy` as `cluster_addons` with `OVERWRITE` on create and update.

Hand-rolled in this module, because ordering matters:

- Fargate pod execution role — trust `eks-fargate-pods.amazonaws.com` scoped by
  `ArnLike aws:SourceArn = arn:aws:eks:{region}:{acct}:fargateprofile/{cluster}/*`
  (asserted by `tests/unit/test_eks_cluster.py`), plus the managed policy attachment.
- `aws_eks_fargate_profile` with the coredns + karpenter selectors.
- **`coredns` as a separate `aws_eks_addon` with `depends_on` on the Fargate profile.**
  This ordering is deliberate in the original and must survive the port.
- Node security group + its 12 rules (6 explicit + 6 from `CLUSTER_FROM_NODE_SG_RULES`).
  Use `aws_vpc_security_group_ingress_rule`/`_egress_rule`, not the deprecated
  `aws_security_group_rule`; the "allow all internal" self-rule becomes
  `referenced_security_group_id = aws_security_group.node.id`.

### `modules/cluster-bootstrap` — from `eks/cluster.py` (k8s half)

`aws-observability` namespace + `aws-logging` ConfigMap. Note the existing
`output.conf` ships literal placeholders (`region region-code`, `log_group_name my-logs`,
`eks/cluster.py:418`). Parameterise them as variables defaulting to the cluster's region
and `/eks/fluentbit/logs/{cluster}` rather than porting the placeholders verbatim.

### `modules/karpenter-iam` + `modules/karpenter` — from `eks/karpenter.py`

Layer 1: node role (EC2 trust), 4 managed policy attachments from `EKS_NODE_POLICIES`,
`aws_eks_access_entry` of type `EC2_LINUX`, and the controller IRSA role carrying the
16-statement policy from `create_karpenter_controller_policy` (`eks/karpenter.py:18`).
Port that policy into an `aws_iam_policy_document` statement-for-statement — the SIDs and
tag conditions are load-bearing.

Layer 2: `helm_release` for `oci://public.ecr.aws/karpenter/karpenter` v1.8.6, then one
`EC2NodeClass` + one `NodePool` per pool.

**CRD chicken-and-egg — the biggest place Terraform is worse than Pulumi here.**
`kubernetes_manifest` reads the CRD schema at *plan* time, so it cannot plan resources
whose CRDs are installed by a `helm_release` in the same apply. Use the `alekc/kubectl`
provider's `kubectl_manifest` (maintained fork of `gavinbunney/kubectl`) for the three CRD
kinds — `karpenter.k8s.aws/v1 EC2NodeClass`, `karpenter.sh/v1 NodePool`,
`tailscale.com/v1alpha1 Connector`. It skips plan-time API validation, which is the point.

`NodePoolConfig.gpu` (the `g*`/`p*` prefix heuristic, `eks/config.py:141`) becomes
`alltrue([for s in local.instance_specs : can(regex("^[gp]", s))])`, driving the same
`nvidia.com/gpu.present` label, nvidia manufacturer requirement, and
`nvidia.com/gpu:NoSchedule` taint.

### `modules/irsa` — from `eks/irsa.py`

One role + N policy attachments. **Fix a real bug while porting:**
`_build_irsa_assume_role_policy` (`eks/irsa.py:19`) writes the `:sub` condition under key
`StringEquals`, then adds a second literal `"StringEquals"` key for `:aud` — in Python the
second key overwrites the first, silently dropping the service-account restriction for
every non-wildcard SA. In `aws_iam_policy_document`, two separate `condition` blocks with
the same `test` merge correctly, so the natural HCL is also the correct one. Worth opening
a separate issue against the Pulumi side.

### `modules/addons/*` — from `eks_addons/`

Seven modules, each an IRSA role + a `helm_release`, values via `yamlencode`. Charts and
pinned versions are in `eks/config.py:16-22`. Extras beyond Helm:

- **ebs-csi** — `gp3` StorageClass marked default, encrypted, WaitForFirstConsumer.
- **efs-csi** — `aws_efs_file_system` + **one mount target per subnet**. The Pulumi version
  creates these inside an `Output.all().apply()` (`eks_addons/efs_csi_addon.py:105`) and
  doesn't even assign the result; a plain `for_each` over subnet IDs is both simpler and
  more correct. Plus the `efs-default` StorageClass.
- **fluent-bit** — CloudWatch log group `/eks/fluentbit/logs/{cluster}`, 30-day retention,
  node affinity excluding Fargate.
- **alb-controller** — the 19-statement inline policy (`alb_controller_addon.py:33-262`).
- **nvidia-device-plugin** — tolerations harvested from every node pool's taints.

`modules/cluster-addons` aggregates them in the `recommended_addons()` order. Today
`EKSClusterAddonInstaller` chains each addon's `depends_on` to the previous one, forcing
strictly serial installs. **Drop that artificial serialisation** and keep only the real
edges (EFS StorageClass needs the CSI driver; nvidia plugin needs node pools). Call this
out as an intentional behaviour change — it is the one place the port deliberately
diverges for speed.

### `modules/skypilot/*` and `modules/tailscale-subnet-router`

Mostly mechanical: Cognito user pool/client/domain/branding, the private Route53 zone
(keep `prevent_destroy` to mirror `retain_on_delete=True`), per-tenant namespace + 7 RBAC
objects, per-tenant user IRSA + annotated ServiceAccount, the FUSE device manager, and the
API server's 13-statement IAM policy + `helm_release`.

Two things need attention:

- **Kubeconfig assembly** (`data_plane.py:620`). The hub API server needs one kubeconfig
  spanning *every* cluster, built from each data plane's SA token Secret. In Terraform:
  `data "kubernetes_secret"` per data plane, then `yamlencode`. Because the sources span
  clusters, the SkyPilot example needs three roots rather than two — `aws/`,
  `dataplanes/` (run per region, outputs the endpoint/CA/token tuples as sensitive), and
  `hub/` (consumes them via `terraform_remote_state`, assembles the kubeconfig, deploys
  Cognito wiring, Tailscale, and the API server). If you'd rather have one apply, the
  fallback is static `kubernetes` provider aliases for a fixed hub + N spokes, at the cost
  of a hardcoded region set.
- **The htpasswd hash.** `SkyPilotAdminCredentials` builds an apr-md5-crypt line with
  `passlib` (`api_server.py:287`). Terraform has `bcrypt()` but no apr-md5, and the value
  is already commented out of the Helm values (`api_server.py:90`). Drop it: keep the
  `random_password` and the Secrets Manager entry, skip the `initial-basic-auth` Secret.

### Secrets

`Output.secret` maps to `sensitive = true` (Cognito client id/secret, SkyPilot admin
password, the assembled kubeconfig). Unlike Pulumi, **Terraform state stores these in
plaintext** — the examples must document an S3 backend with SSE-KMS and restricted access
as a prerequisite, not an optional extra.

## Verification

1. `terraform fmt -check -recursive` and, per module, `terraform init -backend=false &&
   terraform validate`.
2. **Native `terraform test`** (`.tftest.hcl`, plan-only) for the pure logic — this is
   where the existing Python unit tests port cleanly:
   - `modules/vpc`: the 5 parametrised subnet cases and 2 error cases from
     `tests/unit/test_vpc.py`, including `/16` + 3 AZs → three `/18` + one `/28`.
   - `modules/eks-cluster`: the node SG rule set is exactly 12 rules on the expected ports,
     and the Fargate trust policy carries the right `aws:SourceArn` — mirroring
     `tests/unit/test_eks_cluster.py`.
   - `modules/irsa`: the trust document restricts **both** `:sub` and `:aud` (the bug fix).
3. **LocalStack** via `tflocal`, mirroring `tests/integration/`: apply `modules/vpc` and
   assert the subnet CIDR set; apply `modules/vpc-peering` hub-and-spoke across
   us-east-1/us-west-2/eu-west-1 and assert both directions' routes landed. EKS is not
   available in LocalStack's free tier, same limitation as today.
4. **Real apply** of `examples/starter` in a scratch account, then smoke-test: Karpenter
   provisions a node for a pending pod on the `general` pool; a GPU pod schedules on the
   `gpu` pool with the nvidia taint tolerated; a PVC on `efs-default` binds; an ALB ingress
   gets an address.
5. `examples/multi-region` with two regions: layer 1 apply, then layer 2 per region;
   confirm cross-region pod-to-pod connectivity over the peering links.
6. `examples/skypilot-multi-tenant` end-to-end against the existing runbook in
   `projects/skypilot-multi-tenant/DEPLOYMENT.md` — Cognito login, a `sky launch` into each
   tenant namespace, and tenant isolation (team-a cannot reach team-b's namespace).

## Phasing

Each phase ends green on `fmt`/`validate`/`terraform test` and is independently
committable.

1. **Foundations** — `vpc`, `vpc-peering`, `irsa` + their `terraform test` suites.
2. **Cluster** — `eks-cluster`, `cluster-bootstrap`, `karpenter-iam`, `karpenter`.
3. **Addons** — the 7 addon modules + `cluster-addons`.
4. **First examples** — `starter`, then `multi-region`. First real end-to-end validation;
   expect module-interface churn here.
5. **Apps** — `tailscale-subnet-router` and the 5 `skypilot/*` modules.
6. **SkyPilot example + docs + CI** — the three-root example, `terraform/README.md`, a note
   in the root `README.md` that both implementations are live, and
   `.github/workflows/terraform.yml` running fmt/validate/test (leaving `tests.yml`
   untouched).

## Files touched outside `terraform/`

Only two, both additive: `README.md` (a section pointing at the Terraform implementation)
and `.github/workflows/terraform.yml` (new). No existing Python, Pulumi config, or test
file is modified.
