# VMware-to-AWS Re-Platform Engine

A productized migration tool that **re-platforms VMware (ESXi/vCenter) virtual machines
to AWS as Infrastructure-as-Code**. Instead of block-level disk replication, it
discovers your VMware estate, extracts each VM's configuration, and **generates
Terraform + Ansible** to rebuild those workloads on AWS — reproducibly, as code.

> Point it at your vCenter/ESXi → it discovers your VMs → it emits Terraform
> (infrastructure) + Ansible (configuration) → `terraform apply` → validated AWS workloads.

## Why re-platform (vs lift-and-shift)?

| | Lift-and-shift (MGN) | Re-platform as IaC (this tool) |
|---|---|---|
| Moves the disk | Yes (block replication) | No — rebuilds from config |
| Output | EC2 instances | EC2 **+ reusable Terraform/Ansible** |
| Modernization | Minimal | Native AWS, codified, repeatable |
| Drift / DR | Manual | Re-deployable from code anytime |
| Customer value | "We moved your VMs" | "We turned your estate into code you own" |

## Pipeline

```
ESXi/vCenter ─► Discover ─► Normalize ─► Map ─► Generate ─► Deploy ─► Configure ─► Validate
  (govc/API)    (inventory)  (spec.yaml)  (rules) (TF+Ansible) (terraform) (ansible)  (report)
```

## Repo layout

```
vmware-to-aws/
├── engine/            # the product: discovery + codegen
│   ├── discover.py    # vSphere/govc → raw inventory (with cache)
│   ├── normalize.py   # raw inventory → spec.yaml (intermediate spec)
│   ├── generate.py    # spec.yaml → terraform/ + ansible/
│   ├── mapping.yaml   # vSphere → AWS sizing & network rules
│   └── models.py      # spec data model (dataclasses)
├── templates/         # Jinja2 templates for generated code
├── terraform/
│   ├── landing-zone/  # base: VPC, subnets, SGs, IAM (hand-written)
│   └── workloads/     # generated per-VM EC2 definitions
├── ansible/           # generated playbooks + reusable roles
├── scripts/           # bootstrap, demo-up, demo-down
├── sample-inventory/  # cached discovery for reliable demos
└── docs/              # architecture, demo script, sales one-pager
```

## Quick start

```bash
# 1. Install tooling (terraform, ansible, aws cli, govc)
./scripts/bootstrap.sh

# 2. Run the full demo (uses cached sample inventory by default)
./scripts/demo-up.sh

# 3. Tear it all down for a clean rerun
./scripts/demo-down.sh
```

Target region: **eu-west-2** (London — required for AWS Transform availability).

## Status

Scaffold in progress. See `docs/ROADMAP.md` for build order.
