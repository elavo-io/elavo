#!/bin/bash
# elavo-nvidia-open: Turing (2018) and newer, GTX 16 series and all RTX.
# NVIDIA's open kernel modules on the current driver branch, from
# ghcr.io/ublue-os/akmods-nvidia-open. Maxwell, Pascal and Volta cannot
# run the open modules; they use elavo-nvidia-legacy.

set -ouex pipefail

export ELAVO_NVIDIA_EDITION=open
# What the akmods image must contain (its kmods/nvidia-vars file).
export ELAVO_NVIDIA_KMOD_REPO=nvidia
export ELAVO_NVIDIA_MODULE_TYPE=open
# negativo17 repo that matches the driver, for the packages that are not
# in the akmods image.
export ELAVO_NVIDIA_REPO=fedora-nvidia
# License of the core nvidia module: MIT/GPL for the open modules.
export ELAVO_NVIDIA_LICENSE="Dual MIT/GPL"
# Turing and newer only need a driver new enough for the open modules.
export ELAVO_NVIDIA_BRANCH=
export ELAVO_NVIDIA_BRANCH_MIN=560

exec /ctx/install-nvidia.sh
