from pydantic import BaseModel
from typing import Optional


class PaymentRequest(BaseModel):
    order_ref: Optional[str] = None
    amount: float
    card_number: str


class RefundRequest(BaseModel):
    payment_id: str


class PaymentResponse(BaseModel):
    payment_id: str
    status: str
    amount: float
    order_ref: Optional[str] = None
