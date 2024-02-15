process CLASSIFY_16S_RDP {

    tag { "${meta.id}" }
    container "tpaisie/rdp@sha256:ee388dff2e17c567946b7f2bf326765586d30f4ea0a203800616c44f599d53cc"

    input:
    tuple val(meta), path(barnapp_extracted_rna)

    output:
    tuple val(meta), path("${meta.id}.RDP_Classification_File.tsv"), emit: qc_filecheck
    tuple val(meta), path("${meta.id}.RDP.tsv")                    , emit: rdp_tsv
    path(".command.{out,err}")
    path("versions.yml")                                           , emit: versions

    shell:
    // WARN: RDP does not report version information. This variable must be updated when container is updated.
    def VERSION = '2.14'
    '''
    source bash_functions.sh

    msg "INFO: Performing RDP 16S Classification"

    classifier \
      classify \
      --format "!{params.rdp_output_format}" \
      --gene "!{params.rdp_phylomarker}" \
      --outputFile "!{meta.id}.RDP.tsv" \
      "!{barnapp_extracted_rna}"


    if verify_minimum_file_size "!{meta.id}.RDP.tsv" '16S Classification Output File' "!{params.min_filesize_rdp_output}"; then
      echo -e "!{meta.id}\t16S RDP Output File\tPASS" >> !{meta.id}.RDP_Classification_File.tsv
    else
      echo -e "!{meta.id}\t16S RDP Output File\tFAIL" >> !{meta.id}.RDP_Classification_File.tsv
    fi


    # Get process version information
    cat <<-END_VERSIONS > versions.yml
    #"!{task.process}":
        rdp: !{VERSION}
    END_VERSIONS
    '''
}
