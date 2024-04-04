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
; Args for render_sprite subroutine
render_x: .res 1
render_y: .res 1
render_tile: .res 1
available_oam: .res 1

; Animation vars
direction: .res 1 ; 0 = up, 1 = down, 2 = left, 3 = right
animState: .res 1 ; 0 = small arrow, 1 = big arrow
frameCounter: .res 1 ; Counter for frames

.segment "BSS"
x_coord: .res 1
y_coord: .res 1


; Main code segment for the program
.segment "CODE"

.include "constants.inc"

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
    init_oamdata:
    ; Write to CPU page $0200 to prep OAMDMA transfer
    ldx #0 ; i = 0
    loop_init_oamdata:
        lda #$ff ; load garbage byte
        sta SPRITE_BUFFER, x ; store into current address
        inx ; i++
        cpx #255 ; if i >= 255, break
        bne loop_init_oamdata
    
    ; Load weird null sprites for first 2, i think 0 hit or something idk it fixes weird bugs
    load_null_sprites:
        ldx #0
        loop_load_null_sprites:
            lda null_sprite, x
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
        @loop_palettes:
            lda palettes, x
            sta PPUDATA
            inx
            cpx #$20
            nop
            nop
            bne @loop_palettes
        
        lda #$3f
        sta PPUADDR
        lda #$04
        sta PPUADDR
        lda #$0F
        sta PPUDATA

        lda #$3f
        sta PPUADDR
        lda #$08
        sta PPUADDR
        lda #$0F
        sta PPUDATA

    render_initial_sprites:
        ldx #100
        stx x_coord
        ldy #90
        sty y_coord

        ldx #0
        ldy #0
        render_initial_sprites_loop:
            lda x_coord
            sta render_x
            lda y_coord
            sta render_y
            lda ants, x
            sta render_tile
            jsr render_sprite
            inx
            iny
            ; x += 16 since row is not finished
            lda x_coord
            clc
            adc #16
            sta x_coord

            cpy #3
            bne skip_reset_row_counter ; if y < 3, skip resetting x_coord
            ; y += 16 since row is finished
            ; x = 0
            ldy #0
            lda #100
            sta x_coord
            lda y_coord
            clc
            adc #16
            sta y_coord
            skip_reset_row_counter:
            cpx #12
            bne render_initial_sprites_loop
    
    load_name_table:
        lda PPUSTATUS
        lda #$22
        sta PPUADDR
        lda #$8c
        sta PPUADDR

        ldx #$00
        @loop:
            lda name_table, x
            sta PPUDATA
            inx
            cpx #$8
            bne @loop
        
        lda #$22
        sta PPUADDR
        lda #$ac
        sta PPUADDR

        @loop2:
            lda name_table, x
            sta PPUDATA
            inx
            cpx #16
            bne @loop2
        
        lda #$22
        sta PPUADDR
        lda #$cc
        sta PPUADDR

        @loop3:
            lda name_table, x
            sta PPUDATA
            inx
            cpx #24
            bne @loop3
        
        lda #$22
        sta PPUADDR
        lda #$ec
        sta PPUADDR

        @loop4:
            lda name_table, x
            sta PPUDATA
            inx
            cpx #32
            bne @loop4     

    load_attributes:
        lda PPUSTATUS
        lda #$23
        sta PPUADDR
        lda #$eb
        sta PPUADDR

        lda #%01010000
        sta PPUDATA

        lda #$23
        sta PPUADDR
        lda #$ec
        sta PPUADDR

        lda #%10010000
        sta PPUDATA

    enable_rendering:
        lda #%10010000	; Enable NMI
        sta PPUCTRL
        lda #%00011110; Enable background and sprite rendering in PPUMASK.
        sta PPUMASK

forever:
    
    jmp forever

nmi:
    ; Start OAMDMA transfer
    lda #$02          ; High byte of $0200 where SPRITE_BUFFER is located.
    sta OAMDMA         ; Writing to OAMDMA register initiates the transfer.

    ; Frame counting, used for timing the sprite animation rendering
    ; increased by 1 every frame, reset to 0 after 60 frames
    lda frameCounter ; Load frameCounter
    cmp #30 ; Compare frameCounter to 60
    bne skip_reset_timer ; If frameCounter is not 60, skip resetting it
    lda #$00 ; Reset frameCounter to 0
    sta frameCounter ; Store 0 in frameCounter

    skip_reset_timer: ; Skip resetting frameCounter and render_sprite subroutine
    inc frameCounter ; Increase frameCounter by 1

    ; Reset scroll position
    lda #$00
    sta PPUSCROLL
    lda #$00
    sta PPUSCROLL
    rti

render_sprite:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Write first tile of selected sprite

    ; Render first tile of the sprite
    jsr render_tile_subroutine  ; Call render_tile subroutine

    ; Render second tile of the sprite
    lda render_x
    clc
    adc #$08
    sta render_x ; x = x + 8
    lda render_tile
    clc
    adc #$01
    sta render_tile
    jsr render_tile_subroutine  ; Call render_tile subroutine

    ; Render third tile of the sprite
    lda render_y
    clc
    adc #$08
    sta render_y ; y = y + 8

    lda render_tile
    clc
    adc #$10
    sta render_tile
    jsr render_tile_subroutine  ; Call render_tile subroutine

    ; Render fourth tile of the sprite
    ; No need to update y since it's already at the bottom of the sprite
    ; Only update x to move left by 8 pixels
    lda render_x
    sbc #8 ; WHY DOES THIS RESULT IS 0X4F (0X58 - 8) ITS SUPPOSED TO BE 0X50
    tay
    iny ; 0X4F + 1 = 0X50 (EZ FIX I THINK????)
    sty render_x ; x = x - 8

    ldy render_tile 
    dey
    sty render_tile
    jsr render_tile_subroutine  ; Call render_tile subroutine

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

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

palettes:
.byte $0f, $10, $07, $2d
.byte $0f, $00, $2a, $30
.byte $0f, $28, $00, $29
.byte $00, $00, $00, $00

.byte $0F, $16, $13, $37
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

null_sprite: 
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

ants:
.byte $01, $03, $05
.byte $21, $23, $25
.byte $41, $43, $45
.byte $61, $63, $65

name_table:
.byte $01, $02, $03, $04, $05, $06, $07, $08
.byte $11, $12, $13, $14, $15, $16, $17, $18
.byte $21, $22, $23, $24, $25, $26, $27, $28
.byte $31, $32, $33, $34, $35, $36, $37, $38

; Character memory
.segment "CHARS"
.incbin "ants.chr"