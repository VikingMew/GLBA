############################################################################
## Gated Latent Beta Allocation
## Jianbo Ye <jxy198 at ist.psu.edu>

############################################################################
## define prior
tau0 = 0.5
rate0 = 0.1
gamma0 = 0.3 # fixed prior

## compute ratio statistics
ratio = function(I, alpha, beta, gamma, weight =1.) {
  J = (1-I) * weight;
  I = I * weight;
  diag(J) = 0;
  logratio = log(alpha / (alpha+beta) / gamma) %*% I + 
             log(beta / (alpha+beta) / (1-gamma)) %*%  J;
  return (exp(logratio));
}
  
## compute alpha and beta statistics
alpha_and_beta = function(I, ab, tau) {
  omega = as.vector(I %*% tau);
  psi   = rowSums(I);
  return(list(alpha = ab$alpha + omega, 
              beta  = ab$beta + psi - omega));
}

## solve digamma equations
gamma_solve = function(rhs, x0, step=10, rate=rate0, delta=1.) {
  m = nrow(x0);
  x = x0;
  for (i in 1:step) {
    f = digamma(x) - matrix(digamma(rowSums(x)), m, 2) - rhs + 
        delta * matrix(rate * rowSums(x) -  log(rowSums(x)), m, 2);
    df1 =  trigamma(rowSums(x)) + delta / rowSums(x);
    df = cbind(trigamma(x[,1]) - df1 + rate * delta + 1, 
               -df1 + rate * delta + 1, 
               -df1 + rate * delta + 1, 
               trigamma(x[,2]) -df1 + rate * delta + 1);
    invdf = cbind(df[,4], -df[,3], -df[,2], df[,1]) / matrix(df[,1]*df[,4] - df[,2]*df[,3], m, 4);
    x = x - cbind(invdf[,1]*f[,1] + invdf[,2]*f[,2], invdf[,3]*f[,1] + invdf[,4]*f[,2]);
    x[x<=0.01] = 0.01 # projected 
  }
  return(x)
}

## Variational EM update function
varEM_update = function(theta, hypergraph) {
  n = length(hypergraph$I); 
  m = length(theta$tau); 
  Psi = matrix(0, m, 3);
  Tau = as.vector(matrix(0, 1, m));
  Delta = as.vector(matrix(0, 1, m));
  gamma = list(omega = 0, psi = 0);
  for (i in 1:n) {
    I = hypergraph$I[[i]];
    U = hypergraph$inv_oracles[hypergraph$U[[i]]];
    w = theta$w[U];
    ab = list(alpha = theta$ab[U,1], 
                   beta =  theta$ab[U, 2]);
    tau = theta$tau[U];
    ab_data = alpha_and_beta(I, ab, tau * w);
    Psi[U,1]=Psi[U,1] + digamma(ab_data$alpha);
    Psi[U,2]=Psi[U,2] + digamma(ab_data$beta);
    Psi[U,3]=Psi[U,3] + digamma(ab_data$alpha + ab_data$beta);
    r_data = ratio(I, ab$alpha, ab$beta, theta$gamma, w);
    Tau[U] = Tau[U] + r_data * tau / (r_data * tau + 1 - tau);
    gamma$omega = gamma$omega + sum(I %*% ((1-tau) * w));
    gamma$psi   = gamma$psi   + sum(sum(w) - I %*% w - w);
    Delta[U] = Delta[U] + 1;
  }

  theta$ab = gamma_solve(cbind((Psi[,1]-Psi[,3])/Delta, (Psi[,2]-Psi[,3])/Delta), theta$ab, delta = 1/Delta);
  theta$tau = (Tau + tau0) / (Delta+1);
  theta$gamma = (gamma$omega + gamma0) / (gamma$psi + 1);
  #plot(rowSums(theta$ab), theta$tau, ylim=c(0, 1), xlab = "Predictability", ylab = "Reliability")
  rbPal <- colorRampPalette(c('red','green'))
  colors <- rbPal(10)[as.numeric(cut(theta$tau,breaks = 10))]
  plot(theta$ab[,2], theta$ab[,1], xlab = "beta", ylab = "alpha", pch = 20, asp = 1., col = colors);
  abline(a=0, b=theta$gamma / (1-theta$gamma), col = "red", lwd = 2)
  return(theta)
}


glba = function(hypergraph, weight = 1., tau = 0.5, iter = 100) {
  m = length(hypergraph$oracles);
  theta={};
  theta$ab = cbind(matrix(1., m, 1), matrix(1., m, 1)) / (2*tau0);
  theta$tau = tau * as.vector(matrix(1, m, 1));
  theta$gamma = 0.5
  theta$w = weight * as.vector(matrix(1, m, 1));
  
  for (i in 1:iter) {
    theta = varEM_update(theta, hypergraph);
    if (i > 50) { # empirical Bayes
      tau0 <<- mean(theta$tau);
      rate0 <<- 1/mean(theta$ab);
    }
  }
  return(theta);
}
