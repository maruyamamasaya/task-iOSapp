import logging
from pathlib import Path
import tempfile
import unittest
from run_approved_relay import lifecycle_logger

class LifecycleLoggingTests(unittest.TestCase):
    def test_log_rotation_is_bounded_and_private(self):
        with tempfile.TemporaryDirectory() as directory:
            logger = lifecycle_logger(Path(directory))
            try:
                for _ in range(20): logger.info('synthetic-' + 'x' * 100000)
                files = list((Path(directory)/'logs').glob('lifecycle.log*'))
                self.assertLessEqual(len(files), 4)
                self.assertLessEqual(sum(p.stat().st_size for p in files), 4 * 262144)
                self.assertEqual((Path(directory)/'logs').stat().st_mode & 0o077, 0)
            finally:
                for handler in list(logger.handlers):
                    handler.close(); logger.removeHandler(handler)
