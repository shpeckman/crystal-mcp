# examples/echo_server.cr
require "../src/mcp"

server = MCP::Server.new(
  MCP::Implementation.new(name: "echo-server", version: "0.1.0"),
  instructions: "A small demo server exposing echo tools, resources and prompts."
)

server.tool("echo", description: "Echo back the provided text",
  input_schema: {
    type:       "object",
    properties: {text: {type: "string", description: "Text to echo"}},
    required:   ["text"],
  }) do |args, _ctx|
  args["text"]?.try(&.as_s) || ""
end

server.tool("add", description: "Add two numbers",
  input_schema: {
    type:       "object",
    properties: {a: {type: "number"}, b: {type: "number"}},
    required:   ["a", "b"],
  }) do |args, ctx|
  ctx.report_progress(1.0, 1.0)
  a = args["a"].as_f
  b = args["b"].as_f
  (a + b).to_s
end

server.resource("file:///greeting.txt", name: "greeting", mime_type: "text/plain") do |_ctx|
  "Hello from crystal-mcp!"
end

server.resource_template("file:///logs/{date}.log", name: "logs", mime_type: "text/plain") do |vars, _ctx|
  "Log contents for #{vars["date"]}"
end

server.prompt("greet", description: "Generate a greeting prompt",
  arguments: [MCP::PromptArgument.new(name: "name", required: true)]) do |args, _ctx|
  [
    MCP::PromptMessage.user("Please greet #{args["name"]? || "world"} warmly."),
  ]
end

server.on_complete do |params, _ctx|
  case ref = params.ref
  in MCP::PromptReference
    ["name"].select(&.starts_with?(params.argument.value))
  in MCP::ResourceTemplateReference
    ["file:///logs/2026-09-02.log"]
  end
end

server.run_stdio
