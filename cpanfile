requires 'Algorithm::LCSS';
requires 'CHI';
requires 'Data::Serializer';
requires 'Devel::StackTrace';
requires 'English';
requires 'File::Basename';
requires 'File::Path';
requires 'File::Spec';
requires 'List::Util', '1.42';
requires 'Mojolicious', '5.82';
requires 'POSIX';
requires 'Readonly';
requires 'String::Truncate';
requires 'Time::HiRes';
requires 'perl', '5.010001';

on build => sub {
    requires 'ExtUtils::MakeMaker', '6.59';
    requires 'IO::Compress::Gzip';
    requires 'Module::Install';
    requires 'Test::More';
    requires 'Time::HiRes';
};