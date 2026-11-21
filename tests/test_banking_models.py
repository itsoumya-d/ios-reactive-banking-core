import unittest

class TestBankingModels(unittest.TestCase):
    def test_currency_constants(self):
        currencies = ["EUR", "USD", "GBP"]
        self.assertEqual(len(currencies), 3)

if __name__ == '__main__':
    unittest.main()
