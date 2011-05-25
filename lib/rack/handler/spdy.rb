require "rack"
base = File.expand_path(__FILE__ + '/../../../../')
require base + '/ext/Spdy'
$:.push(base + '/lib')
require 'spdy'
require 'spdy/server'

puts 'Loading...'
module Rack
  module Handler
    class Spdy
      def self.run(app, options={})
        options[:app] = app
#        ::Spdy::Server.config.ssl = true
        server = ::Spdy::Server.new(options)
        yield server if block_given?
        EventMachine.run {server.start}
      end
    end
  end
end
