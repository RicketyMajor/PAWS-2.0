package http

import (
	"testing"
	"time"
)

// The hub keys its client map by user id, so a second connection for the same user
// forces two decisions: what happens to the connection being replaced, and what
// happens when that replaced connection later unregisters. Both are exercised here
// because getting either one wrong leaves a user connected but invisible to the hub,
// and their messages take the offline branch while the sender is told they arrived.

// newTestClient builds a client the hub can hold without a socket behind it. Only
// register and unregister are exercised, and neither touches conn.
func newTestClient(h *Hub, userID uint) *Client {
	return &Client{hub: h, send: make(chan []byte, 1), userID: userID}
}

// runTestHub starts a hub loop for the test. The goroutine outlives the test, which
// is fine: the process ends with the run and the loop holds nothing but its channels.
func runTestHub(t *testing.T) *Hub {
	t.Helper()
	h := NewHub(nil, nil)
	go h.Run()
	return h
}

// waitClosed fails unless ch is closed within a second. A closed send channel is the
// observable the hub offers without reading its map from another goroutine, which
// would be a data race rather than an assertion.
func waitClosed(t *testing.T, ch chan []byte, what string) {
	t.Helper()
	select {
	case _, open := <-ch:
		if open {
			t.Fatalf("%s: a message arrived, expected the channel to be closed", what)
		}
	case <-time.After(time.Second):
		t.Fatalf("%s: still open after one second", what)
	}
}

// waitStillOpen fails if ch closes within the window. Used as the negative case: a
// stale unregister must leave the live connection alone.
func waitStillOpen(t *testing.T, ch chan []byte, what string) {
	t.Helper()
	select {
	case _, open := <-ch:
		if !open {
			t.Fatalf("%s: the channel was closed, expected it to stay open", what)
		}
	case <-time.After(100 * time.Millisecond):
	}
}

// A reload or a second tab produces a second connection for the same user. The one
// being replaced must be closed, or its socket and its two goroutines leak.
func TestSecondConnectionClosesTheOneItReplaces(t *testing.T) {
	h := runTestHub(t)

	first := newTestClient(h, 11)
	second := newTestClient(h, 11)

	h.register <- first
	h.register <- second

	waitClosed(t, first.send, "the replaced connection")
}

// The replaced connection unregisters when its readPump ends, which happens after the
// live one is already in the map. Unregistering by user id alone would evict the live
// connection and leave the user connected but invisible to the hub.
func TestStaleUnregisterLeavesTheLiveConnectionRegistered(t *testing.T) {
	h := runTestHub(t)

	stale := newTestClient(h, 11)
	live := newTestClient(h, 11)

	h.register <- stale
	h.register <- live
	waitClosed(t, stale.send, "the replaced connection")

	// The stale connection reports its own death, late.
	h.unregister <- stale
	waitStillOpen(t, live.send, "the live connection")

	// The live connection is still the one the hub holds: unregistering it is what
	// closes it. If the stale unregister had evicted it, the hub would find nothing
	// here and this channel would never close.
	h.unregister <- live
	waitClosed(t, live.send, "the live connection after its own unregister")
}

// A connection that was never registered must not disturb the map.
func TestUnregisterOfAnUnknownClientIsANoOp(t *testing.T) {
	h := runTestHub(t)

	live := newTestClient(h, 11)
	unknown := newTestClient(h, 11)

	h.register <- live
	h.unregister <- unknown

	waitStillOpen(t, live.send, "the registered connection")
}
