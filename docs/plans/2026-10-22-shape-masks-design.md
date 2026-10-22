# Shape masks: design (MSK-35)

Redlamp's drawn masks are the Linear and Radial Gradients, whose edges are parametric and soft, and the Brush, whose edge is wherever the hand went. None of them draws an exact outline: the face of a building, a window or a doorway, a road, a product's label, or a part of a wall or a sky with nothing in it an AI mask would call an object. A Shape mask is a closed outline of points joined by straight edges or Bézier curves, with corners that can be rounded, and an edge that Feather softens and Edge moves.

Lightroom has no such mask. darktable's path mask is a closed Bézier outline with a feather width at each point ([notes](../research/darktable/notes/C-modules-and-masking.md)), and Photoshop has the pen and the polygonal lasso. darktable is GPL, so nothing here comes from its code; the methods below are from the papers cited.

## The idea

- **One mask kind for polygons, rounded polygons and curves.** Create New Mask › Shape. Its outline is a closed list of points, each a corner or smooth. A corner joins its two sides at an angle, and can be rounded. A smooth point has two Bézier handles on one line, set from its neighbours (centripetal Catmull–Rom) until one is dragged, then kept as dragged. A polygon is all corners; a curve is all smooth points.
- **In the sidecar,** a `path` component (`PathMask` in `Masks.swift`; the menu says Shape, since `MaskShape` already names every component kind): `points`, each with `x`, `y`, `kind` (`corner` or `smooth`), a `radius` for a rounded corner and `in` and `out` handles once dragged; and the shape's `roundness`, `feather` and `edge`. A new kind changes how no existing edit renders, so it needs no process version, as mask Curves (MSK-20) and the Color swatch (MSK-23) didn't; the sidecar schema and its documentation gain the kind. An older Redlamp keeps the component and writes it back unchanged, and draws the mask without it, as it does any kind it doesn't know.
- **Points in mask space, edges in the lens-corrected frame.** A shape's points are photo points, as every mask's are (DEC-07), so it stays on its content when the crop, Transform or lens correction changes. Its edges and curves are built in the lens-corrected frame: after distortion correction, and before the homography that carries the crop, straighten, rotation and Transform (`GeometryMap`), which keeps straight lines straight. So an edge drawn along a wall stays on the wall on screen, whatever the geometry. Built in mask space, where the kernel evaluates Linear and Radial, an edge drawn between two points near the top corners of a 24 MP photo whose profile corrects 3% barrel distortion at the corners would sit about 35 px off the roofline it was drawn along, at its middle. The outline is built and flattened in that frame on the CPU, through `GeometryMap`'s `undistorted` and `distorted` (made public for the engine), and carried back to mask space point by point.
- **A distance field, not coverage.** Raster slices are at most 4096 px on the long edge (`MaskResources.rasterLongEdge`), a texel to 2.3 photo pixels on a 60 MP photo, so an outline stored as coverage, as brush strokes are, would draw a soft, stepped edge at 100%. A shape's slice holds its signed distance from the outline instead (half float, negative inside), which bilinear sampling reconstructs as a straight edge at any zoom (Green 2007, "Improved Alpha-Tested Magnification for Vector Textures and Special Effects"); corners round off only at the scale of a texel. A GPU kernel writes it from the flattened outline's segments: exact distances within reach of the widest Feather and Edge, and only the sign (non-zero winding) beyond. The slice is keyed by the outline and the lens correction, as a brush's is by its strokes, and drawn again only when one of them changes. Each shape takes a slice, as a brush does, from the same 32.
- **Feather and Edge, per pixel,** as AI masks have them (MSK-18). Feather softens the edge over a width centred on the outline, so the line drawn is where the edit is half applied; Edge moves the outline out or in. Both act on the sampled distance in `Masks.h`, a new component kind read by the develop kernel and the detail stage, so dragging them draws nothing again. At Feather 0 the edge is smoothed over one output pixel. An outward Edge rounds convex corners by its own distance, as an offset outline does.
- **Roundness** rounds every corner at once, as a share of the largest radius its sides allow; a corner's own radius, dragged on the canvas, takes over from it. A rounded corner is a circular arc tangent to both sides, in the lens-corrected frame.
- **Drawing:** a click adds a corner and a click-drag a smooth point with its handles. Clicking the first point, double-clicking or Return closes the shape; Escape cancels it, and Delete takes back the last point. With Freehand chosen in the panel, as Objects' Rectangle and Brush are, a drag traces the outline, which is fitted with Bézier curves (Schneider 1990, "An Algorithm for Automatically Fitting Digitized Curves", Graphics Gems) into points like any others.
- **Editing:** drag a point or a handle; click an edge to add a point; Option-click a point to remove it; double-click a point to make it a corner or smooth; Shift keeps a dragged point at 45° steps from its neighbour; drag the pin to move the whole shape. The canvas draws the outline, both Feather guides and the handles, mapped through the geometry as other masks' are. Each change is one History step.
- **Everything else masks have** takes a shape as it takes any component: Add, Subtract, Intersect, Invert, Existing Mask, the overlay, pins, thumbnails, presets and copied settings.

## Validation

- **Unit tests:** rounded corners tangent to both sides and bounded by them; smooth points' handles; flattening within its tolerance; winding through a self-intersecting outline; the distance field against an exact distance on the CPU; the sidecar's round trip, unknown fields kept.
- **Render tests:** a straight edge stays straight, its half-coverage contour within half a pixel of a line, under lens correction, a Transform and a crop with an angle; a shape and its inverse add up to full coverage; Feather and Edge draw no slice again. References recorded for the new kind only, with every other reference unchanged (`ProcessStabilityTests`, `SidecarSchemaTests`).
- **A regression scenario,** `masking.shape`, drawn through the user's input: points, a curve, closing, moving a point, Roundness, Feather, Edge and Freehand.
- **Performance:** a shape costs a render one texture sample per pixel, as a brush does. Drawing its slice while a point is dragged is measured with `redlamp bench`, and kept within a frame.

## Steps

1. This design, the tracker row and the workstream canvas.
2. `PathMask`, the sidecar schema and its documentation, with the round trip.
3. The outline: corners, rounding, smooth points and flattening in the lens-corrected frame, with unit tests.
4. The distance field, its slice, and the component kind in the develop kernel and the detail stage, with render tests and references.
5. Drawing and editing on the canvas; Feather, Edge and Roundness in the panel; History.
6. Freehand.
7. `masking.shape`, the manual, the Lightroom comparison and the README; `mise run e2e`; a performance record.

## Later

- Edges that snap to straight lines found in the photo (the engine's `LineDetector`).
- Refine Edges on a shape: its Feather band solved per pixel as AI masks' edges are, so a rough outline follows hair or foliage.
- Open outlines with a width, as a line mask.
- Straight brush strokes between a click and a Shift-click (MSK-36).
