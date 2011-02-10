'''
Created on 2011-02-03

@author: Andrew Roth
'''
import math
import random

import numpy as np

from joint_snv_mix import constants
from joint_snv_mix.classification.data import IndependentData, JointData, MultinomialData
from joint_snv_mix.classification.models import IndependenBetaBinomialModel, IndependentBinomialModel, JointBinomialModel, JointBetaBinomialModel, JointMultinomialModel
from joint_snv_mix.classification.parameter_parsers import IndependentBinomialParameterParser, IndependentBetaBinomialParameterParser, JointBinomialParameterParser, JointBetaBinomialParameterParser, JointMultinomialParameterParser
from joint_snv_mix.classification.prior_parsers import IndependentBetaBinomialPriorParser, IndependentBinomialPriorParser, JointBinomialPriorParser, JointBetaBinomialPriorParser, JointMultinomialPriorParser
from joint_snv_mix.file_formats.jcnt import JointCountsReader
from joint_snv_mix.file_formats.jmm import JointMultiMixWriter
from joint_snv_mix.file_formats.jsm import JointSnvMixWriter
from joint_snv_mix.file_formats.mcnt import MultinomialCountsReader
from joint_snv_mix.classification.fisher_classifier import FisherModel
import csv


def run_classifier( args ):
    if args.priors_file is None:
        args.train = False
    else:
        args.train = True
    
    if args.model == "independent":
        if args.density == "binomial":
            runner = IndependentBinomialRunner()
        elif args.density == "beta_binomial":
            runner = IndependentBetaBinomialRunner()
            
    elif args.model == "joint":
        if args.density == "binomial":
            runner = JointBinomialRunner()
        elif args.density == "beta_binomial":
            runner = JointBetaBinomialRunner()
        elif args.density == "multinomial":
            runner = JointMultinomialRunner()

    elif args.model == "chromosome":
        if args.density == "binomial":
            runner = ChromosomeBinomialRunner()
        elif args.density == "beta_binomial":
            runner = ChromosomeBetaBinomialRunner()
        elif args.density == "multinomial":
            runner = ChromosomeMultinomialRunner()
            
    elif args.model == "fisher":
        runner = FisherTestRunner()

    runner.run( args )

#=======================================================================================================================
# Classes
#=======================================================================================================================
class ModelRunner( object ):
    def run( self, args ):        
        # Load parameters by training or from file.
        if args.train:
            self._train( args )
        else:
            self._load_parameters( args )
        
        self._write_parameters()
        
        self._classify( args )
                            
        self.reader.close()
        self.writer.close()
    
    def _classify( self, args ):
        chr_list = self.reader.get_chr_list()
        
        for chr_name in sorted( chr_list ):
            self._classify_chromosome( chr_name )
            
    def _write_parameters( self ):
        self.writer.write_parameters( self.parameters )
        
    def _write_priors( self ):
        self.writer.write_priors( self.priors )
            
    def _subsample( self, sample_size ):
        chr_list = self.reader.get_chr_list()
        
        sample = []
        
        nrows = self.reader.get_data_set_size()
        
        for chr_name in chr_list:
            chr_size = self.reader.get_chr_size( chr_name=chr_name )
            
            chr_sample_size = math.ceil( float( chr_size ) / nrows * sample_size )
            
            chr_sample_size = int( chr_sample_size )
            
            chr_sample_size = min( chr_size, chr_sample_size )
            
            chr_sample_indices = random.sample( xrange( chr_size ), chr_sample_size )
            
            chr_counts = self.reader.get_counts( chr_name )
            
            chr_sample = chr_counts[chr_sample_indices]
            
            sample.append( chr_sample )
            
        sample = np.vstack( sample )
        
        return sample

#=======================================================================================================================
# Independent Models
#=======================================================================================================================
class IndependentModelRunner( ModelRunner ):                
    def _train( self, args ):
        if args.subsample_size > 0:
            counts = self._subsample( args.subsample_size )
        else:
            counts = self.reader.get_counts()
                   
        self.priors_parser.load_from_file( args.priors_file )
        self.priors = self.priors_parser.to_dict()
        
        self._write_priors()
        
        self.parameters = {}
        
        for genome in constants.genomes:
            data = IndependentData( counts, genome )
            
            self.parameters[genome] = self.model.train( data, self.priors[genome],
                                                        args.max_iters, args.convergence_threshold )
                                    
    def _classify_chromosome( self, chr_name ):
        counts = self.reader.get_counts( chr_name )
        jcnt_rows = self.reader.get_rows( chr_name )
        
        end = self.reader.get_chr_size( chr_name )

        n = int( 1e5 )
        start = 0
        stop = min( n, end )
        

        while start < end:
            sub_counts = counts[start:stop]
            sub_rows = jcnt_rows[start:stop]
            
            indep_resp = {}
            
            for genome in constants.genomes:                          
                data = IndependentData( sub_counts, genome )            
                
                indep_resp[genome] = self.model.classify( data, self.parameters[genome] )
            
            joint_resp = self._get_joint_responsibilities( indep_resp )
        
            self.writer.write_data( chr_name, sub_rows, joint_resp )
            
            start = stop
            stop = min( stop + n, end )
            
    def _get_joint_responsibilities( self, resp ):
        normal_resp = np.log( resp['normal'] )
        tumour_resp = np.log( resp['tumour'] )
        
        n = normal_resp.shape[0]
        
        nclass_normal = normal_resp.shape[1] 
        
        column_shape = ( n, 1 )
        
        log_resp = []
        
        for i in range( nclass_normal ): 
            log_resp.append( normal_resp[:, i].reshape( column_shape ) + tumour_resp )
        
        log_resp = np.hstack( log_resp )
        
        resp = np.exp( log_resp )
        
        return resp

class IndependentBinomialRunner( IndependentModelRunner ):
    def __init__( self ):
        self.model = IndependentBinomialModel()
        self.priors_parser = IndependentBinomialPriorParser()
        self.parameter_parser = IndependentBinomialParameterParser()

class IndependentBetaBinomialRunner( IndependentModelRunner ):
    def __init__( self ):
        self.model = IndependenBetaBinomialModel()
        self.priors_parser = IndependentBetaBinomialPriorParser()
        self.parameter_parser = IndependentBetaBinomialParameterParser()
        
#=======================================================================================================================
# Joint Models
#=======================================================================================================================
class JointModelRunner( ModelRunner ):
    def run( self, args ):
        self.reader = JointCountsReader( args.jcnt_file_name )
        self.writer = JointSnvMixWriter( args.jsm_file_name )
        
        ModelRunner.run( self, args )
                    
    def _train( self, args ):        
        if args.subsample_size > 0:
            counts = self._subsample( args.subsample_size )
        else:
            counts = self.reader.get_counts()
                   
        self.priors_parser.load_from_file( args.priors_file )
        self.priors = self.priors_parser.to_dict()
        
        self._write_priors()
        
        data = JointData( counts )
        
        self.parameters = self.model.train( data, self.priors,
                                            args.max_iters, args.convergence_threshold )

    def _classify_chromosome( self, chr_name ):
        counts = self.reader.get_counts( chr_name )
        jcnt_rows = self.reader.get_rows( chr_name )
        
        end = self.reader.get_chr_size( chr_name )

        n = int( 1e5 )
        start = 0
        stop = min( n, end )
        

        while start < end:
            sub_counts = counts[start:stop]
            sub_rows = jcnt_rows[start:stop]
                              
            data = JointData( sub_counts )            
                
            resp = self.model.classify( data, self.parameters )
        
            self.writer.write_data( chr_name, sub_rows, resp )
            
            start = stop
            stop = min( stop + n, end )
    
class JointBinomialRunner( JointModelRunner ):
    def __init__( self ):
        self.model = JointBinomialModel()
        self.priors_parser = JointBinomialPriorParser()
        self.parameter_parser = JointBinomialParameterParser()

class JointBetaBinomialRunner( JointModelRunner ):
    def __init__( self ):
        self.model = JointBetaBinomialModel()
        self.priors_parser = JointBetaBinomialPriorParser()
        self.parameter_parser = JointBetaBinomialParameterParser()
        
#=======================================================================================================================
# Multinomial
#=======================================================================================================================
class MultinomialModelRunner( ModelRunner ):
    def run( self, args ):
        self.reader = MultinomialCountsReader( args.jcnt_file_name )
        self.writer = JointMultiMixWriter( args.jsm_file_name )
        
        ModelRunner.run( self, args )
               
    def _train( self, args ):
        if args.subsample_size > 0:
            counts = self._subsample( args.subsample_size )
        else:
            counts = self.reader.get_counts()
                   
        self.priors_parser.load_from_file( args.priors_file )
        self.priors = self.priors_parser.to_dict()
        
        self._write_priors()
        
        data = MultinomialData( counts )
        
        self.parameters = self.model.train( data, self.priors,
                                            args.max_iters, args.convergence_threshold )

    def _classify_chromosome( self, chr_name ):
        counts = self.reader.get_counts( chr_name )
        jcnt_rows = self.reader.get_rows( chr_name )
        
        end = self.reader.get_chr_size( chr_name )

        n = int( 1e5 )
        start = 0
        stop = min( n, end )
        

        while start < end:
            sub_counts = counts[start:stop]
            sub_rows = jcnt_rows[start:stop]
                              
            data = MultinomialData( sub_counts )            
                
            resp = self.model.classify( data, self.parameters )
        
            self.writer.write_data( chr_name, sub_rows, resp )
            
            start = stop
            stop = min( stop + n, end )
    
class JointMultinomialRunner( MultinomialModelRunner ):
    def __init__( self ):
        self.model = JointMultinomialModel()
        self.priors_parser = JointMultinomialPriorParser()
        self.parameter_parser = JointMultinomialParameterParser()
        
#=======================================================================================================================
# Chromosome Models
#=======================================================================================================================
class ChromosomeModelRunner( ModelRunner ):
    def run( self, args ):
        self.reader = JointCountsReader( args.jcnt_file_name )
        self.writer = JointSnvMixWriter( args.jsm_file_name )
        
        ModelRunner.run( self, args )
    
    def _train( self, args ):                   
        self.priors_parser.load_from_file( args.priors_file )
        self.priors = self.priors_parser.to_dict()
        
        self._write_priors()
        
        chr_list = self.reader.get_chr_list()
        
        self.parameters = {}
        
        for chr_name in sorted( chr_list ):
            print chr_name
            
            if args.subsample_size > 0:
                counts = self._chrom_subsample( chr_name, args.subsample_size )
            else:        
                counts = self.reader.get_counts( chr_name )
            
            data = self.data_class( counts )
            
            self.parameters[chr_name] = self.model.train( data, self.priors,
                                                          args.max_iters, args.convergence_threshold )
                        
    def _classify_chromosome( self, chr_name ):
        counts = self.reader.get_counts( chr_name )
        jcnt_rows = self.reader.get_rows( chr_name )
        
        end = self.reader.get_chr_size( chr_name )

        n = int( 1e5 )
        start = 0
        stop = min( n, end )
        

        while start < end:
            sub_counts = counts[start:stop]
            sub_rows = jcnt_rows[start:stop]
                              
            data = self.data_class( sub_counts )            
                
            resp = self.model.classify( data, self.parameters[chr_name] )
        
            self.writer.write_data( chr_name, sub_rows, resp )
            
            start = stop
            stop = min( stop + n, end )

    def _chrom_subsample( self, chr_name, sample_size ):
        chr_size = self.reader.get_chr_size( chr_name=chr_name )
        
        sample_size = min( chr_size, sample_size )
        
        chr_sample_indices = random.sample( xrange( chr_size ), sample_size )
        
        chr_counts = self.reader.get_counts( chr_name )
        
        chr_sample = chr_counts[chr_sample_indices]
        
        return chr_sample

class ChromosomeBinomialRunner( ChromosomeModelRunner ):
    def __init__( self ):
        self.data_class = JointData
        
        self.model = JointBinomialModel()
        self.priors_parser = JointBinomialPriorParser()
        self.parameter_parser = JointBinomialParameterParser()

class ChromosomeBetaBinomialRunner( ChromosomeModelRunner ):
    def __init__( self ):
        self.data_class = JointData
        
        self.model = JointBetaBinomialModel()
        self.priors_parser = JointBetaBinomialPriorParser()
        self.parameter_parser = JointBetaBinomialParameterParser()
        
class ChromosomeMultinomialRunner( ChromosomeModelRunner ):
    def __init__( self ):
        self.data_class = MultinomialData
        
        self.model = JointMultinomialModel()
        self.priors_parser = JointMultinomialPriorParser()
        self.parameter_parser = JointMultinomialParameterParser()
        
    def run( self, args ):
        self.reader = MultinomialCountsReader( args.jcnt_file_name )
        self.writer = JointMultiMixWriter( args.jsm_file_name )
        
        ModelRunner.run( self, args )

#=======================================================================================================================
# Fisher
#=======================================================================================================================
class FisherTestRunner( object ):
    def __init__( self ):
        self.model = FisherModel()
        self.data_class = JointData
        
        self.classes = ( 'Reference', 'Germline', 'Somatic', 'LOH', 'Unknown' )
    
    def run( self, args ):
        self.reader = JointCountsReader( args.jcnt_file_name )
        self.writer = csv.writer( open( args.jsm_file_name, 'w' ), delimiter='\t' )
        
        chr_list = self.reader.get_chr_list()
        
        for chr_name in sorted( chr_list ):
            self._classify_chromosome( chr_name )
                            
        self.reader.close()
        
    def _classify_chromosome( self, chr_name ):
        counts = self.reader.get_counts( chr_name )
        jcnt_rows = self.reader.get_rows( chr_name )
        
        end = self.reader.get_chr_size( chr_name )

        n = int( 1e5 )
        start = 0
        stop = min( n, end )
        
        while start < end:
            sub_counts = counts[start:stop]
            sub_rows = jcnt_rows[start:stop]
                              
            data = self.data_class( sub_counts )            
                
            labels = self.model.classify( data )
            
            self._write_rows( chr_name, sub_rows, labels )
        
            start = stop
            stop = min( stop + n, end )

    def _write_rows( self, chr_name, rows, labels ):
        for i, row in enumerate( rows ):
            out_row = [chr_name]
            out_row.extend( row )
            
            label = int( labels[i] )                 
            out_row.append( self.classes[label] )
            
            if label == 2:
                print out_row
            
            self.writer.writerow( out_row )
        
