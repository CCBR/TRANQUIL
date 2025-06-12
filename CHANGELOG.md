## TRANQUIL development version

- Run fastq validator before cutadapt to ensure the input fastq files are valid. (#13, @kelly-sovacool)


## TRANQUIL 0.2.1

- Redirect the website to the README. (#8, @kelly-sovacool)
- Use our custom installation of Python and Snakemake when running the pipeline with SLURM on FRCE. (#9, @kelly-sovacool)

## TRANQUIL 0.2.0

- Now using a changelog to track user-facing changes.
- Add a `mimseq_flags` option to the config file with `--local-modomics` set so users can customize mimseq flags. (#5, @kelly-sovacool)
- Use a Docker container built from a [custom fork](https://github.com/CCBR/mim-tRNAseq/tree/docker_v1.1.8) of mimseq v1.1.8. (#5, @kelly-sovacool)
- Use upgraded singularity and snakemake modules on FRCE. (#5, @kelly-sovacool)
- Get the pipeline version from a version file rather than git commit hash. (#7, @kelly-sovacool)

## TRANQUIL 0.1.0

This is the first version of TRANQUIL which was deployed on FRCE in 2022. (@kopardev)
