# MeCab IPADIC Dictionary Processor

This script processes MeCab IPADIC dictionary CSV files and outputs a simplified TSV format containing essential word information. It also processes the matrix.def file to extract connection costs.

## Features

- Extracts word readings, costs, and original forms from MeCab IPADIC CSV files
- Converts katakana readings to hiragana
- Processes matrix.def file to extract connection costs
- Outputs dictionary entries in TSV format with fields:
  1. Reading (in hiragana)
  2. Left context id
  3. Right context id
  4. Word cost
  5. Original word

## Requirements

- Python 3.x
- Your choice of Python package manager (uv is used in examples, but pip or any other package manager works just fine)
- MeCab IPADIC dictionary files (can be downloaded from https://github.com/shogo82148/mecab/releases/download/v0.996.10/mecab-ipadic-2.7.0-20070801.tar.gz)

## Usage

Basic usage with default settings:

```bash
uv run ipadic_processor.py
```

With custom input/output paths:

```bash
uv run ipadic_processor.py --input-dir path/to/ipadic --output-file path/to/output.tsv --matrix-output path/to/matrix.tsv
```

### Arguments

- `-i, --input-dir`: Directory containing MeCab IPADIC CSV files (default: mecab-ipadic-2.7.0-20070801)
- `-o, --output-file`: Output file path for dictionary (default: combined_dictionary.tsv)
- `-m, --matrix-output`: Output file path for cost matrix (default: cost_matrix.tsv)

## Output Format

The script generates two TSV files:

### Dictionary File (combined_dictionary.tsv)

```
reading[TAB]left_id[TAB]right_id[TAB]word_cost[TAB]original_word
```

Example:

```
あおい	1315	1315	4877	青い
```

### Matrix File (cost_matrix.tsv)

First line contains dimensions:

```
left_size[TAB]right_size
```

Subsequent lines contain connection costs:

```
left_id[TAB]right_id[TAB]cost
```
