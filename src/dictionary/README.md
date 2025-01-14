# MeCab IPADIC Dictionary Processor

This script processes MeCab IPADIC dictionary CSV files and outputs a simplified TSV format containing essential word information.

## Features

- Extracts word readings, costs, and original forms from MeCab IPADIC CSV files
- Converts katakana readings to hiragana
- Outputs in TSV format with fields:
  1. Reading (in hiragana)
  2. Left context cost
  3. Right context cost
  4. Word cost
  5. Original word

## Requirements

- Python 3.x
- uv (Python package manager)

## Usage

Basic usage with default settings:

```bash
uv run mecab_dict_processor.py
```

With custom input/output paths:

```bash
uv run mecab_dict_processor.py --input-dir path/to/ipadic --output-file path/to/output.tsv
```

### Arguments

- `-i, --input-dir`: Directory containing MeCab IPADIC CSV files (default: mecab-ipadic-2.7.0-20070801)
- `-o, --output-file`: Output file path (default: combined_dictionary.tsv)

## Output Format

The script generates a TSV file with the following format:

```
reading[TAB]left_cost[TAB]right_cost[TAB]word_cost[TAB]original_word
```

Example:

```
あおい	1315	1315	4877	青い
```
