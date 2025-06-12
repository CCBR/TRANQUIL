
rule mimseq:
    input:
        infq = expand(join(RESULTSDIR,"fastqs","{replicate}.trim.R1.fastq.gz"),replicate=REPLICATES)
    output:
        ccacounts = join(RESULTSDIR,"{contrast}","mimseq","CCAanalysis","CCAcounts.csv")
    container: TOOLS["mimseq"]["docker"]
    threads: getthreads("mimseq")
    params:
        memg = getmemg("mimseq"),
        memG = getmemG("mimseq"),
        mimseqspecies = config['mimseqspecies'],
        mimseqclusterid = config['mimseqclusterid'],
        mimseqmincov = config['mimseqmincov'],
        mimseqmaxmismatches = config['mimseqmaxmismatches'],
        mimseqmaxmulti = config["mimseqmaxmulti"],
        mimseqremapmismatches = config['mimseqremapmismatches'],
        mimseq_flags = config['mimseq_flags'],
        contrast = "{contrast}",
        sampleinfo = join(RESULTSDIR,"{contrast}","sampleinfo.txt"),
        outdir = join(RESULTSDIR,"{contrast}","mimseq")
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
    tmpdir=(mktemp -d -p $tmp)
    cleanup=1
else
    # Catchall for "other" HPCs
    tmpdir=$(mktemp -d -p /dev/shm)
    cleanup=1
fi

g2=$(echo {params.contrast} | awk -F"_vs_" '{{print $2}}')
mimseq  \\
--species {params.mimseqspecies}  \\
--cluster-id {params.mimseqclusterid}  \\
--threads {threads}  \\
--min-cov {params.mimseqmincov}  \\
--max-mismatches {params.mimseqmaxmismatches}  \\
--control-condition $g2  \\
-n {params.contrast}  \\
--out-dir {params.outdir} \\
--max-multi {params.mimseqmaxmulti} \\
--remap  --remap-mismatches {params.mimseqremapmismatches} \\
{params.mimseq_flags} \\
{params.sampleinfo}

# cleanup tmpdir
if [ "$cleanup" == "1" ];then
    rm -rf $tmpdir
fi
"""
