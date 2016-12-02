FROM eu.gcr.io/divine-arcade-95810/perl:wheezy-node-4.6.0
MAINTAINER news-team@startsiden.no

COPY cpanfile .

RUN cpanm --notest --installdeps .

COPY . .

CMD true
