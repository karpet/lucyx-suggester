#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 3;
use FindBin;
use LucyX::Suggester;

my $idx = "$FindBin::Bin/../index.swish";
SKIP: {
    if ( !-d $idx ) {
        skip "create an index at $idx", 3;
    }

    ok( my $suggester = LucyX::Suggester->new( indexes => [$idx] ),
        "new Suggester" );

    ok( my $suggestions = $suggester->suggest('quiK brwn fx'),
        "get suggestions" );

    is_deeply( $suggestions, [qw( fox brown quick )], "got suggestions" );

}
