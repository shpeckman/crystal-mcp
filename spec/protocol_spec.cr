# spec/protocol_spec.cr
require "spec"
require "../src/mcp"

describe MCP::DiscoverResult do
  it "serializes with required fields" do
    json = JSON.parse(MCP::DiscoverResult.new.to_json)
    json["resultType"].as_s.should eq "complete"
    json["supportedVersions"].as_a.should_not be_empty
    json["ttlMs"].as_i64.should eq 0_i64
  end
end

describe MCP::ElicitResult do
  it "accepts form content" do
    result = MCP::ElicitResult.accept({"name" => "crystal"})
    json   = JSON.parse(result.to_json)
    json["action"].as_s.should eq "accept"
    json["content"]["name"].as_s.should eq "crystal"
  end
end

describe MCP::Tool do
  it "round-trips" do
    tool = MCP::Tool.new(name: "add", description: "adder",
      input_schema: JSON.parse(%({"type":"object"})).as_h)
    parsed = MCP::Tool.from_json(tool.to_json)
    parsed.name.should eq "add"
    parsed.input_schema["type"].as_s.should eq "object"
  end
end

describe MCP::SubscriptionFilter do
  it "serializes camelCase keys" do
    json = JSON.parse(MCP::SubscriptionFilter.all.to_json)
    json["toolsListChanged"].as_bool.should be_true
    json["promptsListChanged"].as_bool.should be_true
  end
end

describe MCP::RpcError do
  it "carries code and message" do
    error = MCP::RpcError.new(MCP::ErrorCodes::INVALID_PARAMS, "bad")
    error.code.should eq(-32602)
    error.message.should eq "bad"
  end
end
