class Spdy::RackBackend
  class Headers < Hash
    attr_accessor :http_status, :http_reason
  end

  def initialize(stream, request)
    @stream = stream
    @app = Spdy::Server.config.app

    status, headers, body = @app.call(request.env)
    hdrs = Headers[headers]
    hdrs.http_status = status
    hdrs.http_reason = (status >= 200 && status < 400) ? 'OK' : 'ERROR'

    @stream.on_headers(hdrs)

    if body.respond_to?(:each)
      body.each do |chunk|
        @stream.on_data(chunk)
      end
    else
      while chunk = body.slice!(0,4096) and chunk.length > 0
        @stream.on_data(chunk)
      end
    end
    @stream.on_eof
  end

  # Cancel the ongoing backend transaction
  def cancel!(reason)
    # TODO
  end

end
