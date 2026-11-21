#!/usr/bin/env bash
# Build steps of the laptop stage (docs/os/03). Runs inside the image build, from the
# Containerfile, with the build context bind-mounted at /ctx. Never run it on a machine.
set -euxo pipefail
umask 022

### Configuration files (docs/os/02, 03, 06) ##########################################
# Preset, kargs, sysctl, modprobe, journald, firewalld zone, registries.d, telemetry.
# Plain `cp -r` (not COPY or `cp -a`) leaves directories that already exist untouched, such
# as /etc/firewalld (0750); new files get 0644 (0755 if executable in git) whatever umask
# the checkout was made with.
cp -rv /ctx/system_files/. /
# Public half of the CI signing key, read by the sigstoreSigned policy (OS-25).
install -D -m 0644 /ctx/cosign.pub /etc/pki/containers/zeroos-cosign.pub

### Packages ZeroOS adds (docs/os/03, 09) ###########################################
# OS-20: rootless Docker. docs/os/06 says Aurora lacks docker-ce-rootless-extras; the base
# pinned on 2026-11-22 already has it (29.10.0), so this is a no-op kept as a guarantee.
# The repository is named explicitly, so this works whether or not the base left it enabled.
dnf -y install --enablerepo=docker-ce-stable docker-ce-rootless-extras
# TODO(09, V-32): further image packages (snapper, pam-u2f, tpm2-tss, ...) once their
#   Fedora 45 names are checked with `dnf info` in this build.
# TODO(02, V-05): scx-scheds and scx_loader; packaging (COPR or release build) is open.
dnf clean all

### Signature policy for the ZeroOS registry (docs/os/03, OS-25) #####################
# Merged in place into the policy in effect, so Universal Blue's own entries stay. Aurora ships
# it at /usr/share/containers/policy.json and has no /etc/containers/policy.json (first CI
# build, 2026-11-21); the script takes the first path that exists.
python3 /ctx/merge-containers-policy.py /ctx/containers-policy-zeroos.json \
    /etc/containers/policy.json /usr/share/containers/policy.json

### Telemetry (docs/os/06, OS-23) #####################################################
# The preset also disables the timer; masking keeps it off even if something enables it.
if [[ -e /usr/lib/systemd/system/rpm-ostree-countme.timer ]]; then
    systemctl mask rpm-ostree-countme.timer
else
    echo "rpm-ostree-countme.timer is not in the base image (answers V-27)"
fi

### Firewall default zone, set offline at build time (docs/os/06, OS-21) ##############
# TODO(V-37): this checks the build half; confirm with `firewall-cmd --get-default-zone`
#   on a booted image that the zone survives the first boot (and FR-29 for IPv6).
firewall-offline-cmd --check-config
firewall-offline-cmd --set-default-zone=zeroos-external
test "$(firewall-offline-cmd --get-default-zone)" = zeroos-external
