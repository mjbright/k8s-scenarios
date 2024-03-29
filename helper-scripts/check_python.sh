
die() { echo "$0: die - $*" >&2; exit 1; }

python -m py_compile $* || die "Failed to compile"
echo "OK"

