require 'webrick'
require 'erb'
require_relative 'magic'



# Define the document root where your HTML templates are located
document_root = File.expand_path('.', File.dirname(__FILE__))

server = WEBrick::HTTPServer.new(
  Port: 3000,
  DocumentRoot: document_root
)

# Mount a custom servlet to handle requests for the root path
server.mount_proc '/' do |req, res|
  @magic = Magic.new
  template_path = File.join(document_root, 'index.html.erb')
  template = ERB.new(File.read(template_path))
  res.body = template.result(binding) # Render the ERB template
  res['Content-Type'] = 'text/html'
end

# Handle server shutdown gracefully
trap 'INT' do
  server.shutdown
end

server.start
