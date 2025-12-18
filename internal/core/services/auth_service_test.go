package services

import (
	"testing"
)

// UT-SEC-01: Validación lógica de antecedentes en Blacklist 
func TestCheckBlacklist(t *testing.T) {
	// Inicializamos el servicio (como no tiene dependencias complejas aún, lo instanciamos directo)
	service := &AuthService{}

	// Caso 1: RUN Baneado [cite: 71]
	t.Run("Debe retornar TRUE si el RUN está en blacklist", func(t *testing.T) {
		bannedRun := "12345678-9" // Este RUN lo "mockeamos" en el paso anterior
		isBanned, err := service.CheckBlacklist(bannedRun)

		if err != nil {
			t.Errorf("No se esperaba error, pero llegó: %v", err)
		}
		if !isBanned {
			t.Error("Se esperaba TRUE (Baneado), pero retornó FALSE")
		}
	})

	// Caso 2: RUN Limpio [cite: 72]
	t.Run("Debe retornar FALSE si el RUN está limpio", func(t *testing.T) {
		cleanRun := "11111111-1"
		isBanned, err := service.CheckBlacklist(cleanRun)

		if err != nil {
			t.Errorf("No se esperaba error, pero llegó: %v", err)
		}
		if isBanned {
			t.Error("Se esperaba FALSE (Permitido), pero retornó TRUE")
		}
	})

	// Caso 3: Formato Inválido [cite: 73]
	t.Run("Debe retornar Error si el RUN está vacío", func(t *testing.T) {
		invalidRun := ""
		_, err := service.CheckBlacklist(invalidRun)

		if err == nil {
			t.Error("Se esperaba un error por RUN vacío, pero no llegó nada")
		}
	})
}