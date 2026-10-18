; ; ---- setup ----
;     LANEID  V9              ; V9 = lane index
;     LI      V0, CX0         ; cx0
;     LI      V8, DX          ; dx
;     MUL     V8, V9, V8      ; V8 = lane * dx
;     ADD     V0, V0, V8      ; V0 = cx = cx0 + lane*dx   (per-lane!)
;     LI      V1, CY0         ; V1 = cy  (uniform this row)
;     LI      V2, 0           ; x = 0
;     LI      V3, 0           ; y = 0
;     LI      V7, 0           ; color = 0
;     LI      V10, FOUR       ; escape threshold 4.0
;     LI      V12, 1          ; integer 1
;     MASKALL                 ; all lanes active
;     SETLOOP MAXITER

; loop:
;     MUL     V4, V2, V2      ; x2 = x*x
;     MUL     V5, V3, V3      ; y2 = y*y
;     MUL     V6, V2, V3      ; xy = x*y
;     ADD     V11, V4, V5     ; |z|^2 = x2 + y2
;     ADD     V7, V7, V12     ; color++   (only active lanes, since ADD is masked)
;     ESCAPE  V11, V10        ; deactivate lanes where |z|^2 > 4  -> they freeze
;     SUB     V8, V4, V5      ; tmp = x2 - y2
;     ADD     V8, V8, V0      ; new x = x2 - y2 + cx
;     ADD     V6, V6, V6      ; 2xy
;     ADD     V6, V6, V1      ; new y = 2xy + cy
;     MOV     V2, V8          ; commit x   (masked: frozen lanes keep old x)
;     MOV     V3, V6          ; commit y
;     ENDLOOP loop            ; loop while iterations remain AND some lane active

;     STORE   V7, FB_BASE     ; write each lane's color to framebuffer
;     HALT



;new version 
addr                                ; comment
MASKALL                             ; all lanes active BEFORE any masked op
LANEID  V9                          ; V9 = lane index (Q4.14 integer)
; when LANEID rd executes, each lane k (e.g., lane 0, lane 1, lane 2) 
; writes its specific index value k into the destination register rd
;
LI      V0, CX0                     ; cx0
LI      V8, DX                      ; dx
MUL     V8, V9, V8                  ; V8 = lane * dx  (masked -> mask must be set)
ADD     V0, V0, V8                  ; V0 = cx = cx0 + lane*dx  (per-lane)
LI      V1, CY0                     ; cy (uniform for this strip)
LI      V2, #0                      ; x = 0
LI      V3, #0                      ; y = 0
LI      V7, #0                      ; color = 0
LI      V10, 4.0                    ; escape threshold (raw 65536)
LI      V12, #1                     ; integer 1 for the color counter
SETLOOP MAX_ITER                    ; controller counter
MUL     V4, V2, V2                  ; x2 = x*x        <-- loop top
MUL     V5, V3, V3                  ; y2 = y*y
ADD     V11, V4, V5                 ; mag = x2 + y2   (saturating)
ADD     V7, V7, V12                 ; color++ (masked: frozen lanes hold)
ESCAPE  V11, V10                    ; deactivate lanes where mag > 4
MUL     V6, V2, V3                  ; xy = x*y
ADD     V6, V6, V6                  ; 2xy
SUB     V8, V4, V5                  ; x2 - y2
ADD     V8, V8, V0                  ; new x = x2 - y2 + cx
ADD     V6, V6, V1                  ; new y = 2xy + cy
MOV     V2, V8                      ; commit x (masked)
MOV     V3, V6                      ; commit y (masked)
ENDLOOP 13                          ; loop while iters left AND any active
STORE   V7, FB_BASE                 ; write each lane's color to the FB
HALT



; V0	cx	The starting X-coordinate (real part of the constant $C$) specific to that lane's pixel.
; V1	cy	The starting Y-coordinate (imaginary part of $C$), which is uniform for the entire horizontal strip.
; V2	x	The current real part of the iterative calculation ($Z$), initially set to 0.
; V3	y	The current imaginary part of the iterative calculation ($Z$), initially set to 0.
; V4, V5	x2, y2	Temporary storage for $x^2$ and $y^2$ during the loop.
; V6	xy, new y	Temporary storage for calculating $x \times y$, $2xy$, and ultimately the updated y coordinate for the next iteration.
; V7	color	A raw integer counter that increments each loop; this becomes the final 8-bit color value written to the framebuffer.
; V8	dx, new x	Initially holds the horizontal step size, and later holds temporary math ($x^2 - y^2$) to calculate the updated x coordinate.
; V9	lane index	The physical lane number (e.g., 0, 1, 2) formatted as a Q4.14 integer to calculate initial pixel offsets.
; V10	4.0	The constant escape threshold (raw 65536).
; V11	mag	The magnitude ($x^2 + y^2$) which is compared against the 4.0 threshold to determine if the pixel escapes.
; V12	#1	The raw integer 1, used to increment the color counter (V7) in every iteration.
; V13–V15	—	Unused in the current reference kernel.