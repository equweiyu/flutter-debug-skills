#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s <device_serial> <package> <remote_relative_path> <output_dir>\n' \
    "${0##*/}" >&2
}

usage_error() {
  printf 'error: %s\n' "$1" >&2
  usage
  exit 64
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

[[ $# -eq 4 ]] || usage_error "expected four arguments"

device_serial=$1
package_name=$2
remote_path=$3
output_dir=$4

[[ -n "$device_serial" ]] || usage_error "device serial must not be empty"
case "$device_serial" in
  -*) usage_error "device serial must not start with '-'" ;;
esac

[[ "$package_name" =~ ^[A-Za-z0-9_]+([.][A-Za-z0-9_]+)+$ ]] ||
  usage_error "package must be an Android application ID"

[[ -n "$remote_path" ]] || usage_error "remote path must not be empty"
[[ "$remote_path" != /* ]] || usage_error "remote path must be relative"
[[ "$remote_path" != */ ]] || usage_error "remote path must name a file"
[[ "$remote_path" != -* ]] || usage_error "remote path must not start with '-'"
[[ "$remote_path" =~ ^[A-Za-z0-9._/-]+$ ]] ||
  usage_error "remote path may contain only letters, digits, '.', '_', '-', and '/'"
case "$remote_path" in
  *$'\n'* | *$'\r'*)
    usage_error "remote path must not contain line breaks"
    ;;
  .. | ../* | */.. | */../*)
    usage_error "remote path must stay inside the app sandbox"
    ;;
esac

[[ "$output_dir" == /* ]] || usage_error "output directory must be absolute"
[[ -n "$output_dir" ]] || usage_error "output directory must not be empty"

file_name=${remote_path##*/}
[[ -n "$file_name" && "$file_name" != "." ]] ||
  usage_error "remote path must name a file"

database_path="$output_dir/$file_name"
wal_path="$database_path-wal"
shm_path="$database_path-shm"

mkdir -p "$output_dir"
[[ -d "$output_dir" ]] || die "output path is not a directory: $output_dir"

for destination in "$database_path" "$wal_path" "$shm_path"; do
  [[ ! -e "$destination" && ! -L "$destination" ]] ||
    die "refusing to overwrite existing file: $destination"
done

adb_bin=${ADB_BIN:-adb}
command -v "$adb_bin" >/dev/null 2>&1 || die "adb not found: $adb_bin"

tmp_database=
tmp_wal=
tmp_shm=

cleanup() {
  [[ -z "$tmp_database" ]] || rm -f "$tmp_database"
  [[ -z "$tmp_wal" ]] || rm -f "$tmp_wal"
  [[ -z "$tmp_shm" ]] || rm -f "$tmp_shm"
}
trap cleanup EXIT

adb_exec() {
  "$adb_bin" -s "$device_serial" exec-out run-as "$package_name" "$@"
}

remote_exists() {
  adb_exec test -e "$1" >/dev/null 2>&1
}

copy_remote_file() {
  local remote_file=$1
  local destination=$2
  if ! adb_exec cat "$remote_file" >"$destination"; then
    die "failed to export $remote_file"
  fi
}

tmp_database=$(mktemp "$output_dir/.${file_name}.main.XXXXXX")
copy_remote_file "$remote_path" "$tmp_database"

wal_present=false
if remote_exists "$remote_path-wal"; then
  tmp_wal=$(mktemp "$output_dir/.${file_name}.wal.XXXXXX")
  copy_remote_file "$remote_path-wal" "$tmp_wal"
  wal_present=true
fi

shm_present=false
if remote_exists "$remote_path-shm"; then
  tmp_shm=$(mktemp "$output_dir/.${file_name}.shm.XXXXXX")
  copy_remote_file "$remote_path-shm" "$tmp_shm"
  shm_present=true
fi

mv "$tmp_database" "$database_path"
tmp_database=

if [[ "$wal_present" == true ]]; then
  mv "$tmp_wal" "$wal_path"
  tmp_wal=
fi

if [[ "$shm_present" == true ]]; then
  mv "$tmp_shm" "$shm_path"
  tmp_shm=
fi

printf 'database: %s\n' "$database_path"
if [[ "$wal_present" == true ]]; then
  printf 'wal: %s\n' "$wal_path"
fi
if [[ "$shm_present" == true ]]; then
  printf 'shm: %s\n' "$shm_path"
fi
