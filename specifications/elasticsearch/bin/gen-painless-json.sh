#!/usr/bin/perl 

use strict;
use warnings;

if (@ARGV != 2) {
  die "Usage: $0 <template_file> <content_file>";
}

my $template_file = shift @ARGV;
my $content_file = shift @ARGV;

open(TEMPLATE, "<", $template_file) || die "Error opening template file: $!";
open(CONTENT, "<", $content_file) || die "Error opening content file: $!";

my $content = "";

while (<CONTENT>) {
  chomp; # Remove trailing newline (optional if content file has proper line endings)
    # Escape quotes in content
  s/([\"\\])/\\$1/g;      # quote any double quotes with a backslash
  s/\t/    /g;            # no tabs allowed in json
  s/\/\/.*$//g;            # remove single line comments
  $content .= $_ . " "; # Append content without modifying line breaks
}


while (<TEMPLATE>) {
  chomp; # Remove trailing newline
  if ($_ =~ /PAINLESS/) {
    print s/PAINLESS/$content/gr; 
    print "\n" # Substitute with escaped content and newline
  } else {
    print "$_\n"; # Print the line as is
  }
}

close TEMPLATE;
close CONTENT;
