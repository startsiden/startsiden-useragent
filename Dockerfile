FROM eu.gcr.io/divine-arcade-95810/perl:jessie
MAINTAINER news-team@startsiden.no

WORKDIR /root

COPY cpanfile .

# Default options for cpanm
ENV PERL_CPANM_OPT --quiet --no-man-pages --skip-satisfied --mirror http://cpan.vianett.no/ --mirror http://admin:admin@pinto.abct.no:5000/

# Install third party deps
RUN cpanfile-dump | cpanm --notest

# Install internal deps
RUN cpanfile-dump --with-feature=own | cpanm --notest

# Bust the cache and reinstall internal deps
ADD https://www.random.org/strings/?num=16&len=16&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new /tmp/CACHEBUST
RUN cpanfile-dump --with-feature=own | cpanm --reinstall

COPY . .

RUN dzil clean && dzil build
