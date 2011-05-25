SPDY daemon
===========

This is a wrapper around the original Google's [SPDY][1] Framer.
It includes a standalone server (spdyd) which can act as a SPDY-HTTP proxy (or use yet another HTTP proxy)
as well as a [Rack][2] adapter.
The server is built around [Eventmachine][3], and should be pretty fast.


Installation:
-------------

### Gem

1. gem build spdy.gemspec
2. sudo gem install ./spdy-0.1.gem

### Manual

1. gem install eventmachine em-http-request
2. Optional, for daemonization: gem install daemons
3. cd ext; ruby extconf.rb; make


Running standalone server:
--------------------------

Running it standalone is as simple as:

    bin/spdyd

Check `bin/spdyd -h` for options.


Rack:
-----

You can also run it as a rack server:

    rack -s Spdy examples/local.ru

or for Rails application:

    rack -s Spdy config.ru


TODO:
-----

* Integrate with npn-enabled openssl which can be built using these steps:
https://gist.github.com/944386


[1]: http://mbelshe.github.com/SPDY-Specification/draft-mbelshe-spdy-00.xml
[2]: http://rack.rubyforge.org/
[3]: http://rubyeventmachine.com/

Copyright 2010 (c) Roman Shterenzon, released under the AGPLv3 license.
