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
animState: .res 1 ; 0 = first frame, 1 = second frame, 2 = third frame
frameCounter: .res 1 ; Counter for frames
vblank_flag: .res 1 ; Flag for vblank

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
        @loop:
            lda palettes, x
            sta PPUDATA
            inx
            cpx #$20
            bne @loop

    render_initial_sprites:
        ldx #100
        stx x_coord
        ldy #90
        sty y_coord

        ldx #0
        render_initial_sprites_loop:
            lda x_coord
            sta render_x
            lda y_coord
            sta render_y
            lda ants, x
            sta render_tile
            jsr render_sprite
            inx
            lda x_coord
            clc
            adc #16
            sta x_coord

            cpx #4
            bne render_initial_sprites_loop

    enable_rendering:
        lda #%10000000	; Enable NMI
        sta PPUCTRL
        lda #%00010110; Enable background and sprite rendering in PPUMASK.
        sta PPUMASK

forever:
    jsr update_sprites
    jmp forever

nmi:

    lda #1
    sta vblank_flag

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

update_sprites:
    ; Exit subroutine if frameCounter is not 29
    lda frameCounter
    cmp #29
    bne skip_update_sprites

    ; Dont update sprites if vblank_flag is not set
    lda vblank_flag
    cmp #1
    bne skip_update_sprites

    ; Update sprites

    ; If animState is 2, reset animState to 0 and reset sprites to first frame
    lda animState
    cmp #2
    bne skip_reset_animState

    ; Reset animState to 0
    lda #$00
    sta animState

    ; Reset sprites to first frame
    ldx #9 ; offset for buffer, where the tile data for tile 1 is stored
    ldy #0
    reset_sprites_loop:
    lda SPRITE_BUFFER, x ; Load tile data for tile y
    clc
    sbc #3 ; Add 2 to the tile data to change the sprite to the next frame
    sta SPRITE_BUFFER, x ; Store the updated tile data back to the buffer
    txa ; Load x to a
    clc
    adc #4 ; Add 4 to x to move to the next tile data
    tax ; Store the updated x back to x
    iny ; Increase y by 1
    cpy #16
    bne reset_sprites_loop ; If y is not 16, loop back to reset_sprites_loop, since we have reset updated all sprites

    ; Skip updating sprites since we just reset them
    jmp skip_update_sprites

    skip_reset_animState:
    ; Update animation state
    lda animState
    clc
    adc #1
    sta animState

    ldx #9 ; offset for buffer, where the tile data for tile 1 is stored
    ldy #0
    update_sprites_loop:
    lda SPRITE_BUFFER, x ; Load tile data for tile y
    clc
    adc #2 ; Add 2 to the tile data to change the sprite to the next frame
    sta SPRITE_BUFFER, x ; Store the updated tile data back to the buffer

    txa ; Load x to a
    clc
    adc #4 ; Add 4 to x to move to the next tile data
    tax ; Store the updated x back to x
    iny ; Increase y by 1
    cpy #16
    bne update_sprites_loop ; If y is not 16, loop back to update_sprites_loop, since we have not updated all sprites

    lda #$00 ; Reset vblank_flag
    sta vblank_flag

    skip_update_sprites:
    rts

palettes:
; background palette
.byte $0F, $16, $13, $37
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

; sprite palette
.byte $0F, $16, $13, $37
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

null_sprite: 
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

ants:
.byte $01, $21, $41, $61

bg_tiles:
.byte $01, $03, $05, $07
.byte $21, $23, $25, $27


; Character memory
.segment "CHARS"
.incbin "ants.chr"