# Findings

Issues encountered hardening RHEL 10 to the DISA STIG. Each is reproducible and
none are visible to a compliance scan.

## 1. Account lockout passes validation and does not function

`pam_faillock` is configured correctly and records zero failed authentication
attempts.

**Verified:**

- `pam_faillock.so` present in `preauth`, `authfail`, and `account` in both
  `/etc/pam.d/system-auth` and `/etc/pam.d/password-auth`
- `with-faillock` enabled in the authselect `custom/hardening` profile
- `authselect check` reports the configuration valid
- Settings applied through `/etc/security/faillock.conf`, not direct PAM edits
- SELinux context on `/var/log/faillock` corrected to `faillog_t`
- Directory permissions stock `755 root:root`

**Observed:** zero entries from `faillock --user <name>` after deliberate
failures via SSH, `su`, and `sudo`. The counter file's mtime updates on every
authentication but the file stays 0 bytes. `pam_lastlog` independently reports
the same failures, confirming they occurred.

**Suspected cause:** authselect places `pam_faillock.so authfail` after
`pam_sss.so` in the stack. On an AD-joined host, the `pam_usertype.so isregular`
branch (`default=1`) can skip it on local-account failures.

A SCAP scan passes this host. The control does not work.

## 2. SELinux context on the faillock directory is not persistent

Remediation creates `/var/log/faillock` with the correct `faillog_t` context,
but SELinux policy has no mapping for that path. Files written into it
afterward inherit `var_log_t`, and `sshd_session_t` is denied write access.

A plain `restorecon` makes this worse — with no policy mapping, it relabels the
directory *down* to `var_log_t`. The fix requires adding the mapping first:

```bash
semanage fcontext -a -t faillog_t "/var/log/faillock(/.*)?"
restorecon -Rv /var/log/faillock
```

## 3. fapolicyd blocks all non-RPM software

`fapolicyd` builds its trust database from the RPM database, so anything
installed outside RPM is denied execution. This surfaced four separate times:

| Tool | Failure |
|---|---|
| `pip install pywinrm` | `ImportError` then `PermissionError` on the module file |
| Ansible Galaxy collections | `EPERM` reading `ansible/posix/plugins/modules/sysctl.py` |
| Ansible module staging | `EPERM` transferring `AnsiballZ_setup.py` |
| `git init` | `EPERM` copying template hooks |

Every one returns `EPERM` with **no SELinux AVC**, which misdirects diagnosis
toward SELinux or file permissions.

```bash
fapolicyd-cli --file add /path/to/trust
fapolicyd-cli --update
```

Practical consequence: configuration management tooling on a hardened host must
be RPM-packaged or explicitly trusted, and that trust management belongs in the
baseline design rather than being discovered when something breaks.

## 4. FIPS mode breaks ed25519 SSH keys

STIG remediation enables the FIPS crypto policy. ed25519 is not FIPS-approved,
so SSH loads such keys and silently declines to offer them:


The failure presents as `Permission denied (publickey)` with no indication that
the key was rejected locally rather than by the server. RSA-4096 works.

The same policy change rotates the host's SSH host keys, invalidating every
client's `known_hosts` entry and producing a man-in-the-middle warning.

At fleet scale this means every workstation, CI runner, and Git integration
using ed25519 stops working the day the policy is applied.

## 5. PowerSTIG Server 2025 content defects

`PowerSTIG 4.30.0`, `WindowsServer 2025 DC v1.1`. The configuration compiles to
a 313 KB MOF but `Test-DscConfiguration` cannot complete.

- **V-278193.c** emits a `CertificateImport` resource with null `Path` and
  `Thumbprint`, and is unreachable by both `SkipRuleType` and `SkipRule`.
  Sibling rules `.a` and `.b` skip correctly.
- Patching the MOF directly clears that, after which **V-278138**
  (`NTFSAccessEntry`) throws on a null ACE during test.

Conclusion: the 2025 content is not production-ready. An assessment would fall
back to the 2022 benchmark or DISA GPO packages.

**Operational note:** DSC's Local Configuration Manager defaults to
`ApplyAndMonitor`, which can enact a staged configuration on its own
consistency-check schedule. On a domain controller that risks cutting WinRM and
RDP unattended. Set `ApplyOnly` before staging anything.

## 6. Account lockout silently fails on AD-joined hosts

`pam_faillock` configured identically via Ansible on two RHEL 10 hosts:
an AD-joined VM using the authselect `custom/hardening` profile, and a
standalone EC2 instance using the `local` profile. Identical SSG content
(0.1.82-2), identical `/etc/security/faillock.conf`, both passing SCAP
validation.

On the standalone host, failed `su` attempts are recorded correctly. On the
AD-joined host, zero failures are recorded across SSH, `su`, and `sudo`,
verified against independent `pam_lastlog` counters.

The distinguishing factor is PAM stack composition. The `local` profile places
`pam_faillock.so authfail` with no intervening modules. The domain-joined stack
places it after `pam_sss.so forward_pass` and behind a `pam_usertype.so
isregular` branch (`default=1`), which can skip the `authfail` line on
local-account failures.

**Impact:** a DoD environment running AD-joined RHEL — the standard
configuration — may have a non-functional lockout control that passes every
compliance scan.
