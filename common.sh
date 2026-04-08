#!/usr/bin/env bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
#CONF_FILE="${SCRIPT_DIR}"/config.sh
#[[ -f "${CONF_FILE}" ]] && source "${CONF_FILE}"

##### Colors ################
AQUA="\033[38;2;18;254;202m"
BLOOD="\033[38;2;102;6;6m"
BOYSENBERRY="\033[38;2;135;50;96m"
BWHITE="\033[1;37m"
CAMEL="\033[38;2;193;154;107m"
CANARY="\033[38;2;255;255;153m"
CARIBBEAN="\033[38;2;0;204;153m"
CHARTREUSE="\033[38;2;127;255;0m"
COOLGRAY="\033[38;2;140;146;172m"
CORAL="\033[38;2;240;128;128m"
CRIMSON="\033[38;2;220;20;60m"
GOLDENROD="\033[38;2;218;165;32m"
HELIOTROPE="\033[38;2;223;115;255m"
HIGHLIGHTER="\033[38;2;248;255;15m"
HOTPINK="\033[38;2;255;105;180m"
INDIGO="\033[38;2;111;0;255m"
JUNEBUD="\033[38;2;189;218;87m"
LAGOON="\033[38;2;142;235;236m"
LEMON="\033[38;2;255;244;79m"
LTVIOLET="\033[38;2;207;159;255m"
LIME="\033[38;2;204;255;0m"
MAUVE="\033[38;2;224;175;255m"
MINT="\033[38;2;152;255;152m"
MISTYROSE="\033[38;2;255;226;223m"
MOSS="\033[38;2;138;154;91m"
NAVAJO="\033[38;2;255;222;173m"
OCHRE="\033[38;2;204;119;34m"
ORANGE="\033[38;2;255;165;0m"
PEACH="\033[38;2;246;161;146m"
PINK="\033[38;2;255;45;192m"
PURPLE_BLUE="\033[38;2;147;130;255m"
REBECCA="\033[38;2;102;51;153m"
SAND="\033[38;2;194;178;128m"
SEA="\033[38;2;32;178;170m"
SKY="\033[38;2;135;206;250m"
SLATE="\033[38;2;109;129;150m"
TAWNY="\033[38;2;204;78;0m"
TEAL="\033[38;2;0;128;128m"
TOMATO="\033[38;2;255;99;71m"
TURQUOISE="\033[38;2;64;224;208m"
UGLY="\033[38;2;122;115;115m"
VIOLET="\033[38;2;143;0;255m"
NEONPINK="\033[38;2;255;19;240m"
NEONBLUE="\033[38;2;4;218;255m"
NEONRED="\033[38;2;255;49;49m"
NEONGREEN="\033[38;2;57;255;20m"
NC="\033[0m"

##############################################
# normalize ARCH names                       #
# Map various CPU architecture names         #
# to canonical values used by Alpine Linux   #
# x86-64/amd64 → x86_64  (Intel/AMD 64-bit)  #
# i386/i486/i586/i686 → x86  (Intel 32-bit)  #
# arm64/armv8 → aarch64  (ARM 64-bit)        #
# armv7* → armv7  (ARM 32-bit with NEON)     #
# armv6/arm → armhf  (ARM 32-bit hard-float) #
##############################################
ARCH=${ARCH:-$(uname -m)}
case "${ARCH}" in
  x86-64|amd64) ARCH="x86_64" ;;
  i*86)         ARCH="x86" ;;
  arm64|armv8)  ARCH="aarch64" ;;
  armv7*)       ARCH="armv7" ;;
  armv6|arm)    ARCH="armhf" ;;
  *)    echo -e "${MAUVE}= ARCH '${ARCH}' not in normalization map, using as-is${NC}" ;;
esac

########################################################
# setup_arch: resolve QEMU_ARCH & ARCH_FLAGS from ARCH #
########################################################
setup_arch() {
  case "${ARCH}" in
    x86_64)
      QEMU_ARCH=""
      ARCH_FLAGS="${X8664_FLAGS}"
      RUST_TARGET="x86_64-alpine-linux-musl"
      ;;
    x86)
      QEMU_ARCH="i386"
      ARCH_FLAGS="${X86_FLAGS}"
      RUST_TARGET="i586-alpine-linux-musl"
      ;;
    aarch64)
      QEMU_ARCH="aarch64"
      ARCH_FLAGS="${AARCH64_FLAGS}"
      RUST_TARGET="aarch64-alpine-linux-musl"
      ;;
    armv7)
      QEMU_ARCH="arm"
      ARCH_FLAGS="${ARMV7_FLAGS}"
      RUST_TARGET="armv7-unknown-linux-musleabihf"
      ;;
    armhf)
      QEMU_ARCH="arm"
      ARCH_FLAGS="${ARMHF_FLAGS}"
      RUST_TARGET="arm-unknown-linux-musleabihf"
      ;;
    *)
      echo -e "${LAGOON}Unknown architecture: ${HOTPINK}${ARCH}${NC}" >&2
      exit 1
      ;;
  esac
  # ALPINE_TARBALL is the Alpine minirootfs filename (distinct from the build source tarball)
  ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MAJOR_MINOR}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
  ALPINE_TARBALL="${ALPINE_URL##*/}"
}

###############################################################
# unmount_chroot: safely unmount all bind mounts in chroot    #
# Called from the EXIT trap (setup_cleanup) and package_output#
###############################################################
unmount_chroot() {
  local max_attempts=3
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if ! grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts 2>/dev/null; then
      return 0  # Successfully unmounted
    fi

    if command -v findmnt >/dev/null 2>&1; then
      sudo findmnt --list --noheadings --output TARGET | grep -F "$(pwd)/${CHROOTDIR}" | tac | xargs -r sudo umount -nfR 2>/dev/null || true
    else
      grep -F "$(pwd)/${CHROOTDIR}" /proc/mounts | cut -f2 -d" " | sort -r | xargs -r sudo umount -nfR 2>/dev/null || true
    fi

    sleep 2
    (( ++attempt ))
  done

  # Final check
  if grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts; then
    if [ "${GITHUB_ACTIONS:-}" == "true" ] || [ "${CI:-}" == "true" ]; then
      echo -e "${TOMATO}CI Environment detected. Forcing lazy unmount...${NC}"
      grep -F "$(pwd)/${CHROOTDIR}" /proc/mounts | cut -f2 -d" " | sort -r | xargs -r sudo umount -l 2>/dev/null || true
    else
      read -p "DANGER - Do you want to lazy unmount? (y/n): " yn
      case $yn in
        [yY] ) grep -F "$(pwd)/${CHROOTDIR}" /proc/mounts | cut -f2 -d" " | sort -r | xargs -r sudo umount -l 2>/dev/null || true;;
        [nN] ) echo -e "${TOMATO}ERROR: Failed to unmount all filesystems in ${CHROOTDIR} after ${max_attempts} attempts${NC}" >&2; exit;;
        * ) echo "Invalid response"; exit 1;;
      esac
    fi
  fi
}

###############################################################
# setup_cleanup: register unmount trap for chroot bind mounts #
###############################################################
setup_cleanup() {
  #trap unmount_chroot EXIT INT TERM
  trap unmount_chroot EXIT
}

#####################################################################
# install_host_deps: install required packages on the Ubuntu runner #
#####################################################################
install_host_deps() {
  echo -e "${SEA}= install dependencies${NC}"
  local DEBIAN_DEPS=(binutils coreutils patch sed curl jq)
  [ -n "${QEMU_ARCH}" ] && DEBIAN_DEPS+=(qemu-user-static)
  sudo flock /var/lib/apt/lists/lock -c "apt-get update -qq"
  sudo apt-get install -qy --no-install-recommends "${DEBIAN_DEPS[@]}"
}

#####################################################
# setup_alpine_chroot TARBALL                       #
# Downloads Alpine rootfs, extracts it, and copies  #
# resolv.conf + source tarball inside.              #
#####################################################
setup_alpine_chroot() {
  local PREBAKED_IMAGE="alpine-base-${ARCH}.tar.zst"
  local tarball="$1"
  if [ -d "./${CHROOTDIR}" ] && [ "${KEEP_CHROOT}" = "false" ]; then
    unmount_chroot
    if grep -qF "$(pwd)/${CHROOTDIR}" /proc/mounts; then
      echo -e "${TOMATO}ERROR: Mounts still active in ${CHROOTDIR}. Deletion ${BLOOD}BLOCKED!${NC}" >&2
      exit 1
    fi
    echo -e "${GOLDENROD}= chroot dir exist! Removing it now.${NC}"
    sudo rm -fr "./${CHROOTDIR}"
  fi
  if [ -f "minirootfs/${PREBAKED_IMAGE}" ]; then
      age=$(( $(date +%s) - $(stat -c %Y "minirootfs/${PREBAKED_IMAGE}") ))
      if (( age > 2592000 )); then  # 30 days
        echo -e "${LEMON}= WARNING: prebaked image is >30 days old, consider rebuilding${NC}"
      fi
      echo -e "${CARIBBEAN}= Found pre-baked image: ${PREBAKED_IMAGE}. Extracting...${NC}"
      mkdir -p "./${CHROOTDIR}"
      tar -xf minirootfs/"${PREBAKED_IMAGE}" -C "./${CHROOTDIR}"
  else
      echo -e "${CORAL}= No pre-baked image found. Downloading official Alpine...${NC}"
      if [ ! -d minirootfs/ ]; then
        echo -e "${INDIGO}minirootfs dir does not exist. Creating it now.${NC}"
        mkdir -p minirootfs/
      fi
      if [ -f minirootfs/"${ALPINE_TARBALL}" ] && [ -f minirootfs/"${ALPINE_TARBALL}.sha256" ]; then
        echo -e "${SLATE}= Alpine rootfs ${ALPINE_TARBALL} already cached, verifying checksum...${NC}"
        if ! ( cd minirootfs && sha256sum -c "${ALPINE_TARBALL}.sha256" --status ); then
          echo -e "${CRIMSON}= ERROR: Cached Alpine rootfs failed checksum verification: minirootfs/${ALPINE_TARBALL}${NC}" >&2
          exit 1
        fi
      else
        echo -e "${CANARY}= download alpine rootfs and checksum${NC}"
        curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
          -o minirootfs/"${ALPINE_TARBALL}" "${ALPINE_URL}" \
          || { echo -e "${CRIMSON}= ERROR: failed to download Alpine rootfs${NC}" >&2; exit 1; }
        curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
          -o minirootfs/"${ALPINE_TARBALL}.sha256" "${ALPINE_URL}.sha256" \
          || { echo -e "${CRIMSON}= ERROR: failed to download Alpine rootfs checksum${NC}" >&2; exit 1; }
        if ! ( cd minirootfs && sha256sum -c "${ALPINE_TARBALL}.sha256" --status ); then
          echo -e "${CRIMSON}= ERROR: Downloaded Alpine rootfs failed checksum verification${NC}" >&2
          exit 1
        fi
      fi
    echo -e "${SKY}= extract rootfs${NC}"
    mkdir -p "${CHROOTDIR}"
    tar xf minirootfs/"${ALPINE_TARBALL}" -C "${CHROOTDIR}"/
  fi
  echo -e "${HELIOTROPE}= copy resolv.conf into chroot${NC}"
  cp /etc/resolv.conf "./${CHROOTDIR}/etc/" || \
    echo -e "${TAWNY}= WARNING: failed to copy resolv.conf — DNS may not work inside chroot${NC}"
  if [ "${tarball}" != "base-setup" ]; then
    echo -e "${PEACH}= copying ${tarball} into chroot${NC}"
    cp distfiles/"${tarball}" "./${CHROOTDIR}/${tarball}"
  fi
  # bundled tools
  echo -e "${SAND}= install prebuilt tools${NC}"
  local src
  for prebuilt in 7zz upx uasm curl jq mold; do
    src="tools/${prebuilt}/${prebuilt}-${ARCH}"
    if [[ ! -f "$src" ]]; then
      echo -e "${CRIMSON}= ERROR: ${src} not found${NC}" >&2
      exit 1
    fi
    cp "$src" "./${CHROOTDIR}/usr/local/bin/${prebuilt}"
  done
}

############################################################
# setup_qemu: copy qemu into chroot for cross-arch builds  #
# Validates QEMU binary exists before copying.             #
############################################################
setup_qemu() {
  if [ -n "${QEMU_ARCH}" ]; then
    echo -e "${TURQUOISE}= setup QEMU for cross-arch builds${NC}"
    local qemu_bin
    if qemu_bin=$(command -v "qemu-${QEMU_ARCH}-static" 2>/dev/null); then
      echo -e "${SKY}= Found static QEMU: ${qemu_bin}${NC}"
      sudo mkdir -p "./${CHROOTDIR}/usr/bin/"
      sudo cp "${qemu_bin}" "./${CHROOTDIR}/usr/bin/"
    elif qemu_bin=$(command -v "qemu-${QEMU_ARCH}" 2>/dev/null); then
      echo -e "${CAMEL}= Found QEMU: ${qemu_bin} (copying as static)${NC}"
      sudo mkdir -p "./${CHROOTDIR}/usr/bin/"
      sudo cp "${qemu_bin}" "./${CHROOTDIR}/usr/bin/qemu-${QEMU_ARCH}-static"
    else
      echo -e "${CRIMSON}= ERROR: No QEMU binary found for ${QEMU_ARCH}${NC}" >&2
      echo -e "${PEACH}  Architecture: ${QEMU_ARCH}${NC}" >&2
      echo -e "${NAVAJO}  Current PATH: $PATH${NC}" >&2
      echo -e "${HELIOTROPE}= Install it with:${NC} ${TEAL}sudo apt-get install qemu-user-static or qemu-user-binfmt${NC}" >&2
      exit 1
    fi
  fi
}

##########################################################
# mount_chroot: bind-mount proc/dev/sys into the chroot  #
# Validates CCACHE_DIR exists before mounting.           #
##########################################################
mount_chroot() {
  echo -e "${VIOLET}= mount, bind and chroot into dir${NC}"
  sudo mount --rbind /dev "./${CHROOTDIR}/dev/"
  sudo mount --make-rslave "./${CHROOTDIR}/dev/"
  sudo mount --rbind /sys "./${CHROOTDIR}/sys/"
  sudo mount --make-rslave "./${CHROOTDIR}/sys/"
  sudo mount -t proc none "./${CHROOTDIR}/proc/"
  sudo mount -o bind /tmp "./${CHROOTDIR}/tmp/"
  sudo mount -t tmpfs -o nosuid,nodev,noexec,mode=755 none "./${CHROOTDIR}/run"
  # Mount ccache directories if CCACHE_DIR is set
  if [ -n "${CCACHE_DIR:-}" ]; then
    if [ ! -d "${CCACHE_DIR}" ]; then
      echo -e "${CRIMSON}= ERROR: CCACHE_DIR is set but directory does not exist: ${CCACHE_DIR}${NC}" >&2
      exit 1
    fi
    echo -e "${JUNEBUD}= bind mounting ccache directories${NC}"
    sudo mkdir -p "./${CHROOTDIR}/${CCACHE_CHROOT_DIR}"
    sudo mount --bind "${CCACHE_DIR}" "./${CHROOTDIR}/${CCACHE_CHROOT_DIR}"
    sudo mount --make-slave "./${CHROOTDIR}/${CCACHE_CHROOT_DIR}"
    sudo mkdir -p "./${CHROOTDIR}/${CCACHE_LOG_DIR}"
  fi
  if [ -n "${CROSS_COMPILE_HOST_PATH:-}" ]; then
    mkdir -p "${CHROOTDIR}/opt/cross"
    mountpoint -q "${CHROOTDIR}/opt/cross" || mount --bind --make-slave "$CROSS_COMPILE_HOST_PATH" "${CHROOTDIR}/opt/cross"
    # Inject the compiler paths into the chroot's environment
    export CC="/opt/cross/bin/${CROSS_PREFIX}gcc"
    export AR="/opt/cross/bin/${CROSS_PREFIX}ar"
    export STRIP="/opt/cross/bin/${CROSS_PREFIX}strip"
    export PATH="/opt/cross/bin:${PATH}"
  fi
}

run_build_setup() {
  local tool="$1" version="$2" tarball="$3"
  shift 3
  [[ $# -gt 0 && "$1" == "--" ]] && shift
  local mirrors=("$@")
  if [[ ${#mirrors[@]} -gt 0 ]]; then
      mapfile -t mirrors < <(get_fastest_mirrors "${mirrors[@]}")
      echo -e "${CANARY}= Fastest mirror: ${PEACH}${mirrors[0]}${NC}"
  fi
  setup_arch
  setup_cleanup
  install_host_deps
  setup_alpine_chroot "${tarball}"
  setup_qemu
  mount_chroot
}

