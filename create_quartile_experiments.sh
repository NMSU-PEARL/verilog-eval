#!/bin/bash

# create_quartile_experiments.sh
# Creates experiment directories for different quartiles with specified model and prompt type
# Supports flag-based arguments for better usability

# Usage: ./create_quartile_experiments.sh -m <model> -p <prompt_type> [-q quartiles] [-r runs]
# Example: ./create_quartile_experiments.sh -m gpt4.1-mini -p cot -q q1,q3 -r 2

set -e

show_help() {
    echo "Usage: $0 -m <model> -p <prompt_type> [-q quartiles] [-r runs] [-s samples]"
    echo "   OR: $0 <model> <prompt_type> [quartiles] [runs]  (legacy positional)"
    echo ""
    echo "Flag-based arguments (recommended):"
    echo "  -m, --model      Model to use (required)"
    echo "  -p, --prompt     Type of prompts to use (required)"
    echo "  -q, --quartiles  Comma-separated list of quartiles (optional, default: all)"
    echo "  -r, --runs       Number of runs or comma-separated run numbers (optional, default: 2)"
    echo "  -s, --samples    Number of samples per problem (optional, default: 10)"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Available models:"
    echo "  OpenAI: gpt-3.5-turbo, gpt-4, gpt-4-turbo, gpt-4o, gpt-4.1, gpt-4.1-mini, o3-mini"
    echo "  Anthropic: claude-3.7-sonnet, claude-3.7-haiku, claude-3-5-sonnet-20240620"
    echo "  Google: gemini-2.5, gemini-2.5-flash"
    echo "  NVIDIA: meta/llama-3.1-8b-instruct, meta/llama-3.1-70b-instruct, etc."
    echo ""
    echo "Available prompt types:"
    echo "  - standard (uses standard prompts)"
    echo "  - cot      (uses chain-of-thought prompts)" 
    echo "  - cot_v1   (uses cot_v1 prompts)"
    echo "  - cot_v2   (uses cot_v2 prompts)"
    echo "  - Multiple types can be specified with commas: cot,standard"
    echo ""
    echo "Available quartiles:"
    echo "  - q1   (low quartile)"
    echo "  - q2   (mid-low quartile)"
    echo "  - q3   (mid-high quartile)"
    echo "  - q4   (high quartile)"
    echo "  - all  (all quartiles - default)"
    echo ""
    echo "Run options:"
    echo "  - 1         (create 1 run: run1)"
    echo "  - 2         (create 2 runs: run1, run2 - default)"
    echo "  - 3         (create 3 runs: run1, run2, run3)"
    echo "  - 1,3       (create specific runs: run1, run3)"
    echo "  - 2,4,5     (create specific runs: run2, run4, run5)"
    echo ""
    echo "Flag-based examples:"
    echo "  $0 -m gpt4.1-mini -p cot                          # All quartiles, 2 runs, 10 samples each"
    echo "  $0 -m gpt4.1-mini -p cot,standard -q q4 -r 1      # q4 with both cot and standard prompts"
    echo "  $0 -m gpt4.1-mini -p cot -q q1,q3                 # Only q1 and q3, 2 runs, 10 samples each"
    echo "  $0 -m gpt4.1-mini -p cot -q q4 -r 1 -s 5          # Only q4, 1 run, 5 samples"
    echo "  $0 -m claude-3.7-sonnet -p cot_v2 -q all -r 3 -s 15  # All quartiles, 3 runs, 15 samples each"
    echo "  $0 -m gpt-4 -p standard,cot,cot_v1 -q q1,q3 -r 1,3 -s 20  # Multiple prompts and quartiles"
    echo ""
    echo "Legacy positional examples:"
    echo "  $0 gpt4.1-mini cot                              # All quartiles, 2 runs each"
    echo "  $0 gpt4.1-mini cot q1,q3                        # Only q1 and q3, 2 runs each"
    echo "  $0 gpt4.1-mini cot q4 1                         # Only q4, 1 run"
    echo ""
}

# Initialize variables
MODEL=""
PROMPT_TYPE=""
QUARTILES_ARG="all"
RUNS_ARG="2"
SAMPLES_ARG="10"

# Check for help flag first
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

# Parse arguments - support both flag-based and positional
if [[ "$1" =~ ^- ]]; then
    # Flag-based parsing
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--model)
                MODEL="$2"
                shift 2
                ;;
            -p|--prompt)
                PROMPT_TYPE="$2"
                shift 2
                ;;
            -q|--quartiles)
                QUARTILES_ARG="$2"
                shift 2
                ;;
            -r|--runs)
                RUNS_ARG="$2"
                shift 2
                ;;
            -s|--samples)
                SAMPLES_ARG="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Error: Unknown option $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate required flag arguments
    if [ -z "$MODEL" ] || [ -z "$PROMPT_TYPE" ]; then
        echo "Error: Model (-m) and prompt type (-p) are required when using flags"
        show_help
        exit 1
    fi
else
    # Legacy positional parsing
    if [ $# -lt 2 ] || [ $# -gt 4 ]; then
        show_help
        exit 1
    fi
    
    MODEL="$1"
    PROMPT_TYPE="$2"
    QUARTILES_ARG="${3:-all}"
    RUNS_ARG="${4:-2}"
fi

# Parse prompt types argument
IFS=',' read -ra PROMPT_TYPES_TO_PROCESS <<< "$PROMPT_TYPE"

# Validate prompt types
for prompt_type in "${PROMPT_TYPES_TO_PROCESS[@]}"; do
    if [[ ! " standard cot cot_v1 cot_v2 " =~ " $prompt_type " ]]; then
        echo "Error: Invalid prompt type '$prompt_type'. Valid options: standard, cot, cot_v1, cot_v2"
        exit 1
    fi
done

# Base directory - the directory this script lives in
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Quartile mappings
declare -A QUARTILE_NAMES=(
    ["q1"]="low"
    ["q2"]="mid-low"
    ["q3"]="mid-high"
    ["q4"]="high"
)

# Parse quartiles argument
if [ "$QUARTILES_ARG" = "all" ]; then
    QUARTILES_TO_PROCESS=("q1" "q2" "q3" "q4")
else
    IFS=',' read -ra QUARTILES_TO_PROCESS <<< "$QUARTILES_ARG"
fi

# Validate quartiles
for q in "${QUARTILES_TO_PROCESS[@]}"; do
    if [[ ! " q1 q2 q3 q4 " =~ " $q " ]]; then
        echo "Error: Invalid quartile '$q'. Valid options: q1, q2, q3, q4, all"
        exit 1
    fi
done

# Parse runs argument
if [[ "$RUNS_ARG" =~ ^[0-9]+$ ]]; then
    # If it's a single number, create runs 1 through that number
    RUNS_TO_PROCESS=()
    for ((i=1; i<=RUNS_ARG; i++)); do
        RUNS_TO_PROCESS+=("$i")
    done
elif [[ "$RUNS_ARG" =~ ^[0-9,]+$ ]]; then
    # If it's comma-separated numbers, use those specific run numbers
    IFS=',' read -ra RUNS_TO_PROCESS <<< "$RUNS_ARG"
else
    echo "Error: Invalid runs argument '$RUNS_ARG'. Use a number (e.g., 3) or comma-separated numbers (e.g., 1,3,5)"
    exit 1
fi

# Validate run numbers (must be positive integers)
for run in "${RUNS_TO_PROCESS[@]}"; do
    if ! [[ "$run" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: Invalid run number '$run'. Run numbers must be positive integers"
        exit 1
    fi
done

# Validate samples argument (must be positive integer)
if ! [[ "$SAMPLES_ARG" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Invalid samples argument '$SAMPLES_ARG'. Samples must be a positive integer"
    exit 1
fi

# Check if quartile files exist for selected quartiles
for q in "${QUARTILES_TO_PROCESS[@]}"; do
    quartile_file="${BASE_DIR}/quartiles/${QUARTILE_NAMES[$q]}_quartile.txt"
    if [ ! -f "$quartile_file" ]; then
        echo "Error: Quartile file not found: $quartile_file"
        exit 1
    fi
done

# Validate all prompt type directories exist
SCRIPTS_DIR="${BASE_DIR}/scripts"
for prompt_type in "${PROMPT_TYPES_TO_PROCESS[@]}"; do
    if [ "$prompt_type" = "standard" ]; then
        prompt_source_dir="$SCRIPTS_DIR/prompt_variants/standard"
    else
        prompt_source_dir="$SCRIPTS_DIR/prompt_variants/$prompt_type"
    fi
    
    if [ ! -d "$prompt_source_dir" ]; then
        echo "Error: Prompt directory not found: $prompt_source_dir"
        exit 1
    fi
    
    # Check for source 2-shot prompt file
    source_prompt_file="$prompt_source_dir/verilog-example-prefix_netlist-to-rtl_2-shot.txt"
    if [ ! -f "$source_prompt_file" ]; then
        echo "Error: 2-shot prompt file not found: $source_prompt_file"
        exit 1
    fi
done

# Function to switch prompt type in main scripts directory
switch_prompt_type() {
    local prompt_type="$1"
    local main_prompt_file="$SCRIPTS_DIR/verilog-example-prefix_netlist-to-rtl_2-shot.txt"
    
    # Determine source prompt directory
    if [ "$prompt_type" = "standard" ]; then
        local prompt_source_dir="$SCRIPTS_DIR/prompt_variants/standard"
    else
        local prompt_source_dir="$SCRIPTS_DIR/prompt_variants/$prompt_type"
    fi
    
    local source_prompt_file="$prompt_source_dir/verilog-example-prefix_netlist-to-rtl_2-shot.txt"
    
    # Remove any existing 2-shot prompt in main scripts directory
    if [ -f "$main_prompt_file" ]; then
        rm "$main_prompt_file"
    fi
    
    # Copy the correct 2-shot prompt to main scripts directory
    echo "Installing $prompt_type 2-shot prompt to main scripts directory..."
    cp "$source_prompt_file" "$main_prompt_file"
}

echo "Creating quartile experiments for:"
echo "  Model: $MODEL"
echo "  Prompt Types: ${PROMPT_TYPES_TO_PROCESS[*]}"
echo "  Quartiles: ${QUARTILES_TO_PROCESS[*]}"
echo "  Runs: ${RUNS_TO_PROCESS[*]}"
echo "  Samples: $SAMPLES_ARG"
echo ""

# Create experiments for each selected quartile and prompt type with specified runs
for q in "${QUARTILES_TO_PROCESS[@]}"; do
    quartile_name="${QUARTILE_NAMES[$q]}"
    
    for run in "${RUNS_TO_PROCESS[@]}"; do
        for prompt_type in "${PROMPT_TYPES_TO_PROCESS[@]}"; do
            # Create directory name: quartile_model_prompttype_shot2_run#
            experiment_dir="${BASE_DIR}/${q}_${MODEL}_${prompt_type}_shot2_run${run}"
            
            echo "Setting up experiment: ${q}_${MODEL}_${prompt_type}_shot2_run${run}"
            
            # Create the experiment directory if it doesn't exist
            if [ ! -d "$experiment_dir" ]; then
                mkdir -p "$experiment_dir"
                echo "  ✓ Created directory: $experiment_dir"
            else
                echo "  ℹ Directory already exists: $experiment_dir"
            fi
            
            # Check if problems.txt exists, copy if missing
            if [ ! -f "$experiment_dir/problems.txt" ]; then
                quartile_file="${BASE_DIR}/quartiles/${quartile_name}_quartile.txt"
                cp "$quartile_file" "$experiment_dir/problems.txt"
                echo "  ✓ Copied problems from: $quartile_file"
            else
                echo "  ℹ problems.txt already exists"
            fi
            
            echo ""
        done
    done
done

echo "All quartile experiments set up successfully!"
echo ""
echo "Total directories created: $((${#QUARTILES_TO_PROCESS[@]} * ${#RUNS_TO_PROCESS[@]} * ${#PROMPT_TYPES_TO_PROCESS[@]})) (${#QUARTILES_TO_PROCESS[@]} quartiles × ${#RUNS_TO_PROCESS[@]} runs × ${#PROMPT_TYPES_TO_PROCESS[@]} prompt types)"
echo ""
echo "Directory structure:"
for q in "${QUARTILES_TO_PROCESS[@]}"; do
    for run in "${RUNS_TO_PROCESS[@]}"; do
        for prompt_type in "${PROMPT_TYPES_TO_PROCESS[@]}"; do
            echo "  ${q}_${MODEL}_${prompt_type}_shot2_run${run}/"
        done
    done
done
echo ""
echo "Running experiments automatically (interleaved by run, then prompt type):"

# Interleaved execution: for each quartile and run, cycle through prompt types
for q in "${QUARTILES_TO_PROCESS[@]}"; do
    quartile_name="${QUARTILE_NAMES[$q]}"
    
    for run in "${RUNS_TO_PROCESS[@]}"; do
        for prompt_type in "${PROMPT_TYPES_TO_PROCESS[@]}"; do
            echo ""
            experiment_dir_name="${q}_${MODEL}_${prompt_type}_shot2_run${run}"
            echo "Running experiment: $experiment_dir_name"
            echo "  cd $experiment_dir_name"
            
            # Switch to the correct prompt type
            switch_prompt_type "$prompt_type"
            
            # Change to experiment directory
            cd "$BASE_DIR/$experiment_dir_name"
            
            # Run configure
            echo "  Running configure..."
            ../configure --with-task=netlist-to-rtl --with-problems=problems.txt --with-model=$MODEL --with-samples=$SAMPLES_ARG --with-examples=2
            
            # Run make with timing
            echo "  Running make -j4..."
            start_time=$(date +%s)
            make -j4
            end_time=$(date +%s)
            elapsed=$((end_time - start_time))
            
            # Save timing to file
            echo "make_time_seconds: $elapsed" > timing.txt
            
            echo "  ✓ Experiment completed in ${elapsed} seconds (saved to timing.txt)"
            echo ""
            
            # Return to base directory
            cd "$BASE_DIR"
        done
    done
done

echo "All experiments completed successfully!"
echo ""
echo "Summary:"
echo "- Created and ran $((${#QUARTILES_TO_PROCESS[@]} * ${#RUNS_TO_PROCESS[@]} * ${#PROMPT_TYPES_TO_PROCESS[@]})) experiments"
echo "- Used prompt types: ${PROMPT_TYPES_TO_PROCESS[*]}"
echo "- Each experiment used $SAMPLES_ARG samples per problem"
echo "- Execution times saved to timing.txt in each experiment directory"