package services

import "testing"

// TestDummy es solo para verificar que GitHub Actions funciona.
// En el futuro, aquí irán los tests de Evil PAWS.
func TestDummy(t *testing.T) {
    expected := 4
    result := 2 + 2

    if result != expected {
        t.Errorf("Matemáticas rotas: se esperaba %d pero se obtuvo %d", expected, result)
    }
}