#!/bin/bash

################################################################################

# Description: Initialize project structure
################################################################################

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

################################################################################
# HELPER FUNCTIONS
################################################################################

print_subheader() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

################################################################################
# STEP 1: CHOOSE ANALYSIS MODE
################################################################################

echo ""
echo "=========================================="
echo "STEP 1: Choose Analysis Mode"
echo "=========================================="
echo ""
echo "Select the type of analysis you want to perform:"
echo ""
echo "  1. Expression Analysis"
echo "     - Uses reference genome and annotation"
echo "     - Tools: STAR, featureCounts, DESeq2"
echo "     - Estimated time: 2-4 hours"
echo "     - Best for: Model organisms with good reference genomes"
echo ""
echo "  2. De Novo Assembly"
echo "     - No reference genome required"
echo "     - Tools: Trinity, BUSCO, Kallisto, edgeR"
echo "     - Estimated time: 24-72 hours"
echo "     - Best for: Non-model organisms, novel transcriptomes"
echo ""

while true; do
    read -p "Enter your choice [1-2]: " analysis_choice

    case "${analysis_choice}" in
        1)
            ANALYSIS_MODE="expression"
            CONDA_ENV_NAME="rnaseq_expression"
            echo -e "${GREEN}✓ Selected: Expression Analysis${NC}"
            break
            ;;
        2)
            ANALYSIS_MODE="denovo"
            CONDA_ENV_NAME="rnaseq_denovo"
            echo -e "${GREEN}✓ Selected: De Novo Assembly${NC}"
            break
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
            ;;
    esac
done

################################################################################
# STEP 2: PROJECT NAME AND LOCATION
################################################################################

echo ""
echo "=========================================="
echo "STEP 2: Project Configuration"
echo "=========================================="
echo ""

# Get project name
while true; do
    read -p "Enter project name (e.g., my_rnaseq_project): " PROJECT_NAME

    if [[ -z "${PROJECT_NAME}" ]]; then
        echo -e "${RED}Project name cannot be empty${NC}"
        continue
    fi

    # Validate project name (alphanumeric, underscore, hyphen only)
    if [[ ! "${PROJECT_NAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Project name can only contain letters, numbers, underscores, and hyphens${NC}"
        continue
    fi

    echo -e "${GREEN}✓ Project name: ${PROJECT_NAME}${NC}"
    break
done

# Get parent directory
echo ""
read -p "Enter parent directory [default: ${HOME}/projects]: " PARENT_DIR
PARENT_DIR="${PARENT_DIR:-${HOME}/projects}"

# Expand tilde and resolve to absolute path
PARENT_DIR=$(eval echo "${PARENT_DIR}")
PARENT_DIR=$(realpath -m "${PARENT_DIR}")

# Create parent directory if it doesn't exist
if [[ ! -d "${PARENT_DIR}" ]]; then
    echo -e "${YELLOW}Parent directory does not exist. Creating...${NC}"
    if ! mkdir -p "${PARENT_DIR}"; then
        echo -e "${RED}Failed to create parent directory: ${PARENT_DIR}${NC}"
        exit 1
    fi
fi

# Set project root
PROJECT_ROOT="${PARENT_DIR}/${PROJECT_NAME}"

# Check if project already exists
if [[ -d "${PROJECT_ROOT}" ]]; then
    echo -e "${YELLOW}Warning: Project directory already exists: ${PROJECT_ROOT}${NC}"

    # Try to load existing mode
    if [[ -f "${PROJECT_ROOT}/.analysis_mode" ]]; then
        EXISTING_MODE=$(cat "${PROJECT_ROOT}/.analysis_mode" | cut -d',' -f1)
        EXISTING_ENV=$(cat "${PROJECT_ROOT}/.analysis_mode" | cut -d',' -f2)
        
        echo ""
        echo "Existing project configuration:"
        echo -e "  Analysis Mode: ${BLUE}${EXISTING_MODE}${NC}"
        echo -e "  Conda Environment: ${BLUE}${EXISTING_ENV}${NC}"
        echo ""
        
        if [[ "${EXISTING_MODE}" != "${ANALYSIS_MODE}" ]]; then
            echo -e "${YELLOW}⚠ Mode mismatch detected!${NC}"
            echo -e "  Existing: ${RED}${EXISTING_MODE}${NC}"
            echo -e "  Selected: ${GREEN}${ANALYSIS_MODE}${NC}"
            echo ""
            echo "What would you like to do?"
            echo ""
            echo "  1. Keep existing project and add more data (recommended)"
            echo "  2. Overwrite entire project with new configuration"
            echo "  3. Abort setup"
            echo ""
            
            while true; do
                read -p "Choose [1-3]: " mode_conflict_choice
                case "${mode_conflict_choice}" in
                    1)
                        echo -e "${GREEN}✓ Keeping existing project (${EXISTING_MODE} mode)${NC}"
                        ANALYSIS_MODE="${EXISTING_MODE}"
                        CONDA_ENV_NAME="${EXISTING_ENV}"
                        SKIP_DIR_CREATION=true
                        break
                        ;;
                    2)
                        echo -e "${YELLOW}⚠ This will DELETE all existing data!${NC}"
                        read -p "Are you absolutely sure? Type 'DELETE' to confirm: " confirm_delete
                        if [[ "${confirm_delete}" == "DELETE" ]]; then
                            echo -e "${YELLOW}Removing existing project...${NC}"
                            rm -rf "${PROJECT_ROOT}"
                            echo -e "${GREEN}✓ Project removed${NC}"
                        else
                            echo -e "${RED}Confirmation failed. Setup aborted.${NC}"
                            exit 1
                        fi
                        break
                        ;;
                    3)
                        echo -e "${RED}Setup aborted${NC}"
                        exit 1
                        ;;
                    *)
                        echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                        ;;
                esac
            done
        else
            echo -e "${GREEN}✓ Project mode matches (${ANALYSIS_MODE})${NC}"
            echo ""
            echo "What would you like to do?"
            echo ""
            echo "  1. Add more data to existing project (recommended)"
            echo "  2. Overwrite entire project"
            echo "  3. Skip - do nothing"
            echo ""
            
            while true; do
                read -p "Choose [1-3]: " existing_choice
                case "${existing_choice}" in
                    1)
                        echo -e "${GREEN}✓ Adding data to existing project${NC}"
                        SKIP_DIR_CREATION=true
                        break
                        ;;
                    2)
                        echo -e "${YELLOW}⚠ This will DELETE all existing data!${NC}"
                        read -p "Are you absolutely sure? Type 'DELETE' to confirm: " confirm_delete
                        if [[ "${confirm_delete}" == "DELETE" ]]; then
                            echo -e "${YELLOW}Removing existing project...${NC}"
                            rm -rf "${PROJECT_ROOT}"
                            echo -e "${GREEN}✓ Project removed${NC}"
                        else
                            echo -e "${RED}Confirmation failed. Setup aborted.${NC}"
                            exit 1
                        fi
                        break
                        ;;
                    3)
                        echo -e "${YELLOW}Setup aborted${NC}"
                        exit 0
                        ;;
                    *)
                        echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                        ;;
                esac
            done
        fi
    else
        # No mode file, ask to overwrite
        echo ""
        echo -e "${YELLOW}⚠ Project exists but no configuration file found (.analysis_mode)${NC}"
        echo ""
        echo "What would you like to do?"
        echo ""
        echo "  1. Try to use existing directory structure"
        echo "  2. Overwrite entire project"
        echo "  3. Abort setup"
        echo ""
        
        while true; do
            read -p "Choose [1-3]: " no_config_choice
            case "${no_config_choice}" in
                1)
                    echo -e "${GREEN}✓ Using existing directory${NC}"
                    SKIP_DIR_CREATION=true
                    break
                    ;;
                2)
                    echo -e "${YELLOW}⚠ This will DELETE all existing data!${NC}"
                    read -p "Are you absolutely sure? Type 'DELETE' to confirm: " confirm_delete
                    if [[ "${confirm_delete}" == "DELETE" ]]; then
                        echo -e "${YELLOW}Removing existing project...${NC}"
                        rm -rf "${PROJECT_ROOT}"
                        echo -e "${GREEN}✓ Project removed${NC}"
                    else
                        echo -e "${RED}Confirmation failed. Setup aborted.${NC}"
                        exit 1
                    fi
                    break
                    ;;
                3)
                    echo -e "${RED}Setup aborted${NC}"
                    exit 1
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                    ;;
            esac
        done
    fi
fi

if [[ -z "${SKIP_DIR_CREATION}" ]]; then
    echo -e "${GREEN}✓ Project will be created at: ${PROJECT_ROOT}${NC}"
else
    echo -e "${GREEN}✓ Using existing project at: ${PROJECT_ROOT}${NC}"
fi

################################################################################
# STEP 3: CREATE DIRECTORY STRUCTURE
################################################################################

if [[ -z "${SKIP_DIR_CREATION}" ]]; then
    echo ""
    echo "=========================================="
    echo "STEP 3: Creating Directory Structure"
    echo "=========================================="
    echo ""

    # Create main project directory
    mkdir -p "${PROJECT_ROOT}"
    cd "${PROJECT_ROOT}"

    # Create directory structure
    echo "Creating directories..."

    # Data directories
    mkdir -p raw_data/{fastq,reference}
    mkdir -p qc_reports/{fastqc_before,fastqc_after}
    mkdir -p trimmed_data
    mkdir -p reproducibility/{logs,metadata}

    # Mode-specific directories
    if [[ "${ANALYSIS_MODE}" == "expression" ]]; then
        mkdir -p genome_indexed
        mkdir -p aligned_data/{sam,bam,stats}
        mkdir -p dea/{featurecounts,deseq2}
        mkdir -p enrichment
        mkdir -p results
    else
        mkdir -p corrected_data
        mkdir -p trinity_assembly
        mkdir -p busco_results
        mkdir -p kallisto/{index,quantification}
        mkdir -p edgeR
        mkdir -p annotation
        mkdir -p enrichment
    fi

    echo -e "${GREEN}✓ Directory structure created${NC}"

    # Save analysis mode and conda environment name
    echo "${ANALYSIS_MODE},${CONDA_ENV_NAME},qualityControl,${PROJECT_ROOT}" > .analysis_mode
    echo -e "${GREEN}✓ Analysis configuration saved${NC}"
else
    # Ensure we're in the project directory
    cd "${PROJECT_ROOT}"
    echo -e "${BLUE}ℹ Using existing directory structure${NC}"
fi

################################################################################
# FUNCTION: Data Input (Unified - Local, SCP, SRA)
################################################################################

data_input_unified() {
    local dest_dir=$1
    local data_type=$2

    # Determine which SRA tool to use and check availability
    local sra_tool=""
    if command -v prefetch &>/dev/null; then
        sra_tool="prefetch"
    elif command -v fasterq-dump &>/dev/null; then
        sra_tool="fasterq-dump"
    fi

    print_subheader "$data_type Input Options"
    
    # Check if directory has files
    local file_count=$(find "$dest_dir" -type f 2>/dev/null | wc -l)
    if [[ $file_count -gt 0 ]]; then
        echo -e "${BLUE}ℹ Found $file_count existing file(s) in $dest_dir${NC}"
        echo ""
    fi
    
    echo ""
    echo -e "${YELLOW}1. Copy from local path${NC}"
    echo -e "${YELLOW}2. Download via SCP (remote SSH server)${NC}"
    if [[ -n "$sra_tool" ]]; then
        echo -e "${YELLOW}3. Download from SRA (NCBI)${NC}"
        echo -e "${YELLOW}4. Skip - use existing files or add manually later${NC}"
    else
        echo -e "${YELLOW}3. Skip - use existing files or add manually later${NC}"
    fi
    echo ""

    while true; do
        if [[ -n "$sra_tool" ]]; then
            read -p "Choose (1-4): " opt
        else
            read -p "Choose (1-3): " opt
        fi

        case "$opt" in
            1)
                print_info "Enter source path for $data_type (or Enter to skip)"
                read -p "Source path: " source_path
                if [[ -z "$source_path" ]]; then
                    print_warning "$data_type copy skipped"
                    return 1
                fi

                # Expand wildcards and copy files
                expanded_paths=(${source_path})
                local copy_success=false
                
                for path in "${expanded_paths[@]}"; do
                    if [[ -f "$path" ]]; then
                        if cp -v "$path" "$dest_dir/" 2>/dev/null; then
                            copy_success=true
                        fi
                    elif [[ -d "$path" ]]; then
                        if cp -rv "$path"/* "$dest_dir/" 2>/dev/null; then
                            copy_success=true
                        fi
                    else
                        print_warning "Skipping invalid path: $path"
                    fi
                done

                if [[ "$copy_success" == true ]]; then
                    print_success "Files copied to: $dest_dir/"
                    return 0
                else
                    print_error "Failed to copy files"
                    continue
                fi
                ;;
            2)
                print_info "Enter remote SCP details:"
                read -p "Remote host (user@hostname): " remote_host
                read -p "Remote directory path: " remote_dir
                read -p "File pattern (e.g., *fastq.gz or leave empty for all): " file_pattern

                if [[ -z "$remote_host" ]] || [[ -z "$remote_dir" ]]; then
                    print_warning "$data_type SCP download skipped - missing host or directory"
                    continue
                fi

                # Setup SSH connection reuse
                local ssh_ctrl="/tmp/ssh-$$"
                local ssh_opts="-o ControlMaster=auto -o ControlPath=${ssh_ctrl} -o ControlPersist=60"

                print_info "Connecting to $remote_host..."

                # List files with numbers (asks password once here)
                if [[ -n "$file_pattern" ]]; then
                    mapfile -t files < <(ssh $ssh_opts "$remote_host" "ls -1 '$remote_dir'/$file_pattern 2>/dev/null")
                else
                    mapfile -t files < <(ssh $ssh_opts "$remote_host" "ls -1 '$remote_dir' 2>/dev/null")
                fi

                if [[ ${#files[@]} -eq 0 ]]; then
                    print_error "No files found"
                    ssh -O exit $ssh_opts "$remote_host" 2>/dev/null
                    continue
                fi

                # Show files
                echo ""
                print_info "Found ${#files[@]} file(s):"
                for i in "${!files[@]}"; do
                    printf "${YELLOW}%3d${NC}) %s\n" "$((i+1))" "$(basename "${files[$i]}")"
                done
                
                echo ""
                echo "Select: number (1), range (1-4), multiple (1,3,5), all"
                read -p "Selection: " selection

                # Parse selection
                declare -a selected
                if [[ "$selection" == "all" ]]; then
                    selected=("${files[@]}")
                else
                    IFS=',' read -ra parts <<< "$selection"
                    for part in "${parts[@]}"; do
                        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                            for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do
                                [[ $i -le ${#files[@]} ]] && selected+=("${files[$((i-1))]}")
                            done
                        elif [[ "$part" =~ ^[0-9]+$ ]]; then
                            [[ $part -le ${#files[@]} ]] && selected+=("${files[$((part-1))]}")
                        fi
                    done
                fi

                if [[ ${#selected[@]} -eq 0 ]]; then
                    print_error "No valid selection"
                    ssh -O exit $ssh_opts "$remote_host" 2>/dev/null
                    continue
                fi

                # Download (no more passwords!)
                print_info "Downloading ${#selected[@]} file(s)..."
                success=0
                for file in "${selected[@]}"; do
                    filename=$(basename "$file")
                    echo "  → $filename"
                    if scp $ssh_opts "$remote_host:$file" "$dest_dir/" &>/dev/null; then
                        ((success++))
                        print_success "$filename"
                    else
                        print_error "Failed: $filename"
                    fi
                done

                # Close connection
                ssh -O exit $ssh_opts "$remote_host" 2>/dev/null

                print_success "Downloaded $success/${#selected[@]} files to: $dest_dir/"
                [[ $success -gt 0 ]] && return 0 || continue
                ;;
            3)
                if [[ -n "$sra_tool" ]]; then
                    print_info "Using $sra_tool for downloads"
                    print_info "Enter SRA identifiers (comma-separated, e.g., SRR1234567,SRR9876543)"
                    read -p "SRA accessions: " sra_accs
                    if [[ -z "$sra_accs" ]]; then
                        print_warning "SRA download skipped"
                        continue
                    fi

                    # Split accessions and download
                    IFS=',' read -ra ACCS <<< "$sra_accs"
                    success_count=0
                    total_count=${#ACCS[@]}

                    for acc in "${ACCS[@]}"; do
                        acc=$(echo "$acc" | xargs)  # Trim whitespace
                        if [[ -n "$acc" ]]; then
                            print_info "Downloading: $acc"
                            if [[ "$sra_tool" == "fasterq-dump" ]]; then
                                if fasterq-dump --split-files --outdir "$dest_dir" "$acc" 2>/dev/null; then
                                    # Compress the output
                                    gzip "$dest_dir"/${acc}*.fastq 2>/dev/null
                                    ((success_count++))
                                    print_success "Download complete: $acc"
                                else
                                    print_error "Download failed: $acc"
                                fi
                            else
                                if fastq-dump --split-files --gzip --outdir "$dest_dir" "$acc" 2>/dev/null; then
                                    ((success_count++))
                                    print_success "Download complete: $acc"
                                else
                                    print_error "Download failed: $acc"
                                fi
                            fi
                        fi
                    done

                    if [[ $success_count -gt 0 ]]; then
                        print_success "Downloaded $success_count/$total_count SRA datasets to: $dest_dir/"
                        return 0
                    else
                        print_error "Failed to download any SRA datasets"
                        continue
                    fi
                else
                    print_warning "Data input skipped"
                    return 1
                fi
                ;;
            4)
                if [[ -n "$sra_tool" ]]; then
                    print_warning "Data input skipped"
                    return 1
                fi
                ;;
            *)
                if [[ -n "$sra_tool" ]]; then
                    print_error "Invalid option. Choose 1-4."
                else
                    print_error "Invalid option. Choose 1-3."
                fi
                ;;
        esac
    done
}

################################################################################
# STEP 4: DATA INPUT
################################################################################

cd "${PROJECT_ROOT}"

# Call the data input function for FASTQ files
print_info "Setting up FASTQ data input..."
data_input_unified "raw_data/fastq" "FASTQ"

# Call the data input function for reference files (only for expression analysis)
if [[ "${ANALYSIS_MODE}" == "expression" ]]; then
    print_info "Setting up reference genome/annotation input..."
    data_input_unified "raw_data/reference" "Reference"
fi

################################################################################
# STEP 5: SUMMARY
################################################################################

print_success "Project setup completed successfully!"
echo -e "${GREEN}Project location: ${PROJECT_ROOT}${NC}"

echo ""
echo "=========================================="
echo "SETUP SUMMARY"
echo "=========================================="
echo -e "Analysis Mode: ${GREEN}${ANALYSIS_MODE}${NC}"
echo -e "Conda Environment: ${GREEN}${CONDA_ENV_NAME}${NC}"
echo -e "QC Environment: ${GREEN}qualityControl${NC}"
echo -e "Project Path: ${GREEN}${PROJECT_ROOT}${NC}"
echo ""

# Count files in key directories
fastq_count=$(find "${PROJECT_ROOT}/raw_data/fastq" -type f 2>/dev/null | wc -l)
echo -e "FASTQ files in raw_data/fastq: ${GREEN}${fastq_count}${NC}"

if [[ "${ANALYSIS_MODE}" == "expression" ]]; then
    ref_count=$(find "${PROJECT_ROOT}/raw_data/reference" -type f 2>/dev/null | wc -l)
    echo -e "Reference files in raw_data/reference: ${GREEN}${ref_count}${NC}"
fi

echo ""
echo "Key directories:"
echo "  ${PROJECT_ROOT}/"
echo "    ├── raw_data/fastq"
if [[ "${ANALYSIS_MODE}" == "expression" ]]; then
    echo "    ├── raw_data/reference"
    echo "    ├── genome_indexed"
    echo "    ├── aligned_data/{sam,bam,stats}"
    echo "    ├── dea/{featurecounts,deseq2}"
else
    echo "    ├── corrected_data"
    echo "    ├── trinity_assembly"
    echo "    ├── busco_results"
    echo "    ├── kallisto/{index,quantification}"
    echo "    ├── edgeR"
    echo "    ├── annotation"
fi
echo "    ├── qc_reports/{fastqc_before,fastqc_after}"
echo "    ├── trimmed_data"
echo "    ├── enrichment"
echo "    └── reproducibility/{logs,metadata}"
echo ""
echo "Next steps:"
echo "1. Activate conda environment: conda activate ${CONDA_ENV_NAME}"
echo "2. Verify your input data is in the correct directories"
echo "3. Run the Quality Control pipeline script"
echo "4. Check results in the output directories"
