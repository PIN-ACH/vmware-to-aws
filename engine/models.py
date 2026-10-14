"""
Data model for the intermediate migration spec.

Both normalize.py (writer) and generate.py (reader) use these dataclasses so the
spec.yaml contract is defined in exactly one place. Pure stdlib — no third-party
deps needed just to load/validate a spec.
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any

import yaml


@dataclass
class Disk:
    label: str
    size_gb: int
    type: str = "ssd"


@dataclass
class Nic:
    network: str
    ip: str | None = None


@dataclass
class Network:
    name: str
    vlan: int | None = None
    cidr: str = ""
    zone: str = "private"  # public | private


@dataclass
class VM:
    name: str
    guest_os: str
    cpu: int
    memory_mb: int
    role: str = "app"  # web | app | db
    disks: list[Disk] = field(default_factory=list)
    nics: list[Nic] = field(default_factory=list)
    services: list[str] = field(default_factory=list)
    tags: dict[str, str] = field(default_factory=dict)


@dataclass
class Metadata:
    source: str = "esxi"
    vcenter: str = ""
    discovered_at: str = ""
    project: str = "migration"
    target_region: str = "eu-west-2"


@dataclass
class Spec:
    metadata: Metadata
    networks: list[Network] = field(default_factory=list)
    vms: list[VM] = field(default_factory=list)

    # ---- (de)serialization --------------------------------------------------
    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Spec":
        meta = Metadata(**(data.get("metadata") or {}))
        networks = [Network(**n) for n in data.get("networks", [])]
        vms = []
        for v in data.get("vms", []):
            v = dict(v)
            v["disks"] = [Disk(**d) for d in v.get("disks", [])]
            v["nics"] = [Nic(**n) for n in v.get("nics", [])]
            vms.append(VM(**v))
        return cls(metadata=meta, networks=networks, vms=vms)

    @classmethod
    def load(cls, path: str) -> "Spec":
        with open(path, "r", encoding="utf-8") as fh:
            return cls.from_dict(yaml.safe_load(fh))

    def to_dict(self) -> dict[str, Any]:
        return {
            "metadata": asdict(self.metadata),
            "networks": [asdict(n) for n in self.networks],
            "vms": [asdict(v) for v in self.vms],
        }

    def dump(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as fh:
            yaml.safe_dump(self.to_dict(), fh, sort_keys=False)

    # ---- validation ---------------------------------------------------------
    def validate(self) -> list[str]:
        """Return a list of human-readable problems; empty list means valid."""
        errors: list[str] = []
        net_names = {n.name for n in self.networks}
        if not self.vms:
            errors.append("spec has no VMs")
        for vm in self.vms:
            if vm.cpu <= 0:
                errors.append(f"{vm.name}: cpu must be > 0")
            if vm.memory_mb <= 0:
                errors.append(f"{vm.name}: memory_mb must be > 0")
            if vm.role not in {"web", "app", "db"}:
                errors.append(f"{vm.name}: unknown role '{vm.role}'")
            if not vm.disks:
                errors.append(f"{vm.name}: has no disks")
            for nic in vm.nics:
                if nic.network not in net_names:
                    errors.append(
                        f"{vm.name}: nic references unknown network '{nic.network}'"
                    )
        return errors


if __name__ == "__main__":
    import sys

    path = sys.argv[1] if len(sys.argv) > 1 else "sample-inventory/spec.yaml"
    spec = Spec.load(path)
    problems = spec.validate()
    if problems:
        print("INVALID spec:")
        for p in problems:
            print(f"  - {p}")
        sys.exit(1)
    print(f"OK: {path} — {len(spec.vms)} VMs, {len(spec.networks)} networks")
    for vm in spec.vms:
        print(f"  {vm.name:8} {vm.role:4} {vm.cpu}vCPU/{vm.memory_mb}MB -> {vm.guest_os}")
