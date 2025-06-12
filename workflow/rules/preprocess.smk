rule fastq_validator:
    input:
        fq = join(WORKDIR,"fastqs","{replicate}.R1.fastq.gz")
    output:
        log = join(RESULTSDIR,"fastqs","{replicate}.R1.fastq_validator.log")
    container:
        TOOLS['fastqvalidator']['docker']
    params:
        minreadlen=2
    shell:
        """
        fastQValidator --noeof --minReadLen {params.minreadlen} --file {input.fq} > {output.log}
        """

rule trim:
    input:
        infq = join(WORKDIR,"fastqs","{replicate}.R1.fastq.gz"),
        fastqv = rules.fastq_validator.output.log
    output:
        outfq = join(RESULTSDIR,"fastqs","{replicate}.trim.R1.fastq.gz"),
        stats = temp(join(RESULTSDIR,"fastqs","{replicate}.readstats"))
    envmodules:
        TOOLS["cutadapt"]["version"]
    container:
        TOOLS["cutadapt"]["docker"]
    threads: getthreads("trim")
    params:
        memg = getmemg("trim"),
        memG = getmemG("trim"),
        workdir = WORKDIR,
        repname = "{replicate}",
        illumina_sequencing_adapter = config["illumina_sequencing_adapter"],
        linker = config["linker"],
        minlen = config["minlen"],
        n5trim = config["n5trim"],
        nextseq_trim_q = config["nextseq_trim_q"],
        read_stats_script = join(SCRIPTSDIR,"_cutadapt_log_get_read_stats.sh")
    shell:"""
set -e -x -o pipefail
# set tmpdir
if [ -w "/lscratch/${{SLURM_JOB_ID}}" ];then
    # if running on BIOWULF
    tmpdir="/lscratch/${{SLURM_JOB_ID}}"
    cleanup=0
elif [ -w "/scratch/cluster_scratch/${{USER}}" ];then
    # if running on FRCE
    tmp="/scratch/cluster_scratch/${{USER}}"
    tmpdir=$(mktemp -d -p $tmp)
    cleanup=1
else
    # Catchall for "other" HPCs
    tmpdir=$(mktemp -d -p /dev/shm)
    cleanup=1
fi

outdir=$(dirname {output.outfq})
cd $tmpdir
echo "{params.repname} : Trimming illumina sequencing adapter"
cutadapt -j {threads} \\
    -b {params.illumina_sequencing_adapter} -m {params.minlen} \\
    -o {params.repname}.trim_seq_adapter.fastq.gz \\
    {input.infq} | tee ${{outdir}}/{params.repname}.log1
echo "{params.repname} : Trimming linker"
cutadapt -j {threads} \\
    -b {params.linker} -m {params.minlen} \\
    -o {params.repname}.trim_seq_adapter.trim_linker.fastq.gz \\
    {params.repname}.trim_seq_adapter.fastq.gz | tee ${{outdir}}/{params.repname}.log2
echo "{params.repname} : 5-prime Trimming"
cutadapt -j {threads} \\
    -u {params.n5trim} -m {params.minlen} \\
    -o {params.repname}.trim_seq_adapter.trim_linker.trim_5prime.fastq.gz \\
    {params.repname}.trim_seq_adapter.trim_linker.fastq.gz | tee ${{outdir}}/{params.repname}.log3
echo "{params.repname} : NextSeq Trimming"
cutadapt -j {threads} \\
    --nextseq-trim={params.nextseq_trim_q} -m {params.minlen} \\
    -o {output.outfq} \\
    {params.repname}.trim_seq_adapter.trim_linker.trim_5prime.fastq.gz | tee ${{outdir}}/{params.repname}.log4

echo -ne "{params.repname}" > {output.stats}
for i in `seq 1 4`;do
    if [[ "$i" == "1" ]];then
    outonly=0
    else
    outonly=1
    fi
    stats=$(bash {params.read_stats_script} ${{outdir}}/{params.repname}.log${{i}} $outonly)
    rm -f ${{outdir}}/{params.repname}.log${{i}}
    echo -ne " $stats" >> {output.stats}
done
echo -ne "\n" >> {output.stats}

# cleanup tmpdir
if [ "$cleanup" == "1" ];then
    cd {params.workdir}
    rm -rf $tmpdir
fi
"""

localrules: concat_stats
rule concat_stats:
    input:
        stats=expand(join(RESULTSDIR,"fastqs","{replicate}.readstats"),replicate=REPLICATES)
    output:
        statstable=join(RESULTSDIR,"fastqs","readstats.txt")
    shell:"""
echo -ne "ReplicateName\\tInput_Nreads\\tInput_RL\\tAfter_removing_seq_adapter_Nreads\\tAfter_removing_seq_adapter_RL\\tAfter_trimming_linker_Nreads\\tAfter_trimming_linker_RL\\tAfter_5prime_trimming_Nreads\\tAfter_5prime_trimming_RL\\tAfter_polyG_trimming_Nreads\\tAfter_polyG_trimming_RL\\n" > {output.statstable}
cat {input.stats} | sed "s/ /\\t/g" >> {output.statstable}
"""

# rule create_sampleinfo:
#     input:
#         expand(join(RESULTSDIR,"fastqs","{replicate}.trim.R1.fastq.gz"),replicate=REPLICATES)
#     output:
#         join(RESULTSDIR,"{contrast}","sampleinfo.txt")
#     shell:"""
# """
