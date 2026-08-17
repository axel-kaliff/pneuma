#!/usr/bin/bash
set -euo pipefail

###############################################################################
# COPR Helper Functions (CentOS Stream 10 / EPEL 10)
###############################################################################
# dnf4's copr plugin guesses the chroot from the running OS and fails when a
# COPR only carries a differently-named chroot (CS10 guesses centos-stream-10;
# our COPRs publish epel-10). Write the repo file explicitly instead,
# keeping the enable -> install -> remove isolation semantics: no COPR repo
# ever persists into the image.
###############################################################################

# copr_install_isolated "owner/project" pkg... [-- chroot]
# Default chroot: epel-10 (the CS10+EPEL+CRB buildroot family; matches the
# axel-kaliff/pneuma and yselkowitz COPRs). Override with COPR_CHROOT for a
# project that only publishes a differently-named chroot.
copr_install_isolated() {
	local copr_name="$1"
	shift
	local packages=("$@")

	if [[ ${#packages[@]} -eq 0 ]]; then
		echo "ERROR: No packages specified for copr_install_isolated"
		return 1
	fi

	local chroot="${COPR_CHROOT:-epel-10}"
	local repo_id="copr-${copr_name//\//-}"
	local repofile="/etc/yum.repos.d/_${repo_id}.repo"
	local results_url="https://download.copr.fedorainfracloud.org/results/${copr_name}/${chroot}-\$basearch"

	echo "Installing ${packages[*]} from COPR ${copr_name} (${chroot}, isolated)"

	# Ensure the repo file is cleaned up even if install fails
	cleanup_copr() {
		rm -f "${repofile}"
	}
	trap cleanup_copr EXIT

	cat >"${repofile}" <<EOF
[${repo_id}]
name=Copr repo for ${copr_name} (${chroot})
baseurl=${results_url}/
type=rpm-md
skip_if_unavailable=False
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/${copr_name}/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
EOF

	dnf -y install --enablerepo="${repo_id}" "${packages[@]}"

	cleanup_copr
	trap - EXIT

	echo "Installed ${packages[*]} from ${copr_name}"
}
