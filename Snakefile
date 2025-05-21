import os
import sys
import datetime
from _preprocess_sampleInfo import discover_sample_dirs

localrules: init

# Load configuration
NGIS_dirs   = config["input"]["NGIS_dirs"]
experiment = config["output"]["experiment"]
outs_dir   = config["output"]["outs_dir"]

# Timestamp for logs in format: YYYY-MM-DD_HH:MM:SS
timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H:%M:%S")

# Sequencing runs (keys from NGIS_dirs)
seqrun_list = list(NGIS_dirs.keys())

# Preprocess sample_info files to get cleaned sample names
# and map each sample back to its NGIS run directory
sample_info_list = discover_sample_dirs(NGIS_dirs)
samples         = [d["sample_id"] for d in sample_info_list]
# Group samples by seqrun
samples_by_seqrun = {}
for d in sample_info_list:
    seqrun = next((run for run, path in NGIS_dirs.items() if path == d["ngis_dir"]), None)
    if seqrun:
        samples_by_seqrun.setdefault(seqrun, []).append(d["sample_id"])

# predefine file structure (For readability)
# Base directories
exp_base         = f"{outs_dir}/{experiment}"
logs_dir         = f"{exp_base}/logs"
# cellRangerMulti directories
multi_config_dir = f"{exp_base}/multi_config"
cellranger_outs  = f"{exp_base}/cellranger_outs"

# Final target: one checksum per run, one multiconfig per sample, cellRanger outputs for each sample
rule all:
    input:
        # Checksums for each sequencing run
        expand(f"{logs_dir}/{{seqrun}}/check_sums.done", seqrun=seqrun_list),
        # Multiconfig files for each sample
        [
            f"{multi_config_dir}/{seqrun}/multi_config_{sample_id}.csv"
            for seqrun, sample_ids in samples_by_seqrun.items()
            for sample_id in sample_ids
        ],
        # Cellranger outputs for each sample
        [
            f"{logs_dir}/{seqrun}/cellranger_{sample_id}.done"
            for seqrun, sample_ids in samples_by_seqrun.items()
            for sample_id in sample_ids
        ]
# Rule: init
# Initializes the file structure
# and touches a per-sequencing run initialization flag file in the logs folder.
rule init:
    output:
        init_done = f"{logs_dir}/{{seqrun}}/init.done"
    params:
        ts = timestamp,
        logs_seqrun = f"{logs_dir}/{{seqrun}}"
    shell:
        """
        mkdir -p {params.logs_seqrun}
        echo "{params.ts}" > {output.init_done}
        """

# Rule: check_sums
# Runs MD5 checksum checks on the NGIS directory for each sequencing run.
# Depends on the init rule to ensure the logs directory is set up.
rule check_sums:
    input:
        NGIS_dir  = lambda wc: NGIS_dirs[wc.seqrun],
        init_done = rules.init.output.init_done
    output:
        log_flag = f"{logs_dir}/{{seqrun}}/check_sums.done"
    log:
        f"{logs_dir}/{{seqrun}}/check_sums.log"
    params:
        script = "cellRanger_pipe/00md5check.sh"
    threads: 8
    resources:
        partition="core",
        time="00:30:00",
    shell:
        """
        # Run checksum script and create flag only on success
        bash {params.script} -d {input.NGIS_dir} > {log} 2>&1 && touch {output.log_flag}
        """

# Rule: gen_multi_config
# Generates a configuration file for each sample using the NGIS directory.
# This rule depends on the check_sums rule to ensure checksums are done before generating configs.
rule gen_multi_config:
    input:
        check_sums = lambda wc: f"{logs_dir}/{wc.seqrun}/check_sums.done",
        NGIS_dir   = lambda wc: NGIS_dirs[wc.seqrun]
    output:
        config_file = f"{multi_config_dir}/{{seqrun}}/multi_config_{{sample_id}}.csv"
    log:
        f"{logs_dir}/{{seqrun}}/multi_config_{{sample_id}}.log"
    params:
        script     = "cellRanger_pipe/01genMultiConfig.sh",
        output_dir = f"{multi_config_dir}/{{seqrun}}",
        gex_ref    = config["input"]["refs"]["gex_ref"],
        vdj_ref    = config["input"]["refs"]["vdj_ref"],
        feat_ref   = config["input"]["refs"]["feat_ref"],
        lanes      = config["input"].get("lanes", "ALL")
    threads: 1
    resources:
        partition="core",  
        time="00:20:00"
    shell:
        """
        mkdir -p {params.output_dir}
        bash {params.script} -s {wildcards.sample_id} -d {input.NGIS_dir} -o {params.output_dir} \
            -g {params.gex_ref} -v {params.vdj_ref} -f {params.feat_ref} -l {params.lanes} > {log} 2>&1
        """

# Rule: cellRanger_multi
# Runs cellRanger using the generated configuration file from gen_multi_config.
#       NOTE: Snakemake automatically creates output directory if it does not exist. Cell ranger will not
#       output to a specified directory if it already exists. Cell ranger outputs are therefore 
#       generated in a tmp dir and moved to their file location.
rule cellranger_multi:
    input:
        config_file = f"{multi_config_dir}/{{seqrun}}/multi_config_{{sample_id}}.csv",
        container = os.path.abspath("cellRanger_apptainer/cellRanger_v9.0.1.sif")
    output:
        flag = f"{logs_dir}/{{seqrun}}/cellranger_{{sample_id}}.done"
    log:
        f"{logs_dir}/{{seqrun}}/cellranger_{{sample_id}}.log"
    params:
        outdir      = f"{exp_base}/cellranger_outs/{{seqrun}}/{{sample_id}}",
        out_tmp_dir = f"{exp_base}/cellranger_outs/{{seqrun}}/{{sample_id}}_tmp",
        status_cellranger = "cellRanger_pipe/_check_cellranger_status.py", #script to check cellRanger completion status
        gb_divisor = 1024,  # Cellranger's definition of GB
    threads: 16
    resources:
        partition="node",
        time="48:00:00",
        mem_mb=109300 # Memory Ceiling for Bianca Node is 117000 MB, Max available for Cellranger=109465
    shell:
        """
        set -e  # Exit on error

        # Check if completed output exists already
        if [ -d "{params.outdir}/outs/" ]; then
            echo "Detected existing Cell Ranger output in {params.outdir}. Skipping." >> {log} 2>&1
            exit 0
        fi  

        # Print debug info to log
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting cellranger multi run" >> {log} 2>&1
        echo "Sample ID: {wildcards.sample_id}" >> {log} 2>&1
        echo "Config file: {input.config_file}" >> {log} 2>&1
        echo "Output directory: {params.outdir}" >> {log} 2>&1
        echo "Container: {input.container}" >> {log} 2>&1
        echo "Threads: {threads}" >> {log} 2>&1
        echo "Memory: {resources.mem_mb} MB" >> {log} 2>&1
        echo "---------------------------------" >> {log} 2>&1        

	# Create parent of output directory if it doesn't exist
        mkdir -p "$(dirname {params.out_tmp_dir})"

        # Run cellranger multi
        apptainer exec {input.container} cellranger multi \
            --id={wildcards.sample_id} \
            --csv={input.config_file} \
            --output-dir={params.out_tmp_dir} \
            --localcores={threads} \
            --localmem=$(({resources.mem_mb}/{params.gb_divisor})) 2>&1 | tee -a {log}

        # Move to final location
        mv {params.out_tmp_dir} {params.outdir}
        
        # Check if cell ranger completed successfully
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking Cell Ranger completion status..." >> {log} 2>&1
        python3 {params.status_cellranger} "{params.outdir}" >> {log} 2>&1
        exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cell Ranger run failed with exit code $exit_code" >> {log} 2>&1
            exit 1
        fi

        # Create our flag file to mark successful completion
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Run completed successfully" >> {log} 2>&1
        touch {output.flag}
        """

