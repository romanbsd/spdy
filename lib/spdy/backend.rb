require 'em-http'

module EventMachine

  # Don't decode gzip/deflate
  module HttpDecoders
    class << self
      def decoder_for_encoding(enc)
        nil
      end
    end
  end

  # Monkey patch HttpRequest to support UNIX sockets
  class HttpRequest
    def send_request(&blk)
      begin
        unix_socket = @req.options.delete(:unix_socket)
        if unix_socket
          method = :connect_unix_domain
          args = [unix_socket, EventMachine::HttpClient]
        else
          method = :connect
          args = [@req.host, @req.port, EventMachine::HttpClient]
        end
        EventMachine.send(method, *args) { |c|
          c.uri = @req.uri
          c.method = @req.method
          c.options = @req.options
          c.comm_inactivity_timeout = @req.options[:timeout]
          c.pending_connect_timeout = @req.options[:timeout]
          blk.call(c) unless blk.nil?
        }
      rescue EventMachine::ConnectionError => e
        conn = EventMachine::HttpClient.new("")
        conn.on_error(e.message, true)
        conn.uri = @req.uri
        conn
      end
    end
  end
end


class Spdy::Backend
  def initialize(stream, request)
    @stream = stream

    #options = {:unix_socket => '/tmp/squid.sock'}
    options = {}
    options[:head] = request.headers
    options[:body] = request.body if request.post?

    if proxy = Spdy::Server.config.proxy
      host,port = proxy.match(%r{http://(.*?):(\d+)}) {|r| [r[1],r[2]]}
      options[:proxy] = {:host => host, :port => port.to_i, :head => request.headers}
    end

    @http = EventMachine::HttpRequest.new(request.url).send(request.method, options)

    @http.headers do |headers|
      @stream.on_headers(filter_headers(headers))
    end

    @http.stream do |chunk|
      @stream.on_data(chunk)
    end

    @http.callback do |http_client|
      @stream.on_eof
    end

    @http.errback do
      @stream.on_error @http.error
    end
  end

  # Cancel the ongoing backend transaction
  def cancel!(reason)
    @http.close(reason)
  end

  private
  def filter_headers(headers)
    hdrs = headers.inject(EventMachine::HttpResponseHeader.new) do |ac,kv|
      ac[kv[0].downcase.gsub('_', '-').gsub(%r{\b[a-z]}) {|letter| letter.upcase}] = kv[1]
      ac
    end
    hdrs.http_reason = headers.http_reason
    hdrs.http_status = headers.http_status
    if cookie = hdrs['Set-Cookie'] and cookie.respond_to?(:join)
      hdrs['Set-Cookie'] = cookie.join(', ')
    end
    hdrs.each {|k,v| hdrs[k] = v.first if v.respond_to?(:first)}
    # Remove junk headers
    hdrs.reject! {|hdr| hdr.start_with?('X-')}
    hdrs.reject! {|hdr| Spdy::REJECTED_HDRS.include? hdr}
    hdrs.reject! {|hdr,val| val.empty?}
    hdrs
  end
end
