import os
import random
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from opentelemetry import trace

from app.database import get_connection
from app.models import PaymentRequest, RefundRequest, PaymentResponse

router = APIRouter()
tracer = trace.get_tracer("payment-service")


def _get_failure_rate() -> int:
    try:
        return int(os.getenv("PAYMENT_FAILURE_RATE", "0"))
    except ValueError:
        return 0


@router.post("/payments", response_model=PaymentResponse, status_code=201)
def process_payment(req: PaymentRequest):
    with tracer.start_as_current_span("payment.process") as span:
        span.set_attribute("payment.amount", req.amount)
        span.set_attribute("payment.order_ref", req.order_ref or "")

        failure_rate = _get_failure_rate()
        if failure_rate > 0 and random.randint(0, 100) < failure_rate:
            span.set_attribute("payment.declined", True)
            span.set_attribute("demo.failure_rate", failure_rate)
            raise HTTPException(
                status_code=402,
                detail={
                    "error": "PaymentDeclined",
                    "message": "Payment was declined by the processor",
                    "code": "INSUFFICIENT_FUNDS",
                },
            )

        payment_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()
        card_last4 = req.card_number[-4:] if len(req.card_number) >= 4 else "****"

        conn = get_connection()
        try:
            conn.execute(
                "INSERT INTO payments (id, order_ref, amount, status, card_last4, created_at, updated_at) "
                "VALUES (?, ?, ?, 'approved', ?, ?, ?)",
                (payment_id, req.order_ref, req.amount, card_last4, now, now),
            )
            conn.commit()
        finally:
            conn.close()

        span.set_attribute("payment.id", payment_id)
        span.set_attribute("payment.status", "approved")

        return PaymentResponse(
            payment_id=payment_id,
            status="approved",
            amount=req.amount,
            order_ref=req.order_ref,
        )


@router.post("/payments/refund", response_model=PaymentResponse)
def refund_payment(req: RefundRequest):
    with tracer.start_as_current_span("payment.refund") as span:
        span.set_attribute("payment.id", req.payment_id)

        conn = get_connection()
        try:
            row = conn.execute(
                "SELECT id, order_ref, amount, status FROM payments WHERE id = ?",
                (req.payment_id,),
            ).fetchone()

            if row is None:
                raise HTTPException(status_code=404, detail="Payment not found")
            if row["status"] == "refunded":
                raise HTTPException(status_code=409, detail="Payment already refunded")

            now = datetime.now(timezone.utc).isoformat()
            conn.execute(
                "UPDATE payments SET status = 'refunded', updated_at = ? WHERE id = ?",
                (now, req.payment_id),
            )
            conn.commit()

            span.set_attribute("payment.status", "refunded")

            return PaymentResponse(
                payment_id=row["id"],
                status="refunded",
                amount=row["amount"],
                order_ref=row["order_ref"],
            )
        finally:
            conn.close()


@router.get("/payments/{payment_id}", response_model=PaymentResponse)
def get_payment(payment_id: str):
    conn = get_connection()
    try:
        row = conn.execute(
            "SELECT id, order_ref, amount, status FROM payments WHERE id = ?",
            (payment_id,),
        ).fetchone()

        if row is None:
            raise HTTPException(status_code=404, detail="Payment not found")

        return PaymentResponse(
            payment_id=row["id"],
            status=row["status"],
            amount=row["amount"],
            order_ref=row["order_ref"],
        )
    finally:
        conn.close()
