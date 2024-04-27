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
changed_direction: .res 1
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

; Nametable things
; These are used for nametable subroutines
NAMETABLE_PTR: .res 2
SELECTED_NAMETABLE: .res 2
SELECTED_ATTRIBUTES: .res 2
SELECTED_TILE_WRITE: .res 1
DECODED_BYTE_IDX: .res 1
BYTE_TO_DECODE: .res 1
BITS_FROM_BYTE: .res 1
SCROLL_POSITION_X: .res 1
SCROLL_POSITION_Y: .res 1
MEGATILES_PTR: .res 2
CURRENT_STAGE_SIDE: .res 1 ; 0 = left, 1 = right
need_update_nametable: .res 1

; Gameplay things
CURRENT_STAGE: .res 1
PLAYER_X: .res 1
PLAYER_Y: .res 1
SCROLL_STAGE: .res 1
CURRENT_STAGE_PTR: .res 2
CURRENT_START_X: .res 1
CURRENT_START_Y: .res 1
CURRENT_END_X: .res 1
CURRENT_END_Y: .res 1
STARTED_ON_NEW_SECTION: .res 1

; Collission stuff
COLLISION_MAP_PTR: .res 2
COLLISION_CHECK_X: .res 1
COLLISION_CHECK_Y: .res 1

; Debugging vars!
PLAYER_MEGATILE_IDX: .res 1

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
COLLISION_MAP_LEFT = $0300
COLLISION_MAP_RIGHT = $0400

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
    stx changed_direction
    stx animState
    stx frameCounter
    stx vblank_flag
    stx isWalking

    ; Init collision map pointer to start at base address COLLISION_MAP_LEFT
    lda #>COLLISION_MAP_LEFT
    sta COLLISION_MAP_PTR+1
    lda #<COLLISION_MAP_LEFT
    sta COLLISION_MAP_PTR

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
            lda stage_one_palettes, x
            sta PPUDATA
            inx
            cpx #$20
            bne @loop_palettes
    
    render_initial_sprites:
        lda #0
        sta render_x
        lda #143
        sta render_y
        lda #$01
        sta render_tile
        jsr render_sprite

        ; Weird bug, PPU writes the tile in x+1, y+1, so PLAYER_X and PLAYER_Y are offset by 1
        lda #0
        sta PLAYER_X
        lda #144
        sta PLAYER_Y
    
    load_nametable:

        ; Set stage to 1
        lda #1
        sta CURRENT_STAGE

        ; Set current stage side to 0
        lda #0
        sta CURRENT_STAGE_SIDE

        ; Select first nametable
        lda #<stage_one_left_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_one_left_packaged
        sta SELECTED_NAMETABLE+1

        ; Select first attribute table
        lda #<stage_one_left_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_one_left_attributes
        sta SELECTED_ATTRIBUTES+1

        ; $2000 for first nametable
        lda #$20
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; $23C0 for first attribute table
        lda #$23
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        ; Set current stage side to 1 (right)
        lda #1
        sta CURRENT_STAGE_SIDE

        ; Increment high byte of COLLISION_MAP_PTR to point to the next 240 bytes (0x0400)
        ; This is because the collision map is 240 bytes long, and we cant overwrite
        ; the first 240 bytes of the collision map with the second stage collision map
        inc COLLISION_MAP_PTR+1

        ; Select second nametable
        lda #<stage_one_right_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_one_right_packaged
        sta SELECTED_NAMETABLE+1

        ; Select second attribute table
        lda #<stage_one_right_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_one_right_attributes
        sta SELECTED_ATTRIBUTES+1

        ; $2400 for second nametable
        lda #$24
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; $27C0 for second attribute table
        lda #$27
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        ; Reset current stage side to 0
        lda #0
        sta CURRENT_STAGE_SIDE

        ; Reset CURRENT_STAGE_PTR to point to the first stage left data
        lda #<stage_one_data
        sta CURRENT_STAGE_PTR
        lda #>stage_one_data
        sta CURRENT_STAGE_PTR+1

        jsr update_stage_data


    enable_rendering:

        ; Set PPUSCROLL to 0,0
        lda #$00
        sta PPUSCROLL
        lda #$00
        sta PPUSCROLL

        lda #%10000000	; Enable NMI
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
        jsr handle_nametable_change
        jsr update_stage_data
        jsr update_collision_ptr
        jsr update_nametable
        jsr main_game_loop
        jsr handle_collision
        jmp forever

nmi:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Set vblank_flag to 1
    lda #1
    sta vblank_flag

    ; Start OAMDMA transfer
    lda #$02          ; High byte of $0200 where SPRITE_BUFFER is located.
    sta OAMDMA         ; Writing to OAMDMA register initiates the transfer.

    ; Frame counting, used for timing the sprite animation rendering
    ; increased by 1 every frame, reset to 0 after 60 frames
    lda frameCounter ; Load frameCounter
    cmp #31 ; Compare frameCounter to 30
    bne skip_reset_timer ; If frameCounter is not 60, skip resetting it
    lda #$00 ; Reset frameCounter to 0
    sta frameCounter ; Store 0 in frameCounter
    jmp scroll_screen_check ; Skip resetting frameCounter and render_sprite subroutine
    
    skip_reset_timer: ; Skip resetting frameCounter and render_sprite subroutine
    inc frameCounter ; Increase frameCounter by 1

    scroll_screen_check:
    lda SCROLL_STAGE
    cmp #0
    beq skip_scroll_screen

    ; Scroll screen right 1px and player left 1px
    lda SCROLL_POSITION_X
    clc
    adc #1
    sta SCROLL_POSITION_X
    jsr move_player_left

    skip_scroll_screen:
    lda SCROLL_POSITION_X
    sta PPUSCROLL
    lda SCROLL_POSITION_Y
    sta PPUSCROLL

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

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
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha


    ldx available_oam ; Offset for OAM buffer

    lda render_y
    sta SPRITE_BUFFER, x
    inx

    lda render_tile
    sta SPRITE_BUFFER, x
    inx

    lda #%00100001
    sta SPRITE_BUFFER, x
    inx

    lda render_x
    sta SPRITE_BUFFER, x
    inx

    stx available_oam ; Update available_oam to the next available OAM buffer index`

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

update_sprites:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Exit subroutine if frameCounter is not 29
    lda frameCounter
    cmp #29
    bne end_update_sprites

    ; Dont update sprites if vblank_flag is not set
    lda vblank_flag
    cmp #1
    bne end_update_sprites

    ; Uupdate base sprite based on direction
    jsr change_base_sprite

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

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla
    rts

handle_input:
    ; No input read if scroll_stage is not 0
    lda SCROLL_STAGE
    cmp #0
    beq input_read
    rts

    input_read:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

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

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla
    rts

update_player:
    ; Disable player movement if scroll_stage is not 0
    lda SCROLL_STAGE
    cmp #0
    beq continue_update_player
    rts

    continue_update_player:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

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
    sta isWalking
    jsr move_player_right
    
    end_update:
    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla
    rts

change_base_sprite:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

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
        jmp end_change_base_sprite
    
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
        jmp end_change_base_sprite
    
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
        jmp end_change_base_sprite
    
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
        jmp end_change_base_sprite
    
    end_change_base_sprite:
    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla
    rts

move_player_up:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ldx #SPRITE_Y_BASE_ADDR
    ldy #0
    move_player_up_loop:
        lda SPRITE_BUFFER, x
        sec
        sbc #1
        sta SPRITE_BUFFER, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_up_loop
    
    ; Update player's y position
    lda PLAYER_Y
    sec
    sbc #1
    sta PLAYER_Y
    
    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla
    rts

move_player_down:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ldx #SPRITE_Y_BASE_ADDR
    ldy #0
    move_player_down_loop:
        lda SPRITE_BUFFER, x
        clc
        adc #1
        sta SPRITE_BUFFER, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_down_loop
    
    ; Update player's y position
    lda PLAYER_Y
    clc
    adc #1
    sta PLAYER_Y

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

move_player_left:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ldx #SPRITE_X_BASE_ADDR
    ldy #0
    move_player_left_loop:
        lda SPRITE_BUFFER, x
        sec
        sbc #1
        sta SPRITE_BUFFER, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_left_loop

    ; Update player's x position
    lda PLAYER_X
    sec
    sbc #1
    sta PLAYER_X

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

move_player_right:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ldx #SPRITE_X_BASE_ADDR
    ldy #0
    move_player_right_loop:
        lda SPRITE_BUFFER, x
        clc
        adc #1
        sta SPRITE_BUFFER, x
        txa
        clc
        adc #4
        tax
        iny
        cpy #4
        bne move_player_right_loop
    
    ; Update player's x position
    lda PLAYER_X
    clc
    adc #1
    sta PLAYER_X

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

write_2x2_region_nametable:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Write first tile of 2x2 region
    lda NAMETABLE_PTR
    sta PPUADDR
    lda NAMETABLE_PTR+1
    sta PPUADDR
    lda SELECTED_TILE_WRITE
    sta PPUDATA

    ; Write second tile of 2x2 region
    lda NAMETABLE_PTR
    sta PPUADDR
    lda NAMETABLE_PTR+1
    clc
    adc #1
    sta PPUADDR
    lda SELECTED_TILE_WRITE
    clc
    adc #1
    sta PPUDATA

    ; Write third tile of 2x2 region
    lda NAMETABLE_PTR
    sta PPUADDR
    lda NAMETABLE_PTR+1
    clc
    adc #32
    sta PPUADDR
    lda SELECTED_TILE_WRITE
    clc
    adc #16
    sta PPUDATA

    ; Write fourth tile of 2x2 region
    lda NAMETABLE_PTR
    sta PPUADDR
    lda NAMETABLE_PTR+1
    clc
    adc #33
    sta PPUADDR
    lda SELECTED_TILE_WRITE
    clc
    adc #17
    sta PPUDATA

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

decode_and_write_byte:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Loop through 2-bit pairs of the byte
    ; Each 2-bit pair corresponds to the top left tile of a 2x2 megatile,
    ; can be used to index megatile array
    ldx #0
    read_bits_loop:
        lda #$00
        sta BITS_FROM_BYTE ; Clear BITS_FROM_BYTE
        
        lda BYTE_TO_DECODE ; Load byte to decode
        clc
        asl ; Sift to read 1 bit into carry
        rol BITS_FROM_BYTE ; Rotate carry into BITS_FROM_BYTE
        asl ; Sift to read 1 bit into carry
        rol BITS_FROM_BYTE ; Rotate carry into BITS_FROM_BYTE
        sta BYTE_TO_DECODE ; Save byte back to BYTE_TO_DECODE

        ldy BITS_FROM_BYTE ; Save the 2-bit pair to X register
        lda (MEGATILES_PTR), y ; Load tile from megatiles based on 2-bit pair
        sta SELECTED_TILE_WRITE ; Save selected tile to SELECTED_TILE_WRITE

        ; Set value of COLLISION_MAP_PTR based on selected tile
        ; If selected tile is collidable (val == $09 or $27 or $0d or $2b), set to 1
        ; Otherwise, set to 0
        lda SELECTED_TILE_WRITE
        cmp #$09
        beq set_collision_map_one
        cmp #$27
        beq set_collision_map_one
        cmp #$0d
        beq set_collision_map_one
        cmp #$2b
        beq set_collision_map_one
        jmp set_collision_map_zero

        set_collision_map_one:
            lda #1
            ldy #0
        sta (COLLISION_MAP_PTR), y
        jmp skip_set_collision_map_zero
        set_collision_map_zero:
            lda #0
            ldy #0
            sta (COLLISION_MAP_PTR), y

        skip_set_collision_map_zero:
        inc COLLISION_MAP_PTR
        ; From SELECTED_TILE_WRITE, call write_region_2x2_nametable 
        ; subroutine to write 2x2 region of nametable
        ; based on the top left tile of the mega tile selected
        jsr write_2x2_region_nametable

        ; Move NAME_TABLE_PTR to next 2x2 region
        lda NAMETABLE_PTR+1
        clc
        adc #2
        sta NAMETABLE_PTR+1

        ; Increment x to move to next 2-bit pair
        inx
        cpx #4
        bne read_bits_loop
    
    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

; Loads, decodes and writes a nametable at NAME_TABLE_PTR 
; from a packaged nametable in ROM
write_nametable:

    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Based on CURRENT_STAGE, select the correct megatiles
    lda CURRENT_STAGE
    cmp #1
    beq select_megatiles_stage_one
    cmp #2
    beq select_megatiles_stage_two

    select_megatiles_stage_one:
        lda #<megatiles_stage_one
        sta MEGATILES_PTR
        lda #>megatiles_stage_one
        sta MEGATILES_PTR+1
        jmp decode_and_write_nametable
    
    select_megatiles_stage_two:
        lda #<megatiles_stage_two
        sta MEGATILES_PTR
        lda #>megatiles_stage_two
        sta MEGATILES_PTR+1
        jmp decode_and_write_nametable
    
    vblankwaitNT:
        bit PPUSTATUS
        bpl vblankwaitNT

    decode_and_write_nametable:
    ldx #0
    read_nametable_loop:
        txa
        tay
        lda (SELECTED_NAMETABLE), y
        sta BYTE_TO_DECODE
        jsr decode_and_write_byte

        ; Check if x+1 % 4 == 0, means we read 4 bytes, increment NAMETABLE_PTR by 32
        txa
        clc
        adc #1
        and #%00000011
        beq increment_lowbyte_nametable_ptr
        jmp continue_next_byte

        increment_lowbyte_nametable_ptr:
            lda NAMETABLE_PTR+1
            clc
            adc #32
            sta NAMETABLE_PTR+1
            lda #0
            adc NAMETABLE_PTR
            sta NAMETABLE_PTR
        
        continue_next_byte:
            inx 
            cpx #60
            bne read_nametable_loop
    
    ; Done with subroutine, pop registers from stack
    ; Reset COLLISION_MAP_PTR to base address COLLISION_MAP_LEFT
    lda #>COLLISION_MAP_LEFT
    sta COLLISION_MAP_PTR+1
    lda #<COLLISION_MAP_LEFT
    sta COLLISION_MAP_PTR

    ; Set initial CURRENT_STAGE_SIDE to 0
    lda #0
    sta CURRENT_STAGE_SIDE

    pla
    tay
    pla
    tax
    pla

    rts

; Writes attributes to NAME_TABLE_PTR from attributes in ROM
load_attributes:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    vblankwaitAttributes:
        bit PPUSTATUS
        bpl vblankwaitAttributes
    ldx #0
    read_attribute_loop:
        txa
        tay
        lda (SELECTED_ATTRIBUTES), y
        sta PPUDATA
        inx
        cpx #64
        bne read_attribute_loop
    ; Done writing attributes

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

handle_nametable_change:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; If need_update_nametable is set, update nametable
    lda need_update_nametable
    cmp #1
    beq start_update_nametable
    jmp skip_nametable_change

    start_update_nametable:
    ; If in stage one, set to stage two
    ; If in stage two, set to stage one
    lda CURRENT_STAGE
    cmp #1
    beq set_stage_two
    cmp #2
    beq set_stage_one

    set_stage_two:
        lda #2
        sta CURRENT_STAGE
        jmp call_update_nametable
    
    set_stage_one:
        lda #1
        sta CURRENT_STAGE
        jmp call_update_nametable
    
    call_update_nametable:
        ; Set scroll position to 0,0
        lda #$00
        sta SCROLL_POSITION_X
        sta SCROLL_POSITION_Y

    skip_nametable_change:
    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla
    
    rts

update_nametable:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Check if need_update_nametable is set
    lda need_update_nametable
    cmp #1
    beq continue_update_nametable
    jmp skip_update_nametable

    continue_update_nametable:
    ; Disable disable NMI and screen
    lda PPUCTRL
    and #%01111111
    sta PPUCTRL
    lda PPUMASK
    and #%11100000
    sta PPUMASK

    vblankwait3:
        bit PPUSTATUS
        bpl vblankwait3

    ; Select nametable based on CURRENT_STAGE
    lda CURRENT_STAGE
    cmp #1
    beq select_stage_one

    lda CURRENT_STAGE
    cmp #2
    beq select_stage_two

    select_stage_one:
        ; Load stage one left nametables
        lda #<stage_one_left_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_one_left_packaged
        sta SELECTED_NAMETABLE+1

        ; Set current stage side to 0 (left)
        lda #0
        sta CURRENT_STAGE_SIDE
        jsr update_collision_ptr

        lda #$20
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; Load stage one left attributes
        lda #<stage_one_left_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_one_left_attributes
        sta SELECTED_ATTRIBUTES+1

        lda #$23
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        ; Load stage one right nametables
        lda #<stage_one_right_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_one_right_packaged
        sta SELECTED_NAMETABLE+1

        ; Set current stage side to 1 (right)
        lda #1
        sta CURRENT_STAGE_SIDE
        jsr update_collision_ptr

        lda #$24
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; Load stage one right attributes
        lda #<stage_one_right_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_one_right_attributes
        sta SELECTED_ATTRIBUTES+1

        lda #$27
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        ; Set need_update_nametable to 0
        lda #0
        sta need_update_nametable

        jmp skip_update_nametable
    
    select_stage_two:
        ; Load stage two left nametables
        lda #<stage_two_left_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_two_left_packaged
        sta SELECTED_NAMETABLE+1

        lda #$20
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; Load stage two left attributes
        lda #<stage_two_left_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_two_left_attributes
        sta SELECTED_ATTRIBUTES+1

        ; Set current stage side to 0 (left)
        lda #0
        sta CURRENT_STAGE_SIDE
        jsr update_collision_ptr

        lda #$23
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        ; Load stage two right nametables
        lda #<stage_two_right_packaged
        sta SELECTED_NAMETABLE
        lda #>stage_two_right_packaged
        sta SELECTED_NAMETABLE+1

        ; Set current stage side to 1 (right)
        lda #1
        sta CURRENT_STAGE_SIDE
        jsr update_collision_ptr

        lda #$24
        sta NAMETABLE_PTR
        lda #$00
        sta NAMETABLE_PTR+1
        jsr write_nametable

        ; Load stage two right attributes
        lda #<stage_two_right_attributes
        sta SELECTED_ATTRIBUTES
        lda #>stage_two_right_attributes
        sta SELECTED_ATTRIBUTES+1

        lda #$27
        sta NAMETABLE_PTR
        lda #$C0
        sta NAMETABLE_PTR+1
        jsr load_attributes

        ; Set need_update_nametable to 0
        lda #0
        sta need_update_nametable

        jmp skip_update_nametable

    skip_update_nametable:

    ; Restore NMI and screen
    lda #$80
    sta PPUCTRL
    lda #$1e
    sta PPUMASK

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

handle_collision:
    ; Ignore collision check if scroll_stage is 1
    lda SCROLL_STAGE
    cmp #1
    bne collision_check
    rts

    collision_check:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Depending on direction, collision check will be different
    ; If player is moving up, check (x, y) and (x+15, y), this checks top boundary of player
    ; If player is moving down, check (x, y+15) and (x15, y+15), this checks bottom boundary of player
    ; If player is moving left, check (x, y) and (x, y+15), this checks left boundary of player
    ; If player is moving right, check (x+15, y) and (x+15, y+15), this checks right boundary of player
    lda direction
    cmp #0
    beq check_up_collision
    cmp #1
    beq check_down_collision
    cmp #2
    beq check_left_collision
    cmp #3
    beq check_right_collission_intermediate

    check_up_collision:
        ; Check top left boundary of player (x, y)
        lda PLAYER_X
        sta COLLISION_CHECK_X
        lda PLAYER_Y
        sta COLLISION_CHECK_Y
        jsr coord_to_megatile

        ldy PLAYER_MEGATILE_IDX
        lda (COLLISION_MAP_PTR), y
        cmp #1
        bne continue_check_up_collision
        jsr move_player_down
        jmp end_collision_check_intermediate
        
        continue_check_up_collision:
        ; Check top right boundary of player (x+15, y)
        lda PLAYER_X
        clc
        adc #15
        sta COLLISION_CHECK_X
        lda PLAYER_Y
        sta COLLISION_CHECK_Y
        jsr coord_to_megatile

        ldy PLAYER_MEGATILE_IDX
        lda (COLLISION_MAP_PTR), y
        cmp #1
        bne end_collision_check_intermediate
        jsr move_player_down
        jmp end_collision_check_intermediate
    
    check_down_collision:
        ; Check bottom left boundary of player (x, y+15)
        lda PLAYER_X
        sta COLLISION_CHECK_X
        lda PLAYER_Y
        clc
        adc #15
        sta COLLISION_CHECK_Y
        jsr coord_to_megatile

        ldy PLAYER_MEGATILE_IDX
        lda (COLLISION_MAP_PTR), y
        cmp #1
        bne continue_check_down_collision
        jsr move_player_up
        jmp end_collision_check_intermediate

        continue_check_down_collision:
        ; Check bottom right boundary of player (x+15, y+15)
        lda PLAYER_X
        clc
        adc #15
        sta COLLISION_CHECK_X
        lda PLAYER_Y
        clc
        adc #15
        sta COLLISION_CHECK_Y
        jsr coord_to_megatile

        ldy PLAYER_MEGATILE_IDX
        lda (COLLISION_MAP_PTR), y
        cmp #1
        bne end_collision_check_intermediate
        jsr move_player_up
        jmp end_collision_check_intermediate
    
    end_collision_check_intermediate:
        jmp end_collision_check

    check_right_collission_intermediate:
        jmp check_right_collision
    
    check_left_collision:
        ; Check top left boundary of player (x, y)
        lda PLAYER_X
        sta COLLISION_CHECK_X
        lda PLAYER_Y
        sta COLLISION_CHECK_Y
        jsr coord_to_megatile

        ldy PLAYER_MEGATILE_IDX
        lda (COLLISION_MAP_PTR), y
        cmp #1
        bne continue_check_left_collision
        jsr move_player_right
        jmp end_collision_check

        continue_check_left_collision:
        ; Check bottom left boundary of player (x, y+15)
        lda PLAYER_X
        sta COLLISION_CHECK_X
        lda PLAYER_Y
        clc
        adc #15
        sta COLLISION_CHECK_Y
        jsr coord_to_megatile

        ldy PLAYER_MEGATILE_IDX
        lda (COLLISION_MAP_PTR), y
        cmp #1
        bne end_collision_check
        jsr move_player_right
        jmp end_collision_check

    check_right_collision:
        ; Check top right boundary of player (x+15, y)
        lda PLAYER_X
        clc
        adc #15
        sta COLLISION_CHECK_X
        lda PLAYER_Y
        sta COLLISION_CHECK_Y
        jsr coord_to_megatile

        ldy PLAYER_MEGATILE_IDX
        lda (COLLISION_MAP_PTR), y
        cmp #1
        bne continue_check_right_collision
        jsr move_player_left
        jmp end_collision_check

        continue_check_right_collision:
        ; Check bottom right boundary of player (x+15, y+15)
        lda PLAYER_X
        clc
        adc #15
        sta COLLISION_CHECK_X
        lda PLAYER_Y
        clc
        adc #15
        sta COLLISION_CHECK_Y
        jsr coord_to_megatile

        ldy PLAYER_MEGATILE_IDX
        lda (COLLISION_MAP_PTR), y
        cmp #1
        bne end_collision_check
        jsr move_player_left
        jmp end_collision_check

    end_collision_check:
    pla
    tay
    pla
    tax
    pla

    rts

coord_to_megatile:
    ; Will convert player's x and y to megatile index 
    ; in the nametable and replace the megatile with a different one

    ; Fix for unaligned collisions due to ppuscroll bug of 1 pixel offset
    ; If current side is 1 (right), add 1 to x
    lda CURRENT_STAGE_SIDE
    cmp #1
    bne skip_fix_collision
    ; COLLISION_CHECK_X = COLLISION_CHECK_X + 1
    dec COLLISION_CHECK_X
    skip_fix_collision:

    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    ; Calulate player's x and y to megatile index using formula (y/16)*16 + (x/16)
    ; Divide PLAYER_X by 16 to get the x megatile index
    lda COLLISION_CHECK_X
    lsr
    lsr
    lsr
    lsr
    sta PLAYER_MEGATILE_IDX

    ; Divide PLAYER_Y by 16 to get the y megatile index
    lda COLLISION_CHECK_Y
    lsr
    lsr
    lsr
    lsr

    ; Multiply y megatile index by 16
    asl
    asl
    asl
    asl

    ; Add x megatile index to y megatile index
    clc
    adc PLAYER_MEGATILE_IDX
    sta PLAYER_MEGATILE_IDX

    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

main_game_loop:
    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha

    jsr update_collision_ptr
    
    continue_game_loop:
    ; If SCROLL_STAGE == 1 and SCROLL_POSITION_X == 255 and CURRENT_STAGE_SIDE == 0
    lda SCROLL_STAGE
    cmp #1
    bne check_if_need_scroll

    ; Turn off player sprite if SCROLL_STAGE == 1
    waitForVBlank:
        bit PPUSTATUS
        bpl waitForVBlank
    
    lda PPUMASK
    and #%11110111
    sta PPUMASK
    lda SCROLL_POSITION_X
    cmp #255
    bne skip_side_change

    ; Stop scrolling since SCROLL_POSITION_X == 255
    lda #0
    sta SCROLL_STAGE

    ; Move player 16 pixels to the right
    ldx #0
    move_p_16_right:
        jsr move_player_right
        inx
        cpx #16
        bne move_p_16_right
    
    ; Set stage side to 1 (right)
    lda #1
    sta CURRENT_STAGE_SIDE

    ; Update collision map pointer
    jsr update_collision_ptr

    ; Show player sprite
    lda PPUMASK
    ora #%00001000
    sta PPUMASK

    jmp skip_side_change

    check_if_need_scroll:
    ; If player reached end of current stage
    ; If playerx == 240 and playery == 64, change current_side to 1 (right)
    lda CURRENT_STAGE_SIDE
    cmp #0
    beq check_left_if_need_scroll
    jmp skip_side_change

    check_left_if_need_scroll:
    lda PLAYER_X
    cmp STAGE_ONE_LEFT_END
    bne skip_side_change
    clc
    lda PLAYER_Y
    cmp STAGE_ONE_LEFT_END+1
    bne skip_side_change

    ; Start transition to scroll to the right
    lda #1
    sta SCROLL_STAGE
    jmp skip_side_change

    skip_side_change:
    ; If current stage side == 1 (right) and playerx == CURRENT_END_X and playery == CURRENT_END_Y
    ; Change nametable and switch to left side
    lda CURRENT_STAGE_SIDE
    cmp #1
    bne end_main_game_loop
    lda PLAYER_X
    cmp CURRENT_END_X
    bne end_main_game_loop
    clc
    lda PLAYER_Y
    cmp CURRENT_END_Y
    bne end_main_game_loop

    ; Since we are at the end of the stage, go to new stage
    lda #1
    sta need_update_nametable

    end_main_game_loop:
    ; Pop registers from stack
    pla
    tay
    pla
    tax
    pla

    rts

update_collision_ptr:
    pha
    txa
    pha
    tya
    pha

    ; Set COLLISION_MAP_PTR based on current side
    lda CURRENT_STAGE_SIDE
    cmp #0
    beq set_collision_map_left
    cmp #1
    beq set_collision_map_right

    set_collision_map_left:
        lda #<COLLISION_MAP_LEFT
        sta COLLISION_MAP_PTR
        lda #>COLLISION_MAP_LEFT
        sta COLLISION_MAP_PTR+1
        jmp end_update_collision_ptr
    
    set_collision_map_right:
        lda #<COLLISION_MAP_RIGHT
        sta COLLISION_MAP_PTR
        lda #>COLLISION_MAP_RIGHT
        sta COLLISION_MAP_PTR+1
    
    end_update_collision_ptr:
    pla
    tay
    pla
    tax
    pla

    rts

update_stage_data:
    pha
    txa
    pha
    tya
    pha

    ; Load stage data based on current stage
    lda CURRENT_STAGE
    cmp #1
    beq load_stage_one_data
    cmp #2
    beq load_stage_two_data

    load_stage_one_data:
        lda CURRENT_STAGE_SIDE
        cmp #0
        beq load_stage_one_left_data
        cmp #1
        beq load_stage_one_right_data

    load_stage_two_data:
        lda CURRENT_STAGE_SIDE
        cmp #0
        beq load_stage_two_left_data
        cmp #1
        beq load_stage_two_right_data
    
    load_stage_one_left_data:
        lda STAGE_ONE_LEFT_START
        sta CURRENT_START_X
        lda STAGE_ONE_LEFT_START+1
        sta CURRENT_START_Y

        lda STAGE_ONE_LEFT_END
        sta CURRENT_END_X
        lda STAGE_ONE_LEFT_END+1
        sta CURRENT_END_Y
        jmp end_update_stage_data
    
    load_stage_one_right_data:
        lda STAGE_ONE_RIGHT_START
        sta CURRENT_START_X
        lda STAGE_ONE_RIGHT_START+1
        sta CURRENT_START_Y

        lda STAGE_ONE_RIGHT_END
        sta CURRENT_END_X
        lda STAGE_ONE_RIGHT_END+1
        sta CURRENT_END_Y
        jmp end_update_stage_data
    
    load_stage_two_left_data:
        lda STAGE_TWO_LEFT_START
        sta CURRENT_START_X
        lda STAGE_TWO_LEFT_START+1
        sta CURRENT_START_Y

        lda STAGE_TWO_LEFT_END
        sta CURRENT_END_X
        lda STAGE_TWO_LEFT_END+1
        sta CURRENT_END_Y
        jmp end_update_stage_data

    load_stage_two_right_data:
        lda STAGE_TWO_RIGHT_START
        sta CURRENT_START_X
        lda STAGE_TWO_RIGHT_START+1
        sta CURRENT_START_Y

        lda STAGE_TWO_RIGHT_END
        sta CURRENT_END_X
        lda STAGE_TWO_RIGHT_END+1
        sta CURRENT_END_Y
    
    end_update_stage_data:
    pla
    tya
    pla
    tax
    pla

    rts

started_on_new_section:

    ; Save registers to stack
    pha
    txa
    pha
    tya
    pha


    pla
    tay
    pla
    tax
    pla

    rts

; BYTEARRAYS
stage_one_palettes:
.byte $0f, $00, $10, $30
.byte $0f, $01, $21, $31
.byte $0f, $06, $27, $17
.byte $0f, $09, $19, $29

.byte $0f, $00, $10, $30
.byte $0f, $01, $21, $31
.byte $0f, $06, $27, $17
.byte $0f, $09, $19, $29

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

; Stage data
STAGE_ONE_LEFT_START: .byte $00, $90
STAGE_ONE_LEFT_END: .byte $F0, $40
STAGE_ONE_RIGHT_START: .byte $00, $40
STAGE_ONE_RIGHT_END: .byte $F1, $90
STAGE_TWO_LEFT_START: .byte $00, $00
STAGE_TWO_LEFT_END: .byte $00, $00
STAGE_TWO_RIGHT_START: .byte $00, $00
STAGE_TWO_RIGHT_END: .byte $00, $00

; Stage one nametables and attributes
stage_one_left_packaged:
.incbin "assets/nametables/stage_one/stage_one_left_packaged.bin"
stage_one_left_attributes:
.incbin "assets/nametables/stage_one/stage_one_left_attributes.bin"
stage_one_right_packaged:
.incbin "assets/nametables/stage_one/stage_one_right_packaged.bin"
stage_one_right_attributes:
.incbin "assets/nametables/stage_one/stage_one_right_attributes.bin"
stage_one_data:
.incbin "assets/nametables/stage_one/stage_one_left_data.bin"
.incbin "assets/nametables/stage_one/stage_one_right_data.bin"

; Stage two nametables and attributes
stage_two_left_packaged:
.incbin "assets/nametables/stage_two/stage_two_left_packaged.bin"
stage_two_left_attributes:
.incbin "assets/nametables/stage_two/stage_two_left_attributes.bin"
stage_two_right_packaged:
.incbin "assets/nametables/stage_two/stage_two_right_packaged.bin"
stage_two_right_attributes:
.incbin "assets/nametables/stage_two/stage_two_right_attributes.bin"
stage_two_data:
.incbin "assets/nametables/stage_two/stage_two_right_data.bin"
.incbin "assets/nametables/stage_two/stage_two_left_data.bin"

; Megatiles
megatiles_stage_one:
.byte $07, $09, $27, $29 ; Only $09 and $27 are collidable
megatiles_stage_two:
.byte $0b, $0d, $2b, $2d ; Only $0d and $2b are collidable

; Character memory
.segment "CHARS"
.incbin "assets/tilesets/ants_and_bg_tiles.chr"