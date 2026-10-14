"""
generate.py — turn an intermediate spec (spec.yaml) + mapping rules
(mapping.yaml) into deployable artifacts:

  1. terraform/workloads/workloads.tf.json  — one EC2 instance (+ extra EBS
     volumes) per VM, wired to the landing-zone outputs via remote state.
  2. ansible/inventory.ini                   — hosts grouped by role (web/app/db).

Terraform is emitted as .tf.json (native Terraform JSON syntax) so we can build
it from Python without a templating engine — easy to diff, validate, and apply.

The generator is pure and offline: it reads files and writes files, touching no
cloud. Sizing is deterministic from mapping.yaml.

Usage:
    python3 engine/generate.py --config config.yaml --spec sample-inventory/spec.yaml
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import yaml

# Import the shared spec model (engine/ is on the path when run from repo root).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from models import Spec, VM  # noqa: E402


# ─────────────────────────────────────────────────────────────────────────────
# Mapping helpers
# ─────────────────────────────────────────────────────────────────────────────
def load_mapping(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def pick_instance_type(vm: VM, mapping: dict) -> str:
    """Smallest instance type satisfying BOTH cpu and memory. Raises if none fits."""
    candidates = mapping["instance_types"]
    for cand in candidates:  # list is authored smallest -> largest
        if cand["vcpu"] >= vm.cpu and cand["memory_mb"] >= vm.memory_mb:
            return cand["type"]
    raise ValueError(
        f"{vm.name}: no instance type in mapping.yaml fits "
        f"{vm.cpu}vCPU/{vm.memory_mb}MB — add a larger type."
    )


def ebs_type(disk_type: str, mapping: dict) -> str:
    dt = mapping.get("disk_types", {})
    return dt.get(disk_type, dt.get("default", "gp3"))


def ami_ssm_param(guest_os: str, mapping: dict) -> str:
    params = mapping.get("ami_ssm_parameters", {})
    if guest_os not in params:
        raise ValueError(
            f"guest_os '{guest_os}' has no AMI SSM parameter in mapping.yaml"
        )
    return params[guest_os]


# ─────────────────────────────────────────────────────────────────────────────
# Terraform generation (.tf.json)
# ─────────────────────────────────────────────────────────────────────────────
def generate_terraform(spec: Spec, mapping: dict, config: dict) -> dict:
    """Build a Terraform JSON doc for the workloads."""
    region = mapping.get("region", config.get("aws", {}).get("region", "eu-west-2"))
    default_tags = mapping.get("default_tags", {})

    tf: dict = {
        "terraform": {
            "required_providers": {
                "aws": {"source": "hashicorp/aws", "version": "~> 5.60"}
            }
        },
        "provider": {"aws": {"region": region}},
        # Read landing-zone outputs (vpc, subnets, SGs, instance profile).
        "data": {
            "terraform_remote_state": {
                "landing": {
                    "backend": "local",
                    "config": {
                        "path": "../landing-zone/terraform.tfstate"
                    },
                }
            },
            # Resolve AMIs from SSM public parameters — no hardcoded AMI IDs.
            "aws_ssm_parameter": {},
        },
        "resource": {"aws_instance": {}, "aws_ebs_volume": {}, "aws_volume_attachment": {}},
    }

    lz = "data.terraform_remote_state.landing.outputs"
    seen_os: set[str] = set()

    for vm in spec.vms:
        itype = pick_instance_type(vm, mapping)
        os_key = vm.guest_os.replace(".", "_").replace("-", "_")

        # One SSM param lookup per distinct OS.
        if vm.guest_os not in seen_os:
            tf["data"]["aws_ssm_parameter"][f"ami_{os_key}"] = {
                "name": ami_ssm_param(vm.guest_os, mapping)
            }
            seen_os.add(vm.guest_os)

        # Subnet selection: a VM's role maps to a subnet of the same name in the
        # landing zone (web→public web subnet; app/db→private subnets). A single
        # ${...} wraps the whole expression — no nested interpolations.
        subnet_expr = (
            f'${{try({lz}.public_subnet_ids["{vm.role}"], '
            f'{lz}.private_subnet_ids["{vm.role}"])}}'
        )

        tags = {**default_tags, **vm.tags, "Name": vm.name, "SourceVM": vm.name}

        root_disk = next((d for d in vm.disks if d.label == "root"), vm.disks[0])

        tf["resource"]["aws_instance"][vm.name] = {
            "ami": f"${{data.aws_ssm_parameter.ami_{os_key}.value}}",
            "instance_type": itype,
            "subnet_id": subnet_expr,
            "vpc_security_group_ids": [f'${{{lz}.security_group_ids["{vm.role}"]}}'],
            "iam_instance_profile": f"${{{lz}.ec2_instance_profile}}",
            "root_block_device": {
                "volume_size": root_disk.size_gb,
                "volume_type": ebs_type(root_disk.type, mapping),
            },
            "tags": tags,
        }

        # Extra (non-root) disks → separate EBS volumes + attachments.
        for i, disk in enumerate([d for d in vm.disks if d is not root_disk]):
            vol_name = f"{vm.name}_{disk.label}"
            tf["resource"]["aws_ebs_volume"][vol_name] = {
                "availability_zone": f"${{aws_instance.{vm.name}.availability_zone}}",
                "size": disk.size_gb,
                "type": ebs_type(disk.type, mapping),
                "tags": {**default_tags, "Name": vol_name},
            }
            tf["resource"]["aws_volume_attachment"][vol_name] = {
                "device_name": f"/dev/sd{chr(ord('f') + i)}",
                "volume_id": f"${{aws_ebs_volume.{vol_name}.id}}",
                "instance_id": f"${{aws_instance.{vm.name}.id}}",
            }

    # Prune empty resource blocks (Terraform rejects empty maps in some cases).
    tf["resource"] = {k: v for k, v in tf["resource"].items() if v}
    return tf


# ─────────────────────────────────────────────────────────────────────────────
# Ansible inventory
# ─────────────────────────────────────────────────────────────────────────────
def generate_ansible_inventory(spec: Spec) -> str:
    groups: dict[str, list[str]] = {}
    for vm in spec.vms:
        groups.setdefault(vm.role, []).append(vm.name)

    lines = ["# Generated by engine/generate.py — do not edit by hand.", ""]
    for role, names in groups.items():
        lines.append(f"[{role}]")
        for name in names:
            # ansible_host is filled from terraform output after deploy; the
            # placeholder keeps the file valid until then.
            lines.append(f"{name} ansible_host=TBD_AFTER_DEPLOY")
        lines.append("")
    lines.append("[all:vars]")
    lines.append("ansible_user=ubuntu")
    lines.append("ansible_python_interpreter=/usr/bin/python3")
    lines.append("")
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
def main() -> int:
    ap = argparse.ArgumentParser(description="Generate Terraform + Ansible from a spec.")
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--spec", default="sample-inventory/spec.yaml")
    ap.add_argument("--mapping", default="engine/mapping.yaml")
    ap.add_argument("--tf-out", default="terraform/workloads/workloads.tf.json")
    ap.add_argument("--inv-out", default="ansible/inventory.ini")
    args = ap.parse_args()

    with open(args.config, "r", encoding="utf-8") as fh:
        config = yaml.safe_load(fh)
    mapping = load_mapping(args.mapping)
    spec = Spec.load(args.spec)

    problems = spec.validate()
    if problems:
        print("Refusing to generate — spec is invalid:")
        for p in problems:
            print(f"  - {p}")
        return 1

    tf = generate_terraform(spec, mapping, config)
    inv = generate_ansible_inventory(spec)

    os.makedirs(os.path.dirname(args.tf_out), exist_ok=True)
    os.makedirs(os.path.dirname(args.inv_out), exist_ok=True)
    with open(args.tf_out, "w", encoding="utf-8") as fh:
        json.dump(tf, fh, indent=2)
        fh.write("\n")
    with open(args.inv_out, "w", encoding="utf-8") as fh:
        fh.write(inv)

    print(f"Generated:")
    print(f"  {args.tf_out}")
    print(f"  {args.inv_out}")
    print(f"Workloads ({len(spec.vms)}):")
    for vm in spec.vms:
        print(f"  {vm.name:20} {vm.role:4} -> {pick_instance_type(vm, mapping)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
