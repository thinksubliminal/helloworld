// Museum artist data — single source of truth for which artworks hang
// in which slots. The gallery loop in test.html reads window.artistsData
// on load and renders accordingly. To hang a new artist:
//   1. Save the image to assets/museum/{slug}.jpg
//   2. Add a new entry inside the artists array below
//   3. Save this file, refresh test.html
//
// Slot positions are filled in order (1, 2, 3, ...). Whatever orientation
// you set on the entry, the frame at that slot adapts to match — so you
// don't need to wait for a submission whose shape matches the slot's
// Latin-square preset. Pick the next available slot, set orientation
// to "P", "L", or "S" matching the submission.
window.artistsData = {
  "artists": []
};
