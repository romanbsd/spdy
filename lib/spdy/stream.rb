require 'spdy/backend'
require 'spdy/rack_backend'

class Spdy::Stream
  CHUNK_SIZE = 2048
  attr_reader :stream_id, :request

  def initialize(stream_id, request, session, backend_class = nil)
    @stream_id, @request, @session, @backend_class = stream_id, request, session, backend_class
    @upload_data = ''
    @data = ''.force_encoding('ASCII-8BIT')
    @eof = false
    @delayed_write_in_progress = false
    create_backend! if request and request.method == :get
  end

  def cancel!
    @backend.cancel!('Spdy::Stream cancelled') if @backend
  end

  ### Callbacks

  # From Spdy::Session
  def on_upload_data(data)
    if data
      @upload_data << data
    else
      if @request
        @request.body = @upload_data
        create_backend!
      else
        $stderr.puts "Buffer size: #{@upload_data.size}"
      end
    end
  end

  # From Spdy::Backend
  # headers should respond_to :http_status and :http_reason
  def on_headers(headers)
    @session.send_syn_reply(self, headers)
  end

  def on_data(chunk)
    chunk.force_encoding('ASCII-8BIT')
    # Spdy.logger.debug "Stream #{@stream_id} on_data #{chunk.size}"
    @data << chunk
    send_data
  end

  def on_eof
    if @data.size > 0
      @eof = true
    else
      @session.send_eof(self)
    end
  end

  def on_error(msg = 'unknown')
    Spdy.logger.error "Error in stream #{@stream_id}: #{msg}"
    @session.send_eof(self)
  end

  private
  def send_data
    # Spdy.logger.debug "Stream #{@stream_id} send_data (data=#{@data.size})"
    return if @data.empty?
    chunk = @data.slice!(0,CHUNK_SIZE)
    if @data.empty?
      @session.send_body(self, chunk, @eof)
    else
      unless @delayed_write_in_progress
        # Spdy.logger.debug "Stream #{@stream_id} enqueueing for next tick"
        @delayed_write_in_progress = true
        EM.next_tick do
          @delayed_write_in_progress = false
          send_data
        end
      end
      @session.send_body(self, chunk)
    end
  end

  def create_backend!
    return unless @backend_class
    @backend = @backend_class.new(self, @request) if @backend_class
  end
end