"""
MeCab IPADIC Dictionary Processor
Extracts and processes word entries from MeCab IPADIC dictionary files.

This script reads MeCab IPADIC CSV files, extracts essential word information,
and outputs it in a simplified TSV format with readings converted to hiragana.
"""

# TODO: ADD LICENSE

import os
import glob
import argparse

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
                    for line in f:
                        if line.strip():
                            # Split the line by comma
                            fields = line.strip().split(',')
                            if len(fields) >= 12:  # Ensure we have enough fields
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

def main():
    parser = argparse.ArgumentParser(description='Process MeCab IPADIC CSV files into a single output file.')
    parser.add_argument('--input-dir', '-i', default='mecab-ipadic-2.7.0-20070801',
                      help='Directory containing the MeCab IPADIC CSV files (default: mecab-ipadic-2.7.0-20070801)')
    parser.add_argument('--output-file', '-o', default='combined_dictionary.tsv',
                      help='Output file path (default: combined_dictionary.tsv)')
    
    args = parser.parse_args()
    
    # Verify input directory exists
    if not os.path.isdir(args.input_dir):
        print(f"Error: Input directory '{args.input_dir}' does not exist.")
        return 1
    
    # Create output directory if it doesn't exist
    output_dir = os.path.dirname(args.output_file)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    process_dictionary(args.input_dir, args.output_file)
    return 0

if __name__ == '__main__':
    exit(main())