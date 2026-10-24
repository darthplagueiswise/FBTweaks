"""Read-only mitmproxy addon. Use run_proxy.py so raw console output stays disabled."""
from pathlib import Path
import sys
import uuid

# mitmproxy loads scripts as modules; make the adjacent stdlib core importable.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from core import EventWriter, summarize_request, summarize_response


class QECapture:
    def __init__(self, writer=None):
        self.writer = writer

    def load(self, loader):
        loader.add_option('qe_output', str, '', 'New private QE metadata JSONL path (required).')

    def running(self):
        from mitmproxy import ctx
        if self.writer is None:
            if not ctx.options.qe_output:
                raise ValueError('qe_output must point to a new private output file')
            self.writer = EventWriter(ctx.options.qe_output)

    def request(self, flow):
        req = flow.request
        summary = summarize_request(req.host, req.path, req.method, req.headers, req.raw_content)
        if summary is None or self.writer is None:
            return
        exchange = str(uuid.uuid4())
        # Metadata belongs to this proxy flow. It is never an app/native session ID.
        flow.metadata['fbt_qe_local_exchange'] = exchange
        self.writer.write({'event': 'request', 'local_exchange_id': exchange, 'summary': summary})

    def response(self, flow):
        exchange = flow.metadata.get('fbt_qe_local_exchange')
        if not exchange or self.writer is None:
            return
        response = flow.response
        summary = summarize_response(response.status_code, response.headers, response.raw_content)
        self.writer.write({'event': 'response', 'local_exchange_id': exchange, 'summary': summary})

    def error(self, flow):
        exchange = flow.metadata.get('fbt_qe_local_exchange')
        if exchange and self.writer is not None:
            # flow.error can contain URLs or other sensitive text. Never stringify it.
            self.writer.write({'event': 'transport_error', 'local_exchange_id': exchange})


addons = [QECapture()]
