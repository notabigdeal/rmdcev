context("Test Bayes")

tol <- 0.00001
data(data_rec, package = "rmdcev")
data_rec

# sprintf("%.10f",result$log.likelihood)
# sprintf("%.10f",result$bic)
# sprintf("%.10f",result[["stan_fit"]][["par"]][["scale"]] )
# sprintf("%.10f",result[["stan_fit"]][["par"]][["psi"]] )
# sprintf("%.10f",result[["stan_fit"]][["par"]][["alpha"]] )
# sprintf("%.10f",wtp_err )


test_that("Bayes gamma0 specification", {
	result <- FitMDCEV(psi_formula = ~ factor(good_name) -1,
								data = subset(data_rec, id < 1000),
								model = "gamma0",
								algorithm = "Bayes",
					   print_iterations = FALSE,
					   n_chains = 1,
					   n_iterations = 10,
					   show_stan_warnings = FALSE)

	expect_equal(dim(result$est_pars), c(175, 3))
})