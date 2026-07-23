# Smoke-test fixture: model_output_execution
#
# An OpenAI chat-completion response is interpreted as Python code and
# passed directly to `exec()`. The LLM's output crosses a code-execution
# trust boundary with no sandboxing, no validation, no syntactic
# allow-list. An attacker who can influence the LLM (via prompt injection
# in `task_description`, a poisoned RAG context, or a compromised tool
# response) can land arbitrary code execution in the host process.
#
# This pattern shows up in "let the LLM write Python and run it"
# data-analysis assistants and ReAct-style agents where the agent emits
# code and the harness blindly evaluates it.
from openai import OpenAI

client = OpenAI(api_key="sk-PLACEHOLDER-DO-NOT-USE")


def run_analysis(task_description: str) -> str:
    """Ask the LLM to write Python that performs the analysis, then exec it."""
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {
                "role": "system",
                "content": "You are a data-analysis assistant. Reply with ONLY a Python snippet that performs the requested task. Do not include explanations.",
            },
            {"role": "user", "content": task_description},
        ],
    )

    generated_code = response.choices[0].message.content

    # Model output execution: the LLM's response is exec'd in this
    # process's globals without sandboxing, without an AST check, without
    # an allow-list of safe builtins. Any code path the LLM produces
    # (or that an attacker tricks the LLM into producing) executes here.
    local_ns: dict = {}
    exec(generated_code, {"__builtins__": __builtins__}, local_ns)

    return local_ns.get("result", "")
