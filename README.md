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

## Switch a machine to the image

From an existing Aurora install, enforcing the signature policy that the image ships:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/nyharena25/zeroos:testing
```
