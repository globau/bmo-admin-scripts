#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use strict;
use warnings;

use Cwd qw(abs_path);
use FindBin qw($RealBin);
use File::Basename;
use HTTP::Cookies;
use SOAP::Lite;
use XMLRPC::Lite;

use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Sortkeys = 1;

use constant USERNAME   => 'glob@example.com';
use constant PASSWORD   => 'secret';
use constant URL        => 'http://bz/%s/xmlrpc.cgi';
use constant PRETTY_XML => 0;
my $rpc = {};

my ($result, $id);

$result = bugzilla(
    'User.login', {
        login    => USERNAME,
        password => PASSWORD,
        remember => 1,
    });

$result = bugzilla(
    'Bug.get', {
        ids => [ 35 ],
    }
);

#
# helpers
#

sub _debug_transport {
    my $r = shift;
    (my $content = $r->as_string) =~ s/\n*$/\n/;
    if (PRETTY_XML) {
        my ($header, $body) = $content =~ /^(.+\n\n)(.+)$/s;
        eval {
            eval 'use XML::LibXML';
            $content = $header . XML::LibXML->new->load_xml(string => $body)->toString(1);
        };
    }
    if ($r->isa('HTTP::Request')) {
        print">>>\n$content>>>\n";
    } elsif ($r->isa('HTTP::Response')) {
        print"<<<\n$content<<<\n";
    } else {
        die;
    }
    return undef;
}

sub bugzilla {
    my ($method, $params) = @_;
    my $soapresult;

    $rpc->{cookie_jar} //= HTTP::Cookies->new( ignore_discard => 1 );
    if (!$rpc->{proxy}) {
        my $path = $RealBin;
        while ($path ne '' && !-e "$path/localconfig") {
            print "($path)\n";
            $path = abs_path("$path/..");
        }
        $path ||= 'unknown';
        $rpc->{proxy} = XMLRPC::Lite->proxy(
            sprintf(URL, basename($path)),
            cookie_jar => $rpc->{cookie_jar},
        );
        foreach my $handler (qw( request_send response_done )) {
            $rpc->{proxy}->transport->set_my_handler( $handler => \&_debug_transport );
        }
    }
    $params->{token} = $rpc->{token}
        if $rpc->{token};

    eval {
        $soapresult = $rpc->{proxy}->call($method, $params);
        if ($soapresult->fault) {
            my ($package, $filename, $line) = caller;
            die $soapresult->faultcode . ' ' . $soapresult->faultstring .
                " in SOAP call near $filename line $line.\n";
        }
    };
    if ($@) {
        print $@;
        exit;
    }
    $rpc->{token} = $soapresult->result->{token}
        if $method eq 'User.login';
    return $soapresult->result;
}
