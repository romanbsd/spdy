require 'logger'

module Spdy
  PORT = 10040
  HTTP_VERSION = 'HTTP/1.1'
  # Headers which will be removed
  REJECTED_HDRS = ['Accept-Ranges', 'Connection', 'P3p', 'Ppserver',
    'Server', 'Transfer-Encoding', 'Vary']

  module ControlFlags
    NONE = 0
    FIN = 1
    UNIDIRECTIONAL = 2
  end

  module DataFlags
    NONE = 0
    FIN = 1
    COMPRESSED = 2
  end

  module Priority
    URGENT = 0
    HIGH = 1
    DEFAULT = 2
    LOW = 3
  end

  def self.ssl?
    @ssl
  end

  def self.ssl=(val)
    @ssl = val
  end

  LOG_FORMAT = "%s, [%s] %s\n"
  def self.logger
    @logger ||= begin
      logger = Logger.new(STDERR)
      logger.level = Logger::INFO
      logger.formatter = lambda {|severity, datetime, progname, msg|
        time = datetime.strftime("%H:%M:%S.") << "%06d" % datetime.usec
        LOG_FORMAT % [severity[0..0], time, msg]
      }
      logger
    end
  end
end

#require 'Spdy'
require 'spdy/session'
require 'spdy/stream'
Spdy.ssl = false
