
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

direction: .res 1
animState: .res 1 ; 0 = Neutral, 1 = Move front, 2 = Move back,
timer: .res 1 ; Timer to control sprite animation
vblank_flag: .res 1 ; Flag to signal when vblank has started
skip_animation_flag: .res 1 ; Flag to skip animation


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
          cpy #(16*4)
          bne loop_load_sprites

enable_rendering:
  lda #%10010000	; Enable NMI
  sta PPUCTRL
  lda #%00011110; Enable background and sprite rendering in PPUMASK.
  sta PPUMASK

forever:
  jsr Update_Sprite_logic
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
 ; update sprite debe entrar al oam data y cambiar los valores de los tiles para que cambie el tile dibujado cada cierto tiempo

Update_Sprite_logic:
  jsr check_update_condition ; jump to check_update_condition subroutine
  lda skip_animation_flag
  cmp #1 ; Check if skip_animation_flag is set
  beq end_update_sprite_logic

  lda animState ; Check if animState is 2
  cmp #2
  beq reset_animation_state_and_sprites ; If animState is not 2, reset animState and sprites


  jsr update_sprites ; If animState is 2, update sprites
  jmp end_update_sprite_logic

  reset_animation_state_and_sprites:
    ; Reset animState to 0
    lda #$00
    sta animState

    ; Reset sprites to first frame (assuming the reset logic is corrected from subtraction to addition)
    ldx #9 ; Start offset in sprite buffer
    ldy #0
    reset_sprites_loop:
      lda SPRITE_BUFFER, x
      clc
      sbc #3 ; Adjust according to the desired frame change
      sta SPRITE_BUFFER, x
      inx
      inx
      inx
      inx
      iny
      cpy #16
      bne reset_sprites_loop
  end_update_sprite_logic:
    lda #$00
    sta skip_animation_flag
  rts

  update_sprites:
  pha
  txa
  pha
  tya
  pha

    ; Update animation state
    lda animState
    clc
    adc #1
    sta animState

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
    lda #$00 ; Reset vblank_flag
    sta vblank_flag

  pla
  tay
  pla
  tax
  pla
    rts


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

; ;segundo sprite hacia arriba 2da animacion
; .byte $54, $03, $00, $74
; .byte $54, $04, $00, $7C
; .byte $5C, $13, $00, $74
; .byte $5C, $14, $00, $7C

; ;tercer sprite hacia arriba 3ra animacion
; .byte $54, $05, $00, $84 
; .byte $54, $06, $00, $8C
; .byte $5C, $15, $00, $84
; .byte $5C, $16, $00, $8C

;cuarto sprite hacia derecha 1ra animacion
.byte $54, $21, $00, $74
.byte $54, $22, $00, $7C
.byte $5C, $31, $00, $74
.byte $5C, $32, $00, $7C

; ;quinto sprite hacia derecha 2da animacion
; .byte $64, $23, $00, $74
; .byte $64, $24, $00, $7C
; .byte $6C, $33, $00, $74
; .byte $6C, $34, $00, $7C

; ;sexto sprite hacia derecha 3ra animacion
; .byte $64, $25, $00, $84
; .byte $64, $26, $00, $8C
; .byte $6C, $35, $00, $84
; .byte $6C, $36, $00, $8C

;septimo sprite hacia abajo 1ra animacion
.byte $54, $41, $00, $84
.byte $54, $42, $00, $8C
.byte $5C, $51, $00, $84
.byte $5C, $52, $00, $8C

; ;octavo sprite hacia abajo 2da animacion
; .byte $74, $43, $00, $74
; .byte $74, $44, $00, $7C
; .byte $7C, $53, $00, $74
; .byte $7C, $54, $00, $7C

; ;noveno sprite hacia abajo 3ra animacion
; .byte $74, $45, $00, $84
; .byte $74, $46, $00, $8C
; .byte $7C, $55, $00, $84
; .byte $7C, $56, $00, $8C

;decimo sprite hacia izquierda 1ra animacion
.byte $54, $61, $00, $94
.byte $54, $62, $00, $9C
.byte $5C, $71, $00, $94
.byte $5C, $72, $00, $9C

; ;onceavo sprite hacia izquierda 2da animacion
; .byte $84, $63, $00, $74
; .byte $84, $64, $00, $7C
; .byte $8C, $73, $00, $74
; .byte $8C, $74, $00, $7C

; ;doceavo sprite hacia izquierda 3ra animacion
; .byte $84, $65, $00, $84
; .byte $84, $66, $00, $8C
; .byte $8C, $75, $00, $84
; .byte $8C, $76, $00, $8C



name_table:
.byte $01, $02, $03, $04, $05, $06, $07, $08
.byte $11, $12, $13, $14, $15, $16, $17, $18
.byte $21, $22, $23, $24, $25, $26, $27, $28
.byte $31, $32, $33, $34, $35, $36, $37, $38



; Character memory
.segment "CHARS"
.incbin "Antsprites.chr"