# NAME

Startsiden::UserAgent - Caching, Non-blocking I/O HTTP, Local file and WebSocket user agent

# SYNOPSIS

use Startsiden::UserAgent;

my $ua = Startsiden::UserAgent->new;

# DESCRIPTION

[Startsiden::UserAgent](https://metacpan.org/pod/Startsiden::UserAgent) is a full featured caching, non-blocking I/O HTTP, Local file and WebSocket user
agent, with IPv6, TLS, SNI, IDNA, Comet (long polling), keep-alive, connection
pooling, timeout, cookie, multipart, proxy, gzip compression and multiple
event loop support.

It inherits all of the features [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) provides but in addition allows you to
retrieve cached content using a [CHI](https://metacpan.org/pod/CHI) compatible caching engine.

See [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) and ["USER AGENT" in Mojolicious::Guides::Cookbook](https://metacpan.org/pod/Mojolicious::Guides::Cookbook#USER-AGENT) for more.

# ATTRIBUTES

[Startsiden::UserAgent](https://metacpan.org/pod/Startsiden::UserAgent) inherits all attributes from [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) and implements the following new ones.

## local\_dir

    my $local_dir = $ua->local_dir;
    $ua->local_dir('/path/to/local_files');

Sets the local dir, used as a prefix where relative URLs are fetched from. A `$ua-`get('foobar.txt')> request would
read the file '/tmp/foobar.txt' if local\_dir is set to '/tmp', defaults to the value of the
`SUA_LOCAL_DIR` environment variable and if not set, to ''.

## always\_return\_file

    my $file = $ua->always_return_file;
    $ua->always_return_file('/tmp/default_file.txt');

Makes all consecutive request return the same file, no matter what file or URL is requested with `$ua-`get()>, defaults
to the value of the `SUA_ALWAYS_RETURN_FILE` environment value and if not, it respects the File/URL in the request.

## cache\_agent

    my $cache_agent = $ua->cache_agent;
    $ua->cache_agent(CHI->new(
          driver             => $ENV{SUA_CACHE_DRIVER}             || 'File',
          root_dir           => $ENV{SUA_CACHE_ROOT_DIR}           || '/tmp/startsiden-useragent-cache',
          serializer         => $ENV{SUA_CACHE_SERIALIZER}         || 'Storable',
          namespace          => $ENV{SUA_CACHE_NAMESPACE}          || 'SUA_Client',
          expires_in         => $ENV{SUA_CACHE_EXPIRES_IN}         // '1 minute',
          expires_on_backend => $ENV{SUA_CACHE_EXPIRES_ON_BACKEND} // 1,
    ));

Tells [Startsiden::UserAgent](https://metacpan.org/pod/Startsiden::UserAgent) which cache\_agent to use. It needs to be CHI-compliant and defaults to the above settings.

You may also set the `SUA_NOCACHE` environment variable to avoid caching at all.

## cache\_url\_opts

    my $urls_href = $ua->cache_url_opts;
    $ua->cache_url_opts({
        'https?://foo.com/long-lasting-data.*' => { expires_in => '2 weeks' }, # Cache some data two weeks
        '.*' => { expires_at => 0 }, # Don't store anything in cache
    });

Accepts a hash ref of regexp strings and expire times, this allows you to define cache validity time for individual URLs, hosts etc.
The first match will be used.

## logger

Provide a logging object, defaults to Mojo::Log

Example:
    Returning fetched 'https://graph.facebook.com?ids=http%3A%2F%2Fwww.abcnyheter.no%2Flivet%2F20...-lommebok&access\_token=705804969518861%7C0dd46c0e1a014e42dccb99b8c8f8ad94' => 200 for A.C.Facebook:133,185,183,A.M.F.ArticleList:19,9,A.M.Selector:47,A.Gonzo:167,responsive/modules/most-shared.html.tt:15,15,13,templates/inc/macros.tt:125,138,templates/responsive/frontpage.html.tt:10,10,16,Template:66,A.G.C.Article:338,147,A.Gonzo:417,main:14 (A.C.Facebook:68,E.C.Sandbox\_874:7,A.C.Facebook:133,,,main:14)

Format:
    Returning &lt;cache-status> '<URL>' => 'HTTP code' for &lt;request\_stacktrace> (&lt;created\_stacktrace>)

    cache-status: (cached|fetched|cached+expired)
    URL: the URL requested, shortened when it is really long
    request_stacktrace: Simplified stacktrace with leading module names shortened, also includes TT stacktrace support. Line numbers in the same module are grouped (order kept of course).
    created_stacktrace: Stack trace for creation of UA object, useful to see what options went in, and which object is used. Same format as normal stacktrace, but skips common parts.
                        Example:
                           created_stacktrace: A.C.Facebook:68,E.C.Sandbox_874:7,A.C.Facebook:133,<common part replaced>,main:14
                           stacktrace: A.C.Facebook:133,< common part: 185,183,A.M.F.ArticleList:19,9,A.M.Selector:47,A.Gonzo:167,responsive/modules/most-shared.html.tt:15,15,13,templates/inc/macros.tt:125,138,templates/responsive/frontpage.html.tt:10,10,16,Template:66,A.G.C.Article:338,147,A.Gonzo:417 >,main:14

## access\_log

A file that will get logs of every request, the format is a hybrid of Apache combined log, including time spent for the request.
If provided the file will be written to. Defaults to `$ENV{SUA_ACCESS_LOG} || ''` which means no log will be written.

## use\_expired\_cached\_content

Indicates that we will send expired, cached content back. This means that if a request fails, and the cache has expired, you
will get back the last successful content. Defaults to `$ENV{SUA_EXPIRED_CONTENT} // 1`

## accepted\_error\_codes

A list of error codes that should not be considered as errors. For instance this means that the client will not look for expired
cached content for requests that result in this response. Defaults to `$ENV{SUA_ACCEPTED_ERROR_CODES} || ''`

## sorted\_queries

Setting this to a true value will sort query parameters in the resulting URL. This means that requests will be identical if the key/value pairs
are the same. This helps when URLs have been built up using hashes that may have random orders.

# OVERRIDEN ATTRIBUTES

In addition [Startsiden::UserAgent](https://metacpan.org/pod/Startsiden::UserAgent) overrides the following [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) attributes.

## connect\_timeout

Defaults to `$ENV{MOJO_CONNECT_TIMEOUT} // 2`

## inactivity\_timeout

Defaults to `$ENV{MOJO_INACTIVITY_TIMEOUT} // 5`

## max\_redirects

Defaults to `$ENV{MOJO_MAX_REDIRECTS} // 4`

## request\_timeout

Defaults to `$ENV{MOJO_REQUEST_TIMEOUT} // 10`

# METHODS

[Startsiden::UserAgent](https://metacpan.org/pod/Startsiden::UserAgent) inherits all methods from [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) and
implements the following new ones.

## invalidate

    $ua->invalidate($key);

Deletes the cache of the given $key.

## expire

    $ua->expire($key);

Set the cache of the given $key as expired.

## set

    my $tx = $ua->build_tx(GET => "http://localhost:$port", ...);
    $tx = $ua->start($tx);
    my $cache_key = $ua->generate_key("http://localhost:$port", ...);
    $ua->set($cache_key, $tx);

Set function sets transmission data directly to cache.
It's mainly used in [Startsiden::UserAgent::Vipr](https://metacpan.org/pod/Startsiden::UserAgent::Vipr).

VideoList class fetches multiple video in single request to save bandwith,
then splits into single video and set to cache one by one.
Video can be requested individually by ID.

## generate\_key(@params)

Returns a key to be used for the cache agent. It accepts the same parameters
that a normal ->get() request does.

## validate\_key

    my $status = $ua4->validate_key('http://example.com');

Fast validates if key is valid in cache without doing fetch.
Return 1 if true.

## sort\_query($url)

Returns a string with the URL passed, with sorted query parameters suitable for cache lookup

# OVERRIDEN METHODS

## new

    my $ua = Startsiden::UserAgent->new( request_timeout => 1, ... );

Accepts the attributes listed above and all attributes from [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent).
Stores its own attributes and passes on the relevant ones when creating a
parent [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) object that it inherits from. Returns a [Startsiden::UserAgent](https://metacpan.org/pod/Startsiden::UserAgent) object

## get(@params)

    my $tx = $ua->get('http://example.com');

Accepts the same arguments and returns the same as [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent).

It will try to return a cached version of the $url, adhering to the set or default attributes.

If any of other arguments than the first one ($url) are given, caching is ignored.

In addition if a relative file path is given, it tries to return the file appended to
the attribute `local_dir`. In this case a fake [Mojo::Transaction::HTTP](https://metacpan.org/pod/Mojo::Transaction::HTTP) object is returned,
populated with a [Mojo::Message::Request](https://metacpan.org/pod/Mojo::Message::Request) with method and url, and a [Mojo::Message::Response](https://metacpan.org/pod/Mojo::Message::Response)
with headers, code and body set.

# ENVIRONMENT VARIABLES

SUA\_CLIENT\_WRITE\_LOCAL\_FILE\_RES\_DIR can be set to a directory to store a request in:

\# Re-usable local file with headers and metadata ends up at 't/data/drfront/lol/foo.html?bar=1'
$ENV{SUA\_CLIENT\_WRITE\_LOCAL\_FILE\_RES\_DIR}='t/data/drfront';
Startsiden::UserAgent->new->get("http://foo.com/lol/foo.html?bar=1");

# SEE ALSO

[Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent), [Mojolicious](https://metacpan.org/pod/Mojolicious), [Mojolicious::Guides](https://metacpan.org/pod/Mojolicious::Guides), [http://mojolicio.us](http://mojolicio.us).
