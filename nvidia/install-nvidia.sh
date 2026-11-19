#!/bin/bash
# Installs one NVIDIA edition onto the Elavo image. build-nvidia-open.sh
# and build-nvidia-legacy.sh set what the edition expects and run this.
# The steps follow Universal Blue's nvidia-install.sh (ublue-os/akmods,
# build_files/nvidia) and Bazzite's bazzite-nvidia build, without their
# gaming and laptop-switching extras.

set -ouex pipefail

: "${ELAVO_NVIDIA_EDITION:?}" "${ELAVO_NVIDIA_KMOD_REPO:?}" \
  "${ELAVO_NVIDIA_MODULE_TYPE:?}" "${ELAVO_NVIDIA_REPO:?}" \
  "${ELAVO_NVIDIA_LICENSE:?}" "${ELAVO_NVIDIA_BRANCH_MIN:?}"

AKMODS=/akmods-nvidia
arch="$(rpm -E '%{_arch}')"

# The akmods image records which kernel and driver its modules are for.
# shellcheck source=/dev/null
source "${AKMODS}/kmods/nvidia-vars"
test "${KMOD_REPO}" = "${ELAVO_NVIDIA_KMOD_REPO}"
test "${KERNEL_MODULE_TYPE}" = "${ELAVO_NVIDIA_MODULE_TYPE}"

# One kernel in the image, and it must be the one the modules were built
# for. A mismatch means the base image moved to a new kernel and the
# build was given an old KERNEL_VERSION, or Universal Blue has not
# published modules for the new kernel yet.
mapfile -t kvers < <(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n')
test "${#kvers[@]}" -eq 1
kver="${kvers[0]}"
if [[ "${kver}" != "${KERNEL_VERSION}" ]]; then
    echo "Base image kernel ${kver}, NVIDIA modules built for ${KERNEL_VERSION}" >&2
    exit 1
fi

# nouveau's firmware is not used once nouveau is blacklisted, and Bazzite
# removes it because it conflicts with NVIDIA's driver. Nothing requires it;
# linux-firmware only recommends it.
if rpm -q nvidia-gpu-firmware >/dev/null; then
    dnf5 remove -y nvidia-gpu-firmware
fi

# Universal Blue's addons: the negativo17 and nvidia-container-toolkit repo
# files (installed disabled), the container SELinux policy, and the
# nvidia-cdi-refresh ordering drop-in.
dnf5 install -y "${AKMODS}"/ublue-os/ublue-os-nvidia-addons-*.rpm

# The driver and modules come from the akmods image. The repos are enabled
# for this one transaction, for the packages the image does not carry
# (egl-wayland, the VA-API driver, the container toolkit) and the driver's
# dependencies. negativo17's multimedia repo must not win over its nvidia
# repo, so it is off for this transaction (base-main turns it on). 32-bit libraries
# are not installed: Steam and other 32-bit apps on Elavo are Flatpaks,
# which bring NVIDIA's GL runtime themselves.
nvidia_rpms=()
for rpm in "${AKMODS}"/nvidia/*.rpm; do
    case "${rpm}" in
        *."${arch}".rpm | *.noarch.rpm) nvidia_rpms+=("${rpm}") ;;
    esac
done
kmod_rpm="${AKMODS}/kmods/kmod-nvidia-${KERNEL_VERSION}-${NVIDIA_AKMOD_VERSION}.${DIST_ARCH}.rpm"
test -f "${kmod_rpm}"
dnf5 install -y \
    --enablerepo="${ELAVO_NVIDIA_REPO}" \
    --enablerepo=nvidia-container-toolkit \
    --disablerepo='fedora-multimedia*' \
    "${nvidia_rpms[@]}" \
    "${kmod_rpm}" \
    egl-wayland \
    libva-nvidia-driver \
    nvidia-container-toolkit

# The module and the userspace driver must be the same release, and the
# branch must be the one this edition is for.
kmod_version="$(rpm -q --queryformat '%{VERSION}' kmod-nvidia)"
driver_version="$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
if [[ "${kmod_version}" != "${driver_version}" ]]; then
    echo "kmod-nvidia ${kmod_version} does not match nvidia-driver ${driver_version}" >&2
    exit 1
fi
branch="${driver_version%%.*}"
if [[ -n "${ELAVO_NVIDIA_BRANCH:-}" && "${branch}" != "${ELAVO_NVIDIA_BRANCH}" ]]; then
    echo "Expected NVIDIA ${ELAVO_NVIDIA_BRANCH}, got ${driver_version}" >&2
    exit 1
fi
test "${branch}" -ge "${ELAVO_NVIDIA_BRANCH_MIN}"

# Every repo the addons package added stays off in the finished image.
# (fedora-multimedia is base-main's own setting and is left as it was.)
enabled_repos="$(dnf5 repo list --enabled)"
if grep -q -E 'nvidia' <<<"${enabled_repos}"; then
    echo "An NVIDIA repo stayed enabled" >&2
    exit 1
fi

# The modules are built for the image's kernel and signed. The core
# nvidia module's license tells the two kinds apart (MIT/GPL for the open
# modules, NVIDIA for the proprietary ones; nvidia-drm is MIT in both).
depmod -a "${kver}"
for module in nvidia nvidia-drm nvidia-modeset nvidia-uvm; do
    test "$(modinfo -k "${kver}" -F vermagic "${module}" | cut -d' ' -f1)" = "${kver}"
    test -n "$(modinfo -k "${kver}" -F signer "${module}")"
done
test "$(modinfo -k "${kver}" -F license nvidia)" = "${ELAVO_NVIDIA_LICENSE}"
test "$(modinfo -k "${kver}" -F version nvidia)" = "${driver_version}"

# Containers: podman run --device nvidia.com/gpu=all uses the CDI spec
# nvidia-cdi-refresh writes at boot.
semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp
systemctl enable nvidia-cdi-refresh.path nvidia-cdi-refresh.service

# Keep video memory across suspend and hibernate. The driver ships these
# units; enable whichever are present.
for unit in nvidia-suspend.service nvidia-resume.service \
    nvidia-hibernate.service nvidia-suspend-then-hibernate.service; do
    if [[ -f "/usr/lib/systemd/system/${unit}" ]]; then
        systemctl enable "${unit}"
    fi
done

# NVK (Mesa's nouveau Vulkan driver) would be listed next to NVIDIA's
# Vulkan driver; nouveau is not running, so remove its ICD.
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json

# Load the driver from the initramfs so the boot splash and labwc get the
# NVIDIA DRM device without a mode switch. As Universal Blue does, the
# Intel and AMD drivers are loaded first, or Chromium-based browsers lose
# hardware acceleration on laptops with two GPUs. nvidia_peermem is for
# InfiniBand and is left out, as in Bazzite.
dracut_conf=/usr/lib/dracut/dracut.conf.d/99-nvidia.conf
test -f "${dracut_conf}"
sed -i 's@omit_drivers@force_drivers@g' "${dracut_conf}"
sed -i 's@ nvidia @ i915 amdgpu nvidia @g' "${dracut_conf}"
sed -i 's/ nvidia_peermem\b//' "${dracut_conf}"
grep -q 'force_drivers' "${dracut_conf}"

# Kernel arguments and the labwc environment for NVIDIA.
cp -avf /ctx/system_files/. /
test -f /usr/lib/bootc/kargs.d/00-elavo-nvidia.toml

# Say which edition this is, for System Settings and bug reports.
osrel=/usr/lib/os-release
sed -i '/^VARIANT=/d; /^VARIANT_ID=/d' "${osrel}"
case "${ELAVO_NVIDIA_EDITION}" in
    open) variant="NVIDIA" ;;
    legacy) variant="NVIDIA Legacy" ;;
esac
printf 'VARIANT="%s"\nVARIANT_ID=nvidia-%s\n' "${variant}" "${ELAVO_NVIDIA_EDITION}" >> "${osrel}"

# Same initramfs rebuild as build_files/build.sh, now with the NVIDIA
# modules in it.
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "${kver}" --reproducible --add ostree -f \
    "/lib/modules/${kver}/initramfs.img"
chmod 0600 "/lib/modules/${kver}/initramfs.img"
# Listed to a file first: grep -q closing the pipe early fails pipefail.
lsinitrd "/lib/modules/${kver}/initramfs.img" > /tmp/initramfs-contents
grep -q '/nvidia-drm.ko' /tmp/initramfs-contents

dnf5 clean all
