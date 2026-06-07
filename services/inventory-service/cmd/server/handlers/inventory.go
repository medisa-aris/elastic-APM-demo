package handlers

import (
	"database/sql"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/demo/inventory-service/cmd/server/models"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
)

var tracer = otel.Tracer("inventory-service")

type Handler struct {
	db *sql.DB
}

func New(db *sql.DB) *Handler {
	return &Handler{db: db}
}

func (h *Handler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "inventory-service"})
}

func (h *Handler) ListInventory(c *gin.Context) {
	ctx, span := tracer.Start(c.Request.Context(), "db.query.list_inventory")
	defer span.End()

	slowMs := getSlowMs()
	if slowMs > 0 {
		span.SetAttributes(attribute.Int("demo.simulated_delay_ms", slowMs))
		time.Sleep(time.Duration(slowMs) * time.Millisecond)
	}

	rows, err := h.db.QueryContext(ctx, "SELECT sku, name, description, price, quantity, reserved FROM inventory ORDER BY name")
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}
	defer rows.Close()

	items := []models.InventoryItem{}
	for rows.Next() {
		var item models.InventoryItem
		if err := rows.Scan(&item.SKU, &item.Name, &item.Description, &item.Price, &item.Quantity, &item.Reserved); err != nil {
			span.RecordError(err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan error"})
			return
		}
		item.Available = item.Quantity - item.Reserved
		items = append(items, item)
	}

	c.JSON(http.StatusOK, items)
}

func (h *Handler) GetInventory(c *gin.Context) {
	sku := c.Param("sku")

	ctx, span := tracer.Start(c.Request.Context(), "db.query.get_inventory")
	defer span.End()
	span.SetAttributes(attribute.String("inventory.sku", sku))

	slowMs := getSlowMs()
	if slowMs > 0 {
		span.SetAttributes(attribute.Int("demo.simulated_delay_ms", slowMs))
		time.Sleep(time.Duration(slowMs) * time.Millisecond)
	}

	var item models.InventoryItem
	err := h.db.QueryRowContext(ctx,
		"SELECT sku, name, description, price, quantity, reserved FROM inventory WHERE sku = ?", sku,
	).Scan(&item.SKU, &item.Name, &item.Description, &item.Price, &item.Quantity, &item.Reserved)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "item not found", "sku": sku})
		return
	}
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
		return
	}

	item.Available = item.Quantity - item.Reserved
	c.JSON(http.StatusOK, item)
}

func (h *Handler) ReserveInventory(c *gin.Context) {
	var req models.ReserveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx, span := tracer.Start(c.Request.Context(), "db.query.reserve_inventory")
	defer span.End()
	span.SetAttributes(attribute.Int("inventory.items_count", len(req.Items)))

	tx, err := h.db.BeginTx(ctx, nil)
	if err != nil {
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not begin transaction"})
		return
	}

	for _, item := range req.Items {
		var available int
		err := tx.QueryRowContext(ctx,
			"SELECT quantity - reserved FROM inventory WHERE sku = ?", item.SKU,
		).Scan(&available)

		if err == sql.ErrNoRows {
			tx.Rollback()
			c.JSON(http.StatusNotFound, gin.H{"error": "item not found", "sku": item.SKU})
			return
		}
		if err != nil {
			tx.Rollback()
			span.RecordError(err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "database error"})
			return
		}
		if available < item.Quantity {
			tx.Rollback()
			c.JSON(http.StatusConflict, gin.H{
				"error":     "insufficient stock",
				"sku":       item.SKU,
				"available": available,
				"requested": item.Quantity,
			})
			return
		}

		_, err = tx.ExecContext(ctx,
			"UPDATE inventory SET reserved = reserved + ? WHERE sku = ?", item.Quantity, item.SKU,
		)
		if err != nil {
			tx.Rollback()
			span.RecordError(err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "update error"})
			return
		}
	}

	if err := tx.Commit(); err != nil {
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "reserved", "items": req.Items})
}

func (h *Handler) RestockInventory(c *gin.Context) {
	var req models.RestockRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx, span := tracer.Start(c.Request.Context(), "db.query.restock_inventory")
	defer span.End()
	span.SetAttributes(attribute.Int("inventory.items_count", len(req.Items)))

	tx, err := h.db.BeginTx(ctx, nil)
	if err != nil {
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not begin transaction"})
		return
	}

	for _, item := range req.Items {
		_, err := tx.ExecContext(ctx,
			"UPDATE inventory SET reserved = MAX(0, reserved - ?), quantity = quantity + ? WHERE sku = ?",
			item.Quantity, item.Quantity, item.SKU,
		)
		if err != nil {
			tx.Rollback()
			span.RecordError(err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "update error"})
			return
		}
	}

	if err := tx.Commit(); err != nil {
		span.RecordError(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "restocked", "items": req.Items})
}

func getSlowMs() int {
	val := os.Getenv("INVENTORY_SLOW_MS")
	if val == "" {
		return 0
	}
	ms, err := strconv.Atoi(val)
	if err != nil || ms < 0 {
		return 0
	}
	return ms
}
