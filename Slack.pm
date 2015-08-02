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
use AnyEvent::WebSocket::Client;

my $base_url = "https://slack.com/api";

sub new
{
	my $class = shift;
	my $token = shift;
	my $user = shift || '';

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

		#users => {},
		#channels => {},
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


sub username
{
	my $s = shift;
	my $uid = shift;

	return $s->{users}{$uid}{name} if exists $s->{users}{$uid};
	return $uid;
}


sub channel
{
	my $s = shift;
	my $id = shift;

	return $s->{channels}{$id}{name} if exists $s->{channels}{$id};
	return;
}


sub channel_id
{
	my $s = shift;
	my $name = shift;

	return unless exists $s->{channelnames};
	return $s->{channelnames}{$name}{id};
}


sub users
{
	my $s = shift;

	# fetch the user id map and then extract from it
	my $j = $s->api("users.list")
		or return;

	for my $user (@{$j->{members}})
	{
		$s->{users}{$user->{id}} = $user;
		$s->{usernames}{$user->{name}} = $user;
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

	# set as_user to true if the user is not defined;
	# this will use the user of the token.  Otherwise
	# set the username and as_user=false, which will
	# flag this as a bot posting.
	my $j = $s->api("chat.postMessage",
		channel => $s->{channel},
		username => $s->{user},
		text => $text,
		as_user => $s->{user} ? "false" : "true",
	) or return;

	print STDERR "post:", Dumper($j)
		if $s->{verbose};

	return $j;
}


sub websocket
{
	my $s = shift;
	my %handlers = @_;

	my $j = $s->api("rtm.start");
	my $url = $j->{url};
	#print Dumper($j);
	warn "URL: $url\n" if $s->{verbose};

	# populate the channels and both fwd/rev username maps
	for my $c (@{$j->{channels}})
	{
		$s->{channels}{$c->{id}} = $c;
		$s->{channelnames}{$c->{name}} = $c;
	}

	for my $u (@{$j->{users}})
	{
		$s->{users}{$u->{id}} = $u;
		$s->{usernames}{$u->{name}} = $u;
	}
	
	my $client = AnyEvent::WebSocket::Client->new;

	$client->connect($url)->cb(sub {
		# make $connection an our variable rather than
		# my so that it will stick around.  Once the
		# connection falls out of scope any callbacks
		# tied to it will be destroyed.
		warn "calling first recv\n";
		our $connection = eval { shift->recv() };
		if($@) {
			# handle error...
			warn $@;
			return;
		}


		# recieve message from the websocket...
		$connection->on(each_message => sub {
			my ($connection, $message) = @_;
			warn Dumper($message) if $s->{verbose};

			my $j = $s->{json}->decode($message->{body});
			my $type = $j->{type} || "unknown";
			if (exists $handlers{$type})
			{
				$handlers{$type}->($s, $j);
			} elsif (exists $handlers{debug})
			{
				$handlers{debug}->($s, $j);
			} else {
				warn "$type: Unhandled.\n", Dumper($j);
			}

			return 1;
		});

		# handle a closed connection...
		$connection->on(finish => sub {
			my($connection) = @_;

			warn "Websocket closed!\n" if $s->{verbose};
			$handlers{close}->($s) if exists $handlers{close};
		});
	});

	# Never returns
	AnyEvent->condvar->recv();
}

__END__
