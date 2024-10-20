#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function artifact_armbian-desktop_config_dump() {
	artifact_input_variables[RELEASE]="${RELEASE}"
	artifact_input_variables[DESKTOP_ENVIRONMENT]="${DESKTOP_ENVIRONMENT}"
	# These two below ideally shouldn't be included, but in practice, they are, otherwise...
	# ... we'll reduce the number of artifacts to 1, and it's not true; we have one per appgroup variant.
	# See https://github.com/armbian/build/issues/5439
	# Having this in the reducer (config_dump()) allows OCI to be populated correctly, but the apt repo will still have trouble
	# until #5439 is somehow addressed.
	artifact_input_variables[DESKTOP_ENVIRONMENT_CONFIG_NAME]="${DESKTOP_ENVIRONMENT_CONFIG_NAME:-"no_DESKTOP_ENVIRONMENT_CONFIG_NAME_set"}"
	artifact_input_variables[DESKTOP_APPGROUPS_SELECTED]="${DESKTOP_APPGROUPS_SELECTED:-"no_DESKTOP_APPGROUPS_SELECTED_set"}"
}

function artifact_armbian-desktop_prepare_version() {
	: "${RELEASE:?RELEASE is not set}"

	: "${DESKTOP_ENVIRONMENT:?DESKTOP_ENVIRONMENT is not set}"
	: "${DESKTOP_ENVIRONMENT_CONFIG_NAME:?DESKTOP_ENVIRONMENT_CONFIG_NAME is not set}" # Not keyed, but required.

	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4

	declare fake_unchanging_base_version="1"

	# Hash variables that affect the contents of desktop package
	declare -a vars_to_hash=(
		"${AGGREGATED_DESKTOP_POSTINST}"
		"${AGGREGATED_DESKTOP_CREATE_DESKTOP_PACKAGE}"
		"${AGGREGATED_PACKAGES_DESKTOP_COMMA}"
	)
	declare hash_variables="undetermined"                                        # will be set by calculate_hash_for_variables()...
	do_normalize_src_path="no" calculate_hash_for_variables "${vars_to_hash[@]}" # ... where do_normalize_src_path="yes" is the default
	declare var_config_hash_short="${hash_variables:0:${short_hash_size}}"

	# get the hashes of the lib/ bash sources involved...
	declare hash_files="undetermined"
	calculate_hash_for_bash_deb_artifact "compilation/packages/armbian-desktop-deb.sh"
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${fake_unchanging_base_version}-V${var_config_hash_short}-B${bash_hash_short}"

	declare desktop_appgroups_id="undetermined"
	get_desktop_appgroups_id # in config-desktop.sh

	declare -a reasons=(
		"Armbian armbian-desktop"
		"vars hash \"${vars_config_hash}\""
		"framework bash hash \"${bash_hash}\""
		"desktop environment \"${DESKTOP_ENVIRONMENT}\""
		"distro release \"${RELEASE}\""
		"desktop config_name \"${DESKTOP_ENVIRONMENT_CONFIG_NAME:-"no_DESKTOP_ENVIRONMENT_CONFIG_NAME_set"}\""
		"desktop appgroups \"${DESKTOP_APPGROUPS_SELECTED:-"no_DESKTOP_APPGROUPS_SELECTED_set"}\""
		"desktop appgroups id \"${desktop_appgroups_id}\""
	)

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_name="armbian-${RELEASE}-desktop-${DESKTOP_ENVIRONMENT}${desktop_appgroups_id}"
	artifact_type="deb"
	artifact_deb_repo="${RELEASE}"
	artifact_deb_arch="all"

	artifact_map_packages=(["armbian-desktop"]="${artifact_name}")

	return 0
}

function artifact_armbian-desktop_build_from_sources() {
	LOG_SECTION="compile_armbian-desktop" do_with_logging compile_armbian-desktop
}

function artifact_armbian-desktop_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_armbian-desktop_cli_adapter_config_prep() {
	: "${RELEASE:?RELEASE is not set}"
	: "${DESKTOP_ENVIRONMENT:?DESKTOP_ENVIRONMENT is not set}"
	: "${DESKTOP_ENVIRONMENT_CONFIG_NAME:?DESKTOP_ENVIRONMENT_CONFIG_NAME is not set}"

	# this requires aggregation, and thus RELEASE, but also everything else.
	declare -g artifact_version_requires_aggregation="yes"
	use_board="yes" allow_no_family="no" skip_kernel="no" prep_conf_main_only_rootfs_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_armbian-desktop_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/os/"
}

function artifact_armbian-desktop_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_armbian-desktop_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_armbian-desktop_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_armbian-desktop_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
