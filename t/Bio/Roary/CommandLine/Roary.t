#!/usr/bin/env perl
use Moose;
use Data::Dumper;
use File::Path qw( remove_tree);
use File::Which;
use File::Path qw(make_path);
use Cwd qw(abs_path getcwd); 
use File::Find::Rule;

#Test changes current working directory so relative paths can get out of sync
local $ENV{PERL5LIB} = join(':', ("$ENV{PERL5LIB}", abs_path('./lib'), abs_path('./t/lib')));
local $ENV{PATH} = join(':', ("$ENV{PATH}", abs_path('./bin')));

BEGIN { unshift( @INC, abs_path('./lib') ) }
BEGIN { unshift( @INC, abs_path('./t/lib') ) }
with 'TestHelper';

BEGIN {
    use Test::Most;
    use_ok('Bio::Roary::CommandLine::Roary');
    use_ok('Bio::Roary::CommandLine::CreatePanGenome');
    use Bio::Roary::SequenceLengths;
}
my $script_name = 'Bio::Roary::CommandLine::Roary';
my $cwd         = getcwd();

local $ENV{PATH} = "$ENV{PATH}:./bin";
my %scripts_and_expected_files;
system('touch empty_file');
cleanup_files();

%scripts_and_expected_files = (

    ' --dont_split_groups   t/data/query_1.gff t/data/query_2.gff t/data/query_5.gff    ' =>
      [ 'gene_presence_absence.csv', 't/data/overall_gene_presence_absence.csv' ],
    ' -j Local -t 1 --dont_split_groups   t/data/query_1.gff t/data/query_2.gff t/data/query_5.gff    ' =>
      [ 'gene_presence_absence.csv', 't/data/overall_gene_presence_absence.csv' ],
    ' -j Parallel  --dont_split_groups t/data/query_1.gff t/data/query_2.gff t/data/query_5.gff    ' =>
      [ 'gene_presence_absence.csv', 't/data/overall_gene_presence_absence.csv' ],
    ' -t 1 -j Parallel --dont_split_groups  t/data/query_1.gff t/data/query_2.gff t/data/query_5.gff    ' =>
      [ 'gene_presence_absence.csv', 't/data/overall_gene_presence_absence.csv' ],
    ' -j Local --dont_split_groups t/data/genbank_gbff/genbank1.gff t/data/genbank_gbff/genbank2.gff t/data/genbank_gbff/genbank3.gff' =>
      [ 'gene_presence_absence.csv', 't/data/genbank_gbff/genbank_gene_presence_absence.csv' ],
    '-h' => [ 'empty_file', 't/data/empty_file' ],
);

mock_execute_script_and_check_output_sorted( $script_name, \%scripts_and_expected_files, [ 0, 6, 7, 8, 9 ] );

cleanup_files();

%scripts_and_expected_files = (
    ' -j Local --dont_split_groups   t/data/query_1.gff t/data/query_2.gff t/data/query_5.gff ' =>
      [ 'clustered_proteins', 't/data/clustered_proteins_pan_genome' ],
    ' -j Parallel --dont_split_groups  t/data/query_1.gff t/data/query_2.gff t/data/query_5.gff ' =>
      [ 'clustered_proteins', 't/data/clustered_proteins_pan_genome' ],
);

mock_execute_script_and_check_output_sorted_groups( $script_name, \%scripts_and_expected_files, [ 0, 6, 7, 8, 9 ] );

# Make sure faa files are cleaned up automatically
ok( !( -e 'query_1.gff.proteome.faa' ), 'Check protein query_1.gff.proteome.faa is cleaned up' );
ok( !( -e 'query_2.gff.proteome.faa' ), 'Check protein query_2.gff.proteome.faa is cleaned up' );
ok( !( -e 'query_5.gff.proteome.faa' ), 'Check protein query_5.gff.proteome.faa is cleaned up' );

cleanup_files();

stderr_should_have($script_name,'-a', 'Looking for');

my $current_cwd = getcwd();
stderr_should_have($script_name,'-v --output_directory t/data/directory_which_doesnt_exist t/data/real_data_1.gff t/data/real_data_2.gff', 'Output directory created');
ok( ( -e 't/data/directory_which_doesnt_exist/clustered_proteins' ), 'pan genome files should be in directory' );
is(getcwd(),$current_cwd , 'current working directory should not have changed after script is finished'); 

SKIP:
{
    skip "prank not installed", 11 unless ( which('prank') );

    %scripts_and_expected_files =
      ( '-j Local --dont_delete_files --dont_split_groups  --output_multifasta_files t/data/real_data_1.gff t/data/real_data_2.gff' =>
          [ 'pan_genome_sequences/mdoH.fa.aln', 't/data/mdoH.fa.aln' ], );
    mock_execute_script_and_check_output( $script_name, \%scripts_and_expected_files );

    ok( -e 'core_gene_alignment.aln', 'Core gene alignment exists' );

    ok(
        my $seq_len = Bio::Roary::SequenceLengths->new(
            fasta_file => 'core_gene_alignment.aln',
        ),
        'Check size of the core_gene_alignment.aln init'
    );

    my @keys = keys %{ $seq_len->sequence_lengths };
    is( $seq_len->sequence_lengths->{ $keys[0] }, 64983, 'length of first sequence' );

    ok( -e 'accessory.tab' );
    ok( -e 'core_accessory.tab' );
    ok( -e 'number_of_conserved_genes.Rtab' );
    ok( -e 'number_of_genes_in_pan_genome.Rtab' );
    ok( -e 'number_of_new_genes.Rtab' );
    ok( -e 'number_of_unique_genes.Rtab' );
    ok( -e 'blast_identity_frequency.Rtab' );

    cleanup_files();
    %scripts_and_expected_files =
      (
'-j Local --output_multifasta_files t/data/core_alignment_gene_lookup/query_1.gff t/data/core_alignment_gene_lookup/query_2.gff t/data/core_alignment_gene_lookup/query_3.gff'
          => [ 'core_gene_alignment.aln', 't/data/core_alignment_gene_lookup/expected_core_gene_alignment.aln' ], );
    mock_execute_script_and_check_output( $script_name, \%scripts_and_expected_files );

    cleanup_files();
}

SKIP:
{
    skip "mafft not installed", 11 unless ( which('mafft') );
    %scripts_and_expected_files =
      ( '-j Local --dont_delete_files --dont_split_groups  --output_multifasta_files --mafft t/data/real_data_1.gff t/data/real_data_2.gff'
          => [ 'pan_genome_sequences/mdoH.fa.aln', 't/data/mdoH_mafft.fa.aln' ], );
    mock_execute_script_and_check_output( $script_name, \%scripts_and_expected_files );

    ok( -e 'core_gene_alignment.aln', 'Core gene alignment exists' );
}

SKIP:
{
	skip "extended tests not run",  40 unless ( defined($ENV{ROARY_FULL_TESTS}));

    %scripts_and_expected_files = (
        '-o some_different_output t/data/real_data_1.gff t/data/real_data_2.gff'    => [ 'some_different_output', 't/data/expected_some_different_output' ],
        '-o some_different_output -i 90 t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'some_different_output', 't/data/expected_some_different_output' ],
        '-o some_different_output --translation_table 1 t/data/real_data_1.gff t/data/real_data_2.gff' =>
          [ 'some_different_output', 't/data/expected_some_different_output' ],
    	'-p 2 -o some_different_output t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'some_different_output', 't/data/expected_some_different_output' ],
    	'-p 2 -i 90 t/data/real_data_1.gff t/data/real_data_2.gff'                    => [ 'clustered_proteins', 't/data/expected_some_different_output' ],
    	'-i 90 t/data/real_data_1.gff t/data/real_data_2.gff'                         => [ 'clustered_proteins', 't/data/expected_some_different_output' ],
    	'-p 2 --translation_table 1 t/data/real_data_1.gff t/data/real_data_2.gff'    => [ 'clustered_proteins', 't/data/expected_some_different_output' ],
    	);
    mock_execute_script_and_check_output_sorted( $script_name, \%scripts_and_expected_files, [ 0 ] );
    
    stderr_should_have($script_name,'-e --group_limit 10 t/data/real_data_1.gff t/data/real_data_2.gff', 'Exiting early because number of clusters is too high');
    stderr_should_have($script_name,'-p 2 --group_limit 10 -e t/data/real_data_1.gff t/data/real_data_2.gff', 'Exiting early because number of clusters is too high');
    stderr_should_have($script_name,'--core_definition 60 --group_limit 10 -e t/data/real_data_1.gff t/data/real_data_2.gff', 'Exiting early because number of clusters is too high');
    stderr_should_have($script_name,'--mafft --group_limit 10 -e t/data/real_data_1.gff t/data/real_data_2.gff', 'Exiting early because number of clusters is too high');
    stderr_should_have($script_name,'-o some_different_output --group_limit 10 -e t/data/real_data_1.gff t/data/real_data_2.gff', 'Exiting early because number of clusters is too high');
    stderr_should_have($script_name,'--translation_table 1 --group_limit 10 -e t/data/real_data_1.gff t/data/real_data_2.gff', 'Exiting early because number of clusters is too high');
    stderr_should_have($script_name,'--verbose_stats --group_limit 10 -e t/data/real_data_1.gff t/data/real_data_2.gff', 'Exiting early because number of clusters is too high');
    stderr_should_not_have($script_name,'-e --group_limit 10 t/data/real_data_1.gff t/data/real_data_2.gff', 'Cant access the multifasta base directory');
    stderr_should_have($script_name,'-v t/data/real_data_1.gff t/data/real_data_2.gff','Cleaning up files');
    stderr_should_have($script_name,'-p 2 -v t/data/real_data_1.gff t/data/real_data_2.gff','Cleaning up files');
    stderr_should_have($script_name,'--core_definition 60 -v t/data/real_data_1.gff t/data/real_data_2.gff','Cleaning up files');
    stderr_should_have($script_name,'-i 90 -v t/data/real_data_1.gff t/data/real_data_2.gff','Cleaning up files');
	stderr_should_have($script_name,'-i 30 t/data/real_data_1.gff t/data/real_data_2.gff','The percentage identity is too low');
    stderr_should_not_have($script_name,'--dont_delete_files -v t/data/real_data_1.gff t/data/real_data_2.gff','Cleaning up files');
    stderr_should_have($script_name,'-v --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff'   ,'Cleaning up files');
    stderr_should_have($script_name,'-v --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' ,'Cleaning up files');
    
    stderr_should_have($script_name,'--translation_table 1 -v t/data/real_data_1.gff t/data/real_data_2.gff' ,'Cleaning up files');
    stderr_should_have($script_name,'-e -v t/data/real_data_1.gff t/data/real_data_2.gff','Creating files with the nucleotide sequences for every cluster');
    
    SKIP:
    {
        skip "kraken not installed",        2 unless ( which('kraken') );
        skip "kraken-report not installed", 2 unless ( which('kraken-report') );
        stderr_should_not_have($script_name,'--group_limit 10 --qc t/data/real_data_1.gff t/data/real_data_2.gff', 'Exiting early because number of clusters is too high');
        stderr_should_have($script_name,'-v --qc t/data/real_data_1.gff t/data/real_data_2.gff' ,'Running Kraken on each input assembly');
    }
    
    %scripts_and_expected_files = (
        # output
        '-o some_different_output -e t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'core_gene_alignment.aln', 't/data/expected_real_data_core_gene_alignment.aln' ],
        '-o some_different_output -e --dont_delete_files t/data/real_data_1.gff t/data/real_data_2.gff' =>
          [ 'pan_genome_sequences/mdoH.fa.aln', 't/data/mdoH.fa.aln' ],
        '-o some_different_output --core_definition 60 t/data/real_data_1.gff t/data/real_data_2.gff' =>
          [ 'summary_statistics.txt', 't/data/expected_core_60_summary_statistics.txt' ],
        '-o some_different_output -e --mafft t/data/real_data_1.gff t/data/real_data_2.gff' =>
          [ 'core_gene_alignment.aln', 't/data/expected_mafft_real_data_core_gene_alignment.aln' ],
         # -e
        '-e -i 95.3 t/data/real_data_1.gff t/data/real_data_2.gff'                 => [ 'core_gene_alignment.aln', 't/data/expected_real_data_core_gene_alignment.aln' ],
        '-e --translation_table 1 t/data/real_data_1.gff t/data/real_data_2.gff'   => [ 'core_gene_alignment.aln', 't/data/expected_real_data_core_gene_alignment.aln' ],
        '-e -v t/data/real_data_1.gff t/data/real_data_2.gff'                      => [ 'core_gene_alignment.aln', 't/data/expected_real_data_core_gene_alignment.aln' ],
        '-e --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff'         => [ 'core_gene_alignment.aln', 't/data/expected_real_data_core_gene_alignment.aln' ],
        '-e --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'core_gene_alignment.aln', 't/data/expected_real_data_core_gene_alignment.aln' ],
        '-e --qc t/data/real_data_1.gff t/data/real_data_2.gff'                    => [ 'core_gene_alignment.aln', 't/data/expected_real_data_core_gene_alignment.aln' ],
    
    #    '-o some_different_output -v t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #    '-o some_different_output --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '-o some_different_output --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '-o some_different_output --qc t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #
    #    # single parameters
        '--core_definition 60 t/data/real_data_1.gff t/data/real_data_2.gff'    => [ 'summary_statistics.txt', 't/data/expected_core_60_summary_statistics.txt' ],
    #    '--translation_table 1 t/data/real_data_1.gff t/data/real_data_2.gff'   => [ 'empty_file', 't/data/empty_file' ],
    #    '--verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff'         => [ 'empty_file', 't/data/empty_file' ],
    #    '--group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #    '--qc t/data/real_data_1.gff t/data/real_data_2.gff'                    => [ 'empty_file', 't/data/empty_file' ],
    #
    #    # Parallel
        '-p 2 -e t/data/real_data_1.gff t/data/real_data_2.gff'                       => [ 'core_gene_alignment.aln', 't/data/expected_real_data_core_gene_alignment.aln' ],
        '-p 2 -e --dont_delete_files t/data/real_data_1.gff t/data/real_data_2.gff'   => [ 'pan_genome_sequences/mdoH.fa.aln', 't/data/mdoH.fa.aln' ],
        '-p 2 --core_definition 60 t/data/real_data_1.gff t/data/real_data_2.gff'     => [ 'summary_statistics.txt', 't/data/expected_core_60_summary_statistics.txt' ],
        '-p 2 -e --mafft t/data/real_data_1.gff t/data/real_data_2.gff'               => [ 'core_gene_alignment.aln', 't/data/expected_mafft_real_data_core_gene_alignment.aln' ],
    #    '-p 2 --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff'          => [ 'empty_file', 't/data/empty_file' ],
    #    '-p 2 --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff'  => [ 'empty_file', 't/data/empty_file' ],
    #    '-p 2 --qc t/data/real_data_1.gff t/data/real_data_2.gff'                     => [ 'empty_file', 't/data/empty_file' ],
    #
    #    # core definition
    #    '--core_definition 60 -e t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #    '--core_definition 60 -e --dont_delete_files t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--core_definition 60 -e --mafft t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #    '--core_definition 60 -i 90 t/data/real_data_1.gff t/data/real_data_2.gff'      => [ 'empty_file', 't/data/empty_file' ],
    #    '--core_definition 60 --translation_table 1 t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--core_definition 60 --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--core_definition 60 --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--core_definition 60 --qc t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #
    #    # mafft
    #    '--mafft -i 90 t/data/real_data_1.gff t/data/real_data_2.gff'                   => [ 'empty_file', 't/data/empty_file' ],
    #    '--mafft --translation_table 1 t/data/real_data_1.gff t/data/real_data_2.gff'   => [ 'empty_file', 't/data/empty_file' ],
    #    '--mafft --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff'         => [ 'empty_file', 't/data/empty_file' ],
    #    '--mafft --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #    '--mafft --qc t/data/real_data_1.gff t/data/real_data_2.gff'                    => [ 'empty_file', 't/data/empty_file' ],
    #
    #
    #    # dont_delete_files
    #    '--dont_delete_files -i 90 t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #    '--dont_delete_files --translation_table 1 t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    
    #    '--dont_delete_files --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--dont_delete_files --group_limit 10 -e t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--dont_delete_files --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--dont_delete_files --qc t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #
    #    # change identity
    #    '-i 90 --translation_table 1 t/data/real_data_1.gff t/data/real_data_2.gff'   => [ 'empty_file', 't/data/empty_file' ],
    
    #    '-i 90 --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff'         => [ 'empty_file', 't/data/empty_file' ],
    #    '-i 90 --group_limit 10 -e t/data/real_data_1.gff t/data/real_data_2.gff'     => [ 'empty_file', 't/data/empty_file' ],
    #    '-i 90 --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #    '-i 90 --qc t/data/real_data_1.gff t/data/real_data_2.gff'                    => [ 'empty_file', 't/data/empty_file' ],
    #
    #    # translation_table
    #    '--translation_table 1 --verbose_stats t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--translation_table 1 --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--translation_table 1 --qc t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #
    #
    #    # verbose stats
    #    '--verbose_stats --group_limit 100000 -e t/data/real_data_1.gff t/data/real_data_2.gff' =>
    #      [ 'empty_file', 't/data/empty_file' ],
    #    '--verbose_stats --qc t/data/real_data_1.gff t/data/real_data_2.gff' => [ 'empty_file', 't/data/empty_file' ],
    #
    );
    mock_execute_script_and_check_output( $script_name, \%scripts_and_expected_files );

}

cleanup_files();

done_testing();

sub cleanup_files {
    remove_tree('pan_genome_sequences');
    remove_tree('fixed_input_files');
	remove_tree('t/data/directory_which_doesnt_exist');
    remove_tree('locus_tags_gffs_output');
    unlink('_blast_results');
    unlink('_clustered');
    unlink('_clustered.bak.clstr');
    unlink('_clustered.clstr');
    unlink('_combined_files');
    unlink('_combined_files.groups');
    unlink('_fasta_files');
    unlink('_gff_files');
    unlink('_inflated_mcl_groups');
    unlink('_inflated_unsplit_mcl_groups');
    unlink('_labeled_mcl_groups');
    unlink('_uninflated_mcl_groups');
    unlink('accessory.header.embl');
    unlink('accessory.header.tab');
    unlink('accessory.tab');
    unlink('blast_identity_frequency.Rtab');
    unlink('clustered_proteins');
    unlink('core_accessory.header.embl');
    unlink('core_accessory.header.tab');
    unlink('core_accessory.tab');
    unlink('core_gene_alignment.aln');
    unlink('database_masking.asnb');
    unlink('example_1.faa.tmp.filtered.fa');
    unlink('example_2.faa.tmp.filtered.fa');
    unlink('example_3.faa.tmp.filtered.fa');
    unlink('gene_presence_absence.csv');
    unlink('number_of_conserved_genes.Rtab');
    unlink('number_of_genes_in_pan_genome.Rtab');
    unlink('number_of_new_genes.Rtab');
    unlink('number_of_unique_genes.Rtab');
    unlink('pan_genome.fa');
    unlink('query_1.gff.proteome.faa');
    unlink('query_2.gff.proteome.faa');
    unlink('query_3.gff.proteome.faa');
    unlink('query_5.gff.proteome.faa');
    unlink('real_data_1.gff.proteome.faa');
    unlink('real_data_2.gff.proteome.faa');
    unlink('pan_genome_reference.fa');
    unlink('accessory_graph.dot');
    unlink('core_accessory_graph.dot');
	unlink('some_different_output');
}
