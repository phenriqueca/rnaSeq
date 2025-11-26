#!/bin/bash

################################################################################
# QUALITY CONTROL AND TRIMMING SCRIPT

################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

get_sample_name() {
    local fq="$1"
    local base=$(basename "${fq}")
    echo "${base}" | sed -E 's/(_R?[12])(.*)?\.(fastq|fq)(\.gz)?$//'
}

check_file_status() {
    local fq="$1"
    local sample=$(get_sample_name "${fq}")
    local base=$(basename "${fq}" .gz)
    base=$(basename "${base}" .fastq)
    base=$(basename "${base}" .fq)
    
    local status="raw"
    
    [[ -f "qc_reports/fastqc_before/${base}_fastqc.html" ]] && status="fastqc_before"
    
    if [[ -f "trimmed_data/${sample}_R1_trimmed.fastq.gz" ]] || \
       [[ -f "trimmed_data/${sample}_R2_trimmed.fastq.gz" ]] || \
       [[ -f "trimmed_data/${sample}_trimmed.fastq.gz" ]]; then
        status="trimmed"
    fi
    
    if [[ -f "qc_reports/fastqc_after/${sample}_R1_trimmed_fastqc.html" ]] || \
       [[ -f "qc_reports/fastqc_after/${sample}_R2_trimmed_fastqc.html" ]] || \
       [[ -f "qc_reports/fastqc_after/${sample}_trimmed_fastqc.html" ]]; then
        status="complete"
    fi
    
    echo "${status}"
}

parse_multiqc_summary() {
    local json_file="$1"
    local report_type="$2"
    
    [[ ! -f "${json_file}" ]] && { print_warning "MultiQC JSON not found: ${json_file}"; return 1; }
    
    print_header "Quality Metrics Summary (${report_type^} Trimming)"
    
    python3 - "${json_file}" "${report_type}" << 'PYTHON_SCRIPT'
import json
import sys

def extract_metrics(data):
    metrics = {'reads': 0, 'gc': 0.0, 'length': 0.0}
    if not isinstance(data, dict):
        return metrics
    
    # Try different field names for reads
    for field in ['total_sequences', 'Total Sequences', 'FastQC_total_sequences']:
        if field in data and data[field]:
            try:
                metrics['reads'] = int(float(data[field]))
                break
            except:
                continue
    
    # Try different field names for GC
    for field in ['percent_gc', '%GC', 'FastQC_percent_gc']:
        if field in data and data[field]:
            try:
                metrics['gc'] = float(data[field])
                break
            except:
                continue
    
    # Try different field names for length
    for field in ['avg_sequence_length', 'Length', 'FastQC_avg_sequence_length']:
        if field in data and data[field]:
            try:
                metrics['length'] = float(data[field])
                break
            except:
                continue
    
    return metrics

def clean_name(name):
    for s in ['_fastqc', '.fastq.gz', '.fq.gz', '_R1', '_R2', '_trimmed', '_1', '_2']:
        name = name.replace(s, '')
    return name

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    samples_data = {}
    
    # Try different MultiQC JSON structures
    if 'report_general_stats_data' in data:
        # MultiQC can nest data under tool names (e.g., "fastqc")
        for source_name, source_data in data['report_general_stats_data'].items():
            if isinstance(source_data, dict):
                samples_data.update(source_data)
    elif 'report_saved_raw_data' in data:
        if 'multiqc_general_stats' in data['report_saved_raw_data']:
            samples_data = data['report_saved_raw_data']['multiqc_general_stats']
    
    if not samples_data:
        print("━" * 90)
        print("⚠ No metrics data found in MultiQC JSON")
        print("  View HTML report for detailed metrics")
        print("━" * 90)
        sys.exit(0)
    
    print("━" * 90)
    print(f"{'Sample':<40} {'Total Reads':>18} {'%GC':>10} {'Length':>12}")
    print("━" * 90)
    
    total_reads = 0
    sample_count = 0
    seen_samples = set()
    
    for name, metrics_dict in samples_data.items():
        m = extract_metrics(metrics_dict)
        if m['reads'] == 0:
            continue
        
        clean = clean_name(name)
        if clean in seen_samples:
            continue
        seen_samples.add(clean)
        
        print(f"{clean[:40]:<40} {m['reads']:>18,} {m['gc']:>9.1f}% {m['length']:>11.1f}")
        total_reads += m['reads']
        sample_count += 1
    
    if sample_count > 0:
        print("━" * 90)
        print(f"{'Total (' + str(sample_count) + ' samples)':<40} {total_reads:>18,}")
    print("━" * 90)
    print()
    
except FileNotFoundError:
    print(f"ERROR: File not found: {sys.argv[1]}", file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"ERROR: Invalid JSON in {sys.argv[1]}: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

find_all_projects() {
    find "$1" -maxdepth 3 -name ".analysis_mode" -type f 2>/dev/null | while read c; do dirname "$c"; done
}

################################################################################
# STEP 1: PROJECT SELECTION
################################################################################

print_header "STEP 1: Project Selection"
print_info "Scanning for projects..."

PROJECTS=()
PROJECT_MODES=()
PROJECT_PATHS=()

[[ -f ".analysis_mode" ]] && {
    IFS=',' read -r mode env qc_env path < .analysis_mode
    PROJECTS+=("$(basename "$(pwd)")")
    PROJECT_MODES+=("${mode}")
    PROJECT_PATHS+=("$(pwd)")
}

while IFS= read -r pd; do
    [[ -f "${pd}/.analysis_mode" ]] && {
        IFS=',' read -r mode env qc_env path < "${pd}/.analysis_mode"
        PROJECTS+=("$(basename "${pd}")")
        PROJECT_MODES+=("${mode}")
        PROJECT_PATHS+=("${pd}")
    }
done < <(find_all_projects "$(pwd)")

[[ -d "${HOME}/projects" ]] && {
    while IFS= read -r pd; do
        [[ -f "${pd}/.analysis_mode" ]] && {
            IFS=',' read -r mode env qc_env path < "${pd}/.analysis_mode"
            PROJECTS+=("$(basename "${pd}")")
            PROJECT_MODES+=("${mode}")
            PROJECT_PATHS+=("${pd}")
        }
    done < <(find_all_projects "${HOME}/projects")
}

[[ ${#PROJECTS[@]} -eq 0 ]] && { print_error "No projects found"; exit 1; }

echo ""
echo "Found ${#PROJECTS[@]} project(s):"
for i in "${!PROJECTS[@]}"; do
    echo -e "  ${CYAN}$((i+1)).${NC} ${PROJECTS[$i]} ${YELLOW}[${PROJECT_MODES[$i]}]${NC}"
    echo -e "     ${BLUE}${PROJECT_PATHS[$i]}${NC}"
done
echo ""

if [[ ${#PROJECTS[@]} -eq 1 ]]; then
    PROJECT_CHOICE=1
else
    read -p "Select project [1-${#PROJECTS[@]}]: " PROJECT_CHOICE
fi

idx=$((PROJECT_CHOICE - 1))
PROJECT_NAME="${PROJECTS[$idx]}"
PROJECT_ROOT="${PROJECT_PATHS[$idx]}"
ANALYSIS_MODE="${PROJECT_MODES[$idx]}"

print_success "Selected project: ${PROJECT_NAME}"

cd "${PROJECT_ROOT}"

IFS=',' read -r ANALYSIS_MODE CONDA_ENV_NAME QC_ENV _ < .analysis_mode 2>/dev/null || \
    IFS=',' read -r ANALYSIS_MODE CONDA_ENV_NAME QC_ENV < .analysis_mode

mkdir -p raw_data/fastq qc_reports/{fastqc_before,fastqc_after} trimmed_data reproducibility/logs

################################################################################
# STEP 3: ANALYZE FILES
################################################################################

print_header "STEP 3: Analyzing File Status"

ALL_FASTQ=($(find raw_data/fastq -type f \( -name "*.fastq" -o -name "*.fq" -o -name "*.fastq.gz" -o -name "*.fq.gz" \) | sort))
[[ ${#ALL_FASTQ[@]} -eq 0 ]] && { print_error "No FASTQ files found"; exit 1; }

print_info "Found ${#ALL_FASTQ[@]} FASTQ file(s)"
echo ""

declare -A FILE_STATUS
declare -A FILE_NEEDS_FASTQC_BEFORE
declare -A FILE_NEEDS_TRIMMING
declare -A FILE_NEEDS_FASTQC_AFTER

INCOMPLETE_FILES=()

print_info "Checking completion status..."
echo ""

for fq in "${ALL_FASTQ[@]}"; do
    status=$(check_file_status "${fq}")
    FILE_STATUS["${fq}"]="${status}"
    
    case "${status}" in
        "raw")
            FILE_NEEDS_FASTQC_BEFORE["${fq}"]=true
            FILE_NEEDS_TRIMMING["${fq}"]=true
            FILE_NEEDS_FASTQC_AFTER["${fq}"]=true
            INCOMPLETE_FILES+=("${fq}")
            ;;
        "fastqc_before")
            FILE_NEEDS_FASTQC_BEFORE["${fq}"]=false
            FILE_NEEDS_TRIMMING["${fq}"]=true
            FILE_NEEDS_FASTQC_AFTER["${fq}"]=true
            INCOMPLETE_FILES+=("${fq}")
            ;;
        "trimmed")
            FILE_NEEDS_FASTQC_BEFORE["${fq}"]=false
            FILE_NEEDS_TRIMMING["${fq}"]=false
            FILE_NEEDS_FASTQC_AFTER["${fq}"]=true
            INCOMPLETE_FILES+=("${fq}")
            ;;
        "complete")
            FILE_NEEDS_FASTQC_BEFORE["${fq}"]=false
            FILE_NEEDS_TRIMMING["${fq}"]=false
            FILE_NEEDS_FASTQC_AFTER["${fq}"]=false
            ;;
    esac
done

echo "File Status:"
echo ""
echo -e "${MAGENTA}Legend:${NC} ${CYAN}●${NC}=Raw  ${YELLOW}●${NC}=QC done  ${BLUE}●${NC}=Trimmed  ${GREEN}●${NC}=Complete"
echo ""

for fq in "${ALL_FASTQ[@]}"; do
    status="${FILE_STATUS[${fq}]}"
    bn=$(basename "${fq}")
    
    case "${status}" in
        "raw") echo -e "  ${CYAN}●${NC} ${bn}" ;;
        "fastqc_before") echo -e "  ${YELLOW}●${NC} ${bn}" ;;
        "trimmed") echo -e "  ${BLUE}●${NC} ${bn}" ;;
        "complete") echo -e "  ${GREEN}●${NC} ${bn}" ;;
    esac
done

echo ""

NEED_QC=0
NEED_TRIM=0
NEED_POST_QC=0
COMPLETE=0

for fq in "${ALL_FASTQ[@]}"; do
    if [[ "${FILE_NEEDS_FASTQC_BEFORE[${fq}]:-}" == "true" ]]; then
        NEED_QC=$((NEED_QC + 1))
    fi
    if [[ "${FILE_NEEDS_TRIMMING[${fq}]:-}" == "true" ]]; then
        NEED_TRIM=$((NEED_TRIM + 1))
    fi
    if [[ "${FILE_NEEDS_FASTQC_AFTER[${fq}]:-}" == "true" ]]; then
        NEED_POST_QC=$((NEED_POST_QC + 1))
    fi
    if [[ "${FILE_STATUS[${fq}]:-}" == "complete" ]]; then
        COMPLETE=$((COMPLETE + 1))
    fi
done

print_info "Summary: ${NEED_QC} need QC, ${NEED_TRIM} need trim, ${NEED_POST_QC} need post-QC, ${COMPLETE} complete"
echo ""

if [[ ${#INCOMPLETE_FILES[@]} -eq 0 ]]; then
    print_header "All Files Fully Processed!"
    
    [[ -f "qc_reports/multiqc_before_report_data/multiqc_data.json" ]] && \
        parse_multiqc_summary "qc_reports/multiqc_before_report_data/multiqc_data.json" "before"
    
    echo ""
    
    [[ -f "qc_reports/multiqc_after_report_data/multiqc_data.json" ]] && \
        parse_multiqc_summary "qc_reports/multiqc_after_report_data/multiqc_data.json" "after"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Reports:"
    echo "  Before: qc_reports/multiqc_before_report.html"
    echo "  After:  qc_reports/multiqc_after_report.html"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi

################################################################################
# STEP 4: FILE SELECTION
################################################################################

print_header "STEP 4: File Selection"

print_info "All incomplete files:"
echo ""

for i in "${!INCOMPLETE_FILES[@]}"; do
    fq="${INCOMPLETE_FILES[$i]}"
    status="${FILE_STATUS[${fq}]}"
    bn=$(basename "${fq}")
    
    needs=""
    [[ "${FILE_NEEDS_FASTQC_BEFORE[${fq}]}" == "true" ]] && needs+="QC→"
    [[ "${FILE_NEEDS_TRIMMING[${fq}]}" == "true" ]] && needs+="Trim→"
    [[ "${FILE_NEEDS_FASTQC_AFTER[${fq}]}" == "true" ]] && needs+="PostQC"
    needs="${needs%→}"
    
    case "${status}" in
        "raw") echo -e "  ${CYAN}$((i+1)).${NC} ${bn} ${CYAN}(needs: ${needs})${NC}" ;;
        "fastqc_before") echo -e "  ${YELLOW}$((i+1)).${NC} ${bn} ${YELLOW}(needs: ${needs})${NC}" ;;
        "trimmed") echo -e "  ${BLUE}$((i+1)).${NC} ${bn} ${BLUE}(needs: ${needs})${NC}" ;;
    esac
done

echo ""
read -p "Process all ${#INCOMPLETE_FILES[@]} incomplete files? [Y/n]: " process_all

if [[ "${process_all}" =~ ^[Nn]$ ]]; then
    echo ""
    print_info "Enter file numbers (e.g., 1,2,5-8)"
    read -p "Files to process: " indices
    
    SELECTED=()
    IFS=',' read -ra nums <<< "${indices}"
    for n in "${nums[@]}"; do
        n=$(echo "$n" | xargs)
        if [[ "$n" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            for ((j=${BASH_REMATCH[1]}; j<=${BASH_REMATCH[2]}; j++)); do
                if [[ $j -ge 1 && $j -le ${#INCOMPLETE_FILES[@]} ]]; then
                    SELECTED+=("${INCOMPLETE_FILES[$((j-1))]}")
                fi
            done
        elif [[ "$n" =~ ^[0-9]+$ ]]; then
            if [[ $n -ge 1 && $n -le ${#INCOMPLETE_FILES[@]} ]]; then
                SELECTED+=("${INCOMPLETE_FILES[$((n-1))]}")
            fi
        fi
    done
    FASTQ_FILES=("${SELECTED[@]}")
else
    FASTQ_FILES=("${INCOMPLETE_FILES[@]}")
fi

[[ ${#FASTQ_FILES[@]} -eq 0 ]] && { print_error "No files selected"; exit 1; }

print_success "Will process ${#FASTQ_FILES[@]} file(s)"
echo ""
print_info "Selected files and their needs:"
for fq in "${FASTQ_FILES[@]}"; do
    bn=$(basename "${fq}")
    needs=""
    [[ "${FILE_NEEDS_FASTQC_BEFORE[${fq}]}" == "true" ]] && needs+="QC→"
    [[ "${FILE_NEEDS_TRIMMING[${fq}]}" == "true" ]] && needs+="Trim→"
    [[ "${FILE_NEEDS_FASTQC_AFTER[${fq}]}" == "true" ]] && needs+="PostQC"
    needs="${needs%→}"
    echo "  • ${bn} (${needs})"
done

SELECTED_FILES_LIST="reproducibility/logs/selected_files.txt"
> "${SELECTED_FILES_LIST}"
for fq in "${FASTQ_FILES[@]}"; do
    status="${FILE_STATUS[${fq}]}"
    needs_qc="${FILE_NEEDS_FASTQC_BEFORE[${fq}]}"
    needs_trim="${FILE_NEEDS_TRIMMING[${fq}]}"
    needs_postqc="${FILE_NEEDS_FASTQC_AFTER[${fq}]}"
    echo "${fq}|${status}|${needs_qc}|${needs_trim}|${needs_postqc}" >> "${SELECTED_FILES_LIST}"
done

RUN_FASTQC_BEFORE=false
RUN_TRIMMING=false
RUN_FASTQC_AFTER=false

for fq in "${FASTQ_FILES[@]}"; do
    [[ "${FILE_NEEDS_FASTQC_BEFORE[${fq}]}" == "true" ]] && RUN_FASTQC_BEFORE=true
    [[ "${FILE_NEEDS_TRIMMING[${fq}]}" == "true" ]] && RUN_TRIMMING=true
    [[ "${FILE_NEEDS_FASTQC_AFTER[${fq}]}" == "true" ]] && RUN_FASTQC_AFTER=true
done

echo ""
print_info "Pipeline will run:"
[[ "${RUN_FASTQC_BEFORE}" == "true" ]] && echo "  • FastQC before (for files that need it)"
[[ "${RUN_TRIMMING}" == "true" ]] && echo "  • Trimming (for files that need it)"
[[ "${RUN_FASTQC_AFTER}" == "true" ]] && echo "  • FastQC after (for files that need it)"

R1_TRIM=()
R2_TRIM=()

for fq in "${FASTQ_FILES[@]}"; do
    if [[ "${FILE_NEEDS_TRIMMING[${fq}]}" == "true" ]]; then
        if [[ "${fq}" =~ _R?1[._]|_1\.f ]]; then
            R1_TRIM+=("${fq}")
        elif [[ "${fq}" =~ _R?2[._]|_2\.f ]]; then
            R2_TRIM+=("${fq}")
        fi
    fi
done

if [[ ${#R1_TRIM[@]} -gt 0 && ${#R1_TRIM[@]} -eq ${#R2_TRIM[@]} ]]; then
    LAYOUT="paired"
else
    LAYOUT="single"
fi

################################################################################
# ENVIRONMENT
################################################################################

REQUIRED_TOOLS=("fastqc" "multiqc" "trimmomatic")
check_tool() { conda run -n "$1" command -v "$2" &>/dev/null 2>&1; }

print_info "Checking environments..."

CONDA_ENVS=$(conda env list | grep -v "^#" | grep -v "^base " | awk '{print $1}' | grep -v "^$")
VALID_ENVS=()

for env in ${CONDA_ENVS}; do
    all_ok=true
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! check_tool "${env}" "${tool}"; then
            all_ok=false
            break
        fi
    done
    [[ "${all_ok}" == true ]] && VALID_ENVS+=("${env}")
done

if [[ ${#VALID_ENVS[@]} -gt 0 ]]; then
    SELECTED_ENV="${VALID_ENVS[0]}"
else
    SELECTED_ENV="${QC_ENV}"
    if ! conda env list | grep -q "^${SELECTED_ENV} "; then
        print_info "Creating: ${SELECTED_ENV}"
        conda create -n "${SELECTED_ENV}" -c bioconda -c conda-forge fastqc multiqc trimmomatic -y
    fi
fi

CONDA_BASE=$(conda info --base)
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "${SELECTED_ENV}"

print_success "Environment: ${SELECTED_ENV}"

TRIMMOMATIC_PATH=$(which trimmomatic 2>/dev/null || echo "")
[[ -z "${TRIMMOMATIC_PATH}" ]] && { print_error "Trimmomatic not found"; exit 1; }

print_success "Trimmomatic: ${TRIMMOMATIC_PATH}"

ADAPTER_DIR=$(dirname $(dirname "${TRIMMOMATIC_PATH}"))/share/trimmomatic/adapters
[[ ! -d "${ADAPTER_DIR}" ]] && ADAPTER_DIR=$(echo $(dirname $(dirname "${TRIMMOMATIC_PATH}"))/share/trimmomatic-*/adapters | awk '{print $1}')

[[ -d "${ADAPTER_DIR}" ]] && print_success "Adapters: ${ADAPTER_DIR}" || { print_warning "Adapters not found"; ADAPTER_DIR=""; }

################################################################################
# SCREEN
################################################################################

print_header "STEP 7: Execution Mode"

read -p "Use screen? [Y/n]: " use_screen

USE_SCREEN=true
SCREEN_NAME="qc_${PROJECT_NAME}"

if [[ "${use_screen}" =~ ^[Nn]$ ]]; then
    USE_SCREEN=false
    print_info "Running in foreground"
else
    if screen -list 2>/dev/null | grep -q "${SCREEN_NAME}"; then
        read -p "Kill existing screen? [Y/n]: " kill_screen
        [[ ! "${kill_screen}" =~ ^[Nn]$ ]] && screen -S "${SCREEN_NAME}" -X quit 2>/dev/null
    fi
    print_success "Will use: ${SCREEN_NAME}"
fi

################################################################################
# CREATE WORKFLOW
################################################################################

print_header "STEP 8: Preparing Workflow"

THREADS=$(nproc 2>/dev/null || echo 4)
WORKFLOW_LOG="reproducibility/logs/qc_workflow.log"

print_info "Files: ${#FASTQ_FILES[@]}"
print_info "Threads: ${THREADS}"
[[ "${RUN_TRIMMING}" == "true" ]] && print_info "Layout: ${LAYOUT}"

rm -f qc_reports/.{proceed_with_trimming,trimming_params,multiqc_before_done,multiqc_after_done}
rm -f trimmed_data/.trimming_done reproducibility/logs/.workflow_error

QC_SCRIPT="reproducibility/logs/qc_workflow.sh"

cat > "${QC_SCRIPT}" << 'WORKFLOW_EOF'
#!/bin/bash
set -uo pipefail

PROJECT_ROOT="__PROJECT_ROOT__"
CONDA_BASE="__CONDA_BASE__"
SELECTED_ENV="__SELECTED_ENV__"
THREADS="__THREADS__"
RUN_FASTQC_BEFORE="__RUN_FASTQC_BEFORE__"
RUN_TRIMMING="__RUN_TRIMMING__"
RUN_FASTQC_AFTER="__RUN_FASTQC_AFTER__"
WORKFLOW_LOG="__WORKFLOW_LOG__"
SELECTED_FILES_LIST="__SELECTED_FILES_LIST__"

exec > >(tee -a "${WORKFLOW_LOG}") 2>&1

echo "=========================================="
echo "QC Workflow: $(date)"
echo "=========================================="
echo ""

cd "${PROJECT_ROOT}"
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "${SELECTED_ENV}"

declare -A FILE_STATUS
declare -A FILE_NEEDS_QC
declare -A FILE_NEEDS_TRIM
declare -A FILE_NEEDS_POSTQC
ALL_FILES=()

while IFS='|' read -r file status needs_qc needs_trim needs_postqc; do
    ALL_FILES+=("${file}")
    FILE_STATUS["${file}"]="${status}"
    FILE_NEEDS_QC["${file}"]="${needs_qc}"
    FILE_NEEDS_TRIM["${file}"]="${needs_trim}"
    FILE_NEEDS_POSTQC["${file}"]="${needs_postqc}"
done < "${SELECTED_FILES_LIST}"

echo "Processing ${#ALL_FILES[@]} files"
echo ""

trap 'echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "✗ ERROR at line ${LINENO}"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo ""; echo "Check log: ${WORKFLOW_LOG}"; echo ""; echo "Press Enter to close screen..."; read; exit 1' ERR

if [[ "${RUN_FASTQC_BEFORE}" == "true" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "FastQC Before"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    FILES_FOR_QC=()
    for file in "${ALL_FILES[@]}"; do
        if [[ "${FILE_NEEDS_QC[${file}]}" == "true" ]]; then
            FILES_FOR_QC+=("${file}")
            echo "  - $(basename "${file}")"
        fi
    done
    
    if [[ ${#FILES_FOR_QC[@]} -gt 0 ]]; then
        echo ""
        fastqc -t ${THREADS} -o qc_reports/fastqc_before/ "${FILES_FOR_QC[@]}"
        echo ""
        echo "✓ FastQC before done for ${#FILES_FOR_QC[@]} files"
    fi
    
    echo "Updating MultiQC report..."
    multiqc qc_reports/fastqc_before/ -o qc_reports/ -n multiqc_before_report --force --quiet
    echo "✓ MultiQC updated"
    touch qc_reports/.multiqc_before_done
fi

if [[ "${RUN_TRIMMING}" == "true" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Waiting for user decision..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    WAIT=0
    while [[ ! -f qc_reports/.proceed_with_trimming ]]; do
        sleep 2
        WAIT=$((WAIT + 1))
        if [[ $((WAIT % 15)) -eq 0 ]]; then
            echo "[$(date +%H:%M:%S)] Waiting..."
        fi
    done
    
    echo "✓ Proceeding with trimming"
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Trimming"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [[ ! -f qc_reports/.trimming_params ]]; then
        echo "✗ No trimming parameters file found!"
        echo ""
        echo "Press Enter to close screen..."
        read
        exit 1
    fi
    
    QUALITY=20
    MIN_LEN=50
    LEADING=3
    TRAILING=3
    SLIDINGWINDOW="4:15"
    ADAPTER_FILE=""
    ADAPTER_SEED_MISMATCHES=2
    ADAPTER_PALINDROME_CLIP_THRESHOLD=30
    ADAPTER_SIMPLE_CLIP_THRESHOLD=10
    
    source qc_reports/.trimming_params
    
    echo "Parameters:"
    echo "  Quality: Q${QUALITY}"
    echo "  Min length: ${MIN_LEN}bp"
    echo "  Leading: ${LEADING}"
    echo "  Trailing: ${TRAILING}"
    echo "  Sliding window: ${SLIDINGWINDOW}"
    if [[ -n "${ADAPTER_FILE}" && -f "${ADAPTER_FILE}" ]]; then
        echo "  Adapter file: $(basename ${ADAPTER_FILE})"
        echo "  Adapter seed mismatches: ${ADAPTER_SEED_MISMATCHES}"
        echo "  Adapter palindrome clip threshold: ${ADAPTER_PALINDROME_CLIP_THRESHOLD}"
        echo "  Adapter simple clip threshold: ${ADAPTER_SIMPLE_CLIP_THRESHOLD}"
    fi
    echo ""
    
    R1_TO_TRIM=()
    R2_TO_TRIM=()
    SE_TO_TRIM=()
    
    for file in "${ALL_FILES[@]}"; do
        if [[ "${FILE_NEEDS_TRIM[${file}]}" == "true" ]]; then
            if [[ "${file}" =~ _R?1[._]|_1\.f ]]; then
                R1_TO_TRIM+=("${file}")
            elif [[ "${file}" =~ _R?2[._]|_2\.f ]]; then
                R2_TO_TRIM+=("${file}")
            else
                SE_TO_TRIM+=("${file}")
            fi
        fi
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Memory Calculation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    TOTAL_SIZE=0
    for file in "${ALL_FILES[@]}"; do
        if [[ "${FILE_NEEDS_TRIM[${file}]}" == "true" && -f "${file}" ]]; then
            SIZE=$(stat -c%s "${file}" 2>/dev/null || stat -f%z "${file}" 2>/dev/null || echo 0)
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
        fi
    done
    
    SIZE_GB=$((TOTAL_SIZE / 1024 / 1024 / 1024 + 1))
    REQUIRED_HEAP=$((SIZE_GB * 4))
    
    [[ ${REQUIRED_HEAP} -lt 4 ]] && REQUIRED_HEAP=4
    [[ ${REQUIRED_HEAP} -gt 32 ]] && REQUIRED_HEAP=32
    
    echo "Total input size: ~${SIZE_GB}GB"
    echo "Allocating ${REQUIRED_HEAP}GB Java heap memory"
    echo ""
    
    export _JAVA_OPTIONS="-Xmx${REQUIRED_HEAP}g -Xms2g"
    
    if [[ ${#R1_TO_TRIM[@]} -gt 0 && ${#R1_TO_TRIM[@]} -eq ${#R2_TO_TRIM[@]} ]]; then
        echo "Layout: Paired-end (${#R1_TO_TRIM[@]} pairs)"
        echo ""
        
        for i in "${!R1_TO_TRIM[@]}"; do
            r1="${R1_TO_TRIM[$i]}"
            r2="${R2_TO_TRIM[$i]}"
            sample=$(basename "${r1}" | sed -E 's/_R?[12][._].*//')
            
            echo "Processing: ${sample}"
            
            if [[ -n "${ADAPTER_FILE}" && -f "${ADAPTER_FILE}" ]]; then
                ILLUMINACLIP_PARAM="ILLUMINACLIP:${ADAPTER_FILE}:${ADAPTER_SEED_MISMATCHES}:${ADAPTER_PALINDROME_CLIP_THRESHOLD}:${ADAPTER_SIMPLE_CLIP_THRESHOLD}"
            else
                ILLUMINACLIP_PARAM=""
            fi
            
            trimmomatic PE -threads ${THREADS} -phred33 \
                "${r1}" "${r2}" \
                "trimmed_data/${sample}_R1_trimmed.fastq.gz" \
                "trimmed_data/${sample}_R1_unpaired.fastq.gz" \
                "trimmed_data/${sample}_R2_trimmed.fastq.gz" \
                "trimmed_data/${sample}_R2_unpaired.fastq.gz" \
                ${ILLUMINACLIP_PARAM:+${ILLUMINACLIP_PARAM}} \
                LEADING:${LEADING} \
                TRAILING:${TRAILING} \
                SLIDINGWINDOW:${SLIDINGWINDOW} \
                MINLEN:${MIN_LEN} \
                2>&1 | tee "reproducibility/logs/${sample}_trimmomatic.log"
            
            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                echo ""
                echo "✗ Trimming failed for ${sample}"
                echo ""
                echo "Press Enter to close screen..."
                read
                exit 1
            fi
            
            echo "✓ ${sample} done"
            echo ""
        done
    fi
    
    if [[ ${#SE_TO_TRIM[@]} -gt 0 ]]; then
        echo "Layout: Single-end (${#SE_TO_TRIM[@]} files)"
        echo ""
        
        for fq in "${SE_TO_TRIM[@]}"; do
            sample=$(basename "${fq}" | sed -E 's/\.(fastq|fq)(\.gz)?$//')
            
            echo "Processing: ${sample}"
            
            if [[ -n "${ADAPTER_FILE}" && -f "${ADAPTER_FILE}" ]]; then
                ILLUMINACLIP_PARAM="ILLUMINACLIP:${ADAPTER_FILE}:${ADAPTER_SEED_MISMATCHES}:${ADAPTER_PALINDROME_CLIP_THRESHOLD}:${ADAPTER_SIMPLE_CLIP_THRESHOLD}"
            else
                ILLUMINACLIP_PARAM=""
            fi
            
            trimmomatic SE -threads ${THREADS} -phred33 \
                "${fq}" \
                "trimmed_data/${sample}_trimmed.fastq.gz" \
                ${ILLUMINACLIP_PARAM:+${ILLUMINACLIP_PARAM}} \
                LEADING:${LEADING} \
                TRAILING:${TRAILING} \
                SLIDINGWINDOW:${SLIDINGWINDOW} \
                MINLEN:${MIN_LEN} \
                2>&1 | tee "reproducibility/logs/${sample}_trimmomatic.log"
            
            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                echo ""
                echo "✗ Trimming failed for ${sample}"
                echo ""
                echo "Press Enter to close screen..."
                read
                exit 1
            fi
            
            echo "✓ ${sample} done"
            echo ""
        done
    fi
    
    echo "✓ Trimming complete"
    touch trimmed_data/.trimming_done
fi

if [[ "${RUN_FASTQC_AFTER}" == "true" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "FastQC After"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    ALL_TRIMMED=($(find trimmed_data -name "*_trimmed.fastq.gz" 2>/dev/null | sort))
    
    if [[ ${#ALL_TRIMMED[@]} -eq 0 ]]; then
        echo "✗ No trimmed files found!"
        echo ""
        echo "Expected files in trimmed_data/ matching *_trimmed.fastq.gz"
        echo ""
        echo "Press Enter to close screen..."
        read
        exit 1
    fi
    
    echo "Found ${#ALL_TRIMMED[@]} trimmed files"
    echo ""
    
    FILES_FOR_POSTQC=()
    for trimmed in "${ALL_TRIMMED[@]}"; do
        base=$(basename "${trimmed}" .gz)
        base=$(basename "${base}" .fastq)
        
        if [[ ! -f "qc_reports/fastqc_after/${base}_fastqc.html" ]]; then
            FILES_FOR_POSTQC+=("${trimmed}")
            echo "  - $(basename "${trimmed}") (needs QC)"
        else
            echo "  - $(basename "${trimmed}") (already done)"
        fi
    done
    
    if [[ ${#FILES_FOR_POSTQC[@]} -gt 0 ]]; then
        echo ""
        echo "Running FastQC on ${#FILES_FOR_POSTQC[@]} files..."
        
        fastqc -t ${THREADS} -o qc_reports/fastqc_after/ "${FILES_FOR_POSTQC[@]}"
        
        if [[ $? -ne 0 ]]; then
            echo ""
            echo "✗ FastQC after failed!"
            echo ""
            echo "Check the error messages above"
            echo ""
            echo "Press Enter to close screen..."
            read
            exit 1
        fi
        
        echo ""
        echo "✓ FastQC after done for ${#FILES_FOR_POSTQC[@]} new files"
    fi
    
    echo ""
    echo "Updating MultiQC report..."
    multiqc qc_reports/fastqc_after/ -o qc_reports/ -n multiqc_after_report --force --quiet
    
    if [[ $? -ne 0 ]]; then
        echo "✗ MultiQC after failed!"
        echo ""
        echo "Check the error messages above"
        echo ""
        echo "Press Enter to close screen..."
        read
        exit 1
    fi
    
    echo "✓ MultiQC updated"
    touch qc_reports/.multiqc_after_done
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Workflow Complete: $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Reports available:"
echo "  - qc_reports/multiqc_before_report.html"
echo "  - qc_reports/multiqc_after_report.html"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Press Enter to close this screen..."
read
WORKFLOW_EOF

sed -i "s|__PROJECT_ROOT__|${PROJECT_ROOT}|g" "${QC_SCRIPT}"
sed -i "s|__CONDA_BASE__|${CONDA_BASE}|g" "${QC_SCRIPT}"
sed -i "s|__SELECTED_ENV__|${SELECTED_ENV}|g" "${QC_SCRIPT}"
sed -i "s|__THREADS__|${THREADS}|g" "${QC_SCRIPT}"
sed -i "s|__RUN_FASTQC_BEFORE__|${RUN_FASTQC_BEFORE}|g" "${QC_SCRIPT}"
sed -i "s|__RUN_TRIMMING__|${RUN_TRIMMING}|g" "${QC_SCRIPT}"
sed -i "s|__RUN_FASTQC_AFTER__|${RUN_FASTQC_AFTER}|g" "${QC_SCRIPT}"
sed -i "s|__WORKFLOW_LOG__|${WORKFLOW_LOG}|g" "${QC_SCRIPT}"
sed -i "s|__SELECTED_FILES_LIST__|${SELECTED_FILES_LIST}|g" "${QC_SCRIPT}"

chmod +x "${QC_SCRIPT}"
print_success "Workflow ready"

################################################################################
# LAUNCH
################################################################################

print_header "STEP 9: Launching"

if [[ "${USE_SCREEN}" == "true" ]]; then
    screen -dmS "${SCREEN_NAME}" bash "${QC_SCRIPT}"
    print_success "Started: ${SCREEN_NAME}"
    echo ""
    print_info "Monitor: screen -r ${SCREEN_NAME}"
    print_info "Log: tail -f ${WORKFLOW_LOG}"
    echo ""
    
    sleep 2
else
    bash "${QC_SCRIPT}"
    exit 0
fi

################################################################################
# MONITOR & INTERACT
################################################################################

if [[ "${RUN_FASTQC_BEFORE}" == "true" ]]; then
    print_info "Waiting for FastQC before..."
    while [[ ! -f "qc_reports/.multiqc_before_done" ]] && [[ ! -f "reproducibility/logs/.workflow_error" ]]; do
        sleep 2
        echo -n "."
    done
    echo ""
    
    [[ -f "reproducibility/logs/.workflow_error" ]] && { print_error "Error in workflow!"; exit 1; }
    print_success "FastQC before done"
    
    print_header "STEP 10: Quality Summary (Before)"
    
    MULTIQC_JSON="qc_reports/multiqc_before_report_data/multiqc_data.json"
    if [[ -f "${MULTIQC_JSON}" ]]; then
        parse_multiqc_summary "${MULTIQC_JSON}" "before" || print_warning "Could not parse MultiQC summary"
    else
        print_warning "MultiQC JSON not found yet: ${MULTIQC_JSON}"
    fi
    
    echo ""
    echo -e "${BLUE}Report:${NC} ${CYAN}qc_reports/multiqc_before_report.html${NC}"
fi

if [[ "${RUN_TRIMMING}" == "true" ]]; then
    print_header "STEP 11: Trimming Decision"
    
    read -p "Proceed with trimming? [Y/n]: " do_trim
    
    if [[ "${do_trim}" =~ ^[Nn]$ ]]; then
        screen -S "${SCREEN_NAME}" -X quit 2>/dev/null
        print_success "Stopped"
        exit 0
    fi
    
    print_header "STEP 12: Trimmomatic Config"
    
    echo "Defaults:"
    echo "  Quality: Q20"
    echo "  Min length: 50bp"
    echo "  Leading: 3"
    echo "  Trailing: 3"
    echo "  Sliding window: 4:15"
    echo "  Adapter parameters: seedMismatches=2, palindromeClipThreshold=30, simpleClipThreshold=10"
    echo ""
    
    QUALITY=20
    MIN_LEN=50
    LEADING=3
    TRAILING=3
    SLIDINGWINDOW="4:15"
    ADAPTER_FILE=""
    ADAPTER_SEED_MISMATCHES=2
    ADAPTER_PALINDROME_CLIP_THRESHOLD=30
    ADAPTER_SIMPLE_CLIP_THRESHOLD=10
    
    read -p "Modify parameters? [y/N]: " modify
    
    if [[ "${modify}" =~ ^[Yy]$ ]]; then
        read -p "Quality [20]: " q; QUALITY="${q:-20}"
        read -p "Min length [50]: " l; MIN_LEN="${l:-50}"
        read -p "Leading [3]: " lead; LEADING="${lead:-3}"
        read -p "Trailing [3]: " trail; TRAILING="${trail:-3}"
        read -p "Sliding window [4:15]: " sw; SLIDINGWINDOW="${sw:-4:15}"
        
        if [[ -n "${ADAPTER_DIR}" && -d "${ADAPTER_DIR}" ]]; then
            echo ""
            echo "Layout: ${LAYOUT}"
            echo ""
            
            ADAPTERS=($(find "${ADAPTER_DIR}" -name "*.fa" -type f | sort))
            
            if [[ ${#ADAPTERS[@]} -gt 0 ]]; then
                echo "Available adapters:"
                for i in "${!ADAPTERS[@]}"; do
                    adapter_name=$(basename "${ADAPTERS[$i]}")
                    
                    if [[ "${LAYOUT}" == "paired" ]]; then
                        if [[ "${adapter_name}" == *"-PE"* ]] || [[ "${adapter_name}" == "NexteraPE"* ]]; then
                            echo -e "  ${GREEN}$((i+1)).${NC} ${adapter_name} ${GREEN}(compatible)${NC}"
                        else
                            echo -e "  ${YELLOW}$((i+1)).${NC} ${adapter_name} ${YELLOW}(single-end)${NC}"
                        fi
                    else
                        if [[ "${adapter_name}" == *"-SE"* ]]; then
                            echo -e "  ${GREEN}$((i+1)).${NC} ${adapter_name} ${GREEN}(compatible)${NC}"
                        else
                            echo -e "  ${YELLOW}$((i+1)).${NC} ${adapter_name} ${YELLOW}(paired-end)${NC}"
                        fi
                    fi
                done
                echo ""
                read -p "Select adapter (or Enter to skip): " choice
                
                if [[ -n "${choice}" ]] && [[ "${choice}" =~ ^[0-9]+$ ]]; then
                    idx=$((choice - 1))
                    if [[ ${idx} -ge 0 && ${idx} -lt ${#ADAPTERS[@]} ]]; then
                        ADAPTER_FILE="${ADAPTERS[$idx]}"
                        
                        echo ""
                        echo "Adapter parameters (for ILLUMINACLIP):"
                        read -p "  Seed mismatches [2]: " sm; ADAPTER_SEED_MISMATCHES="${sm:-2}"
                        read -p "  Palindrome clip threshold [30]: " pct; ADAPTER_PALINDROME_CLIP_THRESHOLD="${pct:-30}"
                        read -p "  Simple clip threshold [10]: " sct; ADAPTER_SIMPLE_CLIP_THRESHOLD="${sct:-10}"
                    fi
                fi
            fi
        fi
    fi
    
    echo ""
    print_success "Config: Q${QUALITY}, ${MIN_LEN}bp, Leading:${LEADING}, Trailing:${TRAILING}, SW:${SLIDINGWINDOW}"
    if [[ -n "${ADAPTER_FILE}" ]]; then
        print_success "Adapter: $(basename "${ADAPTER_FILE}") (${ADAPTER_SEED_MISMATCHES}:${ADAPTER_PALINDROME_CLIP_THRESHOLD}:${ADAPTER_SIMPLE_CLIP_THRESHOLD})"
    fi
    
    cat > qc_reports/.trimming_params << PARAMS
QUALITY=${QUALITY}
MIN_LEN=${MIN_LEN}
LEADING=${LEADING}
TRAILING=${TRAILING}
SLIDINGWINDOW="${SLIDINGWINDOW}"
ADAPTER_FILE="${ADAPTER_FILE}"
ADAPTER_SEED_MISMATCHES=${ADAPTER_SEED_MISMATCHES}
ADAPTER_PALINDROME_CLIP_THRESHOLD=${ADAPTER_PALINDROME_CLIP_THRESHOLD}
ADAPTER_SIMPLE_CLIP_THRESHOLD=${ADAPTER_SIMPLE_CLIP_THRESHOLD}
PARAMS
    
    touch qc_reports/.proceed_with_trimming
    
    print_header "STEP 13: Running Trimming"
    print_info "Trimming in progress..."
    
    while [[ ! -f "trimmed_data/.trimming_done" ]] && screen -list 2>/dev/null | grep -q "${SCREEN_NAME}"; do
        sleep 3
        echo -n "."
    done
    echo ""
    
    [[ -f "reproducibility/logs/.workflow_error" ]] && { print_error "Trimming failed!"; exit 1; }
    print_success "Trimming done"
fi

if [[ "${RUN_FASTQC_AFTER}" == "true" ]]; then
    print_header "STEP 14: Running Post-QC"
    print_info "FastQC after in progress..."
    
    while [[ ! -f "qc_reports/.multiqc_after_done" ]] && screen -list 2>/dev/null | grep -q "${SCREEN_NAME}"; do
        sleep 3
        echo -n "."
    done
    echo ""
    
    [[ -f "reproducibility/logs/.workflow_error" ]] && { print_error "FastQC after failed!"; exit 1; }
    print_success "FastQC after done"
fi

################################################################################
# FINAL SUMMARY
################################################################################

print_header "STEP 15: Final Results"

MULTIQC_BEFORE="qc_reports/multiqc_before_report_data/multiqc_data.json"
MULTIQC_AFTER="qc_reports/multiqc_after_report_data/multiqc_data.json"

if [[ -f "${MULTIQC_BEFORE}" ]]; then
    parse_multiqc_summary "${MULTIQC_BEFORE}" "before" || print_warning "Could not parse before summary"
else
    print_warning "MultiQC before report not found: ${MULTIQC_BEFORE}"
fi

echo ""

if [[ -f "${MULTIQC_AFTER}" ]]; then
    parse_multiqc_summary "${MULTIQC_AFTER}" "after" || print_warning "Could not parse after summary"
else
    print_warning "MultiQC after report not found: ${MULTIQC_AFTER}"
fi

echo ""
print_success "Pipeline Complete! ✨"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Reports:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Before: ${CYAN}qc_reports/multiqc_before_report.html${NC}"
echo -e "  After:  ${CYAN}qc_reports/multiqc_after_report.html${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "Screen ${SCREEN_NAME} will stay open until you confirm closure inside it."
echo ""
print_info "To check status: screen -r ${SCREEN_NAME}"
echo ""
