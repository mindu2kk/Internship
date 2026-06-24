"""Deterministic response composer for grounded sales-advisor answers."""

from __future__ import annotations

from dataclasses import dataclass, field

from backend.agent.comparison import build_comparison
from backend.agent.display_spec_selector import (
    FIELD_LABELS,
    displayed_attribute_fields,
    format_attribute,
    select_display_specs,
)
from backend.agent.evidence import EvidenceLedger
from backend.agent.next_best_question import next_best_question
from backend.agent.product_facts import NormalizedProductFacts
from backend.agent.recommendation_policy import advisory_tradeoff
from backend.agent.state import ProductConstraints


RESPONSE_MODES = {
    "filtered_search_result",
    "query_continuation_result",
    "focused_product_detail",
    "focused_product_field_answer",
    "missing_field",
    "fit_assessment",
    "comparison",
    "no_result",
    "clarifying_question",
    "correction_acknowledged",
    "strong_claim_insufficient_evidence",
    "correction",
    "tradeoff",
    "hardware_explanation",
}


@dataclass(frozen=True)
class UIAction:
    type: str
    product_codes: tuple[str, ...] = ()
    payload: dict[str, object] | None = None


@dataclass(frozen=True)
class ResponseDraftInput:
    response_mode: str
    products: tuple[NormalizedProductFacts, ...] = ()
    evidence_ledger: EvidenceLedger = field(default_factory=EvidenceLedger)
    missing_fields: tuple[str, ...] = ()
    constraints: ProductConstraints | None = None
    comparison_result: object | None = None
    ui_actions: tuple[UIAction, ...] = ()
    focused_product_code: str | None = None
    user_query: str = ""
    alternative_brands: tuple[str, ...] = ()
    requested_attributes: tuple[str, ...] = ()


@dataclass(frozen=True)
class RelatedProductDisplay:
    product_code: str
    display_specs: tuple[str, ...] = ()
    matching_facts: tuple[str, ...] = ()


@dataclass(frozen=True)
class AdvisorResponse:
    answer_text: str
    related_product_codes: tuple[str, ...]
    ui_actions: tuple[UIAction, ...]
    answer_mode: str
    missing_fields: tuple[str, ...] = ()
    displayed_attributes: tuple[str, ...] = ()
    related_products: tuple[RelatedProductDisplay, ...] = ()


def compose_response(draft: ResponseDraftInput) -> AdvisorResponse:
    """Build a grounded advisor response without inventing catalog facts."""

    mode = draft.response_mode
    if mode not in RESPONSE_MODES:
        mode = "focused_product_detail" if draft.products else "no_result"

    if mode == "no_result" or (mode == "filtered_search_result" and not draft.products):
        return _compose_no_result(draft)
    if mode == "missing_field":
        return _compose_missing_field(draft)
    if mode == "focused_product_field_answer":
        return _compose_focused_field_answer(draft)
    if mode == "focused_product_detail":
        return _compose_focused_detail(draft)
    if mode in {"filtered_search_result", "query_continuation_result"}:
        return _compose_filtered_search(draft, mode)
    if mode == "comparison":
        return _compose_comparison(draft)
    if mode in {"correction", "correction_acknowledged"}:
        return _compose_correction(draft, mode)
    if mode == "tradeoff":
        return _compose_tradeoff(draft)
    if mode == "clarifying_question":
        return _response(
            "Bạn đang tìm laptop hay điện thoại, ưu tiên học tập/văn phòng, gaming hay đồ họa, và ngân sách khoảng bao nhiêu?",
            "clarifying_question",
            (),
            draft,
        )
    return _compose_hardware_explanation(draft)


def _compose_focused_detail(draft: ResponseDraftInput) -> AdvisorResponse:
    product = draft.products[0]
    lines = [
        f"Mình đang xem đúng mẫu: {product.name} ({product.code}).",
        "",
        "Thông tin catalog hiện có:",
    ]
    lines.extend(_fact_lines(product, requested_attributes=draft.requested_attributes))
    lines.extend(
        [
            "",
            "Đánh giá nhanh:",
            f"- Phù hợp nếu: bạn cần {_fit_summary(product)}.",
            f"- Cần cân nhắc nếu: {_caution_summary(product)}.",
        ]
    )
    follow_up = next_best_question(
        response_mode="focused_product_detail",
        constraints=draft.constraints,
        requested_attributes=draft.requested_attributes,
        product_count=1,
    )
    if follow_up:
        lines.extend(["", follow_up])
    return _response(
        "\n".join(lines),
        "focused_product_detail",
        (product,),
        draft,
        extra_actions=(UIAction("SET_FOCUSED_PRODUCT", (product.code,)),),
    )


def _compose_focused_field_answer(draft: ResponseDraftInput) -> AdvisorResponse:
    product = draft.products[0]
    field_name = (draft.requested_attributes or ("",))[0]
    value = _field_value_text(product, field_name)
    if value is None:
        return _compose_missing_field(
            ResponseDraftInput(
                response_mode="missing_field",
                products=draft.products,
                evidence_ledger=draft.evidence_ledger,
                missing_fields=(field_name,) if field_name else draft.missing_fields,
                constraints=draft.constraints,
                ui_actions=draft.ui_actions,
                focused_product_code=draft.focused_product_code,
                user_query=draft.user_query,
                alternative_brands=draft.alternative_brands,
                requested_attributes=draft.requested_attributes,
            )
        )
    text = f"{product.name} ({product.code}) có {_field_label(field_name)}: {value}."
    return _response(
        text,
        "focused_product_field_answer",
        (product,),
        draft,
        extra_actions=(UIAction("SET_FOCUSED_PRODUCT", (product.code,)),),
    )


def _compose_missing_field(draft: ResponseDraftInput) -> AdvisorResponse:
    product = draft.products[0] if draft.products else None
    missing = draft.missing_fields or draft.evidence_ledger.missing_fields
    field_text = ", ".join(_field_label(field_name) for field_name in missing) or "trường dữ liệu này"
    if product is None:
        text = f"Catalog hiện chưa có dữ liệu {field_text}, nên mình chưa thể khẳng định phần này."
        return _response(text, "missing_field", (), draft)

    lines = [
        f"Mình đang xem đúng mẫu {product.name} ({product.code}).",
        f"Catalog hiện chưa có dữ liệu {field_text} của mẫu này, nên mình chưa thể khẳng định phần đó.",
        "",
        "Thông tin hiện có:",
    ]
    lines.extend(_fact_lines(product, requested_attributes=draft.requested_attributes, limit=5))
    return _response(
        "\n".join(lines),
        "missing_field",
        (product,),
        draft,
        missing_fields=missing,
        extra_actions=(UIAction("SET_FOCUSED_PRODUCT", (product.code,)),),
    )


def _compose_filtered_search(draft: ResponseDraftInput, mode: str) -> AdvisorResponse:
    products = draft.products
    constraint_text = _constraints_text(draft.constraints)
    intro = (
        f"Mình tìm thấy {len(products)} mẫu khớp bộ lọc {constraint_text}:"
        if constraint_text
        else f"Mình tìm thấy {len(products)} mẫu phù hợp trong catalog:"
    )
    lines = [intro]
    for product in products:
        lines.append(f"- {product.name} ({product.code}): {_compact_facts(product, draft.requested_attributes)}")
    tradeoff = advisory_tradeoff(products, draft.constraints, draft.requested_attributes)
    follow_up = next_best_question(
        response_mode=mode,
        constraints=draft.constraints,
        requested_attributes=draft.requested_attributes,
        product_count=len(products),
    )
    if tradeoff:
        lines.extend(["", tradeoff])
    if follow_up:
        lines.extend(["", follow_up])
    return _response(
        "\n".join(lines),
        mode,
        products,
        draft,
        extra_actions=(
            UIAction(
                "SHOW_RELATED_PRODUCTS",
                _codes(products),
                payload={"display_specs": draft.requested_attributes} if draft.requested_attributes else None,
            ),
        ),
    )


def _compose_no_result(draft: ResponseDraftInput) -> AdvisorResponse:
    constraint_text = _constraints_text(draft.constraints)
    if constraint_text:
        text = f"Mình chưa thấy mẫu {constraint_text} trong catalog hiện tại."
    else:
        text = "Mình chưa thấy sản phẩm phù hợp trong catalog hiện tại."
    follow_up = next_best_question(
        response_mode="no_result",
        constraints=draft.constraints,
        requested_attributes=draft.requested_attributes,
        product_count=0,
    )
    if follow_up:
        text += "\n" + follow_up
    if draft.alternative_brands:
        text += "\nMình cũng có thể mở rộng sang " + "/".join(draft.alternative_brands) + " trong cùng tầm giá."
    return _response(text, "no_result", (), draft)


def _compose_comparison(draft: ResponseDraftInput) -> AdvisorResponse:
    products = draft.products
    comparison = build_comparison(products)
    lines = [
        "Mình so sánh nhanh theo dữ liệu catalog hiện có:",
        "",
        comparison.markdown_table,
        "",
        comparison.conclusion,
    ]
    return _response(
        "\n".join(line for line in lines if line is not None),
        "comparison",
        products,
        draft,
        extra_actions=(
            UIAction("OFFER_COMPARE", _codes(products)),
            UIAction(
                "SHOW_RELATED_PRODUCTS",
                _codes(products),
                payload={"display_specs": draft.requested_attributes} if draft.requested_attributes else None,
            ),
        ),
    )


def _compose_correction(draft: ResponseDraftInput, mode: str) -> AdvisorResponse:
    product = draft.products[0] if draft.products else None
    if product is None:
        return _response(
            "Mình đã ghi nhận điều chỉnh, nhưng cần bạn chỉ rõ mẫu sản phẩm cụ thể để mình bám đúng.",
            mode,
            (),
            draft,
        )
    lines = [
        f"Mình đã chỉnh lại đúng mẫu: {product.name} ({product.code}).",
        "Mình sẽ giữ focus vào mẫu này, không đổi sang danh sách sản phẩm khác.",
        "",
        "Thông tin catalog hiện có:",
    ]
    lines.extend(_fact_lines(product, requested_attributes=draft.requested_attributes))
    return _response(
        "\n".join(lines),
        mode,
        (product,),
        draft,
        extra_actions=(UIAction("SET_FOCUSED_PRODUCT", (product.code,)),),
    )


def _compose_tradeoff(draft: ResponseDraftInput) -> AdvisorResponse:
    products = draft.products
    lines = ["Nếu xét theo trade-off từ dữ liệu catalog hiện có:"]
    for product in products:
        lines.append(
            f"- {product.name} ({product.code}): mạnh ở {_strength_summary(product)}; "
            f"cần cân nhắc {_caution_summary(product)}."
        )
    return _response("\n".join(lines), "tradeoff", products, draft)


def _compose_hardware_explanation(draft: ResponseDraftInput) -> AdvisorResponse:
    products = draft.products
    lines = [
        "Mình giải thích theo thông số catalog, không gán nhãn vào sản phẩm khác nếu bạn chưa chọn.",
    ]
    for product in products:
        lines.append(f"- {product.name} ({product.code}): {_compact_facts(product, draft.requested_attributes)}")
    return _response("\n".join(lines), "hardware_explanation", products, draft)


def _response(
    answer_text: str,
    mode: str,
    products: tuple[NormalizedProductFacts, ...],
    draft: ResponseDraftInput,
    *,
    missing_fields: tuple[str, ...] | None = None,
    extra_actions: tuple[UIAction, ...] = (),
) -> AdvisorResponse:
    product_codes = _codes(products)
    actions = draft.ui_actions + extra_actions
    if product_codes and not any(action.type == "SHOW_RELATED_PRODUCTS" for action in actions):
        actions = actions + (
            UIAction(
                "SHOW_RELATED_PRODUCTS",
                product_codes,
                payload={"display_specs": draft.requested_attributes} if draft.requested_attributes else None,
            ),
        )
    return AdvisorResponse(
        answer_text=answer_text.strip(),
        related_product_codes=product_codes,
        ui_actions=actions,
        answer_mode=mode,
        missing_fields=tuple(missing_fields if missing_fields is not None else draft.missing_fields),
        displayed_attributes=_displayed_attributes(products, draft.requested_attributes),
        related_products=_related_product_displays(products, draft.requested_attributes),
    )


def _codes(products: tuple[NormalizedProductFacts, ...]) -> tuple[str, ...]:
    return tuple(product.code for product in products)


def _fact_lines(
    product: NormalizedProductFacts,
    *,
    requested_attributes: tuple[str, ...] = (),
    limit: int | None = None,
) -> list[str]:
    facts: list[tuple[str, object | None]] = [
        ("Giá", _format_price(product.price_value)),
        ("CPU", product.cpu_raw or product.cpu_tier),
        ("GPU", product.gpu_raw or product.gpu_type),
        ("RAM", f"{product.ram_gb}GB" if product.ram_gb is not None else None),
        ("SSD", f"{product.storage_gb}GB" if product.storage_gb is not None else None),
        ("Màn hình", _format_screen(product)),
        ("Pin", f"{product.battery_wh:g}Wh" if product.battery_wh is not None else None),
        ("Trọng lượng", f"{product.weight_kg:g}kg" if product.weight_kg is not None else None),
    ]
    fact_attributes = {
        "Giá": "price_value",
        "CPU": "cpu_tier",
        "GPU": "gpu_type",
        "RAM": "ram_gb",
        "SSD": "storage_gb",
        "Màn hình": "screen_inches",
        "Pin": "battery_wh",
        "Trọng lượng": "weight_kg",
    }
    requested = set(requested_attributes)
    facts.sort(key=lambda item: (0 if fact_attributes.get(item[0]) in requested else 1, item[0]))
    lines = [f"- {label}: {value}" for label, value in facts if value not in (None, "")]
    return lines[:limit] if limit is not None else lines


def _compact_facts(
    product: NormalizedProductFacts,
    requested_attributes: tuple[str, ...] = (),
) -> str:
    parts = [spec.text for spec in select_display_specs(product, requested_attributes)]
    return "; ".join(part for part in parts if part) or "catalog hiện chưa có nhiều thông số chi tiết"


def _displayed_attributes(
    products: tuple[NormalizedProductFacts, ...],
    requested_attributes: tuple[str, ...],
) -> tuple[str, ...]:
    return displayed_attribute_fields(products, requested_attributes)


def _related_product_displays(
    products: tuple[NormalizedProductFacts, ...],
    requested_attributes: tuple[str, ...],
) -> tuple[RelatedProductDisplay, ...]:
    displays: list[RelatedProductDisplay] = []
    requested = set(requested_attributes)
    for product in products:
        specs = select_display_specs(product, requested_attributes)
        displays.append(
            RelatedProductDisplay(
                product_code=product.code,
                display_specs=tuple(spec.text for spec in specs),
                matching_facts=tuple(spec.text for spec in specs if spec.field in requested),
            )
        )
    return tuple(displays)


def _fit_summary(product: NormalizedProductFacts) -> str:
    if product.gpu_type == "dedicated":
        return "gaming, đồ họa nhẹ-vừa hoặc công việc cần GPU rời"
    if product.category.casefold() == "laptop":
        return "học tập, văn phòng, họp online và di chuyển nhẹ"
    return "nhu cầu sử dụng hằng ngày"


def _caution_summary(product: NormalizedProductFacts) -> str:
    if product.gpu_type == "integrated":
        return "bạn cần gaming/đồ họa nặng vì GPU tích hợp sẽ là điểm cần cân nhắc"
    missing = [field for field in ("battery_wh", "weight_kg") if getattr(product, field, None) is None]
    if missing:
        return "catalog còn thiếu, chưa có " + ", ".join(_field_label(field) for field in missing)
    return "bạn cần thông tin ngoài catalog như độ bền thực tế hoặc bảo hành chi tiết"


def _strength_summary(product: NormalizedProductFacts) -> str:
    if product.gpu_type == "dedicated":
        return "GPU rời"
    if product.cpu_tier:
        return f"CPU {product.cpu_tier}"
    if product.price_value is not None:
        return "mức giá rõ ràng"
    return "các thông số đang có"


def _constraints_text(constraints: ProductConstraints | None) -> str:
    if constraints is None:
        return ""
    parts: list[str] = []
    if constraints.brand:
        parts.append(constraints.brand)
    if constraints.category:
        parts.append(constraints.category)
    if constraints.cpu_tier:
        parts.append(constraints.cpu_tier)
    if constraints.gpu_type == "dedicated":
        parts.append("card rời")
    elif constraints.gpu_type == "integrated":
        parts.append("GPU tích hợp")
    if constraints.ram_gb:
        parts.append(f"RAM {constraints.ram_gb}GB")
    if constraints.storage_gb:
        parts.append(f"SSD {constraints.storage_gb}GB")
    if constraints.min_price is not None and constraints.max_price is not None:
        parts.append(f"từ {_format_price(constraints.min_price)} đến {_format_price(constraints.max_price)}")
    elif constraints.max_price is not None:
        parts.append(f"dưới {_format_price(constraints.max_price)}")
    elif constraints.min_price is not None:
        parts.append(f"từ {_format_price(constraints.min_price)}")
    if constraints.use_case:
        use_case_labels = {
            "office": "văn phòng và học tập",
            "gaming": "gaming",
            "creative": "đồ họa",
            "portability": "mỏng nhẹ",
        }
        parts.append(f"cho {use_case_labels.get(constraints.use_case, constraints.use_case)}")
    return " ".join(parts)


def _format_price(value: int | None) -> str | None:
    if value is None:
        return None
    return f"{value:,}".replace(",", ".") + " VNĐ"


def _format_screen(product: NormalizedProductFacts) -> str | None:
    if product.screen_inches is None and product.refresh_hz is None:
        return None
    parts = []
    if product.screen_inches is not None:
        parts.append(f"{product.screen_inches:g} inch")
    if product.refresh_hz is not None:
        parts.append(f"{product.refresh_hz}Hz")
    return " ".join(parts)


def _field_value_text(product: NormalizedProductFacts, field_name: str) -> str | None:
    return format_attribute(product, field_name)


def _field_label(field_name: str) -> str:
    labels = {
        "weight_kg": "trọng lượng",
        "battery_wh": "pin",
        "durability": "độ bền",
        "warranty": "bảo hành",
        "price_value": "giá",
        "cpu_tier": "CPU",
        "gpu_type": "GPU",
        "ram_gb": "RAM",
        "storage_gb": "SSD",
        "screen_inches": "màn hình",
    }
    return labels.get(field_name, FIELD_LABELS.get(field_name, field_name))
