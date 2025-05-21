#!/usr/bin/env python3
import os
import sys
import yaml
import re

# Import from parent directory
from _preprocess_sampleInfo import discover_sample_dirs

def load_config(config_path="config.yaml"):
    """Load configuration from specified YAML file"""
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        return config
    except Exception as e:
        print(f"Error loading config file {config_path}: {e}", file=sys.stderr)
        sys.exit(1)

def get_samples_by_seqrun(NGIS_dirs):
    """
    Group samples by sequencing run based on the NGIS directories
    
    Args:
        NGIS_dirs: Dictionary of run names to directory paths
        
    Returns:
        Dictionary mapping run names to lists of sample IDs
    """
    if not NGIS_dirs:
        print("Error: No NGIS_dirs provided", file=sys.stderr)
        return {}
    
    # Get sample information using the discover_sample_dirs function
    sample_info_list = discover_sample_dirs(NGIS_dirs)
    
    # Group samples by seqrun
    samples_by_seqrun = {}
    for d in sample_info_list:
        # Find which sequencing run this sample belongs to
        seqrun = next((run for run, path in NGIS_dirs.items() if path == d["ngis_dir"]), None)
        if seqrun:
            # Add this sample to the appropriate run list
            samples_by_seqrun.setdefault(seqrun, []).append(d["sample_id"])
    
    return samples_by_seqrun

def build_aggregate_info(donors, origins, sample_overrides, outs_dir, experiment, samples_by_seqrun):
    """
    Build detailed information for sample aggregation.
    
    Args:
        donors: List of donor names to look for in sample_ids
        origins: List of origin identifiers to look for in sample_ids
        sample_overrides: Dictionary of sample_id overrides for donor/origin info
        outs_dir: Output base directory path
        experiment: Experiment name for path construction
        samples_by_seqrun: Dictionary mapping seqruns to sample lists
        
    Returns:
        List of tuples: (sample_id, sample_outs, donor, origin)
    """
    aggregate_info = []
    
    # Process each sample
    for seqrun, samples in samples_by_seqrun.items():
        for sample_id in samples:
            # Case 2: Check if this sample has an override entry
            if sample_id in sample_overrides:
                donor = sample_overrides[sample_id].get('donor', '')
                origin = sample_overrides[sample_id].get('origin', '')
            
            # Case 1: Try to extract donor and origin from sample_id
            else:
                # Try to match donors from the config
                donor = None
                for d in donors:
                    # Use case-insensitive comparison
                    if d.lower() in sample_id.lower():
                        donor = d
                        break
                        
                # Try to match origins from the config
                origin = None
                for o in origins:
                    # Use case-insensitive comparison
                    if o.lower() in sample_id.lower():
                        origin = o
                        break
            
            # Skip if donor or origin cannot be determined
            if not donor or not origin:
                print(f"\nOmitting {sample_id}.")
                print(f"Reason: missing donor or origin information. Use sample_override in config if needed.")
                continue
                
            # Construct the output path
            sample_outs = os.path.join(
                outs_dir,
                experiment,
                "cellranger_outs", 
                seqrun,
                sample_id,
                "outs",
                "per_sample_outs",
                sample_id
            )
            
            # Add to our results
            aggregate_info.append((sample_id, sample_outs, donor, origin))
    
    return aggregate_info

def print_aggregate_info(aggregate_info):
    """Print formatted aggregate information grouped by donor and origin"""
    print("\n=== Samples for Aggregation ===")
    if not aggregate_info:
        print("  (none found)")
    else:
        # First, group by donor
        by_donor = {}
        for sample_id, sample_outs, donor, origin in aggregate_info:
            # Create nested structure: donor -> origin -> [(sample_id, sample_outs)]
            if donor not in by_donor:
                by_donor[donor] = {}
            
            # Add this sample to the appropriate origin within this donor
            origin_samples = by_donor[donor].setdefault(origin, [])
            origin_samples.append((sample_id, sample_outs))
        
        # Print results in hierarchical format
        for donor in sorted(by_donor.keys()):
            print(f"\nDonor: {donor}")
            for origin in sorted(by_donor[donor].keys()):
                print(f"  -Origin: {origin}")
                for sample_id, sample_outs in sorted(by_donor[donor][origin]):
                    print(f"    --Sample ID: {sample_id}")
                    #print(f"    --Outs path: {sample_outs}\n")

def main():
    """Run the full preflight check process using config.yaml"""
    # Load the configuration
    config = load_config()
    
    # Extract relevant variables from config
    NGIS_dirs = config.get('input', {}).get('NGIS_dirs', {})
    donors = config.get('cellranger_aggregate', {}).get('donors', [])
    origins = config.get('cellranger_aggregate', {}).get('origin', [])
    sample_overrides = config.get('sample_override', {})
    outs_dir = config.get('output', {}).get('outs_dir', '')
    experiment = config.get('output', {}).get('experiment', '')
    
    # Get samples grouped by sequencing run
    samples_by_seqrun = get_samples_by_seqrun(NGIS_dirs)
    
    # Print the samples by run
    print("\n=== Samples by Sequencing Run ===")
    for run, samples in samples_by_seqrun.items():
        print(f"\n{run}:")
        for sample in sorted(samples):
            print(f"  - {sample}")
    
    # Build aggregate information
    aggregate_info = build_aggregate_info(
        donors, origins, sample_overrides, outs_dir, experiment, samples_by_seqrun
    )
    
    # Print the aggregate information
    print_aggregate_info(aggregate_info)
    
    # Return all the collected data
    return {
        "samples_by_seqrun": samples_by_seqrun,
        "aggregate_info": aggregate_info
    }

if __name__ == "__main__":
    result = main()
