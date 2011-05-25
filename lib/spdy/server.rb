require 'singleton'
require 'eventmachine'
require 'spdy/session'

class Spdy::Server
  NAME = 'SpdyServer'
  attr_reader :connections

  def self.backend_class
    config.app ? Spdy::RackBackend : Spdy::Backend
  end

  def initialize(options = {})
    @connections = []
    self.class.config.app = options[:app]
    @host = options[:Host] || '0.0.0.0'
    @port = options[:Port] || Spdy::PORT
  end

  def start
    $stderr.puts "Starting server on port: #{@port} SSL: #{Spdy.ssl? ? 'ON' : 'OFF'}"
    @signature = EventMachine.start_server(@host, @port, Spdy::Session) do |conn|
      add_connection(conn)
      conn.server = self
    end
  end

  def stop
    EventMachine.stop_server(@signature)

    unless wait_for_connections_and_stop
      # Still some connections running, schedule a check later
      EventMachine.add_periodic_timer(1) { wait_for_connections_and_stop }
    end
  end

  def wait_for_connections_and_stop
    if idle?
      EventMachine.stop
      true
    else
      puts "Waiting for #{@connections.size} connection(s) to finish ..."
      false
    end
  end

  def idle?
    @connections.empty?
  end

  def add_connection(conn)
    @connections << conn
  end

  def remove_connection(conn)
    @connections.delete(conn)
  end

  # Configuration and settings storage
  class Configuration
    attr_accessor :proxy, :app
  end

  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield config
  end
end
