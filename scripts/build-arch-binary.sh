#!/usr/bin/env bash
set -euo pipefail

SNAPSHOT_DATE=${SNAPSHOT_DATE:-2017/02/01}
VERSION=${VERSION:-0.11.2_frank.1}
ASSET_NAME=${ASSET_NAME:-frank-geary-${VERSION}-x86_64.tar.zst}
ARCH=${ARCH:-x86_64}

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s WORKDIR\n' "$0" >&2
  exit 2
fi

WORKDIR=$(realpath "$1")
ROOTFS=${WORKDIR}/rootfs
SRC_COPY=${ROOTFS}/build/frank-geary-src
STAGING=${ROOTFS}/pkgroot
PACMAN_CONF=${WORKDIR}/pacman-ala.conf
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
GIT_COMMIT=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || printf 'unknown')

run_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

mkdir -p "${WORKDIR}" "${ROOTFS}/var/lib/pacman" "${ROOTFS}/var/cache/pacman/pkg" "${ROOTFS}/build"

cat >"${PACMAN_CONF}" <<EOF
[options]
Architecture = ${ARCH}
SigLevel = Never
LocalFileSigLevel = Never
ParallelDownloads = 5

[core]
Server = https://archive.archlinux.org/repos/${SNAPSHOT_DATE}/\$repo/os/\$arch

[extra]
Server = https://archive.archlinux.org/repos/${SNAPSHOT_DATE}/\$repo/os/\$arch

[community]
Server = https://archive.archlinux.org/repos/${SNAPSHOT_DATE}/\$repo/os/\$arch
EOF

PACKAGES=(
  bash coreutils filesystem
  gcc make binutils pkg-config fakeroot patch
  git cmake intltool vala desktop-file-utils
  gtk3 libsoup libgee libnotify libcanberra sqlite gmime libsecret libxml2
  gcr webkitgtk enchant gobject-introspection zstd gettext mesa-libgl
)

for attempt in 1 2 3 4 5; do
  if run_root pacman --root "${ROOTFS}" --config "${PACMAN_CONF}" --cachedir "${ROOTFS}/var/cache/pacman/pkg" -Sy --noconfirm "${PACKAGES[@]}"; then
    break
  fi
  if [[ ${attempt} -eq 5 ]]; then
    printf 'Failed to install pinned ALA packages after %s attempts.\n' "${attempt}" >&2
    exit 1
  fi
  printf 'Pinned ALA package install failed; retrying attempt %s/5 after backoff.\n' "$((attempt + 1))" >&2
  sleep $((attempt * 15))
done

rm -rf "${SRC_COPY}" "${STAGING}"
mkdir -p "${SRC_COPY}" "${STAGING}"
git -C "${REPO_ROOT}" archive --format=tar HEAD | tar -x -C "${SRC_COPY}"

run_root chroot "${ROOTFS}" /usr/bin/env -i \
  HOME=/root \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/bin \
  /bin/bash -lc "cd /build/frank-geary-src && mkdir -p build && cd build && cmake .. \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DNO_FATAL_WARNINGS=ON \
    -DGSETTINGS_COMPILE=OFF \
    -DGSETTINGS_COMPILE_IN_PLACE=OFF \
    -DDESKTOP_UPDATE=OFF \
    -DICON_UPDATE=OFF \
    -DTRANSLATE_HELP=OFF \
    -DDISABLE_CONTRACT=ON && make -j\$(nproc) && DESTDIR=/pkgroot make install"

install -d "${STAGING}/opt/frank-geary/bin" "${STAGING}/opt/frank-geary/lib" "${STAGING}/usr/bin"
if [[ ! -x ${STAGING}/usr/bin/geary ]]; then
  printf 'Expected installed binary was not found at %s\n' "${STAGING}/usr/bin/geary" >&2
  exit 1
fi
mv "${STAGING}/usr/bin/geary" "${STAGING}/opt/frank-geary/bin/geary"
cat >"${STAGING}/usr/bin/geary" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export LD_LIBRARY_PATH="/opt/frank-geary/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec /opt/frank-geary/bin/geary "$@"
EOF
chmod 0755 "${STAGING}/usr/bin/geary"
ln -s geary "${STAGING}/usr/bin/frank-geary"

is_core_lib() {
  case "$(basename "$1")" in
    ld-linux*.so*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libresolv.so*|libutil.so*) return 0 ;;
    *) return 1 ;;
  esac
}

copy_lib() {
  local lib=$1 dest real real_dest
  [[ -e ${ROOTFS}${lib} ]] || return 0
  is_core_lib "${lib}" && return 0
  dest=${STAGING}/opt/frank-geary/lib/$(basename "${lib}")
  [[ -e ${dest} ]] || cp -a "${ROOTFS}${lib}" "${dest}"
  real=$(realpath "${ROOTFS}${lib}")
  if [[ ${real} != "${ROOTFS}${lib}" ]]; then
    real_dest=${STAGING}/opt/frank-geary/lib/$(basename "${real}")
    [[ -e ${real_dest} ]] || cp -a "${real}" "${real_dest}"
  fi
}

ldd_paths() {
  local target=$1
  run_root chroot "${ROOTFS}" /usr/bin/env -i \
    LD_LIBRARY_PATH=/pkgroot/opt/frank-geary/lib \
    PATH=/usr/bin \
    /bin/bash -lc "ldd '${target}'" |
    while IFS= read -r line; do
      if [[ ${line} =~ =\>[[:space:]]+(/[^[:space:]]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
      elif [[ ${line} =~ ^[[:space:]]*(/[^[:space:]]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
      fi
    done
}

queue=(/pkgroot/opt/frank-geary/bin/geary)
seen=' '
while [[ ${#queue[@]} -gt 0 ]]; do
  item=${queue[0]}
  queue=("${queue[@]:1}")
  for lib in $(ldd_paths "${item}"); do
    [[ ${lib} == /* ]] || continue
    is_core_lib "${lib}" && continue
    if [[ ${seen} != *" ${lib} "* ]]; then
      seen+="${lib} "
      copy_lib "${lib}"
      queue+=("${lib}")
    fi
  done
done

cat >"${STAGING}/opt/frank-geary/BUILD-MANIFEST.txt" <<EOF
FrankGeary binary release asset
Snapshot-Date: ${SNAPSHOT_DATE}
Git-Commit: ${GIT_COMMIT}
Asset-Name: ${ASSET_NAME}
EOF

rm -f "${WORKDIR}/${ASSET_NAME}"
tar -C "${STAGING}" -cf - . | zstd -T0 -19 -o "${WORKDIR}/${ASSET_NAME}"
sha256sum "${WORKDIR}/${ASSET_NAME}" | tee "${WORKDIR}/${ASSET_NAME}.sha256"
printf 'Created %s\n' "${WORKDIR}/${ASSET_NAME}"
