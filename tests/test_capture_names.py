import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("capture_names", Path(__file__).parents[1] / "scripts/capture_names.py")
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class EventTests(unittest.TestCase):
    def test_event_retained(self):
        event = {"event": "qe_transport_diagnostic", "request_id": 3, "body_status": "not_delivered_to_observed_callback"}
        self.assertEqual(capture.event_record({"type": "send", "payload": event}), event)

    def test_binary_message_not_exported(self):
        self.assertIsNone(capture.event_record({"type": "send", "payload": "raw data"}))

    def test_stack_not_exported(self):
        event = capture.event_record({"type": "error", "stack": "potential sensitive data"})
        self.assertEqual(event["event"], "agent_script_error")
        self.assertNotIn("sensitive", str(event))


if __name__ == "__main__":
    unittest.main()
