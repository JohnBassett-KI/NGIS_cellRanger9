#!/usr/bin/env python3
import os
import csv
import sys
import json

def writeAggrCsv(aggregate_info, experiment_name, output_dir="."):
    """
    Generate a CSV file for cellRanger aggregation using the provided aggregate_info.
    
    Args:
        aggregate_info: List of tuples/lists (sample_id, sample_outs, donor, origin)
        experiment_name: Name of the experiment (used for output filename)
        output_dir: Directory to write the CSV file to (default: current directory)
    
    Returns:
        Path to the generated CSV file
    """
    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    # Define the output filename with path
    output_file = os.path.join(output_dir, f"{experiment_name}_aggr.csv")
    
    try:
        # Check if aggregate_info is empty
        if not aggregate_info:
            print(f"Warning: No samples to aggregate. Empty CSV file will be created.", file=sys.stderr)
            exit(1) # No aggregate info throws an error
        
        # Write the CSV file
        with open(output_file, 'w', newline='') as csvfile:
            csv_writer = csv.writer(csvfile)
            
            # Write header
            csv_writer.writerow(['sample_id', 'sample_outs', 'donor', 'origin'])
            
            # Write data rows
            for entry in aggregate_info:
                # Make sure we have exactly 4 elements
                if len(entry) != 4:
                    print(f"Warning: Skipping invalid entry: {entry}", file=sys.stderr)
                    continue
                
                sample_id, sample_outs, donor, origin = entry
                
                # Check if sample_outs path exists
                if not os.path.exists(sample_outs):
                    print(f"Warning: Sample output path does not exist: {sample_outs}", file=sys.stderr)
                
                csv_writer.writerow([sample_id, sample_outs, donor, origin])
        
        print(f"Aggregation CSV file created: {output_file}")
        return output_file
        
    except Exception as e:
        print(f"Error creating aggregation CSV file: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    """
    Main function to demonstrate the use of writeAggrCsv.
    Reads from sample_info.json if available.
    """
    import argparse
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Generate cellRanger aggregation CSV file')
    parser.add_argument('--json', type=str, help='Path to sample_info.json file')
    parser.add_argument('--output', type=str, help='Name of experiment (used for output filename)')
    parser.add_argument('--dir', type=str, default=".", help='Output directory (default: current directory)')
    args = parser.parse_args()
    
    # Use command line arguments if provided
    if args.json and args.output:
        try:
            # Load sample_info.json
            with open(args.json, 'r') as f:
                sample_info = json.load(f)
            
            # Extract aggregate_info
            aggregate_info = sample_info.get("aggregate_info", [])
            
            # Write the CSV file
            output_file = writeAggrCsv(aggregate_info, args.output, args.dir)
            print(f"Successfully created {output_file}")
            
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print("Please provide both --json and --output arguments.")
        print("Example: python3 03genAggrCsv.py --json /path/to/sample_info.json --output experiment_name")
        sys.exit(1)

if __name__ == "__main__":
    main()
