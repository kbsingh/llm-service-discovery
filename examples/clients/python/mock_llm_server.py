#!/usr/bin/env python3
"""
Mock LLM Server - For testing DNS-based discovery
Simulates an OpenAI-compatible LLM API endpoint
"""

from flask import Flask, request, jsonify
import argparse
import logging
from datetime import datetime, timezone

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@app.route('/health', methods=['GET'])
@app.route('/healthz', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()})


@app.route('/v1/messages', methods=['POST'])
@app.route('/v1/chat/completions', methods=['POST'])
def chat_completion():
    """Mock chat completion endpoint (provider1/OpenAI compatible)"""
    data = request.get_json()

    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    messages = data.get('messages', [])
    model = data.get('model', 'mock-model')

    if not messages:
        return jsonify({"error": "No messages provided"}), 400

    # Get the last user message
    user_message = next((m['content'] for m in reversed(messages) if m['role'] == 'user'), None)

    logger.info(f"Received chat request: model={model}, message='{user_message}'")

    # Mock response
    response = {
        "id": "mock-completion-123",
        "object": "chat.completion",
        "created": int(datetime.now(timezone.utc).timestamp()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": f"[MOCK RESPONSE] You said: {user_message}. This is a mock LLM server for testing DNS discovery."
                },
                "finish_reason": "stop"
            }
        ],
        "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 20,
            "total_tokens": 30
        }
    }

    return jsonify(response)


@app.route('/v1/embeddings', methods=['POST'])
def embeddings():
    """Mock embeddings endpoint"""
    data = request.get_json()

    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    input_text = data.get('input', '')
    model = data.get('model', 'mock-embedding-model')

    logger.info(f"Received embedding request: model={model}, input_length={len(input_text)}")

    # Mock embedding (384 dimensions of zeros)
    mock_embedding = [0.0] * 384

    response = {
        "object": "list",
        "data": [
            {
                "object": "embedding",
                "index": 0,
                "embedding": mock_embedding
            }
        ],
        "model": model,
        "usage": {
            "prompt_tokens": len(input_text.split()),
            "total_tokens": len(input_text.split())
        }
    }

    return jsonify(response)


@app.route('/v1/completions', methods=['POST'])
def completion():
    """Mock completion endpoint (non-chat)"""
    data = request.get_json()

    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    prompt = data.get('prompt', '')
    model = data.get('model', 'mock-model')

    logger.info(f"Received completion request: model={model}, prompt='{prompt[:50]}...'")

    response = {
        "id": "mock-completion-456",
        "object": "text_completion",
        "created": int(datetime.now(timezone.utc).timestamp()),
        "model": model,
        "choices": [
            {
                "text": f"[MOCK] Completion for: {prompt}",
                "index": 0,
                "finish_reason": "stop"
            }
        ]
    }

    return jsonify(response)


@app.route('/', methods=['GET'])
def root():
    """Root endpoint with service info"""
    return jsonify({
        "service": "Mock LLM Server",
        "version": "1.0.0",
        "purpose": "DNS SRV discovery testing",
        "endpoints": [
            "/health",
            "/v1/messages",
            "/v1/chat/completions",
            "/v1/embeddings",
            "/v1/completions"
        ]
    })


def main():
    parser = argparse.ArgumentParser(description='Mock LLM Server for DNS Discovery Testing')
    parser.add_argument('--port', type=int, default=3000, help='Port to listen on')
    # Loopback by default: this is a local test tool, not something to
    # expose to the network
    parser.add_argument('--host', default='127.0.0.1', help='Host to bind to (default: 127.0.0.1)')
    parser.add_argument('--debug', action='store_true', help='Enable Flask debug mode')

    args = parser.parse_args()

    if args.debug and args.host not in ('127.0.0.1', 'localhost', '::1'):
        logger.warning(
            "--debug enables the Werkzeug debugger, which allows ARBITRARY "
            "CODE EXECUTION from anyone who can reach the server. Combining "
            "it with a non-loopback --host is dangerous."
        )

    logger.info(f"Starting Mock LLM Server on {args.host}:{args.port}")
    logger.info("Available endpoints:")
    logger.info("  - GET  /health")
    logger.info("  - POST /v1/messages")
    logger.info("  - POST /v1/chat/completions")
    logger.info("  - POST /v1/embeddings")
    logger.info("  - POST /v1/completions")
    logger.info("")
    logger.info("Test with:")
    logger.info(f"  curl http://localhost:{args.port}/health")
    logger.info(f"  python llm_discovery_client.py --dns-port 5353")

    app.run(host=args.host, port=args.port, debug=args.debug)


if __name__ == '__main__':
    main()
