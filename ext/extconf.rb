#!/usr/bin/env ruby
require 'mkmf'

CONFIG['cleanobjs'] = 'net/spdy/*.o'
$CFLAGS << ' -Wall -DUSE_SYSTEM_ZLIB'

$srcs = Dir[File.join('net/spdy', "*.{#{SRC_EXT.join(%q{,})}}")]
$srcs += ['module.cc', 'em_setsockopt.c']
$objs = $srcs.collect {|file| file.sub(/\.cc?/, '.o')}

have_library('z')
have_library('stdc++')
create_makefile('Spdy')
