#!/bin/bash
# Run inside workbench/claude-codex with EXPECTED_* from checkout version files.
set -euo pipefail
export PATH="${HOME}/.cargo/bin:/usr/local/go/bin:${PATH}"
test "$(rustc --version | awk '{print $2}')" = "${EXPECTED_RUST}"
test "$(go version | awk '{print $3}')" = "go${EXPECTED_GO}"
test "$(python3 --version | awk '{print $2}')" = "${EXPECTED_PYTHON}"
test "$(node --version)" = "v${EXPECTED_NODE}"

smoke_dir="$(mktemp -d)"
trap 'rm -rf "$smoke_dir"' EXIT
cd "$smoke_dir"
printf 'fn main() { println!("rust-ok"); }\n' > main.rs
rustc main.rs -o rust-smoke
test "$(./rust-smoke)" = rust-ok
printf 'package main\nimport "fmt"\nfunc main() { fmt.Println("go-ok") }\n' > main.go
test "$(go run main.go)" = go-ok
cat > cgo.go <<'GO'
package main
// #include <stdlib.h>
import "C"
func main() { if C.abs(-3) != 3 { panic("cgo failed") } }
GO
CGO_ENABLED=1 go run cgo.go
printf 'int main() { return 0; }\n' | g++ -x c++ -o cpp-smoke -
./cpp-smoke
python3 -c 'import ssl, ctypes, zlib; assert zlib.decompress(zlib.compress(b"ok")) == b"ok"'
node -e 'if (JSON.parse("{\"ok\":true}").ok !== true) process.exit(1)'
corepack --version
gcc --version | head -n 1
g++ --version | head -n 1
cargo clippy --version
rustfmt --version
rust-analyzer --version
rustup component list --installed | grep '^rust-src'
rustup component list --installed | grep '^rust-docs'
echo 'Checkout-pinned toolchains passed.'
