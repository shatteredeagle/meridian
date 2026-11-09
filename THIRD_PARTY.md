# Third-party material and credits

## OpenMap

Two parts of Meridian owe something to OpenMap, https://github.com/fitzforge/wowforever-openmap (a mirror of jiforever's
wowforever-openmap), MIT licensed:

- **Inspiration.** The way Meridian stitches zone maps into one continent, drawing each zone's base art through a mask of
  the land that zone owns so neighbours' blank parchment does not cover real terrain, comes from OpenMap's approach.
  Meridian's masks are made by its own tool (`tools/gen_territory.py`) from the shapes of each zone's explored-area
  overlays; none of OpenMap's code, textures or masks are used for them.
- **Data.** `Meridian/Caves.lua` (the cave and mine map list: art file IDs and world boxes) and `Meridian/TransportData.lua`
  (boat and zeppelin dock positions) are derived from OpenMap's data tables (themselves built from the game's tables).

OpenMap's licence:

> MIT License
>
> Copyright (c) 2026 OpenMap contributors
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
> documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
> persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
> Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
> WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
> COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
> OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

All map art is Blizzard Entertainment's, loaded from the game client.
