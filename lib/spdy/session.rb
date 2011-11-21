require 'eventmachine'
require 'socket'
require 'spdy/request'
require 'spdy/server'


class Spdy::Session < EventMachine::Connection
  attr_accessor :server
  attr_reader :peer

  def initialize(*args)
    super
    @stream_id = 1
    @framer = Spdy::Framer.new(self)
    @streams = {}
  end

  def post_init
    set_sock_opt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 0)
    # no_delay = get_sock_opt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY).unpack('i').first
    # logger.debug "Nagle enabled: #{no_delay == 0}"
    start_tls if Spdy.ssl?
    peername = get_peername
    if peername
      @peer = Socket.unpack_sockaddr_in(peername).pop
      logger.info "Connection from: #{@peer}"
    end
  end

  def receive_data(data)
    logger.debug "receive_data #{data.size} bytes"
    res = @framer.process_input(data)
#    puts "process_input consumed #{res} bytes"
  end

  def unbind
    logger.info "Disconnected: #{@peer}"
    @server.remove_connection(self) if @server
  end

  # Responds to a SPDY SYN stream request
  # @param [Spdy::Stream] stream
  # @param [Hash] headers
  def send_syn_reply(stream, headers)
    headers['version'] = Spdy::HTTP_VERSION
    if headers.respond_to?(:http_status) and headers.respond_to?(:http_reason)
      headers['status'] = "#{headers.http_status} #{headers.http_reason}"
    else
      headers['status'] = '200 OK'
    end
    logger.debug "send_syn_reply (stream_id: #{stream.stream_id}) #{headers.inspect}"
    frame = @framer.create_syn_reply(stream.stream_id, Spdy::ControlFlags::NONE, compressed = true, headers)
#    puts "syn_rep size: #{frame.size}"
    send_data(frame.data)
  end

  # Creates a new SPDY stream in the current session
  # @param [String] url
  # @param [Hash] headers
  # @return [Stream] the created stream
  def send_syn_stream(url, headers, method = 'GET', assoc_stream_id = 0, priority = Spdy::Priority::DEFAULT)
    @stream_id += 2
    hdrs = headers.merge({'url'=>url, 'method' => method, 'version' => Spdy::HTTP_VERSION})
    frame = @framer.create_syn_stream(@stream_id, assoc_stream_id, priority, Spdy::ControlFlags::NONE, true, hdrs)
    stream = Spdy::Stream.new(@stream_id, nil, self)
    @streams[@stream_id] = stream
    send_data(frame.data)
    stream
  end

  def send_body(stream, body, eof=false)
    flags = eof ? Spdy::DataFlags::FIN : Spdy::DataFlags::NONE

    frame = @framer.create_data_frame(stream.stream_id, body, flags)
    logger.debug "data_frame (stream_id: #{stream.stream_id}) size: #{frame.size} flags: #{flags}"
    send_data(frame.data)
    @streams.delete(stream.stream_id) if flags == Spdy::DataFlags::FIN
  end

  def send_eof(stream)
    frame = @framer.create_data_frame(stream.stream_id, nil, Spdy::DataFlags::FIN)
    logger.debug "eof_frame (stream_id: #{stream.stream_id}) size: #{frame.size}"
    send_data(frame.data)
    @streams.delete(stream.stream_id)
  end

  protected
  def logger
    Spdy.logger
  end

  def set_sock_opt(level, option, value)
    EventMachine::set_sock_opt(@signature, level, option, value)
  end

  private
  # Callbacks from framer
  def new_stream(stream_id, headers)
    if @streams.has_key?(stream_id)
      logger.error "Duplicate stream: #{stream_id}"
      return
    end
    method = headers.delete('method')
    url = headers.delete('url')
    headers.delete('version')
    logger.debug "New stream: #{stream_id} #{method} #{url} #{headers}"
    options = {:headers => headers, :remote_addr => peer}
    request = Spdy::Request.new(method, url, options)
    stream = Spdy::Stream.new(stream_id, request, self, Spdy::Server.backend_class)
    @streams[stream_id] = stream
  rescue Exception => e
    $stderr.puts "Exception: #{e.inspect} #{e.backtrace.join("\n")}"
  end

  def remove_stream(stream_id)
    logger.debug "Removing stream: #{stream_id}"
    if stream = @streams.delete(stream_id)
      stream.cancel!
    end
  rescue Exception => e
    $stderr.puts "Exception: #{e.inspect} #{e.backtrace.join("\n")}"
  end

  def upload_data(stream_id, data)
#    $stderr.puts "Data on #{stream_id}: '#{data}'"
    stream = @streams[stream_id]
    unless stream
      logger.error "Data on non-existent stream: #{stream_id}"
      return
    end
    stream.on_upload_data(data)
  rescue Exception => e
    $stderr.puts "Exception: #{e.inspect} #{e.backtrace.join("\n")}"
  end

  def syn_reply(stream_id, headers)
    logger.debug "syn_reply (stream_id: #{stream_id}): #{headers.inspect}"
  end

  def framer_error(stream_id)
  end

end
