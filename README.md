This is the Relay 'ec' program.

ec is a Perl script whose purpose is to produces sets of 'entity counts' - the number of documents where a specified set of entities is mentioned. These can be broken down further by content source (medline/grants/clin  trials/patents) ,  by date range (per quarter, per year , or within a arbitrary date range). It can also be used to discover associations ; e g. enumerate the gene entities  or MeSH terms that occur in documents about a specific disease, or set of diseases. It can also be configured by a command line option to generate lists of document IDs rather than counts.

 

In the first release, output is in the form of tab delimited text files which can subdsequently be loaded into an RDBMS or Tableau.

ec uses a Perl interface to AIE's REST API to submit queries. 

A simple web interface ecweb is also available.
