package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strings"
	"testing"
	"unicode"
)

// piiWords mark personal data wherever they appear inside an identifier, so
// targetEmail and user_phone are caught alongside email and phone.
var piiWords = map[string]bool{
	"email": true, "correo": true, "recipient": true,
	"rut": true, "phone": true, "telefono": true,
	"password": true, "contrasena": true, "token": true, "otp": true,
	"latitude": true, "longitude": true,
}

// piiExactNames mark personal data only as a whole identifier. They are real
// names in this codebase — the "to" of a mail send, the "code" of an OTP — but
// as fragments they are everywhere: StatusCode, ToLower, ConvertTo.
var piiExactNames = map[string]bool{
	"to": true, "code": true, "run": true, "body": true,
	"lat": true, "lon": true, "lng": true,
}

// writeSinks write their arguments out. Sprint and Errorf are absent on purpose:
// building a string is not logging it.
var writeSinks = map[string]bool{
	"Print": true, "Printf": true, "Println": true,
	"Fprint": true, "Fprintf": true, "Fprintln": true,
	"Fatal": true, "Fatalf": true, "Fatalln": true,
	"Panic": true, "Panicf": true, "Panicln": true,
}

// levelSinks are the level methods of slog and of any logger value. They count on
// every receiver except fmt and errors, where Errorf builds a value instead.
var levelSinks = map[string]bool{
	"Debug": true, "Info": true, "Warn": true, "Error": true, "Log": true,
	"Debugf": true, "Infof": true, "Warnf": true, "Errorf": true, "Logf": true,
	"DebugContext": true, "InfoContext": true, "WarnContext": true, "ErrorContext": true,
}

// skipDirs are skipped by their path from the repo root, not by bare name, so a
// future internal/scripts/ package cannot drop out of coverage by being called
// the same as a top-level directory.
var skipDirs = map[string]bool{
	".git": true, "app": true, "uploads": true, "context": true, "scripts": true,
	"vendor": true, "testdata": true,
}

// exemptMarker exempts the log call on its own line, or on the line below it.
// It is a comment rather than a file:line entry so that editing the file above a
// deliberate log neither breaks the build nor silently exempts a different call.
const exemptMarker = "pii-ok:"

func TestLogCallsCarryNoPersonalData(t *testing.T) {
	root := filepath.Join("..", "..")
	fset := token.NewFileSet()
	checked := 0

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, relErr := filepath.Rel(root, path)
		if relErr != nil {
			return relErr
		}
		if d.IsDir() {
			if skipDirs[strings.Split(filepath.ToSlash(rel), "/")[0]] {
				return fs.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}

		file, perr := parser.ParseFile(fset, path, nil, parser.ParseComments)
		if perr != nil {
			// One unparseable file must not blind the whole check.
			t.Logf("skipping %s: %v", rel, perr)
			return nil
		}
		checked++

		exempt := exemptLines(fset, file)
		ast.Inspect(file, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok || !isLogCall(call.Fun) {
				return true
			}
			line := fset.Position(call.Pos()).Line
			if exempt[line] {
				return true
			}
			for _, name := range personalDataInArgs(call.Args) {
				t.Errorf("%s:%d: log call receives %q, which carries personal data.\n"+
					"Log the fact, not the person. If this one is deliberate, put a\n"+
					"// %s <reason> comment on it.",
					filepath.ToSlash(rel), line, name, exemptMarker)
			}
			return true
		})
		return nil
	})
	if err != nil {
		t.Fatalf("walking the tree: %v", err)
	}
	// A walk that reaches nothing passes for the wrong reason.
	if checked < 10 {
		t.Fatalf("only %d files checked; the walk is not reaching the source", checked)
	}
}

// exemptLines returns the lines carrying an exemption comment, and the line after
// each, so the marker can sit above the call or at the end of it.
func exemptLines(fset *token.FileSet, file *ast.File) map[int]bool {
	lines := map[int]bool{}
	for _, group := range file.Comments {
		marked := false
		for _, c := range group.List {
			if strings.Contains(c.Text, exemptMarker) {
				marked = true
				break
			}
		}
		if !marked {
			continue
		}
		// The marker covers its whole group and the line after it: a reason worth
		// writing rarely fits on one line, and the call sits below the last of them.
		first := fset.Position(group.Pos()).Line
		last := fset.Position(group.End()).Line
		for l := first; l <= last+1; l++ {
			lines[l] = true
		}
	}
	return lines
}

// isLogCall reports whether the call writes its arguments somewhere a person can
// read them later: a log, a level logger, or standard output.
func isLogCall(fun ast.Expr) bool {
	if ident, ok := fun.(*ast.Ident); ok {
		return ident.Name == "print" || ident.Name == "println"
	}
	sel, ok := fun.(*ast.SelectorExpr)
	if !ok {
		return false
	}
	// fmt.Errorf and errors.* build a value; they do not write one. The receiver is
	// checked rather than assumed so that logger.Errorf still counts.
	if pkg, ok := sel.X.(*ast.Ident); ok && (pkg.Name == "fmt" || pkg.Name == "errors") {
		return writeSinks[sel.Sel.Name]
	}
	return writeSinks[sel.Sel.Name] || levelSinks[sel.Sel.Name]
}

// personalDataInArgs walks each argument's whole subtree, so a value wrapped in
// fmt.Sprintf is caught the same as one passed straight in.
func personalDataInArgs(args []ast.Expr) []string {
	var found []string
	for _, arg := range args {
		ast.Inspect(arg, func(n ast.Node) bool {
			switch e := n.(type) {
			case *ast.SelectorExpr:
				if carriesPersonalData(e.Sel.Name) {
					found = append(found, e.Sel.Name)
					// Sel is the same identifier; descending would report it twice.
					return false
				}
			case *ast.Ident:
				if carriesPersonalData(e.Name) {
					found = append(found, e.Name)
				}
			}
			return true
		})
	}
	return found
}

// carriesPersonalData reports whether an identifier names personal data, either
// as a whole or in one of its camelCase or snake_case words.
func carriesPersonalData(name string) bool {
	if piiExactNames[strings.ToLower(name)] {
		return true
	}
	for _, w := range splitWords(name) {
		if piiWords[w] {
			return true
		}
	}
	return false
}

func splitWords(name string) []string {
	var words []string
	var word strings.Builder
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
	return words
}
