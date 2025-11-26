# RNA-Seq Analysis Pipeline v1.0

[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Conda](https://img.shields.io/badge/Conda-Required-orange.svg)](https://docs.conda.io/)

A modular, interactive, and reproducible pipeline for RNA-Seq data analysis supporting both **Expression Analysis** (reference-based) and **De Novo Assembly** (non-model organisms).

---

## Table of Contents

- [Features](#features)
- [Pipeline Modes](#pipeline-modes)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Pipeline Workflow](#pipeline-workflow)
- [Directory Structure](#directory-structure)
- [Usage Guide](#usage-guide)
- [Reproducibility](#reproducibility)
- [Troubleshooting](#troubleshooting)
- [Citation](#citation)

---

##  Features

- **Dual Analysis Modes**: Expression analysis (STAR/DESeq2) or de novo assembly (Trinity/Kallisto)
- **Interactive QC Checkpoints**: Review quality metrics before committing to trimming
- **Demo Mode**: Test pipeline with subsampled data (25,000 reads) for validation
- **State Management**: Resume from any checkpoint without reprocessing
- **Automatic Environment Detection**: Manages Conda environments automatically
- **Comprehensive Reporting**: Markdown reports with detailed QC metrics and parameters
- **Modular Design**: Each stage (setup, QC, analysis, reporting) runs independently

---

## Pipeline Modes

### Expression Analysis
**Best for:** Model organisms with reference genomes

| Tool           | Purpose                                 |
|----------------|-----------------------------------------|
| STAR           | Ultrafast splice-aware genome alignment |
| featureCounts  | Gene-level read quantification          |
| DESeq2         | Differential expression analysis        |

**Input Required:**
- FASTQ files (paired-end or single-end)
- Reference genome (FASTA)
- Gene annotation (GTF/GFF)

**Estimated Time:** 2-4 hours (depends on genome size)

---

### De Novo Assembly
**Best for:** Non-model organisms or novel transcriptomes

| Tool      | Purpose                             |
|-----------|-------------------------------------|
| Trinity   | De novo transcriptome assembly      |
| Kallisto  | Transcript abundance quantification |
| edgeR     | Differential expression analysis    |

**Input Required:**
- FASTQ files only

**Estimated Time:** 24-72 hours (highly computational resources demmand)

---

## Architecture

![Architecture Diagram](_- visual selection.png)


```
┌─────────────────────────────────────────────────────────────┐
│                    01_setup.sh                              │
│  • Project initialization                                   │
│  • Directory structure creation                             │
│  • Data import (local/SCP/SRA)                             │
│  • Mode selection & persistence (.analysis_mode)           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                 02_qcPipeline.sh                            │
│  • FastQC (pre-trimming)                                    │
│  • Interactive MultiQC review                               │
│  • Trimmomatic (user-configured parameters)                 │
│  • FastQC (post-trimming)                                   │
│  • State tracking (.trimming_params checkpoint)             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                 03_analysis.sh                              │
│  ┌─────────────────────┬──────────────────────┐             │
│  │  Expression Mode    │   De Novo Mode       │             │
│  │  • STAR indexing    │   • Trinity assembly │             │
│  │  • Read alignment   │   • Kallisto index   │             │
│  │  • featureCounts    │   • Quantification   │             │
│  └─────────────────────┴──────────────────────┘             │
│  • Demo mode support (subsampling)                          │
│  • Workflow script generation (reproducibility/logs/)       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                04_relatorio.sh                              │
│  • Parse MultiQC JSON                                       │
│  • Calculate read loss metrics                              │
│  • Generate Markdown report                                 │
│  • Create tar.gz package (excludes raw data)               │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

| Script             | Input          | Output                              | Next Script Uses             |
|--------------------|----------------|-------------------------------------|------------------------------|
| `01_setup.sh`      | User choices   | `raw_data/`, `.analysis_mode`       | Analysis mode, project root  |
| `02_qcPipeline.sh` | Raw FASTQ      | `trimmed_data/`, `.trimming_params` | Clean FASTQ, QC JSON         |
| `03_analysis.sh`   | Trimmed FASTQ  | BAM/Trinity FASTA                   | Results for reporting        |
| `04_relatorio.sh`  | QC JSONs, logs | Final report (MD), tarball          | -                            |

---

## Requirements

### System Requirements
- **OS:** Linux/macOS (tested on Ubuntu 20.04+, CentOS 7+)
- **CPU:** Minimum 4 cores (8+ recommended for de novo assembly)
- **RAM:** 
  - Expression: 16GB minimum, 32GB recommended
  - De Novo: 32GB minimum, 64GB+ recommended
- **Storage:** 
  - 50GB+ for expression analysis
  - 200GB+ for de novo assembly

### Software Dependencies

#### Core Tools
```bash
# Conda/Mamba (required)
conda ≥ 4.10

# Quality Control
fastqc ≥ 0.11.9
multiqc ≥ 1.12
trimmomatic ≥ 0.39

# Expression Analysis Mode
star ≥ 2.7.9a
subread (featureCounts) ≥ 2.0.1
samtools ≥ 1.15
r-deseq2 ≥ 1.34

# De Novo Assembly Mode
trinity ≥ 2.13.2
kallisto ≥ 0.48.0
r-edger ≥ 3.36
```

#### Optional Tools*
```bash
# For SRA downloads
sra-tools (prefetch/fasterq-dump)

# For remote file transfer
openssh-client (scp)

# For background execution
screen
```
*If those tools is missing, some features of the scripts will fail
---

## Installation

### 1. Clone Repository
```bash
git clone https://github.com/phenriqueca/rnaSeq.git
cd rnaSeq
chmod +x *.sh
```

### 2. Install Conda/Mamba
If not already installed:
```bash
# Miniconda
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh

# Mamba (faster alternative)
conda install -n base -c conda-forge mamba
```

### 3. Create Analysis Environments

#### For Expression Analysis:
```bash
conda create -n rnaseq_expression -c bioconda -c conda-forge \
    star=2.7.10b \
    subread=2.0.3 \
    samtools=1.16.1 \
    r-base=4.2 \
    bioconductor-deseq2=1.38.0 -y
```

#### For De Novo Assembly*:
```bash
conda create -n rnaseq_denovo -c bioconda -c conda-forge \
    trinity=2.14.0 \
    kallisto=0.48.0 \
    r-base=4.2 \
    bioconductor-edger=3.40.0 -y
```

#### For Quality Control (Required for Both):
```bash
conda create -n qualityControl -c bioconda -c conda-forge \
    fastqc=0.12.1 \
    multiqc=1.14 \
    trimmomatic=0.39 -y
```
*Note if you change the name of the environment, than update the name at the respective .sh file

### 4. Verify Installation
```bash
# Test QC environment
conda activate qualityControl
fastqc --version
multiqc --version
trimmomatic -version

# Test analysis environment (example for expression)
conda activate rnaseq_expression
STAR --version
featureCounts -v
```

---

## Quick Start

### Minimal Example (Expression Analysis)

```bash
# Step 1: Setup project
bash 01_setup.sh
 Select: 1 (Expression Analysis)
 Project name: my_project
 Import FASTQ files and reference genome

# Step 2: Quality control
bash 02_qcPipeline.sh
 Review MultiQC reports, configure Trimmomatic

# Step 3: Run analysis
conda activate rnaseq_expression
bash 03_analysis.sh
 Choose: 1 (Real Analysis) or 2 (Demo Mode)

# Step 4: Generate report
bash 04_relatorio.sh
 Outputs: results/my_project_final_report.md (this version only QC parameters is considered)
```

---

## Pipeline Workflow

### Stage 1: Project Setup (`01_setup.sh`)

**What it does:**
- Creates standardized directory structure
- Imports data from multiple sources (local/SCP/SRA)
- Saves project configuration to `.analysis_mode` 

**Configuration persisted:**
```bash
# .analysis_mode format:
ANALYSIS_MODE,CONDA_ENV_NAME,QC_ENV,PROJECT_ROOT
(stores the analysis mode, Conda environment and path, allowing subsequent scripts to load the correct configuration)
```

**Data import options:**
1. **Local copy**: From file system
2. **SCP transfer**: From remote SSH server (reuses connection)
3. **SRA download**: From NCBI using accession numbers

---

### Stage 2: Quality Control (`02_qcPipeline.sh`)

**Interactive checkpoints:**

```
[Raw FASTQ] 
    ↓
[FastQC Pre] → [MultiQC Report] → USER REVIEW
    ↓
[Configure Trimmomatic] → USER INPUT
    ↓
[Trimmomatic] → [FastQC Post] → [MultiQC Report]
    ↓
[Proceed Decision]
```

**Trimmomatic parameters saved:**
- Quality threshold (Phred score)
- Minimum length (bp)
- Adapter file
- ILLUMINACLIP settings (seed mismatches, clip thresholds)
- LEADING/TRAILING/SLIDINGWINDOW values

**File status tracking:**
```bash
raw           # No processing
fastqc_before # Pre-QC done
trimmed       # Trimming done
complete      # All QC finished
```

---

### Stage 3: Analysis (`03_analysis.sh`)

**Expression Mode Workflow:**
```bash
1. STAR genome indexing
   → genome_indexed/

2. STAR alignment (paired/single auto-detected)
   → aligned_data/bam/*.bam

3. featureCounts quantification
   → dea/featurecounts/clean_counts.txt
```

**De Novo Mode Workflow:**
```bash
1. Trinity assembly (memory-adaptive)
   → trinity_assembly/Trinity.fasta

2. Kallisto indexing
   → kallisto/index/transcripts.idx

3. Kallisto quantification
   → kallisto/quantification/*/abundance.tsv
```

**Demo Mode:** (The only one tested)
- Subsamples first 25,000 reads per file
- Reduces Trinity memory to 4GB
- Validates pipeline without full compute

---

### Stage 4: Reporting (`04_relatorio.sh`)

**Report contents:**
1. **Project Metadata**
   - Analysis mode, date, environment
2. **Trimmomatic Configuration**
   - All parameters with descriptions
3. **Quality Statistics Table**
   - Raw vs clean read counts
   - Read loss percentage
   - GC content changes
4. **Software Versions**
   - FastQC, MultiQC, Trimmomatic, STAR/Trinity

**Archive contents:**
```bash
project_full_package.tar.gz
├── qc_reports/          # MultiQC HTMLs and JSONs
├── reproducibility/
│   ├── logs/           # Execution logs and workflows
│   └── scripts/        # Pipeline scripts used
├── results/            # Final Markdown report
└── .analysis_mode      # Project configuration
```

**Excluded from archive (for space):**
- `raw_data/`, `trimmed_data/`
- `aligned_data/`, `genome_indexed/`
- `trinity_assembly/`, `kallisto/`

---

## 📂 Directory Structure

```
my_rnaseq_project/
├── .analysis_mode              # Project state (mode, env, paths)
│
├── raw_data/
│   ├── fastq/                  # Input FASTQ files
│   └── reference/              # Genome FASTA + GTF/GFF (expression only)
│
├── qc_reports/
│   ├── fastqc_before/          # Pre-trimming QC
│   ├── fastqc_after/           # Post-trimming QC
│   ├── multiqc_before_report.html
│   ├── multiqc_after_report.html
│   └── .trimming_params        # Checkpoint: Trimmomatic config
│
├── trimmed_data/               # Clean FASTQ files
│
├── genome_indexed/             # STAR index (expression mode)
│
├── aligned_data/
│   └── bam/                    # STAR alignments (expression mode)
│
├── dea/
│   └── featurecounts/          # Count matrices (expression mode)
│
├── trinity_assembly/           # Trinity output (de novo mode)
│
├── kallisto/
│   ├── index/                  # Kallisto index (de novo mode)
│   └── quantification/         # Abundance estimates (de novo mode)
│
├── reproducibility/
│   ├── logs/
│   │   ├── qc_workflow.log     # QC execution log
│   │   ├── analysis_workflow.sh # Generated analysis script
│   │   └── analysis_execution.log
│   └── scripts/                # Backup of pipeline scripts
│
└── results/
    └── my_project_final_report.md
```

---

## Usage Guide

### Resuming Interrupted Runs

The pipeline tracks state automatically:

```bash
# If QC was interrupted after FastQC but before trimming:
bash 02_qcPipeline.sh
 Status: ● (yellow) for fastqc_before files
 Pipeline will skip FastQC and offer trimming

# If analysis crashed during alignment:
bash 03_analysis.sh
 Workflow script is saved: reproducibility/logs/analysis_workflow.sh
 Edit and re-run manually if needed
```

### Running in Background

```bash
# Use screen (recommended for long runs)
bash 03_analysis.sh
 Select: Use screen? [Y/n]: Y

# Monitor progress
screen -r <my_project>
tail -f reproducibility/logs/analysis_execution.log

# Detach: Ctrl+A, D
```

### Adding More Samples

```bash
# Re-run setup for existing project
bash 01_setup.sh
 It will detect existing project and offer:
 1. Add more data (recommended)
 2. Overwrite (requires 'DELETE' confirmation)

# Then run QC only for new files
bash 02_qcPipeline.sh
 Select specify files to process
```

### Customizing Trimmomatic

Edit parameters interactively during `02_qcPipeline.sh`:

```
Example:

Quality threshold (Q20-Q30): 25
Minimum length: 75
Leading: 3
Trailing: 3
Adapter file: TruSeq3-PE-2.fa
   Seed mismatches: 2
   Palindrome clip threshold: 30
   Simple clip threshold: 10
```

Parameters are saved to `qc_reports/.trimming_params` for reproducibility.

---

## Reproducibility

### Variables Tracked

| Variable           | Persisted In                  | Purpose                     |
|--------------------|-------------------------------|-----------------------------|
| `PROJECT_ROOT`     | `.analysis_mode`              | Absolute path portability   |
| `ANALYSIS_MODE`    | `.analysis_mode`              | Expression vs de novo logic |
| `CONDA_ENV_NAME`   | `.analysis_mode`              | Required environment        |
| Trimmomatic params | `qc_reports/.trimming_params` | QC reproducibility          |
| `LAYOUT`           | Auto-detected                 | Paired vs single-end        |
| `THREADS`          | `nproc` output                | CPU allocation              |

### Workflow Scripts

Generated workflow scripts contain all commands:

```bash
# View exact commands executed
cat reproducibility/logs/analysis_workflow.sh

# Re-run manually if needed
bash reproducibility/logs/analysis_workflow.sh
```

---

## Troubleshooting

### Possible Issues

#### 1. Conda Environment Not Found
```bash
 Error: rnaseq_expression environment missing
# Solution:
conda create -n rnaseq_expression -c bioconda star subread samtools r-deseq2 -y
```

#### 2. Trimmomatic Adapter Files Not Detected
```bash
 Error: Adapters not found
# Solution: Check adapter directory
ADAPTER_DIR=$(conda run -n qualityControl which trimmomatic | xargs dirname | xargs dirname)/share/trimmomatic/adapters
ls $ADAPTER_DIR
```

#### 3. STAR Segmentation Fault
```bash
 Cause: Insufficient memory
# Solution: Use demo mode or increase RAM/swap
 Re-run bash 03_analysis.sh
# Select: 2 (Demo Mode)
```

#### 4. MultiQC JSON Parsing Errors
```bash
Symptom: Empty QC reports
# Solution: Check MultiQC version and JSON format
multiqc --version  # Should be ≥1.12
cat qc_reports/multiqc_before_report_data/multiqc_data.json | python -m json.tool
```

#### 5. Trinity Memory Error
```bash
 Error: Trinity killed (OOM)
# Solution 1: Reduce data (use demo mode)
# Solution 2: Adjust memory in workflow script
# Edit reproducibility/logs/analysis_workflow.sh
MEM_GB=16  # Reduce from 32
```

### Debug Mode

```bash
 Enable verbose logging
set -x  # Add to top of script
bash 03_analysis.sh 2>&1 | tee debug.log
```

### Getting Help

1. Check logs: `reproducibility/logs/`
2. Review QC reports: `qc_reports/*.html`
3. Validate input files:
   ```bash
   gzip -t raw_data/fastq/*.gz  # Check FASTQ integrity
   ```

---

## 📚 Citation

If you use this pipeline in your research, please cite the tools:

**Tools:**
- **FastQC**: Andrews S. (2010). FastQC: A Quality Control Tool for High Throughput Sequence Data.
- **MultiQC**: Ewels et al. (2016). Bioinformatics, 32(19), 3047-3048.
- **Trimmomatic**: Bolger et al. (2014). Bioinformatics, 30(15), 2114-2120.
- **STAR**: Dobin et al. (2013). Bioinformatics, 29(1), 15-21.
- **featureCounts**: Liao et al. (2014). Bioinformatics, 30(7), 923-930.
- **Trinity**: Grabherr et al. (2011). Nature Biotechnology, 29(7), 644-652.
- **Kallisto**: Bray et al. (2016). Nature Biotechnology, 34(5), 525-527.
- **DESeq2**: Love et al. (2014). Genome Biology, 15(12), 550.
- **edgeR**: Robinson et al. (2010). Bioinformatics, 26(1), 139-140.

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with detailed description

---

## Related Resources

- [FastQC Help](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/Help/)
- [MultiQC Documentation](https://multiqc.info/docs/)
- [Trimmomatic Manual](http://www.usadellab.org/cms/uploads/supplementary/Trimmomatic/TrimmomaticManual_V0.32.pdf)
- [STAR Manual](https://github.com/alexdobin/STAR/blob/master/doc/STARmanual.pdf)
- [featureCounts (Subread) Guide](http://subread.sourceforge.net/SubreadUsersGuide.pdf)
- [Trinity Wiki](https://github.com/trinityrnaseq/trinityrnaseq/wiki)
- [Kallisto Manual](https://pachterlab.github.io/kallisto/manual)
- [DESeq2 Vignette](https://bioconductor.org/packages/release/bioc/vignettes/DESeq2/inst/doc/DESeq2.html)
- [edgeR User Guide](https://bioconductor.org/packages/release/bioc/vignettes/edgeR/inst/doc/edgeRUsersGuide.pdf)
