# Armbian build train JSON pipeline

```graphviz
digraph hierarchy {
nodesep = 1.0 // Increases the separation between nodes

node [fontname = Helvetica,shape = box]
edge [style = dashed]

# gha-templates pipeline
subgraph cluster_wf_template {
	label = "GHA WF Templating";
	style = filled;
	color = lightgrey;

	gha_template_number_of_chunks [shape = egg label = "Number of Chunks\n- Artifact chunks\n-Image Chunks"];
	gha_template_user_dir [shape = egg label = "Files in git\n- userpatches/gha\n- userpatches/gha/chunked"];
	gha_template_tool [shape = component label = "GHA Template\nProcessor\ngha-templates"];
	gha_workflow_from_templated [shape = doubleoctagon label = "Chunked workflow\nGitHub Actions\n(needs human to commit/push)"];
	gha_template_number_of_chunks -> gha_template_tool;
	gha_template_user_dir -> gha_template_tool;
	gha_template_tool -> gha_workflow_from_templated;
}


# main pipeline
subgraph cluster_main {
	label = "Main pipeline";
	style = filled;
	color = deepskyblue;

	config_boards [shape = egg label = "Files in git\n- config/boards\n- config/..."]

	board_inventory [shape = octagon label = "Board Inventory\nBOARD=x BRANCH=y"];

	targets_yaml [shape = egg label = "targets.yaml file\n(in userpatches)"];
	targets_compositor [shape = component label = "Targets\nCompositor"];


	config_boards -> board_inventory;
	targets_yaml -> {targets_compositor};
	targets_compositor -> {board_inventory} [label = "Queries boardXbranch inventory"];


	targets_compositor -> list_of_image_targets;

	list_of_image_targets [shape = octagon label = "List of image targets to build"];

	info_extractor [shape = component label = "Image JSON info\nextractor"];
	list_of_image_targets -> info_extractor;

	compile_sh_configdump [label = "./compile.sh config-dump @TODO"];
	info_extractor -> compile_sh_configdump [label = "runs N times\nin parallel"];
	info_extractor -> compile_sh_configdump [];
	info_extractor -> compile_sh_configdump [];
	info_extractor -> compile_sh_configdump [];
	info_extractor -> compile_sh_configdump [];


	image_targets_info_json [shape = doubleoctagon label = "JSON for all\nto-be-built image targets"];

	info_extractor -> image_targets_info_json;

	### Artifacts
	reducer_artifacts [shape = component label = "Artifact reducer"];
	image_targets_info_json -> reducer_artifacts [label = "... 2+ images with\nsame kernel..."];


	wanted_artifacts_json [shape = octagon label = "Wanted artifacts JSON"];
	reducer_artifacts -> wanted_artifacts_json [label = "... 1 kernel artifact..."];

	artifact_info_extractor [shape = component label = "Artifact JSON info\nextractor"];
	compile_sh_artifact_configdump [label = "./compile.sh artifact-config-dump @TODO"];
	artifact_info_extractor -> compile_sh_artifact_configdump [label = "runs N times\nin parallel"];
	artifact_info_extractor -> compile_sh_artifact_configdump [];
	artifact_info_extractor -> compile_sh_artifact_configdump [];
	artifact_info_extractor -> compile_sh_artifact_configdump [];

	wanted_artifacts_json -> artifact_info_extractor [label = ""];


	wanted_version_artifacts_json [shape = octagon label = "JSON for all artifacts\n- artifact_version\n - OCI coordinates"];
	artifact_info_extractor -> wanted_version_artifacts_json [label = "... '6.2.9-xxxxx'\n... 'ghcr.io/xxxx'"];


	artifact_uptodate_mapper [shape = component label = "Artifact OCI up-to-date mapper"];
	wanted_version_artifacts_json -> artifact_uptodate_mapper [label = ""];

	oci_registry [shape = cylinder label = "OCI registry\nghcr.io"];
	artifact_uptodate_mapper -> oci_registry [label = "check if exists\nin parallel"];
	artifact_uptodate_mapper -> oci_registry [label = ""];
	artifact_uptodate_mapper -> oci_registry [label = ""];
	artifact_uptodate_mapper -> oci_registry [label = ""];


	outdated_version_artifacts_json [shape = tripleoctagon label = "JSON for all artifacts\n- artifact_version\n - OCI coordinates\n - up-to-date: yes/no"];

	artifact_uptodate_mapper -> outdated_version_artifacts_json [label = ""];


	## Images
	reducer_images [shape = component label = "Image + outdated Artifacts reducer"];
	image_targets_info_json -> reducer_images;


	outdated_images_json [shape = doubleoctagon label = "JSON for all outdated images\nand artifacts"];
	reducer_images -> outdated_images_json;

	outdated_version_artifacts_json -> reducer_images;

}

# output pipeline
subgraph cluster_output {
	label = "CI Output Pipeline";
	style = filled;
	color = gold;

	#csv_export[label="CSV exporter"];
	gha_matrix_artifacts [shape = tripleoctagon label = "GHA - JSON matrix for artifacts\n(chunked)"];

	gha_matrix_image [shape = tripleoctagon label = "GHA - JSON matrix for images\n(chunked)"];


	gha_matrix_generator [shape = component label = "GHA Matrix Output"];

	outdated_images_json -> gha_matrix_generator;

	gha_matrix_generator -> gha_matrix_artifacts;

	gha_matrix_generator -> gha_matrix_image;


	# Future stuff...
	outdated_images_json -> jenkins_generator;
	jenkins_generator [shape = component label = "(future)\nJenkins output"];

	outdated_images_json -> gitlab_generator;
	gitlab_generator [shape = component label = "(future)\nGitLab output"];
}

subgraph cluster_debs {
	label = "Debs/Repo";
	style = filled;
	color = green;

	# debs-to-repo
	outdated_images_json -> debs_to_repo_generator;
	debs_to_repo_generator [shape = component label = "Process .deb artifact\ninfo into repository\ninfo"];

	deb_repo_info_json [shape = tripleoctagon label = "Repository .debs JSON\n(generic/not-tool-specific)"];
	debs_to_repo_generator -> deb_repo_info_json;

	# download-debs
	deb_repo_info_json -> debs_download_tool;
	debs_download_tool [shape = component label = ".deb download tool\n(from OCI to output/debs)"];
	debs_download_tool -> downloaded_debs;
	downloaded_debs [shape = tripleoctagon label = "All .debs downloaded\nto output/debs"];

	# aptly
	deb_repo_info_json -> debs_aptly_generator;
	debs_aptly_generator [shape = component label = "(future)\n.deb APTLY\nscript generator"];


	# reprepro
	deb_repo_info_json -> debs_reprepro_generator;
	debs_reprepro_generator [shape = component label = ".deb REPREPRO\nscript generator"];

	debs_reprepro_generator -> debs_reprepro_script;
	debs_reprepro_script [shape = tripleoctagon label = "reprepro.sh script\nready to run"];

	# repo exists and works
	debs_reprepro_script -> repo_exists_and_works;
	downloaded_debs -> repo_exists_and_works;
	repo_exists_and_works [shape = tripleoctagon label = "apt repo"];
}


}
```
