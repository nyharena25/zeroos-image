# zeroos-image

The build recipe for **ZeroOS**, a personal bootc operating system image for one laptop
(Gigabyte G6 KF: Intel i7-13620H, NVIDIA RTX 4060). It derives from Universal Blue's
[Aurora-DX nvidia-open](https://github.com/ublue-os/aurora) (Fedora 45, KDE Plasma) and adds
a small set of hardening and configuration files. CI builds and signs the image.

- Image: `ghcr.io/nyharena25/zeroos` (tag `testing`, built daily; a smoke-tested `stable` tag comes later)
- Base: `ghcr.io/ublue-os/aurora-dx-nvidia-open`, pinned by digest in the `Containerfile`
- Licence: [Apache-2.0](LICENSE)

The design (decisions OS-01 to OS-34, measurements, acceptance tests) lives in a private
documentation repository. This repository holds only what is needed to build the image, and it
never contains secrets.

## Build locally

Building pulls the base image, about 5.2 GiB compressed.

```bash
podman build --target laptop -t localhost/zeroos:dev .
```

## Verify a published image

```bash
cosign verify --key cosign.pub ghcr.io/nyharena25/zeroos:testing
```

CI checks the base image the same way, with Universal Blue's public key in `keys/ublue-os.pub`.

## Install the laptop

The laptop is installed from the **installer ISO** built by CI (decision OS-37). Moving an
existing installation (Aurora, Ubuntu, ...) to ZeroOS with `bootc switch` is **not supported**:
that machine keeps its `/etc/machine-id`, so systemd never applies the image's preset file and
rootful `docker.socket` and Aurora's update timer stay enabled.

**Before the laptop:** acceptance test V-39 must pass on a VM with a Windows-like partition
table: Windows' partitions unchanged, the layout below created, and
`systemctl is-enabled docker.socket` reporting `disabled` after the first boot.

### Where the ISO comes from

The `installer` job of the build workflow runs after the image is pushed and signed from `main`
(each push and each manual run, not pull requests or the daily build). It verifies the image
signature, builds an interactive Anaconda environment (`installer/Containerfile`, Fedora 45),
and turns it into an ISO with image-builder's `generic-iso` type. The ISO and its `.sha256` are
**Actions artifacts kept for 14 days**. They are not attached to releases, whose assets are
capped at 2 GiB per file. Download the files of a run, then check the ISO:

```bash
gh run download <run-id> -R nyharena25/zeroos-image
```

```bash
sha256sum -c zeroos-installer-*.iso.sha256
```

The ISO stays small because it does not embed the image: the installer pulls the signed image
from GHCR during the install (Ethernet or Wi-Fi needed). Its signature policy refuses an image
that is not signed with this repository's key.

### Partitioning beside Windows

The installer never partitions on its own: its kickstart names only the image to install, so
Anaconda stops at **Installation Destination**. Choose custom partitioning, then:

- leave `nvme0n1p1` to `nvme0n1p4` (Windows' EFI partition, Microsoft reserved, Windows,
  Windows recovery) exactly as they are, and do not format Windows' EFI partition;
- delete Ubuntu's `nvme0n1p5` and `nvme0n1p6`;
- in that free space, create a new 1 GiB EFI System Partition mounted at `/boot/efi`, a 1 GiB
  ext4 `/boot`, and the rest as Btrfs on LUKS2 (encrypted) for `/`.

After the install, the first reboot opens shim's MokManager: choose **Enroll MOK** and type the
password `universalblue` (Universal Blue's published enrolment password, not a secret) so that
the signed kernel modules load under Secure Boot.

Fallback if the installer cannot make this layout: `bootc install to-filesystem` from a live USB
onto partitions made beforehand (also covered by V-39).

### Build the installer locally

This pulls Fedora 45 bootc and the image-builder container (a few GiB):

```bash
sudo podman build -f installer/Containerfile --build-arg PAYLOAD_SOURCE=ghcr.io/nyharena25/zeroos@sha256:<digest> -t localhost/zeroos-installer .
```

```bash
sudo podman run --rm --privileged -v ./output:/output -v /var/lib/containers/storage:/var/lib/containers/storage ghcr.io/osbuild/image-builder-cli:v91.0.0 build --output-dir /output --bootc-ref localhost/zeroos-installer --bootc-default-fs ext4 generic-iso
```
