//
// Uncompress and prepare reference genome files
//

include {
    GUNZIP as GUNZIP_FASTA
    GUNZIP as GUNZIP_GTF
    GUNZIP as GUNZIP_GFF
    GUNZIP as GUNZIP_GENE_BED
    GUNZIP as GUNZIP_TSS_BED
    GUNZIP as GUNZIP_BLACKLIST } from '../../modules/nf-core/modules/gunzip/main'

include { UNTAR                } from '../../modules/nf-core/modules/untar/main'
include { GFFREAD              } from '../../modules/nf-core/modules/gffread/main'
include { CUSTOM_GETCHROMSIZES } from '../../modules/nf-core/modules/custom/getchromsizes/main'
include { BWA_INDEX            } from '../../modules/nf-core/modules/bwa/index/main'

include { GTF2BED                  } from '../../modules/local/gtf2bed'
include { GENOME_BLACKLIST_REGIONS } from '../../modules/local/genome_blacklist_regions'
include { GET_AUTOSOMES            } from '../../modules/local/get_autosomes'
include { TSS_EXTRACT              } from '../../modules/local/tss_extract'

workflow PREPARE_GENOME {
    main:

    ch_versions = Channel.empty()

    //
    // Uncompress genome fasta file if required
    //
    if (params.fasta.endsWith('.gz')) {
        ch_fasta    = GUNZIP_FASTA ( [:], params.fasta ).gunzip.map{ it[1] }
        ch_versions = ch_versions.mix(GUNZIP_FASTA.out.versions)
    } else {
        ch_fasta = file(params.fasta)
    }

    //
    // Uncompress GTF annotation file or create from GFF3 if required
    //
    if (params.gtf) {
        if (params.gtf.endsWith('.gz')) {
            ch_gtf      = GUNZIP_GTF ( [:], params.gtf ).gunzip.map{ it[1] }
            ch_versions = ch_versions.mix(GUNZIP_GTF.out.versions)
        } else {
            ch_gtf = file(params.gtf)
        }
    } else if (params.gff) {
        if (params.gff.endsWith('.gz')) {
            ch_gff      = GUNZIP_GFF ( [:], params.gff ).gunzip.map{ it[1] }
            ch_versions = ch_versions.mix(GUNZIP_GFF.out.versions)
        } else {
            ch_gff = file(params.gff)
        }
        ch_gtf      = GFFREAD ( ch_gff ).gtf
        ch_versions = ch_versions.mix(GFFREAD.out.versions)
    }

    //
    // Uncompress blacklist file if required
    //
    ch_blacklist = Channel.empty()
    if (params.blacklist) {
        if (params.blacklist.endsWith('.gz')) {
            ch_blacklist = GUNZIP_BLACKLIST ( [:], params.blacklist ).gunzip.map{ it[1] }
            ch_versions  = ch_versions.mix(GUNZIP_BLACKLIST.out.versions)
        } else {
            ch_blacklist = Channel.fromPath(file(params.blacklist))
        }
    }

    //
    // Uncompress gene BED annotation file or create from GTF if required
    //

    // If --gtf is supplied along with --genome
    // Make gene bed from supplied --gtf instead of using iGenomes one automatically
    def make_bed = false
    if (!params.gene_bed) {
        make_bed = true
    } else if (params.genome && params.gtf) {
        if (params.genomes[ params.genome ].gtf != params.gtf) {
            make_bed = true
        }
    }

    if (make_bed) {
        ch_gene_bed = GTF2BED ( ch_gtf ).bed
        ch_versions = ch_versions.mix(GTF2BED.out.versions)
    } else {
        if (params.gene_bed.endsWith('.gz')) {
            ch_gene_bed = GUNZIP_GENE_BED ( [:], params.gene_bed ).gunzip.map{ it[1] }
            ch_versions = ch_versions.mix(GUNZIP_GENE_BED.out.versions)
        } else {
            ch_gene_bed = file(params.gene_bed)
        }
    }

    if (!params.tss_bed) {
        ch_tss_bed = TSS_EXTRACT ( ch_gene_bed ).tss
        ch_versions = ch_versions.mix(TSS_EXTRACT.out.versions)
    } else {
        if (params.tss_bed.endsWith('.gz')) {
            ch_tss_bed = GUNZIP_TSS_BED ( [:], params.tss_bed ).gunzip.map{ it[1] }
            ch_versions = ch_versions.mix(GUNZIP_TSS_BED.out.versions)
        } else {
            ch_tss_bed = file(params.tss_bed)
        }
    }

    //
    // Create chromosome sizes file
    //
    ch_chrom_sizes = CUSTOM_GETCHROMSIZES ( ch_fasta ).sizes
    ch_fai         = CUSTOM_GETCHROMSIZES.out.fai
    ch_versions    = ch_versions.mix(CUSTOM_GETCHROMSIZES.out.versions)

    //
    // Create autosomal chromosome list for ataqv
    //
    ch_genome_autosomes = Channel.empty()

    GET_AUTOSOMES (
        CUSTOM_GETCHROMSIZES.out.fai
    )
    ch_genome_autosomes = GET_AUTOSOMES.out.txt
    ch_versions = ch_versions.mix(GET_AUTOSOMES.out.versions)


    //
    // Prepare genome intervals for filtering by removing regions in blacklist file
    //
    ch_genome_filtered_bed = Channel.empty()

    GENOME_BLACKLIST_REGIONS (
        CUSTOM_GETCHROMSIZES.out.sizes,
        ch_blacklist.ifEmpty([])
    )
    ch_genome_filtered_bed = GENOME_BLACKLIST_REGIONS.out.bed
    ch_versions = ch_versions.mix(GENOME_BLACKLIST_REGIONS.out.versions)

    //
    // Uncompress BWA index or generate from scratch if required
    //
    ch_bwa_index = Channel.empty()
    if (params.bwa_index) {
        if (params.bwa_index.endsWith('.tar.gz')) {
            ch_bwa_index = UNTAR ( [:], params.bwa_index ).untar.map{ it[1] }
            ch_versions  = ch_versions.mix(UNTAR.out.versions)
        } else {
            ch_bwa_index = file(params.bwa_index)
        }
    } else {
        ch_bwa_index = BWA_INDEX ( ch_fasta ).index
        ch_versions  = ch_versions.mix(BWA_INDEX.out.versions)
    }

    emit:
    fasta         = ch_fasta                      //    path: genome.fasta
    fai           = ch_fai  //    path: genome.fai
    gtf           = ch_gtf                        //    path: genome.gtf
    gene_bed      = ch_gene_bed                   //    path: gene.bed
    tss_bed       = ch_tss_bed                    //    path: tss.bed
    chrom_sizes   = ch_chrom_sizes                //    path: genome.sizes
    filtered_bed  = ch_genome_filtered_bed        //    path: *.include_regions.bed
    bwa_index     = ch_bwa_index                  //    path: bwa/index/
    autosomes     = ch_genome_autosomes           //    path: *.autosomes.txt

    versions    = ch_versions.ifEmpty(null) // channel: [ versions.yml ]
}