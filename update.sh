#!/bin/bash

if [ "$(id -u)" -eq 0 ]; then echo "Never run this script as root"; exit 1; fi

# Updates manifest.sh to Blender's newest releases: each entry moves to the
# newest patch release of its series, and a series newer than any listed is
# added as a new entry. Entries are never removed. Prints the numbers of the
# entries that changed, for manifest.sh to build; everything else goes to
# stderr.

: "${MANIFEST:=manifest.sh}"
RELEASES="https://download.blender.org/release"

# Prints the newest patch number of a series, such as 3 for 5.2.3, if its
# folder has a Linux tarball with a sha256 file for it.
newest_patch() {
	local series="$1" listing patch
	listing=$(wget -q -O - "$RELEASES/Blender$series/") || return 1
	patch=$(grep -oE "blender-${series//./\\.}\.[0-9]+-linux-x64\.tar\.xz" <<< "$listing" |
		grep -oE '\.[0-9]+-linux' | tr -dc '0-9\n' | sort -n | tail -1)
	if [ -z "$patch" ]; then return 1; fi
	if ! grep -q "blender-$series.$patch.sha256" <<< "$listing"; then return 1; fi
	echo "$patch"
}

mapfile -t lines < "$MANIFEST"
changed=()
last_entry=-1
last_line=-1
newest_major=0
newest_minor=0

for i in "${!lines[@]}"; do
	if [[ ${lines[$i]} =~ ^manifest\[([0-9]+)\]= ]]; then
		last_entry="${BASH_REMATCH[1]}"
	fi
	if [[ ! ${lines[$i]} =~ /Blender([0-9]+)\.([0-9]+)/blender-[0-9]+\.[0-9]+\.([0-9]+)-linux-[a-z0-9_]+\.tar\.[a-z0-9]+\"$ ]]; then
		continue
	fi
	last_line=$i
	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	patch="${BASH_REMATCH[3]}"
	if (( major > newest_major || (major == newest_major && minor > newest_minor) )); then
		newest_major=$major
		newest_minor=$minor
	fi

	series="$major.$minor"
	if ! newest=$(newest_patch "$series"); then
		echo "Blender $series: no Linux tarball with a sha256 file found" >&2
		continue
	fi
	if (( newest <= patch )); then continue; fi

	echo "Blender $series.$patch -> $series.$newest" >&2
	# The hash URL is on the line before the tarball URL.
	lines[i - 1]="${lines[i - 1]//$series.$patch/$series.$newest}"
	lines[i]="${lines[i]//$series.$patch/$series.$newest}"
	changed+=("$last_entry")
done

if [ "$last_line" -lt 0 ]; then echo "No entries found in $MANIFEST" >&2; exit 1; fi

if ! listing=$(wget -q -O - "$RELEASES/"); then echo "Couldn't list $RELEASES" >&2; exit 1; fi
newer=""
for folder in $(grep -oE 'Blender[0-9]+\.[0-9]+/' <<< "$listing" | sort -u); do
	[[ $folder =~ ([0-9]+)\.([0-9]+) ]]
	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	if (( major > newest_major || (major == newest_major && minor > newest_minor) )); then
		newest_major=$major
		newest_minor=$minor
		newer="$major.$minor"
	fi
done

if [ -n "$newer" ]; then
	if patch=$(newest_patch "$newer"); then
		entry=$((last_entry + 1))
		echo "Blender $newer.$patch added as entry $entry" >&2
		new_entry=("" "manifest[$entry]=\"$RELEASES/Blender$newer/blender-$newer.$patch.sha256 \\"
			"$RELEASES/Blender$newer/blender-$newer.$patch-linux-x64.tar.xz\"")
		lines=("${lines[@]:0:last_line + 1}" "${new_entry[@]}" "${lines[@]:last_line + 1}")
		changed+=("$entry")
	else
		echo "Blender $newer: no Linux tarball with a sha256 file yet" >&2
	fi
fi

if [ ${#changed[@]} -gt 0 ]; then
	printf '%s\n' "${lines[@]}" > "$MANIFEST"
fi
echo "${changed[*]}"
