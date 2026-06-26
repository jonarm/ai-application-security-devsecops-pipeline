"""
Adds app/ to sys.path so test files can import prompt_filter.py and
response_filter.py directly, without making app/ a formal Python package.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))