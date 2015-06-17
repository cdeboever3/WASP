#
# Convert SNP files to HDF5 format. This program can be used
# on output from impute2 or on VCF files
#
./snp2h5/snp2h5 --chrom example_data/chromInfo.hg19.txt \
	      --format impute \
	      --geno_prob example_data/geno_probs.h5 \
	      --snp_index example_data/snp_index.h5 \
	      --snp_tab example_data/snp_tab.h5 \
	      --haplotype example_data/haps.h5 \
	      example_data/genotypes/chr*.hg19.impute2.gz \
	      example_data/genotypes/chr*.hg19.impute2_haps.gz

#
# Convert FASTA files to HDF5 format.
# Note the HDF5 sequence files are only used for GC content
# correction part of CHT. This step can be ommitted if
# GC-content correction is not used.
#
./snp2h5/fasta2h5 --chrom example_data/chromInfo.hg19.txt \
	--seq example_data/seq.h5 \
	/data/external_public/reference_genomes/hg19/chr*.fa.gz



# loop over all individuals in samples file
H3K27AC_SAMPLES_FILE=example_data/H3K27ac/samples.txt
ALL_SAMPLES_FILE=example_data/genotypes/YRI_samples.txt

for INDIVIDUAL in $(cat $H3K27AC_SAMPLES_FILE)
do
    echo $INDIVIDUAL

    #
    # read BAM files for this individual and write read counts to
    # HDF5 files
    #
    python CHT/bam2h5.py --chrom example_data/chromInfo.hg19.txt \
	      --snp_index example_data/snp_index.h5 \
	      --snp_tab example_data/snp_tab.h5 \
	      --haplotype example_data/haps.h5 \
	      --samples $ALL_SAMPLES_FILE \
	      --individual $INDIVIDUAL \
	      --ref_as_counts example_data/H3K27ac/ref_as_counts.$INDIVIDUAL.h5 \
	      --alt_as_counts example_data/H3K27ac/alt_as_counts.$INDIVIDUAL.h5 \
	      --other_as_counts example_data/H3K27ac/other_as_counts.$INDIVIDUAL.h5 \
	      --read_counts example_data/H3K27ac/read_counts.$INDIVIDUAL.h5 \
	      example_data/H3K27ac/$INDIVIDUAL.chr*.keep.rmdup.bam


    #
    # create CHT input file for this individual
    #
    python CHT/extract_haplotype_read_counts.py \
       --chrom example_data/chromInfo.hg19.txt \
       --snp_index example_data/snp_index.h5 \
       --snp_tab example_data/snp_tab.h5 \
       --geno_prob example_data/geno_probs.h5 \
       --haplotype example_data/haps.h5 \
       --samples $ALL_SAMPLES_FILE \
       --individual $INDIVIDUAL \
       --ref_as_counts example_data/H3K27ac/ref_as_counts.$INDIVIDUAL.h5 \
       --alt_as_counts example_data/H3K27ac/alt_as_counts.$INDIVIDUAL.h5 \
       --other_as_counts example_data/H3K27ac/other_as_counts.$INDIVIDUAL.h5 \
       --read_counts example_data/H3K27ac/read_counts.$INDIVIDUAL.h5 \
       example_data/H3K27ac/chr22.peaks.txt.gz \
       | gzip > example_data/H3K27ac/haplotype_read_counts.$INDIVIDUAL.txt.gz

done


#
# Adjust read counts in CHT files by modeling
# relationship between read depth and GC content & peakiness
# in each sample.
# (first make files containing lists of input and output files)
#
IN_FILE=example_data/H3K27ac/input_files.txt
OUT_FILE=example_data/H3K27ac/output_files.txt
ls example_data/H3K27ac/haplotype_read_counts* | grep -v adjusted > $IN_FILE
cat $IN_FILE | sed 's/.txt/.adjusted.txt/' >  $OUT_FILE

python CHT/update_total_depth.py --seq example_data/seq.h5 $IN_FILE $OUT_FILE


#
# Adjust heterozygote probabilities in CHT files to account for
# possible genotyping errors. Total counts of reference and
# alternative alleles are used to adjust the probability. In
# this example we just provide the same H3K27ac read counts, however
# you could also use read counts combined across many different
# experiments or (perhaps ideally) from DNA sequencing.
#
for INDIVIDUAL in $(cat $H3K27AC_SAMPLES_FILE)
do
    IN_FILE=example_data/H3K27ac/haplotype_read_counts.$INDIVIDUAL.adjusted.txt.gz
    OUT_FILE=example_data/H3K27ac/haplotype_read_counts.$INDIVIDUAL.adjusted.hetp.txt.gz
    
    python CHT/update_het_probs.py \
	   --ref_as_counts example_data/H3K27ac/ref_as_counts.$INDIVIDUAL.h5  \
	   --alt_as_counts example_data/H3K27ac/alt_as_counts.$INDIVIDUAL.h5 \
	   $IN_FILE $OUT_FILE    
done


CHT_IN_FILE=example_data/H3K27ac/cht_input_file.txt
ls example_data/H3K27ac/haplotype_read_counts*.adjusted.hetp.txt.gz > $CHT_IN_FILE

#
# Estimate overdispersion parameters for allele-specific test (beta binomial)
#
OUT_FILE=example_data/H3K27ac/cht_as_coef.txt
python CHT/fit_as_coefficients.py $CHT_IN_FILE $OUT_FILE


#
# Estimate overdispersion parameters for association test (beta-negative binomial)
#
OUT_FILE=example_data/H3K27ac/cht_bnb_coef.txt
python CHT/fit_bnb_coefficients.py --min_counts 50 --min_as_counts 10 $CHT_IN_FILE $OUT_FILE


#
# run combined haplotype test
#
OUT_FILE=example_data/H3K27ac/cht_results.txt
python CHT/combined_test.py --min_as_counts 10 \
       --bnb_disp example_data/H3K27ac/cht_bnb_coef.txt \
       --as_disp example_data/H3K27ac/cht_as_coef.txt \
       $CHT_IN_FILE $OUT_FILE

