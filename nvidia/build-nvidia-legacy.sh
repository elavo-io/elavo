#!/bin/bash
# elavo-nvidia-legacy: Maxwell, Pascal and Volta (GTX 900 and 1000 series,
# Titan V, GTX 750 Ti, GTX 745, and mobile parts such as the MX150/MX250).
# NVIDIA dropped them from the driver after the 580 branch, and the open
# modules never ran on them, so this edition keeps the proprietary
# modules on 580, NVIDIA's long-term branch, from
# ghcr.io/ublue-os/akmods-nvidia-lts.

set -ouex pipefail

export ELAVO_NVIDIA_EDITION=legacy
export ELAVO_NVIDIA_KMOD_REPO=nvidia-lts
export ELAVO_NVIDIA_MODULE_TYPE=kernel
export ELAVO_NVIDIA_REPO=fedora-nvidia-lts
export ELAVO_NVIDIA_LICENSE="NVIDIA"
export ELAVO_NVIDIA_BRANCH=580
export ELAVO_NVIDIA_BRANCH_MIN=580

exec /ctx/install-nvidia.sh
