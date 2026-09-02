# examples/http_server.cr
require "../src/mcp"

server = MCP::Server.new(
  MCP::Implementation.new(name: "http-demo-server", version: "0.1.0"))

server.tool("time", description: "Get the current UTC time") do |_args, _ctx|
  Time.utc.to_s
end

server.run_http(port: (ENV["PORT"]? || "3000").to_i)
