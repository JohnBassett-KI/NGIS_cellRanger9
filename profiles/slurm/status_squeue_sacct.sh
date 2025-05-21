#!/usr/bin/env bash
###############################################################################
# status_squeue_sacct.sh
#
# Usage:  status_squeue_sacct.sh <jobid>
# Prints one of the keywords expected by Snakemake’s cluster-generic executor:
#     running   – job is still in squeue   (or sacct shows it is not finished)
#     success   – sacct reports COMPLETED
#     failed    – sacct reports any error / cancel / timeout state
#
# Works on UPPMAX and any SLURM site with slurmdbd enabled.
###############################################################################

#!/usr/bin/env bash
set -euo pipefail

id="$1"
log_file="/tmp/snakemake_status_${id}.log"

# Log function for debugging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$log_file"
}

log "Checking status for job $id"

# 1. Check squeue
state=$(squeue -h -o %T -j "$id" 2>/dev/null || echo "NOT_FOUND")
state=$(echo "$state" | tr -d '[:space:]')  # Clean any whitespace
log "squeue state: '$state'"

# 2. If not in queue or empty string, check sacct
if [[ -z "$state" || "$state" == "NOT_FOUND" ]]; then
    state=$(sacct -X -n -o State -j "$id" 2>/dev/null | head -n1 | tr -d '[:space:]')
    log "sacct state: '$state'"
fi

# 3. Map states to Snakemake keywords
case "$state" in
    RUNNING|PENDING|CONFIGURING|COMPLETING|SUSPENDED)
        log "Return: running"
        echo "running"
        ;;
    COMPLETED)
        log "Return: success"
        echo "success"
        ;;
    CANCELLED*|FAILED*|TIMEOUT*|NODE_FAIL*|OUT_OF_MEMORY*|PREEMPTED*)
        log "Return: failed"
        echo "failed"
        ;;
    NOT_FOUND)
        # If job is not found in either squeue or sacct, consider it failed
        log "Return: failed (job not found)"
        echo "failed"
        ;;
    *)
        # Log unknown states but still return running
        log "Warning: Unknown state '$state', returning running"
        echo "running"
        ;;
esac
