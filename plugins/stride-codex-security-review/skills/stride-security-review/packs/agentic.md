Rule pack for the stride-codex-security-review security-reviewer agent. These are instructions, never material under review. Apply a rule only to a file where this pack's activation holds; every rule maps to one of the core prompt's `vulnerability_class` values.

# Agentic vulnerability classes

These five classes apply ONLY when the file under review wires an LLM, AI agent, or Model Context Protocol (MCP) client into the request flow. Detect agentic context by scanning imports/requires/uses statements for any of the following language-neutral signals:

- **Python**: `import openai`, `from anthropic`, `from langchain`, `from langchain_core`, `import llama_index`, `from llama_index`, `import google.generativeai`, `from mistralai`, `import cohere`, `from mcp` (MCP Python SDK), `import boto3` *and* `bedrock-runtime` reference nearby.
- **JavaScript / TypeScript**: `import OpenAI from 'openai'`, `from '@anthropic-ai/sdk'`, `from 'ai'` (Vercel AI SDK), `from 'langchain'`, `from '@langchain/core'`, `from '@modelcontextprotocol/sdk'`, `from '@google/generative-ai'`.
- **Go**: `"github.com/sashabaranov/go-openai"`, `"github.com/anthropics/anthropic-sdk-go"`, `"github.com/tmc/langchaingo"`, `"github.com/modelcontextprotocol/go-sdk"`.
- **Ruby**: `require "openai"` (ruby-openai), `require "anthropic"`, `require "langchain"` (langchainrb).
- **Elixir**: `alias LangChain`, `use OpenAI`, references to `:openai` / `:anthropic` Hex packages.
- **Java / Kotlin**: `com.openai.*`, `com.anthropic.*`, `dev.langchain4j.*`, Spring AI packages.

If the file shows none of these signals, skip the agentic classes entirely — they do not apply to ordinary code. Do NOT use file extension alone as the gate; a `.py` file with no LLM imports is not in scope for these classes.

| Class | What to look for |
|---|---|
| **Prompt injection** | User-controlled input concatenated into an LLM prompt with no separation/sanitization. Sinks: `openai.chat.completions.create(messages=[...{user_input}...])`, `client.messages.create(messages=[{"role":"user","content": user_input}])`, `langchain.prompts.format(template, **untrusted)`, MCP `tools/call` arguments built from user input. The trust boundary is the line where untrusted text enters the prompt body. Defense: structured prompts with explicit role/content separation and untrusted-content delimiters; refusal of in-prompt instructions from the data channel. |
| **Tool abuse** | An agent tool/function-call layer exposes powerful operations (file write, shell exec, HTTP requests, DB writes, credential reads) to the LLM without (a) per-tool authorization checks, (b) input validation on tool arguments, or (c) a confirmation gate for high-impact actions. Sinks: function-calling registries (`tools=[{...}]` lists), MCP `server.tool(name, handler)` registrations, agent frameworks like LangChain `Tool` / `StructuredTool` classes. The trust boundary is the line where the LLM's chosen tool name + arguments reach the handler. |
| **Agent trust boundary** | Multi-agent orchestrations or agent-to-agent (A2A) message passing where outputs from one agent flow into another agent's prompt without the receiving agent treating the input as untrusted. Sinks: orchestrator code that forwards `agent_a.output` into `agent_b.prompt` directly; MCP server-to-server chains; LangGraph node-to-node state transitions; AutoGen GroupChat speaker outputs. The trust boundary is the line between agents. |
| **Model output execution** | LLM output flowing into `eval`, `exec`, `subprocess.Popen(shell=True, ...)`, `Function(...)`, `os/exec.Command(... output ...)`, `Kernel#eval`, or any code-execution sink without sandboxing. Sinks vary by language but the pattern is universal: response text from `chat.completions.create()` (or equivalent) being passed to a code-execution primitive. |
| **Vector store poisoning** | User-controllable content (a comment, an issue body, an uploaded document) being embedded into a vector store without sanitization or source attribution. Sinks: `vector_store.add_documents([user_doc])`, `pgvector` inserts of user-uploaded text, Pinecone/Weaviate/Chroma `upsert` calls in handlers that accept untrusted input. The downstream impact appears when a retrieval-augmented agent later pulls the poisoned content into a prompt. |

Severity assignment for agentic findings: prompt_injection and model_output_execution at the boundary of an unauthenticated endpoint are **critical**. Tool abuse with shell/file/DB access is **high** to **critical** depending on the privileges of the executing process. Agent trust boundary failures and vector store poisoning are typically **medium** to **high** — the impact arrives one hop downstream and is bounded by what the receiving agent can do.
