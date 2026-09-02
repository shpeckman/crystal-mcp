# spec/mcp_spec.cr
require "spec"
require "../src/mcp"

private def make_pair : Tuple(MCP::Server, MCP::Session, MCP::Client)
  srv_in, cli_out = IO.pipe
  cli_in, srv_out = IO.pipe

  server = MCP::Server.new(
    MCP::Implementation.new(name: "spec-server", version: "1.2.3"),
    instructions: "spec server")

  server.tool("add", description: "add two numbers") do |args, ctx|
    ctx.report_progress(0.5, 1.0)
    a = args["a"].as_i64
    b = args["b"].as_i64
    (a + b).to_s
  end

  server.tool("ask", description: "elicits input") do |args, ctx|
    result = ctx.session.elicit(MCP::ElicitFormParams.new(
      message: "who are you?",
      requested_schema: MCP::ElicitFormSchema.new(
        properties: {"name" => MCP::StringSchema.new.as(MCP::PrimitiveSchema)},
        required: ["name"])))
    content = result.content
    if result.action.accept? && content
      "hello #{content["name"]?}"
    else
      "no answer"
    end
  end

  server.resource("file:///hello.txt", name: "hello", mime_type: "text/plain") do |_ctx|
    "hi there"
  end

  server.resource_template("file:///items/{id}", name: "items", mime_type: "text/plain") do |vars, _ctx|
    "item #{vars["id"]}"
  end

  server.prompt("welcome", arguments: [MCP::PromptArgument.new(name: "who", required: true)]) do |args, _ctx|
    "Welcome #{args["who"]? || "stranger"}"
  end

  server_transport = MCP::IOTransport.new(srv_in, srv_out)
  server_session   = server.open_session(server_transport)

  client = MCP::Client.new(MCP::IOTransport.new(cli_in, cli_out),
    MCP::Implementation.new(name: "spec-client", version: "0.0.1"),
    capabilities: MCP::ClientCapabilities.create(elicitation_form: true))
  client.start

  {server, server_session, client}
end

describe MCP::Envelope do
  it "classifies requests" do
    env = MCP::Envelope.parse(%({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"x"}}))
    env.request?.should be_true
    env.notification?.should be_false
    env.response?.should be_false
    env.id.should eq 1_i64
  end

  it "classifies notifications" do
    env = MCP::Envelope.parse(%({"jsonrpc":"2.0","method":"notifications/tools/list_changed"}))
    env.notification?.should be_true
  end

  it "classifies result responses" do
    env = MCP::Envelope.parse(%({"jsonrpc":"2.0","id":"abc","result":{"resultType":"complete"}}))
    env.response?.should be_true
    env.id.should eq "abc"
  end

  it "classifies error responses" do
    env = MCP::Envelope.parse(%({"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"nope"}}))
    env.response?.should be_true
    env.error.not_nil!.code.should eq(-32601)
  end
end

describe MCP::ContentBlock do
  it "round-trips through the type discriminator" do
    blocks = [
      MCP::TextContent.new("hello"),
      MCP::ImageContent.new(data: "aGk=", mime_type: "image/png"),
      MCP::ToolUseContent.new(id: "t1", name: "tool"),
    ] of MCP::ContentBlock
    parsed = Array(MCP::ContentBlock).from_json(blocks.to_json)
    parsed.size.should eq 3
    parsed[0].should be_a(MCP::TextContent)
    parsed[1].should be_a(MCP::ImageContent)
    parsed[2].should be_a(MCP::ToolUseContent)
    parsed[0].as(MCP::TextContent).text.should eq "hello"
  end

  it "emits the type discriminator when serialized" do
    json = JSON.parse(MCP::TextContent.new("x").to_json)
    json["type"].as_s.should eq "text"
  end
end

describe MCP::RequestMeta do
  it "preserves unknown keys" do
    raw  = %({"progressToken":"tok","io.modelcontextprotocol/protocolVersion":"2026-07-28","com.example/custom":42})
    meta = MCP::RequestMeta.from_json(raw)
    meta.progress_token.should eq "tok"
    meta.protocol_version.should eq "2026-07-28"
    meta.extras["com.example/custom"].as_i64.should eq 42_i64
    JSON.parse(meta.to_json)["com.example/custom"].as_i64.should eq 42_i64
  end
end

describe "MCP over stdio-style pipes" do
  it "discovers, calls tools, reads resources and renders prompts" do
    _server, _session, client = make_pair

    discover = client.discover(5.seconds)
    discover.supported_versions.should contain MCP::PROTOCOL_VERSION
    discover.instructions.should eq "spec server"
    discover.capabilities.tools.should_not be_nil
    discover.capabilities.resources.should_not be_nil
    discover.capabilities.prompts.should_not be_nil

    tools = client.list_all_tools(5.seconds)
    tools.map(&.name).sort.should eq ["add", "ask"]

    progressed = Channel(Bool).new
    result = client.call_tool("add", arguments: {a: 20, b: 22}, timeout: 5.seconds) do |progress|
      progressed.send(progress.progress == 0.5)
    end
    result.error?.should be_false
    result.text.should eq "42"
    progressed.receive.should be_true

    contents = client.read_resource("file:///hello.txt", 5.seconds).contents
    contents.first.as(MCP::TextResourceContents).text.should eq "hi there"

    templated = client.read_resource("file:///items/7", 5.seconds).contents
    templated.first.as(MCP::TextResourceContents).text.should eq "item 7"

    prompt = client.get_prompt("welcome", arguments: {"who" => "crystal"}, timeout: 5.seconds)
    prompt.messages.first.content.as(MCP::TextContent).text.should eq "Welcome crystal"

    client.close
  end

  it "delivers list-changed notifications through a subscription" do
    server, _session, client = make_pair

    received = Channel(String).new(8)
    subscription = client.listen(MCP::SubscriptionFilter.all) do |method, _params|
      received.send(method)
    end
    sleep 100.milliseconds
    server.notify_tool_list_changed
    got : String? = nil
    8.times do
      method = received.receive
      if method == MCP::Methods::NOTIF_TOOLS_CHANGED
        got = method
        break
      end
    end
    got.should eq MCP::Methods::NOTIF_TOOLS_CHANGED
    subscription.cancel
    client.close
  end

  it "serves server-initiated elicitation requests" do
    _server, _session, client = make_pair

    client.on_elicitation do |params|
      case params
      in MCP::ElicitFormParams
        MCP::ElicitResult.accept({"name" => "crystal"})
      in MCP::ElicitURLParams
        MCP::ElicitResult.decline
      end
    end

    result = client.call_tool("ask", timeout: 5.seconds)
    result.text.should contain "hello"
    client.close
  end
end
