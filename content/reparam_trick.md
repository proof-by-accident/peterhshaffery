---
title: The Reparameterization Trick for Hierarchical Modeling
author: Peter Shaffery
date: 2019-08-29
---

# Intro

If you apply Bayesian statistics then chances are that at some point in your career you'll encounter a hierarchical model, if you haven't already. Hierarchical models are very handy, and while [non-Bayesian versions exist](https://en.wikipedia.org/wiki/Random_effects_model), in my opinion the Bayesian logic is especially suited for expressing and analyzing them. Furthermore, I think the odds are good that if you're encountering a hierarchical model, that it was implemented and fit using MCMC, and probably Hamiltonian Monte Carlo (HMC) by way of [Stan](https://mc-stan.org/). If I'm right, then you've probably encountered This One Weird Trick to improve HMC performance when fitting heirarchical models; I'm talking about the reparameterization trick.

I've never entirely understood why this trick works, and I've always been a little surprised that a simple transformation makes such a big difference. The outcome seems unusually good for the amount of effort involved. In my experience explanations for why this trick works are kind of sparse. [The sacred text](http://www.stat.columbia.edu/~gelman/book/) devotes like 3 lines to explaining it. Although I've never seen it explicitly stated, I've always gotten the vibe that a complete explanation for this trick is an "exercise left to the reader", but I've been too lazy and/or busy to actually do it. So in this post I'm going to finally bite the bullet and work out why this trick is so effective.

Let's get a handle on what we're talking about here. A standard hierarchical model where reparameteriation would be applied is:
<div>
$$
\begin{split}
y_j &\sim N(\theta_j,\sigma^2_j)\\
\theta_j &\sim N(\mu, \tau)\\
\end{split}
$$
</div>

Where $\sigma^2_j$ is assumed to be known. The reparameterization is then:
<div>
$$
\begin{split}
y_j &\sim N(\mu + \tau \eta_j, \sigma^2_j)\\
\eta_j &\sim N(0,1)\\
\end{split}
$$
</div>

In both cases the goal is to estimate $\mu$ and $\tau$, but in the second case we've made the substitution $\theta_j = \mu + \tau \eta_j$. If you chuck Model 1 into Stan, you'll find that your sampler explodes into [divergence confetti](https://mc-stan.org/users/documentation/case-studies/divergences_and_bias.html). Somehow, reparameterization evades the confetti, so let's see why that is.

# HMC Basics
The variant of HMC implemented in Stan is pretty sophisticated, but to understand why the reparameterization trick works we only need to consider "vanilla" HMC.

Say we want to sample from a density $\pi(\theta)$, and we initialize with point $\theta^{(k)}$. HMC iterates over the following steps:
<ol>
<li>Draw an augmented "momentum" variable $p^{(k)} \sim N(0,\Sigma)$</li>

<li>With initial conditions $(\theta^{(k)},p^{(k)})$, "mass" matrix $M$, and for $l$ time-steps, solve the ODE (typically using a symplectic integrator like the leapfrog method):
<div>
$$
\begin{split}
\frac{d \theta}{d t} &= M p\\
\frac{d p}{d t} &= - \nabla \ln(\pi(\theta))\\
\end{split}
$$
</div>
</li>
<li> Take the endpoint of the trajectory from Step 2, denoted $(\theta',p')$, as a candidate for a Metropolis update. That is, calculate acceptance probability:
<div>
$$
\alpha = \min \left(1, \frac{\pi(\theta') N(p',\Sigma)}{\pi(\theta)N(p,\Sigma)} \right)
$$
</div>
and then set $\theta^{(k+1)} = \theta'$ with probability $\alpha$, otherwise retaining $\theta^{(k+1)} = \theta^{(k)}$.
</li>
</ol>

The values of $l$, $M$, and $\Sigma$ are all free parameters, the choice of which can deeply impact algorithm performance. However, for our purposes is this part of Step 2: $\frac{d p}{d t} = - \nabla \ln(\pi(\theta))$.

What we're seeing here is that the gradient of the log posterior plays a big role in determining how the HMC algorithm behaves. This is because it's directly related to the curvature of the proposal trajectory $\kappa(\theta(t))$. Back in Calc 3 we all learned that curvature can be calculated $\kappa(\theta(t)) = ||T'(\theta(t))||$, where $T(\theta(t))$ is the tangent vector to the trajectory at point $\theta(t)$. From the Hamiltonian ODE in Step 2 we know that $T(t) = p(t)$ and therefore $T' = - \nabla \ln(\pi(\theta(t))$. Therefore the curvature of the proposal trajectory is $\kappa(\theta(t)) = || \nabla \ln(\pi(\theta(t))||$. So when the log-posterior gradient is large, the proposal trajectory will exhibit a high amount of curvature. In general, this is bad. Highly curved trajectories may increase the amount of autocorrelation in our sample chain, which decreases our effective sample size. Even worse, though, high amounts of curvature may effect the numerical performance of our ODE solver. To summarize: when the posterior gradient blows up, our sampler's performance plummets.


# The Problem with Hierarchical Models
Okay so we know that large gradients are problematic for HMC. Now let's see how this relates to the reparameterization trick. To start, let's write out the posterior for model 1 explicity:
<div>
$$
\begin{split}
P[\theta_j,\mu,\tau | y_j ] \propto & \big[ \prod\limits_{j=1}^n \exp(-(y_j-\theta_j)^2/\sigma^2) \times \\
&\exp(-(\theta_j - \mu^2)/\tau) \big] \times \text{Pr}(\mu,\tau)\\
\end{split}
$$
</div>
As we can see, the posterior has a singularity whenever $\tau = 0$, thus when we take the gradient of the log-posterior:
<div>
$$
\frac{d \ln(P[\theta_j,\mu,\tau|y_j])}{d \tau} = \sum\limits_{j=1}^n \frac{(\theta_j - \mu)^2}{\tau^2} + \frac{d}{d \tau} \ln \text{Pr}[\mu,\tau]
$$
</div>
We see that the gradient, and hence the curvature of the HMC proposal trajectory, will blows up near $\tau=0$, producing the divergences.

Now let's look at what the posterior looks like after reparameterization:
<div>
$$
\begin{split}
P[\eta_j,\mu,\tau | y_j ] \propto &\big[\prod\limits_{j=1}^n \exp(-(y_j-\mu - \tau \eta_j)^2/\sigma^2) \times\\
 &\exp(-\eta_j^2) \big] \times \text{Pr}(\mu,\tau)\\
\end{split}
$$
</div>
By reparameterizing $\theta_j$ we've removed the singularity in the posterior: the middle factor in the posterior has gone from $\exp(-(\theta_j - \mu^2/\tau)$ to $\exp(-\eta_j^2)$. Now the gradient will be well-behaved for all $\tau$, and so our sampler will stop diverging.

# But Why?
Frankly, I'm still not satisfied. While I now understand why reparameterization works (it removes the singularity), I still don't really understand [why](https://www.smbc-comics.com/comic/2010-06-20) it's so effective, ie. what, intuitively, allows a pretty simple transformation to remove the singularity in the first place. This post is getting a little long, however, so I'm going to cognizate on that while and maybe address it in a follow-up post.
