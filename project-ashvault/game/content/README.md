# Content

Owns immutable authored definitions, stable content references, and definition
validation metadata. Runtime ownership such as item UIDs does not belong here.

Content must not reference `res://prototype/` or implement alternative gameplay
rules outside production contracts.

`ContentCatalog` stages the complete definition set and publishes it only after
identity, tag, and dependency validation succeeds. Publication freezes both
definitions and the tag registry; a failed load leaves all inputs mutable for
authoring diagnostics and correction.
