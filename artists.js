// Museum artist data — single source of truth for which artworks hang
// in which slots. The gallery loop in test.html reads window.artistsData
// on load and renders accordingly.
//
// HOW TO HANG A NEW PIECE
//   1. Save the artist's image to assets/museum/{slug}.jpg
//   2. Find the next empty slot below (lowest slot number with empty fields)
//   3. Fill in: name, title, year, bio, link, orientation, image
//   4. If the submission's shape differs from the prefilled orientation,
//      change "orientation" to match — the frame adapts ("P"=portrait,
//      "L"=landscape, "S"=square)
//   5. Save this file, commit + push
//
// EMPTY SLOTS render as dark navy placeholders. As long as "image" is "",
// the slot looks unfilled regardless of what's in the other fields.
//
// Field limits (longer text auto-truncates with …):
//   name 40 chars · title 50 chars · bio 200 chars
window.artistsData = {
  "artists": [
    { "slot": 1,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 2,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 3,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 4,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 5,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 6,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 7,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 8,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 9,  "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 10, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 11, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 12, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 13, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 14, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 15, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 16, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 17, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 18, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 19, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 20, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 21, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 22, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 23, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 24, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 25, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 26, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 27, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 28, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 29, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 30, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 31, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 32, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 33, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 34, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 35, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 36, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 37, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 38, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 39, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 40, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 41, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 42, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 43, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 44, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 45, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 46, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 47, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" },
    { "slot": 48, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "S", "image": "" },
    { "slot": 49, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "P", "image": "" },
    { "slot": 50, "name": "", "title": "", "year": 2026, "bio": "", "link": "", "orientation": "L", "image": "" }
  ]
};
