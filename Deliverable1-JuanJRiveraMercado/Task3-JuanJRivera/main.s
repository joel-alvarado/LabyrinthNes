
;Juan J Rivera Mercado 802-20-8179

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007

SPRITE_BUFFER = $0200
available_oam = $0201

OAMADDR   = $2003
OAMDATA   = $2004
OAMDMA    = $4014

CONTROLLER1 = $4016

BTN_RIGHT   = %00000001
BTN_LEFT    = %00000010
BTN_DOWN    = %00000100
BTN_UP      = %00001000
BTN_START   = %00010000
BTN_SELECT  = %00100000
BTN_B       = %01000000
BTN_A       = %10000000


BASE_ADDR_Y = $08
TILE_BASE_ADDR = $01
ATTR_BASE_ADDR = $02
BASE_ADDR_X = $0B

.segment "HEADER"
  ; .byte "NES", $1A      ; iNES header identifier
  .byte $4E, $45, $53, $1A
  .byte 2               ; 2x 16KB PRG code
  .byte 1               ; 1x  8KB CHR data
  .byte $01, $00        ; mapper 0, vertical mirroring

.segment "VECTORS"
  ;; When an NMI happens (once per frame if enabled) the label nmi:
  .addr nmi
  ;; When the processor first turns on or is reset, it will jump to the label reset:
  .addr reset
  ;; External interrupt IRQ (unused)
  .addr 0

; "nes" linker config requires a STARTUP section, even if it's empty
.segment "STARTUP"

.segment "ZEROPAGE"
; Address trackers
current_oam_address: .res 1

; Args for render_sprite subroutine
render_x: .res 1
render_y: .res 1
render_tile: .res 1

; Args for update_sprite subroutine
animState: .res 1 ; 0 = Neutral, 1 = Move front, 2 = Move back,
timer: .res 1 ; Timer to control sprite animation
vblank_flag: .res 1 ; Flag to signal when vblank has started
skip_animation_flag: .res 1 ; Flag to skip animation
isMoving: .res 1

; Args for controllers 
pad1: .res 1 ; Controller 1 input 
direction: .res 1
directionChanged: .res 1
offsetFirstsprite: .res 1



; Main code segment for the program
.segment "CODE"

reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #$40
  stx $4017	; disable APU frame IRQ
  ldx #$ff 	; Set up stack
  txs		;  .
  inx		; now X = 0
  stx PPUCTRL	; disable NMI
  stx PPUMASK 	; disable rendering
  stx $4010 	; disable DMC IRQs

;; first wait for vblank to make sure PPU is ready
vblankwait1:
  bit PPUSTATUS
  bpl vblankwait1

clear_memory:
  lda #$00
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne clear_memory
  
;; second wait for vblank, PPU is ready after this
vblankwait2:
  bit PPUSTATUS
  bpl vblankwait2

main:
lda #$00
sta current_oam_address

  init_oamdata:
    ldx #0
    loop_init_oamdata:
      lda #$ff ; load byte x of sprite list
      sta SPRITE_BUFFER, x ; store current byte in sprite buffer
      inx
      cpx #255
      bne loop_init_oamdata

    load_null_sprites:
        ldx #0
        loop_load_null_sprites:
            lda #$00
            sta SPRITE_BUFFER, x
            inx
            cpx #8
            bne loop_load_null_sprites
        stx available_oam ; Set available_oam to 8

  load_palettes:
    lda PPUSTATUS
    lda #$3f
    sta PPUADDR
    lda #$00
    sta PPUADDR

    ldx #$00
    @loop:
      lda palettes, x
      sta PPUDATA
      inx
      cpx #$20
      bne @loop


    load_sprites:
      ldy #0
      loop_load_sprites:
          lda ant_sprites, y
          sta render_y
          iny
          lda ant_sprites, y
          sta render_tile
          iny
          iny
          lda ant_sprites, y
          sta render_x
          iny
          jsr render_tile_subroutine
          cpy #(16)
          bne loop_load_sprites

enable_rendering:
  lda #%10010000	; Enable NMI
  sta PPUCTRL
  lda #%00011110; Enable background and sprite rendering in PPUMASK.
  sta PPUMASK

forever:
  lda vblank_flag
  cmp #1
  bne NMIunsync
    jsr handle_input
    jsr update_player
    jsr Update_Sprite_logic
  NMIunsync:
    jmp forever

nmi:
  pha
  txa
  pha
  tya
  pha


  lda #1
  sta vblank_flag

  lda #$02 ;load 0200 que es donde empieza el SPRITE_BUFFER
  sta OAMDMA ;store en OAMDATA

  lda timer ; este temporizador nos dira cuando puedo cambiar de animacion
  cmp #30 ; comparo timer con 30
  bne skip_timer_reset; si no es 30 entonces no reseteo el timer

  lda #$00
  sta timer ; reseteo el timer

skip_timer_reset:
  inc timer

  ;reset scroll position
  lda #$00
  sta PPUSCROLL
  lda #$00
  sta PPUSCROLL


  pla 
  tay
  pla
  tax
  pla
  
  rti

render_tile_subroutine:
    ldx available_oam ; Offset for OAM buffer

    lda render_y
    sta SPRITE_BUFFER, x
    inx

    lda render_tile
    sta SPRITE_BUFFER, x
    inx

    lda #$00
    sta SPRITE_BUFFER, x
    inx

    lda render_x
    sta SPRITE_BUFFER, x
    inx

    stx available_oam ; Update available_oam to the next available OAM buffer index`

    rts

handle_input:
    lda #$01
    sta CONTROLLER1  ; Latch the controller state
    lda #$00
    sta CONTROLLER1  ; Complete the latch process

    lda #$00
    sta pad1    ; Initialize 'pad' to 0

    ldx #$08   ; Prepare to read 8 buttons
    read_button_loop:
        lda CONTROLLER1       ; Read a button state
        lsr             ; Shift right, moving the button state into the carry
        rol pad1         ; Rotate left through carry, moving the carry into 'pad'
        dex             ; Decrement the count
        bne read_button_loop  ; Continue until all 8 buttons are read

    rts


 ; update sprite debe entrar al oam data y cambiar los valores de los tiles para que cambie el tile dibujado cada cierto tiempo
Update_Sprite_logic:
  jsr check_update_condition ; jump to check_update_condition subroutine
  lda skip_animation_flag
  cmp #1 ; Check if skip_animation_flag is set
  beq end_update_sprite_logic


  lda isMoving
  cmp #0
  beq reset_animation_state_and_sprites ; If isMoving is 0, reset animState and sprites
  jmp skip_reset_animState

  reset_animation_state_and_sprites:
    ; Reset animState to 0
    lda #$00
    sta animState
    jmp end_update_sprite_logic


  ;   ; Reset sprites to first frame (assuming the reset logic is corrected from subtraction to addition)
  ;   ldx #9 ; Start offset in sprite buffer
  ;   ldy #0
  ;   reset_sprites_loop:
  ;     lda SPRITE_BUFFER, x
  ;     clc
  ;     sbc #3 ; Adjust according to the desired frame change
  ;     sta SPRITE_BUFFER, x
  ;     inx
  ;     inx
  ;     inx
  ;     inx
  ;     iny
  ;     cpy #16
  ;     bne reset_sprites_loop
  skip_reset_animState:
    lda animState
    clc
    adc #1
    sta animState

    cmp #2
    bcc update_sprites
    lda #0
    sta animState
    jsr NOAnimated_sprite
    jmp end_update_sprite_logic

    ; Update animation state
  update_sprites:
  ; pha
  ; txa
  ; pha
  ; tya
  ; pha

    

    ldx #9 ; Start offset in sprite buffer
    ldy #0
    update_sprites_loop:
      lda SPRITE_BUFFER, x
      clc
      adc #2 ; Adjust to change the sprite to the next frame
      sta SPRITE_BUFFER, x
      inx
      inx
      inx
      inx
      iny
      cpy #16
      bne update_sprites_loop
    end_update_sprite_logic:
      lda #$00 ; Reset vblank_flag
      sta vblank_flag
      sta skip_animation_flag
  rts

  ; pla
  ; tay
  ; pla
  ; tax
  ; pla
    ;rts


check_update_condition:
    lda timer
    cmp #29
    bne set_skip_flag  ; Si frameCounter no es 29, se establece la bandera para saltar

    lda vblank_flag
    cmp #1
    beq clear_skip_flag ; Si vblank_flag está establecido, limpiamos la bandera para no saltar

set_skip_flag:
    lda #1
    sta skip_animation_flag
    rts

clear_skip_flag:
    lda #0
    sta skip_animation_flag
    rts



update_player:

    ; Assume no movement initially
    lda #0
    sta isMoving

    ; Check each direction
    lda pad1
    and #BTN_UP
    beq check_down  ; If not pressed, check next button
    lda #0          ; Direction for up
    sta direction
    lda #1          ; Indicate walking
    sta isMoving
    jsr move_player_up
    jmp end_update ; Skip further checks

    check_down:
    lda pad1
    and #BTN_DOWN
    beq check_left
    lda #1
    sta direction
    lda #1
    sta isMoving
    jsr move_player_down
    jmp end_update

    check_left:
    lda pad1
    and #BTN_LEFT
    beq check_right
    lda #2
    sta direction
    lda #1
    sta isMoving
    jsr move_player_left
    jmp end_update

    check_right:
    lda pad1
    and #BTN_RIGHT
    beq end_update
    lda #3
    sta direction
    lda #1
    jsr move_player_right
    sta isMoving


    end_update:
    lda direction
    cmp directionChanged ; Check if the direction has changed
    beq no_change_direction ; If the direction has not changed, skip changing the sprite
    lda direction 
    sta directionChanged ; Update directionChanged to the new direction
    jsr NOAnimated_sprite 
    no_change_direction:
    rts

NOAnimated_sprite:
  ; Get the offset for the sprite
  jsr get_offset_for_direction_sprite

    ldx #9 ; offset for buffer, where the tile data for tile 1 is stored
    ldy #0 ; offset for firstSpritesTiles and 4 count
    reset_sprites_loop:
    tya ; Load y to a
    pha ; Push y to the stack

    ldy offsetFirstsprite ; Load offsetFirstsprite to x
    lda firstSpritesTiles, y ; Load tile data for tile y
    sta SPRITE_BUFFER, x ; Store the tile data in the buffer
    
    lda offsetFirstsprite ; Load offsetFirstsprite to a
    clc
    adc #1
    sta offsetFirstsprite ; Store the updated offsetFirstsprite back to offset_static_spri
    pla
    tay
    ; ; pop in stack variables
    txa ; Load x to a
    clc
    adc #4 ; Add 4 to x to move to the next tile data
    tax ; Store the updated x back to x
    
    iny
    cpy #4 ; Check if y is 4
    bne reset_sprites_loop

  jmp end_update


get_offset_for_direction_sprite:
  ; i will traverse through firstSpritesTiles to get the offset of the sprite
  LDA direction     
  CMP #3         ; Compare offsetFirstsprite with 3
  BEQ SetValue3  
  CMP #2
  BEQ SetValue2  ; If offsetFirstsprite is 2, branch to code that sets Y to the desired value for this case
  CMP #1
  BEQ SetValue1 

  ; If none of the above, we assume offsetFirstsprite is 0 and fall through to SetValue0
  SetValue0:
      LDA #0         ; Set offsetFirstsprite to the value corresponding to offsetFirstsprite being 0
      STA offsetFirstsprite
      JMP Continue   ; Jump to the rest of the code
  SetValue1:
      LDA #4       ; Set offsetFirstsprite to the value corresponding to offsetFirstsprite being 1
      STA offsetFirstsprite
      JMP Continue
  SetValue2:
      LDA #8        ; Set offsetFirstsprite to the value corresponding to offsetFirstsprite being 2
      STA offsetFirstsprite
      JMP Continue
  SetValue3:
      LDA #12         
      STA offsetFirstsprite
      ; here
  Continue:
      rts

move_player_up:
    ldx #BASE_ADDR_Y
    ldy #0
    move_player_up_loop:
        lda SPRITE_BUFFER, x
        clc
        sbc #1
        sta SPRITE_BUFFER, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_up_loop
    rts

move_player_down:
    ldx #BASE_ADDR_Y
    ldy #0
    move_player_down_loop:
        lda SPRITE_BUFFER, x
        clc
        adc #2
        sta SPRITE_BUFFER, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_down_loop
    rts

move_player_left:
    ldx #BASE_ADDR_X
    ldy #0
    move_player_left_loop:
        lda SPRITE_BUFFER, x
        clc
        sbc #1
        sta SPRITE_BUFFER, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_left_loop
    rts

move_player_right:
    ldx #BASE_ADDR_X
    ldy #0
    move_player_right_loop:
        lda SPRITE_BUFFER, x
        clc
        adc #2
        sta SPRITE_BUFFER, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_right_loop
    rts

palettes:
.byte $0f, $10, $07, $2d
.byte $0f, $00, $2a, $30
.byte $0f, $28, $00, $29
.byte $00, $00, $00, $00

.byte $0F, $16, $13, $37
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

ant_sprites:
;primer sprite hacia arriba 1ra animacion
.byte $54, $01, $00, $64
.byte $54, $02, $00, $6C
.byte $5C, $11, $00, $64
.byte $5C, $12, $00, $6C

; ;cuarto sprite hacia derecha 1ra animacion
; .byte $54, $21, $00, $74
; .byte $54, $22, $00, $7C
; .byte $5C, $31, $00, $74
; .byte $5C, $32, $00, $7C

; ;septimo sprite hacia abajo 1ra animacion
; .byte $54, $41, $00, $84
; .byte $54, $42, $00, $8C
; .byte $5C, $51, $00, $84
; .byte $5C, $52, $00, $8C

; ;decimo sprite hacia izquierda 1ra animacion
; .byte $54, $61, $00, $94
; .byte $54, $62, $00, $9C
; .byte $5C, $71, $00, $94
; .byte $5C, $72, $00, $9C


firstSpritesTiles:
      ; 0   1     2   3     4   5     6    7   8     9   A   B     C    D     E   F
.byte $01, $02, $11, $12, $41, $42, $51, $52, $61, $62, $71, $72, $21, $22, $31, $32

name_table:
.byte $01, $02, $03, $04, $05, $06, $07, $08
.byte $11, $12, $13, $14, $15, $16, $17, $18
.byte $21, $22, $23, $24, $25, $26, $27, $28
.byte $31, $32, $33, $34, $35, $36, $37, $38



; Character memory
.segment "CHARS"
.incbin "Antsprites.chr"