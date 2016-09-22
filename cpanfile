requires 'Algorithm::LCSS';
requires 'CHI';
requires 'Data::Serializer';
requires 'Devel::StackTrace';
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

on build => sub {
    requires 'Class::Unload';
    requires 'ExtUtils::Config';
    requires 'ExtUtils::Helpers';
    requires 'ExtUtils::InstallPaths';
    requires 'ExtUtils::MakeMaker', '6.59';
    requires 'IO::Compress::Gzip';
    requires 'Module::Install::Debian';
    requires 'Module::Install';
    requires 'Test::Compile';
    requires 'Test::MockTime';
    requires 'Test::More';
    requires 'Time::HiRes';
};
