# conftest.py — makes `config/ai-litellm/` the root so `fabric_dash` is importable
# when pytest is invoked as: cd config/ai-litellm && pytest fabric_dash/tests/…
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
