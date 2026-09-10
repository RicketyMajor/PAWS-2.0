package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"unicode"
)

// personalDataNames are the words that mark personal data in this codebase. An
// identifier is a finding when any of its camelCase or snake_case words is one of
// these, so targetEmail and user_run are caught alongside email and run.
//
// ponytail: the check is by variable name, so an alias (x := u.E) slips through.
// Upgrade path: move logging to slog with typed attributes and a redacting handler the
// day an alias actually gets one of these into a log.
var personalDataNames = map[string]bool{
	"to": true, "email": true, "correo": true, "recipient": true,
	"run": true, "rut": true, "phone": true, "telefono": true,
	"token": true, "password": true, "contrasena": true,
	"lat": true, "latitude": true, "lon": true, "lng": true, "longitude": true,
	"body": true, "otp": true, "code": true,
}

// allowed marks the deliberate exceptions, by "file:line".
// brevo_client.go prints the message body under EMAIL_SIMULATION on purpose: seeing the
// OTP locally is the point of simulation mode. Its risk is that the variable is set in
// production, which is a Render panel question, not a code one.
var allowed = map[string]bool{
	"internal/infrastructure/email/brevo_client.go:53": true,
}

func TestLogCallsCarryNoPersonalData(t *testing.T) {
	root := filepath.Join("..", "..")
	fset := token.NewFileSet()

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			switch d.Name() {
			case ".git", "app", "uploads", "context", "scripts":
				return fs.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}

		file, perr := parser.ParseFile(fset, path, nil, 0)
		if perr != nil {
			return perr
		}

		ast.Inspect(file, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok || !isLogCall(call.Fun) {
				return true
			}
			for _, name := range personalDataInArgs(call.Args) {
				pos := fset.Position(call.Pos())
				rel, _ := filepath.Rel(root, pos.Filename)
				key := filepath.ToSlash(rel) + ":" + strconv.Itoa(pos.Line)
				if allowed[key] {
					continue
				}
				t.Errorf("%s: log call receives %q, which carries personal data.\n"+
					"Log the fact, not the person. If this is deliberate, add %q to allowed.",
					key, name, key)
			}
			return true
		})
		return nil
	})
	if err != nil {
		t.Fatalf("walking the tree: %v", err)
	}
}

// isLogCall reports whether the call is log.Print*, fmt.Print* or println.
func isLogCall(fun ast.Expr) bool {
	sel, ok := fun.(*ast.SelectorExpr)
	if !ok {
		ident, ok := fun.(*ast.Ident)
		return ok && (ident.Name == "print" || ident.Name == "println")
	}
	pkg, ok := sel.X.(*ast.Ident)
	if !ok {
		return false
	}
	if pkg.Name != "log" && pkg.Name != "fmt" && pkg.Name != "slog" {
		return false
	}
	// Sprintf builds a string; it does not write one. Only the sinks count.
	return strings.HasPrefix(sel.Sel.Name, "Print") ||
		strings.HasPrefix(sel.Sel.Name, "Fatal") ||
		strings.HasPrefix(sel.Sel.Name, "Panic")
}

// personalDataInArgs walks each argument's whole subtree, so a value wrapped in
// fmt.Sprintf is caught the same as one passed straight in.
func personalDataInArgs(args []ast.Expr) []string {
	var found []string
	for _, arg := range args {
		ast.Inspect(arg, func(n ast.Node) bool {
			var name string
			switch e := n.(type) {
			case *ast.SelectorExpr:
				name = e.Sel.Name
			case *ast.Ident:
				name = e.Name
			default:
				return true
			}
			if carriesPersonalData(name) {
				found = append(found, name)
			}
			return true
		})
	}
	return found
}

// carriesPersonalData splits an identifier into its camelCase and snake_case words
// and reports whether any of them names personal data. Whole-name equality is not
// enough: targetEmail slipped past it while logging an address in production.
func carriesPersonalData(name string) bool {
	var word strings.Builder
	words := []string{}
	flush := func() {
		if word.Len() > 0 {
			words = append(words, strings.ToLower(word.String()))
			word.Reset()
		}
	}
	for _, r := range name {
		switch {
		case r == '_':
			flush()
		case unicode.IsUpper(r):
			flush()
			word.WriteRune(r)
		default:
			word.WriteRune(r)
		}
	}
	flush()
	for _, w := range words {
		if personalDataNames[w] {
			return true
		}
	}
	return false
}
