require_relative "../lib/neverblock"

EM.error_handler do |e|
  raise e
end

NB.logger = Logger.new("/dev/null")

class TestServer

  
  def initialize server
    path = File.expand_path("../servers/#{server}.rb",__FILE__)
    @pid = spawn("ruby #{path}")
  end

  def stop
    Process.kill "INT", @pid
  end

end


class TestHTTPServer


  def initialize server
    path = File.expand_path("../servers/#{server}",__FILE__)
    @pid = spawn("thin -R #{path}.ru -p 8080 start")
  end

  def stop
    Process.kill "KILL", @pid
  end

  


end

