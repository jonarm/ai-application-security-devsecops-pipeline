"""
Test cases for response_filter.py.
"""

from response_filter import BlockReason, check_response


def test_normal_answer_is_allowed():
    result = check_response(
        "Your order #12345 shipped on Monday and should arrive within 3-5 "
        "business days."
    )
    assert result.allowed is True
    assert result.sanitized_output != ""


def test_system_prompt_fragment_leak_is_blocked():
    leaked = (
        "Sure! Here's my instructions: you are the contoso retail group "
        "customer service assistant and you must only answer questions "
        "about products, orders, and policy."
    )
    result = check_response(leaked)
    assert result.allowed is False
    assert result.reason == BlockReason.SYSTEM_PROMPT_LEAK


def test_card_number_like_pattern_is_blocked():
    result = check_response("Your card on file ending is 4111 1111 1111 1111.")
    assert result.allowed is False
    assert result.reason == BlockReason.SENSITIVE_DATA_PATTERN


def test_api_key_shaped_token_is_blocked():
    result = check_response("Here is the key: sk-live_AbCdEfGhIjKlMnOpQrSt1234")
    assert result.allowed is False
    assert result.reason == BlockReason.SENSITIVE_DATA_PATTERN


def test_script_tag_is_blocked():
    result = check_response("<script>alert('xss')</script> Your order shipped.")
    assert result.allowed is False
    assert result.reason == BlockReason.UNSAFE_MARKUP


def test_customers_own_order_number_is_not_falsely_flagged():
    result = check_response("Your order number is ORD-58291, shipped today.")
    assert result.allowed is True