package LucyX::Suggester;
use warnings;
use strict;
use Carp;
use Data::Dump qw( dump );
use Search::Tools;
use Lucy;

our $VERSION = '0.001';

=head1 NAME

LucyX::Suggester - suggest terms for Apache Lucy search

=head1 SYNOPSIS

 use LucyX::Suggester;
 my $suggester = LucyX::Suggester->new(
   fields => [qw( foo bar )],
   indexes => $list_of_indexes,
 );
 my $suggestions = $suggester->suggest('quiK brwn fx');

=head1 DESCRIPTION

Inspired by the Solr Suggester feature, LucyX::Suggester
will return a list of suggested terms based on
actual terms in the specified index(es). Spellchecking
on query terms is performed with Search::Tools::SpellCheck,
which uses Text::Aspell.

=head1 METHODS

=head2 new( I<params> )

Returns a new Suggester object. Supported I<params> include:

=over

=item fields I<arrayref>

List of fields to limit Lexicon scans to.

=item indexes I<arrayref>

List of indexes to search within.

=back

=cut

sub new {
    my $class   = shift;
    my %args    = @_;
    my $fields  = delete $args{fields} || [];
    my $indexes = delete $args{indexes} or croak "indexes required";
    if (%args) {
        croak "Too many arguments to new(): " . dump( \%args );
    }
    if ( ref $indexes ne 'ARRAY' ) {
        croak "indexes must be an ARRAY ref";
    }
    return bless( { fields => $fields, indexes => $indexes }, $class );
}

=head2 suggest( I<query> )

Returns arrayref of terms that match I<query>.

=cut

sub suggest {
    my $self  = shift;
    my $query = shift;
    croak "query required" unless defined $query;
    my $qparser      = Search::Tools->parser();
    my $spellchecker = Search::Tools->spellcheck( query_parser => $qparser, );
    my $suggestions  = $spellchecker->suggest($query);
    my %terms;
    for my $s (@$suggestions) {

        if ( !$s->{suggestions} ) {
            $terms{ $s->{word} }++;
        }
        else {
            for my $suggest ( @{ $s->{suggestions} } ) {
                $terms{$suggest}++;
            }
        }
    }

    # must analyze each query term and suggestion
    # per-field, which we cache for performance
    my %analyzed;

    # suggestions
    my %matches;

    my @my_fields = @{ $self->{fields} };

    for my $invindex ( @{ $self->{indexes} } ) {
        my $reader = Lucy::Index::IndexReader->open( index => $invindex );
        my $schema = $reader->get_schema();
        my $fields;
        if (@my_fields) {
            $fields = \@my_fields;
        }
        else {
            $fields = $schema->all_fields();
        }
        my $seg_readers = $reader->seg_readers;
        for my $seg_reader (@$seg_readers) {
            my $lex_reader
                = $seg_reader->obtain('Lucy::Index::LexiconReader');
            for my $field (@$fields) {
                $self->_analyze_terms( $schema, $field, \%analyzed, \%terms );
                my $lexicon = $lex_reader->lexicon( field => $field );
                while ( $lexicon && $lexicon->next ) {
                    my $term = $lexicon->get_term;

                    # TODO linear scan is inefficient
                    # TODO phrases
                    # TODO better weighting than simple freq
                    if ( grep { $term =~ m/^\Q$_/ } keys %terms ) {
                        $matches{$term} += $lex_reader->doc_freq(
                            field => $field,
                            term  => $term
                        );
                    }
                }
            }
        }
    }

    return [ sort { $matches{$b} <=> $matches{$a} } keys %matches ];
}

sub _analyze_terms {
    my ( $self, $schema, $field, $analyzed, $terms ) = @_;

    #warn "field=$field";
    return if exists $analyzed->{$field};
    my $analyzer = $schema->fetch_analyzer($field);
    for my $t ( keys %$terms ) {
        my $baked = $analyzer ? $analyzer->split($t) : $t;
        $analyzed->{$field}->{$baked} = $t;
    }
}

1;

__END__

=head1 AUTHOR

Peter Karman, C<< <karman at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-lucyx-suggester at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=LucyX-Suggester>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc LucyX::Suggester


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=LucyX-Suggester>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/LucyX-Suggester>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/LucyX-Suggester>

=item * Search CPAN

L<http://search.cpan.org/dist/LucyX-Suggester/>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2012 Peter Karman.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut
