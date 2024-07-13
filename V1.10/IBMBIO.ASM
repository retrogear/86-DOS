; Disassembly of PC-DOS 1.00 IBMBIO.COM for SCP assembler
; taken from here: https://flyingpigtech.wordpress.com/2022/12/28/porting-86-dos-1-14-to-the-ibm-pc/
; then a few additions noted below.
; I/O System for PC-DOS version 1.00. Revised 7-22-81.
; made note about STATUS deficiency concerning AL=0
; 6/8/24 add bios support calls for date/time for 86DOS 1.1 and increased DOSSEG

SECSIZE	EQU	512		;Size of a sector
BIOSSEG	EQU	60H		;BIOS segment for the IBM PC

	ORG	0

	JMP	INIT
	JMP	STATUS
	JMP	CONIN
	JMP	CONOUT
	JMP	PRINT
	JMP	AUXIN
	JMP	AUXOUT
	JMP	READ
	JMP	WRITE
	JMP	DSKCHG
	JMP	SETDATE
	JMP	SETTIME
	JMP	GETTIME

;
; BIOS info
;
	DW	DOSSEG
	DW	VERSION

;
; BIOS version string
;
VERSION:
	DM	"BIOS Version 1.10 "
	DB	"22-Jul-81",0

;
; Out of paper error message
;
NOPAPER:
	DB	13,10
	DM	"Out of paper"
	DB	13,10,0

;
; Printer fault error message
;
PRNERR:
	DB	13,10
	DM	"Printer fault"
	DB	13,10,0

;
; AUX I/O error message
;
AUXERR:
	DB	13,10
	DM	"Aux I/O error"
	DB	13,10,0

;
; STATUS - Console input status
;
; AL contains the returned character, all other registers must be
; preserved. ZF set if character not ready, otherwise ZF is cleared.
; Also should return AL=0 if character not ready but this is handled in DOS kernel.
;
STATUS:
	SEG	CS
	MOV	AL,[LASTCHAR]	;Fetch the last returned char
	OR	AL,AL		;Get flags for it
	JNZ	STATUSRET	;Last char is not 0, return it
	PUSH	DX		;Save DX
	XCHG	AX,DX		;Save value of AX to DX
	MOV	AH,1		;Function = get keystroke status
	INT	16H		;Call keyboard BIOS service
	JZ	STATUSDONE	;No key pressed
	CMP	AX,7200H	;Check if key is CTRL + PRTSCR
	JNZ	STATUSDONE	;No, skip the next bit
	MOV	AL,10H		;Yes, set to CTRL + P
	OR	AL,AL		;Get ZF for the character

STATUSDONE:	;Restore registers for STATUS
	MOV	AH,DH		;Restore AH from value saved in DX
	POP	DX		;Restore saved DX

STATUSRET:
	RET	L

;
; BREAK handler
;
BREAK:
	SEG	CS
	MOV	B,[LASTCHAR],03H;Set char to CTRL + C
	IRET

;
; Divide overflow handler
;
DIVZERO:
	STI			;Turn interrupts on
	PUSH	AX		;Save AX
	PUSH	DX		;Save DX
	MOV	DX,DIVOVER	;Load divide overflow message
	CALL	OUTPSTR		;Print it out
	POP	DX		;Restore DX
	POP	AX		;Restore AX
	INT	23H		;Call CTRL + C handler

;
; Dummy interrupt routine
;
INTSTUB:
	IRET			;Simply return

;
; Divide overflow error message
;
DIVOVER:
	DB	13,10
	DM	"Divide overflow"
	DB	13,10,0

;
; CONIN - Console input
;
; AL contains the returned character, all other registers must be
; preserved.
;
INPRETRY:	;Restore registers and retry
	XCHG	AX,DX		;Put saved value back to AX
	POP	DX		;Restore DX

CONIN:
	MOV	AL,0		;Set AL to 0
	SEG	CS
	XCHG	AL,[LASTCHAR]	;Move last char to AL and zero last char
	OR	AL,AL		;Get flags for last char
	JNZ	INPRET		;Last char wasn't zero, done
	PUSH	DX		;Save DX
	XCHG	AX,DX		;Save value of AX to DX
	MOV	AH,0		;Function = wait and read char
	INT	16H		;Call keyboard BIOS service
	OR	AX,AX		;Get flags for AX
	JZ	INPRETRY	;Got 0, restore saved and read again
	CMP	AX,7200H	;Check for CTRL + PRTSCR
	JNZ	INPCHECK	;No, continue
	MOV	AL,10H		;Yes, change to CTRL + P

INPCHECK:	;Check if it is a special function key
	CMP	AL,0		;Check if char is 0
	JNZ	INPDONE		;No, we have a char
	SEG	CS
	MOV	[LASTCHAR],AH	;This is a function key, save scancode

INPDONE:	;Restore registers for CONIN
	MOV	AH,DH		;Restore AH from value in DX
	POP	DX		;Restore DX

INPRET:
	RET	L

;
; CONOUT - Console output
;
; AL contains the character to output to the console, all registers
; must be preserved.
;
CONOUT:
	PUSH	BP		;Save all necessary registers
	PUSH	AX
	PUSH	BX
	PUSH	SI
	PUSH	DI
	MOV	AH,0EH		;Function = write char
	SEG	CS
	MOV	BX,7		;Light gray and page number = 0
	INT	10H		;Call video BIOS service
	POP	DI		;Restore all saved registers
	POP	SI
	POP	BX
	POP	AX
	POP	BP
	RET	L

;
; PRINT - Printer output
;
; AL contains the character to output to the printer, all registers
; must be preserved.
;
PRINT:
	PUSH	AX		;Save AX
	PUSH	DX		;Save DX
	SEG	CS
	MOV	B,[PRNRETRY],0	;Clear retry flag

PRINTCHAR:
	MOV	DX,0		;Printer 0
	MOV	AH,0		;Function = print char
	INT	17H		;Call printer BIOS service
	MOV	DX,NOPAPER	;Load out of paper message
	TEST	AH,20H		;Test for out of paper bit
	JNZ	PRINTERR	;Bit is set, print error
	MOV	DX,PRNERR	;Load printer fault message
	TEST	AH,05H		;Test for time out and IO error
	JZ	PRINTDONE	;No error, done
	SEG	CS
	XOR	B,[PRNRETRY],1	;Set retry flag (to be cleared next time)
	JNZ	PRINTCHAR	;Try printing again

PRINTERR:
	CALL	OUTPSTR		;Print error message

PRINTDONE:
	POP	DX		;Restore DX
	POP	AX		;Restore AX
	RET	L

;
; Output string to console
;
OUTPSTR:
	XCHG	DX,SI		;Swap DX and SI (for LODB)

OUTPSLOOP:	;Character output loop
	SEG	CS
	LODB			;Load byte at SI to AL

	AND	AL,7FH		;Clear MSB, we used to set MSB for last
				;char to terminate strings to save space,
				;now we have moved to zero-terminated
				;strings but we still need to handle MSB-
				;terminated strings because ASM still sets
				;MSB for strings

	JZ	OUTPSDONE	;Reached end of string, break out of loop
	CALL	CONOUT,BIOSSEG	;Call BIOS CONOUT function
	JP	OUTPSLOOP	;Back to loop beginning

OUTPSDONE:
	XCHG	DX,SI		;Swap DX and SI back
	RET

;
; AUXIN - Auxiliary input
;
; AL contains the returned character, all other registers must be
; preserved.
;
AUXIN:
	PUSH	DX		;Save DX
	PUSH	AX		;Save AX
	MOV	DX,0		;Port 0
	MOV	AH,2		;Function = receive char
	INT	14H		;Call serial I/O BIOS service
	MOV	DX,AUXERR	;Load AUX error message
	TEST	AH,0EH		;Test for overrun, parity and framing errors
	JZ	AUXINDONE	;No error, done
	CALL	OUTPSTR		;Print error message

AUXINDONE:
	POP	DX		;Put saved AX into DX
	MOV	AH,DH		;Restore the original AH
	POP	DX		;Restore DX
	RET	L

;
; AUXOUT - Auxiliary output
;
; AL contains the character to output to the auxiliary output device,
; all registers must be preserved.
;
AUXOUT:
	PUSH	AX		;Save AX
	PUSH	DX		;Save DX
	MOV	AH,1		;Function = send char
	MOV	DX,0		;Port 0
	INT	14H		;Call serial I/O BIOS service
	TEST	AH,80H		;Test error bit
	JZ	PRINTDONE	;No error, done
	MOV	DX,AUXERR	;Load error message
	JP	PRINTERR	;Print it out

;
; DSKCHG - Disk change test
;
; See Programer's Manual for details. AL used as input and AX contains
; the return value. CF set on error. This is a stub implementation.
;
DSKCHG:
	MOV	AH,0		;Clear AH
	RET	L
SETDATE:
	SEG	CS
	MOV     [DAYS],AX    ; Number of days since Jan 1, 1980
	XOR     AX,AX   	; Init midnight rollover counter
	INT     1AH     	; Get time of day (clock count in CX:DX)
	RET	L
SETTIME:
	MOV     AL,60
	MUL     AX,CH      	; CH = hours
	MOV     CH,0
	ADD     AX,CX   	; CL = minutes
	MOV     CX,6000
	MOV     BX,DX
	MUL     AX,CX
	MOV     CX,AX
	MOV     AL,100
	MUL     AL,BH
	ADD     CX,AX
	ADC     DX,0
	MOV     BH,0
	ADD     CX,BX
	ADC     DX,0
	XCHG    DX,AX
	XCHG    CX,AX
	MOV     BX,59659
	MUL     AX,BX
	XCHG    CX,DX
	XCHG    DX,AX
	MUL     AX,BX
	ADD     AX,CX
	ADC     DX,0
	XCHG    DX,AX
	MOV     BX,5
	DIV     AL,BL
	MOV     CL,AL
	MOV     CH,0
	MOV     AL,AH
	CBW
	XCHG    DX,AX
	DIV     AX,BX
	MOV     DX,AX
	MOV     AH,1
	INT     1AH     	; SET TIME OF DAY, clock count in CX:DX
	RET	L
GETTIME:
	PUSH    BX
	MOV     AX,0
	INT     1AH     	; GET TIME OF DAY, clock count in CX:DX
				; AL nonzero if midnight rollover occurred
	SEG	CS
	ADD     [DAYS],AX
	MOV     AX,CX
	MOV     BX,DX
	SHL     DX
	RCL     CX
	SHL     DX
	RCL     CX
	ADD     DX,BX
	ADC     AX,CX
	XCHG    DX,AX
	MOV     CX,59659
	DIV     AX,CX
	MOV     BX,AX
	XOR     AX,AX
	DIV     AX,CX
	MOV     DX,BX
	MOV     CX,200
	DIV     AX,CX
	CMP     DL,100
	JB      NOSUB
	SUB     DL,100
NOSUB:
	CMC
	MOV     BL,DL
	RCL     AX
	MOV     DL,0
	RCL     DX
	MOV     CX,60
	DIV     AX,CX
	MOV     BH,DL
	DIV     AL,CL
	XCHG    AH,AL
	MOV     DX,BX
	XCHG    AX,CX
	SEG	CS
	MOV     AX,[DAYS]
	POP     BX
	RET	L
;
; Init hardware and device info
;
INIT:
;Setup temp stack
	CLI			;Disable interrupts
	MOV	AX,CS
	MOV	DS,AX		;DS = CS
	MOV	SS,AX		;SS = CS
	MOV	SP,STACKAREA	;Set SP to temp area
	STI			;Enable interrupts
;Setup hardware
	XOR	AH,AH		;Function = reset disk system
	INT	13H		;Call disk BIOS service
	MOV	AL,0A3H		;Serial IO params = 2400 baud, 8N1
				;Disk init must succeed (AH = 0)
	INT	14H		;Call serial I/O BIOS service
	MOV	AH,1		;Function = init printer
	INT	17H		;Call printer BIOS service
	INT	11H		;Get BIOS equipment flags
	AND	AX,0C0H		;Get number of drives
	MOV	CX,5		;Bits to shift = 5
	SHR	AX,CL		;Shift by 5 = (drives - 1) * 2
	ADD	AX,2		;Plus 2 = drives * 2
	AND	AX,06H		;Set to 0 for 4 drives
	JZ 	FLPDONE		;We have 4 drives
	CMP	AL,2		;Do we have only 1 drive?
	JNZ	MULTIFLP	;No, we have multiple drives
	SHL	AX		;Set drive count to 2 (double AX)
	MOV	B,[SNGDRV],1	;Set single drive flag

MULTIFLP:
	MOV	BX,INITTAB+1	;Load drive list
	ADD	BX,AX		;Increment pointer (2 * drives)
	MOV	[BX],0		;Buffer space = 0
	MOV	[BX+TABSTK],0	;Stack space = 0
	SHR	AX		;Divide by 2 = (drives * 2) / 2
	MOV	[INITTAB],AL	;Save drive count

FLPDONE:
	PUSH	DS		;Save DS
	MOV	AX,0
	MOV	DS,AX		;DS = 0
	MOV	AX,BIOSSEG	;Load BIOS seg
;Set BREAK handler
	MOV	[6CH + 2],AX	;Change INT 1BH seg
	MOV	[6CH],BREAK	;Change INT 1BH address
;Set divide overflow handler
	MOV	[00H],DIVZERO	;Change INT 00H address
	MOV	[00H + 2],AX	;Change INT 00H seg
;Disable all interrupts used for debugging
	MOV	BX,INTSTUB	;Load stub interrupt address
	MOV	[04H],BX	;Change INT 01H address
	MOV	[04H + 2],AX	;Change INT 01H seg
	MOV	[0CH],BX	;Change INT 03H address
	MOV	[0CH + 2],AX	;Change INT 03H seg
	MOV	[10H],BX	;Change INT 04H address
	MOV	[10H + 2],AX	;Change INT 04H seg
;Clear print screen status
	MOV	AX,50H
	MOV	DS,AX		;DS = 50H
	MOV	[00H],0		;Zero print screen flag
	MOV	DX,VERSION	;Load BIOS version
	CALL	OUTPSTR		;print it out
;Move DOS to the end of the BIOS
	PUSH	ES		;Save ES
	MOV	AX,DOSSEG
	MOV	ES,AX		;Set ES to DOS seg
	MOV	CX,5000		;DOS size in words
	CLD			;Clear DF
	MOV	AX,OLDSEG
	MOV	DS,AX		;Set DS to current DOS seg
	XOR	DI,DI		;ES:DI = DOSSEG:0000
	MOV	SI,DI		;DS:SI = OLDSEG:0000
	REP
	MOVSW			;Copy DOS
	POP	ES		;Restore ES
	POP	DS		;Restore DS
;Load 86-DOS
	MOV	SI,INITTAB	;Load drive list pointer
	CALL	0,DOSSEG	;Call DOS init
	STI			;Enable interrupts
	MOV	DX,100H		;DTA = 100H
	MOV	AH,1AH		;Function = set disk transfer address
	INT	21H		;Call DOS interrupt
	MOV	CX,[6]		;Get size of segment
	SUB	CX,100H		;Minus PSP
	MOV	BX,DS		;Save DS to BX
;DS must be set to CS so we can point to the FCB
	MOV	AX,CS
	MOV	DS,AX		;DS = CS
	MOV	DX,FCB		;Load FCB for COMMAND.COM
	MOV	AH,0FH		;Function = open file
	INT	21H		;Call DOS interrupt
	OR	AL,AL		;Get flags for AL
	JNZ	COMERR		;File not found
	MOV	[FCB+21H],0	;Record number = 0
	MOV	[FCB+23H],0
	MOV	[FCB+0EH],1	;Record size = 1
	MOV	AH,27H		;Function = random block read
	INT	21H		;Call DOS interrupt
	JCXZ	COMERR		;Error if no records read
	CMP	AL,1		;Check for EOF
	JNZ	COMERR		;Error if not end-of-file
;Make all segment registers the same
	MOV	DS,BX
	MOV	ES,BX
	MOV	SS,BX
	MOV	SP,40H		;Set stack to 64 bytes
	XOR	AX,AX
	PUSH	AX		;Put zero on top of stack for return
	MOV	DX,[80H]	;Transfer address
	MOV	AH,1AH		;Function = set disk transfer address
	INT	21H		;Call DOS interrupt
	PUSH	BX		;Put segment on stack
	MOV	AX,100H
	PUSH	AX		;Put address to execute within segment on stack
	RET	L		;Jump to COMMAND

COMERR:
	MOV	DX,BADCOM	;Load bad or missing message
	CALL	OUTPSTR		;Print it out

STALL:
	JPE	STALL		;Do nothing forever

;
; COMMAND.COM FCB
;
FCB:
	DB	01H		;Drive A
	DM	"COMMAND COM"
	DS	25

;
; Bad or missing COMMAND.COM error message
;
BADCOM:
	DB	13,10
	DM	"Bad or missing Command Interpreter"
	DB	13,10,0

;
; Explanation of tables below.
;
; INITTAB is the initialization table for 86-DOS as described in the
; 86-DOS Programer's Manual under "Customizing the I/O System."
;
; Each Drive Parameter Table (DPT) represent a different drive type,
; the only DPT for the IBM PC is SSDD8SPT (5.25" 160K SSDD). DPT has
; the following entries:
;
;       SECSIZ    2 bytes       sector size in bytes
;       CLUSSIZ   1 byte        sectors per allocation unit
;       RESSEC    2 bytes       reserved sectors
;       FATCNT    1 byte        number of allocation tables
;       MAXENT    2 bytes       number of directory entrys
;       DSKSIZ    2 bytes       number of sectors on the disk
;
INITTAB:
	DB	4		;4 I/O drivers
	DW	SSDD8SPT	;A: 8 SPT single sided double density
	DW	SSDD8SPT	;B: 8 SPT single sided double density
	DW	SSDD8SPT	;C: 8 SPT single sided double density
	DW	SSDD8SPT	;D: 8 SPT single sided double density
	DW	0		;Reserved buffer space
	DW	0		;Reserved stack space

TABBUF	EQU	0
TABSTK	EQU	2

SSDD8SPT:
	DW	512		;512 bytes/sector
	DB	1		;1 sector/allocation unit
	DW	1		;Reserve 1 boot sector
	DB	2		;2 FATs - one for backup
	DW	64		;4 directory sectors
	DW	320		;Tracks * sectors/track = disk size

DAYS	DW	0

;
; Init code and data will no longer be needed after BIOS init, so this
; area will be used as temp sector buffer. Pad it to the size of a sector
; so that useful code and data won't be overwritten.
;
	DS	INIT+SECSIZE-$

STACKAREA:
PRNRETRY:
	DB	0
LASTCHAR:
	DB	0
	DB	0
SNGDRV:
	DB	0

;
; READ - Disk read
; WRITE - Disk write
;
; AL contains the I/O driver number, AH contains the verify flag, CX
; contains the number of sectors to transfer, DX contains the logical
; sector number and DS:BX is the transfer address. CF is set on error,
; with error code in AL and CX will contain the number of sectors left.
; All registers except for segment registers may be destroyed.
;
READ:
	MOV	AH,2		;Function = read
	JP	DISKIO

WRITE:
	MOV	AH,3		;Function = write

DISKIO:		;Main disk transfer logic
	PUSH	ES		;Save ES
	PUSH	DS		;Save DS
	PUSH	DS
	POP	ES		;ES = DS
	PUSH	CS
	POP	DS		;DS = CS
	MOV	[SPSAVE],SP	;Save SP
	MOV	[DISKOP],AH	;Save function ID
	CMP	B,[SNGDRV],SNGFLG	;Do we have only one drive?
	JNZ	TRANSINIT	;No
	PUSH	DS		;Save DS
	XOR	SI,SI
	MOV	DS,SI		;DS = 0
	MOV	AH,AL
	XCHG	AH,[504H]	;Swap with single drive mode status byte
	POP	DS		;Restore DS
	CMP	AL,AH		;Check if they're the same
	JZ	SKIPSWAP	;Yes, no need to swap
	PUSH	DX		;Save DX
	ADD	AL,"A"		;Convert ID to ASCII
	MOV	[DRVLETTER],AL	;Drive letter
	MOV	DX,SWAPMSG	;Load swap disk message
	CALL	OUTPSTR		;Print it out
	PUSH	DS		;Save DS
	XOR	BP,BP
	MOV	DS,BP		;DS = 0
	MOV	B,[41AH],1EH	;Flush keyboard
	MOV	B,[41CH],1EH
	POP	DS		;Restore DS
	MOV	AH,0		;Function = wait and read
	INT	16H		;Call keyboard BIOS service
	POP	DX		;Restore DX

SKIPSWAP:	;Select drive 0
	MOV	AL,0		;The physical drive A

TRANSINIT:	;Setup variables and check for 64K limitation
	XCHG	AX,DX		;AX = logical sector number, DL = drive ID
	MOV	DH,SPT
	DIV	AX,DH		;Divide sect number by SPT (track ID in AL)
	INC	AH		;Increment sect ID (sect ID starts at 1)
	XCHG	AL,AH		;AL = sect ID, AH = track ID
	XCHG	AX,CX		;AX = count, CL = sect ID, CH = track ID
	MOV	[SECTLEFT],AX	;Save count (sectors to transfer)
	MOV	DH,0		;Head 0
	MOV	DI,ES		;Convert ES:BX to linear address
	SHL	DI
	SHL	DI
	SHL	DI
	SHL	DI
	ADD	DI,BX		;Result in DI
	ADD	DI,SECSIZE-1	;Last byte of the sector
	JC	WORKAROUND	;Overflows, first sect crosses 64K boundary
	XCHG	DI,BX		;BX = ptr to last byte, DI = trans address low
	SHR	BH		;Number of sectors
	MOV	AH,80H		;Number of sectors in 64K
	SUB	AH,BH		;AH = number of sectors until boundary
	MOV	BX,DI		;BX = transfer address low
	CMP	AH,AL		;Compare sectors left and sector ID
	JBE	UNTIL64K	;Not enough space left until 64K boundary
	MOV	AH,AL		;Can do it at once

UNTIL64K:	;Transfer AH sectors at once
	PUSH	AX		;Save AX
	MOV	AL,AH		;AL = sectors to transfer
	CALL	TRANSFER	;Transfer sectors
	POP	AX		;Restore AX
	SUB	AL,AH		;Subtract completed sectors
	JZ	DISKIODONE	;Got 0 left, all done

WORKAROUND:	;Workaround for DMA access across 64K boundary
	DEC	AL		;Decrement sectors to transfer
	PUSH	AX		;Save AX
	CLD			;Ensure incrementing operation
	PUSH	BX		;Save BX
	PUSH	ES		;Save ES
	CMP	B,[DISKOP],RSECT;Check if operation is read
	JZ	RACROSS64K	;Yes, perform read
	MOV	SI,BX		;Source = BX (transfer address low)
	PUSH	CX		;Save CX
	MOV	CX,256		;Sector length in words
	PUSH	ES
	POP	DS		;DS = ES
	PUSH	CS
	POP	ES		;ES = CS
	MOV	DI,INIT		;ES:DI = CS:INIT
	MOV	BX,DI		;Preserve DI before copy
	REP
	MOVSW			;Copy sector to temp area in BIOS
	POP	CX		;Restore CX
	PUSH	CS
	POP	DS		;DS = CS
	CALL	SINGLETRANS	;Transfer this one sector
	POP	ES		;Restore ES
	POP	BX		;Restore BX
	JP	DOREMAINING	;Finish off the rest of the sectors

RACROSS64K:	;Read to address that crosses 64K boundaries
	MOV	BX,INIT		;Temp area in BIOS
	PUSH	CS
	POP	ES		;ES = CS
	CALL	SINGLETRANS	;Read this one sector to temp area
	MOV	SI,BX		;Temp area is now source
	POP	ES		;Restore ES
	POP	BX		;Restore BX
	MOV	DI,BX		;Destination is original BX
	PUSH	CX		;Save CX
	MOV	CX,256		;Sector size in words
	REP
	MOVSW			;Copy sector from temp area to destination
	POP	CX		;Restore CX

DOREMAINING:	;Transfer sectors after the 64K boundary
	ADD	BH,SSIZEHI	;Increment by sector size
	POP	AX		;Restore AX
	CALL	TRANSFER	;Transfer the remaining sectors

DISKIODONE:
	POP	DS		;Restore DS
	POP	ES		;Restore ES
	CLC			;Clear CF (indicate success)
	RET	L

;
; Transfer AL number of sectors
;
TRANSFER:
	OR	AL,AL		;Get flags for sectors to transfer
	JZ	RWDONE		;0 left, read/write of sectors is done
	MOV	AH,SPT+1	;SPT + 1 (add 1 to include current sector)
	SUB	AH,CL		;Take away sect ID, left with remaining ones
	CMP	AH,AL		;Sects left in track against to transfer
	JBE	RWTRACK		;Sectors left <= sectors left in track
	MOV	AH,AL		;Transfer sectors that are left in this track

RWTRACK:	;Read/write sects in current track
	PUSH	AX		;Save AX
	MOV	AL,AH		;AL = sectors to transfer
	CALL	SECTTRANS	;Transfer sectors
	POP	AX		;Restore AX
	SUB	AL,AH		;Decrement sectors left
	SHL	AH		;AH = high byte of transferred bytes
	ADD	BH,AH		;Increment transfer address
	JP	TRANSFER	;Transfer sectors for next track

RWERROR:	;Disk read/write error handler
	XCHG	AX,DI		;Save error code in DI
	MOV	AH,0		;Function = reset disk system
	INT	13H		;Call disk BIOS service
	DEC	SI		;Decrement number of retries
	JZ	ERRLOOKUP	;No retries left, error out
	MOV	AX,DI		;Error code to AX
	CMP	AH,80H		;Check if error is time out
	JZ	ERRLOOKUP	;Yes, don't retry
	POP	AX		;Restore AX
	JP	RWSECT		;Retry reading/writing sectors

ERRLOOKUP:	;Convert to DOS error code and return
	PUSH	CS
	POP	ES		;ES = CS
	MOV	AX,DI		;Error code to AX
	MOV	AL,AH		;Error code to AL
	MOV	CX,10		;10 entries in the table
	MOV	DI,ERRTABLE	;ES:DI points to the error table
	REPNE
	SCASB			;Compare error code
	MOV	AL,[DI+ERRCNT-1];Convert to DOS error code
	MOV	CX,[SECTLEFT]	;Sectors left
	MOV	SP,[SPSAVE]	;Restore original SP
	POP	DS		;Restore original DS
	POP	ES		;Restore original ES
	STC			;Set carry flag (indicate error)
	RET	L

SINGLETRANS:	;Transfer a single sector
	MOV	AL,1		;Transfer 1 sector only

SECTTRANS:	;Transfer multiple sectors
	MOV	SI,5		;We want to retry 5 times
	MOV	AH,[DISKOP]	;Load operation (read/write)

RWSECT:		;Plain read/write sectors
	PUSH	AX		;Save AX
	INT	13H		;Call disk BIOS service
	JC	RWERROR		;Error happened
	POP	AX		;Restore AX
	SUB	[SECTLEFT],AL	;Take away the ones already read/written
	ADD	CL,AL		;Sector ID after read/write
	CMP	CL,SPT		;Compare against sectors per track
	JBE	RWDONE		;Below or equal, we are done
	INC	CH		;Next track
	MOV	CL,1		;Sector ID = 1

RWDONE:		;Read/write of sectors done
	RET

;
; Disk swap message
;

SWAPMSG:
	DB	13,10
	DM	"Insert diskette for drive "
DRVLETTER:
	DM	"A: and strike"
	DB	13,10
	DM	"any key when ready"
	DB	13,10,10,0

;
; BIOS and DOS disk I/O error conversion table
;

ERRTABLE:
	DB	80H		;Time out, not ready
	DB	40H		;Seek failure
	DB	20H		;Controller error
	DB	10H		;CRC error
	DB	09H		;DMA access across 64K boundary
	DB	08H		;DMA overrun
	DB	04H		;Sector not found
	DB	03H		;Write protected
	DB	02H		;Address mark not found or bad sector
	DB	01H		;Bad command
ERRCNT	EQU	$-ERRTABLE
	DB	02H		;Not ready
	DB	06H		;Seek error
	DB	0CH		;Disk error
	DB	04H		;Data error
	DB	0CH		;Disk error
	DB	04H		;Data error
	DB	08H		;Sector not found
	DB	00H		;Write protected
	DB	0CH		;Disk error
	DB	0CH		;Disk error

DISKOP:
	DB	RSECT		;Disk operation, default to read
SPSAVE:
	DW	0		;For saving SP
SECTLEFT:
	DW	0		;For number of sectors to read/write

DOSSEG	EQU	0BFH		;(($)/16)+BIOSSEG 5B0H/16+60H=BBH minimum. PCDOS 1.1 used BFH.
SPT	EQU	8		;Sectors per track
RSECT	EQU	2		;INT 13H command for read
WSECT	EQU	3		;INT 13H command for write
SNGFLG	EQU	1		;Flag for single drive
SSIZEHI	EQU	2		;High byte of sector size

	DS	512
	DB	0C9H		;End of object code
	DS	200H-$		;fill to end of 512 byte boot sector

OLDSEG	EQU	0E0H		;((($+SECSIZE-1)/SECSIZE)*SECSIZE/16)+BIOSSEG
