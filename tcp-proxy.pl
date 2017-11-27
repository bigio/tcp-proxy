#!/usr/bin/perl

# BSD 2-Clause License
# 
# Copyright (c) 2017, Giovanni Bechis
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use warnings;
use strict;

use Getopt::Std;
use IO::Socket;
use IO::Select;

my %opts = ();

my $bind_port;
my $remote_port;
my $iosel = IO::Select->new;
my %socket_map;
my %ip_map;
my $max_conn;
my $max_ip_number;
my $start_ip;
my $destination;
my $local_addr;

my $debug = 1;

getopts('b:c:d:hi:p:s:', \%opts);

sub usage {
	print "Usage $0 [-bcdhips]\n";
	exit;
}

if ( ( defined $opts{'h'} ) || ( not defined $opts{'c'} and not defined $opts{'d'} and not defined $opts{'i'} and not defined $opts{'s'} ) ) {
	usage;
}

if ( defined $opts{'b'} ) {
        $bind_port = $opts{'b'};
} else {
	$bind_port = 8080;
}
if ( defined $opts{'c'} ) {
        $max_conn = $opts{'c'};
}
if ( defined $opts{'d'} ) {
        $destination = $opts{'d'};
}
if ( defined $opts{'i'} ) {
        $max_ip_number = $opts{'i'};
}
if ( defined $opts{'p'} ) {
        $remote_port = $opts{'p'};
} else {
	$remote_port = 25;
}
if ( defined $opts{'s'} ) {
        $start_ip = $opts{'s'};
}

sub add_to_ip($$)
{
  my( $ip, $add ) = @_;
  inet_ntoa pack( 'N', unpack('N',inet_aton $ip) + $add )
}

sub new_conn {
    my ($host, $port) = @_;
    for ( my $i = 1; $i < $max_ip_number; $i++ ) {
	$local_addr = add_to_ip($start_ip, $i);
	if ( not defined $ip_map{$local_addr} ) {
		$ip_map{$local_addr} = 0;
	}
	if ( $ip_map{$local_addr} < $max_conn ) {
		print "Connection from " . $local_addr . " nr: " . $ip_map{$local_addr} . "\n" if $debug;
		$ip_map{$local_addr}++;
    		return IO::Socket::INET->new(
			PeerAddr => $host,
			PeerPort => $port,
			LocalAddr => $local_addr
		) || die "Unable to connect to $host:$port: $!";
		
        }
    }
}

sub new_server {
    my ($host, $port) = @_;
    my $server = IO::Socket::INET->new(
        LocalAddr => $host,
        LocalPort => $port,
        ReuseAddr => 1,
        Listen    => 100
    ) || die "Unable to listen on $host:$port: $!";
}

sub new_connection {
    my $server = shift;
    my $client = $server->accept;
    my $client_ip = client_ip($client);

    print "Connection from $client_ip accepted.\n" if $debug;

    my $remote = new_conn($destination, $remote_port);
    $iosel->add($client);
    $iosel->add($remote);

    $socket_map{$client} = $remote;
    $socket_map{$remote} = $client;
}

sub close_connection {
    my $client = shift;
    my $client_ip = client_ip($client);
    my $remote = $socket_map{$client};
    
    $iosel->remove($client);
    $iosel->remove($remote);

    delete $socket_map{$client};
    delete $socket_map{$remote};

    $client->close;
    $remote->close;

    $ip_map{$client_ip}--;
    print "Connection from $client_ip closed.\n" if $debug;
}

sub client_ip {
    my $client = shift;
    return inet_ntoa($client->sockaddr);
}

print "Starting a server on 0.0.0.0:$bind_port\n";
my $server = new_server('0.0.0.0', $bind_port);
$iosel->add($server);

while (1) {
    for my $socket ($iosel->can_read) {
        if ($socket == $server) {
            new_connection($server);
        }
        else {
            next unless exists $socket_map{$socket};
            my $remote = $socket_map{$socket};
            my $buffer;
            my $read = $socket->sysread($buffer, 4096);
            if ($read) {
                $remote->syswrite($buffer);
            }
            else {
                close_connection($socket);
            }
        }
    }
}

