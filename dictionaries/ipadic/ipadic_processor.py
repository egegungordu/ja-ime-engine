"""
MeCab IPADIC Dictionary Processor
Extracts and processes word entries from MeCab IPADIC dictionary files.

This script reads MeCab IPADIC CSV files, extracts essential word information,
and outputs it in a simplified TSV format with readings converted to hiragana.
It also processes the matrix.def file to output connection costs and char.def for character categories.
"""

import os
import glob
import argparse
import csv
import re

def process_unk_def(input_file, output_file):
    """Process the unk.def file and output the first 4 columns to TSV."""
    print(f'Processing unknown words definition file {input_file}...')
    
    try:
        with open(input_file, 'r', encoding='euc-jp', errors='replace') as f:
            csv_reader = csv.reader(f)
            with open(output_file, 'w', encoding='utf-8') as outfile:
                for row in csv_reader:
                    if row and len(row) >= 4:
                        category = row[0]
                        left_cost = row[1]
                        right_cost = row[2]
                        cost = row[3]
                        outfile.write(f"{category}\t{left_cost}\t{right_cost}\t{cost}\n")
                            
    except Exception as e:
        print(f'Error processing unk.def file: {str(e)}')

def convert_katakana_to_hiragana(text):
    # Conversion range for katakana -> hiragana
    katakana_start = 0x30A1  # ァ
    katakana_end = 0x30F6    # ヶ
    hiragana_start = 0x3041  # ぁ
    
    # Convert each character
    converted = []
    for char in text:
        code = ord(char)
        if katakana_start <= code <= katakana_end:
            # Convert katakana to hiragana by shifting the code point
            new_code = code - katakana_start + hiragana_start
            converted.append(chr(new_code))
        else:
            converted.append(char)
    
    return ''.join(converted)

def process_char_def(input_file, categories_output, mappings_output):
    """Process the char.def file and output category definitions and mappings to separate TSV files."""
    print(f'Processing character definition file {input_file}...')
    
    try:
        with open(input_file, 'r', encoding='euc-jp', errors='replace') as f:
            lines = f.readlines()
            
        # Process category definitions
        with open(categories_output, 'w', encoding='utf-8') as outfile:
            for line in lines:
                line = line.strip()
                if line and not line.startswith('#') and not line.startswith('0x'):
                    # Remove any end-of-line comments
                    if '#' in line:
                        line = line[:line.index('#')].strip()
                    parts = line.split()
                    if len(parts) >= 4:
                        category, invoke, group, length = parts[:4]
                        outfile.write(f"{category}\t{invoke}\t{group}\t{length}\n")
        
        # Process category mappings
        with open(mappings_output, 'w', encoding='utf-8') as outfile:
            for line in lines:
                line = line.strip()
                if line.startswith('0x'):
                    # Remove any end-of-line comments
                    if '#' in line:
                        line = line[:line.index('#')].strip()
                    parts = line.split()
                    if len(parts) >= 2:
                        code_point = parts[0]
                        categories = parts[1:]
                        categories_str = '\t'.join(categories)
                        
                        # Handle ranges (0xXXXX..0xYYYY format)
                        if '..' in code_point:
                            start, end = code_point.split('..')
                            outfile.write(f"{start}\t{end}\t{categories_str}\n")
                        else:
                            outfile.write(f"{code_point}\t\t{categories_str}\n")
                            
    except Exception as e:
        print(f'Error processing char.def file: {str(e)}')

def process_dictionary(input_dir, output_file):
    # Get all CSV files in the input directory
    csv_files = glob.glob(os.path.join(input_dir, '*.csv'))

    # Sort files to ensure consistent order
    csv_files.sort()

    # Create or open the output file in append mode
    with open(output_file, 'w', encoding='utf-8') as outfile:
        # Process each CSV file
        for file in csv_files:
            print(f'Processing {file}...')
            try:
                with open(file, 'r', encoding='euc-jp', errors='replace') as f:
                    csv_reader = csv.reader(f)
                    for fields in csv_reader:
                        if fields and len(fields) >= 12:  # Ensure we have enough fields
                            # Extract word, left cost, right cost, and writing
                            word = fields[0]
                            left_cost = fields[1]
                            right_cost = fields[2]
                            cost = fields[3]
                            writing = convert_katakana_to_hiragana(fields[11])  # Convert katakana to hiragana
                            
                            # Write the selected fields in TSV format: reading, costs, word
                            outfile.write(f'{writing}\t{left_cost}\t{right_cost}\t{cost}\t{word}\n')
            except Exception as e:
                print(f'Error processing {file}: {str(e)}')

    print(f'Dictionary compilation complete. Output saved to {output_file}')

def process_matrix(input_file, output_file):
    """Process the matrix.def file and output connection costs to TSV."""
    print(f'Processing matrix file {input_file}...')
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            with open(output_file, 'w', encoding='utf-8') as outfile:
                # First line contains dimensions
                dimensions = f.readline().strip().split()
                left_size, right_size = map(int, dimensions)
                outfile.write(f'{left_size}\t{right_size}\n')
                
                # Process each subsequent line
                for line in f:
                    if line.strip():
                        left_id, right_id, cost = line.strip().split()
                        outfile.write(f'{left_id}\t{right_id}\t{cost}\n')
    except Exception as e:
        print(f'Error processing matrix file: {str(e)}')

def main():
    parser = argparse.ArgumentParser(description='Process MeCab IPADIC CSV files and matrix.def into output files.')
    parser.add_argument('--input-dir', '-i', default='mecab-ipadic-2.7.0-20070801',
                      help='Directory containing the MeCab IPADIC CSV files (default: mecab-ipadic-2.7.0-20070801)')
    parser.add_argument('--output-file', '-o', default='combined_dictionary.tsv',
                      help='Output file path for dictionary (default: combined_dictionary.tsv)')
    parser.add_argument('--matrix-output', '-m', default='cost_matrix.tsv',
                      help='Output file path for cost matrix (default: cost_matrix.tsv)')
    parser.add_argument('--char-categories-output', '-c', default='char_categories.tsv',
                      help='Output file path for character categories (default: char_categories.tsv)')
    parser.add_argument('--char-mappings-output', '-p', default='char_mappings.tsv',
                      help='Output file path for character mappings (default: char_mappings.tsv)')
    parser.add_argument('--unk-output', '-u', default='unk_data.tsv',
                      help='Output file path for unknown word definitions (default: unk_data.tsv)')
    
    args = parser.parse_args()
    
    # Verify input directory exists
    if not os.path.isdir(args.input_dir):
        print(f"Error: Input directory '{args.input_dir}' does not exist.")
        return 1
    
    # Create output directory if it doesn't exist
    for output_file in [args.output_file, args.matrix_output, args.char_categories_output, 
                       args.char_mappings_output, args.unk_output]:
        output_dir = os.path.dirname(output_file)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)
    
    # Process the dictionary files
    process_dictionary(args.input_dir, args.output_file)
    
    # Process the matrix file
    matrix_file = os.path.join(args.input_dir, 'matrix.def')
    if os.path.exists(matrix_file):
        process_matrix(matrix_file, args.matrix_output)
    else:
        print(f"Warning: Matrix file '{matrix_file}' not found.")
    
    # Process the char.def file
    char_def_file = os.path.join(args.input_dir, 'char.def')
    if os.path.exists(char_def_file):
        process_char_def(char_def_file, args.char_categories_output, args.char_mappings_output)
    else:
        print(f"Warning: Character definition file '{char_def_file}' not found.")
    
    # Process the unk.def file
    unk_def_file = os.path.join(args.input_dir, 'unk.def')
    if os.path.exists(unk_def_file):
        process_unk_def(unk_def_file, args.unk_output)
    else:
        print(f"Warning: Unknown words definition file '{unk_def_file}' not found.")
    
    return 0

if __name__ == '__main__':
    exit(main())