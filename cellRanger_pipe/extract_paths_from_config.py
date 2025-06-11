#!/usr/bin/env python3
# filepath: cellRanger_pipe/extract_paths_from_config.py

import sys
import csv
import re

def extract_paths(config_file):
    """Extract reference and FASTQ paths from a Cell Ranger multi config file"""
    gex_ref = None
    vdj_ref = None
    feat_ref = None
    fastq_dirs = set()
    
    with open(config_file, 'r') as f:
        content = f.read()
        
        # Extract reference paths
        gex_match = re.search(r'\[gene-expression\]\s*\nreference,(.*?)(?:\n|$)', content)
        if gex_match:
            gex_ref = gex_match.group(1).strip()
            
        vdj_match = re.search(r'\[vdj\]\s*\nreference,(.*?)(?:\n|$)', content)
        if vdj_match:
            vdj_ref = vdj_match.group(1).strip()
            
        feat_match = re.search(r'\[feature\]\s*\nreference,(.*?)(?:\n|$)', content)
        if feat_match:
            feat_ref = feat_match.group(1).strip()
        
        # Extract fastq directories
        libs_section = re.search(r'\[libraries\]\s*\n(.+?)(?=\n\s*\[|$)', content, re.DOTALL)
        if libs_section:
            lines = libs_section.group(1).strip().split('\n')
            
            # Find column index for fastqs
            header = lines[0].split(',')
            try:
                fastq_idx = header.index('fastqs')
                for line in lines[1:]:
                    if line.strip():
                        fields = line.split(',')
                        if len(fields) > fastq_idx:
                            fastq_dirs.add(fields[fastq_idx].strip())
            except ValueError:
                pass
    
    # Print results
    if gex_ref:
        print(f"gex_ref:{gex_ref}")
    if vdj_ref:
        print(f"vdj_ref:{vdj_ref}")
    if feat_ref:
        print(f"feat_ref:{feat_ref}")
    for fastq_dir in fastq_dirs:
        print(f"fastq_dir:{fastq_dir}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: extract_paths_from_config.py <config_file>")
        sys.exit(1)
    extract_paths(sys.argv[1])
