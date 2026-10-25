#!/bin/bash

if [ "$(id -u)" -eq 0 ]; then echo "Never run this script as root"; exit 1; fi

download_and_verify() {
	local fileUri="$1"
	local hashUri="$2"

	if [ -n "$hashUri" ]; then
		if [ ! -f "data/${hashUri##*/}" ]; then
			echo "Downloading $hashUri..."
			wget -O "data/${hashUri##*/}" "$hashUri" || exit 1
		fi
	fi

	if [ ! -f "data/${fileUri##*/}" ]; then
		echo "Downloading $fileUri..."
		wget -O "data/${fileUri##*/}" "$fileUri" || exit 1
	fi

	if [ -n "$hashUri" ]; then
		local hashName="${hashUri##*/}"
		local hashExt="${hashName##*.}"
		grep " ${fileUri##*/}$" "data/$hashName" | sed 's|  |  data/|' | "${hashExt}sum" -c - || exit 1
	fi
}

create_apprun_script() {
	{
		echo '#!/bin/bash'
		echo "LAUNCHER=$2"
		echo "PROFILE_VERSION=$3"
		cat << 'EOF'
APPDIR="$(dirname "$(readlink -f "$0")")"

# Portable by default: Blender keeps all its files in one folder next to the
# AppImage, laid out like ~/.config/blender/<version>, unless a BLENDER_USER_*
# variable already says where they go.
if ! env | grep -q '^BLENDER_USER_'; then
	PROFILE="$(dirname "${APPIMAGE:-$APPDIR}")/blender-profile/$PROFILE_VERSION"
	export BLENDER_USER_CONFIG="$PROFILE/config"
	export BLENDER_USER_SCRIPTS="$PROFILE/scripts"
	export BLENDER_USER_DATAFILES="$PROFILE/datafiles"
	export BLENDER_USER_EXTENSIONS="$PROFILE/extensions"
	# Blender takes its cache folder from XDG_CACHE_HOME, and its temporary
	# folder, which holds autosaves and the file it saves on quit, from TMPDIR
	# while Preferences > File Paths leaves it empty. Programs that Blender
	# starts, such as a browser for the manual, inherit both.
	export XDG_CACHE_HOME="$PROFILE/cache"
	export TMPDIR="$PROFILE/temp"
	# Blender saves its preferences to ~/.config/blender instead while the
	# BLENDER_USER_CONFIG folder does not exist yet.
	if ! mkdir -p "$BLENDER_USER_CONFIG" "$BLENDER_USER_SCRIPTS" "$BLENDER_USER_DATAFILES" \
		"$BLENDER_USER_EXTENSIONS" "$XDG_CACHE_HOME" "$TMPDIR"; then
		echo "Couldn't create $PROFILE; set a BLENDER_USER_* variable to keep Blender's files elsewhere" >&2
		exit 1
	fi
fi

exec "$APPDIR/$LAUNCHER" "$@"
EOF
	} > "$1"

	chmod +x "$1"
}

echo "Downloading and verifying content"

TAR_NAME="${2##*/}"
: "${MARCH:=$(uname -m)}"

if [[ $TAR_NAME =~ (x64|x86_64) ]]; then
	ARCH=x86_64
	OUTPUT="${TAR_NAME%-linux*}-x86_64.AppImage"
elif [[ $TAR_NAME =~ (i686) ]]; then
	ARCH=i686
	OUTPUT="${TAR_NAME%-linux*}-i686.AppImage"
fi

if ! mkdir -p data zip; then echo "Couldn't create folders"; exit 1; fi

MARCH="$MARCH" ./dlAppImg.sh
download_and_verify "$2" "$1"

echo "Extracting data/$TAR_NAME"

# Always work on a fresh extraction
if [ -e "AppDir" ]; then rm -R "AppDir"; fi

mkdir -p AppDir
tar -xf "data/$TAR_NAME" -C AppDir --strip-components=1 || exit 1

echo "Reconfiguring files in preparation for AppImage..."

if ! [[ $TAR_NAME =~ ^blender-([0-9]+)\.([0-9]+) ]]; then
	echo "Couldn't read the Blender version from $TAR_NAME"
	exit 1
fi
VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"

if [[ -f "AppDir/blender-launcher" ]]; then
	create_apprun_script "AppDir/AppRun" "blender-launcher" "$VERSION"
else
	create_apprun_script "AppDir/AppRun" "blender" "$VERSION"
fi

# Only builds whose denoiser is linked against ROCm 7, Blender 5.2 and later,
# get AMD's runtime. Blender finds the bundled copy before the system's, and
# older builds need the older ROCm they were built against.
if readelf -d AppDir/lib/libOpenImageDenoise_device_hip.so* 2>/dev/null | grep -q '\[libamdhip64\.so\.7\]'; then
	echo "Adding AMD's HIP runtime"
	./dlRocm.sh AppDir/lib || exit 1
fi

# Add X- in front of desktop entries to make appimage happy
sed -i 's/PrefersNonDefaultGPU/X-PrefersNonDefaultGPU/' "AppDir/blender.desktop"

echo "Creating AppImage $OUTPUT..."

ARCH="$ARCH" "./appimagetool-$MARCH.AppImage" -n AppDir "$OUTPUT"

if [[ ! -f "$OUTPUT" ]]; then exit 1; fi

chmod +x "$OUTPUT"

echo "Zipping $OUTPUT into zip/${OUTPUT}.zip..."

zip -0 "zip/${OUTPUT}.zip" "$OUTPUT"

echo "Cleaning up $OUTPUT..."

rm -R AppDir "$OUTPUT"

echo "$OUTPUT successfully made and stored in zip/${OUTPUT}.zip"
