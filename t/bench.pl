#!/usr/bin/env perl
use strict;
use warnings;
use Benchmark qw(:all);
use LucyX::Suggester;

my $s = LucyX::Suggester->new( indexes => [@ARGV] );

cmpthese(
    100,
    {   'non' => sub {
            $s->suggest( 'quiK brwn fx running', 0 );
        },
        'optimized' => sub {
            $s->suggest( 'quiK brwn fx running', 1 );
        },
    }
);
