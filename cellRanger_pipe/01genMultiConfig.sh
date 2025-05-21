#!/bin/bash

# Parse arguments
while getopts "s:d:o:g:v:f:l:" opt; do
    case $opt in
        s) sample="$OPTARG" ;;
        d) file_dir="$OPTARG" ;;
        o) output_dir="$OPTARG" ;;
        g) gex_ref="$OPTARG" ;;
        v) vdj_ref="$OPTARG" ;;
        f) feat_ref="$OPTARG" ;;
        l) lane_option="$OPTARG" ;;
        *) echo "Usage: $0 -s <sample> -d <input_directory> -o <output_directory> -g <gex_ref> -v <vdj_ref> -f <feat_ref> -l <lane_option>" >&2; exit 1 ;;
    esac
done

# Ensure required arguments are provided
if [ -z "$sample" ] || [ -z "$file_dir" ] || [ -z "$output_dir" ] || [ -z "$gex_ref" ] || [ -z "$vdj_ref" ] || [ -z "$feat_ref" ]; then
    echo "Error: Missing required arguments." >&2
    echo "Usage: $0 -s <sample> -d <input_directory> -o <output_directory> -g <gex_ref> -v <vdj_ref> -f <feat_ref> -l <lane_option>" >&2
    exit 1
fi

# Default lane option to "ALL" if not provided
lane_option="${lane_option:-ALL}"

# Ensure output directory exists
mkdir -p "$output_dir"

# Handle lane options
if [[ "$lane_option" == "ALL" ]]; then
    gex_lanes="ALL"
    vdj_lanes="ALL"
    adt_lanes="ALL"
elif [[ "$lane_option" == "extract" ]]; then
    # Lanes will be extracted dynamically later
    extract_lanes=true
else
    # Parse the custom lane string
    IFS=',' read -r gex_lanes vdj_lanes adt_lanes <<< "$lane_option"
    if [ -z "$gex_lanes" ] || [ -z "$vdj_lanes" ] || [ -z "$adt_lanes" ]; then
        echo "Error: Invalid lane string. Must contain exactly three comma-separated values." >&2
        exit 1
    fi
fi

# FUNCTION extract lane information and associate it with the directory
extract_lane_info() {
    local dir="$1"

    local filename
    local lane
    local output
    local file
    declare -a lanes=()

    # Iterate over each FASTQ file in the directory
    for file in "$dir"/*.fastq.gz; do
        # Skip if no matching files exist
        [ -e "$file" ] || continue

        filename=$(basename "$file")

        # Extract the lane number using the _L00X_ naming convention
        lane=$(echo "$filename" | sed -n 's/.*_L0*\([1-9][0-9]*\)_.*/\1/p')

        # If a lane is found and it's not already in the array, add it
        if [[ -n "$lane" ]]; then
            if [[ ! " ${lanes[@]} " =~ " ${lane} " ]]; then
                lanes+=("$lane")
            fi
        fi
    done

    # Set IFS to a pipe character to join the lane numbers with "|"
    local IFS="|"
    output="${lanes[*]}"
    echo "$output"
}

# FIND SAMPLE INFO FILE
sample_info=$(find "$file_dir" -type f -name "*sample_info.txt")
if [ -z "$sample_info" ]; then
    echo "File not found. Stopping execution."
    exit 1
else
    echo
    echo "Sample info located in:"
    echo " $sample_info"
    echo
fi
# Process the sample info file and store the output in a variable
processed_sample_info=$(awk -F'\t' '{
    gsub(/ /, "_", $1);
    gsub(/ /, "_", $2);
    print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5
}' "$sample_info")

# Log the processed sample info
echo " Sample Info:"
echo "$processed_sample_info"
echo

# Declare associative arrays to store NGI IDs for each experiment type
declare -A gex_ids
declare -A vdj_ids
declare -A adt_ids

# READ SAMPLE INFO FILE
while IFS=$'\t' read -r ngi_id user_id rc mreads q30 || [[ -n "$ngi_id" ]]; do
    # Skip the header line
    if [[ "$ngi_id" == "NGI_ID" ]]; then
        continue
    fi

    # Check if user_id contains the sample string
    if [[ "$user_id" == *"$sample"* ]]; then
        echo "Match found for sample: $sample in user_id: $user_id"

        # Identify the suffix and store the ngi_id and user_id as key-value pairs
                if [[ "$user_id" == *_GEX ]]; then
            gex_ids["$sample"]="$ngi_id"
            echo "Adding to gex_ids: Key=$sample, Value=$ngi_id"
        elif [[ "$user_id" == *_VDJ ]]; then
            vdj_ids["$sample"]="$ngi_id"
            echo "Adding to vdj_ids: Key=$sample, Value=$ngi_id"
        elif [[ "$user_id" == *_ADT ]]; then
            adt_ids["$sample"]="$ngi_id"
            echo "Adding to adt_ids: Key=$sample, Value=$ngi_id"
        fi
    fi
done < <(echo "$processed_sample_info")

#MAIN LOOP:
#locate fastq directories
#extract lane info from fastq file names
#write to a csv file
echo "Writing cellranger multi_config file:"
echo 
for experiment in "${!gex_ids[@]}"; do
    echo "Experiment: $experiment"

    # GEX ID fastq files
    gex_id="${gex_ids[$experiment]}"
    echo "GEX ID: $gex_id"
    gex_dir=$(find "$file_dir" -type f -name "*.fastq.gz" -path "*$gex_id*" -exec dirname {} \; | sort -u)
    if [ -n "$gex_dir" ]; then
        echo "GEX Directory: $gex_dir"
    else
        echo "GEX Directory: Not found"
        exit 1
    fi

    # VDJ ID fastq files
    vdj_id="${vdj_ids[$experiment]}"
    echo "VDJ ID: $vdj_id"
    #find the directory which contains fastq files and has vdj_ids[$experiment] in the path
    vdj_dir=$(find "$file_dir" -type f -name "*.fastq.gz" -path "*$vdj_id*" -exec dirname {} \; | sort -u)
    if [ -n "$vdj_dir" ]; then
        echo "VDJ Directory: $vdj_dir"
    else
        echo "VDJ Directory: Not found"
        exit 1
    fi
    # ADT ID fastq files
    adt_id="${adt_ids[$experiment]}"
    echo "ADT ID: $adt_id"
    adt_dir=$(find "$file_dir" -type f -name "*.fastq.gz" -path "*$adt_id*" -exec dirname {} \; | sort -u)
    if [ -n "$adt_dir" ]; then
        echo "ADT Directory: $adt_dir"
    else
        echo "ADT Directory: Not found"
        exit 1
    fi

    echo


# Extract lane information dynamically if "extract" is specified
    if [[ "$extract_lanes" == true ]]; then
        gex_lanes=($(extract_lane_info "$gex_dir"))
        vdj_lanes=($(extract_lane_info "$vdj_dir"))
        adt_lanes=($(extract_lane_info "$adt_dir"))
    fi

    #print stored lane information
    echo " GEX Lanes: ${gex_lanes[@]}"
    echo " VDJ Lanes: ${vdj_lanes[@]}"
    echo " ADT Lanes: ${adt_lanes[@]}"
    echo

    echo
    echo "Writing multiconfig file for $experiment"
    echo

    output_file="${output_dir}/multi_config_${experiment}.csv"     #write to cellranger multi config file
    {
    echo "[gene-expression]"
    echo "reference,$gex_ref"
    echo "create-bam,false"
    echo
    echo "[vdj]"
    echo "reference,$vdj_ref"
    echo
    echo "[feature]"
    echo "reference,$feat_ref"
    echo
    echo "[libraries]"
    if [[ "$lane_option" == "ALL" ]]; then
        echo "fastq_id,fastqs,feature_types"
        echo "$gex_id,$gex_dir,Gene Expression"
        echo "$vdj_id,$vdj_dir,VDJ-T"
        echo "$adt_id,$adt_dir,Antibody Capture"
    else
        echo "fastq_id,fastqs,lanes,feature_types"
        echo "$gex_id,$gex_dir,$gex_lanes,Gene Expression"
        echo "$vdj_id,$vdj_dir,$vdj_lanes,VDJ-T"
        echo "$adt_id,$adt_dir,$adt_lanes,Antibody Capture"
    fi
    } > "$output_file"
    echo "CSV file '$output_file' created successfully."
    echo
done
