package db

import (
	"database/sql"
	"encoding/json"
	"log"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

type SeedProduct struct {
	SKU         string  `json:"sku"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Price       float64 `json:"price"`
	Quantity    int     `json:"quantity"`
	Reserved    int     `json:"reserved"`
}

type SeedData struct {
	Inventory []SeedProduct `json:"inventory"`
}

func InitDB(dbPath, seedPath string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, err
	}

	if err := createSchema(db); err != nil {
		return nil, err
	}

	if err := seedIfEmpty(db, seedPath); err != nil {
		log.Printf("warning: could not seed data: %v", err)
	}

	return db, nil
}

func createSchema(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS inventory (
			sku         TEXT PRIMARY KEY,
			name        TEXT NOT NULL,
			description TEXT,
			price       REAL NOT NULL,
			quantity    INTEGER NOT NULL DEFAULT 0,
			reserved    INTEGER NOT NULL DEFAULT 0
		)
	`)
	return err
}

func seedIfEmpty(db *sql.DB, seedPath string) error {
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM inventory").Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return nil
	}

	data, err := os.ReadFile(seedPath)
	if err != nil {
		return err
	}

	var seed SeedData
	if err := json.Unmarshal(data, &seed); err != nil {
		return err
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}

	stmt, err := tx.Prepare(`
		INSERT INTO inventory (sku, name, description, price, quantity, reserved)
		VALUES (?, ?, ?, ?, ?, ?)
	`)
	if err != nil {
		tx.Rollback()
		return err
	}
	defer stmt.Close()

	for _, p := range seed.Inventory {
		if _, err := stmt.Exec(p.SKU, p.Name, p.Description, p.Price, p.Quantity, p.Reserved); err != nil {
			tx.Rollback()
			return err
		}
	}

	log.Printf("seeded %d inventory items", len(seed.Inventory))
	return tx.Commit()
}
