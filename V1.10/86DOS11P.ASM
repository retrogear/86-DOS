;TITLE	86DOS V1.10	[6-2-24]
;
;Disassembly of 86DOS V1.10 with notes from Tim Paterson's V1.25 source.
;Converted for Seattle Computer Product's assembler.
;Last edit 6/26/24 changes made for IBM PC see ## in comments.
;
; ****************** Revision History *************************
;          >> EVERY change must noted below!! <<
;
; 0.34 12/29/80 General release, updating all past customers
; 0.42 02/25/81 32-byte directory entries added
; 0.56 03/23/81 Variable record and sector sizes
; 0.60 03/27/81 Ctrl-C exit changes, including register save on user stack
; 0.74 04/15/81 Recognize I/O devices with file names
; 0.75 04/17/81 Improve and correct buffer handling
; 0.76 04/23/81 Correct directory size when not 2^N entries
; 0.80 04/27/81 Add console input without echo, Functions 7 & 8
; 1.00 04/28/81 Renumber for general release
; 1.01 05/12/81 Fix bug in `STORE'
; 1.10 07/21/81 Fatal error trapping, NUL device, hidden files, date & time,
;               RENAME fix, general cleanup
;
; *************************************************************


LF	EQU	0AH
CR	EQU	0DH
MAXCALL	EQU	36
MAXCOM	EQU	45
INTBASE	EQU	80H			;interrupt base set by Intel

; Field definition for FCBs

FNAME   EQU     0       ;Drive code and name
EXTENT  EQU     12
RECSIZ  EQU     14      ;Size of record (user settable)
FILSIZ  EQU     16      ;Size of file in bytes
DRVBP   EQU     18      ;BP for SEARCH FIRST and SEARCH NEXT
FDATE   EQU     20      ;Date of last writing
FTIME   EQU     22      ;Time of last writing
DEVID   EQU     22      ;Device ID number, bits 0-5
                        ;bit 7=0 for file, bit 7=1 for I/O device
                        ;If file, bit 6=0 if dirty
                        ;If I/O device, bit 6=0 if EOF (input)
FIRCLUS EQU     24      ;First cluster of file
LSTCLUS EQU     26      ;Last cluster accessed
CLUSPOS EQU     28      ;Position of last cluster accessed
NR      EQU     32      ;Next record
RR      EQU     33      ;Random record
FILDIRENT EQU	22	;Used only by SEARCH FIRST and SEARCH NEXT

; Description of 32-byte directory entry (same as returned by SEARCH FIRST
; and SEARCH NEXT, functions 17 and 18).
;
; Location      bytes   Description
;
;    0          11      File name and extension ( 0E5H if empty)
;   11           1      Attributes. Bits 1 or 2 make file hidden
;   12          10      Zero field (for expansion)
;   22           2      Time. Bits 0-4=seconds/2, bits 5-10=minute, 11-15=hour
;   24           2      Date. Bits 0-4=day, bits 5-8=month, bits 9-15=year-1980
;   26           2      First allocation unit ( < 4080 )
;   28           4      File size, in bytes (LSB first, 30 bits max.)
;
; The File Allocation Table uses a 12-bit entry for each allocation unit on
; the disk. These entries are packed, two for every three bytes. The contents
; of entry number N is found by 1) multiplying N by 1.5; 2) adding the result
; to the base address of the Allocation Table; 3) fetching the 16-bit word at
; this address; 4) If N was odd (so that N*1.5 was not an integer), shift the
; word right four bits; 5) mask to 12 bits (AND with 0FFF hex). Entry number
; zero is used as an end-of-file trap in the OS and as a flag for directory
; entry size (if SMALLDIR selected). Entry 1 is reserved for future use. The
; first available allocation unit is assigned entry number two, and even
; though it is the first, is called cluster 2. Entries greater than 0FF8H are
; end of file marks; entries of zero are unallocated. Otherwise, the contents
; of a FAT entry is the number of the next cluster in the file.

; Field definition for Drive Parameter Block

DEVNUM  EQU     0       ;I/O driver number
DRVNUM  EQU     0       ;Physical Unit number
SECSIZ  EQU     1       ;Size of physical sector in bytes
CLUSMSK EQU     3       ;Sectors/cluster - 1
CLUSSHFT EQU    4       ;Log2 of sectors/cluster
FIRFAT  EQU     5       ;Starting record of FATs
FATCNT  EQU     7       ;Number of FATs for this drive
MAXENT  EQU     8       ;Number of directory entries
FIRREC  EQU     10      ;First sector of first cluster
MAXCLUS EQU     12      ;Number of clusters on drive + 1
FATSIZ  EQU     14      ;Number of records occupied by FAT
FIRDIR  EQU     15      ;Starting record of directory
FAT     EQU     26      ;Pointer to start of FAT

DPBSIZ  EQU     20      ;Size of the structure in bytes

; BIOS entry point definitions

BIOSSEG		EQU     60H	;## for IBM PC

BIOSINIT        EQU     0       ;Reserve room for jump to init code
BIOSSTAT        EQU     3       ;Console input status check
BIOSIN          EQU     6       ;Get console character
BIOSOUT         EQU     9       ;Output console character
BIOSPRINT       EQU     12      ;Output to printer
BIOSAUXIN       EQU     15      ;Get byte from auxilliary
BIOSAUXOUT      EQU     18      ;Output byte to auxilliary
BIOSREAD        EQU     21      ;Disk read
BIOSWRITE       EQU     24      ;Disk write
BIOSDSKCHG      EQU     27      ;Disk-change status
BIOSSETDATE     EQU     30      ;Set date
BIOSSETTIME     EQU     33      ;Set time
BIOSGETTIME     EQU     36      ;Get time and date

; Location of user registers relative user stack pointer

AXSAVE  EQU     0
BXSAVE  EQU     2
CXSAVE  EQU     4
DXSAVE  EQU     6
SISAVE  EQU     8
DISAVE  EQU     10
BPSAVE  EQU     12
DSSAVE  EQU     14
ESSAVE  EQU     16
IPSAVE  EQU     18
CSSAVE  EQU     20
FSAVE   EQU     22

;from 86-DOS Instruction Manual page 14
;conditions to load and execute a program:

L0000	EQU	$	;Termination point. Contains INT 20H
	ORG	$+2
L0002	EQU	$	;Memory size. The first segment # after the end of memory. [ENDMEM]
	ORG	$+3
L0005	EQU	$	;Function request entry point.
	ORG	$+1
L0006	EQU	$	;Segment size. # of bytes available in the program segment.
	ORG	$+2
L0008	EQU	$	;Reserved.
	ORG	$+2
SAVEXIT	EQU	$	;Terminate address in displacement:segment format.

; Interrupt Entry Points:

; INTBASE:      ABORT			INT 20H program terminate
; INTBASE+4:    COMMAND			INT 21H function request
; INTBASE+8:    BASE EXIT ADDRESS	INT 22H terminate address
; INTBASE+C:    CONTROL-C ABORT		INT 23H ctrl-c
; INTBASE+10H:  FATAL ERROR ABORT	INT 24H not mentioned
; INTBASE+14H:  BIOS DISK READ		INT 25H absolute disk read
; INTBASE+18H:  BIOS DISK WRITE		INT 26H absolute disk write
; INTBASE+40H:  Long jump to CALL entry point

EXIT		EQU	INTBASE+8	;88h base exit address
ENTRYPOINT	EQU	INTBASE+40H	;C0h contains long jump opcode
ENTRYPOINTSEG 	EQU	ENTRYPOINT/16	;entrypoint segment
ENTRYADDR 	EQU	ENTRYPOINT+1	;entry address
ENTRYSEG 	EQU	ENTRYPOINT+3	;entry segment

	ORG	0

CODSTRT	EQU	$		;start of code

	JMP	DOSINIT

ESCTAB:
        DB      "SC"     ;Copy one character from template
        DB      "VN"     ;Skip over one character in template
        DB      "TA"     ;Copy up to specified character
        DB      "WB"     ;Skip up to specified character
        DB      "UH"     ;Copy rest of template
        DB      "HH"     ;Kill line with no change in template (Ctrl-X)
        DB      "RM"     ;Cancel line and update template
        DB      "DD"     ;Backspace (same as Ctrl-H)
        DB      "P@"     ;Enter Insert mode
        DB      "QL"     ;Exit Insert mode
        DB      1BH,1BH  ;Escape sequence to represent escape character
	DB	1BH,1BH
ESCTABLEN EQU	$-ESCTAB

HEADER	DB	CR,LF,'86-DOS version 1.10',CR,LF
	DB	'Copyright 1980',2CH
	DB	'81 Seattle Computer Products',2CH,' Inc.',CR,LF,'$'

QUIT:	MOV	AH,0
	JP	SAVREGS

COMMAND:
	CMP	AH,MAXCOM
	JBE	SAVREGS
BADCALL:
	MOV	AL,0
IRET:	IRET

ENTRY:	POP	AX
	POP	AX
	SEG	CS
	POP	[TEMP]
	PUSHF
	CLI
	PUSH	AX
	SEG	CS
	PUSH	[TEMP]
	CMP	CL,MAXCALL
	JA	BADCALL
	MOV	AH,CL
SAVREGS:
	PUSH	ES
	PUSH	DS
	PUSH	BP
	PUSH	DI
	PUSH	SI
	PUSH	DX
	PUSH	CX
	PUSH	BX
	PUSH	AX
	SEG	CS
	MOV	[SPSAVE],SP
	SEG	CS
	MOV	[SSSAVE],SS
	MOV	SP,CS
	MOV	SS,SP
REDISP:	MOV	SP,IOSTACK
	STI
	MOV	BL,AH
	MOV	BH,0
	SHL	BX
	CLD
	CMP	AH,12
	JLE	SAMSTK
	MOV	SP,DSKSTACK
SAMSTK:	SEG	CS
	CALL	[BX+DISPATCH]
	CLI
	SEG	CS
	MOV	SP,[SPSAVE]
	SEG	CS
	MOV	SS,[SSSAVE]
	MOV	BP,SP
	MOV	[BP+AXSAVE],AL
	POP	AX
	POP	BX
	POP	CX
	POP	DX
	POP	SI
	POP	DI
	POP	BP
	POP	DS
	POP	ES
	IRET

DISPATCH
	DW	ABORT           ;0
        DW      CONIN
        DW      CONOUT
        DW      READER
        DW      PUNCH
        DW      LIST            ;5
        DW      RAWIO
        DW      RAWINP
        DW      IN
        DW      PRTBUF
        DW      BUFIN           ;10
        DW      CONSTAT
        DW      FLUSHKB
        DW      DSKRESET
        DW      SELDSK
        DW      OPEN            ;15
        DW      CLOSE
        DW      SRCHFRST
        DW      SRCHNXT
        DW      DELETE
        DW      SEQRD           ;20
        DW      SEQWRT
        DW      CREATE
        DW      RENAME
        DW      INUSE
        DW      GETDRV          ;25
        DW      SETDMA
        DW      GETFATPT
        DW      GETFATPTDL
        DW      GETRDONLY
        DW      SETATTRIB       ;30
        DW      GETDSKPT
        DW      USERCODE
        DW      RNDRD
        DW      RNDWRT
        DW      FILESIZE        ;35
        DW      SETRNDREC
; Extended Functions
        DW      SETVECT
        DW      NEWBASE
        DW      BLKRD
        DW      BLKWRT          ;40
        DW      MAKEFCB
        DW      GETDATE
        DW      SETDATE
        DW      GETTIME
        DW      SETTIME         ;45

INUSE:
GETFATPTDL:
GETRDONLY:
SETATTRIB:
USERCODE:
	MOV	AL,0
	RET

FLUSHKB:
	MOV	AH,AL
	CMP	AL,1
	JZ	REDISPJ
	CMP	AL,6
	JZ	REDISPJ
	CMP	AL,7
	JZ	REDISPJ
	CMP	AL,8
	JZ	REDISPJ
	CMP	AL,0AH
	JZ	REDISPJ
	MOV	AL,0
	RET

REDISPJ:
	JMP	REDISP

READER:	CALL	STATCHK
	CALL	BIOSAUXIN,BIOSSEG
	RET

PUNCH:	MOV	AL,DL
AUXOUT:	PUSH	AX
	CALL	STATCHK
	POP	AX
	CALL	BIOSAUXOUT,BIOSSEG
	RET

UNPACK:

; Inputs:
;       DS = CS
;       BX = Cluster number
;       BP = Base of drive parameters
;       SI = Pointer to drive FAT
; Outputs:
;       DI = Contents of FAT for given cluster
;       Zero set means DI=0 (free cluster)
; No other registers affected. Fatal error if cluster too big.

	CMP	BX,[BP+MAXCLUS]
	JA	HURTFAT
	LEA	DI,[BX+SI]
	SHR	BX
	MOV	DI,[BX+DI]
	JNB	HAVCLUS
	SHR	DI
	SHR	DI
	SHR	DI
	SHR	DI
	STC
HAVCLUS:
	RCL	BX
	AND	DI,0FFFH
	RET

HURTFAT:
	PUSH	AX
	MOV	AH,80H
	MOV	DI,0FFFH
	CALL	FATAL
	POP	AX
	RET

PACK:

; Inputs:
;       DS = CS
;       BX = Cluster number
;       DX = Data
;       SI = Pointer to drive FAT
; Outputs:
;       The data is stored in the FAT at the given cluster.
;       BX,DX,DI all destroyed
;       No other registers affected

	MOV	DI,BX
	SHR	BX
	ADD	BX,SI
	ADD	BX,DI
	SHR	DI
	MOV	DI,[BX]
	JNB	ALIGNED
	SHL	DX
	SHL	DX
	SHL	DX
	SHL	DX
	AND	DI,000FH
	JP	PACKIN

ALIGNED:
	AND	DI,0F000H
PACKIN:	OR	DI,DX
	MOV	[BX],DI
	RET

DEVNAME:
	MOV	SI,IONAME
	MOV	BX,0FF05H		;BL = number of device names
LOOKIO:	MOV	DI,NAME1
	MOV	CX,3
	REPE
	CMPB
	JZ	IOCHK
	ADD	SI,CX
	DEC	BL
	JNZ	LOOKIO
CRET:	STC
	RET

IOCHK:	DEC	BL
	MOV	CX,5
	MOV	AL,20H	;' '
	REPE
	SCAB
	JNZ	CRET
RET1:	RET

GETFILE:

; Same as GETNAME except ES:DI points to FCB on successful return

	CALL	MOVNAME
	JB	RET1
	PUSH	DX
	PUSH	DS
	CALL	FINDNAME
	POP	ES
	POP	DI
RET2:	RET

GETNAME:

; Inputs:
;       DS,DX point to FCB
; Function:
;       Find file name in disk directory. First byte is
;       drive number (0=current disk). "?" matches any
;       character.
; Outputs:
;       Carry set if file not found
;       ELSE
;       Zero set if attributes match (always except when creating)
;       BP = Base of drive parameters
;       DS = CS
;       ES = CS
;       BX = Pointer into directory buffer
;       SI = Pointer to First Cluster field in directory entry
;       [DIRBUF] has directory record with match
;       [NAME1] has file name
; All other registers destroyed.

	CALL	MOVNAME
	JB	RET2
FINDNAME:
	MOV	AX,CS
	MOV	DS,AX
	CALL	DEVNAME
	JNB	RET2
	CALL	STARTSRCH
CONTSRCH:
	CALL	GETENTRY
	JB	RET2
SRCH:	CMP	B,[BX],0E5H
	JZ	NEXTENT
	MOV	SI,BX
	MOV	DI,NAME1
	MOV	CX,11
WILDCRD:
	REPE
	CMPB
	JZ	FREE
	CMP	B,[DI-1],'?'
	JZ	WILDCRD
NEXTENT:
	CALL	NEXTENTRY
	JNB	SRCH
RET3:	RET

FREE:
	CMP	B,[BP+26],-1
	JZ	RET3
FOUND:

;Check if attributes allow finding it

	MOV	AH,[ATTRIB]
	NOT	AH
	AND	AH,[SI]
	ADD	SI,000FH
	AND	AH,6
	JZ	RET3
	TEST	B,[CREATING],-1
	JZ	NEXTENT
	RET

GETENTRY:

; Inputs:
;       [LASTENT] has previously searched directory entry
; Function:
;       Locates next sequential directory entry in preparation for search
; Outputs:
;       Carry set if none
;       ELSE
;       AL = Current directory block
;       BX = Pointer to next directory entry in [DIRBUF]
;       DX = Pointer to first byte after end of DIRBUF
;       [LASTENT] = New directory entry number

	MOV	AX,[LASTENT]
	INC	AX
	CMP	AX,[BP+MAXENT]
	JNB	NONE
GETENT:	MOV	[LASTENT],AX
	MOV	CL,4
	SHL	AX,CL
	XOR	DX,DX
	CMP	B,[BP+26],-1
	JZ	L024D
	SHL	AX
	RCL	DX
L024D:	MOV	BX,[BP+SECSIZ]
	AND	BL,255-31		;must be multiple of 32
	DIV	AX,BX
	MOV	BX,DX
	MOV	AH,[BP+DEVNUM]
	CMP	AX,[DIRBUFID]
	JZ	HAVDIRBUF
	PUSH	BX
	CALL	DIRREAD
	POP	BX
HAVDIRBUF:
	MOV	DX,DIRBUF
	ADD	BX,DX
	ADD	DX,[BP+SECSIZ]
	RET

NEXTENTRY:

; Inputs:
;       Same as outputs of GETENTRY, above
; Function:
;       Update AL, BX, and [LASTENT] for next directory entry.
;       Carry set if no more.

	MOV	DI,[LASTENT]
	INC	DI
	CMP	DI,[BP+MAXENT]
	JNB	NONE
	MOV	[LASTENT],DI
	ADD	BX,32
	CMP	B,[BP+26],-1
	JNZ	L0288
	SUB	BX,16
L0288:	CMP	BX,DX
	JB	HAVIT
	INC	AL
	PUSH	DX
	CALL	DIRREAD
	POP	DX
	MOV	BX,DIRBUF
HAVIT:	CLC
	RET

NONE:	CALL	CHKDIRWRITE
	STC
RET4:	RET

DELETE:	CALL	GETNAME
	MOV	AL,-1
	JB	RET4
	CMP	BH,AL
	JZ	RET4
DELFILE:
	MOV	B,[DIRTYDIR],-1
	MOV	B,[BX],0E5H
	MOV	BX,[SI]
	LEA	SI,[BP+FAT]
	OR	BX,BX
	JZ	DELNXT
	CMP	BX,[BP+MAXCLUS]
	JA	DELNXT
	CALL	RELEASE
DELNXT:	CALL	CONTSRCH
	JNB	DELFILE
	CALL	FATWRT
	CALL	CHKDIRWRITE
	XOR	AL,AL
	RET

RENAME:	CALL	MOVNAME
	JB	ERRET
	ADD	SI,5
	MOV	DI,NAME2
	CALL	LODNAME
	JB	ERRET
	CALL	FINDNAME
	JB	ERRET
	CMP	BH,-1
	JZ	ERRET
	MOV	SI,NAME1
	MOV	DI,NAME3
	MOV	CX,6
	REPE
	MOVSW
RENFIL:	MOV	DI,NAME1
	MOV	SI,NAME2
	MOV	CX,11
NEWNAM:	LODB
	CMP	AL,'?'
	JNZ	NOCHG
	MOV	AL,[BX]
NOCHG:	STOB
	INC	BX
	LOOP	NEWNAM
	MOV	B,[DI],6
	CALL	DEVNAME
	JNB	RENERR
	PUSH	[LASTENT]
	MOV	W,[LASTENT],-1
	CALL	CONTSRCH
	POP	AX
	JNB	RENERR
	CALL	GETENT
	MOV	DI,BX
	MOV	SI,NAME1
	MOV	CX,11
	REPE
	MOVB
	MOV	B,[DIRTYDIR],-1
	MOV	SI,NAME3
	MOV	DI,NAME1
	MOV	CX,6
	REPE
	MOVSW
	CALL	CONTSRCH
	JNB	RENFIL
	CALL	CHKDIRWRITE
	XOR	AL,AL
	RET

RENERR:	CALL	CHKDIRWRITE
ERRET:	MOV	AL,-1
RET5:	RET

MOVNAME:

; Inputs:
;       DS, DX point to FCB or extended FCB
; Outputs:
;       DS:DX point to normal FCB
;       ES = CS
;       If file name OK:
;       BP has base of driver parameters
;       [NAME1] has name in upper case
; All registers except DX destroyed
; Carry set if bad file name or drive

	SEG	CS
	MOV	B,[EXTFCB+1],0
	MOV	AX,CS
	MOV	ES,AX
	MOV	DI,NAME1
	MOV	SI,DX
	LODB
	SEG	CS
	MOV	[EXTFCB],AL
	MOV	AH,0
	CMP	AL,-1
	JNZ	HAVATTRB
	ADD	DX,7
	ADD	SI,6
	MOV	AH,[SI-1]
	LODB
HAVATTRB:
	SEG	CS
	MOV	[ATTRIB],AH
	CALL	GETTHISDRV
	JB	RET5
LODNAME:

; This entry point copies a file name from DS,SI
; to ES,DI converting to upper case.

	CMP	B,[SI],' '
	STC
	JZ	RET5
	MOV	CX,11
MOVCHK:	CALL	GETLET
	JNZ	STOLET
	CMP	AL,' '
	STC
	JNZ	RET5
STOLET:	CMP	AL,' '
	JB	RET5
	STOB
	LOOP	MOVCHK
RET6:	RET

GETTHISDRV:
	SEG	CS
	CMP	[NUMIO],AL
	JB	RET6
	CBW
	XCHG	AX,BP
	SHL	BP
	MOV	BP,[BP+CURDRV]
	RET

OPEN:	CALL	GETFILE
DOOPEN:

; Enter here to perform OPEN on file already found
; in directory. DS=CS, BX points to directory
; entry in DIRBUF, SI points to First Cluster field, and
; ES:DI point to the FCB to be opened. This entry point
; is used by CREATE.

	JB	ERRET
	CMP	BH,-1
	JZ	L03E5
	MOV	AL,[BP+0]
	INC	AL
	STOB
	ADD	DI,11
	XOR	AX,AX
	STOW
	MOV	AX,128
	STOW
	LODW
	MOV	DX,AX
	MOVSW
	MOVSW
	MOV	AX,[SI-8]
	CMP	B,[BP+26],-1
	JNZ	L03D7
	SEG	ES
	MOV	W,[DI-1],0
	XOR	AX,AX
L03D7:	STOW
	MOV	AX,[LASTENT]
	STOW
	MOV	AX,DX
	STOW
	STOW
	XOR	AX,AX
	STOW
	STOB
	RET

L03E5:	SEG	ES
	MOV	[DI+22],BX
	XOR	AL,AL
L03EB:	RET

STARTSRCH:
	MOV	W,[LASTENT],-1
L03F2:	MOV	AL,[BP+0]
	CALL	BIOSDSKCHG,BIOSSEG
	MOV	AL,[BP+0]
	OR	AH,[BP+25]
	JS	NEWDSK
	DEC	AH
	JZ	L03EB
	MOV	AH,1
	CMP	AX,[BUFDRVNO]
	JZ	L03EB
NEWDSK:	CMP	AL,[BUFDRVNO]
	JNZ	BUFOK
	MOV	W,[BUFSECNO],0
	MOV	W,[BUFDRVNO],00FFH
BUFOK:	MOV	W,[DIRBUFID],-1
	CALL	FIGFAT
NEXTFAT:
	PUSH	AX
	CALL	DSKREAD
	POP	AX
	JB	BADFAT
	MOV	DL,AL
	LEA	SI,[BP+17]
	CMP	B,[BP+26],-1
	JZ	L043E
	ADD	SI,4
L043E:	LODW
	MOV	[BP+10],AX
	LODW
	MOV	[BP+12],AX
	MOV	AL,DL
	SUB	AL,[BP+FATCNT]
	JZ	L03EB
	NEG	AL
	JMP	FATWRT

BADFAT:	MOV	CX,DI
	ADD	DX,CX
	DEC	AL
	JNZ	NEXTFAT
	CALL	FIGFAT
	JMP	DREAD

OKRET1:	MOV	AL,0
	RET

CLOSE:	MOV	DI,DX
	CMP	B,[DI],-1
	JNZ	NORMFCB3
	ADD	DI,7
NORMFCB3:
	CMP	B,[DI+23],-1
	JZ	OKRET1
	TEST	B,[DI+30],-1
	JZ	OKRET1
	MOV	AL,[DI]
	CALL	GETTHISDRV
	JB	BADCLOSEJ
	MOV	AL,[BP+0]
	MOV	AH,1
	SEG	CS
	CMP	AX,[BUFDRVNO]
	JNZ	FNDDIR
	PUSH	DX
	PUSH	DS
	PUSH	CS
	POP	DS
	MOV	B,[DIRTYBUF],0
	MOV	BX,[BUFFER]
	MOV	CX,1
	MOV	DX,[BUFSECNO]
	CALL	DWRITE
	POP	DS
	POP	DX
FNDDIR:	CALL	GETFILE
BADCLOSEJ:
	JB	BADCLOSE
	MOV	AX,[LASTENT]
	SEG	ES
	CMP	AX,[DI+FILDIRENT]
	JNZ	BADCLOSE
	SEG	ES
	MOV	CX,[DI+FIRCLUS]
	MOV	[SI],CX
	SEG	ES
	MOV	DX,[DI+FILSIZ]
	MOV	[SI+2],DX
	SEG	ES
	MOV	DX,[DI+FILSIZ+2]
	CMP	B,[BP+26],-1
	JNZ	L04CF
	MOV	[SI+4],DL
	JP	L04D9

L04CF:	MOV	[SI+4],DX
	SEG	ES
	MOV	DX,[DI+FDATE]
	MOV	[SI-2],DX
L04D9:	CALL	DIRWRITE
CHKFATWRT:

; Do FATWRT only if FAT is dirty and uses same I/O driver

	CMP	B,[BP+25],1
	JNZ	OKRET
FATWRT:

; Inputs:
;       DS = CS
;       BP = Base of drive parameter table
; Function:
;       Write the FAT back to disk and reset FAT
;       dirty bit.
; Outputs:
;       AL = 0
;       BP unchanged
; All other registers destroyed

	MOV	B,[BP+25],0
	CALL	FIGFAT
EACHFAT:
	PUSH	DX
	PUSH	CX
	PUSH	BX
	PUSH	AX
	CALL	DWRITE
	POP	AX
	POP	BX
	POP	CX
	POP	DX
	ADD	DX,CX
	DEC	AL
	JNZ	EACHFAT
OKRET:	MOV	AL,0
	RET

BADCLOSE:
	MOV	B,[BP+25],0
	MOV	AL,-1
	RET

FIGFAT:

; Loads registers with values needed to read or
; write a FAT.

	MOV	AL,[BP+FATCNT]
	LEA	BX,[BP+FAT]
	MOV	CL,[BP+FATSIZ]
	MOV	CH,0
	MOV	DX,[BP+FIRFAT]
	RET

DIRCOMP:

; Prepare registers for directory read or write

	CBW
	ADD	AX,[BP+FIRDIR]
	MOV	DX,AX
	MOV	BX,DIRBUF
	MOV	CX,1
	RET

CREATE:	CALL	MOVNAME
	JB	ERRET3
	MOV	DI,NAME1
	MOV	CX,11
	MOV	AL,'?'
	REPNE
	SCAB
	JZ	ERRET3
	SEG	CS
	MOV	B,[CREATING],-1
	PUSH	DX
	PUSH	DS
	CALL	FINDNAME
	JNB	EXISTENT
	CALL	STARTSRCH
	CALL	GETENTRY
L0544:	CMP	B,[BX],0E5H
	JZ	FREESPOT
	CALL	NEXTENTRY
	JNB	L0544
ERRPOP:	POP	DS
	POP	DX
ERRET3:	MOV	AL,-1
	RET

EXISTENT:
	JNZ	ERRPOP
	CMP	BH,-1
	JZ	OPENJMP
	MOV	CX,[SI]
	JCXZ	FREESPOT
	CMP	CX,[BP+MAXCLUS]
	JA	FREESPOT
	PUSH	BX
	MOV	BX,CX
	LEA	SI,[BP+FAT]
	CALL	RELEASE
	CALL	FATWRT
	POP	BX
FREESPOT:
	MOV	DI,BX
	MOV	SI,NAME1
	MOV	CX,5
	MOVB
	REPE
	MOVSW
	CMP	B,[BP+26],-1
	JNZ	L0588
	PUSH	DI
	MOV	CL,5
	XOR	AX,AX
	JP	SMALLENT

L0588:	MOV	AL,[ATTRIB]
	STOB
	XOR	AX,AX
	MOV	CL,6
	REPE
	STOW
	CALL	DATE16
	STOW
	XOR	AX,AX
	PUSH	DI
	MOV	CL,6
SMALLENT:
	REPE
	STOB
	PUSH	BX
	CALL	DIRWRITE
	POP	BX
	POP	SI
OPENJMP:
	CLC
	POP	ES
	POP	DI
	JMP	DOOPEN

DIRREAD:

; Inputs:
;       DS = CS
;       AL = Directory block number
;       BP = Base of drive parameters
; Function:
;       Read the directory block into DIRBUF.
; Outputs:
;       AX,BP unchanged
; All other registers destroyed.

	PUSH	AX
	CALL	CHKDIRWRITE
	POP	AX
	PUSH	AX
	MOV	AH,[BP+0]
	MOV	[DIRBUFID],AX
	CALL	DIRCOMP
	CALL	DREAD
	POP	AX
RET8:	RET

DREAD:

; Inputs:
;       BX,DS = Transfer address
;       CX = Number of sectors
;       DX = Absolute record number
;       BP = Base of drive parameters
; Function:
;       Calls BIOS to perform disk read. If BIOS reports
;       errors, will call HARDERR for further action.
; BP preserved. All other registers destroyed.

	CALL	DSKREAD
	JNB	RET8
	SEG	CS
	MOV	B,[READOP],0
	CALL	HARDERR
	CMP	AL,1
	JZ	DREAD
	RET

HARDERR:

;Hard disk error handler. Entry conditions:
;       DS:BX = Original disk transfer address
;       DX = Original logical sector number
;       CX = Number of sectors to go (first one gave the error)
;       AX = Hardware error code
;       DI = Original sector transfer count
;       BP = Base of drive parameters
;       [READOP] = 0 for read, 1 for write

	XCHG	AX,DI
	SUB	AX,CX
	ADD	DX,AX
	PUSH	DX
	MUL	AX,[BP+SECSIZ]
	POP	DX
	ADD	BX,AX
	MOV	AH,0
	CMP	DX,[BP+FIRFAT]
	JB	ERRINT
	INC	AH
	CMP	DX,[BP+FIRDIR]
	JB	ERRINT
	INC	AH
	CMP	DX,[BP+FIRREC]
	JB	ERRINT
	INC	AH
ERRINT:	SHL	AH
	SEG	CS
	OR	AH,[READOP]
FATAL:	MOV	AL,[BP+DRVNUM]
	PUSH	BP
	SEG	CS
	MOV	[CONTSTK],SP
	CLI
	SEG	CS
	MOV	SS,[SSSAVE]
	SEG	CS
	MOV	SP,[SPSAVE]
	INT	24H			;fatal error interrupt vector
	SEG	CS
	MOV	[SPSAVE],SP
	SEG	CS
	MOV	[SSSAVE],SS
	MOV	SP,CS
	MOV	SS,SP
	SEG	CS
	MOV	SP,[CONTSTK]
	STI
	POP	BP
	CMP	AL,2
	JZ	ERROR
	RET

DSKREAD:
	MOV	AL,[BP+DEVNUM]
	PUSH	BP
	PUSH	BX
	PUSH	CX
	PUSH	DX
	CALL	BIOSREAD,BIOSSEG
	POP	DX
	POP	DI
	POP	BX
	POP	BP
RET9:	RET

CHKDIRWRITE:
	TEST	B,[DIRTYDIR],-1
	JZ	RET9
DIRWRITE:

; Inputs:
;       DS = CS
;       AL = Directory block number
;       BP = Base of drive parameters
; Function:
;       Write the directory block into DIRBUF.
; Outputs:
;       BP unchanged
; All other registers destroyed.

	MOV	B,[DIRTYDIR],0
	MOV	AL,[DIRBUFID]
	CALL	DIRCOMP

DWRITE:

; Inputs:
;       BX,DS = Transfer address
;       CX = Number of sectors
;       DX = Absolute record number
;       BP = Base of drive parameters
; Function:
;       Calls BIOS to perform disk write. If BIOS reports
;       errors, will call HARDERR for further action.
; BP preserved. All other registers destroyed.

	MOV	AL,[BP+DEVNUM]
	PUSH	BP
	PUSH	BX
	PUSH	CX
	PUSH	DX
	CALL	BIOSWRITE,BIOSSEG
	POP	DX
	POP	DI
	POP	BX
	POP	BP
	JNB	RET9
	SEG	CS
	MOV	B,[READOP],1
	CALL	HARDERR
	CMP	AL,1
	JZ	DWRITE
	RET

ABORT:	SEG	CS
	LDS	SI,[SPSAVE]
	MOV	DS,[SI+14H]
	XOR	AX,AX
	MOV	ES,AX
	MOV	SI,10
	MOV	DI,0088H
	MOVSW
	MOVSW
	MOVSW
	MOVSW
	MOVSW
	MOVSW
ERROR:	MOV	AX,CS
	MOV	DS,AX
	MOV	ES,AX
	CALL	WRTFATS
	XOR	AX,AX
	CLI
	MOV	SS,[SSSAVE]
	MOV	SP,[SPSAVE]
	MOV	DS,AX
	MOV	SI,EXIT
	MOV	DI,EXITHOLD
	MOVSW
	MOVSW
	POP	AX
	POP	BX
	POP	CX
	POP	DX
	POP	SI
	POP	DI
	POP	BP
	POP	DS
	POP	ES
	STI
	SEG	CS
	JMP	L,[EXITHOLD]

SEQRD:	CALL	GETREC
	CALL	LOAD
	JP	FINSEQ

SEQWRT:	CALL	GETREC
	CALL	STORE
FINSEQ:	JCXZ	SETNREX
	ADD	AX,1
	ADC	DX,0
	JP	SETNREX

RNDRD:	CALL	GETRRPOS1
	CALL	LOAD
	JP	FINRND

RNDWRT:	CALL	GETRRPOS1
	CALL	STORE
	JP	FINRND

BLKRD:	CALL	GETRRPOS
	CALL	LOAD
	JP	FINBLK

BLKWRT:	CALL	GETRRPOS
	CALL	STORE
FINBLK:	LDS	SI,[SPSAVE]
	MOV	[SI+4],CX
	JCXZ	FINRND
	ADD	AX,1
	ADC	DX,0
FINRND:	SEG	ES
	MOV	[DI+21H],AX
	SEG	ES
	MOV	[DI+23H],DL
	OR	DH,DH
	JZ	SETNREX
	SEG	ES
	MOV	[DI+24H],DH
SETNREX:
	MOV	CX,AX
	AND	AL,7FH
	SEG	ES
	MOV	[DI+20H],AL
	AND	CL,80H
	SHL	CX
	RCL	DX
	MOV	AL,CH
	MOV	AH,DL
	SEG	ES
	MOV	[DI+0CH],AX
	SEG	CS
	MOV	AL,[DSKERR]
	RET

GETRRPOS1:
	MOV	CX,1
GETRRPOS:
	MOV	DI,DX
	CMP	B,[DI],-1
	JNZ	NORMFCB1
	ADD	DI,7
NORMFCB1:
	MOV	AX,[DI+RR]
	MOV	DX,[DI+RR+2]
	RET

NOFILERR:
	XOR	CX,CX
	MOV	B,[DSKERR],4
	POP	BX
	RET

SETUP:

; Inputs:
;       DS:DI point to FCB
;       DX:AX = Record position in file of disk transfer
;       CX = Record count
; Outputs:
;       DS = CS
;       ES:DI point to FCB
;       BL = DEVID from FCB
;       CX = No. of bytes to transfer
;       BP = Base of drive parameters
;       SI = FAT pointer
;       [RECCNT] = Record count
;       [RECPOS] = Record position in file
;       [FCB] = DI
;       [NEXTADD] = Displacement of disk transfer within segment
;       [SECPOS] = Position of first sector
;       [BYTPOS] = Byte position in file
;       [BYTSECPOS] = Byte position in first sector
;       [CLUSNUM] = First cluster
;       [SECCLUSPOS] = Sector within first cluster
;       [DSKERR] = 0 (no errors yet)
;       [TRANS] = 0 (No transfers yet)
;       [THISDRV] = Physical drive unit number
; If SETUP detects no records will be transfered, it returns 1 level up 
; with CX = 0.

	PUSH	AX
	MOV	AL,[DI]
	MOV	SI,[DI+RECSIZ]
	OR	SI,SI
	JNZ	HAVRECSIZ
	MOV	SI,128
	MOV	[DI+RECSIZ],SI
HAVRECSIZ:
	MOV	BX,DS
	MOV	ES,BX
	MOV	BX,CS
	MOV	DS,BX
	CALL	GETTHISDRV
	POP	AX
	JB	NOFILERR
	CMP	SI,64
	JB	SMALREC
	MOV	DH,0
SMALREC:
	MOV	[RECCNT],CX
	MOV	[RECPOS],AX
	MOV	[RECPOS+2],DX
	MOV	[FCB],DI
	MOV	BX,[DMAADD]
	MOV	[NEXTADD],BX
	MOV	B,[DSKERR],0
	MOV	B,[TRANS],0
	MOV	BX,DX
	MUL	AX,SI
	MOV	[BYTPOS],AX
	PUSH	DX
	MOV	AX,BX
	MUL	AX,SI
	POP	BX
	ADD	AX,BX
	ADC	DX,0
	JNZ	EOFERR
	MOV	[BYTPOS+2],AX
	MOV	DX,AX
	MOV	AX,[BYTPOS]
	MOV	BX,[BP+1]
	CMP	DX,BX
	JNB	EOFERR
	DIV	AX,BX
	MOV	[SECPOS],AX
	MOV	[BYTSECPOS],DX
	MOV	DX,AX
	AND	AL,[BP+3]
	MOV	[SECCLUSPOS],AL
	MOV	AX,CX
	MOV	CL,[BP+4]
	SHR	DX,CL
	MOV	[CLUSNUM],DX
	MUL	AX,SI
	MOV	CX,AX
	ADD	AX,[DMAADD]
	ADC	DX,0
	JZ	OK
	MOV	AX,[DMAADD]
	NEG	AX
	JNZ	PARTSEG
	DEC	AX
PARTSEG:
	XOR	DX,DX
	DIV	AX,SI
	MOV	[RECCNT],AX
	MUL	AX,SI
	MOV	B,[DSKERR],2
	MOV	CX,AX
	JCXZ	NOROOM
OK:	SEG	ES
	MOV	BX,[DI+16H]
	LEA	SI,[BP+1AH]
	RET

EOFERR:	MOV	B,[DSKERR],1
	XOR	CX,CX
NOROOM:	POP	BX
	RET

BREAKDOWN:

;Inputs:
;       DS = CS
;       CX = Length of disk transfer in bytes
;       BP = Base of drive parameters
;       [BYTSECPOS] = Byte position witin first sector
;Outputs:
;       [BYTCNT1] = Bytes to transfer in first sector
;       [SECCNT] = No. of whole sectors to transfer
;       [BYTCNT2] = Bytes to transfer in last sector
;AX, BX, DX destroyed. No other registers affected.

	MOV	AX,[BYTSECPOS]
	MOV	BX,CX
	OR	AX,AX
	JZ	SAVFIR
	SUB	AX,[BP+SECSIZ]
	NEG	AX
	SUB	BX,AX
	JNB	SAVFIR
	ADD	AX,BX
	XOR	BX,BX
SAVFIR:	MOV	[BYTCNT1],AX
	MOV	AX,BX
	XOR	DX,DX
	DIV	AX,[BP+SECSIZ]
	MOV	[SECCNT],AX
	MOV	[BYTCNT2],DX
RET10:	RET

FNDCLUS:

; Inputs:
;       DS = CS
;       CX = No. of clusters to skip
;       BP = Base of drive parameters
;       SI = FAT pointer
;       ES:DI point to FCB
; Outputs:
;       BX = Last cluster skipped to
;       CX = No. of clusters remaining (0 unless EOF)
;       DX = Position of last cluster
; DI destroyed. No other registers affected.

	SEG	ES
	MOV	BX,[DI+LSTCLUS]
	SEG	ES
	MOV	DX,[DI+CLUSPOS]
	OR	BX,BX
	JZ	NOCLUS
	SUB	CX,DX
	JNB	FINDIT
	ADD	CX,DX
	XOR	DX,DX
	SEG	ES
	MOV	BX,[DI+FIRCLUS]
FINDIT:	JCXZ	RET10
SKPCLP:	CALL	UNPACK
	CMP	DI,0FF8H
	JNB	RET10
	XCHG	BX,DI
	INC	DX
	LOOP	SKPCLP
	RET

NOCLUS:	INC	CX
	DEC	DX
	RET

BUFSEC:

; Inputs:
;       AL = 0 if buffer must be read, 1 if no pre-read needed
;       BP = Base of drive parameters
;       [CLUSNUM] = Physical cluster number
;       [SECCLUSPOS] = Sector position of transfer within cluster
;       [BYTCNT1] = Size of transfer
; Function:
;       Insure specified sector is in buffer, flushing buffer before
;       read if necessary.
; Outputs:
;       SI = Pointer to buffer
;       DI = Pointer to transfer address
;       CX = Number of bytes
;       [NEXTADD] updated
;       [TRANS] set to indicate a transfer will occur

	MOV	DX,[CLUSNUM]
	MOV	BL,[SECCLUSPOS]
	CALL	FIGREC
	MOV	[PREREAD],AL
	CMP	DX,[BUFSECNO]
	JNZ	GETSEC
	MOV	AL,[BUFDRVNO]
	CMP	AL,[BP+0]
	JZ	FINBUF
GETSEC:	TEST	B,[DIRTYBUF],-1
	JZ	RDSEC
	PUSH	DX
	PUSH	BP
	MOV	BP,[BUFDRVBP]
	MOV	BX,[BUFFER]
	MOV	CX,1
	MOV	DX,[BUFSECNO]
	CALL	DWRITE
	POP	BP
	POP	DX
RDSEC:	TEST	B,[PREREAD],-1
	JNZ	SETBUF
	MOV	BX,[BUFFER]
	MOV	CX,1
	PUSH	DX
	CALL	DREAD
	POP	DX
SETBUF:	MOV	[BUFSECNO],DX
	MOV	AL,[BP+0]
	MOV	AH,0
	MOV	[BUFDRVNO],AX
	MOV	[BUFDRVBP],BP
FINBUF:	MOV	B,[TRANS],1
	MOV	DI,[NEXTADD]
	MOV	SI,DI
	MOV	CX,[BYTCNT1]
	ADD	SI,CX
	MOV	[NEXTADD],SI
	MOV	SI,[BUFFER]
	ADD	SI,[BYTSECPOS]
	RET

BUFRD:	XOR	AL,AL
	CALL	BUFSEC
	PUSH	ES
	MOV	ES,[DMAADD+2]
	SHR	CX
	JNB	EVENRD
	MOVB
EVENRD:	REPE
	MOVSW
	POP	ES
	RET

BUFWRT:	MOV	AX,[SECPOS]
	INC	AX
	MOV	[SECPOS],AX
	CMP	AX,[VALSEC]
	MOV	AL,1
	JA	NOREAD
	MOV	AL,0
NOREAD:	CALL	BUFSEC
	XCHG	DI,SI
	PUSH	DS
	PUSH	ES
	PUSH	CS
	POP	ES
	MOV	DS,[DMAADD+2]
	SHR	CX
	JNB	EVENWRT
	MOVB
EVENWRT:	REPE
	MOVSW
	POP	ES
	POP	DS
	MOV	B,[DIRTYBUF],1
	RET

NEXTSEC:
	TEST	B,[TRANS],-1
	JZ	CLRET
	MOV	AL,[SECCLUSPOS]
	INC	AL
	CMP	AL,[BP+CLUSMSK]
	JBE	SAVPOS
	MOV	BX,[CLUSNUM]
	CMP	BX,0FF8H
	JNB	NONEXT
	LEA	SI,[BP+FAT]
	CALL	UNPACK
	MOV	[CLUSNUM],DI
	INC	[LASTPOS]
	MOV	AL,0
SAVPOS:	MOV	[SECCLUSPOS],AL
CLRET:	CLC
	RET

NONEXT:	STC
	RET

TRANBUF:
	LODB
	STOB
	CMP	AL,0DH
	JNZ	NORMCH
	MOV	B,[SI],0AH
NORMCH:	CMP	AL,0AH
	LOOPNZ	TRANBUF
	JNZ	ENDRDCON
	CALL	OUT
	XOR	SI,SI
	OR	CX,CX
	JNZ	GETBUF
	OR	AL,1
ENDRDCON:
	MOV	[CONTPOS],SI
ENDRDDEV:
	MOV	[NEXTADD],DI
	POP	ES
	JNZ	SETFCBJ
	MOV	DI,[FCB]
	SEG	ES
	OR	B,[DI+DEVID],80H
SETFCBJ:
	JMP	SETFCB
READDEV:
	PUSH	ES
	LES	DI,[DMAADD]
	OR	BL,BL
	JZ	READCON
	DEC	BL
	JNZ	ENDRDDEV
READAUX:
	CALL	READER
	STOB
	CMP	AL,1AH
	LOOPNZ	READAUX
	JP	ENDRDDEV
READCON:
	PUSH	CS
	POP	DS
	MOV	SI,[CONTPOS]
	OR	SI,SI
	JNZ	TRANBUF
	CMP	B,[CONBUF],80H
	JZ	GETBUF
	MOV	W,[CONBUF],0FF80H
GETBUF:	PUSH	CX
	PUSH	ES
	PUSH	DI
	MOV	DX,CONBUF
	CALL	BUFIN
	POP	DI
	POP	ES
	POP	CX
	MOV	SI,CONBUF+2
	CMP	B,[SI],1AH
	JNZ	TRANBUF
	MOV	AL,1AH
	STOB
	MOV	AL,0AH
	CALL	OUT
	XOR	SI,SI
	JP	ENDRDCON

RDERR:	XOR	CX,CX
	JMP	L0B0C

RDLASTJ:	JMP	RDLAST

LOAD:

; Inputs:
;       DS:DI point to FCB
;       DX:AX = Position in file to read
;       CX = No. of records to read
; Outputs:
;       DX:AX = Position of last record read
;       CX = No. of bytes read
;       ES:DI point to FCB
;       LSTCLUS, CLUSPOS fields in FCB set

	CALL	SETUP
	CMP	BH,-1
	JZ	READDEV
	SEG	ES
	MOV	AX,[DI+FILSIZ]
	SEG	ES
	MOV	BX,[DI+FILSIZ+2]
	SUB	AX,[BYTPOS]
	SBB	BX,[BYTPOS+2]
	JB	RDERR
	JNZ	ENUF
	OR	AX,AX
	JZ	RDERR
	CMP	AX,CX
	JNB	ENUF
	MOV	CX,AX
ENUF:	CALL	BREAKDOWN
	MOV	CX,[CLUSNUM]
	CALL	FNDCLUS
	OR	CX,CX
	JNZ	RDERR
	MOV	[LASTPOS],DX
	MOV	[CLUSNUM],BX
	CMP	W,[BYTCNT1],0
	JZ	RDMID
	CALL	BUFRD
RDMID:	CMP	W,[SECCNT],0
	JZ	RDLASTJ
	CALL	NEXTSEC
	JB	SETFCB
	MOV	B,[TRANS],1
	MOV	DL,[SECCLUSPOS]
	MOV	CX,[SECCNT]
	MOV	BX,[CLUSNUM]
RDLP:	CALL	OPTIMIZE
	PUSH	DI
	PUSH	AX
	PUSH	DS
	MOV	DS,[DMAADD+2]
	CALL	DREAD
	POP	DS
	POP	CX
	POP	BX
	JCXZ	RDLAST
	CMP	BX,0FF8H
	JNB	SETFCB
	MOV	DL,0
	INC	[LASTPOS]
	JP	RDLP

SETFCB:	MOV	SI,[FCB]
	MOV	AX,[NEXTADD]
	MOV	DI,AX
	SUB	AX,[DMAADD]
	XOR	DX,DX
	SEG	ES
	MOV	CX,[SI+RECSIZ]
	DIV	AX,CX
	CMP	AX,[RECCNT]
	JZ	L0A84
	MOV	B,[DSKERR],1
	OR	DX,DX
	JZ	L0A84
	MOV	B,[DSKERR],3
	SUB	CX,DX
	PUSH	ES
	MOV	ES,[DMAADD+2]
	XCHG	AX,BX
	XOR	AX,AX
	SHR	CX
	JNB	L0A7F
	STOB
L0A7F:	REPE
	STOW
	XCHG	AX,BX
	POP	ES
	INC	AX
L0A84:	MOV	CX,AX
	MOV	DI,SI
SETCLUS:
	MOV	AX,[CLUSNUM]
	SEG	ES
	MOV	[DI+LSTCLUS],AX
	MOV	AX,[LASTPOS]
	SEG	ES
	MOV	[DI+CLUSPOS],AX
ADDREC:	MOV	AX,[RECPOS]
	MOV	DX,[RECPOS+2]
	JCXZ	L0AA6
	DEC	CX
	ADD	AX,CX
	ADC	DX,0
	INC	CX
L0AA6:	RET

RDLAST:	MOV	AX,[BYTCNT2]
	OR	AX,AX
	JZ	SETFCB
	MOV	[BYTCNT1],AX
	CALL	NEXTSEC
	JB	SETFCB
	MOV	W,[BYTSECPOS],0
	CALL	BUFRD
	JP	SETFCB

WRTDEV:	PUSH	DS
	LDS	SI,[DMAADD]
	AND	BL,7FH
	OR	BL,BL
	JZ	WRTCON
	DEC	BL
	JZ	WRTAUX
	DEC	BL
	JZ	L0AF5
WRTLST:	LODB
	CMP	AL,1AH
	JZ	L0AF5
	CALL	L11D1
	LOOP	WRTLST
	JP	L0AF5

WRTAUX:	LODB
	CALL	AUXOUT
	CMP	AL,1AH
	LOOPNZ	WRTAUX
	JP	L0AF5

WRTCON:	LODB
	CMP	AL,1AH
	JZ	L0AF5
	CALL	OUT
	LOOP	WRTCON
L0AF5:	POP	DS
	MOV	CX,[RECCNT]
	MOV	DI,[FCB]
	JP	ADDREC

HAVSTART:
	MOV	CX,AX
	CALL	SKPCLP
	JCXZ	L0B1D
	CALL	ALLOCATE
	JNB	L0B1D
L0B0C:	MOV	B,[DSKERR],1
	MOV	AX,[RECPOS]
	MOV	DX,[RECPOS+2]
	MOV	DI,[FCB]
	RET

L0B1D:	JMP	L0B99

L0B20:	JMP	L0C2A

STORE:

; Inputs:
;       DS:DI point to FCB
;       DX:AX = Position in file of disk transfer
;       CX = Record count
; Outputs:
;       DX:AX = Position of last record written
;       CX = No. of records written
;       ES:DI point to FCB
;       LSTCLUS, CLUSPOS fields in FCB set

	CALL	SETUP
	CALL	DATE16
	SEG	ES
	MOV	[DI+FDATE],AX
	CMP	BH,-1
	JZ	WRTDEV
	SEG	ES
	MOV	B,[DI+30],1
	CALL	BREAKDOWN
	MOV	AX,[BYTPOS]
	MOV	DX,[BYTPOS+2]
	JCXZ	L0B20
	DEC	CX
	ADD	AX,CX
	ADC	DX,0
	DIV	AX,[BP+SECSIZ]
	MOV	CL,[BP+CLUSSHFT]
	SHR	AX,CL
	PUSH	AX
	SEG	ES
	MOV	AX,[DI+FILSIZ]
	SEG	ES
	MOV	DX,[DI+FILSIZ+2]
	DIV	AX,[BP+SECSIZ]
	OR	DX,DX
	JZ	L0B62
	INC	AX
L0B62:	MOV	[VALSEC],AX
	POP	AX
	MOV	CX,[CLUSNUM]
	CALL	FNDCLUS
	MOV	[CLUSNUM],BX
	MOV	[LASTPOS],DX
	SUB	AX,DX
	JZ	L0B99
	JCXZ	HAVSTART
	PUSH	CX
	MOV	CX,AX
	CALL	ALLOCATE
	POP	AX
	JB	L0B0C
	MOV	CX,AX
	MOV	DX,[LASTPOS]
	INC	DX
	DEC	CX
	JZ	L0B91
	CALL	SKPCLP
L0B91:	MOV	[CLUSNUM],BX
	MOV	[LASTPOS],DX
L0B99:	CMP	W,[BYTCNT1],0
	JZ	L0BA7
	MOV	BX,[CLUSNUM]
	CALL	BUFWRT
L0BA7:	MOV	AX,[SECCNT]
	OR	AX,AX
	JZ	L0BE0
	ADD	[SECPOS],AX
	CALL	NEXTSEC
	MOV	B,[TRANS],1
	MOV	DL,[SECCLUSPOS]
	MOV	BX,[CLUSNUM]
	MOV	CX,[SECCNT]
L0BC6:	CALL	OPTIMIZE
	PUSH	DI
	PUSH	AX
	PUSH	DS
	MOV	DS,[DMAADD+2]
	CALL	DWRITE
	POP	DS
	POP	CX
	POP	BX
	JCXZ	L0BE0
	MOV	DL,0
	INC	[LASTPOS]
	JP	L0BC6

L0BE0:	MOV	AX,[BYTCNT2]
	OR	AX,AX
	JZ	L0BF6
	MOV	[BYTCNT1],AX
	CALL	NEXTSEC
	MOV	W,[BYTSECPOS],0
	CALL	BUFWRT
L0BF6:	MOV	AX,[NEXTADD]
	SUB	AX,[DMAADD]
	ADD	AX,[BYTPOS]
	MOV	DX,[BYTPOS+2]
	ADC	DX,0
	MOV	CX,DX
	MOV	DI,[FCB]
	SEG	ES
	CMP	AX,[DI+10H]
	SEG	ES
	SBB	CX,[DI+12H]
	JB	L0C20
	SEG	ES
	MOV	[DI+10H],AX
	SEG	ES
	MOV	[DI+12H],DX
L0C20:	MOV	CX,[RECCNT]
	JMP	SETCLUS

L0C27:	JMP	L0B0C

L0C2A:	MOV	CX,AX
	OR	CX,DX
	JZ	L0C6B
	SUB	AX,1
	SBB	DX,0
	DIV	AX,[BP+1]
	MOV	CL,[BP+4]
	SHR	AX,CL
	MOV	CX,AX
	CALL	FNDCLUS
	JCXZ	L0C5F
	CALL	ALLOCATE
	JB	L0C27
L0C4A:	MOV	DI,[FCB]
	MOV	AX,[BYTPOS]
	SEG	ES
	MOV	[DI+10H],AX
	MOV	AX,[BYTPOS+2]
	SEG	ES
	MOV	[DI+12H],AX
	XOR	CX,CX
	RET

L0C5F:	MOV	DX,0FFFH
	CALL	RELBLKS
L0C65:	MOV	B,[BP+19H],1
	JP	L0C4A

L0C6B:	XOR	BX,BX
	SEG	ES
	XCHG	BX,[DI+18H]
	OR	BX,BX
	JZ	L0C4A
	CALL	RELEASE
	JP	L0C65

OPTIMIZE:

; Inputs:
;       DS = CS
;       BX = Physical cluster
;       CX = No. of records
;       DL = sector within cluster
;       BP = Base of drives parameters
;       [NEXTADD] = transfer address
; Outputs:
;       AX = No. of records remaining
;       BX = Transfer address
;       CX = No. or records to be transferred
;       DX = Physical sector address
;       DI = Next cluster
;       Carry clear if a sector to transfer is in the buffer
;       Carry set otherwise
;       [CLUSNUM] = Last cluster accessed
;       [NEXTADD] updated
; BP unchanged. Note that segment of transfer not set.

	PUSH	DX
	PUSH	BX
	MOV	AL,[BP+3]
	INC	AL
	MOV	AH,AL
	SUB	AL,DL
	MOV	DX,CX
	LEA	SI,[BP+1AH]
	MOV	CX,0

OPTCLUS:

;AL has number of sectors available in current cluster
;AH has number of sectors available in next cluster
;BX has current physical cluster
;CX has number of sequential sectors found so far
;DX has number of sectors left to transfer
;SI has FAT pointer

	CALL	UNPACK
	ADD	CL,AL
	ADC	CH,0
	CMP	CX,DX
	JNB	L0CC5
	MOV	AL,AH
	INC	BX
	CMP	DI,BX
	JZ	OPTCLUS
	DEC	BX
L0CA1:	MOV	[CLUSNUM],BX
	SUB	DX,CX
	PUSH	DX
	MOV	AX,CX
	MUL	AX,[BP+1]
	MOV	SI,[NEXTADD]
	ADD	AX,SI
	MOV	[NEXTADD],AX
	POP	AX
	POP	DX
	SUB	BX,DX
	ADD	[LASTPOS],BX
	POP	BX
	CALL	FIGREC
	MOV	BX,SI
	RET

L0CC5:	SUB	CX,DX
	SUB	AH,CL
	DEC	AH
	MOV	[SECCLUSPOS],AH
	MOV	CX,DX
	JP	L0CA1

FIGREC:

;Inputs:
;       DX = Physical cluster number
;       BL = Sector postion within cluster
;       BP = Base of drive parameters
;Outputs:
;       DX = physical sector number
;No other registers affected.

	PUSH	CX
	MOV	CL,[BP+4]
	DEC	DX
	DEC	DX
	SHL	DX,CL
	OR	DL,BL
	ADD	DX,[BP+0AH]
	POP	CX
	RET

GETREC:

; Inputs:
;       DS:DX point to FCB
; Outputs:
;       CX = 1
;       DX:AX = Record number determined by EXTENT and NR fields
;       DS:DI point to FCB
; No other registers affected.

	MOV	DI,DX
	CMP	B,[DI],-1
	JNZ	L0CEC
	ADD	DI,7
L0CEC:	MOV	CX,1
	MOV	AL,[DI+20H]
	MOV	DX,[DI+0CH]
	SHL	AL
	SHR	DX
	RCR	AL
	MOV	AH,DL
	MOV	DL,DH
	MOV	DH,0
	RET

ALLOCATE:

; Inputs:
;       DS = CS
;       ES = Segment of FCB
;       BX = Last cluster of file (0 if null file)
;       CX = No. of clusters to allocate
;       DX = Position of cluster BX
;       BP = Base of drive parameters
;       SI = FAT pointer
;       [FCB] = Displacement of FCB within segment
; Outputs:
;       IF insufficient space
;         THEN
;       Carry set
;       CX = max. no. of records that could be added to file
;         ELSE
;       Carry clear
;       BX = First cluster allocated
;       FAT is fully updated including dirty bit
;       FIRCLUS field of FCB set if file was null
; SI,BP unchanged. All other registers destroyed.

	PUSH	[SI]
	PUSH	DX
	PUSH	CX
	PUSH	BX
	MOV	AX,BX
L0D09:	MOV	DX,BX
L0D0B:	INC	BX
	CMP	BX,[BP+0CH]
	JLE	TRYOUT
	CMP	AX,1
	JG	TRYIN
	POP	BX
	MOV	DX,0FFFH
	CALL	RELBLKS
	POP	AX
	SUB	AX,CX
	POP	DX
	POP	[SI]
	INC	DX
	ADD	AX,DX
	MOV	DL,[BP+3]
	MOV	DH,0
	INC	DX
	MUL	AX,DX
	MOV	CX,AX
	SUB	CX,[RECPOS]
	JA	L0D38
	XOR	CX,CX
L0D38:	STC
L0D39:	RET

TRYOUT:	CALL	UNPACK
	JZ	L0D4B
TRYIN:	DEC	AX
	JLE	L0D0B
	XCHG	AX,BX
	CALL	UNPACK
	JZ	L0D4B
	XCHG	AX,BX
	JP	L0D0B

L0D4B:	XCHG	BX,DX
	MOV	AX,DX
	CALL	PACK
	MOV	BX,AX
	LOOP	L0D09
	MOV	DX,0FFFH
	CALL	PACK
	MOV	B,[BP+19H],1
	POP	BX
	POP	CX
	POP	DX
	CALL	UNPACK
	POP	[SI]
	XCHG	BX,DI
	OR	DI,DI
	JNZ	L0D39
	MOV	DI,[FCB]
	SEG	ES
	MOV	[DI+FIRCLUS],BX
L0D76:	RET

RELEASE:

; Inputs:
;       DS = CS
;       BX = Cluster in file
;       SI = FAT pointer
;       BP = Base of drive parameters
; Function:
;       Frees cluster chain starting with [BX]
; AX,BX,DX,DI all destroyed. Other registers unchanged.

	XOR	DX,DX

RELBLKS:

; Enter here with DX=0FFFH to put an end-of-file mark
; in the first cluster and free the rest in the chain.

	CALL	UNPACK
	JZ	L0D76
	MOV	AX,DI
	CALL	PACK
	CMP	AX,0FF8H
	MOV	BX,AX
	JB	RELEASE
L0D8A:	RET

GETEOF:

; Inputs:
;       BX = Cluster in a file
;       SI = Base of drive FAT
;       DS = CS
; Outputs:
;       BX = Last cluster in the file
; DI destroyed. No other registers affected.

	CALL	UNPACK
	CMP	DI,0FF8H
	JNB	L0D8A
	MOV	BX,DI
	JP	GETEOF

SRCHFRST:
	CALL	GETFILE

SAVPLCE:

; Search-for-next enters here to save place and report
; findings.

	JB	KILLSRCH
	CMP	BH,-1
	JZ	SRCHDEV
	MOV	AX,[LASTENT]
	SEG	ES
	MOV	[DI+FILDIRENT],AX

;Information in directory entry must be copied into the first
; 33 bytes starting at the disk transfer address.

	MOV	SI,BX
	LES	DI,[DMAADD]
	MOV	AX,00FFH
	CMP	AL,[EXTFCB]
	JNZ	NORMFCB
	STOW
	INC	AL
	STOW
	STOW
	MOV	AL,[ATTRIB]
	STOB
NORMFCB:
	MOV	AL,[BP+0]
	INC	AL
	STOB
	MOVB
	MOV	CX,5
	REPE
	MOVSW
	XOR	AX,AX
	CMP	B,[BP+26],-1
	JNZ	L0DE0
	STOB
	MOV	CX,7
	REPE
	STOW
	MOVSW
	MOVSW
	MOVB
	STOB
	RET

L0DE0:	MOV	CX,10
	REPE
	MOVSW
	MOVB
	RET

KILLSRCH:
	SEG	ES
L0DE8:	MOV	W,[DI+16H],0FFFEH
	MOV	AL,-1
	RET

SRCHDEV:
	SEG	ES
	MOV	[DI+16H],BX
	LES	DI,[DMAADD]
	XOR	AX,AX
	STOB
	SUB	SI,3
	MOVSW
	MOVB
	MOV	AX,2020H	;'  '
	MOV	CX,4
	REPE
	STOW
	XOR	AX,AX
	MOV	CX,10
	REPE
	STOW
	STOB
L0E10:	RET

SRCHNXT:
	CALL	MOVNAME
	MOV	DI,DX
	JB	L0DE8
	PUSH	DX
	PUSH	DS
	MOV	AX,[DI+16H]
	PUSH	CS
	POP	DS
	MOV	[LASTENT],AX
	CALL	CONTSRCH
	POP	ES
	POP	DI
	JMP	SAVPLCE

FILESIZE:
	CALL	GETFILE
	MOV	AL,-1
	JB	L0E10
	ADD	DI,33
	SEG	ES
	MOV	CX,[DI-13H]
	OR	CX,CX
	JNZ	L0E3F
	MOV	CX,0080H
L0E3F:	XOR	AX,AX
	XOR	DX,DX
	CMP	BH,-1
	JZ	DEVSIZ
	INC	SI
	INC	SI
	MOV	AX,[SI+2]
	CMP	B,[BP+1AH],-1
	JNZ	L0E55
	MOV	AH,0
L0E55:	DIV	AX,CX
	PUSH	AX
	LODW
	DIV	AX,CX
	OR	DX,DX
	POP	DX
	JZ	DEVSIZ
	INC	AX
	JNZ	DEVSIZ
	INC	DX
DEVSIZ:	STOW
	MOV	AX,DX
	STOB
	MOV	AL,0
	CMP	CX,0040H
	JNB	L0E10
	SEG	ES
	MOV	[DI],AH
	RET

SETDMA:	SEG	CS
	MOV	[DMAADD],DX
	SEG	CS
	MOV	[DMAADD+2],DS
	RET

GETFATPT:
	MOV	AX,CS
	MOV	DS,AX
	MOV	BP,[CURDRV]
	CALL	L03F2
	LEA	BX,[BP+1AH]
	MOV	AL,[BP+3]
	INC	AL
	MOV	DX,[BP+0CH]
	DEC	DX
	MOV	B,[BP+19H],1
	MOV	CX,[BP+1]
	LDS	SI,[SPSAVE]
	MOV	[SI+BXSAVE],BX
	MOV	[SI+DXSAVE],DX
	MOV	[SI+CXSAVE],CX
	MOV	[SI+DSSAVE],CS
	RET

GETDSKPT:
	SEG	CS
	MOV	BX,[CURDRV]
	SEG	CS
	LDS	SI,[SPSAVE]
	MOV	[SI+BXSAVE],BX
	MOV	[SI+DSSAVE],CS
	RET

DSKRESET:
	PUSH	CS
	POP	DS

WRTFATS:

; DS=CS. Writes back all dirty FATs. All registers destroyed.

	MOV	AX,[BUFDRVNO]
	OR	AH,AH
	JZ	L0EE2
	CBW
	MOV	BX,AX
	SHL	BX
	MOV	BP,[BX+DRVTAB]
	MOV	B,[DIRTYBUF],0
	MOV	DX,[BUFSECNO]
	MOV	BX,BUFFER
	MOV	CX,1
	CALL	DWRITE
L0EE2:	MOV	CL,[NUMIO]
	MOV	CH,0
	MOV	SI,DRVTAB
L0EEB:	LODW
	PUSH	CX
	PUSH	SI
	MOV	BP,AX
	CALL	CHKFATWRT
	POP	SI
	POP	CX
	LOOP	L0EEB
	RET

GETDRV:	SEG	CS
	MOV	BP,[CURDRV]
	MOV	AL,[BP+0]
L0F00:	RET

SETRNDREC:
	CALL	GETREC
	MOV	[DI+33],AX
	MOV	[DI+35],DL
	CMP	W,[DI+RECSIZ],64
	JNB	L0F00
	MOV	[DI+36],DH
L0F13:	RET

SELDSK:	MOV	DH,0
	MOV	BX,DX
	PUSH	CS
	POP	DS
	MOV	AL,[NUMIO]
	CMP	BL,AL
	JNB	L0F13
	SHL	BX
	MOV	DX,[BX+DRVTAB]
	MOV	[CURDRV],DX
L0F2B:	RET

BUFIN:	MOV	AX,CS
	MOV	ES,AX
	MOV	SI,DX
	MOV	CH,0
	LODW
	OR	AL,AL
	JZ	L0F2B
	MOV	BL,AH
	MOV	BH,CH
	CMP	AL,BL
	JBE	L0F46
	CMP	B,[BX+SI],0DH
	JZ	L0F48
L0F46:	MOV	BL,CH
L0F48:	MOV	DL,AL
	DEC	DX
NEWLIN:	SEG	CS
	MOV	AL,[CARPOS]
	SEG	CS
	MOV	[STARTPOS],AL
	PUSH	SI
	MOV	DI,INBUF
	MOV	AH,CH
	MOV	BH,CH
	MOV	DH,CH
GETCH:	CALL	IN
	CMP	AL,7FH
	JZ	BACKSP
	CMP	AL,8
	JZ	BACKSP
	CMP	AL,0DH
	JZ	ENDLIN
	CMP	AL,0AH
	JZ	L0FC9
	CMP	AL,18H
	JZ	KILNEW
	CMP	AL,1BH
	JZ	ESC
SAVCH:	CMP	DH,DL
	JNB	GETCH
	STOB
	INC	DH
	CALL	BUFOUT
	OR	AH,AH
	JNZ	GETCH
	CMP	BH,BL
	JNB	GETCH
	INC	SI
	INC	BH
	JP	GETCH

ESC:
	CALL	IN
	MOV	CL,ESCTABLEN
	PUSH	DI
	MOV	DI,3
	REPNE
	SCAB
	POP	DI
	AND	CL,0FEH
	MOV	BP,CX
	SEG	CS
	JMP	[BP+ESCFUNC]

ENDLIN:	STOB
	CALL	OUT
	POP	DI
	MOV	[DI-1],DH
	INC	DH
COPYNEW:
	MOV	BP,ES
	MOV	BX,DS
	MOV	ES,BX
	MOV	DS,BP
	MOV	SI,INBUF
	MOV	CL,DH
	REPE
	MOVB
	RET

CRLF:	MOV	AL,0DH
	CALL	OUT
	MOV	AL,0AH
	JMP	OUT

L0FC9:	CALL	CRLF
	JP	GETCH

KILNEW:	MOV	AL,5CH	;'\'
	CALL	OUT
	POP	SI
PUTNEW:	CALL	CRLF
	SEG	CS
	MOV	AL,[STARTPOS]
	CALL	TAB
	JMP	NEWLIN

BACKSP:	OR	DH,DH
	JZ	OLDBAK
	CALL	BACKUP
	SEG	ES
	MOV	AL,[DI]
	CMP	AL,20H	;' '
	JNB	OLDBAK
	CMP	AL,9
	JZ	BAKTAB
	CALL	L1039
OLDBAK:	OR	AH,AH
	JNZ	L1001
	OR	BH,BH
	JZ	L1001
	DEC	BH
	DEC	SI
L1001:	JMP	GETCH

BAKTAB:	PUSH	DI
	DEC	DI
	STD
	MOV	CL,DH
	MOV	AL,20H	;' '
	PUSH	BX
	MOV	BL,7
	JCXZ	L101E
FNDPOS:	SCAB
	JBE	L101C
	SEG	ES
	CMP	B,[DI+1],9
	JZ	L1023
	DEC	BL
L101C:	LOOP	FNDPOS
L101E:	SEG	CS
	SUB	BL,[STARTPOS]
L1023:	SUB	BL,DH
	ADD	CL,BL
	AND	CL,7
	CLD
	POP	BX
	POP	DI
	JZ	OLDBAK
L102F:	CALL	L1039
	LOOP	L102F
	JP	OLDBAK

BACKUP:	DEC	DH
	DEC	DI
L1039:	MOV	AL,8
	CALL	OUT
	MOV	AL,20H	;' '
	CALL	OUT
	MOV	AL,8
	JMP	OUT

TWOESC:	MOV	AL,1BH
	JMP	SAVCH

COPYLIN:
	MOV	CL,BL
	SUB	CL,BH
	JP	L105A

COPYSTR:
	CALL	FINDOLD
	JP	L105A

COPYONE:
	MOV	CL,1
L105A:	CMP	DH,DL
	JZ	L106D
	CMP	BH,BL
	JZ	L106D
	LODB
	STOB
	CALL	BUFOUT
	INC	BH
	INC	DH
	LOOP	L105A
L106D:	JMP	GETCH

SKIPONE:
	CMP	BH,BL
	JZ	L106D
	INC	BH
	INC	SI
	JMP	GETCH

SKIPSTR:
	CALL	FINDOLD
	ADD	SI,CX
	ADD	BH,CL
	JMP	GETCH

FINDOLD:
	CALL	IN
	MOV	CL,BL
	SUB	CL,BH
	JZ	L10A4
	DEC	CX
	JZ	L10A4
	PUSH	ES
	PUSH	DS
	POP	ES
	PUSH	DI
	MOV	DI,SI
	INC	DI
	REPNE
	SCAB
	POP	DI
	POP	ES
	JNZ	L10A4
	NOT	CL
	ADD	CL,BL
	SUB	CL,BH
L10A3:	RET

L10A4:	POP	BP
	JMP	GETCH

REEDIT:	MOV	AL,40H	;'@'
	CALL	OUT
	POP	DI
	PUSH	DI
	PUSH	ES
	PUSH	DS
	CALL	COPYNEW
	POP	DS
	POP	ES
	POP	SI
	MOV	BL,DH
	JMP	PUTNEW

ENTERINS:
	MOV	AH,-1
	JMP	GETCH

EXITINS:
	MOV	AH,0
	JMP	GETCH

ESCFUNC DW      GETCH
        DW      TWOESC
        DW      EXITINS
        DW      ENTERINS
        DW      BACKSP
        DW      REEDIT
        DW      KILNEW
        DW      COPYLIN
        DW      SKIPSTR
        DW      COPYSTR
        DW      SKIPONE
        DW      COPYONE

BUFOUT:	CMP	AL,' '
	JNB	OUT
	CMP	AL,9
	JZ	OUT
	PUSH	AX
	MOV	AL,'^'
	CALL	OUT
	POP	AX
	OR	AL,40H
	JP	OUT

CONOUT:	MOV	AL,DL
OUT:	CMP	AL,20H	;' '
	JB	CTRLOUT
	CMP	AL,7FH
	JZ	OUTCH
	SEG	CS
	INC	B,[CARPOS]
OUTCH:	PUSH	AX
	CALL	STATCHK
	POP	AX
	CALL	BIOSOUT,BIOSSEG
	SEG	CS
	TEST	B,[PFLAG],-1
	JZ	L10A3
	CALL	BIOSPRINT,BIOSSEG
L1117:	RET

STATCHK:
	CALL	BIOSSTAT,BIOSSEG
	JZ	L1117
INCHK:	CALL	BIOSIN,BIOSSEG
	CMP	AL,13H
	JNZ	L112D
	CALL	BIOSIN,BIOSSEG
L112D:	CMP	AL,10H
	JZ	PRINTON
	CMP	AL,0EH
	JZ	PRINTOFF
	CMP	AL,3
	JNZ	L1117

; Ctrl-C handler.
; "^C" and CR/LF is printed. Then the user registers are restored and the
; user CTRL-C handler is executed. At this point the top of the stack has
; 1) the interrupt return address should the user CTRL-C handler wish to
; allow processing to continue; 2) the original interrupt return address
; to the code that performed the function call in the first place. If the
; user CTRL-C handler wishes to continue, it must leave all registers
; unchanged and IRET. The function that was interrupted will simply be
; repeated.

	MOV	AL,3
	CALL	BUFOUT
	CALL	CRLF
	CLI
	SEG	CS
	MOV	SS,[SSSAVE]
	SEG	CS
	MOV	SP,[SPSAVE]
	POP	AX
	POP	BX
	POP	CX
	POP	DX
	POP	SI
	POP	DI
	POP	BP
	POP	DS
	POP	ES
	INT	23H
	JMP	COMMAND

PRINTON:
	SEG	CS
	MOV	B,[PFLAG],1
	RET

PRINTOFF:
	SEG	CS
	MOV	B,[PFLAG],0
	RET

CTRLOUT:
	CMP	AL,CR
	JZ	ZERPOS
	CMP	AL,8
	JZ	BACKPOS
	CMP	AL,9
	JNZ	L1192
	SEG	CS
	MOV	AL,[CARPOS]
	OR	AL,0F8H
	NEG	AL
TAB:	PUSH	CX
	MOV	CL,AL
	MOV	CH,0
	JCXZ	L118A
L1183:	MOV	AL,' '
	CALL	OUT
	LOOP	L1183
L118A:	POP	CX
L118B:	RET

ZERPOS:	SEG	CS
	MOV	B,[CARPOS],0
L1192:	JMP	OUTCH

BACKPOS:
	SEG	CS
	DEC	B,[CARPOS]
	JMP	OUTCH

CONSTAT:
	CALL	BIOSSTAT,BIOSSEG
	JZ	L118B
	OR	AL,-1
	RET

CONIN:	CALL	IN
	PUSH	AX
	CALL	OUT
	POP	AX
	RET

IN:	CALL	INCHK
	JZ	IN
L11B5:	RET

RAWIO:	MOV	AL,DL
	CMP	AL,-1
	JNZ	RAWOUT
	CALL	BIOSSTAT,BIOSSEG
	JZ	L11B5
RAWINP:	CALL	BIOSIN,BIOSSEG
	RET

RAWOUT:	CALL	BIOSOUT,BIOSSEG
	RET

LIST:	MOV	AL,DL
L11D1:	PUSH	AX
	CALL	STATCHK
	POP	AX
	CALL	BIOSPRINT,BIOSSEG
L11DB:	RET

PRTBUF:	MOV	SI,DX
OUTSTR:	LODB
	CMP	AL,'$'
	JZ	L11DB
	CALL	OUT
	JP	OUTSTR

OUTMES:	SEG	CS
	LODB
	CMP	AL,'$'
	JZ	L11DB
	CALL	OUT
	JP	OUTMES

MAKEFCB:
	MOV	DL,0
	OR	AL,AL
	JZ	L11FF
L11F9:	CALL	GETLET
	JZ	L11F9
	DEC	SI
L11FF:	MOV	AL,0
	CMP	B,[SI],' '
	JB	L121D
	CMP	B,[SI+1],':'
	JNZ	L121D
	CALL	GETLET
	INC	SI
	SUB	AL,40H
	JBE	L121B
	SEG	CS
	CMP	AL,[NUMIO]
	JBE	L121D
L121B:	MOV	DL,-1
L121D:	STOB
	MOV	CX,8
	CALL	GETWORD
	CMP	B,[SI],'.'
	JNZ	L122A
	INC	SI
L122A:	MOV	CX,3
	CALL	GETWORD
	SEG	CS
	LDS	BX,[SPSAVE]
	MOV	[BX+8],SI
	XOR	AX,AX
	STOW
	STOW
	MOV	AL,DL
	RET

GETWORD:
	CALL	GETLET
	JZ	L125D
	CMP	AL,' '
	JBE	L125D
	CMP	AL,'*'
	JNZ	L1252
	MOV	AL,'?'
	DEC	CX
	REPE
	STOB
	INC	CX
L1252:	STOB
	CMP	AL,'?'
	JNZ	L125A
	OR	DL,1
L125A:	LOOP	GETWORD
	INC	SI
L125D:	MOV	AL,' '
	REPE
	STOB
	DEC	SI
L1262:	RET

GETLET:

;Get a byte from [SI], convert it to upper case, and compare for delimiter.
;ZF set if a delimiter, CY set if a control character (other than TAB).

	LODB
	AND	AL,7FH
	CMP	AL,'a'
	JB	L1270
	CMP	AL,'z'
	JA	L1270
	SUB	AL,20H
L1270:	CMP	AL,' '
	JZ	L1262
	CMP	AL,'='
	JZ	L1262
	CMP	AL,','
	JZ	L1262
	CMP	AL,';'
	JZ	L1262
	CMP	AL,'.'
	JZ	L1262
	CMP	AL,':'
	JZ	L1262
	CMP	AL,'"'
	JZ	L1262
	CMP	AL,'+'
	JZ	L1262
	CMP	AL,'/'
	JZ	L1262
	CMP	AL,'['
	JZ	L1262
	CMP	AL,']'
	JZ	L1262
	CMP	AL,9
	RET

SETVECT:
	XOR	BX,BX
	MOV	ES,BX
	MOV	BL,AL
	SHL	BX
	SHL	BX
	SEG	ES
	MOV	[BX],DX
	SEG	ES
	MOV	[BX+2],DS
	RET

NEWBASE:
	MOV	ES,DX
	SEG	CS
	LDS	SI,[SPSAVE]
	MOV	DS,[SI+CSSAVE]
	XOR	SI,SI
	MOV	DI,SI
	MOV	CX,0080H
	REPE
	MOVSW
SETMEM:

; Inputs:
;       AX = Size of memory in paragraphs
;       DX = Segment
; Function:
;       Completely prepares a program base at the 
;       specified segment.
; Outputs:
;       DS = DX
;       ES = DX
;       [0] has INT 20H
;       [2] = First unavailable segment ([ENDMEM])
;       [5] to [9] form a long call to the entry point
;       [10] to [13] have exit address (from INT 22H)
;       [14] to [17] have ctrl-C exit address (from INT 23H)
;       [18] to [21] have fatal error address (from INT 24H)
; DX,BP unchanged. All other registers destroyed.

	XOR	CX,CX
	MOV	DS,CX
	MOV	ES,DX
	MOV	SI,EXIT
	MOV	DI,SAVEXIT
	MOVSW
	MOVSW
	MOVSW
	MOVSW
	MOVSW
	MOVSW
	SEG	CS
	MOV	CX,[ENDMEM]
	SEG	ES
	MOV	[L0002],CX
	SUB	CX,DX
	CMP	CX,0FFFH
	JBE	L12EB
	MOV	CX,0FFFH
L12EB:	MOV	BX,12
	SUB	BX,CX
	SHL	CX
	SHL	CX
	SHL	CX
	SHL	CX
	MOV	DS,DX
	MOV	[L0006],CX
	MOV	[L0008],BX
	MOV	W,[L0000],20CDH
	MOV	B,[L0005],9AH
	RET

DATE16:	PUSH	CX
	PUSH	DX
	CALL	READTIME
	POP	DX
	POP	CX
	MOV	AX,[MONTH]
	SHL	AL
	SHL	AL
	SHL	AL
	SHL	AL
	SHL	AX
	OR	AL,[DAY]
L1326:	RET

FOURYEARS EQU	3*365+366

READTIME:

;Gets time in CX:DX. Figures new date if it has changed.
;Uses AX, CX, DX.

	CALL	BIOSGETTIME,BIOSSEG
	CMP	AX,[DAYCNT]
	JZ	L1326
	CMP	AX,FOURYEARS*30		;# of days in 120 years
	JNB	L1326
	MOV	[DAYCNT],AX
	PUSH	SI
	PUSH	CX
	PUSH	DX
	XOR	DX,DX
	MOV	CX,FOURYEARS
	DIV	AX,CX
	SHL	AX
	SHL	AX
	SHL	AX
	MOV	CX,AX
	MOV	SI,YRTAB
	CALL	L1375
	SHR	CX
	JNB	L135A
	ADD	DX,200
L135A:	CALL	SETYEAR
	MOV	CL,1
	MOV	SI,MONTAB
	CALL	L1375
	MOV	[MONTH],CL
	INC	DX
	MOV	[DAY],DL
	CALL	L1429
	POP	DX
	POP	CX
	POP	SI
L1374:	RET

L1375:	MOV	AH,0
L1377:	LODB
	CMP	DX,AX
	JB	L1374
	SUB	DX,AX
	INC	CX
	JP	L1377

SETYEAR:

;Set year with value in CX. Adjust length of February for this year.

	MOV	[YEAR],CL
L1385:	TEST	CL,3
	MOV	AL,1CH
	JNZ	L138E
	INC	AL
L138E:	MOV	[MONTAB+1],AL
	RET

YRTAB   DB      200,166         ;Leap year
        DB      200,165
        DB      200,165
        DB      200,165
MONTAB  DB      31              ;January
        DB      28              ;February--reset each time year changes
        DB      31              ;March
        DB      30              ;April
        DB      31              ;May
        DB      30              ;June
        DB      31              ;July
        DB      31              ;August
        DB      30              ;September
        DB      31              ;October
        DB      30              ;November
        DB      31              ;December

GETDATE:
	PUSH	CS
	POP	DS
	CALL	READTIME
	MOV	AX,[YEAR]
	MOV	BX,[DAY]
	LDS	SI,[SPSAVE]
	MOV	[SI+DXSAVE],BX
	ADD	AX,1980
	MOV	[SI+CXSAVE],AX
	SEG	CS
	MOV	AL,[WEEKDAY]
L13C3:	RET

SETDATE:
	MOV	AL,-1
	SUB	CX,1980
	JB	L13C3
	CMP	CX,119
	JA	L13C3
	OR	DH,DH
	JZ	L13C3
	OR	DL,DL
	JZ	L13C3
	CMP	DH,12
	JA	L13C3
	PUSH	CS
	POP	DS
	CALL	L1385
	MOV	AL,DH
	MOV	BX,MONTAB-1
	XLAT
	CMP	AL,DL
	MOV	AL,-1
	JB	L13C3
	CALL	SETYEAR
	MOV	[DAY],DX
	SHR	CX
	SHR	CX
	MOV	AX,FOURYEARS
	MOV	BX,DX
	MUL	AX,CX
	MOV	CL,[YEAR]
	AND	CL,3
	MOV	SI,YRTAB
	MOV	DX,AX
	SHL	CX
	CALL	L143C
	MOV	CL,BH
	MOV	SI,MONTAB
	DEC	CX
	CALL	L143C
	MOV	CL,BL
	DEC	CX
	ADD	DX,CX
	XCHG	AX,DX
	MOV	[DAYCNT],AX
	CALL	BIOSSETDATE,BIOSSEG
L1429:	MOV	AX,[DAYCNT]
	XOR	DX,DX
	MOV	CX,7
	INC	AX
	INC	AX
	DIV	AX,CX
	MOV	[WEEKDAY],DL
	XOR	AL,AL
L143B:	RET

L143C:	MOV	AH,0
	JCXZ	L143B
L1440:	LODB
	ADD	DX,AX
	LOOP	L1440
	RET

GETTIME:
	PUSH	CS
	POP	DS
	CALL	READTIME
	LDS	SI,[SPSAVE]
	MOV	[SI+6],DX
	MOV	[SI+4],CX
	XOR	AL,AL
L1457:	RET

SETTIME:
	MOV	AL,-1
	CMP	CH,24
	JNB	L1457
	CMP	CL,60
	JNB	L1457
	CMP	DH,60
	JNB	L1457
	CMP	DL,100
	JNB	L1457
	CALL	BIOSSETTIME,BIOSSEG
	XOR	AL,AL
	RET

; Default handler for division overflow trap

DIVOV:	PUSH	SI
	MOV	SI,DIVMES
	CALL	OUTMES
	POP	SI
	INT	23H			;use ctrl-c abort on divide overflow
	IRET

CODSIZ	EQU	$-CODSTRT		;size of code segment

;*****  DATA AREA  *****

CONSTRT	EQU	$			;start of constants segment

IONAME	DB	"PRN","LST","NUL","AUX","CON"
DIVMES	DB	CR,LF,"Divide overflow",CR,LF,"$"
CARPOS	DB	0
STARTPOS DB	0
PFLAG	DB	0
DIRTYDIR DB	0
NUMIO	DB	0
CONTPOS	DW	0
DMAADD	DW	80H			;disk transfer offset
	DW	0			;disk transfer segment
ENDMEM	DW	0
MAXSEC	DW	0
BUFFER	DW	0
BUFSECNO DW	0
BUFDRVNO DB	-1
DIRTYBUF DB	0
BUFDRVBP DW	0
DIRBUFID DW	-1
DAY	DB	0
MONTH	DB	0
YEAR	DW	0
DAYCNT	DW	-1
WEEKDAY	DB	0
CURDRV	DW	0
DRVTAB	DW	0
	DS	28

DOSLEN	EQU	CODSIZ+($-CONSTRT)

INBUF	DS	128			;14E4
CONBUF	DS	131			;1564
LASTENT	DW	0
EXITHOLD DS	4
FATBASE	DW	0			;not used
NAME1	DS	11
ATTRIB	DB	0
NAME2	DS	11
NAME3	DS	12
EXTFCB	DB	0
CREATING DB	0
TEMP:
SPSAVE	DW	0
SSSAVE	DW	0
CONTSTK	DW	0
SECCLUSPOS DB	0
DSKERR	DB	0
TRANS	DB	0
PREREAD	DB	0
READOP	DB	0
THISDRV	DB	0			;not used

	ALIGN
FCB	DW	0
NEXTADD	DW	0
RECPOS	DS	4
RECCNT	DW	0
LASTPOS	DW	0
CLUSNUM	DW	0
SECPOS	DW	0
VALSEC	DW	0
BYTSECPOS DW	0
BYTPOS	DS	4
BYTCNT1	DW	0
BYTCNT2	DW	0
SECCNT	DW	0
ENTFREE	DW	0			;not used
	DS	26H+80H			;## was 1640 add 80H
IOSTACK	DS	3CH+80H			;## was 1666 add 80H
DSKSTACK:				;was 16A2
DIRBUF:	
	ORG	DOSLEN			;back to 14E4
	PUT	DOSLEN+100H

MOVFAT:	SEG	ES
	REPE
	MOVB
	CLD
L14E8:	CALL	SETMEM
	RET	L

DOSINIT:
	CLI
	CLD
	PUSH	CS
	POP	ES
	LODB
	SEG	ES
	MOV	[NUMIO],AL
	MOV	BX,DRVTAB
	MOV	DI,MEMSTRT+2
L14FB:	SEG	ES
	MOV	[BX],DI
	MOV	BP,DI
	INC	BX
	INC	BX
	SEG	ES
	MOV	AL,[DRVCNT]
	STOB
	LODW
	PUSH	SI
	MOV	SI,AX
	LODW
	STOW
	MOV	DX,AX
	SEG	ES
	CMP	AX,[MAXSEC]
	JBE	L151A
	SEG	ES
	MOV	[MAXSEC],AX
L151A:	LODB
	DEC	AL
	STOB
	JZ	HAVSHFT
	CBW
L1521:	INC	AH
	SAR	AL
	JNZ	L1521
	MOV	AL,AH
HAVSHFT:
	STOB
	MOVSW
	MOVB
	MOVSW
	MOV	AX,DX
	MOV	CL,5
	SHR	AX,CL
	MOV	CX,AX
	DEC	AX
	SEG	ES
	ADD	AX,[BP+8]
	XOR	DX,DX
	DIV	AX,CX
	STOW
	SHR	AX
	ADC	AX,0
	SEG	ES
	MOV	[MEMSTRT],AX
	MOVSW
L1549:	MOV	AL,1
	MOV	DX,1
L154E:	PUSH	DX
	CALL	L1690
	POP	DX
	CMP	AL,DL
	JZ	L1565
	CMP	AL,DH
	MOV	DH,DL
	MOV	DL,AL
	JNZ	L154E
	SEG	ES
	DEC	[BP+0CH]
	JP	L1549

L1565:	STOB
	SEG	ES
	MUL	AL,[BP+7]
	SEG	ES
	ADD	AX,[BP+5]
	STOW
	MOV	DX,AX
	SEG	ES
	ADD	AX,[MEMSTRT]
	STOW
	XCHG	AX,CX
	STOW
	XCHG	AX,DX
	SEG	ES
	ADD	AX,[BP+0AH]
	STOW
	CALL	L169D
	XCHG	AX,CX
	STOW
	MOV	AX,00FFH
	STOB
	SEG	ES
	MOV	AL,[BP+0EH]
	SEG	ES
	MUL	AX,[BP+1]
	ADD	DI,AX
	POP	SI
	SEG	ES
	MOV	AL,[DRVCNT]
	INC	AL
	SEG	ES
	MOV	[DRVCNT],AL
	SEG	ES
	CMP	AL,[NUMIO]
	JNB	L15A7
	JMP	L14FB

L15A7:	LODW
	SEG	ES
	MOV	BX,[MAXSEC]
	MOV	AX,DIRBUF
	ADD	AX,BX
	SEG	ES
	MOV	[BUFFER],AX
	PUSH	DI
	ADD	DI,BX
	ADD	DI,BX
	ADD	DI,ADJFAC		;need variable label here. was LFFEF
	MOV	CL,4
	SHR	DI,CL
	MOV	BP,DI
	XOR	AX,AX
	MOV	DS,AX
	MOV	ES,AX
	MOV	DI,INTBASE
	MOV	AX,QUIT
	STOW
	MOV	AX,CS
	MOV	B,[ENTRYPOINT],0EAH
	MOV	W,[ENTRYADDR],ENTRY
	MOV	[ENTRYSEG],AX
	MOV	W,[L0000],DIVOV
	MOV	[L0002],AX
	MOV	CX,9
	REPE
	STOW
	MOV	W,[INTBASE+4],COMMAND
	MOV	W,[INTBASE+0CH],IRET
	MOV	W,[INTBASE+10H],IRET
	MOV	AX,0015H
	STOW
	MOV	AX,BIOSSEG
	STOW
	STOW
	STOW
	MOV	W,[INTBASE+18H],BIOSWRITE
	MOV	DX,CS
	MOV	DS,DX
	ADD	DX,BP
	MOV	W,[DMAADD],0080H
	MOV	[DMAADD+2],DX
	MOV	AX,[DRVTAB]
	MOV	[CURDRV],AX
	MOV	CX,DX
	MOV	BX,15
L162D:
	INC	CX
	JZ	L1640
	MOV	DS,CX
	MOV	AL,[BX]
	NOT	AL
	MOV	[BX],AL
	CMP	AL,[BX]
	NOT	AL
	MOV	[BX],AL
	JZ	L162D
L1640:
	SEG	CS
	MOV	[ENDMEM],CX
	XOR	CX,CX
	MOV	DS,CX
	MOV	W,[INTBASE+8],0100H
	MOV	[INTBASE+0AH],DX
	MOV	SI,001BH
	CALL	OUTMES
	PUSH	CS
	POP	DS
	PUSH	CS
	POP	ES
	POP	SI
	MOV	AX,[MAXSEC]
	SHL	AX
	ADD	AX,0FFE0H
	JZ	L168D
	MOV	DI,DRVTAB
	MOV	CX,15
L166E:	ADD	[DI],AX
	INC	DI
	INC	DI
	LOOP	L166E
	MOV	CX,SI
	MOV	SI,MEMSTRT+2
	SUB	CX,SI
	MOV	DI,AX
	ADD	DI,SI
	OR	AX,AX
	JS	L168A
	DEC	CX
	ADD	DI,CX
	ADD	SI,CX
	INC	CX
	STD
L168A:	JMP	MOVFAT

L168D:	JMP	L14E8

L1690:	SEG	ES
	MUL	AL,[BP+7]
	SEG	ES
	ADD	AX,[BP+5]
	SEG	ES
	ADD	AX,[MEMSTRT]
L169D:	SEG	ES
	SUB	AX,[BP+0CH]
	NEG	AX
	SEG	ES
	MOV	CL,[BP+4]
	SHR	AX,CL
	INC	AX
	MOV	CX,AX
	INC	AX
	MOV	DX,AX
	SHR	DX
	ADC	AX,DX
	SEG	ES
	MOV	SI,[BP+1]
	ADD	AX,SI
	DEC	AX
	XOR	DX,DX
	DIV	AX,SI
	RET

DRVCNT	DB	0
MEMSTRT	EQU	$+100H			;## was 16C0
ADJFAC	EQU	DIRBUF-MEMSTRT		;## was 16A2-16C0+0D=FFEF
LFFEF	EQU	0FFEFH
;
END	
