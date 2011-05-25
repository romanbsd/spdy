require 'uri'
require 'stringio'

class Spdy::Request
  attr_reader :method, :url

  PATH_INFO         = 'PATH_INFO'.freeze
  QUERY_STRING      = 'QUERY_STRING'.freeze
  REQUEST_METHOD    = 'REQUEST_METHOD'.freeze
  SERVER_NAME       = 'SERVER_NAME'.freeze
  SERVER_PORT       = 'SERVER_PORT'.freeze
  SERVER_SOFTWARE   = 'SERVER_SOFTWARE'.freeze
  HTTP_VERSION      = 'HTTP_VERSION'.freeze
  REMOTE_ADDR       = 'REMOTE_ADDR'.freeze

  # Freeze some Rack header names
  RACK_INPUT        = 'rack.input'.freeze
  RACK_VERSION      = 'rack.version'.freeze
  RACK_ERRORS       = 'rack.errors'.freeze
  RACK_MULTITHREAD  = 'rack.multithread'.freeze
  RACK_MULTIPROCESS = 'rack.multiprocess'.freeze
  RACK_RUN_ONCE     = 'rack.run_once'.freeze
  RACK_SCHEME       = 'rack.url_scheme'.freeze
  ASYNC_CALLBACK    = 'async.callback'.freeze
  ASYNC_CLOSE       = 'async.close'.freeze

  # For authorization:
  # options[:headers]['authorization'] = ['user', 'pass']
  def initialize(method, url, options)
    @method = method.downcase.intern
    @url = url.gsub(%r{(?<!:)/+}, '/')
    @options = options
    @env = {
      REQUEST_METHOD    => method,
      SERVER_SOFTWARE   => Spdy::Server::NAME,
      HTTP_VERSION      => Spdy::HTTP_VERSION,
      REMOTE_ADDR       => options[:remote_addr],

      # Rack stuff
      RACK_VERSION      => [1,1],
      RACK_ERRORS       => STDERR,
      RACK_SCHEME       => 'http',
      RACK_MULTITHREAD  => true,
      RACK_MULTIPROCESS => false,
      RACK_RUN_ONCE     => false
    }
  end

  def post?
    @method == :post
  end

  def headers
    @options[:headers]
  end

  def body
    @options[:body]
  end

  def body=(data)
    @options[:body] = data.respond_to?(:force_encoding) ? data.force_encoding('ASCII-8BIT') : data
  end

  def env
    # Lazily prepare environment. Don't waste CPU when it's not a Rack application
    unless @prepared
      uri = URI.parse(@url)
      @env.merge!({
        SERVER_NAME       => uri.host || 'localhost',
        SERVER_PORT       => uri.port.to_s,
        PATH_INFO         => uri.path,
        QUERY_STRING      => uri.query || '',
        RACK_INPUT        => StringIO.new(body || ''.force_encoding('ASCII-8BIT'))
      })
      headers.each do |k,v|
        key = k.gsub('-', '_').upcase
        unless key == 'CONTENT_TYPE' || key == 'CONTENT_LENGTH'
          key = 'HTTP_' + key
        end
        @env[key] = v
      end
      @prepared = true
    end
    @env
  end
end
