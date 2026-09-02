# gifts/server_template.cr
require "mcp"

def num(value : JSON::Any) : Float64
  value.as_f? || value.as_i64.to_f
end

server = MCP::Server.new(
  MCP::Implementation.new(name: "myservice-mcp", version: "0.1.0"),
  instructions: "MCP server for myservice. Replace the example registrations with real tools, resources and prompts."
)

server.tool("myservice_echo", description: "Echo text back",
  input_schema: {
    type:       "object",
    properties: {text: {type: "string", description: "Text to echo"}},
    required:   ["text"],
  },
  annotations: MCP::ToolAnnotations.new(read_only_hint: true, idempotent_hint: true, open_world_hint: false)) do |args, _ctx|
  args["text"]?.try(&.as_s) || ""
end

server.tool("myservice_divide", description: "Divide a by b; demonstrates structured output and domain errors",
  input_schema: {
    type:       "object",
    properties: {a: {type: "number"}, b: {type: "number"}},
    required:   ["a", "b"],
  },
  output_schema: {
    type:       "object",
    properties: {quotient: {type: "number"}},
    required:   ["quotient"],
  },
  annotations: MCP::ToolAnnotations.new(read_only_hint: true, idempotent_hint: true, open_world_hint: false)) do |args, _ctx|
  a = num(args["a"])
  b = num(args["b"])
  if b == 0.0
    MCP::CallToolResult.error("Division by zero: 'b' must be non-zero.")
  else
    quotient = a / b
    MCP::CallToolResult.new(
      content: [MCP::TextContent.new(quotient.to_s)] of MCP::ContentBlock,
      structured_content: MCP.to_any({quotient: quotient}))
  end
end

server.tool("myservice_tick", description: "Count steps with progress notifications; demonstrates progress and cancellation",
  input_schema: {
    type:       "object",
    properties: {steps: {type: "integer", minimum: 1, maximum: 100, default: 5, description: "Number of steps (1-100)"}},
  },
  annotations: MCP::ToolAnnotations.new(read_only_hint: true, open_world_hint: false)) do |args, ctx|
  steps     = (args["steps"]?.try(&.as_i64) || 5_i64).clamp(1_i64, 100_i64)
  i         = 0_i64
  cancelled = false
  while i < steps
    if ctx.cancelled?
      cancelled = true
      break
    end
    sleep 100.milliseconds
    i += 1
    ctx.report_progress(i.to_f64, steps.to_f64, "step #{i}/#{steps}")
  end
  if cancelled
    MCP::CallToolResult.error("Cancelled after #{i} of #{steps} steps")
  else
    "completed #{steps} steps"
  end
end

server.resource("myservice://info", name: "info", mime_type: "application/json",
  description: "Static information about this server") do |_ctx|
  MCP.to_any({service: "myservice", version: "0.1.0"}).to_json
end

server.resource_template("myservice://items/{id}", name: "item", mime_type: "application/json",
  description: "Fetch an item by ID") do |vars, _ctx|
  MCP.to_any({id: vars["id"], name: "item-#{vars["id"]}"}).to_json
end

server.prompt("myservice_summarize", description: "Summarize an item",
  arguments: [MCP::PromptArgument.new(name: "item_id", description: "Item ID", required: true)]) do |args, _ctx|
  [
    MCP::PromptMessage.user("Summarize item #{args["item_id"]? || "unknown"} in three bullet points."),
  ]
end

server.on_complete do |params, _ctx|
  case ref = params.ref
  in MCP::PromptReference
    ["1", "2", "42"].select(&.starts_with?(params.argument.value))
  in MCP::ResourceTemplateReference
    ["myservice://items/1", "myservice://items/2", "myservice://items/42"]
  end
end

if port = ENV["PORT"]?
  server.run_http(port: port.to_i)
else
  server.run_stdio
end
