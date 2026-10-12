#!/usr/bin/env bash
set -euo pipefail

recipe_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
work_dir=${1:-$(mktemp -d)}
mkdir -p "$work_dir"
work_dir=$(CDPATH='' cd -- "$work_dir" && pwd)
source_dir="$work_dir/source"
consumer_dir="$work_dir/consumer"
for path in "$source_dir" "$consumer_dir" "$work_dir/portable.box" "$work_dir/extracted"; do
  if [ -e "$path" ]; then
    echo "Use a fresh workspace; already exists: $path" >&2
    exit 1
  fi
done

marker="package-roundtrip-$(ruby -rsecurerandom -e 'print SecureRandom.hex(16)')"
export PACKAGE_BOX_NAME=${PACKAGE_BOX_NAME:-local/$marker}
source_started=false
consumer_started=false
box_added=false

run_in() {
  local project_dir=$1
  shift
  (cd "$project_dir" && VAGRANT_CWD="$project_dir" vagrant "$@")
}

cleanup() {
  local recipe_status=$?
  trap - EXIT
  if $consumer_started; then run_in "$consumer_dir" destroy -f || recipe_status=1; fi
  if $source_started; then run_in "$source_dir" destroy -f || recipe_status=1; fi
  if $box_added; then run_in "$source_dir" box remove "$PACKAGE_BOX_NAME" || recipe_status=1; fi
  exit "$recipe_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$source_dir" "$consumer_dir" "$work_dir/extracted"
cp "$recipe_dir/source/Vagrantfile" "$source_dir/Vagrantfile"
cp "$recipe_dir/consumer/Vagrantfile" "$consumer_dir/Vagrantfile"

echo "Packaging recipe workspace: $work_dir"
vagrant --version
vagrant plugin list
qemu-img --version
source_started=true
run_in "$source_dir" up --provider=qemu
run_in "$source_dir" ssh -c "printf '%s\\n' '$marker' > ~/package-roundtrip-marker && sync"
run_in "$source_dir" package --output "$work_dir/portable.box"

tar -xzf "$work_dir/portable.box" -C "$work_dir/extracted"
qemu-img info --output=json "$work_dir/extracted/box.img" > "$work_dir/image-info.json"
ruby -rjson -e 'info = JSON.parse(File.read(ARGV[0])); abort "image is not standalone qcow2" unless info["format"] == "qcow2" && !info.key?("backing-filename"); puts "Exported image: standalone qcow2"' "$work_dir/image-info.json"

# Remove the source VM before importing: the consumer must use the exported data.
run_in "$source_dir" destroy -f
source_started=false
run_in "$source_dir" box add "$PACKAGE_BOX_NAME" "$work_dir/portable.box"
box_added=true
consumer_started=true
run_in "$consumer_dir" up --provider=qemu
restored=$(run_in "$consumer_dir" ssh -c 'cat ~/package-roundtrip-marker' | tr -d '\r')
if [ "$restored" != "$marker" ]; then
  echo "Packaged guest data did not match the source marker" >&2
  exit 1
fi
printf '%s\n' "$marker" > "$work_dir/verified-marker.txt"
echo "Package round-trip verified: $marker"
echo "Reusable box retained at: $work_dir/portable.box"
