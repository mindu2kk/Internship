"""Grounded product comparison helpers."""

from __future__ import annotations

from dataclasses import dataclass

from backend.agent.display_spec_selector import format_attribute
from backend.agent.product_facts import NormalizedProductFacts


LAPTOP_COMPARISON_FIELDS = (
    ("price_value", "Giá"),
    ("cpu_tier", "CPU"),
    ("ram_gb", "RAM"),
    ("storage_gb", "SSD"),
    ("gpu_type", "GPU"),
    ("screen_inches", "Màn hình"),
)

PHONE_COMPARISON_FIELDS = (
    ("price_value", "Giá"),
    ("cpu_raw", "Chip"),
    ("ram_gb", "RAM"),
    ("storage_gb", "Bộ nhớ"),
    ("screen_inches", "Màn hình"),
)


@dataclass(frozen=True)
class ComparisonResult:
    markdown_table: str
    conclusion: str


def build_comparison(products: tuple[NormalizedProductFacts, ...]) -> ComparisonResult:
    selected = products[:4]
    if len(selected) < 2:
        return ComparisonResult("", "Mình cần ít nhất 2 mẫu đã xác định để so sánh.")
    is_phone_comparison = all(product.category == "Mobile Phone" for product in selected)
    fields = PHONE_COMPARISON_FIELDS if is_phone_comparison else LAPTOP_COMPARISON_FIELDS
    lines = [
        "| Tiêu chí | " + " | ".join(_product_label(product) for product in selected) + " |",
        "|---|" + "---|" * len(selected),
    ]
    for field, label in fields:
        lines.append(
            f"| {label} | "
            + " | ".join(_value(product, field) for product in selected)
            + " |"
        )

    conclusion_parts: list[str] = []
    priced = [product for product in selected if product.price_value is not None]
    if len(priced) == len(selected):
        cheaper = min(priced, key=lambda product: product.price_value or 0)
        conclusion_parts.append(f"Nếu ưu tiên giá thấp, {cheaper.name} lợi hơn.")
    if is_phone_comparison and any(product.cpu_raw is None for product in selected):
        conclusion_parts.append(
            "Dữ liệu chip chưa đầy đủ nên chưa thể kết luận máy nào mạnh nhất."
        )
    elif not is_phone_comparison and len({product.gpu_type for product in selected}) > 1:
        gpu_pick = next(
            (product for product in selected if product.gpu_type == "dedicated"),
            None,
        )
        if gpu_pick:
            conclusion_parts.append(f"Nếu cần GPU rời, {gpu_pick.name} đáng ưu tiên hơn.")
    if not conclusion_parts:
        conclusion_parts.append("Nếu chỉ văn phòng/học tập, hãy chọn theo giá và kích thước màn hình bạn thích hơn.")
    conclusion_parts.append(
        "Mình không kết luận độ bền/pin khi catalog chưa có đủ bằng chứng."
    )
    return ComparisonResult("\n".join(lines), " ".join(conclusion_parts))


def _product_label(product: NormalizedProductFacts) -> str:
    return f"{product.name} ({product.code})"


def _value(product: NormalizedProductFacts, field: str) -> str:
    return format_attribute(product, field) or "Chưa có dữ liệu"
