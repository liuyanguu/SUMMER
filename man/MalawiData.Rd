% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/MalawiData.R
\docType{data}
\name{MalawiData}
\alias{MalawiData}
\title{Auxiliary data for Malawi 2000, 2004, 2010, and 2015 DHS.}
\format{An object of class \code{list} of length 4.}
\usage{
data(MalawiData)
}
\description{
The list contains several data frames.
}
\details{
\itemize{
 \item HIV, a data frame with three columns: years (in five year periods),  survey, and the estimated bias of the reported U5MR due to HIV for each 5 year period. The bias is represented as the ratio of the reported U5MR to the true U5MR.
 \item HIV.yearly, a data frame with three columns: years (in one year interval),  survey, and the estimated bias of the reported U5MR due to HIV for each year. The bias is represented as the ratio of the reported U5MR to the true U5MR.
 \item IGME2019. Yearly Estimates of national under-5 child mortality in Malawi from the 2019 UN-IGME estimates.
 \item IGME2019.nmr. Yearly Estimates of national neonatal mortality in Malawi from the 2019 UN-IGME estimates.
}
}
\references{
Neff Walker, Kenneth Hill, and Fengmin Zhao (2012) \emph{Child mortality estimation: methods used to adjust for bias due to aids in estimating trends in under-five mortality.}, \cr \emph{PLoS Medicine, 9(8):e1001298}.
}
\keyword{datasets}
