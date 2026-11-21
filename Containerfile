# ZeroOS image recipe (docs/os/03). Stages:
#   ctx     build-only files, bind-mounted into RUN steps and never part of an image
#   laptop  the desktop image for the laptop (x86_64)
# TODO(OS-28): add a zero-common stage shared by laptop and a twin stage
#   (FROM quay.io/fedora/fedora-bootc), both built for x86_64 and aarch64 (docs/os/11).

FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY cosign.pub /cosign.pub

# Base (OS-01): Aurora-DX nvidia-open, pinned by digest; its kernel is never replaced (OS-02).
# Tracking rule (OS-03, docs/os/02): build from `stable` unless its kernel branch is end-of-life
# and `latest` carries a supported one. `stable` carries 7.2, end-of-life on kernel.org, so this
# follows `latest`. Pinned 2026-11-22: version latest-45.20261121.1, kernel 7.3.4-300.fc45.
# TODO(OS-03): let CI apply the tracking rule (read the `ostree.linux` label, compare with
#   kernel.org) and let Renovate propose digest bumps.
FROM ghcr.io/ublue-os/aurora-dx-nvidia-open:latest@sha256:9070827027618b10de5935833bdec2e59872bde593d3c519bc02668ecee93776 AS laptop

LABEL org.opencontainers.image.title="ZeroOS" \
      org.opencontainers.image.description="Personal bootc image for one laptop, derived from Aurora-DX nvidia-open" \
      org.opencontainers.image.source="https://github.com/nyharena25/zeroos-image" \
      org.opencontainers.image.licenses="Apache-2.0"

# Configuration files, packages, signature policy, telemetry and the firewall default zone,
# in the order of docs/os/03's sketch: see build_files/build.sh.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
