requires 'Algorithm::LCSS';
requires 'CHI';
requires 'Data::Serializer';
requires 'Devel::StackTrace';
requires 'Digest::SHA';
requires 'English';
requires 'File::Basename';
requires 'File::Path';
requires 'File::Spec';
requires 'List::Util', '1.42';
requires 'Mojolicious';
requires 'POSIX';
requires 'Readonly';
requires 'Socket';
requires 'String::Truncate';
requires 'Time::HiRes';

on build => sub {
    requires 'base', '2.23';
    requires 'Class::Unload';
    requires 'IO::Compress::Gzip';
    requires 'Module::Install::Debian';
    requires 'Module::Install';
    requires 'Test::Compile';
    requires 'Test::Harness', '3.36';
    requires 'Test::MockTime';
    requires 'Test::More';
    requires 'Time::HiRes';
};
