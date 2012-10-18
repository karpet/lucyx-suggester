package LucyX::Suggester;
use warnings;
use strict;
use Carp;
use Data::Dump qw( dump );
use Search::Tools;
use Lucy;

our $VERSION = '0.003';

=head1 NAME

LucyX::Suggester - suggest terms for Apache Lucy search

=head1 SYNOPSIS

 use LucyX::Suggester;
 my $suggester = LucyX::Suggester->new(
   fields       => [qw( foo bar )],
   indexes      => $list_of_indexes,
   spellcheck   => $search_tools_spellcheck,
   limit        => 10,
 );
 my $suggestions = $suggester->suggest('quiK brwn fox');

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

=item spellcheck I<search_tools_spellcheck>

An instance of L<Search::Tools::SpellCheck>. Set
this to indicate custom values for language, dictionary,
and other params to L<Search::Tools::SpellCheck>.

=item limit I<n>

Maximum number of suggestions to return. Defaults to 10.

=back

=cut

sub new {
    my $class      = shift;
    my %args       = @_;
    my $fields     = delete $args{fields} || [];
    my $indexes    = delete $args{indexes} or croak "indexes required";
    my $spellcheck = delete $args{spellcheck};
    my $limit      = delete $args{limit} || 10;
    my $debug      = delete $args{debug} || $ENV{LUCYX_DEBUG} || 0;
    if (%args) {
        croak "Too many arguments to new(): " . dump( \%args );
    }
    if ( ref $indexes ne 'ARRAY' ) {
        croak "indexes must be an ARRAY ref";
    }
    return bless(
        {   fields     => $fields,
            indexes    => $indexes,
            spellcheck => $spellcheck,
            limit      => $limit,
            debug      => $debug,
        },
        $class
    );
}

=head2 suggest( I<query> )

Returns arrayref of terms that match I<query>.

=cut

#
# I tried re-writing this to use a PolySearcher
# instead, in order to preserve phrases, etc
# but it was up to 3x slower.
#

sub suggest {
    my $self     = shift;
    my $query    = shift;
    my $optimize = shift;
    $optimize = 1 unless defined $optimize;
    croak "query required" unless defined $query;

    my $debug = $self->{debug};

    my $spellchecker = $self->{spellcheck};
    if ( !$spellchecker ) {
        my $qparser = Search::Tools->parser(
            debug         => $debug,
        );
        $spellchecker = Search::Tools->spellcheck(
            debug        => $debug,
            query_parser => $qparser,
        );
    }

    my $suggestions = $spellchecker->suggest($query);
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

INDEX: for my $invindex ( @{ $self->{indexes} } ) {
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
    SEG: for my $seg_reader (@$seg_readers) {
            my $lex_reader
                = $seg_reader->obtain('Lucy::Index::LexiconReader');
        FIELD: for my $field (@$fields) {
                $self->_analyze_terms( $schema, $field, \%analyzed, \%terms );

                # sort in order to seek() below.
                my @to_check = sort keys %{ $analyzed{$field} };

                $debug and warn "$field=" . dump \@to_check;

                my $lexicon = $lex_reader->lexicon( field => $field );
                next FIELD unless $lexicon;

            CHECK: for my $check_term (@to_check) {

                    my ($check_initial) = ( $check_term =~ m/^(.)/ );
                    if ($optimize) {
                        $debug and warn "seek($check_term)";
                        $lexicon->seek($check_term);
                    }
                    else {
                        $lexicon->reset();
                    }

                TERM: while ( defined( my $term = $lexicon->get_term ) ) {

                        $debug and warn "$check_term -> $term";

                        if ($optimize) {
                            my ($initial) = ( $term =~ m/^(.)/ );
                            if ( $initial and $initial gt $check_initial ) {
                                $debug
                                    and warn
                                    "  reset: initial=$initial > check_initial=$check_initial";
                                $lexicon->reset();    # reset to start
                                next CHECK;
                            }
                        }

                        # TODO phrases?
                        # TODO better weighting than simple freq?

                        if ( $term =~ m/^\Q$check_term/ ) {
                            my $freq = $lex_reader->doc_freq(
                                field => $field,
                                term  => $term,
                            );
                            $debug and warn "ok term=$term [$freq]";
                            $matches{$term} += $freq;

                            # abort everything if we've hit our limit
                            if ( scalar( keys %matches ) >= $self->{limit} ) {
                                last INDEX;
                            }

                        }

                        last TERM unless $lexicon->next;

                    }
                }
            }
        }
    }

    $debug and warn "matches=" . dump( \%matches );

    return [
        sort { $matches{$b} <=> $matches{$a} || $a cmp $b }
            keys %matches
    ];
}

sub _analyze_terms {
    my ( $self, $schema, $field, $analyzed, $terms ) = @_;

    return if exists $analyzed->{$field};

    my $analyzer = $schema->fetch_analyzer($field);
    for my $t ( keys %$terms ) {
        my $baked = $analyzer ? $analyzer->split($t)->[0] : $t;
        next if length $baked == 1;    # too much noise
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
