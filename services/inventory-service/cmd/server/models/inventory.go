package models

type InventoryItem struct {
	SKU         string  `json:"sku"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Price       float64 `json:"price"`
	Quantity    int     `json:"quantity"`
	Reserved    int     `json:"reserved"`
	Available   int     `json:"available"`
}

type ReserveRequest struct {
	Items []ReserveItem `json:"items" binding:"required"`
}

type ReserveItem struct {
	SKU      string `json:"sku" binding:"required"`
	Quantity int    `json:"quantity" binding:"required,min=1"`
}

type RestockRequest struct {
	Items []RestockItem `json:"items" binding:"required"`
}

type RestockItem struct {
	SKU      string `json:"sku" binding:"required"`
	Quantity int    `json:"quantity" binding:"required,min=1"`
}
