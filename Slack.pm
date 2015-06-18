#!/opt/local/bin/perl
#
# Slack web API
# SSL errors require Crypt::SSLeay, so we include it here.
#
package Slack;
use warnings;
use strict;
use FindBin '$Bin';
use Fcntl;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use Net::SSL;

my $base_url = "https://slack.com/api";

sub new
{
	my $class = shift;
	my $token = shift;
	my $user = shift;

	bless {
		json => JSON->new->utf8->pretty(1),
		lwp => LWP::UserAgent->new(
			agent	=> "slack-client/0.0000",
			ssl_opts => { verify_hostname => 0 }, # shouldn't do this
		),
		user => $user,
		token => $token,
		last_time => time(),
		verbose => 0,

		users => {},
		channels => {},
	}, $class;
}


sub api
{
	my $s = shift;
	my $method = shift;
	my $args = {
		token => $s->{token},
		@_,
	};

	my $rc = $s->{lwp}->post("$base_url/$method", $args)
		or return;

	unless ($rc->is_success)
	{
		warn "$method failed. sleeping\n";
		sleep 1;
		return;
	}

	my $j = $s->{json}->decode($rc->decoded_content);
	warn Dumper($j)
		if $s->{verbose};

	return $j;
}


sub uid2user
{
	my $s = shift;
	my $uid = shift;

	return $s->{users}{$uid} if exists $s->{users}{$uid};

	# refresh the user uids
	$s->users();

	return $s->{users}->{$uid} ||= $uid;
}


sub users
{
	my $s = shift;

	# fetch the user id map and then extract from it
	my $j = $s->api("users.list")
		or return;

	for my $user (@{$j->{members}})
	{
		$s->{users}{$user->{id}} = $user->{name};
	}

	return $s->{users};
}


sub channels
{
	my $s = shift;
	my $j = $s->api("channels.list")
		or return;

	for my $c (@{$j->{channels}})
	{
		my $name = $c->{name};
		my $id = $c->{id};

		$s->{channels}{$name} = $id;
	}

	return $s->{channels}
}


sub messages
{
	my $s = shift;

	my $j = $s->api("channels.history", 
		channel	=> $s->{channel},
		oldest => $s->{last_time},
		count => 1000,
	) or return;

	my @lines;

	#print Dumper($j->{ok});
	#print Dumper($j->{messages});
	#print Dumper($j->{has_more});
	my $lines = 0;
	my $total_lines = 0;

	# ignore empty messages
	return unless @{$j->{messages}};

	for my $msg (@{$j->{messages}})
	{
		print STDERR Dumper($msg), "\n"
			if $s->{verbose};

		$total_lines++;
		if ($msg->{ts} > $s->{last_time})
		{
			warn "ts: $msg->{ts} > $s->{last_time}\n" if $s->{verbose};
			$s->{last_time} = $msg->{ts};
		}

		if ($msg->{subtype})
		{
			# ignore all subtyped messages
			next;
			next if $msg->{subtype} eq 'bot_message';
		}

		my $text = $msg->{text};
		my $user = $s->uid2user($msg->{user});

		push @lines, [$user, $text];

		$lines++;
	}

	warn "$lines/$total_lines\n" if $s->{verbose};
	return @lines;
}


sub send
{
	my $s = shift;
	my $text = shift;

	# reformat the text to avoid reflows; broken
	#$text =~ s/(?<!\n)\n(?!\n)/ /msg;

	my $j = $s->api("chat.postMessage",
		channel => $s->{channel},
		username => $s->{user},
		text => $text,
		as_user => "true",
	) or return;

	print STDERR "post:", Dumper($j)
		if $s->{verbose};

	return 1;
}
__END__
