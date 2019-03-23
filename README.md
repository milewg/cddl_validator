# CDDL tool

A parser, generator, and validator for CDDL, enhanced from [cddl 0.8.8 of Carsten Bormann](https://rubygems.org/gems/cddl/versions/0.8.8) implementation written in Ruby. This implmentation is based on the Internet drafts below. 

* draft-ietf-cbor-cddl-06
* draft-ietf-mile-jsoniodef-06(developing version), Appendix A. Data Types used in this document
developing version: https://github.com/milewg/draft-ietf-mile-jsoniodef/blob/master/draft-ietf-mile-jsoniodef-06.xml

## Setup

### Requirements
* [git](https://git-scm.com/)
* [ruby](https://www.ruby-lang.org/en/)
  * Ruby 2.5.X
  
### Recommandation Environment
* Windowns 10
* Ubuntu 16.04

### Install Ruby

* Windowns 10: [Download and install RubyInstallers](https://rubyinstaller.org/downloads/)
* Ubuntu 16.04: Can use the package management system of your distribution or third-party tools [rbenv](https://github.com/rbenv/rbenv) and [RVM](http://rvm.io/).

### Install gem which  was built in advance

Download and install https://github.com/TakeshiTakahashi/2018iodef-cbor/tree/master/cddl_validator/cddl-gem/cddl-0.8.8.gem

    $ gem install ./cddl-0.8.8.gem

### Re-build and install from source code

Download the enhanced source code of cddl tool at https://github.com/TakeshiTakahashi/2018iodef-cbor/tree/master/cddl_validator/cddl-0.8.8. Build and install as following:

    $ cd ~/cddl-0.8.8
    $ gem build cddl.gemspec
    $ gem install ./cddl-0.8.8.gem

### Data
Download sample input and cddl schema at https://github.com/TakeshiTakahashi/2018iodef-cbor/tree/master/cddl_validator/example and https://github.com/TakeshiTakahashi/2018iodef-cbor/blob/master/schema/cddl-schema.txt

### Usage

##### Validation JSON, CBOR against cddl-schema
Execution command

    $ cddl <cddl-schema-file> validate <input-file>

Parameters
- *cddl-schema-file*:  the cddl-schema
- *input-file*: data to validate against cddl-schema

Examples

    $ cddl cddl-schema.txt validate "Minimal Example CDDL.txt"

If input file completely matches with cddl schema, you will see the following output message
`[*** Ignoring .default for now.]`

##### Check format JSON, CBOR
Execution command

    $ cddl formatcheck-json <input-file>
    $ cddl formatcheck-cbor <input-file>
    $ cddl formatcheck-cddl <input-file>

Parameters
- *input-file*: data to check format

Examples

    $ cddl formatcheck-json aaa.json

If format of input file is valid, you will see the following output message
`Format of file aaa.json is valid`