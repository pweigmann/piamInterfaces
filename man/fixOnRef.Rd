% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/fixOnRef.R
\name{fixOnRef}
\alias{fixOnRef}
\title{Checks for a run if it is correctly fixed on the reference run for t < startyear}
\usage{
fixOnRef(
  data,
  refscen,
  startyear,
  ret = "boolean",
  failfile = NULL,
  relDiff = 1e-12
)
}
\arguments{
\item{data}{quitte object or mif file}

\item{refscen}{scenario name of reference scenario, or file or quitte object with reference data}

\item{startyear}{first time step for which scenarios and reference scenario are expected to differ}

\item{ret}{"boolean": just return TRUE/FALSE if check was successful
"fails": data frame with mismatches between scenario and reference data
"fixed": quitte object with data correctly fixed on reference data}

\item{failfile}{csv file to which mismatches are written to}

\item{relDiff}{threshold for acceptable relative difference}
}
\value{
see parameter 'ret'
}
\description{
Checks for a run if it is correctly fixed on the reference run for t < startyear
}
\author{
Oliver Richters
}
