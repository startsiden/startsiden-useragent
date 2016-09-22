FROM eu.gcr.io/divine-arcade-95810/perl:jessie
WORKDIR /root

COPY cpanfile .

# Set default pinto stack to "master". Can be overridden with build args
ARG PINTO_STACK
ENV PINTO_STACK ${PINTO_STACK:-master}

# Default options for cpanm
ENV PERL_CPANM_OPT --quiet --no-man-pages --skip-satisfied --mirror http://cpan.vianett.no/ --mirror http://admin:admin@pinto.startsiden.no/stacks/$PINTO_STACK

# Install third party deps
RUN cpanm --notest --installdeps .

# Install internal deps
RUN cpanm --notest --with-feature=own --installdeps .

# Bust the cache and reinstall internal deps
ADD https://www.random.org/strings/?num=16&len=16&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new /tmp/CACHEBUST
RUN cpanm --with-feature=own --reinstall --installdeps .

COPY . .

RUN dzil clean && dzil build
