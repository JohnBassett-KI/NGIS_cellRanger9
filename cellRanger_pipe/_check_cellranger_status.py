import os
import sys
import glob

# Default directory to check if no argument is provided
outdir = "empty"

def check_cellranger_status(outdir, print_log_on_fail=True):
    """
    Checks the status of a Cell Ranger pipeline in `outdir` by examining log files.
    Returns: ('complete'|'failed'|'unknown', exit_code)
    """
    # Check if outdir is a valid directory
    if not os.path.isdir(outdir):
        print(f"Error: Output directory '{outdir}' does not exist")
        return "unknown", 1
    
    # Find log files in the output directory
    #If log file does not exist, return unknown status -ADD THIS
    log_file = os.path.join(outdir, "_log")
    # Check if log file exists
    if not os.path.isfile(log_file):
        print(f"Error: Log file not found at {log_file}")

    # Open the log file and check for success or failure messages
    try:
        # Read the file from the bottom up, as status messages are usually at the end
        success_found = False
        failed_found = False
        error_message = ""
        
        with open(log_file, 'r') as f:
            # Read last 100 lines (adjust as needed)
            lines = f.readlines()
            last_lines = lines[-100:] if len(lines) > 100 else lines
            
            # Search from the end
            for line in reversed(last_lines):
                if "Pipestance completed successfully!" in line:
                    success_found = True
                    break
                elif "Pipestance failed" in line:
                    failed_found = True
                    # Capture 10 lines BEFORE failure for context
                    error_index = last_lines.index(line)
                    # Calculate start index (don't go below 0)
                    start_index = max(0, error_index - 10)
                    error_message = ''.join(last_lines[start_index:error_index+1])
                    break
        
        if success_found:
            print(f"Cell Ranger run in {outdir} completed successfully")
            return "complete", 0
        elif failed_found:
            error_msg = f"Cell Ranger run in {outdir} failed"
            if print_log_on_fail and error_message:
                error_msg += f"\nError details:\n{error_message}"
            print(error_msg)
            return "failed", 1
        else:
            print(f"Cell Ranger run status unknown - no completion message found in logs")
            return "unknown", 1
                
    except IOError as e:
        print(f"Error: Failed to read log file: {e}")
        return "unknown", 1

# Run this function when script is executed directly
if __name__ == "__main__":    
    # Use command line argument if provided, otherwise use default outdir
    dir_to_check = sys.argv[1] if len(sys.argv) > 1 else outdir
    status, exit_code = check_cellranger_status(dir_to_check)
    sys.exit(exit_code)

