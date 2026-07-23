// Smoke-test fixture: prompt_injection
//
// An Express handler concatenates HTTP-supplied `q` query-string parameter
// directly into an Anthropic Messages API prompt body with no
// instruction/data separation. Same shape as the Python fixture, different
// ecosystem — included so the rule pack is verified to detect agentic
// patterns in TypeScript code, not just Python.

import express, { Request, Response } from "express";
import Anthropic from "@anthropic-ai/sdk";

const app = express();
const client = new Anthropic({ apiKey: "sk-ant-PLACEHOLDER-DO-NOT-USE" });

app.get("/summarise", async (req: Request, res: Response) => {
  const query = (req.query.q ?? "") as string;

  // Prompt injection: `query` is user-controlled and is concatenated into
  // the user-role message body. An attacker who controls `q` can override
  // the system instruction or exfiltrate it.
  const message = await client.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 1024,
    system: "You are a documentation summariser. Summarise the user's query.",
    messages: [
      { role: "user", content: "Please summarise: " + query },
    ],
  });

  res.send(message.content);
});

app.listen(3000);
