% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/SimulateMDCEV.R
\name{StanWelfare}
\alias{StanWelfare}
\title{StanWelfare}
\usage{
StanWelfare(df_indiv, df_common, sim_options)
}
\arguments{
\item{df_indiv}{list of inc, quant_j, price_j, psi, and psi_p that vary by individual}

\item{df_common}{list of parameters that are constant for all individuals}

\item{sim_options}{list of simualtion options}
}
\value{
wtp list
}
\description{
Use Stan functions to simulate Welfare
}
