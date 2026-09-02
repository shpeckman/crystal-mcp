# spec/http_spec.cr
require "spec"
require "../src/mcp"

describe "MCP over Streamable HTTP" do
  it "discovers, calls tools and streams subscription notifications" do
    server = MCP::Server.new(MCP::Implementation.new(name: "http-spec-server", version: "0.1.0"))
    server.tool("mul", description: "multiply") do |args, _ctx|
      a = args["a"].as_i64
      b = args["b"].as_i64
      (a * b).to_s
    end

    spawn server.run_http(port: 39211)
    sleep 200.milliseconds

    client = MCP::Client.connect_http("http://127.0.0.1:39211/mcp",
      info: MCP::Implementation.new(name: "http-spec-client", version: "0.1.0"))

    discover = client.discover(5.seconds)
    discover.supported_versions.should contain MCP::PROTOCOL_VERSION

    result = client.call_tool("mul", arguments: {a: 6, b: 7}, timeout: 5.seconds)
    result.text.should eq "42"

    received = Channel(String).new(8)
    subscription = client.listen(MCP::SubscriptionFilter.new(tools_list_changed: true)) do |method, _params|
      received.send(method)
    end
    sleep 300.milliseconds
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
end
