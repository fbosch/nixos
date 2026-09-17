#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
viewer="${RPG_MAKER_VIEWER_SCRIPT:-$script_dir/../scripts/rpg-maker-image-viewer.sh}"
test_root="/tmp/rpg-maker-image-viewer-test-$UID-$$"
cache_root="/tmp/rpg-maker-loupe-test-$UID-$$"
stub_bin="$test_root/bin"
call_log="$test_root/rpgmasd.calls"
hash_log="$test_root/sha256sum.calls"
loupe_log="$test_root/loupe.args"
zenity_log="$test_root/zenity.errors"

cleanup() {
  rm -rf -- "$test_root" "$cache_root"
}
trap cleanup EXIT

mkdir -p -- "$stub_bin"
export RPG_MAKER_CACHE_ROOT="$cache_root"
export RPG_TEST_CALLS="$call_log"
export RPG_TEST_HASH_LOG="$hash_log"
export RPG_TEST_LOUPE_LOG="$loupe_log"
export RPG_MAKER_DECODER_IDENTITY=test-decoder-v1
export RPG_TEST_ZENITY_LOG="$zenity_log"
system_sha256sum="$(command -v sha256sum)"
export PATH="$stub_bin:$PATH"
: >"$call_log"
: >"$hash_log"
: >"$loupe_log"
: >"$zenity_log"

printf '#!%s\n' "$(command -v bash)" >"$stub_bin/rpgmasd"
cat >>"$stub_bin/rpgmasd" <<'EOF'
set -euo pipefail

[[ ${1:-} == decrypt ]] || exit 2
shift
input_dir=""
output_dir=""
while (($# > 0)); do
  case "$1" in
    --input-dir)
      input_dir="$2"
      shift 2
      ;;
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    *)
      echo "unexpected argument: $1" >&2
      exit 2
      ;;
  esac
done
printf '%s\n' "$input_dir" >>"$RPG_TEST_CALLS"
if [[ ${RPG_TEST_SLEEP:-0} != 0 ]]; then
  sleep "$RPG_TEST_SLEEP"
fi
mkdir -p -- "$output_dir"
for input in "$input_dir"/*; do
  [[ -f $input ]] || continue
  base="$(basename -- "$input")"
  case "$base" in
    *.rpgmvp | *.png_) ;;
    *)
      echo "unexpected non-image input: $base" >&2
      exit 3
      ;;
  esac
  if grep -q 'BAD' "$input"; then
    echo "corrupt image: $base" >&2
    exit 4
  fi
  printf '\x89PNG\r\n\x1a\nPNG:%s:%s\n' "$base" "$(<"$input")" >"$output_dir/${base%.*}.png"
done
EOF
chmod 700 -- "$stub_bin/rpgmasd"

printf '#!%s\n' "$(command -v bash)" >"$stub_bin/sha256sum"
cat >>"$stub_bin/sha256sum" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >>"$RPG_TEST_HASH_LOG"
exec "$RPG_TEST_REAL_SHA256SUM" "$@"
EOF
chmod 700 -- "$stub_bin/sha256sum"
export RPG_TEST_REAL_SHA256SUM="$system_sha256sum"

printf '#!%s\n' "$(command -v bash)" >"$stub_bin/loupe"
cat >>"$stub_bin/loupe" <<'EOF'
set -euo pipefail
for argument in "$@"; do
  printf '%s\n' "$argument" >>"$RPG_TEST_LOUPE_LOG"
done
EOF
chmod 700 -- "$stub_bin/loupe"

printf '#!%s\n' "$(command -v bash)" >"$stub_bin/zenity"
cat >>"$stub_bin/zenity" <<'EOF'
set -euo pipefail
for argument in "$@"; do
  case "$argument" in
    --text=*) printf '%s\n' "${argument#--text=}" >>"$RPG_TEST_ZENITY_LOG" ;;
  esac
done
EOF
chmod 700 -- "$stub_bin/zenity"

assert_file() {
  [[ -f $1 ]] || {
    echo "expected file: $1" >&2
    exit 1
  }
}

assert_absent() {
  [[ ! -e $1 && ! -L $1 ]] || {
    echo "expected absent path: $1" >&2
    exit 1
  }
}

assert_equal() {
  if [[ $1 != "$2" ]]; then
    echo "${3:-values differ}: expected '$1', got '$2'" >&2
    exit 1
  fi
}

cache_dir_for() {
  local source_dir="$1"
  local hash
  hash="$(printf '%s' "$source_dir" | sha256sum - | cut -d ' ' -f1)"
  printf '%s/%s' "$cache_root" "$hash"
}

run_viewer() {
  : >"$loupe_log"
  bash "$viewer" "$@"
}

source_dir="$test_root/game Sp ace/Æventyr 🔥"
mkdir -p -- "$source_dir"
printf 'hero-v1\n' >"$source_dir/hero name.rpgmvp"
printf 'collision-rpgmvp\n' >"$source_dir/same.rpgmvp"
printf 'collision-png_\n' >"$source_dir/same.png_"
printf 'this corrupt audio must not be staged\n' >"$source_dir/unrelated.ogg"

run_viewer "$source_dir/hero name.rpgmvp" "$source_dir/hero name.rpgmvp"
source_cache_dir="$(cache_dir_for "$source_dir")"
assert_equal 1 "$(wc -l <"$call_log")" "initial batch count"
assert_equal 1 "$(wc -l <"$loupe_log")" "duplicate selection count"
assert_equal "$source_cache_dir/hero name.rpgmvp.png" "$(<"$loupe_log")" "selected image opens first"
assert_file "$source_cache_dir/hero name.rpgmvp.png"
assert_file "$source_cache_dir/same.rpgmvp.png"
assert_file "$source_cache_dir/same.png_.png"
assert_equal 700 "$(stat -c '%a' "$cache_root")" "cache root permissions"
assert_equal 700 "$(stat -c '%a' "$source_cache_dir")" "cache directory permissions"

# Full encrypted basenames keep .rpgmvp and .png_ outputs distinct.
grep -Eq 'PNG:image-[0-9]+\.rpgmvp:collision-rpgmvp' "$source_cache_dir/same.rpgmvp.png"
grep -Eq 'PNG:image-[0-9]+\.png_:collision-png_' "$source_cache_dir/same.png_.png"

hash_count_before="$(wc -l <"$hash_log")"
run_viewer "$source_dir/hero name.rpgmvp"
assert_equal 1 "$(wc -l <"$call_log")" "cache hit count"
assert_equal "$((hash_count_before + 1))" "$(wc -l <"$hash_log")" "unchanged launch hashes only cache key"

touch -m -d 'next minute' "$source_dir/hero name.rpgmvp"
run_viewer "$source_dir/hero name.rpgmvp"
assert_equal 2 "$(wc -l <"$call_log")" "metadata change rebuild count"
printf 'hero-v2\n' >"$source_dir/hero name.rpgmvp"
run_viewer "$source_dir/hero name.rpgmvp"
assert_equal 3 "$(wc -l <"$call_log")" "content change count"
grep -Fq 'hero-v2' "$source_cache_dir/hero name.rpgmvp.png"

export RPG_MAKER_DECODER_IDENTITY=test-decoder-v2
run_viewer "$source_dir/hero name.rpgmvp"
assert_equal 4 "$(wc -l <"$call_log")" "decoder identity change rebuild count"

rm -- "$source_dir/same.png_"
run_viewer "$source_dir/hero name.rpgmvp"
assert_equal 4 "$(wc -l <"$call_log")" "sibling deletion should be a cache hit"
assert_absent "$source_cache_dir/same.png_.png"
assert_absent "$source_cache_dir/same.png_.png.source-hash"

bad_dir="$test_root/bad"
mkdir -p -- "$bad_dir"
printf 'BAD image\n' >"$bad_dir/broken.rpgmvp"
: >"$zenity_log"
if bash "$viewer" "$bad_dir/broken.rpgmvp" >"$test_root/bad.stdout" 2>"$test_root/bad.stderr"; then
  echo "corrupt image unexpectedly succeeded" >&2
  exit 1
fi
assert_absent "$(cache_dir_for "$bad_dir")/broken.rpgmvp.png"
grep -Fq 'corrupt image' "$zenity_log"

concurrent_dir="$test_root/concurrent"
mkdir -p -- "$concurrent_dir"
printf 'concurrent\n' >"$concurrent_dir/image.rpgmvp"
concurrent_calls="$test_root/concurrent.calls"
: >"$concurrent_calls"
export RPG_TEST_CALLS="$concurrent_calls"
export RPG_TEST_SLEEP=1
if bash "$viewer" "$concurrent_dir/image.rpgmvp" >"$test_root/concurrent-1.out" 2>&1 & then
  first_pid=$!
else
  echo "failed to start first concurrent viewer" >&2
  exit 1
fi
if bash "$viewer" "$concurrent_dir/image.rpgmvp" >"$test_root/concurrent-2.out" 2>&1 & then
  second_pid=$!
else
  echo "failed to start second concurrent viewer" >&2
  exit 1
fi
if ! wait "$first_pid"; then
  cat "$test_root/concurrent-1.out" >&2
  exit 1
fi
if ! wait "$second_pid"; then
  cat "$test_root/concurrent-2.out" >&2
  exit 1
fi
assert_equal 1 "$(wc -l <"$concurrent_calls")" "concurrent conversion count"

printf 'rpg-maker-image-viewer regression tests passed\n'
