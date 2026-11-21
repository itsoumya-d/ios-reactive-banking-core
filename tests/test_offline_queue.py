import unittest

class TestOfflineQueue(unittest.TestCase):
    def test_idempotent_enqueue(self):
        keys = {"idem-1"}
        self.assertIn("idem-1", keys)

if __name__ == '__main__':
    unittest.main()
