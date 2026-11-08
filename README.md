# govcloud-lab

DISA STIG hardening and compliance automation for a hybrid Windows/Linux
environment, built as hand-written Ansible roles.

The target is the configuration defense contractors actually run: RHEL hosts
joined to an Active Directory domain, hardened to the DISA STIG, with
compliance validated by OpenSCAP.

## Environment

| Host | Role |
|---|---|
| DC01 | Windows Server 2025 — Active Directory Domain Services, DNS |
| rhel10 | RHEL 10 — domain-joined via realmd/SSSD, STIG-hardened |

Both run under VMware Workstation on an isolated network. RHEL serves as the
Ansible control node and manages the Windows host over WinRM.

## Results

Baseline scan against the DISA STIG profile for RHEL 10, before any remediation:

**47.59%** — 170 passed, 267 failed (13 high, 234 medium, 16 low)

After automated remediation generated from the scan results:

**93.68%** — 3,148 tasks, 378 changes, zero failures

The remaining gap is not a shortfall. Filesystem separation, FIPS mode, and
several other controls cannot be satisfied on a running system; they are
install-time or image-build decisions. That constraint is the reason golden
AMIs exist, and documenting it is part of the work.

## Roles

Generated SCAP remediation produces a working but unmaintainable artifact —
over 50,000 lines of YAML performing regex surgery on config files. These
roles reimplement the controls by hand, parameterized and readable.

| Role | Controls | Approach |
|---|---|---|
| `ssh_hardening` | 17 | Single templated drop-in under `/etc/ssh/sshd_config.d/`, validated with `sshd -t` before install |
| `kernel_params` | 28 | Dictionary-driven `sysctl` applied to both the running kernel and `/etc/sysctl.d/` |
| `pam_auth` | 33 | Configures the files authselect *reads* — never edits `/etc/pam.d/*` directly, since authselect regenerates those |

Each role is applied and then verified against the scanner on a per-rule basis,
rather than assumed correct because the file looks right.

```bash
ansible-playbook site.yml --check --diff -K   # preview
ansible-playbook site.yml --diff -K           # apply
```

## Findings

Hardening a system and verifying the controls actually function are different
activities. Four defects surfaced that a compliance scan does not catch —
including an account lockout control that passes validation and records
nothing.

See [docs/findings.md](docs/findings.md).
