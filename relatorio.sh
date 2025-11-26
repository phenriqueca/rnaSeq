#!/bin/bash

################################################################################
# REPORT GENERATOR 
################################################################################

set -euo pipefail

# --- COLORS ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

find_all_projects() {
    find "$1" -maxdepth 3 -name ".analysis_mode" -type f 2>/dev/null | while read c; do dirname "$c"; done
}

clear
echo -e "${BOLD}INITIALIZING REPORT GENERATOR V8.1...${NC}"

################################################################################
# PASSO 1: SELEÇÃO DO PROJETO
################################################################################

PROJECTS=()
PROJECT_PATHS=()
SCRIPT_SOURCE_DIR=$(pwd)

while IFS= read -r pd; do
    PROJECTS+=("$(basename "${pd}")")
    PROJECT_PATHS+=("${pd}")
done < <(find_all_projects "$(pwd)")

[[ -d "${HOME}/projects" ]] && {
    while IFS= read -r pd; do
        PROJECTS+=("$(basename "${pd}")")
        PROJECT_PATHS+=("${pd}")
    done < <(find_all_projects "${HOME}/projects")
}

if [[ ${#PROJECTS[@]} -eq 0 ]]; then echo -e "${RED}No projects found.${NC}"; exit 1; fi

echo ""
echo "Available Projects:"
for i in "${!PROJECTS[@]}"; do
    echo -e "  ${CYAN}$((i+1)).${NC} ${PROJECTS[$i]}"
done
echo ""

if [[ ${#PROJECTS[@]} -eq 1 ]]; then
    idx=0
else
    read -p "Select Project [1-${#PROJECTS[@]}]: " PROJECT_CHOICE
    idx=$((PROJECT_CHOICE - 1))
fi

PROJECT_NAME="${PROJECTS[$idx]}"
PROJECT_ROOT="${PROJECT_PATHS[$idx]}"

cd "${PROJECT_ROOT}"

if [[ ! -f ".analysis_mode" ]]; then echo "Invalid configuration."; exit 1; fi

IFS=',' read -r MODE ENV QC_ENV PROJECT_PATH < .analysis_mode
DATE=$(date +"%Y-%m-%d %H:%M")

################################################################################
# PASSO 2: COLETA DE DADOS COMPLETA
################################################################################

# Params (Agora lê TUDO do Trimmomatic)
TRIM_PARAMS_FILE="qc_reports/.trimming_params"
if [[ -f "$TRIM_PARAMS_FILE" ]]; then
    source "$TRIM_PARAMS_FILE"
    ADAPTER_NAME=$(basename "${ADAPTER_FILE:-None}")
    # Defaults para variaveis extras se não existirem no arquivo antigo
    SEED=${ADAPTER_SEED_MISMATCHES:-2}
    PCT=${ADAPTER_PALINDROME_CLIP_THRESHOLD:-30}
    SCT=${ADAPTER_SIMPLE_CLIP_THRESHOLD:-10}
else
    QUALITY="N/A"; MIN_LEN="N/A"; LEADING="N/A"; TRAILING="N/A"; SLIDINGWINDOW="N/A"; ADAPTER_NAME="N/A"
    SEED="N/A"; PCT="N/A"; SCT="N/A"
fi

# Versões
V_FASTQC=$(fastqc --version 2>/dev/null | awk '{print $2}' || echo "N/A")
V_MULTIQC=$(multiqc --version 2>/dev/null | grep -oE "version [0-9.]+" | awk '{print $2}' || echo "N/A")
V_TRIM="0.39"

export P_NAME="$PROJECT_NAME" P_DATE="$DATE" P_MODE="$MODE" P_ENV="$ENV" P_ROOT="$PROJECT_ROOT"
# Exportar TODAS as variáveis de trimming
export T_QUAL="$QUALITY" T_LEN="$MIN_LEN" T_LEAD="$LEADING" T_TRAIL="$TRAILING" T_SLIDE="$SLIDINGWINDOW" T_ADAPT="$ADAPTER_NAME"
export T_SEED="$SEED" T_PCT="$PCT" T_SCT="$SCT"
export V_FASTQC="$V_FASTQC" V_MULTIQC="$V_MULTIQC" V_TRIM="$V_TRIM"

REPORT_FILE="results/${PROJECT_NAME}_final_report.md"
mkdir -p results

################################################################################
# PASSO 3: GERAÇÃO DO RELATÓRIO (PYTHON)
################################################################################

python3 - << 'EOF'
import json, sys, os

# --- VISUAL SETUP ---
C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_CYAN = "\033[36m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_RED = "\033[31m"
C_BLUE = "\033[34m"
C_DIM = "\033[2m"

def print_box(title, color=C_BLUE):
    print(f"\n{color}{C_BOLD}┌────────────────────────────────────────────────────────────────────────┐{C_RESET}")
    print(f"{color}{C_BOLD}│ {title.center(70)} │{C_RESET}")
    print(f"{color}{C_BOLD}└────────────────────────────────────────────────────────────────────────┘{C_RESET}\n")

# --- INPUTS ---
env = os.environ
p_name = env.get("P_NAME", "Unknown")

# Trimmomatic Params
t_adapt = env.get("T_ADAPT", "N/A")
t_seed = env.get("T_SEED", "2")
t_pct = env.get("T_PCT", "30")
t_sct = env.get("T_SCT", "10")

json_pre = "qc_reports/multiqc_before_report_data/multiqc_data.json"
json_post = "qc_reports/multiqc_after_report_data/multiqc_data.json"

samples_data = []

# --- CLEANING FUNCTION ---
def normalize_name(n):
    for ext in [".fastq.gz", ".fq.gz", ".fastq", ".fq", ".gz"]:
        n = n.replace(ext, "")
    for junk in ["_fastqc", "MultiQC", "_trimmed", "_val_1", "_val_2", "_unpaired_1", "_unpaired_2"]:
        n = n.replace(junk, "")
    n = n.replace("_aaa", "") # Fix specific
    if n.endswith("_1"): n = n[:-2] + "_R1"
    elif n.endswith("_2"): n = n[:-2] + "_R2"
    return n.strip()

try:
    if os.path.exists(json_pre) and os.path.exists(json_post):
        with open(json_pre) as f: data_pre = json.load(f)
        with open(json_post) as f: data_post = json.load(f)

        def get_stats(data_dict):
            merged = {}
            raw = data_dict.get("report_general_stats_data", [])
            if isinstance(raw, list):
                for x in raw: merged.update(x)
            elif isinstance(raw, dict):
                for k,v in raw.items(): merged.update(v)
            if not merged and "report_saved_raw_data" in data_dict:
                 if "multiqc_general_stats" in data_dict["report_saved_raw_data"]: 
                     merged = data_dict["report_saved_raw_data"]["multiqc_general_stats"]
            return merged

        pre = get_stats(data_pre)
        post = get_stats(data_post)
        
        post_map = {}
        for k in post.keys():
            norm = normalize_name(k)
            post_map[norm] = k

        for k_pre in pre.keys():
            norm_pre = normalize_name(k_pre)
            k_post = post_map.get(norm_pre)
            
            if k_post:
                rp = float(pre[k_pre].get("total_sequences", pre[k_pre].get("Total Sequences", 0)))
                gcp = float(pre[k_pre].get("percent_gc", pre[k_pre].get("%GC", 0)))
                rpo = float(post[k_post].get("total_sequences", post[k_post].get("Total Sequences", 0)))
                gcpo = float(post[k_post].get("percent_gc", post[k_post].get("%GC", 0)))
                loss = 100 - (rpo/rp*100) if rp > 0 else 0.0
                
                display = norm_pre.replace("_R1", " (R1)").replace("_R2", " (R2)")
                samples_data.append({ "name": display, "raw": rp, "clean": rpo, "loss": loss, "gc_pre": gcp, "gc_post": gcpo })

    # --- RENDER OUTPUT ---
    print_box(f"ANALYSIS REPORT: {env.get('P_NAME').upper()}", C_CYAN)
    
    print(f" {C_BOLD}Project Summary:{C_RESET}")
    print(f"  • Date:         {env.get('P_DATE')}")
    print(f"  • Mode:         {env.get('P_MODE')}")
    print(f"  • Environment:  {env.get('P_ENV')}")
    
    print(f"\n {C_BOLD}Trimmomatic Configuration (Detailed):{C_RESET}")
    print(f"  • Adapter File:      {C_YELLOW}{t_adapt}{C_RESET}")
    print(f"  • Illuminaclip:      Seed:{t_seed} | Palindrome:{t_pct} | Simple:{t_sct}")
    print(f"  • Sliding Window:    {env.get('T_SLIDE')}")
    print(f"  • Leading/Trailing:  Qual {env.get('T_LEAD')} / Qual {env.get('T_TRAIL')}")
    print(f"  • Min Quality:       Phred {env.get('T_QUAL')}")
    print(f"  • Min Length:        {env.get('T_LEN')} bp")
    
    print(f"\n {C_BOLD}Software Versions:{C_RESET}")
    print(f"  • FastQC v{env.get('V_FASTQC')} | MultiQC v{env.get('V_MULTIQC')} | Trimmomatic v{env.get('V_TRIM')}")

    print(f"\n {C_BOLD}Quality Statistics:{C_RESET}")
    
    if samples_data:
        samples_data.sort(key=lambda x: x['name'])
        print(f" {C_DIM}┌──────────────────────────┬────────────────┬────────────────┬──────────┬───────────────┐{C_RESET}")
        print(f" {C_DIM}│{C_RESET} {C_BOLD}{'Sample':<24}{C_RESET} {C_DIM}│{C_RESET} {C_BOLD}{'Raw Reads' :>14}{C_RESET} {C_DIM}│{C_RESET} {C_BOLD}{'Clean Reads':>14}{C_RESET} {C_DIM}│{C_RESET} {C_BOLD}{'Loss %':>8}{C_RESET} {C_DIM}│{C_RESET} {C_BOLD}{'GC % (Change)':<13}{C_RESET} {C_DIM}│{C_RESET}")
        print(f" {C_DIM}├──────────────────────────┼────────────────┼────────────────┼──────────┼───────────────┤{C_RESET}")
        for s in samples_data:
            l_col = C_GREEN
            if s['loss'] > 15: l_col = C_YELLOW
            if s['loss'] > 30: l_col = C_RED
            print(f" {C_DIM}│{C_RESET} {s['name']:<24} {C_DIM}│{C_RESET} {int(s['raw']):>14,} {C_DIM}│{C_RESET} {int(s['clean']):>14,} {C_DIM}│{C_RESET} {l_col}{s['loss']:>8.2f}%{C_RESET} {C_DIM}│{C_RESET} {s['gc_pre']:.1f} -> {s['gc_post']:.1f} {C_DIM}│{C_RESET}")
        print(f" {C_DIM}└──────────────────────────┴────────────────┴────────────────┴──────────┴───────────────┘{C_RESET}")
        
        # Save MD with ALL parameters
        md = f"results/{env.get('P_NAME')}_final_report.md"
        with open(md, 'w') as f:
            f.write(f"# ANALYSIS REPORT: {env.get('P_NAME')}\n\n")
            f.write(f"**Date:** {env.get('P_DATE')} | **Mode:** {env.get('P_MODE')} | **Environment:** {env.get('P_ENV')}\n\n")
            f.write("## 1. Pipeline Configuration (Trimmomatic)\n\n")
            f.write("| Parameter | Value | Description |\n|---|---|---|\n")
            f.write(f"| Adapter File | {t_adapt} | Adapter sequences removed |\n")
            f.write(f"| Illuminaclip | {t_seed}:{t_pct}:{t_sct} | Seed Mismatches : Palindrome Clip : Simple Clip |\n")
            f.write(f"| Sliding Window | {env.get('T_SLIDE')} | Window Size : Average Quality Required |\n")
            f.write(f"| Leading Cut | {env.get('T_LEAD')} | Remove leading low quality bases |\n")
            f.write(f"| Trailing Cut | {env.get('T_TRAIL')} | Remove trailing low quality bases |\n")
            f.write(f"| Min Length | {env.get('T_LEN')} bp | Drop reads shorter than this |\n\n")
            f.write("## 2. Quality Statistics\n\n")
            f.write("| Sample | Raw Reads | Clean Reads | Loss % | GC% (Change) |\n|---|---|---|---|---|\n")
            for s in samples_data:
                f.write(f"| {s['name']} | {int(s['raw']):,} | {int(s['clean']):,} | {s['loss']:.2f}% | {s['gc_pre']:.1f} -> {s['gc_post']:.1f} |\n")
    else:
        print(f"\n{C_RED}{C_BOLD}  [!] NO MATCHING DATA FOUND{C_RESET}")

except Exception as e:
    print(f"\n{C_RED}PYTHON CRITICAL ERROR:{C_RESET} {e}")
EOF

echo -e "${GREEN}✓ Report saved: results/${PROJECT_NAME}_final_report.md${NC}"

################################################################################
# PASSO 4: ARQUIVAMENTO E BACKUP
################################################################################

echo ""
echo -e "${BOLD}${BLUE}┌────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}${BLUE}│ BACKUP AND DELIVERY                                                    │${NC}"
echo -e "${BOLD}${BLUE}└────────────────────────────────────────────────────────────────────────┘${NC}"
echo ""

mkdir -p reproducibility/scripts
cp "${SCRIPT_SOURCE_DIR}"/*.sh reproducibility/scripts/ 2>/dev/null || true

ARCHIVE_NAME="${PROJECT_NAME}_full_package.tar.gz"

echo -e "  ${CYAN}ℹ${NC} Compressing files..."
tar -czf "$ARCHIVE_NAME" \
    --exclude='raw_data' --exclude='trimmed_data' --exclude='genome_indexed' \
    --exclude='aligned_data' --exclude='trinity_assembly' --exclude='kallisto' \
    --exclude='*.bam' --exclude='*.fastq.gz' --exclude='*.fq.gz' \
    qc_reports reproducibility results .analysis_mode 2>/dev/null

if [[ -f "$ARCHIVE_NAME" ]]; then
    SIZE=$(du -h "$ARCHIVE_NAME" | cut -f1)
    echo -e "  ${GREEN}✓${NC} Archive created: ${BOLD}${ARCHIVE_NAME}${NC} (${SIZE})"
else
    echo -e "  ${RED}✗${NC} Archive creation failed."
fi

echo ""
echo -e "${BOLD}Download Options:${NC}"
echo -e "  1. Copy via SCP:"
echo -e "     ${YELLOW}scp $(whoami)@$(hostname):$(pwd)/$ARCHIVE_NAME .${NC}"
echo ""
echo -e "  2. Upload to GitHub:"
echo -e "     ${CYAN}git add results/ reproducibility/ $ARCHIVE_NAME${NC}"
echo -e "     ${CYAN}git commit -m 'Final Results' && git push${NC}"
echo ""
