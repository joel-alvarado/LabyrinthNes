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
isWalking: .res 1 ; Flag for walking to animate

; Controller vars
pad: .res 1 ; Controller 1 input

.segment "BSS"
x_coord: .res 1
y_coord: .res 1


; Main code segment for the program
.segment "CODE"

; Constants
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007

OAMADDR   = $2003
OAMDATA   = $2004
OAMDMA    = $4014

SPRITE_BUFFER = $0200

CONTROLLER1 = $4016
CONTROLLER2 = $4017

BTN_RIGHT   = %00000001
BTN_LEFT    = %00000010
BTN_DOWN    = %00000100
BTN_UP      = %00001000
BTN_START   = %00010000
BTN_SELECT  = %00100000
BTN_B       = %01000000
BTN_A       = %10000000

SPRITE_Y_BASE_ADDR = $08
SPRITE_TILE_BASE_ADDR = $09
SPRITE_ATTR_BASE_ADDR = $0a
SPRITE_X_BASE_ADDR = $0b

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

    ; Init zeropage vars
    ldx #0
    stx render_x
    stx render_y
    stx render_tile
    stx available_oam
    stx direction
    stx animState
    stx frameCounter
    stx vblank_flag
    stx isWalking

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
        lda #100
        sta render_x
        lda #100
        sta render_y
        lda #$01
        sta render_tile
        jsr render_sprite

    enable_rendering:
        lda #%10010000	; Enable NMI
        sta PPUCTRL
        lda #%00011110; Enable background and sprite rendering in PPUMASK.
        sta PPUMASK

forever:
    lda vblank_flag
    cmp #1
    bne NotNMISynced
    NMISynced:
        jsr handle_input
        jsr update_player
        jsr update_sprites
    NotNMISynced:
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
    bne end_update_sprites

    ; Dont update sprites if vblank_flag is not set
    lda vblank_flag
    cmp #1
    bne end_update_sprites

    ; Skip animation if not walking
    lda isWalking
    cmp #0
    beq reset_anim_state
    jmp skip_reset_anim_state
    reset_anim_state:
    lda #0
    sta animState
    jmp end_update_sprites

    skip_reset_anim_state:
    ; Change base sprite based on direction
    ; Increment animState for next frame, wrap around if needed
    inc animState
    lda animState
    cmp #2 ; Assuming 2 frames of animation for simplicity
    bcc animate_sprite
    lda #0
    sta animState
    jsr change_base_sprite
    jmp end_update_sprites

    ; Animate sprite
    animate_sprite:
    ldx #9
    ldy #0
    animate_sprite_loop:
        ; Load the correct sprite based on direction
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
        bne animate_sprite_loop
    inc animState

    end_update_sprites:
    lda #$00 ; Reset vblank_flag
    sta vblank_flag
    rts

handle_input:
    lda #$01
    sta CONTROLLER1  ; Latch the controller state
    lda #$00
    sta CONTROLLER1  ; Complete the latch process

    lda #$00
    sta pad    ; Initialize 'pad' to 0

    ldx #$08   ; Prepare to read 8 buttons

    read_button_loop:
        lda CONTROLLER1       ; Read a button state
        lsr             ; Shift right, moving the button state into the carry
        rol pad         ; Rotate left through carry, moving the carry into 'pad'
        dex             ; Decrement the count
        bne read_button_loop  ; Continue until all 8 buttons are read

    rts


update_player:

    ; Assume no movement initially
    lda #0
    sta isWalking

    ; Check each direction
    lda pad
    and #BTN_UP
    beq check_down  ; If not pressed, check next button
    lda #0          ; Direction for up
    sta direction
    lda #1          ; Indicate walking
    sta isWalking
    jsr move_player_up
    jmp end_update ; Skip further checks

    check_down:
    lda pad
    and #BTN_DOWN
    beq check_left
    lda #1
    sta direction
    lda #1
    sta isWalking
    jsr move_player_down
    jmp end_update

    check_left:
    lda pad
    and #BTN_LEFT
    beq check_right
    lda #2
    sta direction
    lda #1
    sta isWalking
    jsr move_player_left
    jmp end_update

    check_right:
    lda pad
    and #BTN_RIGHT
    beq end_update
    lda #3
    sta direction
    lda #1
    jsr move_player_right
    sta isWalking
    
    end_update:
    rts


change_base_sprite:
    ldx direction
    cpx #0
    beq update_up
    cpx #1
    beq update_down
    cpx #2
    beq update_left
    cpx #3
    beq update_right

    update_up:
        ldx #9
        ldy #0
        update_up_loop:
            lda ant_static_up, y
            sta SPRITE_BUFFER, x
            txa
            clc
            adc #4
            tax
            iny
            cpy #4
            bne update_up_loop
        jmp end_update
    
    update_down:
        ldx #9
        ldy #0
        update_down_loop:
            lda ant_static_down, y
            sta SPRITE_BUFFER, x
            txa
            clc
            adc #4
            tax
            iny
            cpy #4
            bne update_down_loop
        jmp end_update
    
    update_left:
        ldx #9
        ldy #0
        update_left_loop:
            lda ant_static_left, y
            sta SPRITE_BUFFER, x
            txa
            clc
            adc #4
            tax
            iny
            cpy #4
            bne update_left_loop
        jmp end_update
    
    update_right:
        ldx #9
        ldy #0
        update_right_loop:
            lda ant_static_right, y
            sta SPRITE_BUFFER, x
            txa
            clc
            adc #4
            tax
            iny
            cpy #4
            bne update_right_loop
        jmp end_update

move_player_up:
    ldx #SPRITE_Y_BASE_ADDR
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
    ldx #SPRITE_Y_BASE_ADDR
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
    ldx #SPRITE_X_BASE_ADDR
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
    ldx #SPRITE_X_BASE_ADDR
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

null_sprite: 
.byte $00, $00, $00, $00
.byte $00, $00, $00, $00

ant_static_up:
.byte $01, $02, $12, $11

ant_static_right:
.byte $21, $22, $32, $31

ant_static_down:
.byte $41, $42, $52, $51

ant_static_left:
.byte $61, $62, $72, $71

name_table_packaged:
.incbin "assets/nametables/output.bin"

; Character memory
.segment "CHARS"
.incbin "assets/tilesets/ants.chr"