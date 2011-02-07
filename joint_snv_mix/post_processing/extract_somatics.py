import matplotlib
import csv
matplotlib.use( 'agg' )

import matplotlib.pyplot as plot

from joint_snv_mix.file_formats.jsm import JointSnvMixReader

import bisect

excluded_chrom = ['Y', 'MT']

fields = [
          'chrom',
          'position',
          'ref_base',
          'normal_base',
          'tumour_base',
          'normal_counts_a',
          'normal_counts_b',
          'tumour_counts_a',
          'tumour_counts_b',
          'somatic_prob'          
          ]

genotypes = ['aa', 'ab', 'bb']

for g_1 in genotypes:
    for g_2 in genotypes:
        prob_field = "_".join( ( 'p', g_1, g_2 ) )
        fields.append( prob_field )

def main( jsm_file_name, out_file_name ):
    rows = load_somatics( jsm_file_name )
    rows.reverse()

    writer = csv.DictWriter( open( out_file_name, 'w' ), fields, delimiter='\t' )

    writer.writeheader()
    writer.writerows( rows )


def load_somatics( jsm_file_name ):
    n = int( 1e5 )
    threshold = 1e-6

    reader = JointSnvMixReader( jsm_file_name )

    chr_list = reader.get_chr_list()

    scores = []
    rows = []

    for chr_name in sorted( chr_list ):
        if chr_name in excluded_chrom:
            continue
        
        print chr_name

        chr_rows = reader.get_rows( chr_name )

        for row in chr_rows:
            score = row['p_aa_ab'] + row['p_aa_bb']

            insert_position = bisect.bisect( scores, score )

            if insert_position > 0 or len( scores ) == 0:
                scores.insert( insert_position, score )
                
                row = format_rows( row, chr_name )
                
                rows.insert( insert_position, row )
            
                if scores[0] <= threshold or len( scores ) > n:
                    scores.pop( 0 )
                    rows.pop( 0 )

    reader.close()
    
    max_diff = 0
    index = 0
    
    for i in range( len( scores ) - 1 ):
        diff = scores[i + 1] - scores[i]
        
        if diff > max_diff:
            max_diff = diff
            index = i
            
    rows = rows[index:]

    return rows

def format_rows( row, chrom ):
    row = dict( zip( row.dtype.names, row.real ) )
    row['somatic_prob'] = row['p_aa_ab'] + row['p_aa_bb']
    row['chrom'] = chrom
    
    return row

if __name__ == "__main__":
    import sys
    
    jsm_file_name = sys.argv[1]
    
    out_file_name = sys.argv[2]
    
    main( jsm_file_name, out_file_name )
