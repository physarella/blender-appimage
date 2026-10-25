#!/bin/bash

if [ "$(id -u)" -eq 0 ]; then echo "Never run this script as root"; exit 1; fi

# Copies AMD's HIP runtime into the folder given as the only argument, so that
# Cycles and OpenImageDenoise can use AMD GPUs without ROCm on the system.
# These are AMD's builds for EL8, whose glibc 2.28 is no newer than the one
# Blender is built for.
#
# The hashes are AMD's, from the repository's primary.xml.gz. Its own hash is
# in repodata/repomd.xml, which repodata/repomd.xml.asc signs with AMD's ROCm
# key, fingerprint CA8B B472 7A47 B4D0 9B4E  E896 9386 B48A 1A69 3C5C.

set -o pipefail

ROCM_VERSION=7.2.4
ROCM_REPO="https://repo.radeon.com/rocm/el8/$ROCM_VERSION/main"
ROCM_DIR="data/rocm-$ROCM_VERSION"

packages=(
	"926682b6b94f16cd5470c70c1e6b6c3fc90af6a6c94af20cf8d29fdc4226982e  hip-runtime-amd-7.2.53211.70204-93.el8.x86_64.rpm"
	"65de30f29558ae195a0dcc81e5d30b35ab1a012c232210ad86559ddd74dba6e0  hsa-rocr-1.18.0.70204-93.el8.x86_64.rpm"
	"35808ed7f1549b6e35020f60d7c36f7971220a954a0fcbdb2b246a9c0816ccd7  comgr-3.0.0.70204-93.el8.x86_64.rpm"
	"625f2e86b101a0496d36535147655acb04efd7a0d02e8fe6104219968c21b4a3  rocm-core-7.2.4.70204-93.el8.x86_64.rpm"
	"9251fefc532393327e9f6b24cb07068c9f05022dc29071e6c2594b3b3cf25ec0  rocprofiler-register-0.6.0.70204-93.el8.x86_64.rpm"
)

if [ -z "$1" ]; then echo "Usage: $0 <folder to copy the libraries into>"; exit 1; fi

if [ ! -d "$ROCM_DIR" ]; then
	if ! mkdir -p data; then echo "Couldn't create folders"; exit 1; fi

	for package in "${packages[@]}"; do
		file="${package##* }"
		if [ ! -f "data/$file" ]; then
			echo "Downloading $file..."
			wget -O "data/$file" "$ROCM_REPO/$file" || exit 1
		fi
		if ! echo "${package%% *}  data/$file" | sha256sum -c -; then
			rm "data/$file"
			exit 1
		fi
	done

	echo "Extracting ROCm $ROCM_VERSION"

	# Unpacked beside the final folder and renamed at the end, so that an
	# interrupted run is not taken for a finished one.
	if [ -e "$ROCM_DIR.part" ]; then rm -R "$ROCM_DIR.part"; fi
	mkdir "$ROCM_DIR.part" || exit 1
	for package in "${packages[@]}"; do
		rpm2cpio "data/${package##* }" | (cd "$ROCM_DIR.part" && cpio -idm --quiet) || exit 1
	done
	mv "$ROCM_DIR.part" "$ROCM_DIR" || exit 1
fi

cp -P "$ROCM_DIR/opt/rocm-$ROCM_VERSION/lib/"*.so* "$1" || exit 1
