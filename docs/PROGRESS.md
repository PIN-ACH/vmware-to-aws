# Progress & Decisions — VMware-to-AWS Re-Platform Engine

_Last updated: 2026-10-14. This file is the durable memory of the project — read it first when resuming._

## Product in one line
Discover VMware (ESXi/vCenter) VMs → rebuild them on AWS as Terraform + Ansible (re-platform, not disk replication) → migrate DB data with AWS DMS → validated, repeatable demo.

## Locked decisions
- **Strategy:** Re-platform via Infrastructure-as-Code (not MGN lift-and-shift).
- **Source:** Real ESXi.
- **Target region:** `eu-west-2` (London) — chosen because **AWS Transform** is available there.
- **AWS Transform:** used live, as the discovery + first-pass IaC generator.
- **AWS DMS (Database Migration Service):** used to replicate the actual DB data (fills the re-platform data gap).
- **Portability:** container-first. Pinned Docker toolchain is the default control node; `RUNNER=local` is the fallback.
- **Terraform state:** S3 remote backend with local fallback (`config.yaml: aws.state.backend`).
- **Reference workload:** classic 3-tier Linux app — web01 (nginx), app01 (api), db01 (postgres).
- **Engine language:** Python; outputs Terraform + Ansible; Jinja2 templating.

## Control node / where things run
- Operator runs everything as `make <step>` from repo root, inside the container.
- Confirmed control node path: `/home/pin/vmware-to-aws` (Fedora host), bind-mounted to `/work`.
- Three network paths: (1) control node → vCenter for discovery; (2) control node → AWS API; (3) **AWS VPC → source DB for DMS replication** (distinct from path 1).

## Status
### Done
- Repo scaffold, README.
- Spec contract: `engine/models.py` + `sample-inventory/spec.yaml` (validates: 3 VMs, 3 networks).
- Mapping rules: `engine/mapping.yaml`.
- Portability spine: `Dockerfile` (pinned TF 1.9.8 / govc 0.37.3 / aws-cli 2.15.30 / ansible-core 2.17.4), `requirements.txt`, `Makefile`, `config.yaml`, `.env.example`, `.gitignore`.
- **Part 1 & 2 setup verified inside the container** on the Fedora control node (all pinned tools report correct versions).
- **Terraform landing zone (`terraform/landing-zone/`) — validated in-container**: `terraform init -backend=false`, `fmt -check`, and `validate` all pass. AWS provider v5.100.0 (within `~> 5.60`). `.terraform.lock.hcl` committed for reproducibility.

### Not built yet
- `terraform/landing-zone/` (IN PROGRESS — building now).
- `engine/generate.py`, `discover.py`, `normalize.py`, `dms_migrate.py`, `validate.py`.
- `ansible/` roles (web/app/db), inventory, `site.yml`.
- `templates/` Jinja2 for TF + Ansible.
- DMS Terraform module.
- Demo narrative / sales one-pager in `docs/`.

## Open items to resolve
1. **AWS Transform exact interface** — confirm whether it emits Terraform vs CloudFormation, its API/console workflow, and its **IAM permissions**. Design keeps a clean seam (`spec.yaml`) so the product isn't locked to it. _Recommend researching AWS docs before wiring live._
2. **Source-DB reachability from the AWS VPC** (needed for DMS path 3). If unreachable at demo time, use `config.yaml: dms.source.mode: dump` (staged dump) fallback.

## Bug log
- Dockerfile AWS CLI layer 404'd: wrong URL scheme (`aws-cli-exe` → correct `awscli-exe`) + bad pin (`2.17.0`). Fixed: pinned `2.15.30` + fallback to `latest`. Verified in-container: `aws-cli/2.15.30`.
- `.env` GOTCHA: `docker --env-file` does NOT strip trailing `# comments` — the whole string after `=` becomes the value. Broke `GOVC_INSECURE=1   # comment` (govc saw `"1   # comment"` ≠ `1`, kept TLS verification on → cert error). Fix: no trailing comments on any `.env` value; comments only on their own lines. Applies to passwords/keys too. Fixed in `.env.example`.

## Environment facts (real)
- ESXi host: `sd-wro-esxi-rhos-1.intive.org` (standalone ESXi host client, not vCenter → datacenter is `ha-datacenter`). Cert expired 2025-12-08 → needs `GOVC_INSECURE=1`.
- govc auth = same user/password as the ESXi web panel login.
- 8 VMs present. First migration target: **Migratin_test-new** (Ubuntu, powered on, ~38 GB disk, ~8 GB RAM, hostname `migration-test`).
- Showcase app (parallel track): **Focalboard** (real RHEL 9 app on the host; has Postgres backend → good DMS story). Candidate VM `focalboard-migrate` (RHEL 9, 40 GB).
- Control node repo path: `/home/pin/vmware-to-aws`.

## Build order (next)
1. ~~Terraform landing zone~~ ✅ done & validated
2. ~~`generate.py` (spec → TF workloads + Ansible)~~ ✅ built; produces valid JSON, correct sizing, no nested interpolations. NEEDS `terraform validate` in-container against workloads.tf.json.
3. Ansible roles (web/app/db) ← current
4. DMS module + `dms_migrate.py`
5. `discover.py` / `normalize.py` (+ AWS Transform seam) — target real VM `Migratin_test-new`
6. `validate.py` + docs/demo narrative

## Real target VM (Migratin_test-new) — discovered values
- Guest OS: Ubuntu Linux 64-bit → ubuntu-22.04 AMI mapping; CPU 4 vCPU; Memory 8192MB; poweredOn; IP 10.191.72.10
- Disk: disk-1000-0 = 31,457,280 KB = 30 GB, SCSI/LSI Logic (parser must convert KB→GB)
- NIC: ethernet-0, VMXNET3, port group "VM Network", connected
- Sizing result: 4vCPU/8192MB → t3.xlarge (ladder has no 4/8GB, rounds up)
