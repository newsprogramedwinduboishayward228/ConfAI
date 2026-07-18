#!/bin/sh
# ConfAI installer for Linux and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/redstone-md/ConfAI/main/install.sh | sh
#
# Downloading a script and running it is a trust decision. Read it first if you
# would rather not take it on faith; see INSTALL.md for the archive and
# `cargo install` routes, which do not involve this file at all.
#
# POSIX sh. No bashisms, no `local`, no arrays.

set -eu

REPO="redstone-md/ConfAI"
BIN="confai"
MARKER="# added by the confai installer"

opt_version=""
opt_prefix=""
opt_modify_path=1
opt_force=0
opt_quiet=0
opt_uninstall=0

tmpdir=""

# ---------------------------------------------------------------- output ----

say() {
	[ "$opt_quiet" -eq 1 ] || printf '%s\n' "$*"
}

warn() {
	printf 'warning: %s\n' "$*" >&2
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	[ -n "$tmpdir" ] && [ -d "$tmpdir" ] && rm -rf "$tmpdir"
	return 0
}
trap cleanup EXIT INT TERM

usage() {
	cat <<EOF
Install $BIN, the CLI for every AI coding agent's config.

Usage:
  install.sh [options]

Options:
  --version <vX.Y.Z>  Install this release instead of the latest one.
  --prefix <dir>      Install into <dir> instead of the default location.
  --no-modify-path    Do not touch any shell profile, even if the install
                      directory is not on PATH.
  --force             Reinstall even if this version is already present.
  --quiet             Only print errors.
  --uninstall         Remove the binary and the PATH line this script added.
  --help              Show this message.

Install directory, in order of preference:
  --prefix, then \$XDG_BIN_HOME, then ~/.local/bin, then /usr/local/bin
  (which asks before using sudo).

Every download is checked against the SHA256SUMS file published with the
release. A mismatch aborts the install.
EOF
}

# ------------------------------------------------------------ arguments ----

while [ $# -gt 0 ]; do
	case "$1" in
	--version)
		[ $# -ge 2 ] || die "--version needs a value, for example --version v0.0.1"
		opt_version="$2"
		shift 2
		;;
	--version=*)
		opt_version="${1#--version=}"
		shift
		;;
	--prefix)
		[ $# -ge 2 ] || die "--prefix needs a directory"
		opt_prefix="$2"
		shift 2
		;;
	--prefix=*)
		opt_prefix="${1#--prefix=}"
		shift
		;;
	--no-modify-path)
		opt_modify_path=0
		shift
		;;
	--force)
		opt_force=1
		shift
		;;
	--quiet | -q)
		opt_quiet=1
		shift
		;;
	--uninstall)
		opt_uninstall=1
		shift
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		printf 'error: unknown option: %s\n\n' "$1" >&2
		usage >&2
		exit 1
		;;
	esac
done

# --------------------------------------------------------------- system ----

need() {
	command -v "$1" >/dev/null 2>&1
}

# An unknown libc is answered with musl: a static musl binary runs on a glibc
# system, but a glibc binary does not run on Alpine.
detect_target() {
	dt_os="$(uname -s)"
	dt_arch="$(uname -m)"

	case "$dt_arch" in
	x86_64 | amd64) dt_arch=x86_64 ;;
	aarch64 | arm64) dt_arch=aarch64 ;;
	*) die "unsupported architecture: $dt_arch (see the release page for what is published)" ;;
	esac

	case "$dt_os" in
	Linux)
		if ldd --version 2>&1 | grep -qi musl; then
			dt_libc=musl
		elif ldd --version 2>&1 | grep -qiE 'glibc|gnu libc|gnu c library'; then
			dt_libc=gnu
		elif need getconf && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
			dt_libc=gnu
		else
			dt_libc=musl
		fi
		printf '%s-unknown-linux-%s\n' "$dt_arch" "$dt_libc"
		;;
	Darwin)
		printf '%s-apple-darwin\n' "$dt_arch"
		;;
	MINGW* | MSYS* | CYGWIN* | Windows_NT)
		die "this script is for Linux and macOS; on Windows use install.ps1 (see INSTALL.md)"
		;;
	*)
		die "unsupported operating system: $dt_os"
		;;
	esac
}

http_get() {
	if need curl; then
		curl -fsSL --retry 3 --proto '=https' --tlsv1.2 "$1"
	elif need wget; then
		wget -qO- "$1"
	else
		die "neither curl nor wget is installed"
	fi
}

http_download() {
	if need curl; then
		curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$2" "$1"
	elif need wget; then
		wget -qO "$2" "$1"
	else
		die "neither curl nor wget is installed"
	fi
}

sha256_of() {
	if need sha256sum; then
		sha256sum "$1" | awk '{print $1}'
	elif need shasum; then
		shasum -a 256 "$1" | awk '{print $1}'
	elif need openssl; then
		openssl dgst -sha256 "$1" | awk '{print $NF}'
	else
		die "no SHA-256 tool found (need sha256sum, shasum or openssl); refusing to install unverified"
	fi
}

lower() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Reads from the terminal, not stdin: stdin is this script when the install is
# piped from curl.
ask() {
	if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
		return 1
	fi
	printf '%s [y/N] ' "$1" >/dev/tty 2>/dev/null || return 1
	read -r ask_reply </dev/tty || return 1
	case "$ask_reply" in
	y | Y | yes | YES | Yes) return 0 ;;
	*) return 1 ;;
	esac
}

# ------------------------------------------------------- install location ----

# Also decides whether sudo is needed, into $SUDO.
resolve_prefix() {
	SUDO=""

	if [ -n "$opt_prefix" ]; then
		mkdir -p "$opt_prefix" 2>/dev/null || true
		[ -d "$opt_prefix" ] || die "--prefix $opt_prefix does not exist and could not be created"
		if [ ! -w "$opt_prefix" ]; then
			need_sudo_for "$opt_prefix"
		fi
		PREFIX="$opt_prefix"
		return 0
	fi

	if [ -n "${XDG_BIN_HOME:-}" ]; then
		mkdir -p "$XDG_BIN_HOME" 2>/dev/null || true
		if [ -d "$XDG_BIN_HOME" ] && [ -w "$XDG_BIN_HOME" ]; then
			PREFIX="$XDG_BIN_HOME"
			return 0
		fi
	fi

	if mkdir -p "$HOME/.local/bin" 2>/dev/null && [ -w "$HOME/.local/bin" ]; then
		PREFIX="$HOME/.local/bin"
		return 0
	fi

	need_sudo_for /usr/local/bin
	PREFIX=/usr/local/bin
	$SUDO mkdir -p "$PREFIX"
}

need_sudo_for() {
	if [ "$(id -u)" -eq 0 ]; then
		SUDO=""
		return 0
	fi
	need sudo || die "$1 is not writable and sudo is not installed; pass --prefix <dir> to install somewhere you own"
	say "$1 is not writable by $(id -un)."
	if ask "Use sudo to write to $1?"; then
		SUDO="sudo"
	else
		die "declined; pass --prefix <dir> to install somewhere you own, for example --prefix \"\$HOME/.local/bin\""
	fi
}

# ------------------------------------------------------------ PATH setup ----

profile_for_shell() {
	pfs_shell="$(basename "${SHELL:-sh}")"
	case "$pfs_shell" in
	bash) printf '%s\n' "$HOME/.bashrc" ;;
	zsh) printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
	fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
	*) printf '%s\n' "$HOME/.profile" ;;
	esac
}

path_line_for_shell() {
	case "$(basename "${SHELL:-sh}")" in
	fish) printf 'set -gx PATH "%s" $PATH\n' "$1" ;;
	*) printf 'export PATH="%s:$PATH"\n' "$1" ;;
	esac
}

dir_on_path() {
	case ":${PATH}:" in
	*":$1:"*) return 0 ;;
	*) return 1 ;;
	esac
}

add_to_path() {
	atp_dir="$1"

	if dir_on_path "$atp_dir"; then
		return 0
	fi

	if [ "$opt_modify_path" -eq 0 ]; then
		warn "$atp_dir is not on PATH, and --no-modify-path was given."
		warn "Add it yourself with:  $(path_line_for_shell "$atp_dir")"
		return 0
	fi

	atp_profile="$(profile_for_shell)"
	atp_line="$(path_line_for_shell "$atp_dir")"

	mkdir -p "$(dirname "$atp_profile")"
	[ -f "$atp_profile" ] || : >"$atp_profile"

	# Idempotent: the same line is never appended twice, so re-running this
	# script to upgrade does not grow the profile.
	if grep -Fqx "$atp_line" "$atp_profile" 2>/dev/null; then
		say "PATH already set up in $atp_profile."
		return 0
	fi

	printf '\n%s\n%s\n' "$MARKER" "$atp_line" >>"$atp_profile"

	say ""
	say "Added to $atp_profile:"
	say "    $atp_line"
	say "To undo, delete that line and the '$MARKER' comment above it,"
	say "or run:  sh install.sh --uninstall"
	say "Open a new shell, or run:  . \"$atp_profile\""
}

remove_from_path() {
	rfp_dir="$1"
	rfp_line="$(path_line_for_shell "$rfp_dir")"

	for rfp_profile in \
		"$HOME/.bashrc" \
		"$HOME/.bash_profile" \
		"${ZDOTDIR:-$HOME}/.zshrc" \
		"$HOME/.config/fish/config.fish" \
		"$HOME/.profile"; do

		[ -f "$rfp_profile" ] || continue
		grep -Fq "$MARKER" "$rfp_profile" 2>/dev/null || continue

		rfp_tmp="$tmpdir/profile.$$"
		# Drops the marker comment and the line that follows it, plus any bare
		# copy of the PATH line this script would have written.
		awk -v marker="$MARKER" -v line="$rfp_line" '
			$0 == marker { skip = 1; next }
			skip == 1    { skip = 0; if ($0 == line) next }
			$0 == line   { next }
			{ print }
		' "$rfp_profile" >"$rfp_tmp"

		if cmp -s "$rfp_profile" "$rfp_tmp"; then
			rm -f "$rfp_tmp"
			continue
		fi
		cat "$rfp_tmp" >"$rfp_profile"
		rm -f "$rfp_tmp"
		say "Removed the PATH entry from $rfp_profile."
	done
}

# ------------------------------------------------------------- uninstall ----

do_uninstall() {
	tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/confai-uninstall.XXXXXX")"

	un_found=0
	for un_dir in \
		"${opt_prefix:-}" \
		"${XDG_BIN_HOME:-}" \
		"$HOME/.local/bin" \
		/usr/local/bin; do

		[ -n "$un_dir" ] || continue
		[ -f "$un_dir/$BIN" ] || continue

		un_sudo=""
		if [ ! -w "$un_dir" ] && [ "$(id -u)" -ne 0 ]; then
			need sudo || die "$un_dir/$BIN needs root to remove and sudo is not installed"
			ask "Use sudo to remove $un_dir/$BIN?" || die "declined"
			un_sudo="sudo"
		fi
		$un_sudo rm -f "$un_dir/$BIN"
		say "Removed $un_dir/$BIN"
		un_found=1
		remove_from_path "$un_dir"
	done

	if [ "$un_found" -eq 0 ]; then
		say "No $BIN binary found in any directory this installer uses."
	fi

	say ""
	say "ConfAI also keeps user data in ~/.confai (presets, agent rosters)."
	say "It was left alone. Remove it with:  rm -rf ~/.confai"
}

# --------------------------------------------------------------- install ----

do_install() {
	target="$(detect_target)"

	if [ -n "$opt_version" ]; then
		tag="$opt_version"
		case "$tag" in
		v*) ;;
		*) tag="v$tag" ;;
		esac
	else
		say "Resolving the latest release..."
		api_json="$(http_get "https://api.github.com/repos/${REPO}/releases/latest")" ||
			die "could not reach the GitHub API; pass --version vX.Y.Z to skip the lookup"
		tag="$(printf '%s' "$api_json" |
			tr ',' '\n' |
			sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
			head -n 1)"
		[ -n "$tag" ] || die "could not find a tag_name in the GitHub API response; pass --version vX.Y.Z"
	fi

	version="${tag#v}"
	archive_ext="tar.gz"
	stem="${BIN}-${version}-${target}"
	archive="${stem}.${archive_ext}"
	base="https://github.com/${REPO}/releases/download/${tag}"

	resolve_prefix

	if [ "$opt_force" -eq 0 ] && [ -x "$PREFIX/$BIN" ]; then
		# `-V` is the terse "confai X.Y.Z"; `--version` prints the wordmark.
		installed="$("$PREFIX/$BIN" -V 2>/dev/null | awk 'NR == 1 { print $NF }' || true)"
		if [ "$installed" = "$version" ]; then
			say "$BIN $version is already installed in $PREFIX. Use --force to reinstall."
			add_to_path "$PREFIX"
			return 0
		fi
	fi

	say "Installing $BIN $version ($target) into $PREFIX"

	tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/confai-install.XXXXXX")"

	say "Downloading $archive"
	http_download "$base/$archive" "$tmpdir/$archive" ||
		die "download failed: $base/$archive
Check that $target is published for $tag at https://github.com/${REPO}/releases"

	say "Downloading SHA256SUMS"
	http_download "$base/SHA256SUMS" "$tmpdir/SHA256SUMS" ||
		die "could not download SHA256SUMS for $tag; refusing to install an unverified binary"

	# `sha256sum` writes "<hash>  <name>"; the name is anchored so a substring
	# of another archive's name cannot match.
	expected="$(awk -v want="$archive" '
		{ name = $2; sub(/^\*/, "", name); if (name == want) { print $1; exit } }
	' "$tmpdir/SHA256SUMS")"

	[ -n "$expected" ] || die "SHA256SUMS for $tag has no entry for $archive; refusing to install"

	actual="$(sha256_of "$tmpdir/$archive")"

	if [ "$(lower "$actual")" != "$(lower "$expected")" ]; then
		printf '\n' >&2
		printf 'error: CHECKSUM MISMATCH -- NOTHING WAS INSTALLED\n' >&2
		printf '  file:     %s\n' "$archive" >&2
		printf '  expected: %s\n' "$expected" >&2
		printf '  actual:   %s\n' "$actual" >&2
		printf '\n' >&2
		printf 'The download does not match the checksum published with the release.\n' >&2
		printf 'Do not use it. Retry; if it happens again, open an issue at\n' >&2
		printf 'https://github.com/%s/issues\n' "$REPO" >&2
		exit 1
	fi

	say "Checksum verified."

	tar -xzf "$tmpdir/$archive" -C "$tmpdir" || die "could not extract $archive"
	[ -f "$tmpdir/$stem/$BIN" ] || die "$archive did not contain $stem/$BIN"

	# Land in the target directory under a temporary name and rename, so a
	# failure part way through never leaves a truncated binary on PATH.
	staged="$PREFIX/.${BIN}.install.$$"
	$SUDO cp "$tmpdir/$stem/$BIN" "$staged"
	$SUDO chmod 755 "$staged"
	$SUDO mv -f "$staged" "$PREFIX/$BIN"

	say "Installed $PREFIX/$BIN"

	add_to_path "$PREFIX"

	say ""
	if dir_on_path "$PREFIX"; then
		say "Run '$BIN' with no arguments for the interactive view, or '$BIN --help'."
	else
		say "Run '$PREFIX/$BIN --help' to get started."
	fi
}

if [ "$opt_uninstall" -eq 1 ]; then
	do_uninstall
else
	do_install
fi
