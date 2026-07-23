// Smoke-test fixture: tool_abuse
//
// An MCP server exposes a `write_file` tool to LLM clients with no
// authorization check, no path validation (so the LLM can write outside
// the working directory), and no confirmation step. Any client that
// connects to this MCP server can ask the assistant to overwrite any file
// the server process has permission to touch.

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { writeFileSync } from "fs";

const server = new McpServer({ name: "file-tools", version: "1.0.0" });

// Tool abuse: write_file accepts an arbitrary path and content. No
// allow-list of writable directories, no canonicalisation against a
// project root, no auth check on the calling LLM session.
server.tool(
  "write_file",
  {
    path: z.string().describe("Absolute or relative path to write to"),
    content: z.string().describe("Content to write to the file"),
  },
  async ({ path, content }) => {
    writeFileSync(path, content);
    return {
      content: [{ type: "text", text: `Wrote ${content.length} bytes to ${path}` }],
    };
  }
);

// Tool abuse: delete_file with the same pattern — arbitrary FS write.
server.tool(
  "delete_file",
  { path: z.string() },
  async ({ path }) => {
    const { unlinkSync } = await import("fs");
    unlinkSync(path);
    return { content: [{ type: "text", text: `Deleted ${path}` }] };
  }
);

await server.connect();
