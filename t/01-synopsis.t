#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 5;
use FindBin;
use LucyX::Suggester;
use Data::Dump qw( dump );

my $idx      = "$FindBin::Bin/../index.swish";

# sorted by frequency, then alpha
my $expected = [qw( brawn quirk brown fox quick run )];
SKIP: {
    if ( !-d $idx ) {
        skip "create an index at $idx", 5;
    }

    ok( my $suggester = LucyX::Suggester->new(
            fields  => [ 'swishdefault', 'swishtitle' ],
            indexes => [$idx]
        ),
        "new Suggester"
    );

    ok( my $suggestions = $suggester->suggest('quiK brwn fx running'),
        "get suggestions" );

    dump($suggestions);

    is_deeply( $suggestions, $expected, "got suggestions" );

    ok( $suggestions = $suggester->suggest( 'quiK brwn fx running', 0 ),
        "suggest() with no optimize" );

    dump($suggestions);

    is_deeply( $suggestions, $expected, "got suggestions" );

}
