# Smoke-test fixture: prompt_injection
#
# A Flask handler concatenates HTTP-supplied `question` directly into an OpenAI
# chat-completions prompt body with no instruction/data separation. The trust
# boundary is the request handler; the sink is the LLM prompt. A user can
# craft `question` to override the system prompt's instructions ("Ignore
# previous instructions and ..."), exfiltrate the system prompt, or pivot
# the assistant into producing arbitrary attacker-chosen output.
from flask import Flask, request
from openai import OpenAI

app = Flask(__name__)
client = OpenAI(api_key="sk-PLACEHOLDER-DO-NOT-USE")


@app.route("/ask")
def ask():
    question = request.args.get("question", "")

    # Prompt injection: user-controlled `question` is concatenated into the
    # message body with no separation from the assistant's system prompt.
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You are a customer-service bot. Only answer questions about Acme product returns."},
            {"role": "user", "content": "User asks: " + question},
        ],
    )

    return response.choices[0].message.content
