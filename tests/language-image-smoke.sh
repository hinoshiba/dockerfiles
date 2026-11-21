#!/bin/bash
# Run in the Go/Rust image with LANG_IMAGE and EXPECTED_VERSION from checkout.
set -euo pipefail

: "${LANG_IMAGE:?Set LANG_IMAGE to golang or rust}"
: "${EXPECTED_VERSION:?Set EXPECTED_VERSION to the pinned strict version}"
case "$LANG_IMAGE" in
    golang|rust) ;;
    *) echo "Unsupported language image: $LANG_IMAGE" >&2; exit 2 ;;
esac

locale -a | grep -iq '^ja_JP\.utf8$'
test "$(locale charmap)" = 'UTF-8'
test -w /tmphome
test -w /.cache

smoke_directory="$(mktemp -d)"
trap 'rm -rf "$smoke_directory"' EXIT
cd "$smoke_directory"

case "$LANG_IMAGE" in
    golang)
        test "$(go version | awk '{print $3}')" = "go${EXPECTED_VERSION}"
        cat > main.go <<'GO'
package main

/*
static int answer(void) { return 42; }
*/
import "C"
import "fmt"

func main() {
    if C.answer() != 42 {
        panic("CGo returned the wrong value")
    }
    fmt.Println("go-ok")
}
GO
        CGO_ENABLED=1 go build -o language-smoke main.go
        test "$(./language-smoke)" = 'go-ok'
        ;;
    rust)
        test "$(rustc --version | awk '{print $2}')" = "${EXPECTED_VERSION}"
        cargo --version
        rustdoc --version
        mkdir src
        cat > Cargo.toml <<'TOML'
[package]
name = "language-smoke"
version = "0.1.0"
edition = "2021"
TOML
        printf 'fn main() { println!("rust-ok"); }\n' > src/main.rs
        cargo build --offline --quiet
        test "$(./target/debug/language-smoke)" = 'rust-ok'
        ;;
esac
echo "$LANG_IMAGE image version, locale and compiler checks passed."
