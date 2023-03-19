#!/bin/sh

# SPDX-FileCopyrightText: 2023 Alexander Zhang
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eo pipefail

TEMPDIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMPDIR"' EXIT

USER="${1:-${SUDO_USER:-ctf}}"

echo 'Upgrading system packages'
dnf upgrade -y

echo 'Installing system prackages'
dnf install -y \
	gdb vim git openssh-clients file wget curl python3-pwntools \
	podman moby-engine \
	cargo rubygems python3-pip \
	openssl-devel xz-devel pkgconf-pkg-config patchelf elfutils bsdtar \
	jq java-17-openjdk-devel \
	gdb-gdbserver

systemctl enable --now docker.service
usermod -aG docker "$USER"

echo 'Installing one_gadget'
gem install one_gadget

echo 'Downloading Ghidra'
GHIDRA_URL="$(curl -fsSL \
	-H 'Accept: application/vnd.github+json' \
	-H 'X-GitHub-Api-Version: 2022-11-28' \
	'https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest' \
	| jq -r '.assets | .[] | first(select(.name | test("ghidra_\\d+\\.\\d+\\.\\d+_PUBLIC_\\d{8}\\.zip"))).browser_download_url')"
curl -fsSL "$GHIDRA_URL" -o "$TEMPDIR/ghidra.zip"

echo 'Installing Ghidra'
rm -rf /opt/ghidra
mkdir /opt/ghidra
bsdtar -xf "$TEMPDIR/ghidra.zip" -C /opt/ghidra --strip-components 1 --preserve-permissions
rm "$TEMPDIR/ghidra.zip"
ln -sf /opt/ghidra/ghidraRun /usr/local/bin/ghidra

echo 'Configuring pwntools'
cat <<-'END_PWN_CONF' > /etc/pwn.conf
	[update]
	interval=never

	[context]
	terminal=['gnome-terminal', '--']
END_PWN_CONF

runuser -l "$USER" <<-'END_USER_SCRIPT'
	set -eo pipefail
	shopt -s nullglob

	echo 'Installing crates'
	if ! grep -qxF '# ctf-init' ~/.bash_profile; then
		cat <<-'END_PROFILE_LINES' >> ~/.bash_profile
			# ctf-init
			PATH="$HOME/.cargo/bin:$PATH"
			export CARGO_TARGET_DIR="$HOME/.cargo-target"
		END_PROFILE_LINES
	fi
	export CARGO_TARGET_DIR="$HOME/.cargo-target"
	mkdir -p "$CARGO_TARGET_DIR"
	cargo install pwninit
	cargo install xgadget --features cli-bin

	echo 'Installing GEF'
	rm -f ~/.gef-*.py
	sh -c "$(curl -fsSL 'https://gef.blah.cat/sh')"
END_USER_SCRIPT
