#!/bin/bash

################################################################################
# RNASEQ PIPELINE - CORE ANALYSIS SCRIPT
# Version: 2.1 (FIX: Demo Mode Pipe Error)
################################################################################

set -euo pipefail

# --- CORES E FORMATAÇÃO ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

print_header() {
    echo ""
    echo -e "${BOLD}==========================================${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}==========================================${NC}"
    echo ""
}

print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# --- FUNÇÕES UTILITÁRIAS ---

find_all_projects() {
    find "$1" -maxdepth 3 -name ".analysis_mode" -type f 2>/dev/null | while read c; do dirname "$c"; done
}

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        print_error "Tool not found: $1 (Make sure conda env is active in the workflow)"
        return 1
    fi
}

################################################################################
# PASSO 1: SELEÇÃO E VALIDAÇÃO DO PROJETO
################################################################################

print_header "PASSO 1: Seleção do Projeto"

PROJECTS=()
PROJECT_PATHS=()

# Busca projetos
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

if [[ ${#PROJECTS[@]} -eq 0 ]]; then print_error "Nenhum projeto encontrado."; exit 1; fi

echo "Projetos encontrados:"
for i in "${!PROJECTS[@]}"; do
    echo -e "  ${CYAN}$((i+1)).${NC} ${PROJECTS[$i]}"
done
echo ""

if [[ ${#PROJECTS[@]} -eq 1 ]]; then
    idx=0
else
    read -p "Selecione o projeto [1-${#PROJECTS[@]}]: " PROJECT_CHOICE
    idx=$((PROJECT_CHOICE - 1))
fi

PROJECT_NAME="${PROJECTS[$idx]}"
PROJECT_ROOT="${PROJECT_PATHS[$idx]}"

cd "${PROJECT_ROOT}"

# Carregar configurações salvas
if [[ ! -f .analysis_mode ]]; then
    print_error "Arquivo de configuração .analysis_mode corrompido ou ausente."
    exit 1
fi

IFS=',' read -r ANALYSIS_MODE CONDA_ENV_NAME QC_ENV _ < .analysis_mode

print_success "Projeto Carregado: ${PROJECT_NAME}"
print_info "Modo de Análise: ${ANALYSIS_MODE}"
print_info "Ambiente Conda: ${CONDA_ENV_NAME}"

################################################################################
# PASSO 2: VERIFICAÇÃO DE INPUTS (INTEGRIDADE)
################################################################################

print_header "PASSO 2: Verificação de Integridade dos Arquivos"

# 1. Verificar Dados de Sequenciamento (FASTQ)
if [[ -d "trimmed_data" ]] && [[ $(ls trimmed_data/*.gz 2>/dev/null | wc -l) -gt 0 ]]; then
    DATA_SOURCE="trimmed_data"
    print_success "Dados processados (Trimmed) detectados."
elif [[ -d "raw_data/fastq" ]] && [[ $(ls raw_data/fastq/*.gz 2>/dev/null | wc -l) -gt 0 ]]; then
    DATA_SOURCE="raw_data/fastq"
    print_warning "Dados Trimmed não encontrados. Usando dados RAW (Brutos)."
else
    print_error "Nenhum arquivo FASTQ encontrado em raw_data ou trimmed_data!"
    exit 1
fi

# 2. Verificar Referências (Apenas para Expressão)
REF_GENOME=""
REF_GTF=""

if [[ "${ANALYSIS_MODE}" == "expression" ]]; then
    print_info "Verificando genoma de referência e anotação..."
    
    REF_GENOME=$(find raw_data/reference -name "*.fa" -o -name "*.fasta" -o -name "*.fna" | head -n 1)
    REF_GTF=$(find raw_data/reference -name "*.gtf" -o -name "*.gff" -o -name "*.gff3" | head -n 1)

    if [[ -z "${REF_GENOME}" ]]; then
        print_error "Arquivo FASTA do genoma não encontrado em raw_data/reference"
        exit 1
    else
        print_success "Genoma: $(basename ${REF_GENOME})"
    fi

    if [[ -z "${REF_GTF}" ]]; then
        print_error "Arquivo GTF/GFF de anotação não encontrado em raw_data/reference"
        exit 1
    else
        print_success "Anotação: $(basename ${REF_GTF})"
    fi
fi

################################################################################
# PASSO 3: MODO DE EXECUÇÃO (REAL vs DEMO VISUAL)
################################################################################

print_header "PASSO 3: Configuração da Execução"

echo "Escolha o modo de análise:"
echo -e "  ${CYAN}1. Análise Real${NC} (Processar todos os dados - Pode levar horas/dias)"
echo -e "  ${YELLOW}2. Modo DEMO / Teste de Pipeline${NC} (Cria mini-arquivos para validar o fluxo)"
echo ""
read -p "Opção [1-2]: " EXEC_MODE

IS_DEMO=false
INPUT_DIR="${DATA_SOURCE}"
DEMO_READS=25000  # Quantidade de reads para o demo

if [[ "${EXEC_MODE}" == "2" ]]; then
    IS_DEMO=true
    INPUT_DIR="demo_workspace/fastq"
    
    print_header "Preparando Ambiente DEMO"
    print_info "O pipeline irá criar sub-amostras reais dos seus arquivos."
    print_info "Isso garante que o teste seja tecnicamente válido."
    echo ""
    
    mkdir -p "${INPUT_DIR}"
    
    FILES=($(find "${DATA_SOURCE}" -name "*.fastq.gz" -o -name "*.fq.gz" | sort))
    
    # --- CORREÇÃO AQUI: Desabilitar pipefail temporariamente ---
    set +o pipefail
    
    for f in "${FILES[@]}"; do
        bn=$(basename "$f")
        target="${INPUT_DIR}/${bn}"
        
        if [[ ! -f "${target}" ]]; then
            echo -n "  Extraindo ${DEMO_READS} reads de ${bn}... "
            
            # Usando gzip -cd para compatibilidade
            # 2>/dev/null esconde o erro de "broken pipe" se o head fechar antes
            gzip -cd "$f" 2>/dev/null | head -n $((DEMO_READS * 4)) | gzip > "${target}"
            
            print_success "OK"
            
            # Preview visual seguro
            echo -e "    ${MAGENTA}Preview dos dados gerados:${NC}"
            gzip -cd "${target}" | head -n 4 | sed 's/^/    │ /'
            echo -e "    │ ..."
            echo ""
        else
            print_info "Arquivo demo já existe para ${bn}, pulando."
        fi
    done
    
    # --- Reabilitar segurança ---
    set -o pipefail
    
    print_success "Ambiente DEMO pronto em: ${INPUT_DIR}"
    print_warning "Nota: Os resultados biológicos não serão reais,"
    print_warning "mas servirão para provar que todas as ferramentas funcionam."
fi

################################################################################
# PASSO 4: DETECÇÃO DE LAYOUT (PAIRED vs SINGLE)
################################################################################

# Detectar layout automaticamente baseando-se nos arquivos do INPUT_DIR
R1_FILES=($(find "${INPUT_DIR}" -name "*_R1_*.gz" -o -name "*_1.f*gz" | sort))
R2_FILES=($(find "${INPUT_DIR}" -name "*_R2_*.gz" -o -name "*_2.f*gz" | sort))

if [[ ${#R1_FILES[@]} -gt 0 && ${#R1_FILES[@]} -eq ${#R2_FILES[@]} ]]; then
    LAYOUT="paired"
    print_info "Layout Detectado: PAIRED-END (${#R1_FILES[@]} pares)"
else
    LAYOUT="single"
    ALL_FILES=($(find "${INPUT_DIR}" -name "*.fastq.gz" -o -name "*.fq.gz" | sort))
    print_info "Layout Detectado: SINGLE-END (${#ALL_FILES[@]} amostras)"
fi

################################################################################
# PASSO 5: GERAÇÃO DO SCRIPT DE WORKFLOW
################################################################################

print_header "PASSO 5: Construção do Pipeline"

THREADS=$(nproc)
[[ "${IS_DEMO}" == "true" ]] && THREADS=4

WORKFLOW_SCRIPT="reproducibility/logs/analysis_workflow.sh"
WORKFLOW_LOG="reproducibility/logs/analysis_execution.log"

CONDA_BASE=$(conda info --base)

# --- INÍCIO DA GERAÇÃO DO SCRIPT ---
cat > "${WORKFLOW_SCRIPT}" << EOF
#!/bin/bash
set -u

# ==========================================
# CONFIGURAÇÃO AUTOMÁTICA
# ==========================================
PROJECT_ROOT="${PROJECT_ROOT}"
INPUT_DIR="${INPUT_DIR}"
THREADS=${THREADS}
LAYOUT="${LAYOUT}"
LOG_FILE="${WORKFLOW_LOG}"
CONDA_BASE="${CONDA_BASE}"
ENV_NAME="${CONDA_ENV_NAME}"
IS_DEMO="${IS_DEMO}"

# Redirecionar output para log e tela
exec > >(tee -a "\${LOG_FILE}") 2>&1

echo "=========================================="
echo "INÍCIO DO PIPELINE: \$(date)"
echo "MODO: \${ENV_NAME}"
echo "=========================================="

# ATIVAR CONDA DENTRO DO SCRIPT
source "\${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "\${ENV_NAME}"
echo "✓ Ambiente ativado: \${ENV_NAME}"
echo ""

cd "\${PROJECT_ROOT}"

EOF

# --- INJEÇÃO DA LÓGICA ESPECÍFICA ---

if [[ "${ANALYSIS_MODE}" == "expression" ]]; then
    cat >> "${WORKFLOW_SCRIPT}" << EOF
REF_GENOME="${REF_GENOME}"
REF_GTF="${REF_GTF}"

# 1. INDEXAÇÃO
echo ">> PASSO 1: Indexação do Genoma (STAR)"
mkdir -p genome_indexed

if [ -z "\$(ls -A genome_indexed)" ]; then
    echo "Gerando índice..."
    STAR --runThreadN \${THREADS} \
         --runMode genomeGenerate \
         --genomeDir genome_indexed \
         --genomeFastaFiles "\${REF_GENOME}" \
         --sjdbGTFfile "\${REF_GTF}" \
         --sjdbOverhang 100
else
    echo "✓ Índice já existe."
fi

# 2. ALINHAMENTO
echo ""
echo ">> PASSO 2: Alinhamento (STAR)"
mkdir -p aligned_data/bam

if [ "\${LAYOUT}" == "paired" ]; then
    R1_FILES=(\$(find "\${INPUT_DIR}" -name "*_R1_*.gz" -o -name "*_1.f*gz" | sort))
    R2_FILES=(\$(find "\${INPUT_DIR}" -name "*_R2_*.gz" -o -name "*_2.f*gz" | sort))
    
    for i in "\${!R1_FILES[@]}"; do
        r1="\${R1_FILES[\$i]}"
        r2="\${R2_FILES[\$i]}"
        sample=\$(basename "\$r1" | sed -E 's/(_R?1)?(_trimmed)?(\.fastq\.gz|\.fq\.gz)//')
        
        echo "  → Alinhando: \$sample"
        STAR --runThreadN \${THREADS} \
             --genomeDir genome_indexed \
             --readFilesIn "\$r1" "\$r2" \
             --readFilesCommand zcat \
             --outFileNamePrefix "aligned_data/bam/\${sample}_" \
             --outSAMtype BAM SortedByCoordinate \
             --outSAMunmapped Within 
             
        samtools index "aligned_data/bam/\${sample}_Aligned.sortedByCoord.out.bam"
    done
else
    FILES=(\$(find "\${INPUT_DIR}" -name "*.fastq.gz" | sort))
    for f in "\${FILES[@]}"; do
        sample=\$(basename "\$f" | sed -E 's/(_trimmed)?(\.fastq\.gz|\.fq\.gz)//')
        echo "  → Alinhando: \$sample"
        STAR --runThreadN \${THREADS} \
             --genomeDir genome_indexed \
             --readFilesIn "\$f" \
             --readFilesCommand zcat \
             --outFileNamePrefix "aligned_data/bam/\${sample}_" \
             --outSAMtype BAM SortedByCoordinate
             
        samtools index "aligned_data/bam/\${sample}_Aligned.sortedByCoord.out.bam"
    done
fi

# 3. QUANTIFICAÇÃO
echo ""
echo ">> PASSO 3: Contagem (featureCounts)"
mkdir -p dea/featurecounts

BAM_FILES=\$(find aligned_data/bam -name "*sortedByCoord.out.bam")
PC_OPT=""
[ "\${LAYOUT}" == "paired" ] && PC_OPT="-p"

featureCounts -T \${THREADS} \
              \${PC_OPT} \
              -a "\${REF_GTF}" \
              -o dea/featurecounts/counts_matrix.txt \
              \${BAM_FILES}

cut -f1,7- dea/featurecounts/counts_matrix.txt > dea/featurecounts/clean_counts.txt
echo "✓ Matriz de contagem gerada: dea/featurecounts/clean_counts.txt"

EOF

else
    cat >> "${WORKFLOW_SCRIPT}" << EOF
# Ajuste de memória para Demo vs Real
MEM_GB=32
[[ "\${IS_DEMO}" == "true" ]] && MEM_GB=4

# 1. MONTAGEM
echo ">> PASSO 1: Montagem De Novo (Trinity)"
mkdir -p trinity_assembly

if [ "\${LAYOUT}" == "paired" ]; then
    LEFT=\$(find "\${INPUT_DIR}" -name "*_R1_*.gz" -o -name "*_1.f*gz" | tr '\n' ',' | sed 's/,$//')
    RIGHT=\$(find "\${INPUT_DIR}" -name "*_R2_*.gz" -o -name "*_2.f*gz" | tr '\n' ',' | sed 's/,$//')
    CMD="--left \${LEFT} --right \${RIGHT}"
else
    SINGLE=\$(find "\${INPUT_DIR}" -name "*.fastq.gz" | tr '\n' ',' | sed 's/,$//')
    CMD="--single \${SINGLE}"
fi

if [[ "\${IS_DEMO}" == "true" ]]; then
    echo "  (Modo Demo: Trinity pode não montar contigs reais com poucos reads)"
fi

# Executa Trinity
Trinity --seqType fq --max_memory \${MEM_GB}G \${CMD} --CPU \${THREADS} \
        --output trinity_assembly/trinity_out_dir --full_cleanup

# Tenta encontrar o output e lidar com falha do Trinity no modo Demo
if [ -f "trinity_assembly/trinity_out_dir.Trinity.fasta" ]; then
    cp trinity_assembly/trinity_out_dir.Trinity.fasta trinity_assembly/Trinity.fasta
elif [ -f "trinity_assembly/trinity_out_dir/Trinity.fasta" ]; then
    cp trinity_assembly/trinity_out_dir/Trinity.fasta trinity_assembly/Trinity.fasta
else
    if [[ "\${IS_DEMO}" == "true" ]]; then
        echo "⚠ Aviso Demo: Trinity não gerou output (esperado com poucos reads)."
        echo "  Criando FASTA dummy para testar Kallisto..."
        echo ">DummyTranscript_1" > trinity_assembly/Trinity.fasta
        echo "ATGCATGCATGCATGCATGCATGCATGC" >> trinity_assembly/Trinity.fasta
    else
        echo "✗ Erro: Trinity falhou."
        exit 1
    fi
fi

# 2. QUANTIFICAÇÃO
echo ""
echo ">> PASSO 2: Quantificação (Kallisto)"
mkdir -p kallisto/index

kallisto index -i kallisto/index/transcripts.idx trinity_assembly/Trinity.fasta

echo "  Quantificando amostras..."
EOF
    
    cat >> "${WORKFLOW_SCRIPT}" << 'KALLISTO_LOOP'
if [ "${LAYOUT}" == "paired" ]; then
    R1_FILES=($(find "${INPUT_DIR}" -name "*_R1_*.gz" -o -name "*_1.f*gz" | sort))
    R2_FILES=($(find "${INPUT_DIR}" -name "*_R2_*.gz" -o -name "*_2.f*gz" | sort))
    for i in "${!R1_FILES[@]}"; do
        r1="${R1_FILES[$i]}"; r2="${R2_FILES[$i]}"
        sample=$(basename "$r1" | sed -E 's/(_R?1)?(_trimmed)?(\.fastq\.gz|\.fq\.gz)//')
        mkdir -p kallisto/quantification/$sample
        kallisto quant -i kallisto/index/transcripts.idx -o kallisto/quantification/$sample -t ${THREADS} "$r1" "$r2"
    done
else
    FILES=($(find "${INPUT_DIR}" -name "*.fastq.gz" | sort))
    for f in "${FILES[@]}"; do
        sample=$(basename "$f" | sed -E 's/(_trimmed)?(\.fastq\.gz|\.fq\.gz)//')
        mkdir -p kallisto/quantification/$sample
        kallisto quant -i kallisto/index/transcripts.idx -o kallisto/quantification/$sample -t ${THREADS} --single -l 200 -s 20 "$f"
    done
fi
KALLISTO_LOOP

fi

# FIM DO SCRIPT
cat >> "${WORKFLOW_SCRIPT}" << EOF
echo ""
echo "=========================================="
echo "PIPELINE CONCLUÍDO: \$(date)"
echo "=========================================="
EOF

chmod +x "${WORKFLOW_SCRIPT}"
print_success "Script de análise gerado com sucesso."

################################################################################
# PASSO 6: EXECUÇÃO
################################################################################

SCREEN_NAME="ana_${PROJECT_NAME}"
echo ""
print_header "PASSO 6: Lançamento"

if [[ "${IS_DEMO}" == "true" ]]; then
    print_info "Como estamos no MODO DEMO (rápido), rodaremos em foreground para você ver."
    print_info "Pressione ENTER para iniciar a demonstração..."
    read
    bash "${WORKFLOW_SCRIPT}"
else
    print_info "Análise REAL selecionada."
    read -p "Usar 'screen' (background)? [Y/n]: " use_screen
    
    if [[ "${use_screen}" =~ ^[Nn]$ ]]; then
        bash "${WORKFLOW_SCRIPT}"
    else
        # Mata screen anterior se existir
        screen -list 2>/dev/null | grep -q "${SCREEN_NAME}" && screen -S "${SCREEN_NAME}" -X quit
        
        screen -dmS "${SCREEN_NAME}" bash "${WORKFLOW_SCRIPT}"
        print_success "Pipeline rodando no screen: ${SCREEN_NAME}"
        echo "  Monitorar: screen -r ${SCREEN_NAME}"
        echo "  Log: tail -f ${WORKFLOW_LOG}"
    fi
fi
