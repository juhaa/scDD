#' mclustRestricted
#'
#' Function to determine how many normal mixture components are present.
#' 
#' @details Robust to detecting multiple components that are close together 
#' by enforcing that the distance between two clusters 
#'  of appreciable size (at least 4 samples), have sufficiently high bimodal 
#'  index (cluster mean difference standardized by average
#'  standard deviation and multiplied by a balance factor which is one when 
#'  clusters are perfectly balanced) and not have variances
#'  that differ by more than a ratio of 20. Bimodal index threshold is 
#'  dependent on sample size to ensure consistent performance
#'  in power and type I error of detection of multiple components. 
#' 
#' @param y Numeric vector of values to fit to a normal mixture model with 
#' Mclust.
#' 
#' @param restrict Logical indicating whether or not to enforce the restriction
#'  on cluster separation based on bimodal index
#'   and ratio of largest to smallest variance (see details).  If False, 
#'   then Mclust results as is are returned.
#'   
#' @param min.size a positive integer that specifies the minimum size of a 
#' cluster (number of cells) for it to be used
#'  during the classification step. A clustering with all clusters of 
#'  size less than \code{min.size} is not valid and clusters will be merged if 
#'  this happens.
#'  
#' @param seed a single value for the random number generator (used when/if
#' calculating jitter).
#' 
#' @param jitter Numeric vector of length two with minimum and maximum for
#' jitter range (as in \code{runif(n, min = jitter[1], max = jitter[2])}).
#'   
#' @importFrom mclust Mclust
#' 
#' @references Korthauer KD, Chu LF, Newton MA, Li Y, Thomson J, Stewart R, 
#' Kendziorski C. A statistical approach for identifying differential 
#' distributions
#' in single-cell RNA-seq experiments. Genome Biology. 2016 Oct 25;17(1):222.
#'  \url{https://genomebiology.biomedcentral.com/articles/10.1186/s13059-016-
#'  1077-y}
#' 
#' @return List object with (1) vector of cluster membership, 
#' (2) cluster means, (3) cluster variances, (4) number of model parameters,
#'  (5) sample size, (6) BIC of selected model, and 
#'  (6) loglikelihood of selected model. 
#' 



mclustRestricted <- function(y, restrict=TRUE, min.size, seed=1, jitter=c(-0.1, 0.1)){
  set.seed(seed)
  
  # add jitter if all y vals are identical
  if (length(unique(y))==1){
    y <- y + runif(length(y), jitter[1], jitter[2])
  }
  
  mc <- tryCatch({
    mc <- suppressWarnings(Mclust(y, warn=FALSE, modelNames=c("V"), G=1:5, 
                                  verbose=FALSE))
  }, error = function(e) {
    # add jitter if numerical errors occur with Mclust
    y <- y + runif(length(y), jitter[1], jitter[2])
    mc <- suppressWarnings(Mclust(y, warn=FALSE, modelNames=c("V"), G=1:5, 
                                  verbose=FALSE))
    return(list(mc=mc, y=y))
  })
  
  if (class(mc) != "Mclust") {
    y <- mc[["y"]]
    mc <- mc[["mc"]]
  }
  	
  cl <- mc$classification
  comps <- mc$G
  
  if(comps > length(unique(cl))){
    mc <- suppressWarnings(Mclust(y, warn=FALSE, 
                                  modelNames=c("V"), G=1:(comps-1),
                                  verbose=FALSE))
    cl <- mc$classification
    comps <- mc$G
  }
  
  # Bimodal index threshold for removing a component (minimum of 1.6, 
  # increases with sample size and levels off at 2.2)
  remThresh <- 1/(1+exp(-length(y)/60+0.4)) + 1.2
  
  # Bimodal index threshold for keeping an added component (maximum of 4.0,
  # but is 3.6 at sample size 50
  # increases with sample size and levels off at 3.4
  addThresh <- 1/(1+exp(length(y)/9-4.5)) + 3.4
  
  if (restrict) { 
    if (comps > 1){
      compmeans <- mc$parameters$mean
      meandiff <- diff(compmeans)/max(sqrt(mc$parameters$variance$sigmasq))
      
      max.cl <- which.max(mc$parameters$variance$sigmasq)
      min.cl <- which.min(mc$parameters$variance$sigmasq)
      vardiff <- mc$parameters$variance$sigmasq[max.cl] / 
        mc$parameters$variance$sigmasq[min.cl]
      nmin <- table(cl)[min.cl]
      mincat <- min(table(cl))
      tries <- 0	
      nmax <- table(cl)[max.cl]
      balance <- 2*sqrt(nmin*nmax/(nmin+nmax)^2)
      meandiff <- meandiff*balance
      
      # Error handling checks
      if (length(vardiff)==0){
        vardiff <- 1
      }else if(sum(is.na(vardiff))>0){
        vardiff <- 1
      }
      if (length(nmin)==0){
        nmin <- Inf
      }else if(is.na(nmin)){
        nmin <- Inf
      }
      if (length(meandiff)==0){
        meandiff <- Inf
      }else if(sum(is.na(meandiff))>0){
        meandiff <- Inf
      }
      if (length(mincat)==0){
        mincat <- 1
      }else if(is.na(mincat)){
        mincat <- 1
      }
      
      err <- 0
      # enforce that clusters have to be have sufficient bimodal index -
      # if not, decrease possible components by 1 and refit
      while( (min(meandiff) < remThresh | (vardiff > 20)) & mincat>2 
             & tries <=4 & sum(is.na(mc$class))==0 & err==0){
         err <- 0
        comps_old <- comps
        comps <- comps-1 
        mc <- suppressWarnings(Mclust(y, warn=FALSE, 
                                      modelNames=c("V"), G=1:comps,
                                      verbose=FALSE))
        cl <- mc$classification
        comps <- mc$G
        mincat <- min(table(cl))
        
        tries <- tries + 1
        if (comps > 1 & comps_old-comps==1){
          compmeans <- as.numeric(by(y, cl, mean))
          meandiff <- diff(compmeans)/max(sqrt(mc$parameters$variance$sigmasq))
          balance <- 2*sqrt(nmin*nmax/(nmin+nmax)^2)
          meandiff <- meandiff*balance
          
          max.cl <- which.max(mc$parameters$variance$sigmasq)
          min.cl <- which.min(mc$parameters$variance$sigmasq)
          vardiff <- mc$parameters$variance$sigmasq[max.cl] / 
            mc$parameters$variance$sigmasq[min.cl]
          nmin <- table(cl)[min.cl]
        }else{
          meandiff <- 10
          vardiff <- -Inf
          nmin <- 100
        }
        
        # check for errors in new fit
        if (length(vardiff)==0){
          vardiff <- 1
          err <- 1
        }else if(sum(is.na(vardiff))>0){
          vardiff <- 1
          err <- 1
        }
        if (length(nmin)==0){
          nmin <- Inf
          err <- 1
        }else if(is.na(nmin)){
          nmin <- Inf
          err <- 1
        }
        if (length(meandiff)==0){
          meandiff <- Inf
          err <- 1
        }else if(sum(is.na(meandiff))>0){
          meandiff <- Inf
          err <- 1
        }
        if (length(mincat)==0){
          mincat <- 1
          err <- 1
        }else if(is.na(mincat)){
          mincat <- 1
          err <- 1
        }
        
        # if fit resulted in any errors, revert to previous fit
        if (err == 1){
          comps <- comps+1 
          mc <- suppressWarnings(Mclust(y, warn=FALSE, 
                                        modelNames=c("V"), G=1:comps,
                                        verbose=FALSE))
          cl <- mc$classification
          comps <- mc$G
        }
        
      }
    }else{  # check whether to add a component if only identified one
      comps_old <- comps
      comps <- comps+1 
      mc <- tryCatch({suppressWarnings(Mclust(y, warn=FALSE, 
                                              modelNames=c("V"), G=comps,
                                              verbose=FALSE))},
                      error = function(e) {return(NULL)})
      cl <- mc$classification
      
      if(!is.null(mc) & length(unique(cl))==comps){ 
        mincat <- min(table(cl)) 
        compmeans <- mc$parameters$mean
        meandiff <- diff(compmeans)/max(sqrt(mc$parameters$variance$sigmasq))
        
        max.cl <- which.max(mc$parameters$variance$sigmasq)
        min.cl <- which.min(mc$parameters$variance$sigmasq)
        vardiff <- mc$parameters$variance$sigmasq[max.cl] / 
          mc$parameters$variance$sigmasq[min.cl]
        nmin <- table(cl)[min.cl]
        mincat <- min(table(cl))
        tries <- 0	
        nmax <- table(cl)[max.cl]
        balance <- 2*sqrt(nmin*nmax/(nmin+nmax)^2)
        meandiff <- meandiff*balance
        
        if(!((min(meandiff) > addThresh & (vardiff < 10)) & mincat>2)){
          mc <- suppressWarnings(Mclust(y, warn=FALSE, 
                                        modelNames=c("V"), G=comps_old,
                                        verbose=FALSE))
          cl <- mc$classification
          comps <- mc$G
        }
      }else{ # couldn't fit requested model; revert to previous fit
        mc <- suppressWarnings(Mclust(y, warn=FALSE, 
                                      modelNames=c("V"), G=comps_old,
                                      verbose=FALSE))
        cl <- mc$classification
        comps <- mc$G
      }
    }
  }
  
  # if more than one cluster, and all clusters have less than min.size,
  # merge clusters together
  if (comps > 1 & max(table(cl)) < min.size){
    comps <- comps-1 
    mc <- suppressWarnings(Mclust(y, warn=FALSE, 
                                  modelNames=c("V"), G=1:comps,
                                  verbose=FALSE))
    cl <- mc$classification
    comps <- mc$G
  }
  
  # enforce clusters to have increasing means
  cl2 <- cl
  clust.order <- 1
  if (comps > 1){
    clust.order <- order(mc$parameters$mean)
    nms.clust <- names(mc$parameters$mean[clust.order])
    for (i in 1:comps){
      cl2[cl==i] <- as.numeric(nms.clust[i])
    }
  }
  return(list(class=cl2, mean=mc$parameters$mean[clust.order], 
              var=mc$parameters$variance$sigmasq[clust.order], 
              df=mc$df, n=mc$n, bic=mc$bic, loglik=mc$loglik, 
              model=mc$modelName))
}
