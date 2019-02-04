
//stan_wtp <- "
functions {

/**
 * Draw conditional or unconditional error draws *
 * @param N Number of rows correspond to data items
 * @param K Number of predictors, counting the intercept, per
 *          item.
 * @return Matrix of nerrs X ngood errors
 */
vector[] DrawError_rng(real quant_num, vector quant_j, vector price_j,
					vector psi_j, vector gamma_j, vector alpha, real scale,
					int ngoods, int nerrs, int cond_error){
// Function to Draw conditional or unconditional errors
	vector[ngoods+1] error[nerrs];

	// Unconditional Error Draws
	if (cond_error == 0){
		for(err in 1:nerrs)
			for(j in 1:ngoods+1)
				error[err, j] = -log(-log(uniform_rng(0, 1))) * scale; //uniform(0,1) draws

	// Conditional Error Draws
	} else if (cond_error == 1){
		// Cacluate the demand function, g
		vector[ngoods + 1] cond_demand = append_row(quant_num, quant_j);
		// compute vk and v1
		real v1 = (alpha[1] - 1) * log(quant_num);
		vector[ngoods + 1] e;
		vector[ngoods] vk = psi_j + (alpha[2:ngoods+1] - 1) .* log(quant_j ./ gamma_j + 1) - log(price_j);
		// ek = v1 - vk and assume error term is zero for outside good
		e = append_row(0, (v1 - vk) / scale);

		// Calculate errors
		// For unvisited alternatives, draw from truncated multivariate
		// logistic distribution
		for(err in 1:nerrs)
			for(j in 1:ngoods+1)
				error[err, j] = cond_demand[j] > 0 ? e[j] * scale :
							-log(-log(uniform_rng(0, 1) * exp(-exp(-e[j])))) * scale;
		}
return(error);
}


int[] CalcGoodOrder(vector MUzero, int ngoods) {
/**
 * Returns an ranking vector of non-numeraire goods by MUzero
 *
 * @param MUzero vector of MU for each good
 * @param ngoods Number of goods
 * @return integer vector of ordered goods by MUzero
 */
	int order_x[ngoods+1];
	vector[ngoods] ord_goods;
	int order_MU[ngoods] = sort_indices_desc(MUzero[2:ngoods+1]);
	for (j in 1:ngoods)
		ord_goods[j] = j;

	order_x = sort_indices_asc(append_row(1.0, to_vector(ord_goods[order_MU] + 1)));
return(order_x);
}

matrix SortParmMatrix(vector MUzero, vector price, vector gamma, vector alpha, int ngoods) {

	matrix[ngoods+1, 4] parm_matrix;
	vector[ngoods] MU_j = MUzero[2:ngoods+1];
	vector[ngoods] price_j = price[2:ngoods+1];
	vector[ngoods] gamma_j = gamma[2:ngoods+1];
	vector[ngoods] alpha_j = alpha[2:ngoods+1];
	int order_MU[ngoods] = sort_indices_desc(MU_j);	// find ranking of non-numeraire goods by MUzero

	parm_matrix = append_col(append_row(MUzero[1], MU_j[order_MU]),
	append_col(append_row(price[1], price_j[order_MU]),
	append_col(append_row(gamma[1], gamma_j[order_MU]), append_row(alpha[1], alpha_j[order_MU]))));
return(parm_matrix);
}

vector MarshallianDemandHybrid(real inc, vector price,
							vector MUzero, vector gamma, vector alpha,
							int ngoods) {
// Function to simulate Marshallian Demands using Hybrid approach

	vector[ngoods+1] mdemand;
	int M = 1; // Indicator of which ordered alteratives (<=M) are being considered
	int exit = 0;
	int order_x[ngoods+1] = CalcGoodOrder(MUzero, ngoods);
	real lambda_num;
	real lambda_den;
	real lambda;
	real alpha_1;
	vector[ngoods+1] X = rep_vector(0, ngoods+1);
	vector[ngoods+1] a;
	vector[ngoods+1] b;
	vector[ngoods+1] c;
	vector[ngoods+1] d = append_row(0, rep_vector(1, ngoods));
	vector[ngoods+1] mu;
	vector[ngoods+1] g;
	matrix[ngoods+1, 4] parm_matrix = SortParmMatrix(MUzero, price, gamma, alpha, ngoods);

	mu = col(parm_matrix, 1);
	g = col(parm_matrix, 3);
	a = g .* col(parm_matrix, 2);
	alpha_1 = alpha[1];

	for (j in 1:ngoods+1)
		b[j] = pow(mu[j], inv(1 - alpha_1));

	c = a .* b;

	while (exit == 0){
		// Calculate lambda equal to MUzero(M+1)
		lambda_num = inc + sum(a[1:M]) - 1; // minus one for numeraire
		lambda_den = sum(c[1:M]);
		lambda = pow(lambda_num / lambda_den, alpha_1 - 1);

		//Compare lambda to baseline utility of the next lowest alternative
		//(M+1). If lambda exceeds this value then all lower-valued
		//alternatives have zero demand.

		if (lambda > mu[min(M + 1, ngoods + 1)] || M == ngoods+1){
			// Compute demands (using eq. 12 in Pinjari and Bhat)
			for (m in 1:M)
				X[m] = (pow(lambda / mu[m], 1 / (alpha_1 - 1)) - d[m]) * g[m];
			exit = 1;

		} else if ( M < ngoods + 1)
			M = M + 1;
	}

		// This code puts the choices back in their original
		// order and exports demands
	mdemand = X[order_x];
return(mdemand);
}

real ComputeE(int M, real lambda, vector a, vector b, vector c, vector d){
	real output;
	vector[M] temp;
	for (m in 1:M)
		temp[m] = a[m] * (lambda ^ b[m] / c[m] -d[m]);
	output =  sum(temp);
return(output);
}

vector MarshallianDemandGeneral(real inc, vector price,
							vector MUzero, vector gamma, vector alpha,
							int ngoods) {
// Function to simulate Marshallian Demans using General approach

	vector[ngoods+1] mdemand;
	real tol_e = 1e-20;
	int max_loop = 999;
	int M = 1; // Indicator of which ordered alteratives (<=M) are being considered
	int exit = 0;
	real E;
	int order_x[ngoods+1] = CalcGoodOrder(MUzero, ngoods);
	real lambda_l;
	real lambda_u;
	real lambda;
	vector[ngoods+1] X = rep_vector(0, ngoods+1);
	vector[ngoods+1] a;
	vector[ngoods+1] b;
	vector[ngoods+1] c;
	vector[ngoods+1] d = append_row(0, rep_vector(1, ngoods));
	vector[ngoods+1] mu;
	vector[ngoods+1] g;
	matrix[ngoods+1, 4] parm_matrix = SortParmMatrix(MUzero, price, gamma, alpha, ngoods);

	mu = col(parm_matrix, 1);
	g = col(parm_matrix, 3);
	a = g .* col(parm_matrix, 2);
	b = col(parm_matrix, 4);
	b = inv(append_row(b[1], b[2:ngoods+1]) - 1);

	for (j in 1:ngoods+1)
		c[j] = mu[j] ^ b[j];

	while (exit == 0){
		// Calculate lambda equal to MUzero(M+1)
		lambda = mu[M + 1];
		// Calculate E
		E = ComputeE(M, lambda, a, b, c, d);

		if (E >= inc || M+1 == ngoods+1){
			M = E < inc ? M + 1 : M;
			lambda_l = E < inc ? 0 : lambda;
			lambda_u = mu[M];
			lambda = (lambda_l + lambda_u) / 2;

			for (n in 1:max_loop){
				E = ComputeE(M, lambda, a, b, c, d);

				// Update lambdas's
				lambda_u = E > inc ? lambda_u : (lambda_l + lambda_u) / 2;
				lambda_l = E < inc ? lambda_l : (lambda_l + lambda_u) / 2;
				lambda = (lambda_l + lambda_u) / 2;

				if (fabs(E - inc) < tol_e) break;
				}

			// Compute demands (using eq. 12 in Pinjari and Bhat)
			for (m in 1:M)
				X[m] = ((lambda / mu[m]) ^ b[m] -d[m]) * g[m];
			exit = 1;

		} else if (E < inc && M + 1 < ngoods + 1)
			M = M + 1;
	}

	// This code puts the choices back in their original
	// order and exports demands
	mdemand = X[order_x];
return(mdemand);
}

vector MarshallianDemand(real inc, vector price,
							vector MUzero, vector gamma, vector alpha,
							int ngoods, int algo_gen) {

	vector[ngoods+1] mdemand;
	int M = 1; // Indicator of which ordered alteratives (<=M) are being considered
	int exit = 0;
	real E;
	int order_x[ngoods+1] = CalcGoodOrder(MUzero, ngoods);
	vector[ngoods+1] X = rep_vector(0, ngoods+1);
	vector[ngoods+1] d = append_row(0, rep_vector(1, ngoods));
	matrix[ngoods+1, 4] parm_matrix = SortParmMatrix(MUzero, price, gamma, alpha, ngoods);
	vector[ngoods+1] mu = col(parm_matrix, 1); // obtain mu
	vector[ngoods+1] g = col(parm_matrix, 3); // obtain gamma
	vector[ngoods+1] a = g .* col(parm_matrix, 2);

	if (algo_gen == 0) { //Hybrid
		real lambda_num;
		real lambda_den;
		real lambda;
		real alpha_1 = alpha[1];
		vector[ngoods+1] g_psi = g .* mu .* col(parm_matrix, 2); // obtain gamma_psi
		vector[ngoods+1] b;
		vector[ngoods+1] c;

		for (j in 1:ngoods+1)
			b[j] = pow(mu[j], inv(1 - alpha_1));

		c = a .* b;

		while (exit == 0){
			// Calculate lambda equal to MUzero(M+1)
			lambda_num = inc + sum(a[1:M]) - 1; // minus one for numeraire
			lambda_den = sum(c[1:M]);
			lambda = pow(lambda_num / lambda_den, alpha_1 - 1);

			//Compare lambda to baseline utility of the next lowest alternative
			//(M+1). If lambda exceeds this value then all lower-valued
			//alternatives have zero demand.

			if (lambda > mu[min(M + 1, ngoods + 1)] || M == ngoods+1){
				// Compute demands (using eq. 12 in Pinjari and Bhat)
				for (m in 1:M)
					X[m] = (pow(lambda / mu[m], 1 / (alpha_1 - 1)) - d[m]) * g[m];
				exit = 1;

			} else if ( M < ngoods + 1)
				M = M + 1;
			}

	} else if (algo_gen == 1) {//	General
		real tol_e = 1e-20;
		int max_loop = 999;
		real lambda_l;
		real lambda_u;
		real lambda;
		vector[ngoods+1] b = col(parm_matrix, 4);
		vector[ngoods+1] c;
		b = inv(append_row(b[1], b[2:ngoods+1]) - 1);

		for (j in 1:ngoods+1)
			c[j] = mu[j] ^ b[j];

		while (exit == 0){
			// Calculate lambda equal to MUzero(M+1)
			lambda = mu[M + 1];
			// Calculate E
			E = ComputeE(M, lambda, a, b, c, d);

			if (E >= inc || M+1 == ngoods+1){
				M = E < inc ? M + 1 : M;
				lambda_l = E < inc ? 0 : lambda;
				lambda_u = mu[M];
				lambda = (lambda_l + lambda_u) / 2;

				for (n in 1:max_loop){
					E = ComputeE(M, lambda, a, b, c, d);

					// Update lambdas's
					lambda_u = E > inc ? lambda_u : (lambda_l + lambda_u) / 2;
					lambda_l = E < inc ? lambda_l : (lambda_l + lambda_u) / 2;
					lambda = (lambda_l + lambda_u) / 2;

					if (fabs(E - inc) < tol_e) break;
					}

				// Compute demands (using eq. 12 in Pinjari and Bhat)
				for (m in 1:M)
					X[m] = ((lambda / mu[m]) ^ b[m] -d[m]) * g[m];
				exit = 1;

			} else if (E < inc && M + 1 < ngoods + 1)
				M = M + 1;
		}
	}
	// This code puts the choices back in their original
	// order and exports demands
	mdemand = X[order_x];
return(mdemand);
}

real ComputeUtilJ(real inc, vector quant_j, vector price_j,
					vector psi_j, vector gamma_j, vector alpha,
					int ngoods, int model_type) {

	real output;
	real util_num; // numeraire
	vector[ngoods] util_j;

	if (model_type != 4){
		util_num = 1 / alpha[1] * pow(inc -  price_j' * quant_j, alpha[1]);

		if (model_type == 1){
			util_j = psi_j .* gamma_j .* log(quant_j ./ gamma_j + 1);
		} else if (model_type != 1){
			for (n in 1:ngoods)
				util_j[n] = (psi_j[n] * gamma_j[n]) / alpha[n+1] *
				(pow(quant_j[n] / gamma_j[n] + 1, alpha[n+1]) - 1);
		}
	} else if (model_type == 4){
		util_num = log(inc -  price_j' * quant_j);
		util_j = psi_j .* gamma_j .* log(quant_j ./ gamma_j + 1);
	}

	output = util_num + sum(util_j);
return(output);
}

vector HicksianDemandHybrid(real util, vector price,
						vector MUzero, vector gamma, vector alpha,
						int ngoods, int model_type) {

	vector[ngoods+1] hdemand;
	int M = 1; // Indicator of which ordered alteratives (<=M) are being considered
	int exit = 0;
	real util_new;
	int order_x[ngoods+1] = CalcGoodOrder(MUzero, ngoods);
	real lambda_num;
	real lambda_den;
	real lambda;
	real lambda1;
	matrix[ngoods+1, 4] parm_matrix = SortParmMatrix(MUzero, price, gamma, alpha, ngoods);
	vector[ngoods+1] X = rep_vector(0, ngoods+1);
	vector[ngoods+1] d = append_row(0, rep_vector(1, ngoods));
	real alpha_1 = alpha[1];
	vector[ngoods+1] mu = col(parm_matrix, 1); // obtain mu
	vector[ngoods+1] g = col(parm_matrix, 3); // obtain gamma
	vector[ngoods+1] g_psi = g .* mu .* col(parm_matrix, 2); // obtain gamma_psi
	vector[ngoods+1] b;
	vector[ngoods+1] c;

	for (j in 1:ngoods+1)
		b[j] = pow(mu[j], -alpha_1 / (alpha_1 - 1)); // want price/psi so take negative of exponent

	c = g_psi .* b;

	while (exit == 0){
		// Calculate 1/lambda for a given M
		lambda_num = alpha_1 * util + sum(g_psi[1:M]) - g_psi[1] / g[1]; // utility not expenditure and subtract numeriare psi
		lambda_den = sum(c[1:M]);
		lambda = pow(lambda_num / lambda_den, -(alpha_1 - 1) / alpha_1); // new exponent term
		lambda1 = 1 / lambda;   // Compare 1/lambda to MU

		// Compare 1/lambda to baseline utility of the next lowest alternative
		// (M+1). If lambda exceeds this value then all lower-valued
		// alternatives have zero demand.
		if (lambda1 > mu[min(M + 1, ngoods + 1)] || M == ngoods+1){

			// Compute demands (using eq. 12 in Pinjari and Bhat)
			for (m in 1:M)
				X[m] = (pow(inv(lambda * mu[m]), inv(alpha_1 - 1)) - d[m]) * g[m];
			exit = 1;

		} else if (M < ngoods + 1)
			M = M + 1;
	}

	// This code puts the choices back in their original order and exports demands
	hdemand = X[order_x];
return(hdemand);
}

real ComputeUtilM(int M, real lambda1, vector g_psi_a, vector a_a_1, vector mu_a_a_1,
					vector psi, vector g, vector price, vector d, int model_type){
	real output;
	vector[M] temp;
	temp[1] = g_psi_a[1] * (pow(lambda1, a_a_1[1]) * mu_a_a_1[1] - d[1]); // compute numeraire util
	if (M > 1){
		for (m in 2:M){
			if (model_type == 1) {
				temp[m] = psi[m] * g[m] * log(psi[m] / (lambda1 * price[m]));
			} else if (model_type != 1) {
			 	temp[m] = g_psi_a[m] * (pow(lambda1, a_a_1[m]) * mu_a_a_1[m] - d[m]);
			}
		}
	}
	output =  sum(temp);
return(output);
}


vector HicksianDemandGeneral(real util, vector price,
				vector MUzero, vector gamma, vector alpha,
				int ngoods, int model_type) {

	vector[ngoods+1] hdemand;
	real tol_l = 1e-20;
	int max_loop = 9999;
	int M = 1; // Indicator of which ordered alteratives (<=M) are being considered
	int exit = 0;
	real util_new;
	real lambda_l;
	real lambda_u;
	real lambda1;
	int order_x[ngoods+1] = CalcGoodOrder(MUzero, ngoods);
	matrix[ngoods+1, 4] parm_matrix = SortParmMatrix(MUzero, price, gamma, alpha, ngoods);
	vector[ngoods+1] X = rep_vector(0, ngoods+1);
	vector[ngoods+1] d = append_row(0, rep_vector(1, ngoods));
	vector[ngoods+1] a; // alpha
	vector[ngoods+1] g_psi_a; // gamma*psi/alpha
	vector[ngoods+1] a_a_1; // (alpha/(alpha-1))
	vector[ngoods+1] mu_a_a_1; // (1/MUzero)^(alpha/(alpha-1))
	vector[ngoods+1] mu; // MUzero
	vector[ngoods+1] g; // gamma
	vector[ngoods+1] price_ord; // price
	vector[ngoods+1] psi;

	mu = col(parm_matrix, 1);
	g = col(parm_matrix, 3);
	price_ord = col(parm_matrix, 2);
	a = col(parm_matrix, 4);

	psi = mu .* price_ord;
	g_psi_a = g .* psi ./ a;
	a_a_1 = a ./ (a - 1);

	for (j in 1:ngoods+1)
		mu_a_a_1[j] = pow(inv(mu[j]), a_a_1[j]);

	while (exit == 0){
		// Calculate lambda equal to MUzero(M+1)
		lambda1 = mu[M + 1];
		// Calculate new utility
		util_new = ComputeUtilM(M, lambda1, g_psi_a, a_a_1, mu_a_a_1, psi, g, price_ord, d, model_type);

		if (util_new >= util || M+1 == ngoods+1){
			M = util_new < util ? M + 1 : M;
			lambda_l = util_new < util ? 0 : lambda1;
			lambda_u = mu[M];
			lambda1 = (lambda_l + lambda_u) / 2;

			for (n in 1:max_loop){
				util_new = ComputeUtilM(M, lambda1, g_psi_a, a_a_1, mu_a_a_1, psi, g, price_ord, d, model_type);

				// Update lambdas's
				lambda_u = util_new > util ? lambda_u : (lambda_l + lambda_u) / 2;
				lambda_l = util_new < util ? lambda_l : (lambda_l + lambda_u) / 2;
				lambda1 = (lambda_l + lambda_u) / 2;

				if (fabs((lambda_l - lambda_u) / (lambda_l + lambda_u) * 0.5) < tol_l) break;
			}

		// Compute demands (using eq. 12 in Pinjari and Bhat)
		for (m in 1:M)
			X[m] = ((lambda1 / mu[m]) ^ (1 / (a[m]-1))  -d[m]) * g[m];

		exit = 1;

		} else if (util_new < util && M + 1 < ngoods + 1)
		M = M + 1;
	}

	// This code puts the choices back in their original order and exports demands
	hdemand = X[order_x];
return(hdemand);
}

vector HicksianDemand(real util, vector price,
				vector MUzero, vector gamma, vector alpha,
				int ngoods, int algo_gen, int model_type) {

	vector[ngoods+1] hdemand;
	int M = 1; // Indicator of which ordered alteratives (<=M) are being considered
	int exit = 0;
	real lambda1;
	real util_new;
	int order_x[ngoods+1] = CalcGoodOrder(MUzero, ngoods);
	vector[ngoods+1] X = rep_vector(0, ngoods+1);
	vector[ngoods+1] d = append_row(0, rep_vector(1, ngoods));
	matrix[ngoods+1, 4] parm_matrix = SortParmMatrix(MUzero, price, gamma, alpha, ngoods);
	vector[ngoods+1] mu = col(parm_matrix, 1); // obtain mu
	vector[ngoods+1] g = col(parm_matrix, 3); // obtain gamma

	if (algo_gen == 0) { //Hybrid
		real lambda_num;
		real lambda_den;
		real lambda;
		real alpha_1 = alpha[1];
		vector[ngoods+1] g_psi = g .* mu .* col(parm_matrix, 2); // obtain gamma_psi
		vector[ngoods+1] b;
		vector[ngoods+1] c;

		for (j in 1:ngoods+1)
			b[j] = pow(mu[j], -alpha_1 / (alpha_1 - 1)); // want price/psi so take negative of exponent

		c = g_psi .* b;

		while (exit == 0){
			// Calculate 1/lambda for a given M
			lambda_num = alpha_1 * util + sum(g_psi[1:M]) - g_psi[1] / g[1]; // utility not expenditure and subtract numeriare psi
			lambda_den = sum(c[1:M]);
			lambda = pow(lambda_num / lambda_den, -(alpha_1 - 1) / alpha_1); // new exponent term
			lambda1 = 1 / lambda;   // Compare 1/lambda to MU

			// Compare 1/lambda to baseline utility of the next lowest alternative
			// (M+1). If lambda exceeds this value then all lower-valued
			// alternatives have zero demand.
			if (lambda1 > mu[min(M + 1, ngoods + 1)] || M == ngoods+1){

				// Compute demands (using eq. 12 in Pinjari and Bhat)
				for (m in 1:M)
					X[m] = (pow(inv(lambda * mu[m]), inv(alpha_1 - 1)) - d[m]) * g[m];
				exit = 1;

			} else if (M < ngoods + 1)
				M = M + 1;
		}
	} else if (algo_gen == 1) {//	General
		real tol_l = 1e-20;
		int max_loop = 9999;
		real lambda_l;
		real lambda_u;
		vector[ngoods+1] price_ord = col(parm_matrix, 2); // price
		vector[ngoods+1] a = col(parm_matrix, 4);//	alpha
		vector[ngoods+1] psi = mu .* price_ord;
		vector[ngoods+1] g_psi_a = g .* psi ./ a; // gamma*psi/alpha
		vector[ngoods+1] a_a_1 = a ./ (a - 1); // (alpha/(alpha-1))
		vector[ngoods+1] mu_a_a_1; // (1/MUzero)^(alpha/(alpha-1))

		for (j in 1:ngoods+1)
			mu_a_a_1[j] = pow(inv(mu[j]), a_a_1[j]);

		while (exit == 0){
			// Calculate lambda equal to MUzero(M+1)
			lambda1 = mu[M + 1];
			// Calculate new utility
			util_new = ComputeUtilM(M, lambda1, g_psi_a, a_a_1, mu_a_a_1, psi, g, price_ord, d, model_type);

			if (util_new >= util || M+1 == ngoods+1){
				M = util_new < util ? M + 1 : M;
				lambda_l = util_new < util ? 0 : lambda1;
				lambda_u = mu[M];
				lambda1 = (lambda_l + lambda_u) / 2;

				for (n in 1:max_loop){
					util_new = ComputeUtilM(M, lambda1, g_psi_a, a_a_1, mu_a_a_1, psi, g, price_ord, d, model_type);

					// Update lambdas's
					lambda_u = util_new > util ? lambda_u : (lambda_l + lambda_u) / 2;
					lambda_l = util_new < util ? lambda_l : (lambda_l + lambda_u) / 2;
					lambda1 = (lambda_l + lambda_u) / 2;

					if (fabs((lambda_l - lambda_u) / (lambda_l + lambda_u) * 0.5) < tol_l) break;
				}

			// Compute demands (using eq. 12 in Pinjari and Bhat)
			for (m in 1:M)
				X[m] = ((lambda1 / mu[m]) ^ (1 / (a[m]-1))  -d[m]) * g[m];

			exit = 1;

			} else if (util_new < util && M + 1 < ngoods + 1)
			M = M + 1;
		}
	}
	// This code puts the choices back in their original order and exports demands
	hdemand = X[order_x];
return(hdemand);
}

// Overall code
vector CalcTest_rng(real inc, vector quant_j, vector price, //vector error,
						vector[] price_p, matrix[] psi_p_sims,
						matrix psi_sims, vector[] gamma_sims, vector[] alpha_sims, vector scale_sims,
						int ngoods, int nsims, int nerrs, int npols,
						int cond_error, int algo_gen, int model_type){

	matrix[nsims, npols] wtp;
	real quant_num = inc - quant_j' * price[2:ngoods+1];
	vector[nsims] util;

	for (sim in 1:nsims){
		vector[ngoods] psi_j = psi_sims[sim]';
		matrix[npols, ngoods] psi_p = psi_p_sims[sim];
		vector[ngoods + 1] gamma = append_row(1, gamma_sims[sim]);
		vector[ngoods + 1] alpha = alpha_sims[sim];
		real scale = scale_sims[sim];
		vector[ngoods + 1] error[nerrs];
//		vector[ngoods + 1] psi_b_err[nerrs]; // keep psi for use in policies
		vector[npols] wtp_policy;
		vector[nerrs] util_s;

		error = DrawError_rng(quant_num, quant_j, price[2:ngoods+1],
							psi_j, gamma[2:ngoods+1], alpha, scale,
							ngoods, nerrs, cond_error);

		// Compute Marshallian demands and baseline utility
		for (err in 1:nerrs){
			vector[ngoods + 1] mdemand;
			vector[ngoods + 1] MUzero_b;
			vector[ngoods + 1] psi_b_err;
			psi_b_err = exp(append_row(0, psi_j) + error[err]);
			MUzero_b = psi_b_err ./ price;

			if (cond_error == 1){
				mdemand = append_row(quant_num, quant_j);
			} else if(cond_error == 0)	{

				if (algo_gen == 1)
					mdemand = MarshallianDemandGeneral(inc, price, MUzero_b, gamma, alpha, ngoods);
				else if (algo_gen == 0)
					mdemand = MarshallianDemandHybrid(inc, price, MUzero_b, gamma, alpha, ngoods);
			}

			util_s[err] = ComputeUtilJ(inc, mdemand[2:ngoods+1], price[2:ngoods+1],
									psi_b_err[2:ngoods+1], gamma[2:ngoods+1], alpha,
									ngoods, model_type);
		}

		util[sim] = mean(util_s);
	}

return(util);
}


// Overall code
matrix CalchdemandTest_rng(real inc, vector quant_j, vector price,
						vector price_p, vector psi_p_sims,
						vector psi_sims, vector gamma_sims, vector alpha_sims, real scale_sims,
						int ngoods, int nsims, int nerrs, int npols,
						int cond_error, int algo_gen, int model_type){

	matrix[nsims, ngoods+1] hdemand_out;
	real quant_num = inc - quant_j' * price[2:ngoods+1];

	for (sim in 1:nsims){
		vector[ngoods] psi_j = psi_sims;
		vector[ngoods] psi_p = psi_p_sims;
		vector[ngoods + 1] gamma = append_row(1, gamma_sims);
		vector[ngoods + 1] alpha = alpha_sims;
		real scale = scale_sims;
		vector[ngoods + 1] error[nerrs];
//		vector[ngoods + 1] psi_b_err[nerrs]; // keep psi for use in policies
		matrix[nerrs, ngoods + 1] hdemand;
		row_vector[ngoods + 1] hdemand_sims;
		matrix[ngoods + 1, nerrs] hdemand_trans;
		vector[ngoods + 1] price_p_policy = price + price_p; // add price increase

		error = DrawError_rng(quant_num, quant_j, price[2:ngoods+1],
							psi_j, gamma[2:ngoods+1], alpha, scale,
							ngoods, nerrs, cond_error);

		// Compute Marshallian demands and baseline utility
		for (err in 1:nerrs){
			real util;
			vector[ngoods + 1] psi_b_err = exp(append_row(0, psi_j) + error[err]);
			vector[ngoods + 1] MUzero_b = psi_b_err ./ price;
			vector[ngoods + 1] MUzero_p = exp(append_row(0, psi_p) + error[err]) ./ price_p_policy;	// change to psi_p_err for policy

			util = ComputeUtilJ(inc, quant_j, price[2:ngoods+1],
									psi_b_err[2:ngoods+1], gamma[2:ngoods+1], alpha,
									ngoods, model_type);

			if (algo_gen == 1)
				hdemand[err] = HicksianDemandGeneral(util, price_p_policy, MUzero_p, gamma, alpha,
										ngoods, model_type)';
			else if (algo_gen == 0)
				hdemand[err] = HicksianDemandHybrid(util, price_p_policy, MUzero_p, gamma, alpha,
										ngoods, model_type)';
		}

		hdemand_trans = hdemand';

		for(g in 1:ngoods+1)
  			hdemand_sims[g] = mean(hdemand_trans[g]);

		hdemand_out[sim] = hdemand_sims;
	}

return(hdemand_out);
}


// Overall code
matrix CalcmdemandTest_rng(real inc, vector quant, vector price,
						vector psi_sims, vector gamma_sims, vector alpha_sims, real scale_sims,
						int ngoods, int nsims, int nerrs,
						int cond_error, int algo_gen){

	matrix[nsims, ngoods+1] mdemand_out;
	real quant_num = inc - quant[2:ngoods+1]' * price[2:ngoods+1];

	for (sim in 1:nsims){
		vector[ngoods] psi_j = psi_sims;
		vector[ngoods + 1] gamma = append_row(1, gamma_sims);
		vector[ngoods + 1] alpha = alpha_sims;
		real scale = scale_sims;
		vector[ngoods + 1] error[nerrs];
		matrix[nerrs, ngoods + 1] mdemand;
		row_vector[ngoods + 1] mdemand_sims;
		matrix[ngoods + 1, nerrs] mdemand_trans;

		error = DrawError_rng(quant_num, quant[2:ngoods+1], price[2:ngoods+1],
							psi_j, gamma[2:ngoods+1], alpha, scale,
							ngoods, nerrs, cond_error);

		// Compute Marshallian demands and baseline utility
		for (err in 1:nerrs){
			vector[ngoods + 1] MUzero_b;
			vector[ngoods + 1] psi_b_err;
			psi_b_err = exp(append_row(0, psi_j) + error[err]);
			MUzero_b = psi_b_err ./ price;

			if (algo_gen == 1)
				mdemand[err] = MarshallianDemandGeneral(inc, price, MUzero_b, gamma, alpha, ngoods)';
			else if (algo_gen == 0)
				mdemand[err] = MarshallianDemandHybrid(inc, price, MUzero_b, gamma, alpha, ngoods)';
		}
		mdemand_trans = mdemand';

		for(g in 1:ngoods+1)
  			mdemand_sims[g] = mean(mdemand_trans[g]);

		mdemand_out[sim] = mdemand_sims;
	}

return(mdemand_out);
}


// Overall code
matrix Calcmdemand_rng(real inc, vector price,
						vector psi_sims, vector gamma_sims, vector alpha_sims, real scale_sims,
						int ngoods, int nsims, int nerrs,
						int algo_gen){

	matrix[nsims, ngoods+1] mdemand_out;

	for (sim in 1:nsims){
		vector[ngoods] psi_j = psi_sims;
		vector[ngoods + 1] gamma = append_row(1, gamma_sims);
		vector[ngoods + 1] alpha = alpha_sims;
		real scale = scale_sims;
		vector[ngoods + 1] error[nerrs];
		matrix[nerrs, ngoods + 1] mdemand;
		row_vector[ngoods + 1] mdemand_sims;
		matrix[ngoods + 1, nerrs] mdemand_trans;

		for(err in 1:nerrs)
			for(j in 1:ngoods+1)
				error[err, j] = -log(-log(uniform_rng(0, 1))) * scale; //uniform(0,1) draws

		// Compute Marshallian demands and baseline utility
		for (err in 1:nerrs){
			vector[ngoods + 1] MUzero_b;
			vector[ngoods + 1] psi_b_err;
			psi_b_err = exp(append_row(0, psi_j) + error[err]);
			MUzero_b = psi_b_err ./ price;

		if (algo_gen == 1)
			mdemand[err] = MarshallianDemandGeneral(inc, price, MUzero_b, gamma, alpha, ngoods)';
		else if (algo_gen == 0)
			mdemand[err] = MarshallianDemandHybrid(inc, price, MUzero_b, gamma, alpha, ngoods)';
		}
		mdemand_trans = mdemand';

		for(g in 1:ngoods+1)
  			mdemand_sims[g] = mean(mdemand_trans[g]);

		mdemand_out[sim] = mdemand_sims;
	}

return(mdemand_out);
}

matrix CalcWTP_rng(real inc, vector quant_j, vector price,
						vector[] price_p_policy, matrix[] psi_p_sims,
						matrix psi_sims, vector[] gamma_sims, vector[] alpha_sims, vector scale_sims,
						int ngoods, int nsims, int nerrs, int npols,
						int cond_error, int algo_gen, int model_type){

	matrix[nsims, npols] wtp;
	real quant_num = inc - quant_j' * price[2:ngoods+1];

	for (sim in 1:nsims){
		vector[ngoods] psi_j = psi_sims[sim]';
		matrix[npols, ngoods] psi_p_policy = psi_p_sims[sim]; //change for no psi_p
//		vector[ngoods + 1] psi_b_err[nerrs]; // keep psi for use in policies
		vector[ngoods + 1] gamma = append_row(1, gamma_sims[sim]);
		vector[ngoods + 1] alpha = alpha_sims[sim];
		real scale = scale_sims[sim];
		vector[ngoods + 1] error[nerrs];
		vector[npols] wtp_policy;
		vector[nerrs] util;

		error = DrawError_rng(quant_num, quant_j, price[2:ngoods+1],
							psi_j, gamma[2:ngoods+1], alpha, scale,
							ngoods, nerrs, cond_error);

		// Compute Marshallian demands and baseline utility
		for (err in 1:nerrs){
			vector[ngoods + 1] mdemand;
			vector[ngoods + 1] MUzero_b;
//			psi_b_err[err] = exp(append_row(0, psi_j) + error[err]);
//			MUzero_b = psi_b_err[err] ./ price;
			vector[ngoods + 1] psi_b_err;
			psi_b_err = exp(append_row(0, psi_j) + error[err]); //change for no psi_p
			MUzero_b = psi_b_err ./ price; //change for no psi_p

			if (cond_error == 1){
				mdemand = append_row(quant_num, quant_j);
			} else if(cond_error == 0)	{

				if (algo_gen == 1)
					mdemand = MarshallianDemandGeneral(inc, price, MUzero_b, gamma, alpha, ngoods);
				else if (algo_gen == 0)
					mdemand = MarshallianDemandHybrid(inc, price, MUzero_b, gamma, alpha, ngoods);
			}

			util[err] = ComputeUtilJ(inc, mdemand[2:ngoods+1], price[2:ngoods+1],
									psi_b_err[2:ngoods+1], gamma[2:ngoods+1], alpha,
									ngoods, model_type); // add err to psi_b if no psi_p
		}

		for (policy in 1:npols){
			vector[ngoods + 1] price_p = price + price_p_policy[policy]; // add price increase
			vector[ngoods] psi_p = psi_p_policy[policy]'; //change for no psi_p
			vector[nerrs] wtp_err;

			for (err in 1:nerrs){
//				vector[ngoods + 1] MUzero_p = psi_b_err[err] ./ price_p;	// change to psi_p_err for policy
				vector[ngoods + 1] MUzero_p = exp(append_row(0, psi_p) + error[err]) ./ price_p; //change for no psi_p
				vector[ngoods + 1] hdemand;

				if (algo_gen == 1)
					hdemand = HicksianDemandGeneral(util[err], price_p, MUzero_p, gamma, alpha,
											ngoods, model_type);
				else if (algo_gen == 0)
					hdemand = HicksianDemandHybrid(util[err], price_p, MUzero_p, gamma, alpha,
											ngoods, model_type);

				wtp_err[err] = inc - price_p' * hdemand;
			}

			wtp_policy[policy] = mean(wtp_err);
		}

	wtp[sim] = wtp_policy';

	}

return(wtp);
}

}