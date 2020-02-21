#' Performs spatial tests on spatial cytometry data.
#'
#' @param x A segmentedCells or data frame that contains at least the variables x and y, giving the location of each cell, and cellType.
#' @param whichCondition Vector containing the two conditions to be analysed.
#' @param dist The distance at which the statistic is obtained.
#' @param integrate Should the statistic be the integral from 0 to dist, or the value of the L curve at dist.
#' @param subject Vector of subject IDs corresponding to each image if x is a data frame.
#' @param condition Vector of conditions corresponding to each image if x is a data frame.
#' @param nsim Number of simulations to perform. If empty, the p-value from lmerTest is used.
#'
#' @return Data frame of p-values.
#' @export
#'
#' @examples
#' @importFrom mgcv gam ti
spicy <- function(x, 
                  condition=NULL, 
                  subject=NULL, 
                  covariates=NULL,
                  from = NULL,
                  to = NULL,
                  dist=NULL,
                  integrate=TRUE,
                  nsim=NULL,
                  verbose=TRUE,
                  ...) {
  
  
  if (!is(x, "segmentedCells")) {
    stop('x needs to be a segmentedCells object')
  }
  
  if(is.null(from))from <- as.character(unique(cellType(x)))
  if(is.null(to))to <- as.character(unique(cellType(x)))
  
  nCells <- table(imageID(x), cellType(x))
  
  ## Find pairwise associations
  
  m1 <- rep(from, times = length(to))
  m2 <- rep(to, each = length(from))
  labels <- paste(m1, m2, sep="_")
  
  MoreArgs1 <- list(x = x, dist = dist)
  
  if(verbose)message("Calculating pairwise spatial associations")
  
  pairwiseAssoc <- mapply(getPairwise,
                     from = m1,
                     to = m2,
                     MoreArgs = MoreArgs1)
  
  
  
  count1 <- as.vector(sapply(m1,function(x)nCells[,x]))
  count2 <- as.vector(sapply(m2,function(x)nCells[,x]))
  
  resSq <- as.vector(apply(pairwiseAssoc,2,function(x)(x-mean(x,na.rm = TRUE))^2))
  
  weightFunction <- gam(resSq~ti(count1,count2))
  
  pairwiseAssoc <- as.list(data.frame(pairwiseAssoc))
  names(pairwiseAssoc) <- labels
  
  
  
  ## Linear model
  if(is.null(subject) & !is.null(condition)){
    if(verbose)message("Testing for spatial differences across conditions")
    
    MoreArgs2 <- list(cells = x, condition = condition, covariates = covariates, weightFunction = weightFunction)
    
     linearModels <- mapply(spatialLM,
                          spatAssoc = pairwiseAssoc,
                          from = m1,
                          to = m2,
                          MoreArgs = MoreArgs2,
                          SIMPLIFY = FALSE)
     
     df <- cleanLM(linearModels,from,to)
  }
  
  ## Mixed effects model
  if((!is.null(subject)) & !is.null(condition)){
    if(verbose)message("Testing for spatial differences across conditions accounting for multiple images per subject")
    
  MoreArgs2 <- list(cells = x, subject = subject, condition = condition, covariates = covariates, weightFunction = weightFunction)
  
  mixed.lmer <- mapply(spatialMEM,
                       spatAssoc = pairwiseAssoc,
                       from = m1,
                       to = m2,
                       MoreArgs = MoreArgs2,
                       SIMPLIFY = FALSE)
  df <- cleanMEM(mixed.lmer,from,to, nsim)
  
  }
  

  
  df$pairwiseAssoc <- pairwiseAssoc
  
  df <- new('spicy',df)
  df
}




cleanLM <- function(linearModels,from,to){
 
    tLm <- lapply(linearModels, function(LM){
      coef <- as.data.frame(t(summary(LM)$coef))
      coef <- split(coef,c("coefficient", "se", "statistic", "p.value"))
      coef <- lapply(coef,function(x){rownames(x)<-paste(from,to,sep = '_');x})
    })
    
    df <- apply(do.call(rbind, tLm),2,function(x)do.call(rbind,x))
    df
  }
  








cleanMEM <- function(mixed.lmer, from,to, nsim){
  if (length(nsim) > 0) {
    boot <- lapply(mixed.lmer, spatialMEMBootstrap, nsim = nsim)
    #p <- do.call(rbind, p)
    tBoot <- lapply(boot, function(coef){
      coef <- as.data.frame(t(coef))
      coef <- split(coef,c("coefficient", "se", "p.value"))
      coef <- lapply(coef,function(x){rownames(x)<-paste(from,to,sep = '_');x})
    })
    
    
    df <- apply(do.call(rbind, tBoot),2,function(x)do.call(rbind,x))
  } else {
    
    tLmer <- lapply(mixed.lmer, function(lmer){
      coef <- as.data.frame(t(summary(lmer)$coef))
      coef <- split(coef,c("coefficient", "se", "df", "statistic", "p.value"))
      coef <- lapply(coef,function(x){rownames(x)<-paste(from,to,sep = '_');x})
    })
    
    df <- apply(do.call(rbind, tLmer),2,function(x)do.call(rbind,x))
    
  }
  df
}
















#' Get statistic from pairwise L curve of a single image.
#'
#' @param x A segmentedCells or data frame that contains at least the variables x and y, giving the location of each cell, and cellType.
#' @param from The 'from' cellType for generating the L curve.
#' @param to The 'to' cellType for generating the L curve.
#' @param dist The distance at which the statistic is obtained.
#' @param integrate Should the statistic be the integral from 0 to dist, or the value of the L curve at dist.
#'
#' @return Statistic from pairwise L curve of a single image.
#' @export
#' 
#' @examples
getPairwise <- function(x, from, to, dist = NULL) {
        cells <- location(x, bind = FALSE)
    
        pairwiseVals <- lapply(cells, 
                               getStat, 
                               from = from,
                               to = to,
                               dist = dist)
    
    unlist(pairwiseVals)
}

#' Title
#'
#' @param cells 
#' @param from 
#' @param to 
#' @param dist 
#'
#' @return
#' 
#' @importFrom spatstat Lcross
#' @examples
getStat <- function(cells, from, to, dist) {
    pppCell <- pppGenerate(cells)
    
    L <- tryCatch({
        Lcross(pppCell, from=from, to=to, correction="best")
    }, error = function(e) {
    })
    
    if (length(class(L)) == 1) {
        return(NA)
    }
    
    if(is.null(dist)) dist <- max(L$r)
    
    theo = L$theo[L$r <= dist]
    iso = L$iso[L$r <= dist]
    mean(iso - theo)
    }



#' Performs bootstrapping to estimate p-value.
#'
#' @param mixed.lmer lmerModLmerTest object.
#' @param nsim Number of simulations.
#'
#' @return Vector of two p-values.
#' @export
#' 
#' @importFrom lme4 fixef bootMer
#' @examples
spatialMEMBootstrap <- function(mixed.lmer, nsim=19) {

  
  
    bootCoef <- bootMer(mixed.lmer, 
                        fixef, 
                        nsim=nsim, 
                        re.form=NA)
    
    stats <- bootCoef$t
    fe <- fixef(mixed.lmer)
    pval = pmin(colMeans(stats<0),colMeans(stats>0))*2
    df <- data.frame(coefficient = fe, se = apply(stats,2,sd), p.value = pval )
    df
    }







.show_spicy <- function(df){
  pval <- as.data.frame(df$p.value)
  cond <- colnames(pval)[grep('condition',colnames(pval))]
  cat(df$test)
  cat("Number of cell type pairs: ",nrow(pval),"\n")
  cat("Number of differentially localised cell type pairs: \n")
  if(nrow(pval)==1)print(sum(pval[cond]<0.05))
  if(nrow(pval)>1)print(colSums(apply(pval[cond],2,p.adjust, 'fdr')<0.05))
  
}
setMethod("show", signature(object = "spicy"), function(object) {
  .show_spicy(object)
})





#' @importFrom lmerTest lmer
spatialMEM <- function(spatAssoc, from, to, cells, subject, condition, covariates, weightFunction) {
   
    cellCounts <- table(imageID(cells),cellType(cells))
    
    count1 <- cellCounts[,from]
    count2 <- cellCounts[,to]
    filter <- !is.na(spatAssoc)
    
    if(sum(filter)<3)return(NA)
    
    pheno <- as.data.frame(phenotype(cells))
    spatialData <- data.frame(spatAssoc, condition = pheno[,condition], subject = pheno[,subject], pheno[covariates])
    
    spatialData <- spatialData[filter,]
    count1 <- count1[filter]
    count2 <- count2[filter]

    if(is.null(weightFunction)){
      w <- rep(1, length(count1))
      }else{
    z1 <- predict(weightFunction, data.frame(count1,count2))
    w <- 1/sqrt(z1-min(z1)+1)
    w <- w/sum(w)
    }
     
    formula <- 'spatAssoc ~ condition + (1|subject)'
    if(!is.null(covariates))formula <- paste('spatAssoc ~ condition + (1|subject)',paste(covariates, collapse = '+'), sep = "+")
    mixed.lmer <- lmer(formula(formula),
                             data = spatialData,
                             weights = w)
    mixed.lmer
}




spatialLM <- function(spatAssoc, from, to, cells, condition, covariates, weightFunction) {
  
  cellCounts <- table(imageID(cells),cellType(cells))
  
  count1 <- cellCounts[,from]
  count2 <- cellCounts[,to]
  filter <- !is.na(spatAssoc)
  
  if(sum(filter)<3)return(NA)
  
  pheno <- as.data.frame(phenotype(cells))
  spatialData <- data.frame(spatAssoc, condition = pheno[,condition], pheno[covariates])
  
  spatialData <- spatialData[filter,]
  count1 <- count1[filter]
  count2 <- count2[filter]
  
  if(is.null(weightFunction)){
    w <- rep(1, length(count1))
  }else{
    z1 <- predict(weightFunction, data.frame(count1,count2))
    w <- 1/sqrt(z1-min(z1)+1)
    w <- w/sum(w)
  }
  
  formula <- 'spatAssoc ~ condition'
  if(!is.null(covariates))formula <- paste('spatAssoc ~ condition',paste(covariates, collapse = '+'), sep = "+")
  lm1 <- lm(formula(formula),
                     data = spatialData,
                     weights = w)
  lm1
}


#' Plots result of spatialMEMMulti.
#'
#' @param df Data frame obtained from spatialMEMMulti.
#' @param fdr TRUE if FDR correction is used.
#' @param breaks Vector of 3 numbers giving breaks used in pheatmap. The first number is the minimum, the second is the maximum, the third is the number of breaks.
#' @param col Vector of colours to use in pheatmap.
#'
#' @return
#' @export
#' 
#' @importFrom pheatmap pheatmap
#'
#' @examples
spatialMEMMultiPlot <- function(df,
                                fdr=FALSE,
                                breaks=c(-5, 5, 0.5),
                                col=c("blue", "white", "red")) {
    pVal <- pmin(df[,3], df[,4])*2
  
    marks <- unique(df[,2])
  
    if (min(pVal) == 0) {
        pVal <- pVal + 10^floor(log10(min(pVal[pVal>0])))
    }
  
    if (fdr) {
        pVal <- p.adjust(pVal, method = "fdr")
    }
  
    isGreater <- df[,3] > df[,4]
  
    pVal <- log10(pVal)
  
    pVal[isGreater] <- abs(pVal[isGreater])
  
    pVal <- matrix(pVal, nrow = length(marks))
    colnames(pVal) <- marks
    rownames(pVal) <- marks
  
    breaks <- seq(from = breaks[1], to = breaks[2], by = breaks[3])
    pal <- colorRampPalette(col)(length(breaks))
  
    heatmap <- pheatmap(pVal,
                        col = pal,
                        breaks = breaks,
                        cluster_rows = FALSE,
                        cluster_cols = FALSE)
  
    heatmap
}

#' Title
#'
#' @param cells 
#'
#' @return
#' @importFrom spatstat ppp
#'
#' @examples
pppGenerate <- function(cells) {
    pppCell <- ppp(cells$x,
                   cells$y,
                   xrange = c(0,max(cells$x)),
                   yrange = c(0,max(cells$y)),
                   marks = cells$cellType)
    
    pppCell
}