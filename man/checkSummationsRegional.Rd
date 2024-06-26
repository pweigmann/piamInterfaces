% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/checkSummationsRegional.R
\name{checkSummationsRegional}
\alias{checkSummationsRegional}
\title{Checks for a run if the regions for selected variables sum up as expected}
\usage{
checkSummationsRegional(mifFile, parentRegion, childRegions, variables)
}
\arguments{
\item{mifFile}{path to the mif file to apply summation checks to, or quitte object}

\item{parentRegion}{region to sum up to}

\item{childRegions}{regions that should sum up to \code{parentRegion}}

\item{variables}{list of variables to check}
}
\description{
Checks for a run if the regions for selected variables sum up as expected
}
\examples{
\dontrun{
checkSummationsRegional(
  mifFile = "path/to/file",
  childRegions = c("R5ASIA", "R5LAM", "R5MAF", "R5OECD90+EU", "R5REF"),
  parentRegion = "World",
  variables = c("Final Energy|Industry", "Emissions|CO2|Energy|Demand|Industry")
)
}
}
\author{
Falk Benke
}
