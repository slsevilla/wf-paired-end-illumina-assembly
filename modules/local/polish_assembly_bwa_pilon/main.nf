process POLISH_ASSEMBLY_BWA_PILON {

    publishDir "${params.outdir}/asm",
        mode: "${params.publish_dir_mode}",
        pattern: "*.{txt,fna}"
    publishDir "${params.qc_filecheck_log_dir}",
        mode: "${params.publish_dir_mode}",
        pattern: "*File*.tsv"
    publishDir "${params.process_log_dir}",
        mode: "${params.publish_dir_mode}",
        pattern: ".command.*",
        saveAs: { filename -> "${prefix}.${task.process}${filename}"}

    label "process_high"
    tag { "${prefix}" }

    container "gregorysprenger/bwa-samtools-pilon@sha256:209ac13b381188b4a72fe746d3ff93d1765044cbf73c3957e4e2f843886ca57f"
    
    input:
    tuple val(prefix), path(paired_R1_gz), path(paired_R2_gz), path(single_gz), path(qc_nonoverlap_filecheck), path(uncorrected_contigs)

    output:
    tuple val(prefix), path("${prefix}.paired.bam"), path("${prefix}.single.bam"), path("*File*.tsv"), emit: bam
    tuple val(prefix), path("${prefix}.fna"), emit: assembly
    path "${prefix}.Filtered_Assembly_File.tsv", emit: qc_filtered_asm_filecheck
    path "${prefix}.Binary_PE_Alignment_Map_File.tsv", emit: qc_pe_alignment_filecheck
    path "${prefix}.Polished_Assembly_File.tsv", emit: qc_polished_asm_filecheck
    path "${prefix}.Final_Corrected_Assembly_FastA_File.tsv", emit: qc_corrected_asm_filecheck
    path "${prefix}.Binary_SE_Alignment_Map_File.tsv", emit: qc_se_alignment_filecheck
    path "${prefix}.InDels-corrected.cnt.txt"
    path "${prefix}.SNPs-corrected.cnt.txt"
    path ".command.out"
    path ".command.err"
    path "versions.yml", emit: versions

    shell:
    '''
    source bash_functions.sh

    # Exit if previous process fails qc filecheck
    for filecheck in !{qc_nonoverlap_filecheck}; do
      if [[ $(grep "FAIL" ${filecheck}) ]]; then
        error_message=$(awk -F '\t' 'END {print $2}' ${filecheck} | sed 's/[(].*[)] //g')
        msg "${error_message} Check failed" >&2
        exit 1
      else
        rm ${filecheck}
      fi
    done

    # Correct cleaned SPAdes contigs with cleaned PE reads
    if verify_minimum_file_size "!{uncorrected_contigs}" 'Filtered Assembly File' "!{params.min_filesize_filtered_assembly}"; then
      echo -e "!{prefix}\tFiltered Assembly File\tPASS" > !{prefix}.Filtered_Assembly_File.tsv
    else
      echo -e "!{prefix}\tFiltered Assembly File\tFAIL" > !{prefix}.Filtered_Assembly_File.tsv
    fi

    echo -n '' > !{prefix}.InDels-corrected.cnt.txt
    echo -n '' > !{prefix}.SNPs-corrected.cnt.txt

    # Make sure polish_corrections is at least 1, if not set to 1
    polish_corrections=!{params.spades_polish_corrections}
    if [[ ${polish_corrections} -lt 1 ]]; then
      polish_corrections=1
    fi

    msg "INFO: Correcting contigs with PE reads using !{task.cpus} threads"

    for ((i=1;i<=polish_corrections;i++)); do
      bwa index !{uncorrected_contigs}

      bwa mem \
        -t !{task.cpus} \
        -x intractg \
        -v 2 \
        !{uncorrected_contigs} \
        !{paired_R1_gz} !{paired_R2_gz} \
        | \
        samtools sort \
        -@ !{task.cpus} \
        --reference !{uncorrected_contigs} \
        -l 9 \
        -o !{prefix}.paired.bam

      if verify_minimum_file_size "!{prefix}.paired.bam" 'Binary PE Alignment Map File' "!{params.min_filesize_binary_pe_alignment}"; then
        echo -e "!{prefix}\tBinary PE Alignment Map File (${i} of 3)\tPASS" \
          >> !{prefix}.Binary_PE_Alignment_Map_File.tsv
      else
        echo -e "!{prefix}\tBinary PE Alignment Map File (${i} of 3)\tFAIL" \
          >> !{prefix}.Binary_PE_Alignment_Map_File.tsv
      fi

      samtools index !{prefix}.paired.bam

      pilon \
        --genome !{uncorrected_contigs} \
        --frags !{prefix}.paired.bam \
        --output "!{prefix}" \
        --changes \
        --fix snps,indels \
        --mindepth 0.50 \
        --threads !{task.cpus} >&2

      if verify_minimum_file_size "!{uncorrected_contigs}" 'Polished Assembly File' "!{params.min_filesize_polished_assembly}"; then
        echo -e "!{prefix}\tPolished Assembly File (${i} of 3)\tPASS" \
          >> !{prefix}.Polished_Assembly_File.tsv
      else
        echo -e "!{prefix}\tPolished Assembly File (${i} of 3)\tFAIL" \
          >> !{prefix}.Polished_Assembly_File.tsv
      fi

      echo $(grep -c '-' !{prefix}.changes >> !{prefix}.InDels-corrected.cnt.txt)
      echo $(grep -vc '-' !{prefix}.changes >> !{prefix}.SNPs-corrected.cnt.txt)

      rm -f !{prefix}.{changes,uncorrected.fna}
      rm -f "!{prefix}"Pilon.bed
      mv -f !{prefix}.fasta !{prefix}.uncorrected.fna

      sed -i 's/_pilon//1' !{prefix}.uncorrected.fna
    done

    mv -f !{prefix}.uncorrected.fna !{prefix}.fna

    if verify_minimum_file_size "!{prefix}.fna" 'Final Corrected Assembly FastA File' "!{params.min_filesize_final_assembly}"; then
      echo -e "!{prefix}\tFinal Corrected Assembly FastA File\tPASS" \
        > !{prefix}.Final_Corrected_Assembly_FastA_File.tsv
    else
      echo -e "!{prefix}\tFinal Corrected Assembly FastA File\tFAIL" \
        > !{prefix}.Final_Corrected_Assembly_FastA_File.tsv
    fi

    # Single read mapping if available for downstream depth of coverage
    #  calculations, not for assembly polishing.
    if [[ !{single_gz} ]]; then
      msg "INFO: Single read mapping with !{task.cpus} threads"
      bwa index !{prefix}.fna

      bwa mem \
        -t !{task.cpus} \
        -x intractg \
        -v 2 \
        !{prefix}.fna \
        !{single_gz} \
        | \
        samtools sort \
        -@ !{task.cpus} \
        --reference !{prefix}.fna \
        -l 9 \
        -o !{prefix}.single.bam

      if verify_minimum_file_size "!{prefix}.single.bam" 'Binary SE Alignment Map File' '!{params.min_filesize_binary_se_alignment}'; then
        echo -e "!{prefix}\tBinary SE Alignment Map File\tPASS" \
          > !{prefix}.Binary_SE_Alignment_Map_File.tsv
      else
        echo -e "!{prefix}\tBinary SE Alignment Map File\tFAIL" \
          > !{prefix}.Binary_SE_Alignment_Map_File.tsv
      fi

      samtools index !{prefix}.single.bam
    fi

    # Get process version
    cat <<-END_VERSIONS > versions.yml
    "!{task.process}":
      bwa: $(bwa 2>&1 | head -n 3 | tail -1 | awk 'NF>1{print $NF}')
      samtools: $(samtools --version | head -n 1 | awk 'NF>1{print $NF}')
      pilon: $(pilon --version | cut -d ' ' -f 3)
    END_VERSIONS
    '''
}