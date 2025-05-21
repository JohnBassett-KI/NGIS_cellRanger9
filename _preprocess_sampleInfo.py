#!/usr/bin/env python3
import os
import glob
import sys
import yaml

# Function to load NGIS directories from config.yaml
def load_config(config_path="config.yaml"):
    """Load configuration from YAML file"""
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        return config
    except Exception as e:
        print(f"Error loading config file {config_path}: {e}", file=sys.stderr)
        sys.exit(1)

LIB_SUFFIXES = {"ADT", "GEX", "VDJ"}

def normalize_header(s):
    """Normalize header text so that 'User ID', 'user_id', etc. all become 'userid'."""
    return s.lower().replace(" ", "").replace("_", "")

def discover_sample_dirs(ngis_dirs):
    """
    1) Prints out which sample_info file is being used,
       and the final mapping of sample → ngis_dir.
    2) Returns a list of dicts:
         [ {"sample": "Foo", "ngis_dir": "/path/to/run"}, … ]
    """
    sample_dirs = {}
    # 1) scan each run root
    for run_name, root_path in ngis_dirs.items():
        pattern = os.path.join(root_path, "**", "*sample_info.txt")
        info_files = glob.glob(pattern, recursive=True)
        if not info_files:
            print(f"Warning: no *sample_info.txt found under {root_path}", file=sys.stderr)
            continue

        sample_info = info_files[0]
        print(f"\nUsing sample_info: {sample_info}")

        with open(sample_info, 'r') as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue

                cols = line.split("\t")
                if len(cols) < 2:
                    print(f"  Skipping malformed line: {line}", file=sys.stderr)
                    continue

                raw_name = cols[1]
                # skip any header line (User ID, user_id, etc.)
                if normalize_header(raw_name) == "userid":
                    continue

                # clean spaces → underscores
                clean_name = raw_name.strip().replace(" ", "_")
                # strip off ADT/GEX/VDJ suffix if present
                parts = clean_name.rsplit("_", 1)
                if len(parts) == 2 and parts[1] in LIB_SUFFIXES:
                    sample = parts[0]
                else:
                    sample = clean_name

                # record once, pointing back at the run root
                if sample not in sample_dirs:
                    sample_dirs[sample] = root_path

    # print the final mapping for logs
    print("\nformat = sample_id: location found")
    print("=== Discovered samples ===")
    if not sample_dirs:
        print("  (none found)", file=sys.stderr)
    else:
        for sample, path in sorted(sample_dirs.items()):
            print(f"{sample}: {path}")

    print("==============================\n")

    # build and return the list of dicts
    return [
        {"sample_id": sample, "ngis_dir": path}
        for sample, path in sorted(sample_dirs.items())
    ]

def main():
    # Load the config file
    config = load_config()
    
    # Extract NGIS_dirs from config
    NGIS_dirs = config.get('input', {}).get('NGIS_dirs', {})
    
    if not NGIS_dirs:
        print("Error: No NGIS_dirs found in config file", file=sys.stderr)
        sys.exit(1)
    
    # Print which NGIS directories we're using
    print("\nUsing NGIS directories from config:")
    for name, path in NGIS_dirs.items():
        print(f"  {name}: {path}")
    
    # call the function (which will do all the printing)
    samples_list = discover_sample_dirs(NGIS_dirs)

    #pringt statements for understanding variables if needed
    #print(samples_list)
    #print("")
    #samples = [d["sample_id"] for d in samples_list]
    #print(samples)
if __name__ == "__main__":
    main()


