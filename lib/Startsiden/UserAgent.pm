package Startsiden::UserAgent;

use warnings;
use strict;
use v5.10;
use CHI;
use Devel::StackTrace;
use English qw(-no_match_vars);
use File::Basename;
use File::Path;
use File::Spec;
use List::Util;
use Mojo::Transaction::HTTP;
use Mojo::URL;
use Mojo::Log;
use Mojo::Base 'Mojo::UserAgent';
use Mojo::Util;
use POSIX;
use Readonly;
use String::Truncate;
use Time::HiRes qw/time/;

Readonly my $HTTP_OK => 200;
Readonly my $HTTP_FILE_NOT_FOUND => 404;

# TODO: Timeout, fallback
# TODO: Expected result content (json etc)

# MOJO_USERAGENT_CONFIG
## no critic (ProhibitMagicNumbers)
has 'connect_timeout'    => sub { $ENV{MOJO_CONNECT_TIMEOUT}    // 2  };
has 'inactivity_timeout' => sub { $ENV{MOJO_INACTIVITY_TIMEOUT} // 5  };
has 'max_redirects'      => sub { $ENV{MOJO_MAX_REDIRECTS}      // 4  };
has 'request_timeout'    => sub { $ENV{MOJO_REQUEST_TIMEOUT}    // 10 };
## use critic

# SUA_CLIENT_CONFIG
has 'local_dir'          => sub { $ENV{SUA_LOCAL_DIR}          // q{}   };
has 'always_return_file' => sub { $ENV{SUA_ALWAYS_RETURN_FILE} // undef };
has 'cache_agent'        => sub { $ENV{SUA_NOCACHE}            ? () : # Allow override cache
    CHI->new(
        driver             => 'File',
        root_dir           => '/tmp/startsiden-useragent-cache',
        serializer         => 'Storable',
        namespace          => 'SUA_Client',
        expires_in         => '1 minute',
        expires_on_backend => 1,
    );
};
has 'logger' => sub { Mojo::Log->new() };
has 'access_log' => sub { $ENV{SUA_ACCESS_LOG} || '' };
has 'use_expired_cached_content' => sub { $ENV{SUA_USE_EXPIRED_CACHED_CONTENT} // 1 };
has 'accepted_error_codes' => sub { $ENV{SUA_ACCEPTED_ERROR_CODES} || '' };

has 'created_stacktrace' => '';

sub new {
    my ($class, %opts) = @_;

    my %mojo_agent_config = map { $_ => $opts{$_} } grep { exists $opts{$_} } qw/
        ca
        cert
        connect_timeout
        cookie_jar
        inactivity_timeout
        ioloop
        key
        local_address
        max_connections
        max_redirects
        proxy
        request_timeout
        server
        transactor
    /;

    my $ua = $class->SUPER::new(%mojo_agent_config);

    # Populate attributes
    map { $ua->$_( $opts{$_} ) } grep { exists $opts{$_} } qw/
        local_dir
        always_return_file
        cache_agent
        access_log
        use_expired_cached_content
        accepted_error_codes
    /;

    $ua->created_stacktrace($ua->_get_stacktrace);

    return bless($ua, $class);
}

sub invalidate {
    my ($self, $key) = @_;

    if ($self->is_cacheable($key)) {
        $self->logger->debug("Invalidating cache for '$key'");
        return $self->cache_agent->remove($key);
    }

    return;
}

sub expire {
    my ($self, $key) = @_;

    if ($self->is_cacheable($key)) {
        $self->logger->debug("Expiring cache for '$key'");
        return $self->cache_agent->expire($key);
    }

    return;
}

sub get {
    my ($self, $url, @opts) = @_;

    my $cb = ref $opts[-1] eq 'CODE' ? pop @opts : undef;
    $url = ($self->always_return_file || $url);

    my $key = $self->generate_key($url, @opts);

    my $start_time = time;

    # We wrap the incoming callback in our own callback to be able to cache the response
    my $wrapper_cb = $cb ? sub {
        my ($ua, $tx) = @_;
        $cb->($ua, $ua->_post_process_get($tx, $start_time, $key, @opts));
    } : ();
    # Is an absolute URL or an URL relative to the app eg. http://foo.com/ or /foo.txt
    if (Mojo::URL->new($url)->is_abs || $url =~ m{ \A / }gmx) {
        if ($self->is_cacheable($key)) { # TODO: URL by URL, and case-by-case expiration
            my $serialized = $self->cache_agent->get($key);
            if ($serialized) {
                my $cached_tx = _build_fake_tx($serialized);

                $self->_log_line($cached_tx, {
                    start_time => $start_time,
                    key => $key,
                    type => 'cached result',
                });

                return $cb->($self, $cached_tx) if $cb;
                return $cached_tx;
            }
        }

        # first non-blocking, if no callback regular post process
        return $self->SUPER::get($url,$wrapper_cb) if $wrapper_cb;
        return $self->_post_process_get( $self->SUPER::get($url, @opts), $start_time, $key, @opts );

    } else { # Local file eg. t/data/foo.txt
        $url = $self->local_dir ? File::Spec->catfile($self->local_dir, "$url") : "$url";

        my $code = $HTTP_FILE_NOT_FOUND;
        my $res;
        eval {
            $res = $self->_parse_local_file_res($url);
            $code = $res->{code};
        } or $self->logger->error($EVAL_ERROR);

        my $params = { url => $url, body => $res->{body}, code => $code, method => 'FILE', headers => $res->{headers} };

        # first non-blocking, if no callback, regular post process
        my $tx = _build_fake_tx($params);
        $self->_log_line($tx, {
            start_time => $start_time,
            key => $key,
            type => 'local file',
        });

        return $cb->($self, $tx) if $cb;
        return $tx;
    }
}

sub _post_process_get {
    my ($self, $tx, $start_time, $key, @opts) = @_;

    if ( $self->is_cacheable($key) ) {
        if ( $self->is_considered_error($tx) ) {
            # Return an expired+cached version of the page for other errors
            # for all services, e.g. Chartbeat (also including DrPublish).
            if ( $self->use_expired_cached_content ) { # TODO: URL by URL, and case-by-case expiration
                my $cache_obj = $self->cache_agent->get_object($key);
                if ($cache_obj) {
                    my $serialized = $cache_obj->value;
                    $serialized->{headers}->{'X-Startsiden-UserAgent-ExpiresAt'}
                        = $cache_obj->expires_at($key);

                    my $expired_tx = _build_fake_tx($serialized);
                    $self->_log_line( $expired_tx, {
                        start_time => $start_time,
                        key        => $key,
                        type       => 'expired and cached',
                        orig_tx    => $tx,
                    });

                    return $expired_tx;
                }
            }
        } else {
            # Store object in cache
            $self->cache_agent->set($key, _serialize_tx($tx));
        }
    }

    $self->_log_line($tx, {
        start_time => $start_time,
        key => $key,
        type => 'fetched',
    });

    return $tx;
}

sub set {
    my ($self, $url, $value) = @_;

    # key is Mojo::URL
    my $key = $self->generate_key($url);
    $self->logger->debug("Illegal cache key: $key") && return if ref $key;

    my $fake_tx = _build_fake_tx({
        url    => $key,
        body   => $value,
        code   => $HTTP_OK,
        method => 'FILE'
    });

    $self->logger->debug("Set cache key: $key");
    $self->cache_agent->set($key, _serialize_tx($fake_tx));
    return $key;
}

sub is_valid {
    my ($self, $key) = @_;

    ($self->logger->debug("Illegal cache key: $key") && return) if ref $key;

    $self->logger->debug("Checking if key is valid: $key");
    return $self->cache_agent->is_valid($key);
}

sub is_cacheable {
    my ($self, $url) = @_;

    return $self->cache_agent && ($url !~ m{ \A / }gmx);
}

sub generate_key {
    my ($self, $url, @opts) = @_;

    my $cb = ref $opts[-1] eq 'CODE' ? pop @opts : undef;
    my $key = join q{,}, "$url", map {
        ref $_ eq 'ARRAY' ? "[" . (join q{,}, @{$_}) . "]" :
        ref $_ eq 'HASH'  ? "{" . (join q{,}, %{$_}) . "}" :
        "$_"
    } @opts;

    return $key;
}

sub is_considered_error {
    my ($self, $tx) = @_;

    # If we find some error codes that should be accepted, we don't consider this an error
    if ( $tx->error && $self->accepted_error_codes ) {
        my $codes = ref $self->accepted_error_codes ?     $self->accepted_error_codes
                  :                                   [ ( $self->accepted_error_codes ) ];
        return if List::Util::first { $tx->error->{code} == $_ } @{$codes};
    }

    return $tx->error;
}


sub _serialize_tx {
    my ($tx) = @_;

    my $cached_ts = time;
    return {
        cached  => $cached_ts,
        method  => $tx->req->method,
        url     => $tx->req->url,
        code    => $tx->res->code,
        body    => $tx->res->body,
        json    => $tx->res->json,
        headers => {
          %{ $tx->res->headers->to_hash || {} },
          'X-Startsiden-UserAgent-Cached' => $cached_ts
        }
    };
}

sub _build_fake_tx {
    my ($opts) = @_;

    # Create transaction object to return so we look like a regular request
    my $tx = Mojo::Transaction::HTTP->new();

    $tx->req->method($opts->{method});
    $tx->req->url(Mojo::URL->new($opts->{url}));

    $tx->res->headers->from_hash($opts->{headers});
    $tx->res->code($opts->{code});
    $tx->res->{json} = $opts->{json};
    $tx->res->body($opts->{body});

    return $tx;
}

sub _parse_local_file_res {
    my ($self, $url) = @_;

    my $headers;
    my $body = Mojo::Util::slurp($url, 'binmode' => ':raw' );
    my $code = $HTTP_OK;
    my $msg  = 'OK';

    if ($body =~ m{\A (?: DELETE | GET | HEAD | OPTIONS | PATCH | POST | PUT ) \s }gmx) {
        my $code_msg_headers;
        my $code_msg;
        my $http;
        my $msg;
        (undef, $code_msg_headers, $body) = split m{(?:\r\n|\n){2,}}mx, $body,             3; ## no critic (ProhibitMagicNumbers)
        ($code_msg, $headers)             = split m{(?:\r\n|\n)}mx,     $code_msg_headers, 2;
        ($http, $code, $msg)              = $code_msg =~ m{ \A (?:(\S+) \s+)? (\d+) \s+ (.*) \z}mx;

        $headers = Mojo::Headers->new->parse("$headers\n\n")->to_hash;
    }

    return { body => $body, code => $code, message => $msg, headers => $headers };
}

sub _write_local_file_res {
    my ($self, $tx, $dir) = @_;

    return unless ($dir && -e $dir && -d $dir);

    my $method = $tx->req->method;
    my $url  = $tx->req->url;
    my $body = $tx->res->body;
    my $code = $tx->res->code;
    my $message = $tx->res->message;

    my $target_file = File::Spec->catfile($dir, split '/', $url->path_query);
    File::Path::make_path(File::Basename::dirname($target_file));
    Mojo::Util::spurt((
        join "\n\n",
           (join " ", $method, "$url\n"  ) . $tx->req->headers->to_string,
           (join " ", $code, "$message\n") . $tx->res->headers->to_string,
           $body),
    $target_file)
        and $self->logger->debug("Wrote request+response to: '$target_file'");
}

sub _log_line {
    my ($self, $tx, $opts) = @_;

    $self->_write_local_file_res($tx, $ENV{SUA_CLIENT_WRITE_LOCAL_FILE_RES_DIR});

    my $callers = $self->_get_stacktrace;

    $self->logger->debug(sprintf(q{Returning %s '%s' => %s for %s (%s)}, (
        $opts->{type},
        String::Truncate::elide( $tx->req->url, 150, { truncate => 'middle'} ),
        ($tx->res->code || $tx->res->error->{code} || $tx->res->error->{message}),
        $callers, $self->created_stacktrace
    )));

    return unless $self->{access_log};

    my $elapsed_time = sprintf '%.3f', (time-$opts->{start_time});

    my $NONE = q{-};

    my $http_host              = $tx->req->url->host                                   || $NONE;
    my $remote_addr            =                                                          $NONE;
    my $time_local             = POSIX::strftime('%d/%b/%Y:%H:%M:%S %z', localtime)    || $NONE;
    my $request                = ($tx->req->method . q{ } . $tx->req->url->path_query) || $NONE;
    my $status                 = $tx->res->code                                        || $NONE;
    my $body_bytes_sent        = length $tx->res->body                                 || $NONE;
    my $http_referer           = $callers                                              || $NONE;
    my $http_user_agent        = __PACKAGE__ . "(" . $opts->{type} .")"                || $NONE;
    my $request_time           = $elapsed_time                                         || $NONE;
    my $upstream_response_time = $elapsed_time                                         || $NONE;
    my $http_x_forwarded_for   =                                                          $NONE;

    # Use sysopen, slightly slower and hits disk, but avoids clobbering
    sysopen my $fh, $self->access_log,  O_WRONLY | O_APPEND | O_CREAT; ## no critic (ProhibitBitwiseOperators)
    syswrite $fh, qq{$http_host $remote_addr [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_time $upstream_response_time "$http_x_forwarded_for"\n}
        or $self->logger->warn("Unable to write to '" . $self->access_log . "': $OS_ERROR");
    close $fh or $self->logger->warn("Unable to close '" . $self->access_log . "': $OS_ERROR");

    return;
}

sub _get_stacktrace {
    my ($self) = @_;

    my @frames = ( Devel::StackTrace->new(
        ignore_class => [ 'Devel::StackTrace', 'Startsiden::UserAgent', 'Template::Document', 'Template::Context', 'Template::Service' ],
        frame_filter => sub { ($_[0]->{caller}->[0] !~ m{ \A Mojo | Try }gmx) },
    )->frames() );

    my $prev_package = '';
    my $callers = join q{,}, map {
        my $package = $_->package;
        if ($package eq 'Template::Provider') {
            $package = (join "/", grep { $_ } (split '/', $_->filename)[-3..-1]);
        }
        if ($prev_package eq $package) {
            $package = '';
        } else {
            $prev_package = $package;
            $package =~ s/(?:(\w)\w*::)/$1./gmx;
            $package .= ':';
        }
        $package . $_->line();
    } grep { $_ } @frames;
}

1;

=encoding utf8

=head1 NAME

Startsiden::UserAgent - Caching, Non-blocking I/O HTTP, Local file and WebSocket user agent

=head1 SYNOPSIS

use Startsiden::UserAgent;

my $ua = Startsiden::UserAgent->new;

=head1 DESCRIPTION

L<Startsiden::UserAgent> is a full featured caching, non-blocking I/O HTTP, Local file and WebSocket user
agent, with IPv6, TLS, SNI, IDNA, Comet (long polling), keep-alive, connection
pooling, timeout, cookie, multipart, proxy, gzip compression and multiple
event loop support.

It inherits all of the features L<Mojo::UserAgent> provides but in addition allows you to
retrieve cached content using a L<CHI> compatible caching engine.

See L<Mojo::UserAgent> and L<Mojolicious::Guides::Cookbook/"USER AGENT"> for more.

=head1 ATTRIBUTES

L<Startsiden::UserAgent> inherits all attributes from L<Mojo::UserAgent> and implements the following new ones.

=head2 local_dir

  my $local_dir = $ua->local_dir;
  $ua->local_dir('/path/to/local_files');

Sets the local dir, used as a prefix where relative URLs are fetched from. A C<$ua->get('foobar.txt')> request would
read the file '/tmp/foobar.txt' if local_dir is set to '/tmp', defaults to the value of the
C<SUA_LOCAL_DIR> environment variable and if not set, to ''.

=head2 always_return_file

  my $file = $ua->always_return_file;
  $ua->always_return_file('/tmp/default_file.txt');

Makes all consecutive request return the same file, no matter what file or URL is requested with C<$ua->get()>, defaults
to the value of the C<SUA_ALWAYS_RETURN_FILE> environment value and if not, it respects the File/URL in the request.

=head2 cache_agent

  my $cache_agent = $ua->cache_agent;
  $ua->cache_agent(CHI->new(
     driver             => 'File',
     root_dir           => '/tmp/startsiden-useragent-cache',
     serializer         => 'Storable',
     namespace          => 'SUA_Client',
     expires_in         => '1 minutes',
     expires_on_backend => 1,
  ));

Tells L<Startsiden::UserAgent> which cache_agent to use. It needs to be CHI-compliant and defaults to the above settings.

You may also set the C<SUA_NOCACHE> environment variable to avoid caching at all.

=head2 logger

Provide a logging object, defaults to ABCN::Logger

=head2 access_log

A file that will get logs of every request, the format is a hybrid of Apache combined log, including time spent for the request.
If provided the file will be written to. Defaults to C<$ENV{SUA_ACCESS_LOG} || ''> which means no log will be written.

=head2 use_expired_cached_content

Indicates that we will send expired, cached content back. This means that if a request fails, and the cache has expired, you
will get back the last successful content. Defaults to C<$ENV{SUA_EXPIRED_CONTENT} // 1>

=head2 accepted_error_codes

A list of error codes that should not be considered as errors. For instance this means that the client will not look for expired
cached content for requests that result in this response. Defaults to C<$ENV{SUA_ACCEPTED_ERROR_CODES} || ''>

=head1 OVERRIDEN ATTRIBUTES

In addition L<Startsiden::UserAgent> overrides the following L<Mojo::UserAgent> attributes.

=head2 connect_timeout

Defaults to C<$ENV{MOJO_CONNECT_TIMEOUT} // 2>

=head2 inactivity_timeout

Defaults to C<$ENV{MOJO_INACTIVITY_TIMEOUT} // 5>

=head2 max_redirects

Defaults to C<$ENV{MOJO_MAX_REDIRECTS} // 4>

=head2 request_timeout

Defaults to C<$ENV{MOJO_REQUEST_TIMEOUT} // 10>

=head1 METHODS

L<Startsiden::UserAgent> inherits all methods from L<Mojo::UserAgent> and
implements the following new ones.

=head2 invalidate

  $ua->invalidate($key);

Deletes the cache of the given $key.

=head2 expire

  $ua->expire($key);

Set the cache of the given $key as expired.

=head2 set

  my $tx = $ua->build_tx(GET => "http://localhost:$port", ...);
  $tx = $ua->start($tx);
  my $cache_key = $ua->generate_key("http://localhost:$port", ...);
  $ua->set($cache_key, $tx);

Set function sets transmission data directly to cache.
It's mainly used in L<Startsiden::UserAgent::Vipr>.

VideoList class fetches multiple video in single request to save bandwith,
then splits into single video and set to cache one by one.
Video can be requested individually by ID.

=head2 generate_key(@params)

Returns a key to be used for the cache agent. It accepts the same parameters
that a normal ->get() request does.

=head1 OVERRIDEN METHODS

=head2 new

  my $ua = Startsiden::UserAgent->new( request_timeout => 1, ... );

Accepts the attributes listed above and all attributes from L<Mojo::UserAgent>.
Stores its own attributes and passes on the relevant ones when creating a
parent L<Mojo::UserAgent> object that it inherits from. Returns a L<Startsiden::UserAgent> object

=head2 get(@params)

  my $tx = $ua->get('http://example.com');

Accepts the same arguments and returns the same as L<Mojo::UserAgent>.

It will try to return a cached version of the $url, adhering to the set or default attributes.

If any of other arguments than the first one ($url) are given, caching is ignored.

In addition if a relative file path is given, it tries to return the file appended to
the attribute C<local_dir>. In this case a fake L<Mojo::Transaction::HTTP> object is returned,
populated with a L<Mojo::Message::Request> with method and url, and a L<Mojo::Message::Response>
with headers, code and body set.

=head2 validate_key

  my $status = $ua4->validate_key('http://example.com');

Fast validates if key is valid in cache without doing fetch.
Return 1 if true.

=head1 ENVIRONMENT VARIABLES

SUA_CLIENT_WRITE_LOCAL_FILE_RES_DIR can be set to a directory to store a request in:

# Re-usable local file with headers and metadata ends up at 't/data/drfront/lol/foo.html?bar=1'
$ENV{SUA_CLIENT_WRITE_LOCAL_FILE_RES_DIR}='t/data/drfront';
Startsiden::UserAgent->new->get("http://foo.com/lol/foo.html?bar=1");

=head1 SEE ALSO

L<Mojo::UserAgent>, L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
