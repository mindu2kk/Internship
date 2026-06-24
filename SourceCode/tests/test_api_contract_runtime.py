from __future__ import annotations

from fastapi.testclient import TestClient

from backend.api.main import app


def _post_chat(client: TestClient, message: str, history: list[dict], state: dict | None) -> dict:
    response = client.post(
        "/api/chat",
        json={
            "message": message,
            "history": history,
            "conversation_state": state,
        },
    )
    assert response.status_code == 200
    return response.json()


def _append_history(history: list[dict], user_text: str, response: dict) -> None:
    history.append({"role": "user", "text": user_text, "product_codes": []})
    history.append(
        {
            "role": "assistant",
            "text": response["text"],
            "product_codes": [product["code"] for product in response["products"]],
        }
    )


def test_web_chat_contract_runtime_transcript() -> None:
    client = TestClient(app)
    history: list[dict] = []
    state: dict | None = None

    q1 = "Có laptop nào RAM 16GB SSD 512GB không?"
    r1 = _post_chat(client, q1, history, state)
    assert r1["response_mode"] == "filtered_search_result"
    assert "RAM 16GB" in r1["text"]
    assert "SSD 512GB" in r1["text"]
    assert all("RAM 16GB" in " | ".join(product["specs"][:2]) and "SSD 512GB" in " | ".join(product["specs"][:2]) for product in r1["products"])
    _append_history(history, q1, r1)
    state = r1["conversation_state"]

    q2 = "Có laptop Dell nào có card rời dưới 30 triệu không?"
    r2 = _post_chat(client, q2, history, state)
    assert r2["response_mode"] == "filtered_search_result"
    assert all(product["brand"] == "Dell" for product in r2["products"])
    assert all(product["price_value"] <= 30_000_000 for product in r2["products"])
    assert all("Nvidia" in " ".join(product["specs"]) or "RTX" in " ".join(product["specs"]) or "GTX" in " ".join(product["specs"]) for product in r2["products"])
    assert "Ryzen AI 5" not in r2["text"]
    _append_history(history, q2, r2)
    state = r2["conversation_state"]

    q3 = "Còn máy nào khác không?"
    r3 = _post_chat(client, q3, history, state)
    assert r3["response_mode"] in {"query_continuation_result", "filtered_search_result", "no_result"}
    if r3["products"]:
        assert all(product["brand"] == "Dell" for product in r3["products"])
        assert r2["products"][0]["code"] not in [product["code"] for product in r3["products"]]
    else:
        assert "Dell Laptop card rời dưới 30.000.000 VNĐ" in r3["text"]
    _append_history(history, q3, r3)
    state = r3["conversation_state"]

    q4 = "Có laptop Dell i7 dưới 30 triệu không?"
    r4 = _post_chat(client, q4, history, state)
    assert r4["response_mode"] == "filtered_search_result"
    assert all(product["brand"] == "Dell" for product in r4["products"])
    assert all("Core i7" in " ".join(product["specs"][:2]) for product in r4["products"])
    assert "Core 7" not in r4["text"]
    assert "Ryzen AI" not in r4["text"]
    _append_history(history, q4, r4)
    state = r4["conversation_state"]

    q5 = "Mẫu Dell đó bao nhiêu inch?"
    r5 = _post_chat(client, q5, history, state)
    assert r5["response_mode"] == "focused_product_field_answer"
    assert "inch" in r5["text"]
    assert "Đánh giá nhanh" not in r5["text"]
    assert "Thông tin catalog hiện có" not in r5["text"]


def test_compare_followup_uses_previous_dell_candidates() -> None:
    client = TestClient(app)
    history: list[dict] = []
    state: dict | None = None

    q1 = "Cho toi laptop Dell duoi 20 trieu"
    r1 = _post_chat(client, q1, history, state)
    first_codes = [product["code"] for product in r1["products"]]
    assert first_codes == ["00927778", "00927423"]
    _append_history(history, q1, r1)
    state = r1["conversation_state"]

    q2 = "so sanh 2 mau nay di"
    r2 = _post_chat(client, q2, history, state)
    compared_codes = [product["code"] for product in r2["products"]]

    assert r2["response_mode"] == "comparison"
    assert r2["ai_mode"] == "deterministic_advisor"
    assert compared_codes == first_codes
    assert r2["conversation_state"]["compared_codes"] == first_codes
    assert "Asus" not in r2["text"]
    assert "Lenovo" not in r2["text"]


def test_notable_two_followup_uses_latest_dell_candidates_after_prior_search() -> None:
    client = TestClient(app)
    history: list[dict] = []
    state: dict | None = None

    q1 = "Laptop hoc tap duoi 20 trieu"
    r1 = _post_chat(client, q1, history, state)
    _append_history(history, q1, r1)
    state = r1["conversation_state"]

    q2 = "Cho toi cac laptop Dell duoi 20 trieu"
    r2 = _post_chat(client, q2, history, state)
    dell_codes = [product["code"] for product in r2["products"][:2]]
    assert dell_codes == ["00927778", "00927423"]
    _append_history(history, q2, r2)
    state = r2["conversation_state"]

    q3 = "2 mau dang chu y nay di"
    r3 = _post_chat(client, q3, history, state)

    assert r3["response_mode"] == "comparison"
    assert [product["code"] for product in r3["products"]] == dell_codes
    assert r3["conversation_state"]["compared_codes"] == dell_codes
    assert "Asus TUF" not in r3["text"]
    assert "Lenovo Gaming" not in r3["text"]

