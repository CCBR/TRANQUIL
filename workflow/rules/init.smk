#########################################################
# IMPORT PYTHON LIBRARIES HERE
#########################################################
import sys
import json
import os
import pandas as pd
import yaml
# import glob
# import shutil
#########################################################
# no truncations during print pandas data frames
pd.set_option('display.max_rows', None)
pd.set_option('display.max_columns', None)
pd.set_option('display.width', None)
pd.set_option('display.max_colwidth', None)

#########################################################
# FILE-ACTION FUNCTIONS
#########################################################
def check_existence(filename):
  if not os.path.exists(filename):
    exit("# File: %s does not exists!"%(filename))

def check_readaccess(filename):
  check_existence(filename)
  if not os.access(filename,os.R_OK):
    exit("# File: %s exists, but cannot be read!"%(filename))

def check_writeaccess(filename):
  check_existence(filename)
  if not os.access(filename,os.W_OK):
    exit("# File: %s exists, but cannot be read!"%(filename))

def get_file_size(filename):
    filename=filename.strip()
    if check_readaccess(filename):
        return os.stat(filename).st_size
#########################################################

#########################################################
# DEFINE CONFIG FILE AND READ IT
#########################################################
CONFIGFILE = str(workflow.overwrite_configfiles[0])

# set memory limit
# used for sambamba sort, etc
# MEMORYG="100G"

# read in various dirs from config file
WORKDIR=config['workdir']
RESULTSDIR=join(WORKDIR,"results")

# get resources folder
try:
    RESOURCESDIR = config["resourcesdir"]
except KeyError:
    RESOURCESDIR = join(WORKDIR,"resources")
check_existence(RESOURCESDIR)

# get scripts folder
try:
    SCRIPTSDIR = config["scriptsdir"]
except KeyError:
    SCRIPTSDIR = join(WORKDIR,"scripts")
check_existence(SCRIPTSDIR)

if not os.path.exists(join(WORKDIR,"fastqs")):
    os.mkdir(join(WORKDIR,"fastqs"))
if not os.path.exists(RESULTSDIR):
    os.mkdir(RESULTSDIR)
if not os.path.exists(join(RESULTSDIR,"fastqs")):
    os.mkdir(join(RESULTSDIR,"fastqs"))

# check read access to required files
for f in ["samplemanifest"]:
    check_readaccess(config[f])
#########################################################


#########################################################
# CREATE SAMPLE DATAFRAME
#########################################################
# each line in the samplemanifest is a replicate
# samplemanifest has the following columns:
# sampleName	replicateNumber	path_to_R1_fastq
# multiple replicates belong to a sample
# currently only 1,2,3 or 4 replicates per sample is supported
REPLICATESDF = pd.read_csv(config["samplemanifest"],sep="\t",header=0)
REPLICATESDF["replicateName"] = REPLICATESDF.apply(lambda row: row["sampleName"] + "_" + str(row["replicateNumber"]), axis=1)
REPLICATESDF = REPLICATESDF.set_index("replicateName")
REPLICATES = list(REPLICATESDF.index)
SAMPLES = list(REPLICATESDF.sampleName.unique())

print("#"*100)
print("# Checking Sample Manifest...")
print("# \tTotal Replicates in manifest : "+str(len(REPLICATES)))
print("# \tTotal Samples in manifest : "+str(len(SAMPLES)))
print("# Checking read access to raw fastqs...")

REPLICATESDF["R1"]=join(RESOURCESDIR,"dummy")
# REPLICATESDF["R2"]=join(RESOURCESDIR,"dummy")
# REPLICATESDF["PEorSE"]="PE"

for replicate in REPLICATES:
    R1file=REPLICATESDF["path_to_R1_fastq"][replicate]
#     R2file=REPLICATESDF["path_to_R2_fastq"][replicate]
#     # print(replicate,R1file,R2file)
    check_readaccess(R1file)
    R1filenewname=join(WORKDIR,"fastqs",replicate+".R1.fastq.gz")
    if not os.path.exists(R1filenewname):
        os.symlink(R1file,R1filenewname)
    REPLICATESDF.loc[[replicate],"R1"]=R1filenewname
#     if str(R2file)!='nan':
#         check_readaccess(R2file)
#         R2filenewname=join(WORKDIR,"fastqs",replicate+".R2.fastq.gz")
#         if not os.path.exists(R2filenewname):
#             os.symlink(R2file,R2filenewname)
#         REPLICATESDF.loc[[replicate],"R2"]=R2filenewname
#     else:
# # only PE samples are supported by the ATACseq pipeline at the moment
#         print("# Only Paired-end samples are supported by this pipeline!")
#         print("# "+config["samplemanifest"]+" is missing second fastq file for "+replicate)
#         exit()
#         REPLICATESDF.loc[[replicate],"PEorSE"]="SE"

print("# Read access to all raw fastqs is confirmed!")
print("# Symlinks to all raw fastqs is created!")
print("#"*100)

SAMPLE2REPLICATES=dict()
for g in SAMPLES:
    SAMPLE2REPLICATES[g]=list(REPLICATESDF[REPLICATESDF['sampleName']==g].index)

# print(REPLICATESDF.columns)
# print(REPLICATESDF.sampleName)
# print(SAMPLES[0])
# print(REPLICATESDF[REPLICATESDF['sampleName']==SAMPLES[0]].index)
# print(SAMPLE2REPLICATES)
# exit()

# read in contrasts
CONTRASTSDF = pd.read_csv(config["contrasts"],sep="\t",header=0)
CONTRASTSDF["contrast"] = CONTRASTSDF.apply(lambda row: row["group1"] + "_vs_" + row["group2"], axis=1)
CONTRASTSDF = CONTRASTSDF.set_index("contrast")
CONTRASTS = list(CONTRASTSDF.index)

SAMPLES_IN_CONTRASTS = list()
SAMPLES_IN_CONTRASTS.extend(CONTRASTSDF['group1'])
SAMPLES_IN_CONTRASTS.extend(CONTRASTSDF['group2'])
if not set(SAMPLES_IN_CONTRASTS).issubset(SAMPLES):
    exit("# contrasts.tsv has samples which are absent in samples.tsv")
for s in SAMPLES_IN_CONTRASTS:
    print(s)
    print(len(SAMPLE2REPLICATES[s]))
    if (not len(SAMPLE2REPLICATES[s])>=2):
        exit("# Sample: %s does not have replicates!"%(s))

# create output folders
for c in CONTRASTS:
    if not os.path.exists(join(RESULTSDIR,c)):
        os.mkdir(join(RESULTSDIR,c))

for index, row in CONTRASTSDF.iterrows():
    c = index
    out = open(join(RESULTSDIR,c,"sampleinfo.txt"),'w')
    s1 = row['group1']
    s2 = row['group2']
    for s in [s1, s2]:
        for r in SAMPLE2REPLICATES[s]:
            trimoutputfile = join(RESULTSDIR,"fastqs",r+".trim.R1.fastq.gz")
            out.write("%s\t%s\n"%(trimoutputfile,s))
    out.close()


# print(SAMPLES)
# print(SAMPLES_IN_CONTRASTS)
# exit()

#########################################################
# READ IN TOOLS REQUIRED BY PIPELINE
# THESE INCLUDE LIST OF BIOWULF MODULES (AND THEIR VERSIONS)
# MAY BE EMPTY IF ALL TOOLS ARE DOCKERIZED
#########################################################
## Load tools from YAML file
try:
    TOOLSYAML = config["tools"]
except KeyError:
    TOOLSYAML = join(RESOURCESDIR,"tools.yaml")
check_readaccess(TOOLSYAML)
with open(TOOLSYAML) as f:
    TOOLS = yaml.safe_load(f)
#########################################################


#########################################################
# READ CLUSTER PER-RULE REQUIREMENTS
#########################################################

## Load cluster.json
try:
    CLUSTERJSON = config["clusterjson"]
except KeyError:
    CLUSTERJSON = join(RESOURCESDIR,"cluster.json")
check_readaccess(CLUSTERJSON)
with open(CLUSTERJSON) as json_file:
    CLUSTER = json.load(json_file)

## Create lambda functions to allow a way to insert read-in values
## as rule directives
getthreads=lambda rname:int(CLUSTER[rname]["threads"]) if rname in CLUSTER and "threads" in CLUSTER[rname] else int(CLUSTER["__default__"]["threads"])
getmemg=lambda rname:CLUSTER[rname]["mem"] if rname in CLUSTER and "mem" in CLUSTER[rname] else CLUSTER["__default__"]["mem"]
getmemG=lambda rname:getmemg(rname).replace("g","G")
#########################################################

#########################################################
# SET OTHER PIPELINE GLOBAL VARIABLES
#########################################################

print("# Pipeline Parameters:")
print("#"*100)
print("# Working dir :",WORKDIR)
print("# Results dir :",RESULTSDIR)
print("# Scripts dir :",SCRIPTSDIR)
print("# Resources dir :",RESOURCESDIR)
print("# Cluster JSON :",CLUSTERJSON)

# GENOME=config["genome"]
# INDEXDIR=config[GENOME]["indexdir"]
# print("# Bowtie index dir:",INDEXDIR)

# GENOMEFILE=join(INDEXDIR,GENOME+".genome") # genome file is required by macs2 peak calling
# check_readaccess(GENOMEFILE)
# print("# Genome :",GENOME)
# print("# .genome :",GENOMEFILE)

# GENOMEFA=join(INDEXDIR,GENOME+".fa") # genome file is required by motif enrichment rule
# check_readaccess(GENOMEFA)
# print("# Genome fasta:",GENOMEFA)

QCDIR=join(RESULTSDIR,"QC")

# FASTQ_SCREEN_CONFIG=config["fastqscreen_config"]
# check_readaccess(FASTQ_SCREEN_CONFIG)
# print("# FQscreen config  :",FASTQ_SCREEN_CONFIG)


#########################################################
