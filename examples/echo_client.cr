# examples/echo_client.cr
require "../src/mcp"

command = ARGV[0]? || "crystal"
args    = ARGV.size > 1 ? ARGV[1..] : ["run", "#{__DIR__}/echo_server.cr", "--"]

client = MCP::Client.connect_stdio(command, args: args,
  info: MCP::Implementation.new(name: "echo-client", version: "0.1.0"),
  capabilities: MCP::ClientCapabilities.create(elicitation_form: true, sampling: true))

discover = client.discover
puts "server: #{discover.meta.try(&.server_info).try(&.name) || "unknown"}"
puts "versions: #{discover.supported_versions.join(", ")}"
puts "instructions: #{discover.instructions}"

client.list_all_tools.each do |tool|
  puts "tool: #{tool.name} - #{tool.description}"
end

result = client.call_tool("add", arguments: {a: 2, b: 40})
puts "add(2, 40) = #{result.text}"

echo = client.call_tool("echo", arguments: {text: "hello mcp"}) do |progress|
  STDERR.puts "progress: #{progress.progress}"
end
puts "echo: #{echo.text}"

puts client.read_resource("file:///greeting.txt").contents.first.as(MCP::TextResourceContents).text
puts client.read_resource("file:///logs/2026-09-02.log").contents.first.as(MCP::TextResourceContents).text

prompt = client.get_prompt("greet", arguments: {"name" => "Crystal"})
prompt.messages.each do |message|
  puts "prompt message: #{message.content.as(MCP::TextContent).text}"
end

client.close
