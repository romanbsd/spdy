#\ -E none -p 10040
#
# Trivial server which serves files from the current dir
# the server name is prepended to the pathname

require 'stringio'
require 'zlib'

class LocalFiles
  ROOT = Dir.getwd
  MIME_TYPES = {
    'gif' => 'image/gif',
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'html' => 'text/html',
    'js' => 'text/javascript',
    'css' => 'text/css'
    }.freeze

  def self.call(env)
    file = env['PATH_INFO']
    file = '/index.html' if file == '/' or file.empty?
    ext = file[/\.(\w+)$/, 1]
    ctype = (ext && MIME_TYPES[ext]) || 'text/plain'
    path = "#{ROOT}/#{env['SERVER_NAME']}#{file}"
    path += "?#{env['QUERY_STRING']}" unless env['QUERY_STRING'].empty?
#    $stderr.puts path
    if File.exist?(path)
      contents = File.read(path)
      headers = {'Content-Type' => ctype}
      if %w{text/html text/css text/javascript}.include?(ctype)
        strio = StringIO.new
        gz = Zlib::GzipWriter.new(strio)
        gz.write(contents)
        gz.close
        headers['Content-Encoding'] = 'gzip'
        contents = strio.string
      end
      contents.force_encoding('ASCII-8BIT')
      headers['Content-Length'] = contents.size.to_s
      [200, headers, [contents]]
    else
      $stderr.puts "\n*** NOT FOUND: #{path}"
      [404, {'Content-Type' => 'text/plain'}, ['Not found']]
    end
  end
end

use Rack::CommonLogger, File.open('access_log', 'a+')
run LocalFiles
