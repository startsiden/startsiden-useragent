use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_NO_SOCKS} = $ENV{MOJO_NO_TLS} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Time::HiRes;
use IO::Compress::Gzip 'gzip';
use Mojo::IOLoop;
use Mojo::Message::Request;
use Startsiden::UserAgent;
use Mojo::UserAgent::Server;
use Mojolicious;

# Startsiden::UserAgent specific tests

# Setup mock server
my $app = Mojolicious->new();
my $controller = sub { shift->render(text => Time::HiRes::time(), status => 200); };
$app->routes->get('/' => { text => 'works' });
$app->routes->get('/maybe_not_found' => sub { $controller->(@_); } );


use FindBin qw($Bin);

my $ua1 = Startsiden::UserAgent->new( local_dir => "$Bin/../t/data" );
ok $ua1->get('abcn_newsfeed.xml')->success, 'Can fetch local file and success is set';
is $ua1->get('abcn_newsfeed.xml')->res->code, 200, 'Can fetch local file and get correct status';
like $ua1->get('abcn_newsfeed.xml')->res->body, qr/^<\?xml/, 'Can fetch local file and get its body';

my $ua2 = Startsiden::UserAgent->new();
is $ua2->get('t/data/abcn_newsfeed.xml')->res->code, 200, 'Can fetch local file and get correct status';
like $ua2->get('t/data/abcn_newsfeed.xml')->res->body, qr/^<\?xml/, 'Can fetch local file and get its body';

my $ua3 = Startsiden::UserAgent->new( local_dir => "$Bin/../t/data", always_return_file => 'abcn_newsfeed.xml' );
is $ua3->get('NOT_abcn_newsfeed.xml')->res->code, 200, 'Always return file provided and get correct status';
like $ua3->get('NOT_abcn_newsfeed.xml')->res->body, qr/^<\?xml/, 'Always return file provided and get its body';

my $ua4 = Startsiden::UserAgent->new();
is $ua4->get('NOT_abcn_newsfeed.xml')->res->code, 404, 'Return 404 when file is not found';
is $ua4->get('NOT_abcn_newsfeed.xml')->res->body, '',  'Return empty body when file not found';

$ua4->invalidate('http://google.com');

my $tx1 = $ua4->get('http://google.com');
my $first_ts = $tx1->res->headers->header('X-Startsiden-UserAgent-Cached');
ok !$first_ts, 'Not cached first time';

my $tx2 = $ua4->get('http://google.com');
my $second_ts = $tx2->res->headers->header('X-Startsiden-UserAgent-Cached');
ok $second_ts, 'Response is cached';

my $tx3 = $ua4->get('http://google.com');
my $third_ts = $tx3->res->headers->header('X-Startsiden-UserAgent-Cached');
is $second_ts, $third_ts, 'Response is still the same one cached';

# Requests with headers
my $rand = time;
my $tx4 = $ua4->get('http://google.com' => { 'X-Some-Header' => $rand });
my $fourth_ts = $tx4->res->headers->header('X-Startsiden-UserAgent-Cached');
ok !$fourth_ts, 'Not cached first time';
ok $tx4->res->content, 'Contains something';

my $tx5 = $ua4->get('http://google.com' => { 'X-Some-Header' => $rand });
my $fifth_ts = $tx5->res->headers->header('X-Startsiden-UserAgent-Cached');
ok $fifth_ts, 'Response is cached';
ok $tx5->res->content, 'Contains something';

# Set cache directly to avoid redundant call to Vipr
my $ua_with_mock_server = Startsiden::UserAgent->new();
$ua_with_mock_server->server->app($app);
my $tx = $ua_with_mock_server->get("/");

my $cache_key = "http://some_server/this_is_modified_cache_key";
$ua4->set($cache_key, $tx);
is $ua4->get($cache_key)->res->code, 200, 'Can fetch from modified cache key';

# validate cache key
is $ua4->is_valid($cache_key), 1, "Cache key is valid";
$ua4->invalidate($cache_key); # expire
is $ua4->is_valid($cache_key), undef, "Cache key is expired";

is $ua4->is_valid('INVALID_KEY'), undef, 'Invalid key';

# HUH? What is this testing?
is $ua4->is_valid(Mojo::UserAgent->new()), undef, 'Invalid key (object) survives';

subtest 'ABCN-3702' => sub {
    my $ua = Startsiden::UserAgent->new();
    my $tx = $ua->get('t/data/abcn_client_body+headers.txt');
    is $tx->res->code, 200, 'Can fetch local file and get correct status';
    is $tx->res->headers->header('X-Test'), 'Works', 'Can fetch local file and get correct header';
    is $tx->res->body, "test\n\nbody\n", 'Can fetch local file and get its body';
};

subtest 'ABCN-3572' => sub {
    my $ua = Startsiden::UserAgent->new();

    my $url = "http://www.google.com/?non-blocking-cache-test";
    $ua->invalidate($url);
    my $tx = $ua->get($url);
    is $tx->res->code, 200, 'right status';
    ok !$tx->res->headers->header('X-Startsiden-UserAgent-Cached'), 'First request should not be cached';

    my $first_code = $tx->res->code;
    my $first_body = $tx->res->body;
    my $first_headers = $tx->res->headers;

    my ($headers, $success, $code, $body);
    $ua->get(
        $url => sub {
            my ($ua, $tx) = @_;
            $headers = $tx->res->headers;
            $success = $tx->success;
            $code    = $tx->res->code;
            $body    = $tx->res->body;
            Mojo::IOLoop->stop;
        }
    );
    ok $success, 'successful';
    ok $headers->header('X-Startsiden-UserAgent-Cached'), 'Non-blocking request should be cached';

    is $code,    $first_code, 'cached status is the same as original';
    is $body,    $first_body, 'cached body is the same as original';

    $headers->remove('X-Startsiden-UserAgent-Cached');
    is_deeply $headers->to_hash, $first_headers->to_hash, 'cached headers are the same as original';
};

subtest 'Cache with request headers' => sub {
    my $ua = Startsiden::UserAgent->new();

    my $keys = {
        'http://www.google.com' => ['http://www.google.com'],
        'http://www.google.com,{X-Test,Test}' => ['http://www.google.com', { 'X-Test' => 'Test' } ],
        'http://www.google.com,{X-Test,Test}' => ['http://www.google.com', { 'X-Test' => 'Test' }, sub { } ],
        'http://www.google.com,{},form,{a,b}' => ['http://www.google.com', {}, form => { 'a' => 'b' } ],
        'http://www.google.com,{X-Test,Test},form,{a,b}' => ['http://www.google.com', { 'X-Test' => 'Test' }, form => { 'a' => 'b' }, sub { } ],
        'http://www.google.com,{X-Test,Test},json,{a,b}' => ['http://www.google.com', { 'X-Test' => 'Test' }, json => { 'a' => 'b' }, sub { } ],
    };
    while (my ($k, $v) = each %{$keys}) {
        is $ua->generate_key(@{$v}), $k, "generate_key " . (join " ", @{$v}) . " => $k";
    }

    my @params = ('http://www.google.com' => { 'X-Test' => 'Test' });

    my $cache_key = $ua->generate_key(@params);
    is($cache_key, 'http://www.google.com,{X-Test,Test}', 'cache key is correct');
    $ua->invalidate($cache_key);

    my $tx1 = $ua->get(@params);
    ok !$tx1->res->headers->header('X-Startsiden-UserAgent-Cached'), 'first response is not cached';

    my $tx2 = $ua->get(@params);
    ok $tx2->res->headers->header('X-Startsiden-UserAgent-Cached'), 'response is cached';

};

subtest 'Should run callbacks even if content is local' => sub {
    my $ua = Startsiden::UserAgent->new();

    my $tx = $ua->get('t/data/abcn_client_body+headers.txt' => sub {
      my ($ua, $tx) = @_;
      is $tx->res->code, 200, 'Can fetch local file and get correct status';
      is $tx->res->headers->header('X-Test'), 'Works', 'Can fetch local file and get correct header';
      is $tx->res->body, "test\n\nbody\n", 'Can fetch local file and get its body';
   });

};

subtest 'Should run callbacks even if content is cached' => sub {
    my $ua = Startsiden::UserAgent->new();

    my $url = 'http://www.google.com';
    my $tx = $ua->get($url);

    $tx = $ua->get($url => sub {
      my ($ua, $tx) = @_;
      is $tx->res->code, 200, 'Can fetch cached file and get correct status';
   });

};

subtest 'expired+cached functionality' => sub {
	my $ua = Startsiden::UserAgent->new();
	$ua->server->app($app);
	# Allow caching /foo requests too
	local *Startsiden::UserAgent::is_cacheable = sub { return 1; };
	# make sure we have no cache around
	$ua->invalidate($ua->generate_key("/maybe_not_found"));

	ok $ua->is_cacheable("/maybe_not_found"), 'Local URL is cacheable';

	# First normal request
	my $tx = $ua->get("/maybe_not_found");
	is $tx->res->code, '200', 'Get 200 correctly first time';
	my $body = $tx->res->body;
	like $body, qr/\d+\.\d+/, 'Body has timestamp only';

	# ...switch to serving 404
	$controller = sub { shift->render(text => Time::HiRes::time(), status => 404); };

	# ...Second request now gets cached version
	$tx = $ua->get("/maybe_not_found");
	is $tx->res->code, '200', 'Get 200 correctly first cached version';
	is $body, $tx->res->body, 'Result is cached';

	# ...expire our cache (time has passed...)
	$ua->expire($ua->generate_key('/maybe_not_found'));

	# ...get a a expired+cached result now that it returns 404 and we expired the cache
	$tx = $ua->get("/maybe_not_found");
	is $tx->res->code, '200', 'Get 200 correctly cached and expired';
	is $body, $tx->res->body, 'Result is cached';

	# ...start accepting 404 as non-error content
	$ua->accepted_error_codes(404);

	# ...we now accept 404s so we should get a fresh 404 request
	$tx = $ua->get("/maybe_not_found");
	my $new_body = $tx->res->body;
	is $tx->res->code, '404', 'Get 404 correctly - Not in cache anymore';
	isnt $body, $new_body, 'Result is fresh';

	# ...this result should now be cached
	$tx = $ua->get("/maybe_not_found");
	is $tx->res->code, '404', 'Get 404 correctly - cached again';
	is $new_body, $tx->res->body, 'Result is the same as last one';

	# ...expire our cache (time has passed...)
	$ua->expire($ua->generate_key('/maybe_not_found'));

	# ...get fresh result as we expired the cache and 404 is still not considered an error
	$tx = $ua->get("/maybe_not_found");
	is $tx->res->code, '404', 'Get 404 correctly - fresh';
	isnt $new_body, $tx->res->body, 'Result is fresh';
};

# TODO: Replace google.com tests with local server

subtest 'normalize URLs' => sub {
    my $ua = Startsiden::UserAgent->new();

    my $urls = {
       '/foo?c=1&a=1' => '/foo?a=1&c=1',
       'http://foo.com/foo?c=1&a=1' => 'http://foo.com/foo?a=1&c=1',
       'foo.com/foo?c=1&a=1' => 'foo.com/foo?a=1&c=1',
       '/foo?c&a=1' => '/foo?a=1&c',
       'http://foo.com/foo?c&a=1' => 'http://foo.com/foo?a=1&c',
       'foo.com/foo?c&a=1' => 'foo.com/foo?a=1&c',
    };
    while (my ($in, $exp) = each %{$urls}) {
        is $ua->normalize_url($in), $exp, "$in => $exp";
    }
};

done_testing();
