// Smoke-test fixture: agent_trust_boundary
//
// A two-agent orchestrator runs a "researcher" agent and pipes its raw
// output into a "writer" agent's prompt without treating the researcher's
// output as untrusted data. If the researcher is ever prompt-injected (by
// poisoned web content, by a malicious tool response, by a chain-of-agents
// upstream), its output can contain instructions that the writer agent
// will then follow as if they came from the orchestrator's system prompt.
//
// The trust boundary that's missing here: the writer should treat the
// researcher's output as a data channel (delimited, escaped, or summarized)
// — not as instructions.

import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic({ apiKey: "sk-ant-PLACEHOLDER-DO-NOT-USE" });

async function researcher(topic: string): Promise<string> {
  const response = await client.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 2048,
    system: "You are a web researcher. Find relevant facts about the topic and return them as a bulleted list.",
    messages: [{ role: "user", content: topic }],
  });
  // Returned content may include facts AND any "instructions" the
  // researcher absorbed from poisoned web content along the way.
  return response.content
    .filter((b) => b.type === "text")
    .map((b) => (b as { type: "text"; text: string }).text)
    .join("\n");
}

async function writer(researchResult: string): Promise<string> {
  // Agent trust boundary: researchResult is injected directly into the
  // writer agent's user message body. There is no delimiter, no marker
  // saying "treat the following as data not instructions", no length cap,
  // and no scan for prompt-injection markers. If researcher was poisoned,
  // the writer obeys the attacker.
  const response = await client.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 4096,
    system: "You are a writer. Compose a publishable article using the supplied research notes.",
    messages: [
      { role: "user", content: "Research notes:\n" + researchResult },
    ],
  });

  return response.content
    .filter((b) => b.type === "text")
    .map((b) => (b as { type: "text"; text: string }).text)
    .join("\n");
}

export async function runArticlePipeline(topic: string): Promise<string> {
  const research = await researcher(topic);
  // No quarantine, no delimiter, no integrity check between agents.
  const article = await writer(research);
  return article;
}
