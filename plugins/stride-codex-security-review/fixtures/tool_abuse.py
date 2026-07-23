# Smoke-test fixture: tool_abuse
#
# A LangChain agent is given a `run_shell` tool that executes arbitrary shell
# commands chosen by the LLM. There's no per-tool authorization gate, no
# input validation, no allow-list of safe commands, and no confirmation
# step. An attacker who can influence the LLM's input (via prompt injection
# or a poisoned RAG context) can ask the agent to run any shell command —
# including reading files, exfiltrating data, or pivoting to the host.
import subprocess

from langchain.agents import AgentExecutor, create_react_agent
from langchain.tools import StructuredTool
from langchain_openai import ChatOpenAI


def run_shell(command: str) -> str:
    """Run a shell command and return its output."""
    # Tool abuse: no validation, no allow-list, no auth check, shell=True.
    # The LLM can call this with any string and the process executes it.
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    return result.stdout + result.stderr


def read_file(path: str) -> str:
    """Read the contents of an arbitrary file from disk."""
    # Tool abuse: arbitrary file read by LLM choice.
    with open(path) as f:
        return f.read()


tools = [
    StructuredTool.from_function(run_shell),
    StructuredTool.from_function(read_file),
]

llm = ChatOpenAI(model="gpt-4o-mini", api_key="sk-PLACEHOLDER")
agent = create_react_agent(llm, tools, prompt="You are a helpful assistant.")
executor = AgentExecutor(agent=agent, tools=tools)

# Anywhere a user-controlled string flows into `executor.invoke({"input": ...})`,
# the LLM can choose to call run_shell or read_file with attacker-chosen args.
