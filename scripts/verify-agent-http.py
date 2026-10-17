#!/usr/bin/env python3
"""Exercise the real HTTP adapter against a local, deterministic provider.

No real API key, model, user documents, or external network is used.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import subprocess
import threading


class Provider(BaseHTTPRequestHandler):
    stolen_requests = 0

    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.path == '/stolen':
            Provider.stolen_requests += 1
        if self.headers.get('Authorization') != 'Bearer qizhi-fixture-key-not-a-secret':
            self.send_error(403)
            return
        size = int(self.headers.get('Content-Length', 0))
        if not 0 < size < 100_000:
            self.send_error(413)
            return
        payload = json.loads(self.rfile.read(size))
        assert payload['model'] == 'fixture-model'
        assert {x['function']['name'] for x in payload['tools']} == {'read_source', 'submit_cards'}
        if self.path == '/auth':
            self.send_error(401)
            return
        if self.path == '/quota':
            self.send_error(429)
            return
        if self.path == '/redirect':
            self.send_response(307)
            self.send_header('Location', '/stolen')
            self.end_headers()
            return
        if self.path == '/oversize':
            self.respond(b'x' * (3 * 1024 * 1024))
            return
        if self.path == '/stream-oversize':
            self.send_response(200)
            self.end_headers()
            try:
                self.wfile.write(b'x' * (3 * 1024 * 1024))
            except (BrokenPipeError, ConnectionResetError):
                pass  # The bounded client is expected to cancel this response.
            return
        if self.path == '/malformed':
            self.respond(b'{invalid JSON')
            return
        messages = payload['messages']
        for index, message in enumerate(messages):
            if message['role'] == 'tool':
                previous = messages[index - 1]
                assert previous['role'] == 'assistant'
                assert message['tool_call_id'] in {x['id'] for x in previous['tool_calls']}
        tool_messages = [m for m in messages if m['role'] == 'tool']
        docs = []
        for message in tool_messages:
            if not message['content'].startswith('ERROR:'):
                docs.append(json.loads(message['content']))
        source_ids = re.findall(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', messages[1]['content'])
        if not tool_messages and self.path == '/scope':
            name, args = 'read_source', {'source_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}
        elif not tool_messages and self.path == '/injection':
            name, args = 'delete_all_tasks', {}
        elif len(docs) < len(source_ids):
            name, args = 'read_source', {'source_id': source_ids[len(docs)]}
        else:
            cards = []
            for index, doc in enumerate(docs):
                passage = doc['passages'][0]
                cards.append({'title': f'Fixture action {index + 1}', 'instruction': 'Read this passage and write a concrete observation.',
                              'outcome': 'One short note with evidence.', 'minutes': 15,
                              'citations': [{'source_id': doc['source_id'], 'passage_id': passage['id'], 'quote': passage['text']}]})
            if self.path == '/repair' and len(tool_messages) == 3:
                cards[0]['citations'][0]['quote'] = 'A fabricated quote that is not in the source.'
            name, args = 'submit_cards', {'cards': cards}
        response = {'choices': [{'message': {'role': 'assistant', 'content': None, 'tool_calls': [
            {'id': f'fixture_{len(messages)}', 'type': 'function', 'function': {'name': name, 'arguments': json.dumps(args, ensure_ascii=False)}}
        ]}}], 'usage': {'prompt_tokens': 100, 'completion_tokens': 25}}
        self.respond(json.dumps(response, ensure_ascii=False).encode())

    def respond(self, body):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', default='.build/debug/QizhiAgentChecks')
    args = parser.parse_args()
    binary = Path(args.binary).resolve()
    server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for route in ['normal', 'repair', 'scope', 'injection', 'auth', 'quota', 'redirect', 'oversize', 'stream-oversize', 'malformed']:
            endpoint = f'http://127.0.0.1:{server.server_port}/{route}'
            result = subprocess.run([str(binary), '--http-fixture', endpoint], capture_output=True, text=True, timeout=30)
            should_pass = route in ['normal', 'repair', 'scope', 'injection']
            assert (result.returncode == 0) == should_pass, f'{route}: {result.stdout} {result.stderr}'
            expected_error = {'auth': '401', 'quota': '429', 'redirect': '307',
                              'oversize': 'Response size limit exceeded', 'stream-oversize': 'Response size limit exceeded',
                              'malformed': 'Incompatible provider response'}
            if route in expected_error:
                assert expected_error[route] in result.stdout, f'{route} failed for an unexpected reason: {result.stdout}'
            assert 'qizhi-fixture-key-not-a-secret' not in result.stdout + result.stderr, 'Credential echoed to output'
            print('PASS HTTP:', route)
        assert Provider.stolen_requests == 0, 'Provider redirect forwarded a credential-bearing request'
        print('10 HTTP fixture scenarios passed; no real model calls.')
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
