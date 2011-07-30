'''
Created on 2011-06-21

@author: andrew
'''
import unittest

import pysam

from joint_snv_mix.counters.quality_counter import QualityCounter

class Test(unittest.TestCase):
    def get_counter(self, bam_file_name):
        bam_file = pysam.Samfile(bam_file_name, 'rb')        
        counter = QualityCounter(bam_file)

        return counter
    
    def test_iter_matches_row(self):
        counter = self.get_counter('data/plain.bam')        
        iter = counter.iter_ref('1')
        
        for row in iter:
            self.assertEqual(row.position, iter.position)
            self.assertEqual(row.ref, iter.ref)
    
    def test_str(self):
        counter = self.get_counter('data/plain.bam')
        iter = counter.iter_ref('1')
        
        row = iter.next()
        
        s = str(row)
        
        s_parts = s.split("\t")
        
        self.assertEqual(s_parts[0], '1')
        self.assertEqual(int(s_parts[1]), 33)
        
    
    def test_refs(self):
        reader = self.get_counter('data/plain.bam')
        
        self.assertTrue('1' in reader.refs)
        
    def test_iter_row(self):
        reader = self.get_counter('data/plain.bam')
        
        iter = reader.iter_ref('1')
        
        iter.next()
        iter.next()
        row_1 = iter.next()     
        self.assertEqual(row_1.position, 35)
        self.assertEqual(row_1.bases[0], 'C')
        self.assertEqual(row_1.base_quals[0], ord('<') - 33)
        self.assertEqual(row_1.map_quals[0], 20)
    
    def test_deletion_correct(self):
        reader = self.get_counter('data/deletion.bam')
        
        for row in reader.iter_ref('1'):
            if row.position == 34:
                self.assertEqual(row.depth, 0)
                
            if row.position == 35:
                self.assertEqual(row.bases[0], ('G'))
                self.assertEqual(row.bases[1], ('G'))
                self.assertEqual(row.bases[2], ('C'))

    def test_insertion_correct(self):
        reader = self.get_counter('data/insertion.bam')
        
        for row in reader.iter_ref('1'):
            if row.position == 34:
                self.assertEqual(row.bases[0], ('C'))
                self.assertEqual(row.bases[1], ('C'))
                                
            if row.position == 35:
                self.assertEqual(row.bases[0], ('T'))
                self.assertEqual(row.bases[1], ('T'))
                self.assertEqual(row.bases[2], ('C'))
        
if __name__ == "__main__":
    #import sys;sys.argv = ['', 'Test.testName']
    unittest.main()
