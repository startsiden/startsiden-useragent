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
requires 'Mojolicious', '7.07';
requires 'POSIX';
requires 'Readonly';
requires 'String::Truncate';
requires 'Time::HiRes';
requires 'Socket', '1.97';

on build => sub {
    requires 'Class::Unload';
    requires 'IO::Compress::Gzip';
    requires 'Module::Install::Debian';
    requires 'Module::Install';
    requires 'Test::Compile';
    requires 'Test::MockTime';
    requires 'Test::More';
    requires 'Time::HiRes';
};
