# src/mcp/version.cr
module MCP
  VERSION                     = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
  PROTOCOL_VERSION            = "2026-07-28"
  SUPPORTED_PROTOCOL_VERSIONS = [PROTOCOL_VERSION]

  RESULT_TYPE_COMPLETE       = "complete"
  RESULT_TYPE_INPUT_REQUIRED = "input_required"

  CACHE_SCOPE_PUBLIC  = "public"
  CACHE_SCOPE_PRIVATE = "private"
end
