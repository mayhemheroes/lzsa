; -----------------------------------------------------------------------------
; Decompress raw LZSA2 block.
; Create one with lzsa -r -f2 <original_file> <compressed_file>
;
; in:
; * LZSA_SRC_LO and LZSA_SRC_HI contain the compressed raw block address
; * LZSA_DST_LO and LZSA_DST_HI contain the destination buffer address
;
; out:
; * LZSA_DST_LO and LZSA_DST_HI contain the last decompressed byte address, +1
; -----------------------------------------------------------------------------
;
;  Copyright (C) 2019 Emmanuel Marty
;
;  This software is provided 'as-is', without any express or implied
;  warranty.  In no event will the authors be held liable for any damages
;  arising from the use of this software.
;
;  Permission is granted to anyone to use this software for any purpose,
;  including commercial applications, and to alter it and redistribute it
;  freely, subject to the following restrictions:
;
;  1. The origin of this software must not be misrepresented; you must not
;     claim that you wrote the original software. If you use this software
;     in a product, an acknowledgment in the product documentation would be
;     appreciated but is not required.
;  2. Altered source versions must be plainly marked as such, and must not be
;     misrepresented as being the original software.
;  3. This notice may not be removed or altered from any source distribution.
; -----------------------------------------------------------------------------

NIBCOUNT = $FC                          ; zero-page location for temp offset

DECOMPRESS_LZSA2
   LDY #$00
   STY NIBCOUNT

DECODE_TOKEN
   JSR GETSRC                           ; read token byte: XYZ|LL|MMM
   PHA                                  ; preserve token on stack

   AND #$18                             ; isolate literals count (LL)
   BEQ NO_LITERALS                      ; skip if no literals to copy
   CMP #$18                             ; LITERALS_RUN_LEN_V2 << 3?
   BNE EMBEDDED_LITERALS                ; if less, count is directly embedded in token

   JSR GETNIBBLE                        ; get extra literals length nibble
                                        ; add nibble to len from token
   ADC #$02                             ; (LITERALS_RUN_LEN_V2) minus carry
   CMP #$12                             ; LITERALS_RUN_LEN_V2 + 15 ?
   BNE PREPARE_COPY_LITERALS            ; if less, literals count is complete

   JSR GETSRC                           ; get extra byte of variable literals count
                                        ; the carry is always set by the CMP above
                                        ; GETSRC doesn't change it
   SBC #$EE                             ; overflow?
   BCC PREPARE_COPY_LITERALS            ; if not, literals count is complete

                                        ; handle 16 bits literals count
                                        ; literals count = directly these 16 bits
   JSR GETLARGESRC                      ; grab low 8 bits in X, high 8 bits in A
   TAY                                  ; put high 8 bits in Y
   BCS PREPARE_COPY_LITERALS_HIGH       ; (*like JMP PREPARE_COPY_LITERALS_HIGH but shorter)

EMBEDDED_LITERALS
   LSR A                                ; shift literals count into place
   LSR A
   LSR A

PREPARE_COPY_LITERALS
   TAX
PREPARE_COPY_LITERALS_HIGH
   INY

COPY_LITERALS
   JSR GETPUT                           ; copy one byte of literals
   DEX
   BNE COPY_LITERALS
   DEY
   BNE COPY_LITERALS
   
NO_LITERALS
   PLA                                  ; retrieve token from stack
   PHA                                  ; preserve token again
   ASL
   BCS REPMATCH_OR_LARGE_OFFSET         ; 1YZ: rep-match or 13/16 bit offset

   ASL                                  ; 0YZ: 5 or 9 bit offset
   BCS OFFSET_9_BIT         
    
                                        ; 00Z: 5 bit offset

   LDX #$0FF                            ; set offset bits 15-8 to 1

   JSR GETCOMBINEDBITS                  ; rotate Z bit into bit 0, read nibble for bits 4-1
   ORA #$E0                             ; set bits 7-5 to 1
   BNE GOT_OFFSET_LO                    ; go store low byte of match offset and prepare match
   
OFFSET_9_BIT                            ; 01Z: 9 bit offset
   ;;ASL                                  ; shift Z (offset bit 8) in place
   ROL
   ROL
   AND #$01
   EOR #$FF                             ; set offset bits 15-9 to 1
   BNE GOT_OFFSET_HI                    ; go store high byte, read low byte of match offset and prepare match
                                        ; (*same as JMP GOT_OFFSET_HI but shorter)

REPMATCH_OR_LARGE_OFFSET
   ASL                                  ; 13 bit offset?
   BCS REPMATCH_OR_16_BIT               ; handle rep-match or 16-bit offset if not

                                        ; 10Z: 13 bit offset

   JSR GETCOMBINEDBITS                  ; rotate Z bit into bit 8, read nibble for bits 12-9
   ADC #$DE                             ; set bits 15-13 to 1 and substract 2 (to substract 512)
   BNE GOT_OFFSET_HI                    ; go store high byte, read low byte of match offset and prepare match
                                        ; (*same as JMP GOT_OFFSET_HI but shorter)

REPMATCH_OR_16_BIT                      ; rep-match or 16 bit offset
   ;;ASL                                  ; XYZ=111?
   BMI REP_MATCH                        ; reuse previous offset if so (rep-match)
   
                                        ; 110: handle 16 bit offset
   JSR GETSRC                           ; grab high 8 bits
GOT_OFFSET_HI
   TAX
   JSR GETSRC                           ; grab low 8 bits
GOT_OFFSET_LO
   STA OFFSLO                           ; store low byte of match offset
   STX OFFSHI                           ; store high byte of match offset

REP_MATCH
   CLC                                  ; add dest + match offset
   LDA PUTDST+1                         ; low 8 bits
OFFSLO = *+1
   ADC #$AA
   STA COPY_MATCH_LOOP+1                ; store back reference address
OFFSHI = *+1
   LDA #$AA                             ; high 8 bits
   ADC PUTDST+2
   STA COPY_MATCH_LOOP+2                ; store high 8 bits of address
   
   PLA                                  ; retrieve token from stack again
   AND #$07                             ; isolate match len (MMM)
   ADC #$01                             ; add MIN_MATCH_SIZE_V2 and carry
   CMP #$09                             ; MIN_MATCH_SIZE_V2 + MATCH_RUN_LEN_V2?
   BNE PREPARE_COPY_MATCH               ; if less, length is directly embedded in token

   JSR GETNIBBLE                        ; get extra match length nibble
                                        ; add nibble to len from token
   ADC #$08                             ; (MIN_MATCH_SIZE_V2 + MATCH_RUN_LEN_V2) minus carry
   CMP #$18                             ; MIN_MATCH_SIZE_V2 + MATCH_RUN_LEN_V2 + 15?
   BNE PREPARE_COPY_MATCH               ; if less, match length is complete

   JSR GETSRC                           ; get extra byte of variable match length
                                        ; the carry is always set by the CMP above
                                        ; GETSRC doesn't change it
   SBC #$E8                             ; overflow?
   BCC PREPARE_COPY_MATCH               ; if not, the match length is complete
   BEQ DECOMPRESSION_DONE               ; if EOD code, bail

                                        ; Handle 16 bits match length
   JSR GETLARGESRC                      ; grab low 8 bits in X, high 8 bits in A
   TAY                                  ; put high 8 bits in Y
   .DB $A9                              ; mask TAX, faster than TXA/TAX

PREPARE_COPY_MATCH
   TAX
PREPARE_COPY_MATCH_Y
   INY

COPY_MATCH_LOOP
   LDA $AAAA                            ; get one byte of backreference
   INC COPY_MATCH_LOOP+1
   BEQ GETMATCH_INC_HI
GETMATCH_DONE
   JSR PUTDST                           ; copy to destination
   DEX
   BNE COPY_MATCH_LOOP
   DEY
   BNE COPY_MATCH_LOOP
   JMP DECODE_TOKEN
GETMATCH_INC_HI
   INC COPY_MATCH_LOOP+2
   BNE GETMATCH_DONE                    ; (*like JMP GETMATCH_DONE but shorter)

GETCOMBINEDBITS
   EOR #$80
   ASL
   PHP

   JSR GETNIBBLE                        ; get nibble into bits 0-3 (for offset bits 1-4)
   PLP                                  ; merge Z bit as the carry bit (for offset bit 0)
COMBINEDBITZ
   ROL                                  ; nibble -> bits 1-4; carry(!Z bit) -> bit 0 ; carry cleared
   RTS

GETNIBBLE
NIBBLES = *+1
   LDA #$AA
   LSR NIBCOUNT
   BCS HAS_NIBBLES

   INC NIBCOUNT
   JSR GETSRC                           ; get 2 nibbles
   STA NIBBLES
   LSR 
   LSR 
   LSR 
   LSR 
   SEC

HAS_NIBBLES
   AND #$0F                             ; isolate low 4 bits of nibble
   RTS

GETPUT
   JSR GETSRC
PUTDST
LZSA_DST_LO = *+1
LZSA_DST_HI = *+2
   STA $AAAA
   INC PUTDST+1
   BEQ PUTDST_INC_HI
PUTDST_DONE
DECOMPRESSION_DONE
   RTS
PUTDST_INC_HI
   INC PUTDST+2
   RTS

GETLARGESRC
   JSR GETSRC                           ; grab low 8 bits
   TAX                                  ; move to X
                                        ; fall through grab high 8 bits

GETSRC
LZSA_SRC_LO = *+1
LZSA_SRC_HI = *+2
   LDA $AAAA
   INC GETSRC+1
   BEQ GETSRC_INC_HI
GETSRC_DONE
   RTS
GETSRC_INC_HI
   INC GETSRC+2
   RTS
