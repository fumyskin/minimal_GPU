; ---- setup ----
    LANEID  V9              ; V9 = lane index
    LI      V0, CX0         ; cx0
    LI      V8, DX          ; dx
    MUL     V8, V9, V8      ; V8 = lane * dx
    ADD     V0, V0, V8      ; V0 = cx = cx0 + lane*dx   (per-lane!)
    LI      V1, CY0         ; V1 = cy  (uniform this row)
    LI      V2, 0           ; x = 0
    LI      V3, 0           ; y = 0
    LI      V7, 0           ; color = 0
    LI      V10, FOUR       ; escape threshold 4.0
    LI      V12, 1          ; integer 1
    MASKALL                 ; all lanes active
    SETLOOP MAXITER

loop:
    MUL     V4, V2, V2      ; x2 = x*x
    MUL     V5, V3, V3      ; y2 = y*y
    MUL     V6, V2, V3      ; xy = x*y
    ADD     V11, V4, V5     ; |z|^2 = x2 + y2
    ADD     V7, V7, V12     ; color++   (only active lanes, since ADD is masked)
    ESCAPE  V11, V10        ; deactivate lanes where |z|^2 > 4  -> they freeze
    SUB     V8, V4, V5      ; tmp = x2 - y2
    ADD     V8, V8, V0      ; new x = x2 - y2 + cx
    ADD     V6, V6, V6      ; 2xy
    ADD     V6, V6, V1      ; new y = 2xy + cy
    MOV     V2, V8          ; commit x   (masked: frozen lanes keep old x)
    MOV     V3, V6          ; commit y
    ENDLOOP loop            ; loop while iterations remain AND some lane active

    STORE   V7, FB_BASE     ; write each lane's color to framebuffer
    HALT



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