## very simple genotyper
genotyper <- function(x, model_background=0.1, model_nbeads=40) {

    GL <- vapply(
        c(model_background, 0.5, 1-model_background),
        function(af) {
            dbinom(
                round(x*model_nbeads),
                size=model_nbeads, prob=af)}, numeric(1))
        
    ind <- which.max(GL)
    GT <- c('0/0','0/1','1/1')[ind]
    GS <- floor(-log10(1-GL[ind] / sum(GL))*10) # assuming equal prior
    list(GT=GT, GS=GS)
}

vcf_header <- function(genome) {
    c('##fileformat=VCFv4.0',
        sprintf('##fileDate=%s',format(Sys.time(),"%Y%m%d")),
        sprintf('##reference=%s', genome),
        paste0('##INFO=<ID=PVF,Number=1,Type=Float,',
            'Description="Pseudo Variant Frequency">'),
        paste0('##INFO=<ID=GT,Number=1,Type=String,',
            'Description="Genotype">'),
        paste0('##INFO=<ID=GS,Number=1,Type=Integer,',
            'Description="Genotyping score from 7 to 85">'))
}

#' Convert SNP from Infinium array to VCF file
#'
#' @param sdf SigDF
#' @param vcf output VCF file path, if NULL output to console
#' @param genome genome
#' @param annoS SNP variant annotation, available at
#' https://github.com/zhou-lab/InfiniumAnnotationV1/tree/main/Anno/EPIC
#' EPIC.hg19.snp_overlap_b151.rds
#' EPIC.hg38.snp_overlap_b151.rds
#' @param annoI Infinium-I variant annotation, available at
#' https://github.com/zhou-lab/InfiniumAnnotationV1/tree/main/Anno/EPIC
#' EPIC.hg19.typeI_overlap_b151.rds
#' EPIC.hg38.typeI_overlap_b151.rds
#' @param verbose print more messages
#' @return VCF file. If vcf is NULL, a data.frame is output to
#' console. The data.frame does not contain VCF headers.
#' 
#' Note the vcf is not sorted. You can sort with
#' awk '$1 ~ /^#/ {print $0;next} {print $0 | "sort -k1,1 -k2,2n"}'
#' 
#' @importFrom utils write.table
#' @examples
#' sesameDataCacheAll() # if not done yet
#' sdf <- sesameDataGet('EPIC.1.SigDF')
#'
#' \dontrun{
#' ## download annoS and annoI from
#' ## https://github.com/zhou-lab/InfiniumAnnotationV1/tree/main/Anno/EPIC
#' ## output to console
#' head(formatVCF(sdf, annoS, annoI))
#' }
#' 
#' @export
formatVCF <- function(
    sdf, annoS, annoI, vcf=NULL, genome="hg19", verbose = FALSE) {
    
    platform <- sdfPlatform(sdf, verbose = verbose)
    betas <- getBetas(sdf)[names(annoS)]
    vafs <- ifelse(annoS$U == 'REF', betas, 1-betas)
    gts <- lapply(vafs, genotyper)
    GT <- vapply(gts, function(g) g$GT, character(1))
    GS <- vapply(gts, function(g) g$GS, numeric(1))
    vcflines_snp <- cbind(as.character(GenomicRanges::seqnames(annoS)),
        as.character(GenomicRanges::end(annoS)),
        names(annoS), annoS$REF, annoS$ALT, GS, ifelse(GS>20,'PASS','FAIL'),
        sprintf("PVF=%1.3f;GT=%s;GS=%d", vafs, GT, GS))

    af <- getAFTypeIbySumAlleles(sdf, known.ccs.only=FALSE)
    af <- af[names(annoI)]
    vafs <- ifelse(annoI$In.band == 'REF', af, 1-af)
    gts <- lapply(vafs, genotyper)
    GT <- vapply(gts, function(g) g$GT, character(1))
    GS <- vapply(gts, function(g) g$GS, numeric(1))
    vcflines_typeI <- cbind(as.character(GenomicRanges::seqnames(annoI)),
        as.character(GenomicRanges::end(annoI)),
        annoI$rs, annoI$REF, annoI$ALT, GS, ifelse(GS>20,'PASS','FAIL'),
        sprintf("PVF=%1.3f;GT=%s;GS=%d", vafs, GT, GS))

    header <- vcf_header(genome)    
    out <- data.frame(rbind(vcflines_snp, vcflines_typeI))
    colnames(out) <- c("#CHROM","POS","ID","REF","ALT","QUAL","FILTER","INFO")
    rownames(out) <- out$ID
    out <- out[order(out[['#CHROM']], as.numeric(out[['POS']])),]
    
    if(is.null(vcf)) { return(out);
    } else {
        writeLines(header, vcf)
        write.table(out, file=vcf, append=TRUE, sep='\t',
            row.names = FALSE, col.names = FALSE, quote = FALSE) }
}
