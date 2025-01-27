"""
MeCab IPADIC Dictionary Processor
Extracts and processes word entries from MeCab IPADIC dictionary files.

This script reads MeCab IPADIC CSV files, extracts essential word information,
and outputs it in a simplified TSV format with readings converted to hiragana.
It also processes the matrix.def file to output connection costs.
"""

import os
import glob
import argparse
import csv

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
    
    args = parser.parse_args()
    
    # Verify input directory exists
    if not os.path.isdir(args.input_dir):
        print(f"Error: Input directory '{args.input_dir}' does not exist.")
        return 1
    
    # Create output directory if it doesn't exist
    for output_file in [args.output_file, args.matrix_output]:
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
    
    return 0

if __name__ == '__main__':
    exit(main())