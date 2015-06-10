#!/bin/env perl
#
# class hierarchy to manage the filter definitions for ec.
# we define a base class EC::FIlter then subclasses
# This replaces all the arrays/hashes that ConfigQueryParser and fiends use
# with something a bit more maintainable
#
package ECFilters;
{
use strict;
use 5.012;
use Moose;

    has 'fields', is => 'rw', isa => 'ArrayRef[Str]',default => sub {[]};
    has 'colhead', is => 'rw', isa =>'Str';
    has 'alias', is => 'rw', isa => 'Str' ;
    has  'nvalues', is=>'rw', isa => 'Int';
    has 'inputtext', is=>'rw', isa =>'String';

}
package ECFilters::Fulltext;
{
use Moose;

   extends 'ECFilters';
   
   has 'fieldtype', is => 'ro', isa => 'Str', default => sub{ return 'fulltext'};
   
}
#####
# entity (or indeed other)  fields for which we do a simple text match
package ECFilters::StringField;
{
use Moose;
    
   extends 'ECFilters';
   
   has 'fieldtype' ,is => 'ro', isa => 'Str', default => sub {"stringfield"};
   
}
#####   
package ECFilters::Source;
{
use Moose;

   extends 'ECFilters';
   
   has 'fieldtype' => (is => 'ro', isa => 'Str', default => sub{'source'});
   
  # sub Build {  }
}
######   
package ECFilters::Date;
{
use Moose;

   extends 'ECFilters';
   
   has 'fieldtype' => (is => 'ro', isa => 'Str', default => sub{'date'});
}
######   
package ECFilters::Tags;
{
use Moose;

   extends 'ECFilters';
   
   has 'fieldtype' => (is => 'ro', isa => 'Str', default => sub{'tag'});
############
}
1;   
