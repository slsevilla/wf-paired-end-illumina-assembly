process MLST_MLST {

    publishDir "${params.process_log_dir}",
        mode: "${params.publish_dir_mode}",
        pattern: ".command.*",
        saveAs: { filename -> "${prefix}.${task.process}${filename}"}

    tag { "${prefix}" }
    
    container "gregorysprenger/mlst@sha256:69c8c8027474b8f361ef4a579df171702f3ed52f45e3fb388a41ccbf4542706f"

    input:
      tuple val(prefix), path(paired_bam), path(single_bam), path(qc_assembly_filecheck), path(assembly)

    output:
    path "${prefix}.Summary.MLST.tab", emit: summary_mlst
    path ".command.out"
    path ".command.err"
    path "versions.yml", emit: versions

    shell:
    '''
    source bash_functions.sh

    # Exit if previous process fails qc filecheck
    for filecheck in !{qc_assembly_filecheck}; do
      if [[ $(grep "FAIL" ${filecheck}) ]]; then
        error_message=$(awk -F '\t' 'END {print $2}' ${filecheck} | sed 's/[(].*[)] //g')
        msg "${error_message} Check failed" >&2
        exit 1
      else
        rm ${filecheck}
      fi
    done

    # MLST for each assembly
    msg "INFO: Running MLST with !{task.cpus} threads"

    if [[ -s !{assembly} ]]; then
      mlst \
        --threads !{task.cpus} \
        "!{assembly}" \
        >> !{prefix}.Summary.MLST.tab
    fi

    # Get process version
    cat <<-END_VERSIONS > versions.yml
    "!{task.process}":
      mlst: $(mlst --version | awk '{print $2}')
    END_VERSIONS
    '''
}