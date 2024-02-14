process ASSEMBLY_CLASSIFY_CHECKM2 {

    label "process_high"
    tag { "${meta.id}" }
    container "quay.io/biocontainers/checkm2:1.0.1--pyh7cba7a3_0@sha256:sha256:f4adc81bff88ab5a27a2a7c4e7af2cdb0943a7b89e76ef9d2f7ec680a3b95111"

    input:
    tuple val(meta), path(assembly)
    path database

    output:
    path(".command.{out,err}")
    path "checkm2.${meta.id}.log.gz"
    path "versions.yml"                                   , emit: versions
    tuple val(meta), path("checkm2.${meta.id}.report.tsv"), emit: checkm2_report_file

    shell:
    '''
    source bash_functions.sh

    # Assess the full FastA assembly with CheckM2
    msg "INFO: Classifying assembly contig set with CheckM2"

    # Run CheckM2
    checkm2 \
      predict \
      --database_path !{database} \
      --input !{assembly} \
      --output-directory checkm2 \
      --force \
      !{params.checkm2_model} \
      --threads !{task.cpus}

    # Verify output file
    file=checkm2/quality_report.tsv
    if verify_minimum_file_size "${file}" 'CheckM2 Report File' '1c'; then
      mv -f "${file}" checkm2.!{meta.id}.report.tsv
    else
      msg "ERROR: ${file} CheckM2 output report file missing" >&2
      exit 1
    fi

    # Compress the logfile for compact storage
    gzip -9f checkm2/checkm2.log

    # Get process version information
    cat <<-END_VERSIONS > versions.yml
    "!{task.process}":
        checkm2: $(checkm2 --version)
    END_VERSIONS
    '''
}
