'''
Created on 2011-08-04

@author: Andrew Roth
'''
from libc.stdlib cimport free, malloc
from libc.math cimport abs, exp, log

from joint_snv_mix.counters.counter cimport Counter
from joint_snv_mix.counters.joint_binary_counter cimport JointBinaryCounterRow
from joint_snv_mix.counters.joint_binary_quality_counter cimport JointBinaryQualityCounterRow, base_map_qualities_struct
from joint_snv_mix.counters.shared cimport binary_counts_struct

from joint_snv_mix.trainers.trainer cimport Trainer
from joint_snv_mix.utils.log_pdf cimport multinomial_log_likelihood, dirichlet_log_likelihood, mixture_posterior

DEF FLOAT_INFN = float('-inf')

DEF NUM_GENOTYPES = 3
DEF NUM_BASES = 2
DEF EPS = 1e-100

ctypedef struct snv_mix_params_struct:
    double mu[NUM_GENOTYPES][NUM_BASES]
    double pi[NUM_GENOTYPES]

ctypedef struct snv_mix_priors_struct:
    double mu[NUM_GENOTYPES][NUM_BASES]
    double pi[NUM_GENOTYPES]
    
ctypedef struct snv_mix_ess_struct:
    double n[NUM_GENOTYPES]
    double a[NUM_GENOTYPES]
    double b[NUM_GENOTYPES]
    
cdef class SnvMixParameters(object):
    cdef snv_mix_params_struct _normal
    cdef snv_mix_params_struct _tumour

    def __init__(self, **kwargs):
        self._init_params(**kwargs)
    
    def _init_params(self, **kwargs):
        mu_N = kwargs.get('mu_N', (0.99, 0.5, 0.01))
        mu_T = kwargs.get('mu_T', (0.99, 0.5, 0.01))
        pi_N = kwargs.get('pi_N', (0.99, 0.009, 0.001))
        pi_T = kwargs.get('pi_T', (0.99, 0.009, 0.001))
        
        for i in range(NUM_GENOTYPES):
            self._normal.mu[i][0] = mu_N[i]
            self._normal.mu[i][1] = 1 - mu_N[i]
            
            self._tumour.mu[i][0] = mu_T[i]
            self._tumour.mu[i][1] = 1 - mu_T[i]
            
            self._normal.pi[i] = pi_N[i]            
            self._tumour.pi[i] = pi_T[i]
    
    property normal:
        def __get__(self):
            return self._convert_params_struct_to_dict(self._normal)
    
    property tumour:
        def __get__(self):
            return self._convert_params_struct_to_dict(self._tumour)
    
    cdef dict _convert_params_struct_to_dict(self, snv_mix_params_struct params):
        result = {}
        
        result['pi'] = []
        result['mu'] = []
        
        for i in range(NUM_GENOTYPES):
            result['pi'].append(params.pi[i])
            result['mu'].append(params.mu[i][0])
        
        return result

cdef SnvMixParameters makeSnvMixParameters(snv_mix_params_struct normal_params, snv_mix_params_struct tumour_params):
     cdef SnvMixParameters params = SnvMixParameters.__new__(SnvMixParameters)
    
     params._normal = normal_params
     params._tumour = tumour_params
     
     return params

cdef class SnvMixPriors(object):
    cdef snv_mix_priors_struct _normal
    cdef snv_mix_priors_struct _tumour

    def __init__(self, **kwargs):
        self._init_params(**kwargs)
    
    def _init_params(self, **kwargs):
        mu_N = kwargs.get('mu_N', (
                                   (100, 3),
                                   (50, 50),
                                   (3, 100)
                                   )
                          )
        mu_T = kwargs.get('mu_T', (
                                   (100, 3),
                                   (50, 50),
                                   (3, 100)
                                   )
                          )
        pi_N = kwargs.get('pi_N', (1000, 100, 100))
        pi_T = kwargs.get('pi_T', (1000, 100, 100))
        
        for i in range(NUM_GENOTYPES):
            self._normal.mu[i][0] = mu_N[i][0]
            self._normal.mu[i][1] = mu_N[i][1]
            
            self._tumour.mu[i][0] = mu_T[i][0]
            self._tumour.mu[i][1] = mu_T[i][1]
            
            self._normal.pi[i] = pi_N[i]            
            self._tumour.pi[i] = pi_T[i]
    
    property normal:
        def __get__(self):
            return self._convert_priors_struct_to_dict(self._normal)
    
    property tumour:
        def __get__(self):
            return self._convert_priors_struct_to_dict(self._tumour)
    
    cdef dict _convert_priors_struct_to_dict(self, snv_mix_priors_struct params):
        result = {}
        
        result['pi'] = []
        result['mu'] = []
        
        for i in range(NUM_GENOTYPES):
            result['pi'].append(params.pi[i])
            result['mu'].append(
                                (params.mu[i][0], params.mu[i][1])
                                )
        
        return result

cdef class SnvMixTrainingData(object):
    cdef double component_log_likelihood(self, double mu[2]):
        pass

cdef class SnvMixOneTrainingData(SnvMixTrainingData):
    cdef int counts[2]
    
    cdef double component_log_likelihood(self, double mu[2]):
        return multinomial_log_likelihood(self.counts, mu, NUM_BASES)
    
cdef SnvMixOneTrainingData makeSnvMixOneTrainingData(binary_counts_struct counts):
    cdef SnvMixOneTrainingData data = SnvMixOneTrainingData.__new__(SnvMixOneTrainingData)
    
    data.counts[0] = counts.A
    data.counts[1] = counts.B
    
    return data
         
#cdef class SnvMixTwoTrainingData(SnvMixTrainingData):
#    cdef int depth
#    cdef int * labels
#    cdef double * q
#    cdef double * r    
#    
#    def __dealloc__(self):
#        free(self.labels)
#        free(self.q)
#        free(self.r)
#    
#cdef SnvMixTwoTrainingData makeSnvMixTwoTrainingData(base_map_qualities_struct data_struct):
#    cdef read_index, i, l
#    cdef double temp_q
#    cdef SnvMixTwoTrainingData data = SnvMixTwoTrainingData.__new__(SnvMixTwoTrainingData)
#    
#    l = data_struct.depth.A + data_struct.depth.B
#    
#    data.depth = l
#    
#    data.labels = < int *> malloc(l * sizeof(int))
#    data.q = < double *> malloc(l * sizeof(double))
#    data.r = < double *> malloc(l * sizeof(double))
#    
#    i = 0
#    
#    for read_index in range(data.depth.A):
#        data.labels[i] = 1
#        data.q[i] = get_phred_qual_to_prob(data.base_quals.A[read_index])
#        data.r[i] = get_phred_qual_to_prob(data.map_quals.A[read_index])
#        
#        i += 1
#    
#    for read_index in range(data.depth.B):
#        data.labels[i] = 1
#        
#        temp_q = get_phred_qual_to_prob(data.base_quals.B[read_index])
#        data.q[i] = (1 - q) / 3
#                
#        data.r[i] = get_phred_qual_to_prob(data.map_quals.B[read_index])
#        
#        i += 1
#    
#    return data

cdef class SnvMixTrainer(Trainer):
    def train(self, Counter counter, init_params, priors, sub_sample_fraction=0.01):
        sample_data = self._load_data_set(counter, sub_sample_fraction)
        
        print "training"
        
        parameters = self._train(sample_data, init_params, priors)
        
        return parameters
    
    cdef _train(self, list sample_data, SnvMixParameters init_params, SnvMixPriors priors):
        pass

    cdef snv_mix_params_struct _do_em(self,
                                      list data,
                                      snv_mix_params_struct init_params,
                                      snv_mix_priors_struct priors):
        cdef bint converged
        cdef int iter
        cdef double lb
        cdef list lower_bounds
        cdef snv_mix_params_struct params
        cdef snv_mix_ess_struct ess
        
        iter = 0
        converged = 0
        lower_bounds = [FLOAT_INFN]
        
        params = init_params
        
        lb = self._get_lower_bound(data, params, priors)        
        lower_bounds.append(lb)
                
        converged = self._check_convergence(lower_bounds, iter)
        
        while not converged:
            ess = self._do_e_step(data, params)
            params = self._do_m_step(ess, priors)
            
            lb = self._get_lower_bound(data, params, priors)        
            lower_bounds.append(lb)
            
            iter += 1
            
            converged = self._check_convergence(lower_bounds, iter)
            
            print iter, lb
            print "mu : ", params.mu[0][0], params.mu[1][0], params.mu[2][0]
            print "pi : ", params.pi[0], params.pi[1], params.pi[2]
        
        return params
    
    cdef snv_mix_ess_struct _do_e_step(self,
                                       list data,
                                       snv_mix_params_struct params):
        cdef int i, g
        cdef snv_mix_ess_struct ess
        cdef double * resp
        ess = make_snv_mix_ess_struct()
    
        for pos_data in data:
            resp = self._get_resp(pos_data, params)
            
            ess = self._update_ess(ess, pos_data, resp)
            
            free(resp)
        
        return ess

    cdef double * _get_resp(self, SnvMixTrainingData data, snv_mix_params_struct params):
        pass
    
    cdef snv_mix_ess_struct _update_ess(self, snv_mix_ess_struct ess, SnvMixTrainingData data, double * resp):
        pass
    
    cdef snv_mix_params_struct _do_m_step(self, snv_mix_ess_struct ess, snv_mix_priors_struct priors):
        cdef int g
        cdef double alpha, beta, pi, denom
        cdef snv_mix_params_struct params
    
        for g in range(NUM_GENOTYPES):
            alpha = ess.a[g] + priors.mu[g][0] - 1
            beta = ess.b[g] + priors.mu[g][1] - 1
            denom = alpha + beta
            
            params.mu[g][0] = alpha / denom
            params.mu[g][1] = 1 - params.mu[g][0]
        
        denom = 0
        for g in range(NUM_GENOTYPES):
            pi = ess.n[g] + priors.pi[g] - 1
            denom += pi
        
        for g in range(NUM_GENOTYPES):
            pi = ess.n[g] + priors.pi[g] - 1
            
            params.pi[g] = pi / denom
        
        return params

    cdef double _get_lower_bound(self, list data, snv_mix_params_struct params, snv_mix_priors_struct priors):
        cdef int g
        cdef double ll, pos_likelihod
        
        ll = 0
        
        for pos_data in data:
            pos_likelihood = self._get_pos_likelihood(pos_data, params)

            # Guard against numerical issues associated with highly unlikely positions.
            if pos_likelihood == 0:
                pos_likelihood = EPS
            
            ll += log(pos_likelihood)
        
        for g in range(NUM_GENOTYPES):
            ll += dirichlet_log_likelihood(params.mu[g], priors.mu[g], NUM_BASES)
        
        ll += dirichlet_log_likelihood(params.pi, priors.pi, NUM_GENOTYPES)
        
        return ll

    cdef _get_pos_likelihood(self, SnvMixTrainingData data, snv_mix_params_struct params):
        pass
    
    cdef bint _check_convergence(self, lower_bounds, iter):
        cdef double rel_change
        
        rel_change = (lower_bounds[-1] - lower_bounds[-2]) / abs(< double > lower_bounds[-2])
    
        if rel_change < 0:
            print "Lower bound decreased exiting."
            return 1
        elif rel_change < 1e-6:
            print "Converged"
            return 1
        elif iter >= 100:
            print "Maximum number of iters exceeded exiting."
            return 1
        else:
            return 0

cdef class SnvMixOneTrainer(SnvMixTrainer):    
    cdef _train(self, list sample_data, SnvMixParameters init_params, SnvMixPriors priors):
        cdef list normal_counts = []
        cdef list tumour_counts = []
        cdef snv_mix_params_struct normal_params, tumour_params
        cdef JointBinaryCounterRow row
        
        for row in sample_data:
            normal_counts.append(makeSnvMixOneTrainingData(row._normal_counts))
            tumour_counts.append(makeSnvMixOneTrainingData(row._tumour_counts))
    
        normal_params = self._do_em(normal_counts, init_params._normal, priors._normal)
        tumour_params = self._do_em(tumour_counts, init_params._tumour, priors._tumour)
        
        return makeSnvMixParameters(normal_params, tumour_params)
    
    cdef double * _get_resp(self, SnvMixTrainingData data, snv_mix_params_struct params):
        cdef int g
        cdef double ll[NUM_GENOTYPES]
                
        for g in range(NUM_GENOTYPES):
            ll[g] = data.component_log_likelihood(params.mu[g])
            
        resp = mixture_posterior(ll, params.pi, NUM_BASES) 
        
        return resp
    
    cdef snv_mix_ess_struct _update_ess(self, snv_mix_ess_struct ess, SnvMixTrainingData data, double * resp):
        for g in range(NUM_GENOTYPES):
            ess.n[g] += resp[g]
            ess.a[g] += (< SnvMixOneTrainingData > data).counts[0] * resp[g]
            ess.b[g] += (< SnvMixOneTrainingData > data).counts[1] * resp[g]
        
        return ess
    
    cdef _get_pos_likelihood(self, SnvMixTrainingData data, snv_mix_params_struct params):
        cdef int g
        cdef double pos_likelihood, density
        
        for g in range(NUM_GENOTYPES):
            density = data.component_log_likelihood(params.mu[g])
            
            pos_likelihood += exp(log(params.pi[g]) + density)
        
        return pos_likelihood
        

#cdef class SnvMixTwoTrainer(AbstractSnvMixTrainer):
#    cdef _train(self, list sample_data, SnvMixParameters init_params, SnvMixPriors priors):
#        cdef list normal_data
#        cdef list tumour_data
#        cdef snv_mix_params_struct normal_params, tumour_params
#        cdef JointBinaryQualityCounterRow row
#        
#        for row in sample_data:
#            normal_counts.append(makeSnvMixTwoTrainingData(row._normal_data))
#            tumour_counts.append(makeSnvMixTwoTrainingData(row._tumour_data))
#            
#        normal_params = self._do_em(normal_data, init_params._normal, priors._normal)
#        tumour_params = self._do_em(tumour_data, init_params._tumour, priors._tumour)
#
#        return makeSnvMixParameters(normal_params, tumour_params)
#
#    cdef double * _get_resp(self, SnvMixTwoTrainingData data, snv_mix_params_struct params)):
#        for i in range(data.depth):
#            if data.labels[i] == 1:
#                likelihood += self._get_match_likelihood(data.q[i], data.r[i], params.mu)
#            elif data.labels[i] == 0:
#                likelihood += self._get_mismatch_likelihood(data.q[i], data.r[i], params.mu)
#    
#    cdef void _update_ess(snv_mix_ess_struct ess, SnvMixOneTrainingData data, double * resp):
#        for g in range(NUM_GENOTYPES):
#            ess.a[g] = resp[g][1][0] + resp[g][1][1]
#            ess.b[g] = resp[g][0][0] + resp[g][0][1]
#            ess.n[g] = ess.a[g] + ess.b[g]
#
#    cdef double _get_pos_likelihood(self, SnvMixTwoTrainingData data, snv_mix_params_struct params):
#        cdef int i
#        cdef double likelihood
#        
#        likelihood = 0
#        
#        for i in range(data.depth):
#            if data.labels[i] == 1:
#                likelihood += self._get_match_likelihood(data.q[i], data.r[i], params.mu)
#            elif data.labels[i] == 0:
#                likelihood += self._get_mismatch_likelihood(data.q[i], data.r[i], params.mu)
#        
#        likelihood *= p
#        
#        return likelihood
#
##=======================================================================================================================
## SNVMix2 Code
##=======================================================================================================================
#cdef double get_snv_mix_2_position_likelihood(base_map_qualities_struct data, snv_mix_params_struct params):
#    cdef int read_index
#    cdef double q, r, likelihood
#    cdef double read_resp[NUM_GENOTYPES][2][2]
#    
#    likelihood = 0
#    
#    for read_index in range(data.depth.A):
#        q = get_phred_qual_to_prob(data.base_quals.A[read_index])
#        
#        r = get_phred_qual_to_prob(data.map_quals.A[read_index])
#        
#        get_snv_mix_2_read_resp(q, r, params.mu, read_resp)
#        
#        likelihood += sum_snv_mix_2_resp(read_resp, params.pi)
#    
#    for read_index in range(data.depth.B):
#        q = get_phred_qual_to_prob(data.base_quals.B[read_index])
#        q = (1 - q) / 3
#                
#        r = get_phred_qual_to_prob(data.map_quals.B[read_index])
#        
#        get_snv_mix_2_read_resp(q, r, params.mu, read_resp)
#        
#        likelihood += sum_snv_mix_2_resp(read_resp, params.pi)
#        
#    return likelihood
#
#cdef void get_snv_mix_2_position_resp(base_map_qualities_struct data,
#                                      double mu[NUM_GENOTYPES][2],
#                                      double resp[NUM_GENOTYPES][2][2]):
#    '''
#    Return class log_likelihoods under SNVMix2 model with parameters mu.
#    
#    Allocates log_likelihood which will need to be freed by caller.
#    '''
#    cdef int read_index
#    cdef double q, r
#    cdef double read_resp[NUM_GENOTYPES][2][2]
#    
#    for read_index in range(data.depth.A):
#        q = get_phred_qual_to_prob(data.base_quals.A[read_index])
#        
#        r = get_phred_qual_to_prob(data.map_quals.A[read_index])
#        
#        get_snv_mix_2_read_resp(q, r, mu, read_resp)
#        
#        add_snv_mix_2_resp(resp, read_resp)
#    
#    for read_index in range(data.depth.B):
#        q = get_phred_qual_to_prob(data.base_quals.B[read_index])
#        q = (1 - q) / 3
#                
#        r = get_phred_qual_to_prob(data.map_quals.B[read_index])
#        
#        get_snv_mix_2_read_resp(q, r, mu, read_resp)
#        
#        add_snv_mix_2_resp(resp, read_resp)
#
#cdef double get_phred_qual_to_prob(int qual):
#    cdef double base, exp, prob
#    
#    exp = -1 * (< double > qual) / 10
#    base = 10
#    
#    prob = 1 - pow(base, exp)
#
#    return prob
#
#cdef void get_snv_mix_2_read_resp(double q, double r, double mu[NUM_GENOTYPES][2], double resp[NUM_GENOTYPES][2][2]):
#    cdef int a, g, z
#    cdef double norm_const
#    
#    norm_const = 0
#    for g in range(NUM_GENOTYPES):
#        for a in range(2):
#            for z in range(2):
#                resp[g][a][z] = compute_snv_mix_2_conditional(q, r, mu[g][0], a, z)
#                
#                norm_const += resp[g][a][z]
#     
#    for g in range(NUM_GENOTYPES):
#        for a in range(2):
#            for z in range(2):
#                resp[g][a][z] = resp[g][a][z] / norm_const
#
#cdef compute_snv_mix_2_conditional(double q, double r, double mu, int a, int z):
#    if a == 0 and z == 0:
#        return 0.5 * (1 - r) * (1 - mu)
#    elif a == 0 and z == 1:
#        return (1 - q) * r * (1 - mu)
#    elif a == 1 and z == 0:
#        return 0.5 * (1 - r) * mu
#    else:
#        return q * r * mu

#=======================================================================================================================
# Helper functions
#=======================================================================================================================
cdef snv_mix_ess_struct make_snv_mix_ess_struct():
    cdef int g
    cdef snv_mix_ess_struct ess
    
    for g in range(NUM_GENOTYPES):
        ess.n[g] = 0
        ess.a[g] = 0
        ess.b[g] = 0
    
    return ess
#
#cdef void init_snv_mix_2_resp(double resp[NUM_GENOTYPES][2][2]):
#    cdef int a, g, z 
#
#    for g in range(NUM_GENOTYPES):
#        for a in range(2):
#            for z in range(2):
#                resp[g][a][z] = 0
#    
#cdef void add_snv_mix_2_resp(double result_resp[NUM_GENOTYPES][2][2], double other_resp[NUM_GENOTYPES][2][2]):
#    for g in range(NUM_GENOTYPES):
#        for a in range(2):
#            for z in range(2):
#                result_resp[g][a][z] += other_resp[g][a][z]
#
#cdef double sum_snv_mix_2_resp(double resp[NUM_GENOTYPES][2][2], double pi[NUM_GENOTYPES]):
#    cdef double result
#    
#    result = 0
#    
#    for g in range(NUM_GENOTYPES):
#        for a in range(2):
#            for z in range(2):
#                result += pi[g] * resp[g][a][z]
#    
#    return result
    
    
