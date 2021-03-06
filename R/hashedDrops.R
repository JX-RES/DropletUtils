#' Demultiplex cell hashing data
#'
#' Demultiplex cell barcodes into their samples of origin based on the most significant hash tag oligo (HTO).
#' Also identify potential doublets based on the presence of multiple significant HTOs.
#'
#' Note that this function is still experimental; feedback is welcome.
#'
#' @param x A numeric/integer matrix-like object containing UMI counts.
#' Rows correspond to HTOs and columns correspond to cell barcodes.
#' Each barcode is assumed to correspond to a cell, i.e., cell calling is assumed to have already been performed.
#' @param ambient A numeric vector of length equal to \code{nrow(x)},
#' specifying the relative abundance of each HTO in the ambient solution.
#' See below for details.
#' @param pseudo.scale A numeric scalar specifying the scaling of the pseudo-count when computing log-fold changes.
#' Also serves as the minimum pseudo-count.
#' @param nmads A numeric scalar specifying the number of median absolute deviations (MADs) to use for calling outliers.
#'
#' @return
#' A \linkS4class{DataFrame} with one row per column of \code{x}, containing the following fields:
#' \itemize{
#' \item \code{Total}, integer specifying the total count across all HTOs for each barcode.
#' \item \code{Best}, integer specifying the HTO with the highest abundance for each barcode.
#' \item \code{Second}, integer specifying the HTO with the second-highest abundance.
#' \item \code{LogFC}, numeric containing the log-fold change between the abundances of the best and second-best HTO.
#' \item \code{LogFC2}, numeric containing the log-fold change in the second-best HTO over the ambient contamination.
#' \item \code{Doublet}, logical specifying whether a barcode is a doublet.
#' \item \code{Confident}, logical specifying whether a barcode is a confidently assigned singlet.
#' }
#'
#' @details
#' The idea behind cell hashing is that cells from the same sample are stained with reagent conjugated with a single HTO.
#' Cells are mixed across multiple samples and subjected to droplet-based single-cell sequencing.
#' Cell barcode libraries can then be demultiplexed into individual samples based on whether their unique HTO is detected.
#'
#' We identify the sample of origin for each cell barcode as that corresponding to the most abundant HTO.
#' (See below for more details on exactly how \dQuote{most abundant} is defined.)
#' The log-fold change between the largest and second-largest abundances is also reported for each barcode, with large log-fold changes representing confident assignment to a single sample.
#' We also report the log-fold change of the second-most abundant HTO over the estimated level of ambient contamination.
#' Large log-fold changes indicate that the second HTO has greater abundance than expected, consistent with a doublet.
#'
#' To facilitate quality control, we explicitly identify problematic barcodes as outliers on the relevant metrics.
#' We first identify putative doublets as those with \code{LogFC2} values that are \code{nmad} MADs above the median.
#' Of the non-doublet libraries, we consider them to be confidently assigned to a single sample if their \code{LogFC} values are \emph{not} less than \code{nmad} MADs below the median.
#' In general, the magnitude of \code{nmad} is inversely proportional to the stringency of the filtering.
#'
#' @section Adjusting abundances for ambient contamination:
#' HTO abundances require some care to compute due to the presence of ambient contamination in each library.
#' Ideally, the experiment would be performed in such a manner that the concentration of each HTO is the same.
#' However, if one HTO is present at higher concentration in the ambient solution,
#' this might incorrectly cause us to assign all barcodes to the corresponding sample.
#' 
#' To adjust for ambient contamination, we assume that the ambient contamination in each library follows the same profile as \code{ambient}.
#' We further assume that a minority of HTOs in a library are actually driven by the presence of cell(s), the rest coming from the ambient solution.
#' We estimate the level of ambient contamination in each barcode by scaling \code{ambient}, using a \pkg{DESeq}-like normalization algorithm to compute the scaling factor.
#' (The requisite assumption of a non-DE majority follows from the two assumptions above.)
#' We then subtract the scaled ambient proportions from the HTO count profile to remove the effect of contamination.
#' Abundances that would otherwise be negative are set to zero.
#'
#' For experiments with 3-4 HTOs, we assume that higher-order multiplets are negligible and define the scaling factor as the third-largest ratio between the HTO counts and \code{ambient}.
#' For experiments with only 2 HTOs, doublet detection is not possible as the second-most abundant HTO is always used to estimate the ambient contamination.
#' 
#' @section Getting the ambient proportions:
#' Ideally, \code{ambient} would be obtained from libraries that do not correspond to cell-containing droplets.
#' For example, we could get this information from the \code{\link{metadata}} of the \code{\link{emptyDrops}} output,
#' had we run \code{\link{emptyDrops}} on the HTO count matrix (see below).
#' Unfortunately, in some cases (e.g., public data), counts are provided for only the cell-containing barcodes.
#' To handle this, we compute the median of each HTO across all barcodes to obtain a rough proxy for the ambient profile.
#' This does assume that there are at least 3 HTOs with evenly distributed numbers of cells in each sample.
#'
#' @section Computing the log-fold changes:
#' After subtraction of the ambient noise but before calculation of the log-fold changes,
#' we need to add a pseudo-count to ensure that the log-fold changes are well-defined.
#' We set the pseudo-count to the average ambient HTO count (i.e., the average of the scaled \code{ambient}), effectively exploiting the ambient contamination as a natural pseudo-count that scales with barcode-specific capture efficiency and sequencing depth.
#'
#' This scaling behavior is useful as it ensures that shrinkage of the log-fold changes is not more severe for libraries that have not been sequenced as deeply.
#' We thus avoid excessive variability in the log-fold change distribution (and reduction in precision of outlier detection).
#' The implicit assumption is that the number of contaminating transcript molecules is roughly the same in each droplet, meaning that any differences in ambient coverage between libraries reflect technical biases that would also affect cell-derived HTO counts. 
#'
#' Another nice aspect of this entire procedure (subtraction and re-addition) is that it collapses to a no-op if the experiment is well-executed with identical concentrations of all HTOs in the ambient solution.
#' 
#' @section Use only on non-empty droplets:
#' This function assumes that cell calling has already been performed, e.g., with \code{\link{emptyDrops}}.
#' Specifically, \code{x} should only contain columns corresponding to non-empty droplets.
#' If empty droplets are included, their log-fold changes will simply reflect stochastic sampling in the ambient solution
#' and violate the assumptions involved in outlier detection.
#'
#' If \code{x} contains columns for both empty and non-empty droplets,
#' it is straightforward to simply run \code{\link{emptyDrops}} on the HTO count matrix to identify the latter.
#' Note that some fiddling with the \code{lower=} argument may be required,
#' depending on the sequencing depth of the HTO libraries.
#'
#' @author Aaron Lun
#' @examples
#' # Mocking up an example dataset with 10 HTOs and 10% doublets.
#' ncells <- 1000
#' nhto <- 10
#' y <- matrix(rpois(ncells*nhto, 50), nrow=nhto)
#' true.sample <- sample(nhto, ncells, replace=TRUE)
#' y[cbind(true.sample, seq_len(ncells))] <- 1000
#'
#' ndoub <- ncells/10
#' next.sample <- (true.sample[1:ndoub]  + 1) %% nrow(y)
#' next.sample[next.sample==0] <- nrow(y)
#' y[cbind(next.sample, seq_len(ndoub))] <- 500
#'
#' # Computing hashing statistics.
#' stats <- hashedDrops(y)
#'
#' # Doublets show up in the top-left,
#' # singlets in the bottom right.
#' plot(stats$LogFC, stats$LogFC2)
#'
#' # Most cells should be singlets with low NMAD.
#' hist(stats$LogFC2, breaks=50)
#'
#' # Identify confident singlets or doublets at the given NMAD threshold.
#' summary(stats$Confident)
#' summary(stats$Doublet)
#' 
#' # Chcecking against the known truth, in this case
#' # 'Best' contains the putative sample of origin.
#' table(stats$Best, true.sample) 
#'
#' @references
#' Stoeckius M, Zheng S, Houck-Loomis B et al. (2018)
#' Cell Hashing with barcoded antibodies enables multiplexing and doublet detection for single cell genomics.
#' \emph{Genome Biol.} 19, 1:224
#'
#' @seealso
#' \code{\link{emptyDrops}}, to identify which barcodes are likely to contain cells.
#' 
#' @export
#' @importFrom Matrix t colSums
#' @importFrom S4Vectors DataFrame
#' @importFrom stats median mad
hashedDrops <- function(x, ambient=NULL, pseudo.scale=1, nmads=3) {
    totals <- colSums(x)
    cell.names <- colnames(x)

    if (is.null(ambient)) {
        ambient <- vapply(seq_len(nrow(x)), function(i) median(x[i,]), 0)
    }

    discard <- ambient == 0
    x <- x[!discard,,drop=FALSE]
    ambient <- ambient[!discard]

    output <- hashed_deltas(x, ambient, pseudo.scale)
    lfc <- log2(output$FC)
    lfc2 <- log2(output$FC2)

    med2 <- median(lfc2)
    mad2 <- mad(lfc2, center=med2)
    upper.threshold <- med2 + nmads * mad2
    is.doublet <- lfc2 > upper.threshold 

    lfc.singlet <- lfc[!is.doublet]
    med.singlet <- median(lfc.singlet)
    mad.singlet <- mad(lfc.singlet, center=med.singlet)
    lower.threshold <- med.singlet - nmads * mad.singlet
    confident.singlet <- lfc > lower.threshold & !is.doublet

    DataFrame(
        row.names=cell.names,
        Total=totals,
        Best=output$Best+1L,
        Second=output$Second+1L,
        LogFC=lfc,
        LogFC2=lfc2,
        Doublet=is.doublet,
        Confident=confident.singlet
    )
}
