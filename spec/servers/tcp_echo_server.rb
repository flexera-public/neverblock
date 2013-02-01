require 'rubygems'
require 'eventmachine'

module EchoServer
  def post_init
    send_data "hi"
  end

  def receive_data data
    EM.add_timer(0.1) {
      send_data "#{data}"
      close_connection if data =~ /quit/i
    }
  end

  def unbind

  end
end

trap "INT" do
  EM.stop
end

EventMachine::run {
  
  EventMachine::start_server "0.0.0.0", 8080, EchoServer
  
#  EM.add_timer(1) { EM.stop }

}
