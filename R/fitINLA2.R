#' Fit cluster-level space-time smoothing models to mortality rates 
#' 
#' 
#' 
#' @param data count data of person-months with the following columns
#' \itemize{
#'  \item cluster: cluster ID
#'  \item years: time period
#'  \item region: region of the cluster
#' \item strata: stratum of the cluster
#' \item age: age group corresponding to the row
#' \item total: total number of person-month in this age group, stratum, cluster, and period
#' \item Y: total number of deaths in this age group, stratum, cluster, and period
#' }
#' @param age.groups a character vector of age groups in increasing order.
#' @param age.n number of months in each age groups in the same order.
#' @param family family of the model. This can be either binomial (with logistic normal prior) or betabiniomial.
#' @param Amat Adjacency matrix for the regions
#' @param geo Geo file
#' @param bias.adjust the ratio of unadjusted mortality rates or age-group-specific hazards to the true rates or hazards. It needs to be a data frame that can be merged to thee outcome, i.e., with the same column names for time periods (for national adjustment), or time periods and region (for subnational adjustment). The column specifying the ratio should be named "ratio".
#' @param formula INLA formula.  See vignette for example of using customized formula.
#' @param year_names string vector of year names
#' @param na.rm Logical indicator of whether to remove rows with NA values in the data. Default set to TRUE.
#' @param priors priors from \code{\link{simhyper}}
#' @param rw Take values 1 or 2, indicating the order of random walk.
#' @param is.yearly Logical indicator for fitting yearly or period model.
#' @param year_range Entire range of the years (inclusive) defined in year_names.
#' @param m Number of years in each period.
#' @param type.st type for space-time interaction
#' @param hyper which hyperpriors to use. Default to be using the PC prior ("pc"). 
#' @param pc.u hyperparameter U for the PC prior on precisions.
#' @param pc.alpha hyperparameter alpha for the PC prior on precisions.
#' @param pc.u.phi hyperparameter U for the PC prior on the mixture probability phi in BYM2 model.
#' @param pc.alpha.phi hyperparameter alpha for the PC prior on the mixture probability phi in BYM2 model.
#' @param a.iid hyperparameter for i.i.d random effects.
#' @param b.iid hyperparameter for i.i.d random effects.
#' @param a.rw hyperparameter for RW 1 or 2 random effects.
#' @param b.rw hyperparameter for RW 1 or 2random effects.
#' @param a.icar hyperparameter for ICAR random effects.
#' @param b.icar hyperparameter for ICAR random effects.
#' @param options list of options to be passed to control.compute() in the inla() function.
#' @param verbose logical indicator to print out detailed inla() intermediate steps.
#' @seealso \code{\link{getDirect}}
#' @import Matrix
#' @importFrom stats dgamma
#' @importFrom Matrix Diagonal 
#' @return INLA model fit using the provided formula, country summary data, and geographic data
#' @examples
#' \dontrun{
#'  
#' 
#' }
#' 
#' @export
#' 
#' 

fitINLA2 <- function(data, family = c("betabinomial", "binomial")[1], age.groups = c("0", "1-11", "12-23", "24-35", "36-47", "48-59"), age.n = c(1,11,12,12,12,12), Amat, geo, bias.adjust = NULL, formula = NULL, rw = 2, is.yearly = TRUE, year_names, year_range = c(1980, 2014), m = 5, na.rm = TRUE, priors = NULL, type.st = 1, hyper = c("pc", "gamma")[1], pc.u = 1, pc.alpha = 0.01, pc.u.phi = 0.5, pc.alpha.phi = 2/3, a.iid = NULL, b.iid = NULL, a.rw = NULL, b.rw = NULL, a.icar = NULL, b.icar = NULL, options = list(config = TRUE), verbose = FALSE){

  # check region names in Amat is consistent
  if(!is.null(Amat)){
    if(is.null(rownames(Amat))){
        stop("Row names of Amat needs to be specified to region names.")
    }
    if(is.null(colnames(Amat))){
        stop("Column names of Amat needs to be specified to region names.")
    }
    if(sum(rownames(Amat) != colnames(Amat)) > 0){
        stop("Row and column names of Amat needs to be the same.")
    }
  }

  # get around CRAN check of using un-exported INLA functions
  rate0 <- shape0 <- my.cache <- inla.as.sparse <- type <- NULL

  if (!isTRUE(requireNamespace("INLA", quietly = TRUE))) {
    stop("You need to install the packages 'INLA'. Please run in your R terminal:\n install.packages('INLA', repos='https://www.math.ntnu.no/inla/R/stable')")
  }
  if (!is.element("Matrix", (.packages()))) {
    attachNamespace("Matrix")
  }
  # If INLA is installed, then attach the Namespace (so that all the relevant functions are available)
  if (isTRUE(requireNamespace("INLA", quietly = TRUE))) {
    if (!is.element("INLA", (.packages()))) {
      attachNamespace("INLA")
    }


    tau = exp(10)

   
    
    ## ---------------------------------------------------------
    ## Common Setup
    ## --------------------------------------------------------- 
    if(is.null(geo)){
      data <- data[which(data$region == "All"), ]
      if(length(data) == 0){
        stop("No geographics specified and no observation labeled 'All' either.")
      }
    } else{
      data <- data[which(data$region != "All"), ]
    }  
    #################################################################### Re-calculate hyper-priors
    
    if (is.null(priors)) {
      priors <- simhyper(R = 2, nsamp = 1e+05, nsamp.check = 5000, Amat = Amat, nperiod = length(year_names), only.iid = TRUE)
    }
    
    if(is.null(a.iid)) a.iid <- priors$a.iid
    if(is.null(b.iid)) b.iid <- priors$b.iid
    if(is.null(a.rw)) a.rw <- priors$a.iid
    if(is.null(b.rw)) b.rw <- priors$b.iid
    if(is.null(a.icar)) a.icar <- priors$a.iid
    if(is.null(b.icar)) b.icar <- priors$b.iid
    
    #################################################################### # remove NA rows? e.g. if no 10-14 available
    # if (na.rm) {
    #   na.count <- apply(data, 1, function(x) {
    #     length(which(is.na(x)))
    #   })
    #   to_remove <- which(na.count == 6)
    #   if (length(to_remove) > 0) 
    #     data <- data[-to_remove, ]
    # }
    # #################################################################### get the list of region and numeric index in one data frame
    if(is.null(geo)){
      region_names <- regions <- "All"
      region_count <- S <- 1
      dat <- cbind(data, region_number = 0)
    }else{
      region_names <- colnames(Amat) 
      region_count <- S <- length(region_names)
      regions <- data.frame(region = region_names, region_number = seq(1, region_count))      
      # -- merging in the alphabetical region number -- #
      dat <- merge(data, regions, by = "region")
    }
    
    # -- creating IDs for the spatial REs -- #
    dat$region.struct <- dat$region.unstruct <- dat$region.int <- dat$region_number
    
    ################################################################### get the lsit of region and numeric index in one data frame
    if(is.yearly){
      n <- year_range[2] - year_range[1] + 1
      nn <- n %/% m
      N <- n + nn
      rw.model <- INLA::inla.rgeneric.define(model = rw.new,
                                       n = n, 
                                       m = m,
                                       order = rw,
                                       tau = exp(10),
                                       shape0 = a.rw,
                                       rate0 = b.rw) 
      iid.model <- INLA::inla.rgeneric.define(model = iid.new,
                                             n = n, 
                                             m = m,
                                             tau = exp(10),
                                             shape0 = a.iid,
                                             rate0 = b.iid)

      rw.model.pc <- INLA::inla.rgeneric.define(model = rw.new.pc,
                                       n = n, 
                                       m = m,
                                       order = rw,
                                       tau = exp(10),
                                       u0 = pc.u,
                                       alpha0 = pc.alpha) 
      iid.model.pc <- INLA::inla.rgeneric.define(model = iid.new.pc,
                                             n = n, 
                                             m = m,
                                             tau = exp(10),
                                             u0 = pc.u,
                                             alpha0 = pc.alpha) 
      if(!is.null(geo)){
         st.model <- INLA::inla.rgeneric.define(model = st.new,
                                       n = n, 
                                       m = m,
                                       order = rw,
                                       S = region_count,
                                       Amat = Amat,
                                       type = type.st,
                                       tau = exp(10),
                                       shape0 = a.iid,
                                       rate0 = b.iid)
         st.model.pc <- INLA::inla.rgeneric.define(model = st.new.pc,
                                       n = n, 
                                       m = m,
                                       order = rw,
                                       S = region_count,
                                       Amat = Amat,
                                       type = type.st,
                                       tau = exp(10),
                                       u0 = pc.u,
                                       alpha0 = pc.alpha) 
       }
      
      year_names_new <- c(as.character(c(year_range[1]:year_range[2])), year_names)
      time.index <- cbind.data.frame(idx = 1:N, Year = year_names_new)
      constr = list(A = matrix(c(rep(1, n), rep(0, nn)), 1, N), e = 0)
      
      if(type.st %in% c(2, 4)){
        tmp <- matrix(0, S, N * S)
        for(i in 1:S){
          tmp[i, ((i-1)*n + 1) : (i*n)] <- 1
        }
      }else{
        tmp <- NULL
      }
      
      # ICAR constraints
      if(type.st %in% c(3, 4)){
        tmp2 <- matrix(0, n, N*S)
        for(i in 1:n){
          tmp2[i , which((1:(n*S)) %% n == i-1)] <- 1
        }
      }else{
        tmp2 <- NULL
      }
      tmp <- rbind(tmp, tmp2)
      if(is.null(tmp)){
        constr.st <- NULL
      }else{
        constr.st <- list(A = tmp, e = rep(0, dim(tmp)[1]))
      }
      years <- data.frame(year = year_names_new[1:N], year_number = seq(1, N))
    }else{
      n <- 0
      N <- nn <- length(year_names)
      years <- data.frame(year = year_names, year_number = seq(1, N))      
    }
    
    # -- creating IDs for the temporal REs -- #
    if(is.yearly){
      dat$time.unstruct <- dat$time.struct <- dat$time.int <- years[match(dat$years, years[, 1]), 2]
    }else{
      dat$time.unstruct <- dat$time.struct <- dat$time.int <- years[match(dat$years, years[, 1]), 2]
    }
    
    ################################################################## get the number of surveys
    if(sum(!is.na(data$survey)) == 0){
      data$survey <- 1
      nosurvey <- TRUE
    }else{
      nosurvey <- FALSE
    }
    survey_count <- length(table(data$survey))
    ################################################################## -- these are the time X survey options -- #
    x <- expand.grid(1:nn, 1:survey_count)
    survey.time <- data.frame(time.unstruct = x[, 1], survey = x[, 2], survey.time = c(1:nrow(x)))
    
    # -- these are the area X survey options -- #
    x <- expand.grid(1:region_count, 1:survey_count)
    survey.area <- data.frame(region_number = x[, 1], survey = x[, 2], survey.area = c(1:nrow(x)))
    
    # -- these are the area X time options -- #
    # The new structure takes the following order
    # (x_11, ..., x_1T, ..., x_S1, ..., x_ST, xx_11, ..., xx_1t, ..., xx_S1, ..., xx_St)
    #  x_ij : random effect of region i, year j 
    # xx_ik : random effect of region i, period k
    if(is.yearly){
      x <- rbind(expand.grid(1:n, 1:region_count), 
                 expand.grid((n+1):N, 1:region_count))
    }else{
      x <- expand.grid(1:N, 1:region_count)
    }
    time.area <- data.frame(region_number = x[, 2], time.unstruct = x[, 1], time.area = c(1:nrow(x)))
    # fix for 0 instead of 1 when no geo file provided
    if(is.null(geo)){
      time.area$region_number <- 0
    }
    # -- these are the area X time X survey options -- #
    x <- expand.grid(1:region_count, 1:N, 1:survey_count)
    survey.time.area <- data.frame(region_number = x[, 1], time.unstruct = x[, 2], survey = x[, 3], survey.time.area = c(1:nrow(x)))
    
    # -- merge these all into the data sets -- #
    newdata <- dat
    if (!nosurvey) {
      newdata <- merge(newdata, survey.time, by = c("time.unstruct", "survey"))
      newdata <- merge(newdata, survey.area, by = c("region_number", "survey"))
      newdata <- merge(newdata, survey.time.area, by = c("region_number", "time.unstruct", "survey"))
    }
    if(!is.null(geo)){
      newdata <- merge(newdata, time.area, 
        by = c("region_number", "time.unstruct"))
    }else{
      newdata$time.area <- NA
    }
    
    
    ########################## Model Selection ######
    
    # -- subset of not missing and not direct estimate of 0 -- #
    exdat <- newdata
    # # clusters <- unique(exdat$cluster)
    # # exdat$cluster.id <- match(exdat$cluster, clusters)
    # # cluster.time <- expand.grid(cluster = clusters, time = 1:N)
    # cluster.time$nugget.id <- 1:dim(cluster.time)[1]
    # exdat <- merge(exdat, cluster.time, by.x = c("cluster", "time.struct"), by.y = c("cluster", "time"))
    exdat$nugget.id <- 1:dim(exdat)[1]

  if(is.null(formula)){
        period.constr <- NULL
        Tmax <- length(year_names)            
        if(rw == 2) period.constr <- list(A = matrix(c(rep(1, Tmax)), 1, Tmax), e = 0)
        if(rw %in% c(1, 2) == FALSE) stop("Random walk only support rw = 1 or 2.")
   
     ## ---------------------------------------------------------
    ## Setup PC prior model
    ## ---------------------------------------------------------
    if(tolower(hyper) == "pc"){
        hyperpc1 <- list(prec = list(prior = "pc.prec", param = c(pc.u , pc.alpha)))
        hyperpc2 <- list(prec = list(prior = "pc.prec", param = c(pc.u , pc.alpha)), 
                         phi = list(prior = 'pc', param = c(pc.u.phi , pc.alpha.phi)))
        
        ## -----------------------
        ## Period + National + PC
        ## ----------------------- 
        if(!is.yearly && is.null(geo)){

              formula <- Y ~
                            f(time.struct,model=paste0("rw", rw), constr = TRUE,  extraconstr = period.constr, hyper = hyperpc1) + 
                            f(time.unstruct,model="iid", hyper = hyperpc1) 

        ## -----------------------
        ## Yearly + National + PC
        ## -----------------------
        }else if(is.yearly && is.null(geo)){

          formula <- Y ~
              f(time.struct, model = rw.model.pc, diagonal = 1e-6, extraconstr = constr, values = 1:N) + 
              f(time.unstruct,model=iid.model.pc) 
            

        ## -------------------------
        ## Period + Subnational + PC
        ## ------------------------- 
        }else if(!is.yearly && (!is.null(geo))){

            formula <- Y ~ 
                f(time.struct, model=paste0("rw", rw), hyper = hyperpc1, scale.model = TRUE, extraconstr = period.constr)  + 
                f(time.unstruct,model="iid", hyper = hyperpc1) + 
                f(region.struct, graph=Amat,model="bym2", hyper = hyperpc2, scale.model = TRUE)  

            if(type.st == 1){
                formula <- update(formula, ~. + 
                    f(time.area,model="iid", hyper = hyperpc1))
            }else if(type.st == 2){
                formula <- update(formula, ~. + 
                    f(region.int,model="iid", group=time.int,control.group=list(model=paste0("rw", rw), scale.model = TRUE), hyper = hyperpc1))
            }else if(type.st == 3){
                formula <- update(formula, ~. + 
                    f(region.int, model="besag", graph = Amat, group=time.int,control.group=list(model="iid"), hyper = hyperpc1, scale.model = TRUE))
            }else{
                formula <- update(formula, ~. + 
                    f(region.int,model="besag", graph = Amat, scale.model = TRUE, group=time.int, control.group=list(model=paste0("rw", rw), scale.model = TRUE), hyper = hyperpc1))
            }
          
        ## ------------------------- 
        ## Yearly + Subnational + PC
        ## ------------------------- 
        }else{
              formula <- Y ~
                  f(time.struct, model = rw.model.pc, diagonal = 1e-6, extraconstr = constr, values = 1:N) +
                  f(time.unstruct,model=iid.model.pc) + 
                  f(region.struct, graph=Amat,model="bym2", hyper = hyperpc2, scale.model = TRUE) + 
                  f(time.area,model=st.model.pc, diagonal = 1e-6, extraconstr = constr.st, values = 1:(N*S))
        }

    ## ---------------------------------------------------------
    ## Setup Gamma prior model
    ## ---------------------------------------------------------
    }else if(tolower(hyper) == "gamma"){
        ## ------------------- 
        ## Period + National
        ## ------------------- 
        if(!is.yearly && is.null(geo)){
            formula <- Y ~
              f(time.struct,model=paste0("rw", rw),param=c(a.rw,b.rw), constr = TRUE)  + 
              f(time.unstruct,model="iid",param=c(a.iid,b.iid)) 
            
        ## ------------------- 
        ## Yearly + National
        ## -------------------   
        }else if(is.yearly && is.null(geo)){
           formula <- Y ~
                  f(time.struct, model = rw.model, diagonal = 1e-6, extraconstr = constr, values = 1:N) + 
                  f(time.unstruct,model=iid.model) 
            
        ## ------------------- 
        ## Period + Subnational
        ## ------------------- 
        }else if(!is.yearly && (!is.null(geo))){
       
            formula <- Y ~
                  f(time.struct,model=paste0("rw", rw), param=c(a.rw,b.rw), scale.model = TRUE, extraconstr = period.constr)  + 
                  f(time.unstruct,model="iid",param=c(a.iid,b.iid)) + 
                  f(region.struct, graph=Amat,model="besag",param=c(a.icar,b.icar), scale.model = TRUE) + 
                  f(region.unstruct,model="iid",param=c(a.iid,b.iid)) 
                  
            if(type.st == 1){
                formula <- update(formula, ~. + f(time.area,model="iid", param=c(a.iid,b.iid)))
            }else if(type.st == 2){
                formula <- update(formula, ~. + f(region.int,model="iid", group=time.int,control.group=list(model="rw2", scale.model = TRUE), param=c(a.iid,b.iid)))
            }else if(type.st == 3){
                formula <- update(formula, ~. + f(region.int,model="besag", graph = Amat, group=time.int,control.group=list(model="iid"),param=c(a.iid,b.iid), scale.model = TRUE))
            }else{
                formula <- update(formula, ~. + f(region.int,model="besag", graph = Amat, scale.model = TRUE, group=time.int,control.group=list(model="rw2", scale.model = TRUE),param=c(a.iid,b.iid)))
            }
         
          
        ## ------------------- 
        ## Yearly + Subnational
        ## ------------------- 
        }else{
            formula <- Y ~
              f(time.struct, model = rw.model, diagonal = 1e-6, extraconstr = constr, values = 1:N) + 
              f(time.unstruct,model=iid.model) + 
              f(region.struct, graph=Amat,model="besag",param=c(a.icar,b.icar), scale.model = TRUE) + 
              f(region.unstruct,model="iid",param=c(a.iid,b.iid)) + 
              f(time.area,model=st.model, diagonal = 1e-6, extraconstr = constr.st, values = 1:(N*S)) 
        }
    }else{
      stop("hyper needs to be either pc or gamma.")
    }

    if(family == "binomial"){
      if(tolower(hyper) == "gamma"){
          formula <- update(formula, ~.+ f(nugget.id,model="iid",model="iid", param=c(a.iid,b.iid)))
      }else if(tolower(hyper) == "pc"){
          formula <- update(formula, ~.+ f(nugget.id,model="iid", hyper = hyperpc1))
      }else{
          stop("hyper needs to be either pc or gamma.")
      }
    }
    formula <- update(formula, ~. -1 + age + strata)
    if(!is.null(bias.adjust)){
      exdat <- merge(exdat, bias.adjust, all.x = TRUE)
      if("ratio" %in% colnames(exdat) == FALSE){
        stop("bias.adjust argument is misspecified. It require the following column: ratio.")
      }
    }else{
      exdat$ratio <- 1
    }
    exdat$logoffset <- log(exdat$ratio)

    formula <- update(formula, ~. + offset(logoffset))
}


## add yearly observations with NA outcome and 1 trial, does not contribute to likelihood
total <- NA
exdat <- subset(exdat, total != 0)
for(i in 1:N){
    tmp<-exdat[match(unique(exdat$region), exdat$region), ]
    tmp$time.unstruct<-tmp$time.struct<-tmp$time.int <- i
    tmp <- tmp[, colnames(tmp) != "time.area"]
    tmp <- merge(tmp, time.area, by = c("region_number", "time.unstruct"))
    tmp$years<-years[i, 1]
    tmp$total <- 1
    tmp$Y <- NA
    exdat<-rbind(exdat,tmp)   
  }
  exdat$strata <- factor(exdat$strata)
  exdat$age <- factor(exdat$age, levels = age.groups)


  # for(z in 1:20) print(".")

      
  fit <- INLA::inla(formula, family = family, control.compute = options, data = exdat, control.predictor = list(compute = FALSE), Ntrials = exdat$total, lincomb = NULL, control.inla = list(int.strategy = "auto"), verbose = verbose)

 # find the name for baseline strata
 levels <- grep("strata", rownames(fit$summary.fixed))   
 levels <- gsub("strata", "", rownames(fit$summary.fixed)[levels])
 strata.all <- as.character(unique(exdat$strata))
 strata.base <- strata.all[strata.all%in%levels == FALSE]

  return(list(model = formula, fit = fit, family= family, Amat = Amat, newdata = exdat, time = seq(0, N - 1), area = seq(0, region_count - 1), survey.time = survey.time, survey.area = survey.area, time.area = time.area, survey.time.area = survey.time.area, a.iid = a.iid, b.iid = b.iid, a.rw = a.rw, b.rw = b.rw, a.rw = a.rw, b.rw = b.rw, a.icar = a.icar, b.icar = b.icar, is.yearly = is.yearly, age.groups = age.groups, age.n = age.n, strata.base = strata.base))
    
  }
}
  
  