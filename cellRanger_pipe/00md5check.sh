#!/bin/bash
#This file may experience I/O bottlenecks running many md5 checks in parallel.

# Fail fast on errors, unset vars, broken pipelines
set -euo pipefail

# Ensure the variable exists even when the script is run
# outside a SLURM allocation (e.g. local test run)
: "${SLURM_CPUS_PER_TASK:=1}"

#load GNU parallel
module load bioinfo-tools
module load gnuparallel/20230422

################################################################
#Parse Arguments
################################################################
#User can supply a directory using the argument option -d or --directory
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--directory)
      target_dir="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-d|--directory <path>]"
      echo
      echo "This script recursively finds and verifies all .md5 checksum files"
      echo "in the specified directory. If no directory is provided, it uses the default:"
      echo "  $target_dir"
      echo
      echo "Options:"
      echo "  -d, --directory   Specify an alternate directory"
      echo "  -h, --help        Show this help message and exit"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information."
      exit 1
      ;;

  esac
done
################################################################
#Check if target directory contains any md5 files. If not exit.
################################################################
md5_count=$(find "$target_dir" -type f -name "*.md5" | wc -l)

if [[ "$md5_count" -eq 0 ]]; then
    echo "No .md5 files found in $target_dir"
    exit 1
fi

echo "Located $md5_count .md5 files"
################################################################
#Function check_md5: check a single md5 file
################################################################
check_md5() {
	local md5file="$1"
	local dir
	dir=$(dirname "$md5file")
	#change to the directory and run md5sum on the file basename
	cd "$dir" && md5sum -c "$(basename "$md5file")"
}

export -f check_md5

################################################################
#Run the MD5 checks in parallel with GNU parallel
################################################################
find "$target_dir" -type f -name "*.md5" | parallel --jobs "$SLURM_CPUS_PER_TASK" check_md5 {}
#capture status from parallel
status=$?

################################################################
#Return status and exit
################################################################
if [[ $status -ne 0 ]]; then
  echo "One or more checksum verifications failed."
  exit 1
else
  echo "All files passed checksum verification."
  exit 0
fi
#!/bin/bash
#This file may experience I/O bottlenecks running many md5 checks in parallel.

# Fail fast on errors, unset vars, broken pipelines
set -euo pipefail

# Ensure the variable exists even when the script is run
# outside a SLURM allocation (e.g. local test run)
: "${SLURM_CPUS_PER_TASK:=1}"

#load GNU parallel
module load bioinfo-tools
module load gnuparallel/20230422

################################################################
#Parse Arguments
################################################################
#User can supply a directory using the argument option -d or --directory
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--directory)
      target_dir="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-d|--directory <path>]"
      echo
      echo "This script recursively finds and verifies all .md5 checksum files"
      echo "in the specified directory. If no directory is provided, it uses the default:"
      echo "  $target_dir"
      echo
      echo "Options:"
      echo "  -d, --directory   Specify an alternate directory"
      echo "  -h, --help        Show this help message and exit"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information."
      exit 1
      ;;

  esac
done
################################################################
#Check if target directory contains any md5 files. If not exit.
################################################################
md5_count=$(find "$target_dir" -type f -name "*.md5" | wc -l)

if [[ "$md5_count" -eq 0 ]]; then
    echo "No .md5 files found in $target_dir"
    exit 1
fi

echo "Located $md5_count .md5 files"
################################################################
#Function check_md5: check a single md5 file
################################################################
check_md5() {
	local md5file="$1"
	local dir
	dir=$(dirname "$md5file")
	#change to the directory and run md5sum on the file basename
	cd "$dir" && md5sum -c "$(basename "$md5file")"
}

export -f check_md5

################################################################
#Run the MD5 checks in parallel with GNU parallel
################################################################
find "$target_dir" -type f -name "*.md5" | parallel --jobs "$SLURM_CPUS_PER_TASK" check_md5 {}
#capture status from parallel
status=$?

################################################################
#Return status and exit
################################################################
if [[ $status -ne 0 ]]; then
  echo "One or more checksum verifications failed."
  exit 1
else
  echo "All files passed checksum verification."
  exit 0
fi

