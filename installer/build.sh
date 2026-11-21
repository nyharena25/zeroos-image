#!/usr/bin/env bash
# Build steps of the ZeroOS installer environment (installer/Containerfile, OS-37). Runs inside
# the container build with the repository bind-mounted read-only at /ctx. The Anaconda steps
# follow image-builder's installer examples (doc/20-advanced/20-bootc/10-isos.md).
set -euxo pipefail
umask 022

: "${PAYLOAD_SOURCE:?pass --build-arg PAYLOAD_SOURCE=ghcr.io/nyharena25/zeroos@sha256:...}"
: "${PAYLOAD_TARGET:?pass --build-arg PAYLOAD_TARGET=ghcr.io/nyharena25/zeroos:<tag>}"
if [[ "$PAYLOAD_SOURCE" != *@sha256:* ]]; then
    echo "PAYLOAD_SOURCE must be pinned by digest: $PAYLOAD_SOURCE" >&2
    exit 1
fi

### Installer and ISO tooling ##########################################################
# mokutil queues the MOK enrolment (kickstart %post); NetworkManager-wifi and the firmware
# packages are for the laptop's Wi-Fi (iwlwifi) and Ethernet (r8169), since the payload is
# pulled from the registry during the install.
# TODO(V-39): check that Wi-Fi and Ethernet come up in the installer on the laptop.
dnf -y install \
    anaconda anaconda-install-img-deps anaconda-dracut dracut-config-generic dracut-network \
    net-tools grub2-efi-x64-cdboot plymouth \
    default-fonts-core-sans default-fonts-other-sans google-noto-sans-cjk-fonts \
    xorriso squashfs-tools isomd5sum jq mokutil \
    NetworkManager-wifi iwlwifi-mvm-firmware realtek-firmware
dnf clean all

mkdir -p /boot/efi
cp -ra /usr/lib/efi/*/*/EFI /boot/efi

### ISO boot menu ######################################################################
install -D -m 0644 /ctx/installer/iso.yaml /usr/lib/image-builder/bootc/iso.yaml

### Signature policy: the installer verifies the image it pulls (docs/os/03, OS-25) ##########
install -D -m 0644 /ctx/system_files/etc/containers/registries.d/zeroos.yaml /etc/containers/registries.d/zeroos.yaml
install -D -m 0644 /ctx/cosign.pub /etc/pki/containers/zeroos-cosign.pub
python3 /ctx/build_files/merge-containers-policy.py /ctx/build_files/containers-policy-zeroos.json \
    /etc/containers/policy.json /usr/share/containers/policy.json

### Kickstart: payload only, no storage commands (OS-37; see installer/zeroos.ks.in) ##########
ks=/usr/share/anaconda/interactive-defaults.ks
sed -e "s|@PAYLOAD_SOURCE@|$PAYLOAD_SOURCE|" -e "s|@PAYLOAD_TARGET@|$PAYLOAD_TARGET|" \
    /ctx/installer/zeroos.ks.in > "$ks"
if grep -Eq '^[[:space:]]*(clearpart|zerombr|autopart|ignoredisk|part|partition|reqpart|logvol|volgroup|raid|btrfs)([[:space:]]|$)' "$ks"; then
    echo "$ks contains a storage command; Windows shares the laptop's disk (OS-37)" >&2
    exit 1
fi
ksvalidator "$ks"

### What lorax normally does so that Anaconda runs (upstream example) ######################
echo "install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda" >> /etc/passwd
echo "install::14438:0:99999:7:::" >> /etc/shadow
# Root without a password inside the installer environment only (Anaconda's shell on VT2).
passwd -d root
mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives
# Installer repositories: unused by a bootc payload, kept where Anaconda expects them.
mkdir -p /etc/anaconda.repos.d
for dir in /etc/yum.repos.d /usr/share/dnf5/repos.d; do
    if [[ -d "$dir" ]]; then
        find "$dir" -maxdepth 1 -name '*.repo' -exec mv -t /etc/anaconda.repos.d {} +
    fi
done
ln -sf /usr/lib/systemd/system/anaconda.target /etc/systemd/system/default.target
rm -fv /usr/lib/systemd/system-generators/systemd-gpt-auto-generator
ln -sf /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service
install -D -m 0644 /ctx/installer/logind-anaconda-shell.conf /usr/lib/systemd/logind.conf.d/anaconda-shell.conf
install -D -m 0644 /ctx/installer/pipewire-allowroot.conf /etc/systemd/user/pipewire.service.d/allowroot.conf
install -D -m 0644 /ctx/installer/pipewire-allowroot.conf /etc/systemd/user/pipewire.socket.d/allowroot.conf

### initramfs with Anaconda's dracut module ##############################################
mkdir -p "$(realpath /root)"
kernel=$(kernel-install list --json pretty | jq -r '.[] | select(.has_kernel == true) | .version')
DRACUT_NO_XATTR=1 dracut --force -v --zstd --reproducible --no-hostonly \
    --add anaconda "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"
