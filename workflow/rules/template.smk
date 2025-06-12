# template rule
# rule trim:
#     input:
#         infq = join(WORKDIR,"fastqs","{replicate}.fastq.gz")
#     output:
#         outfq = join(RESULTSDIR,"fastqs","{replicate}.trim.fastq.gz")
#     envmodules:
#         TOOLS["cutadapt"]["version"]
#     container: config["cutadapt"]["docker"]
#     threads: getthreads("trim")
#     params:
#         memg = getmemg("trim"),
#         memG = getmemG("trim")
#     shell:"""
# set -e -x -o pipefail
# # set tmpdir
# if [ -w "/lscratch/${{SLURM_JOB_ID}}" ];then
#     # if running on BIOWULF
#     tmpdir="/lscratch/${{SLURM_JOB_ID}}"
#     cleanup=0
# elif [ -w "/scratch/cluster_scratch/${{USER}}" ];then
#     # if running on FRCE
#     tmp="/scratch/cluster_scratch/${{USER}}"
#     tmpdir=(mktemp -d -p $tmp)
#     cleanup=1
# else
#     # Catchall for "other" HPCs
#     tmpdir=$(mktemp -d -p /dev/shm)
#     cleanup=1
# fi

# # cleanup tmpdir
# if [ "$cleanup" == "1" ];then
#     rm -rf $tmpdir
# fi
# """
