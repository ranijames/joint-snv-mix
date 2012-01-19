'''
Created on 2012-01-16

@author: Andrew Roth
'''
from __future__ import division

import ConfigParser

from libc.math cimport exp, log
from libc.stdlib cimport malloc, free

from joint_snv_mix.counter cimport JointBinaryData, JointBinaryCountData, JointBinaryQualityData
from joint_snv_mix.models.utils cimport binomial_log_likelihood, beta_log_likelihood, dirichlet_log_likelihood, \
                                        snv_mix_two_log_likelihood, snv_mix_two_single_read_log_likelihood, \
                                        snv_mix_two_expected_a, snv_mix_two_expected_b, \
                                        log_space_normalise, log_sum_exp 

#=======================================================================================================================
# Priors and Parameters
#=======================================================================================================================
cdef class JointSnvMixPriors(object):
    cdef tuple _mu_N
    cdef tuple _mu_T
    cdef tuple _pi
    
    def __init__(self, mu_N=None, mu_T=None, pi=None):
        default_mu = (
                      {'alpha' : 100, 'beta' : 2},
                      {'alpha' : 50, 'beta' : 50},
                      {'alpha' : 2, 'beta' : 100}
                      )
        
        default_pi = (2,) * 9
        
        if mu_N is None:
            self._mu_N = default_mu
        else:
            self._mu_N = tuple(mu_N)
        
        if mu_T is None:
            self._mu_T = default_mu
        else:
            self._mu_T = tuple(mu_T)
        
        if pi is None:
            self._pi = default_pi
        else:
            self._pi = tuple(pi)

    def __str__(self):
        s = "mu_N_alpha : "        
        s += "\t".join([str(x['alpha']) for x in self.mu_N])
        s += "\n"

        s += "mu_N_beta : "        
        s += "\t".join([str(x['beta']) for x in self.mu_N])
        s += "\n"
        
        s += "mu_T_alpha : "        
        s += "\t".join([str(x['alpha']) for x in self.mu_T])
        s += "\n"

        s += "mu_T_beta : "        
        s += "\t".join([str(x['beta']) for x in self.mu_T])
        s += "\n"                   
        
        s += "pi : "
        s += "\t".join([str(x) for x in self.pi])
        s += "\n"
        
        return s

    def read_from_file(self, file_name):
        genotypes = ['AA', 'AB', 'BB']
        joint_genotypes = []
        
        for g_N in genotypes:
            for g_T in genotypes:
                joint_genotypes.append("_".join((g_N, g_T)))
        
        config = ConfigParser.SafeConfigParser()
        config.read(file_name)
        
        mu_N = []
        mu_T = []
        pi = []
        
        for g in range(genotypes):
            mu_N_g = {}
            mu_N_g['alpha'] = float(config.get('mu_N_alpha', g))
            mu_N_g['beta'] = float(config.get('mu_N_beta', g)) 
            
            mu_N.append(mu_N_g)
            
            mu_T_g = {}
            mu_T_g['alpha'] = float(config.get('mu_T_alpha', g))
            mu_T_g['beta'] = float(config.get('mu_T_beta', g)) 
            
            mu_T.append(mu_T_g)
        
        for g in range(joint_genotypes):
            pi_g = float(config.get('pi', g))
            
            self.pi.append(pi_g)
        
        self._mu_N = tuple(mu_N)
        self._mu_T = tuple(mu_T)
        
        # Normalise pi
        self._pi = tuple(pi)
        
    property mu_N:
        def __get__(self):
            return self._mu_N
    
    property mu_T:
        def __get__(self):
            return self._mu_T
        
    property pi:
        def __get__(self):
            return self._pi

#---------------------------------------------------------------------------------------------------------------------- 
cdef class JointSnvMixParameters(object):
    cdef tuple _mu_N
    cdef tuple _mu_T
    cdef tuple _pi

    def __init__(self, mu_N=None, mu_T=None, pi=None):
        default_mu = (0.99, 0.5, 0.01)
        
        default_pi = (1e6, 1e3, 1e3, 1e3, 1e4, 1e3, 1e1, 1e1, 1e4)
        
        if mu_N is None:
            self._mu_N = default_mu
        else:
            self._mu_N = tuple(mu_N)
            
        if mu_T is None:
            self._mu_T = default_mu
        else:
            self._mu_T = tuple(mu_T)
        
        if pi is None:
            self._pi = default_pi
        else:
            self._pi = tuple(pi)
        
        # Normalise pi
        self._pi = tuple([x / sum(self._pi) for x in self._pi])         
        
    def __str__(self):
        s = "mu_N : "
        s += "\t".join([str(x) for x in self.mu_N])
        s += "\n"
        
        s += "mu_T : "
        s += "\t".join([str(x) for x in self.mu_T])
        s += "\n"

        s += "pi : "
        s += "\t".join([str(x) for x in self.pi])
        s += "\n"
        
        return s
    
    def write_to_file(self, file_name):
        genotypes = ['AA', 'AB', 'BB']
        joint_genotypes = []
        
        for g_N in genotypes:
            for g_T in genotypes:
                joint_genotypes.append("_".join((g_N, g_T)))
        
        config = ConfigParser.SafeConfigParser()
        
        config.add_section('pi')
        config.add_section('mu_N')
        config.add_section('mu_T')
        
        for g_N, mu_N in zip(genotypes, self.mu_N):
            config.set('mu_N', g_N, "{0:.10f}".format(mu_N))
        
        for g_T, mu_T in zip(genotypes, self.mu_T):
            config.set('mu_T', g_T, "{0:.10f}".format(mu_T))
            
        for g_J, pi in zip(joint_genotypes, self.pi):
            config.set('pi', g_J, "{0:.10f}".format(pi))
        
        fh = open(file_name, 'w')
        config.write(fh)
        fh.close()
        
    def read_from_file(self, file_name):
        genotypes = ['AA', 'AB', 'BB']
        joint_genotypes = []
        
        for g_N in genotypes:
            for g_T in genotypes:
                joint_genotypes.append("_".join((g_N, g_T)))
        
        config = ConfigParser.SafeConfigParser()
        config.read(file_name)
        
        mu_N = []
        mu_T = []
        pi = []
        
        for g in range(genotypes):
            mu_N_g = config.getfloat('mu_N', g)            
            mu_N.append(mu_N_g)
            
            mu_T_g = config.getfloat('mu_T', g)
            mu_T.append(mu_T_g)
        
        for g in range(joint_genotypes):
            pi_g = config.getgetfloat('pi', g)
            pi.append(pi_g)
        
        self._mu_N = tuple(mu_N)
        self._mu_T = tuple(mu_T)
        
        # Normalise pi
        self._pi = tuple([x / sum(pi) for x in pi])

    property mu_N:
        def __get__(self):
            return self._mu_N
    
    property mu_T:
        def __get__(self):
            return self._mu_T
        
    property pi:
        def __get__(self):
            return self._pi
        
#=======================================================================================================================
# Model
#=======================================================================================================================
cdef class JointSnvMixModel(object):
    cdef JointSnvMixPriors _priors
    cdef JointSnvMixParameters _params
    
    cdef _JointSnvMixDensity _density
    cdef _JointSnvMixEss _ess
    
    cdef int _num_joint_genotypes
    cdef double * _resp
    
    def __cinit__(self, JointSnvMixPriors priors, JointSnvMixParameters params, model="jsm1"):
        self._priors = priors
        self._params = params
        
        if model == "jsm1":
            self._density = _JointSnvMixOneDensity(params)
            self._ess = _JointSnvMixOneEss(len(params._mu_N), len(params._mu_T))            
        elif model == "jsm2":
            self._density = _JointSnvMixTwoDensity(params)
            self._ess = _JointSnvMixTwoEss(len(params._mu_N), len(params._mu_T))
        else:
            raise Exception("{0} not a recongnised model. Options are jsm1, jsm2.".format(model))
        
        self._num_joint_genotypes = len(params._mu_N) * len(params._mu_T)
        
        self._resp = < double *> malloc(sizeof(double) * self._num_joint_genotypes)
    
    def __dealloc__(self):
        free(self._resp)

    def predict(self, data_point):
        self._density.get_responsibilities(data_point, self._resp)
        
        return [exp(x) for x in self._resp[:self._num_joint_genotypes]]
    
    def fit(self, data, max_iters=1000, tolerance=1e-6, verbose=False):
        '''
        Fit the model using the EM algorithm.
        '''        
        iters = 0
        ll = [float('-inf')]
        converged = False
        
        while not converged:            
            self._E_step(data)
            
            ll_iter = self._get_log_likelihood(data)
            
            self._M_step()
            
            ll.append(ll_iter)
            
            ll_diff = ll[-1] - ll[-2]
            
            iters += 1
            
            if verbose:
                print "#" * 20
                print iters, ll[-1]
                print self.params
            
            if ll_diff < 0:
                print self.params
                print ll[-1], ll[-2]
                raise Exception('Lower bound decreased.')
            elif ll_diff < tolerance:
                print "Converged"
                converged = True
            elif iters >= max_iters:
                print "Maximum number of iterations exceeded exiting."
                converged = True
            else:
                converged = False
    
    cdef _E_step(self, data):
        cdef JointBinaryData data_point
    
        self._ess.reset()
        self._density.set_params(self._params)

        for data_point in data:
            self._density.get_responsibilities(data_point, self._resp)
            self._ess.update(data_point, self._resp)

    cdef _M_step(self):
        self._params._mu_N = self._get_updated_mu(self._ess.a_N, self._ess.b_N, self._priors._mu_N)
        self._params._mu_T = self._get_updated_mu(self._ess.a_T, self._ess.b_T, self._priors._mu_T)
        
        self._params._pi = self._get_updated_pi(self._ess.n, self._priors._pi)

    cdef _get_updated_mu(self, a, b, prior):
        '''
        Compute MAP update to binomial parameter mu with a beta prior.
        ''' 
        mu = []
        
        for a_g, b_g, prior_g in zip(a, b, prior):
            alpha = a_g + prior_g['alpha'] - 1
            beta = b_g + prior_g['beta'] - 1
            
            denom = alpha + beta

            mu.append(alpha / denom)
        
        return tuple(mu)
            
    cdef _get_updated_pi(self, n, prior):
        '''
        Compute the MAP update of the mix-weights in a mixture model with a Dirichlet prior.
        '''        
        pi = []
        
        for n_g, prior_g in zip(n, prior):
            pi.append(n_g + prior_g - 1)
        
        pi = [x / sum(pi) for x in pi]

        return tuple(pi)
    
    cdef double _get_log_likelihood(self, data):
        cdef double log_liklihood
        cdef JointBinaryData data_point
        
        log_likelihood = self._get_prior_log_likelihood()
        
        for data_point in data:
            log_likelihood += self._density.get_log_likelihood(data_point, self._resp)
        
        return log_likelihood
    
    cdef _get_prior_log_likelihood(self):
        '''
        Compute the prior portion of the log likelihood.
        '''        
        ll = 0
        
        for mu_N, mu_N_prior in zip(self.params.mu_N, self.priors.mu_N):
            ll += beta_log_likelihood(mu_N, mu_N_prior['alpha'], mu_N_prior['beta'])

        for mu_T, mu_T_prior in zip(self.params.mu_T, self.priors.mu_T):
            ll += beta_log_likelihood(mu_T, mu_T_prior['alpha'], mu_T_prior['beta'])         
        
        ll += dirichlet_log_likelihood(self.params.pi, self.priors.pi)
        
        print ll
        
        return ll
    
    property params:
        def __get__(self):
            return self._params
        
    property priors:
        def __get__(self):
            return self._priors

#=======================================================================================================================
# Density
#=======================================================================================================================
cdef class _JointSnvMixDensity(object):
    '''
    Base class for density objects. Sub-classing objects need to implement one method, get_responsibilities. This method
    computes the responsibilities for a data-point.
    '''
    cdef int _num_normal_genotypes
    cdef int _num_tumour_genotypes
    cdef int _num_joint_genotypes
    
    cdef double * _mu_N
    cdef double * _mu_T
    cdef double * _log_mix_weights
    #===================================================================================================================
    # Interface
    #===================================================================================================================
    cdef _get_complete_log_likelihood(self, JointBinaryData data_point, double * ll):
        '''
        Get the log_likelihood the data point belongs to each class in the model. This will be stored in ll.
        '''
        pass
    
    #===================================================================================================================
    # Implementation
    #===================================================================================================================
    def __cinit__(self, JointSnvMixParameters params):        
        self._num_normal_genotypes = len(params._mu_N)
        
        self._num_tumour_genotypes = len(params._mu_T)
           
        self._num_joint_genotypes = self._num_normal_genotypes * self._num_tumour_genotypes

        self._init_arrays()

        self.set_params(params)        
        
    def __dealloc__(self):
        free(self._mu_N)
        free(self._mu_T)
        free(self._log_mix_weights)
    
    cdef _init_arrays(self):
        self._mu_N = < double *> malloc(sizeof(double) * self._num_normal_genotypes)
        self._mu_T = < double *> malloc(sizeof(double) * self._num_tumour_genotypes)
        
        self._log_mix_weights = < double *> malloc(sizeof(double) * self._num_joint_genotypes)    

    cdef get_responsibilities(self, JointBinaryData data_point, double * resp):
        '''
        Computes the responsibilities of the given data-point. Results are stored in resp.
        '''
        cdef int i
        
        self._get_complete_log_likelihood(data_point, resp)
       
        # Normalise the class log likelihoods in place to get class posteriors
        log_space_normalise(resp, self._num_joint_genotypes)
        
        for i in range(self._num_joint_genotypes):
            resp[i] = exp(resp[i])
        
    cdef double get_log_likelihood(self, JointBinaryData data_point, double * ll):
        '''
        Computes the log_likelihood for a single point.
        '''
        self._get_complete_log_likelihood(data_point, ll)
        
        return log_sum_exp(ll, self._num_joint_genotypes)
    
    cdef set_params(self, JointSnvMixParameters params):
        '''
        Copy Python level parameters into C arrays for fast access.
        '''
        for i, mu_N in enumerate(params._mu_N):
            self._mu_N[i] = mu_N

        for i, mu_T in enumerate(params._mu_T):
            self._mu_T[i] = mu_T
        
        # Store the log of the mix-weights to speed up computation.
        for i, pi in enumerate(params._pi):
            self._log_mix_weights[i] = log(pi)

#---------------------------------------------------------------------------------------------------------------------- 
cdef class _JointSnvMixOneDensity(_JointSnvMixDensity):    
    cdef _get_complete_log_likelihood(self, JointBinaryData uncast_data_point, double * ll):        
        cdef int g_N, g_T, g_J, a, b
        cdef double mu_N, mu_T, log_mix_weight, normal_log_likelihood, tumour_log_likelihood
        
        cdef JointBinaryCountData data_point = < JointBinaryCountData > uncast_data_point
    
        for g_N in range(self._num_normal_genotypes):            
            for g_T in range(self._num_tumour_genotypes):
                # Index of joint genotype
                g_J = (self._num_tumour_genotypes * g_N) + g_T
                
                mu_N = self._mu_N[g_N]
                mu_T = self._mu_T[g_T]
                
                log_mix_weight = self._log_mix_weights[g_J]
                
                normal_log_likelihood = binomial_log_likelihood(data_point._a_N, data_point._b_N, mu_N)
                tumour_log_likelihood = binomial_log_likelihood(data_point._a_T, data_point._b_T, mu_T)
                
                # Combine the mix-weight, normal likelihood and tumour likelihood to obtain class likelihood
                ll[g_J] = log_mix_weight + normal_log_likelihood + tumour_log_likelihood
                
#---------------------------------------------------------------------------------------------------------------------- 
cdef class _JointSnvMixTwoDensity(_JointSnvMixDensity):
    cdef _get_complete_log_likelihood(self, JointBinaryData uncast_data_point, double * ll):
        cdef int g_N, g_T, g_J
        cdef double mu_N, mu_T, log_mix_weight, normal_log_likelihood, tumour_log_likelihood
    
        cdef JointBinaryQualityData data_point = < JointBinaryQualityData > uncast_data_point
    
        for g_N in range(self._num_normal_genotypes):            
            for g_T in range(self._num_tumour_genotypes):
                # Index of joint genotype
                g_J = (self._num_tumour_genotypes * g_N) + g_T
                
                mu_N = self._mu_N[g_N]
                mu_T = self._mu_T[g_T]
                
                log_mix_weight = self._log_mix_weights[g_J]
                                        
                normal_log_likelihood = snv_mix_two_log_likelihood(data_point._q_N,
                                                                   data_point._r_N,
                                                                   data_point._d_N,
                                                                   mu_N)
                
                tumour_log_likelihood = snv_mix_two_log_likelihood(data_point._q_T,
                                                                   data_point._r_T,
                                                                   data_point._d_T,
                                                                   mu_T)
                
                # Combine the mix-weight, normal likelihood and tumour likelihood to obtain class likelihood
                ll[g_J] = log_mix_weight + normal_log_likelihood + tumour_log_likelihood

#=======================================================================================================================
# Ess
#=======================================================================================================================
cdef class _JointSnvMixEss(object):
    '''
    Base class for storing and updating expected sufficient statistics (ESS) for JointSnvMix models using Bernoulli or
    Binomial distributions.
    '''
    cdef int _num_normal_genotypes
    cdef int _num_tumour_genotypes
    cdef int _num_joint_genotypes
    
    cdef double * _a_N
    cdef double * _b_N
    cdef double * _a_T
    cdef double * _b_T
    cdef double * _n
        
    #===================================================================================================================
    # Interface
    #===================================================================================================================
    cdef update(self, JointBinaryData data_point, double * resp):
        '''
        Update the ESS given the data-point and responsibilities.
        '''
        pass
    
    #===================================================================================================================
    # Implementation
    #===================================================================================================================
    def __init__(self, int num_normal_genotypes, int num_tumour_genotypes):        
        self._num_normal_genotypes = num_normal_genotypes
        
        self._num_tumour_genotypes = num_tumour_genotypes
        
        self._num_joint_genotypes = num_normal_genotypes * num_tumour_genotypes        

        self._init_arrays()
        
        self.reset()    
    
    def __dealloc__(self):
        free(self._a_N)
        free(self._b_N)
        free(self._a_T)
        free(self._b_T)
        free(self._n)

    cdef _init_arrays(self):
        '''
        Allocate arrays for sufficient statistics and initialise to 0.        
        '''
        self._a_N = < double *> malloc(sizeof(double) * self._num_normal_genotypes)
        self._b_N = < double *> malloc(sizeof(double) * self._num_normal_genotypes)

        self._a_T = < double *> malloc(sizeof(double) * self._num_tumour_genotypes)
        self._b_T = < double *> malloc(sizeof(double) * self._num_tumour_genotypes)
       
        self._n = < double *> malloc(sizeof(double) * self._num_joint_genotypes)
        
    cdef reset(self):
        cdef int i
    
        for i in range(self._num_normal_genotypes):
            self._a_N[i] = 0
            self._b_N[i] = 0
            
        for i in range(self._num_tumour_genotypes):
            self._a_T[i] = 0
            self._b_T[i] = 0            

        for i in range(self._num_joint_genotypes):
            self._n[i] = 0
    
    property a_N:
        def __get__(self):
            return [x for x in self._a_N[:self._num_normal_genotypes]]

    property b_N:
        def __get__(self):
            return [x for x in self._b_N[:self._num_normal_genotypes]]
        
    property a_T:
        def __get__(self):
            return [x for x in self._a_T[:self._num_tumour_genotypes]]
        
    property b_T:
        def __get__(self):
            return [x for x in self._b_T[:self._num_tumour_genotypes]]
    
    property n:
        def __get__(self):
            return [x for x in self._n[:self._num_joint_genotypes]]
                    
#---------------------------------------------------------------------------------------------------------------------- 
cdef class _JointSnvMixOneEss(_JointSnvMixEss):
    cdef update(self, JointBinaryData data_point, double * resp):
        cdef int g_N, g_T, g_J
    
        for g_N in range(self._num_normal_genotypes):            
            for g_T in range(self._num_tumour_genotypes):
                g_J = (self._num_tumour_genotypes * g_N) + g_T
            
                self._a_N[g_N] += data_point._a_N * resp[g_J]
                self._b_N[g_N] += data_point._b_N * resp[g_J]
                
                self._a_T[g_T] += data_point._a_T * resp[g_J]
                self._b_T[g_T] += data_point._b_T * resp[g_J]
            
                self._n[g_J] += resp[g_J]      

#---------------------------------------------------------------------------------------------------------------------- 
cdef class _JointSnvMixTwoEss(_JointSnvMixEss):
    cdef update(self, JointBinaryData uncast_data_point, double * resp):
        cdef int g_N, g_T, g_J
        cdef double mu_N, mu_T, a_N, a_T, b_N, b_T
        
        cdef JointBinaryQualityData data_point = < JointBinaryQualityData > uncast_data_point
    
        for g_N in range(self._num_normal_genotypes):            
            for g_T in range(self._num_tumour_genotypes):
                # Index of joint genotype
                g_J = (self._num_tumour_genotypes * g_N) + g_T
                
                mu_N = self._mu_N[g_N]
                mu_T = self._mu_T[g_T]
            
                for i in range(data_point._d_N):
                    a_N = snv_mix_two_expected_a(data_point._q_N[i], data_point._r_N[i], mu_N)
                    b_N = snv_mix_two_expected_b(data_point._q_N[i], data_point._r_N[i], mu_N)
                    
                    self._a_N[g_N] += a_N * self._resp[g_J]
                    self._b_N[g_N] += b_N * self._resp[g_J]
                    
                for i in range(data_point._d_T):
                    a_T = snv_mix_two_expected_a(data_point._q_T[i], data_point._r_T[i], mu_T)
                    b_T = snv_mix_two_expected_b(data_point._q_T[i], data_point._r_T[i], mu_T)
                    
                    self._a_T[g_T] += a_T * self._resp[g_J]
                    self._b_T[g_T] += b_T * self._resp[g_J]                    

                self._n[g_J] += self._resp[g_J] 
