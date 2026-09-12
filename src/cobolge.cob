*> cobolge — Classic Malbolge engine (59049 ternary cells) in GnuCOBOL.
*> Bit-exact port of Malbolge-Engine vm.c via the Rustbolge/Swiftbolge/Javolge
*> lineage: crazy5 split-chunk table, lazy crazy chain fill with block
*> granularity, write-through shadow overlay, instruction decode (mem[c]+c)%94.
*>
*> CLI (flag-for-flag compatible with rustbolge / swiftbolge / javolge):
*>   cobolge <program.mal> [max_steps] [--snapshot-out f] [--resume f] [--json] < input
*>
*> Raw byte I/O goes through c/shim.c (cobgetc/cobputc/cobwrite/cobwerr/
*> cobfread/cobfsave): COBOL DISPLAY/ACCEPT cannot move raw bytes faithfully.
*> Numeric ORD/CHAR semantics (measured on GnuCOBOL 3.2.0): ORD(c)=byte+1,
*> CHAR(n)=byte at n-1.  JSON report/snapshot layout matches serde_json
*> compact output byte-for-byte so hashes agree with the -bolge family.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. cobolge.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *> ---------------- machine constants ----------------
       01 WS-CONST.
          05 MEM-SIZE      PIC 9(9) COMP-5 VALUE 59049.
          05 LAST-POS      PIC 9(9) COMP-5 VALUE 59048.
          05 POW9          PIC 9(9) COMP-5 VALUE 19683.
          05 HALF          PIC 9(9) COMP-5 VALUE 243.
          05 BLOCK-SIZE    PIC 9(9) COMP-5 VALUE 243.
          05 OUT-CAP       PIC 9(9) COMP-5 VALUE 65536.
      *> ---------------- machine state ----------------
       01 WS-MACHINE.
          05 A-REG         PIC 9(9) COMP-5 VALUE 0.
          05 C-REG         PIC 9(9) COMP-5 VALUE 0.
          05 D-REG         PIC 9(9) COMP-5 VALUE 0.
          05 HALTED        PIC X VALUE 'N'.
          05 HALT-CODE     PIC 99 COMP-5 VALUE 0.
      *>    1=VInstruction 2=InvalidCell 3=Eof 4=StepsExhausted 5=RestoredHalted
          05 STEPS         PIC 9(18) COMP-5 VALUE 0.
          05 INPUT-POS     PIC 9(18) COMP-5 VALUE 0.
          05 OUT-LEN       PIC 9(9) COMP-5 VALUE 0.
          05 FILL-START    PIC 9(9) COMP-5 VALUE 2.
          05 CHAIN-UNTIL   PIC 9(9) COMP-5 VALUE 2.
          05 MAX-STEPS     PIC 9(18) COMP-5 VALUE 100000000.
      *> ---------------- memory tables ----------------
      *> overlay: address (0..59048) -> value, present flag ('Y')
       01 WS-OVERLAY.
          05 OV-PRESENT    PIC X OCCURS 59049 TIMES.
          05 OV-VAL        PIC 9(9) COMP-5 OCCURS 59049 TIMES.
      *> chain: crazy values [0, chain_until) computed so far
       01 WS-CHAIN.
          05 CHAIN-VAL     PIC 9(9) COMP-5 OCCURS 59049 TIMES.
      *> crazy5 table: C5(a5*243 + b5 + 1) = tritwise combine of 5 trits
       01 WS-CRAZY5.
          05 C5            PIC 9(5) COMP-5 OCCURS 59049 TIMES.
      *> crazy trit table as digits, position k (1..9) = [1,0,0,1,0,2,2,2,1]
       01 TRIT-STR   PIC X(9) VALUE "100102221".
      *> ENCRYPT table as hex byte string (byte k = ORD(ENC-STR(k:1)) - 1)
       01 ENC-STR    PIC X(94) VALUE
              X"357a5d2667717479667224287765347b575029482d5a6e2c5b255c33644c2b513b3e5521704a53373246684f4131434236765e3d495f302f387c6a7362396d3c2e545661636075592a4d4b27587e78446c7d52456f6b4e3a233f47226940".
      *> ---------------- program / input / json buffers ----------------
       01 PG-BUF       PIC X(200000).
       01 PG-LEN       PIC 9(9) COMP-5.
       01 IN-BUF       PIC X(1000000).
       01 IN-LEN       PIC 9(9) COMP-5.
       01 JS-BUF       PIC X(4000000).
       01 JS-LEN       PIC 9(9) COMP-5.
       01 OUT-BUF      PIC X(65536).
      *> ---------------- CLI args ----------------
       01 WS-ARGS.
          05 ARG-COUNT     PIC 9(9) COMP-5.
          05 ARG-I         PIC 9(9) COMP-5.
          05 ARG-STR       PIC X(512).
          05 ARG-TRIM      PIC X(512).
          05 PROG-FILE     PIC X(512).
          05 PROG-SET      PIC X VALUE 'N'.
          05 SNAP-FILE     PIC X(512).
          05 SNAP-SET      PIC X VALUE 'N'.
          05 RESUME-FILE   PIC X(512).
          05 RESUME-SET    PIC X VALUE 'N'.
          05 JSON-FLAG     PIC X VALUE 'N'.
          05 WS-TOK-LEN    PIC 9(9) COMP-5.
      *> ---------------- mem_get / crazy / ensure_filled temps ----------------
       01 WS-MEM.
          05 MEM-ADDR      PIC 9(9) COMP-5.
          05 MEM-IDX       PIC 9(9) COMP-5.
          05 MEM-RESULT    PIC 9(9) COMP-5.
       01 WS-CRAZY.
          05 CRAZY-A       PIC 9(9) COMP-5.
          05 CRAZY-B       PIC 9(9) COMP-5.
          05 CRAZY-AA      PIC 9(9) COMP-5.
          05 CRAZY-BB      PIC 9(9) COMP-5.
05 CRAZY-IDX     PIC 9(9) COMP-5.
           05 CRAZY-LOW     PIC 9(9) COMP-5.
           05 CRAZY-R       PIC 9(9) COMP-5.
           05 CRAZY-HA      PIC 9(9) COMP-5.
           05 CRAZY-HB      PIC 9(9) COMP-5.
       01 WS-EF.
          05 EF-X          PIC 9(9) COMP-5.
          05 EF-BLOCK-END  PIC 9(9) COMP-5.
          05 EF-TAIL-END   PIC 9(9) COMP-5.
          05 EF-I          PIC 9(9) COMP-5.
          05 EF-IDX        PIC 9(9) COMP-5.
          05 EF-P1         PIC 9(9) COMP-5.
          05 EF-P2         PIC 9(9) COMP-5.
          05 EF-NXT        PIC 9(9) COMP-5.
05 EF-V1         PIC 9(9) COMP-5.
           05 EF-V2         PIC 9(9) COMP-5.
           05 EF-Q          PIC 9(9) COMP-5.
      *> ---------------- run loop temps ----------------
       01 WS-RUN.
          05 RUN-V         PIC 9(9) COMP-5.
          05 RUN-INS       PIC 9(9) COMP-5.
          05 RUN-R         PIC 9(9) COMP-5.
05 RUN-B         PIC 9(9) COMP-5.
           05 RUN-BYTE      PIC 9(9) COMP-5.
           05 RUN-Q         PIC 9(9) COMP-5.
      *> ---------------- number to ascii helpers ----------------
       01 WS-NUM.
          05 NUM-IN        PIC 9(18) COMP-5.
          05 NUM-TMP       PIC 9(18) COMP-5.
          05 NUM-NEW       PIC 9(18) COMP-5.
          05 NUM-REM       PIC 9(18) COMP-5.
          05 NUM-REV       PIC X(21).
          05 NUM-REV-LEN   PIC 9(9) COMP-5.
          05 NUM-OUT       PIC X(21).
          05 NUM-LEN       PIC 9(9) COMP-5.
          05 NUM-K         PIC 9(9) COMP-5.
          05 NUM-CH        PIC X.
      *> ---------------- json building / parsing temp ----------------
       01 WS-JSON-STATE.
          05 JPTR          PIC 9(9) COMP-5.
          05 JCH           PIC X.
          05 JKEY          PIC X(32).
          05 JKEY-LEN      PIC 9(9) COMP-5.
          05 JNUM          PIC 9(18) COMP-5.
          05 JBOOL         PIC X VALUE 'N'.
          05 J-I           PIC 9(9) COMP-5.
          05 J-IDX         PIC 9(9) COMP-5.
          05 J-TOK         PIC X(16).
          05 J-FIRST       PIC X VALUE 'Y'.
       01 NUM-ARR      PIC 9(18) COMP-5 OCCURS 59049 TIMES.
      *> ---------------- misc ----------------
       01 WS-WORK.
          05 WS-K          PIC 9(9) COMP-5.
          05 WS-N          PIC 9(18) COMP-5.
          05 WS-ERR        PIC S9(9) COMP-5.
          05 WS-CH         PIC X.
          05 WS-HEX        PIC X(16) VALUE "0123456789abcdef".
          05 WS-HEX-OUT    PIC X(2).
          05 WS-GETC       PIC S9(9) COMP-5.
          05 WS-FIRST      PIC X.

       PROCEDURE DIVISION.
      *> ==================== MAIN ====================
MAIN-PARA.
            CALL "cobinit".
            PERFORM INIT-STATE.
           PERFORM PARSE-ARGS.
           IF RESUME-SET = 'Y'
              PERFORM READ-RESUME
           ELSE
              IF PROG-SET = 'Y'
                 PERFORM READ-PROGRAM
              ELSE
                 PERFORM USAGE-DIE
              END-IF
           END-IF.
           PERFORM BUILD-CRAZY5.
           PERFORM READ-STDIN.
           PERFORM RUN-VM.
           PERFORM EMIT-OUTPUT.
           IF JSON-FLAG = 'Y'
              PERFORM EMIT-JSON-REPORT
           ELSE
              PERFORM EMIT-PLAIN-REPORT
           END-IF.
           IF SNAP-SET = 'Y'
              PERFORM WRITE-SNAPSHOT
           END-IF.
           MOVE 0 TO RETURN-CODE.
           STOP RUN.
      *> ==================== INIT ====================
       INIT-STATE.
           INITIALIZE WS-OVERLAY.
           INITIALIZE WS-CHAIN.
           MOVE 2 TO FILL-START.
           MOVE 2 TO CHAIN-UNTIL.
           MOVE 0 TO A-REG C-REG D-REG STEPS INPUT-POS OUT-LEN.
           MOVE 'N' TO HALTED.
           MOVE 0 TO HALT-CODE.
           MOVE 100000000 TO MAX-STEPS.
           MOVE 'N' TO PROG-SET SNAP-SET RESUME-SET JSON-FLAG.
           MOVE 'N' TO JBOOL.
           EXIT PARAGRAPH.
      *> ==================== ARGS ====================
       PARSE-ARGS.
           MOVE 0 TO ARG-COUNT.
           ACCEPT ARG-COUNT FROM ARGUMENT-NUMBER.
           PERFORM VARYING ARG-I FROM 0 BY 1 UNTIL ARG-I >= ARG-COUNT
              MOVE SPACES TO ARG-STR
              ACCEPT ARG-STR FROM ARGUMENT-VALUE
              MOVE FUNCTION TRIM(ARG-STR) TO ARG-TRIM
              EVALUATE ARG-TRIM
                 WHEN "--snapshot-out"
                    MOVE SPACES TO ARG-STR
                    ACCEPT ARG-STR FROM ARGUMENT-VALUE
                    MOVE FUNCTION TRIM(ARG-STR) TO SNAP-FILE
                    MOVE 'Y' TO SNAP-SET
                 WHEN "--resume"
                    MOVE SPACES TO ARG-STR
                    ACCEPT ARG-STR FROM ARGUMENT-VALUE
                    MOVE FUNCTION TRIM(ARG-STR) TO RESUME-FILE
                    MOVE 'Y' TO RESUME-SET
                 WHEN "--json"
                    MOVE 'Y' TO JSON-FLAG
                 WHEN OTHER
                    IF ARG-TRIM(1:1) = '-'
                       CONTINUE
                    ELSE
                       IF PROG-SET = 'N'
                          MOVE ARG-TRIM TO PROG-FILE
                          MOVE 'Y' TO PROG-SET
                       ELSE
                          MOVE FUNCTION NUMVAL(ARG-TRIM) TO WS-N
                          IF WS-N > 0
                             MOVE WS-N TO MAX-STEPS
                          END-IF
                       END-IF
                    END-IF
              END-EVALUATE
           END-PERFORM.
           EXIT PARAGRAPH.
      *> ==================== READ PROGRAM ====================
       READ-PROGRAM.
           MOVE PROG-FILE TO ARG-TRIM.
           COMPUTE WS-TOK-LEN = FUNCTION LENGTH(FUNCTION TRIM(PROG-FILE)).
           CALL "cobfread" USING
                BY REFERENCE PROG-FILE
                BY VALUE WS-TOK-LEN
                BY REFERENCE PG-BUF
                BY VALUE 200000
                RETURNING WS-GETC
           END-CALL.
           IF WS-GETC < 0
              MOVE 2 TO RETURN-CODE
              DISPLAY "error: cannot open " FUNCTION TRIM(PROG-FILE)
                 UPON STDERR
              STOP RUN
           END-IF.
           MOVE WS-GETC TO PG-LEN.
           PERFORM LOAD-PROGRAM.
           EXIT PARAGRAPH.
      *> ==================== LOAD ====================
       LOAD-PROGRAM.
           MOVE 0 TO WS-K.
           PERFORM VARYING ARG-I FROM 1 BY 1 UNTIL ARG-I > PG-LEN
              MOVE PG-BUF(ARG-I:1) TO WS-CH
              COMPUTE WS-N = FUNCTION ORD(WS-CH) - 1
              IF WS-N = 10 OR WS-N = 13 OR WS-N = 32 OR WS-N = 9
                 CONTINUE
              ELSE
                 IF WS-N < 33 OR WS-N > 126
                    MOVE 2 TO RETURN-CODE
                    PERFORM FORMAT-HEX
                    DISPLAY "error: invalid character 0x" WS-HEX-OUT
                       " in program" UPON STDERR
                    STOP RUN
                 END-IF
                 IF WS-K < MEM-SIZE
                    COMPUTE MEM-IDX = WS-K + 1
                    MOVE 'Y' TO OV-PRESENT(MEM-IDX)
                    MOVE WS-N TO OV-VAL(MEM-IDX)
                    ADD 1 TO WS-K
                 END-IF
              END-IF
           END-PERFORM.
      *> fill_start = cells.len() > 2 ? len : 2
           IF WS-K > 2
              MOVE WS-K TO FILL-START
           ELSE
              MOVE 2 TO FILL-START
           END-IF.
           MOVE FILL-START TO CHAIN-UNTIL.
           MOVE 0 TO A-REG C-REG D-REG STEPS INPUT-POS OUT-LEN.
           MOVE 'N' TO HALTED.
           MOVE 0 TO HALT-CODE.
           EXIT PARAGRAPH.
      *> ==================== FORMAT-HEX ====================
       FORMAT-HEX.
           COMPUTE WS-K = WS-N / 16 + 1.
           MOVE WS-HEX(WS-K:1) TO WS-HEX-OUT(1:1).
           COMPUTE WS-K = FUNCTION MOD(WS-N, 16) + 1.
           MOVE WS-HEX(WS-K:1) TO WS-HEX-OUT(2:1).
           EXIT PARAGRAPH.
      *> ==================== READ STDIN ====================
       READ-STDIN.
           MOVE 0 TO IN-LEN.
           PERFORM UNTIL IN-LEN >= 1000000
              CALL "cobgetc" RETURNING WS-GETC END-CALL
              IF WS-GETC < 0
                 EXIT PERFORM
              END-IF
              MOVE FUNCTION CHAR(WS-GETC + 1) TO WS-CH
              ADD 1 TO IN-LEN
              MOVE WS-CH TO IN-BUF(IN-LEN:1)
           END-PERFORM.
           EXIT PARAGRAPH.
      *> ==================== BUILD CRAZY5 ====================
       BUILD-CRAZY5.
           PERFORM VARYING CRAZY-A FROM 0 BY 1 UNTIL CRAZY-A >= 243
              PERFORM VARYING CRAZY-B FROM 0 BY 1 UNTIL CRAZY-B >= 243
                 MOVE 0 TO CRAZY-R
                 MOVE 1 TO CRAZY-LOW
                 MOVE CRAZY-A TO CRAZY-AA
                 MOVE CRAZY-B TO CRAZY-BB
                 PERFORM VARYING WS-K FROM 1 BY 1 UNTIL WS-K > 5
                    COMPUTE CRAZY-IDX =
                      FUNCTION MOD(CRAZY-BB, 3) * 3
                      + FUNCTION MOD(CRAZY-AA, 3) + 1
                    COMPUTE CRAZY-R = CRAZY-R
                       + (FUNCTION ORD(TRIT-STR(CRAZY-IDX:1)) - 49)
                          * CRAZY-LOW
                    DIVIDE CRAZY-AA BY 3 GIVING CRAZY-AA
                    DIVIDE CRAZY-BB BY 3 GIVING CRAZY-BB
                    COMPUTE CRAZY-LOW = CRAZY-LOW * 3
                 END-PERFORM
                 COMPUTE CRAZY-IDX = CRAZY-A * 243 + CRAZY-B + 1
                 MOVE CRAZY-R TO C5(CRAZY-IDX)
              END-PERFORM
           END-PERFORM.
           EXIT PARAGRAPH.
      *> ==================== MEM-GET ====================
       MEM-GET.
           COMPUTE MEM-IDX = MEM-ADDR + 1.
           IF OV-PRESENT(MEM-IDX) = 'Y'
              MOVE OV-VAL(MEM-IDX) TO MEM-RESULT
              EXIT PARAGRAPH
           END-IF.
           IF MEM-ADDR < FILL-START
              MOVE 0 TO MEM-RESULT
              EXIT PARAGRAPH
           END-IF.
           IF MEM-ADDR >= CHAIN-UNTIL
              MOVE MEM-ADDR TO EF-X
              PERFORM ENSURE-FILLED
           END-IF.
           COMPUTE MEM-IDX = MEM-ADDR + 1.
           MOVE CHAIN-VAL(MEM-IDX) TO MEM-RESULT.
           EXIT PARAGRAPH.
      *> ==================== ENSURE-FILLED ====================
      *> Fills chain[.. block_end) with rolling p1/p2.  The vm.c tail cases
      *> (i == tail_end, i == tail_end+1) read mem(i-1)/mem(i-2); those cells
      *> are exactly the values this loop already produced (p1/p2), so the
      *> recursion collapses to an overlay shadow check (mem_get returns the
      *> overlay value when one exists).  No COBOL paragraph recursion.
       ENSURE-FILLED.
DIVIDE EF-X BY 243 GIVING EF-Q
            COMPUTE EF-BLOCK-END = (EF-Q + 1) * 243.
            DIVIDE FILL-START BY 243 GIVING EF-Q
            COMPUTE EF-TAIL-END = (EF-Q + 1) * 243.
           IF CHAIN-UNTIL = FILL-START
              MOVE FILL-START TO EF-I
      *>       p1 = overlay(fill_start-1) or 0 ; p2 = overlay(fill_start-2) or 0
              COMPUTE EF-IDX = FILL-START
              IF OV-PRESENT(EF-IDX) = 'Y'
                 MOVE OV-VAL(EF-IDX) TO EF-P1
              ELSE
                 MOVE 0 TO EF-P1
              END-IF
              COMPUTE EF-IDX = FILL-START - 1
              IF EF-IDX >= 1
                 IF OV-PRESENT(EF-IDX) = 'Y'
                    MOVE OV-VAL(EF-IDX) TO EF-P2
                 ELSE
                    MOVE 0 TO EF-P2
                 END-IF
              ELSE
                 MOVE 0 TO EF-P2
              END-IF
           ELSE
              MOVE CHAIN-UNTIL TO EF-I
              COMPUTE EF-IDX = EF-I
              MOVE CHAIN-VAL(EF-IDX) TO EF-P1
              COMPUTE EF-IDX = EF-I - 1
              MOVE CHAIN-VAL(EF-IDX) TO EF-P2
           END-IF.
           PERFORM UNTIL EF-I >= EF-BLOCK-END
              IF EF-I = EF-TAIL-END
                 MOVE EF-P1 TO EF-V1
                 COMPUTE EF-IDX = EF-I
                 IF OV-PRESENT(EF-IDX) = 'Y'
                    MOVE OV-VAL(EF-IDX) TO EF-V1
                 END-IF
                 MOVE EF-P2 TO EF-V2
                 COMPUTE EF-IDX = EF-I - 1
                 IF EF-IDX >= 1
                    IF OV-PRESENT(EF-IDX) = 'Y'
                       MOVE OV-VAL(EF-IDX) TO EF-V2
                    END-IF
                 END-IF
                 MOVE EF-V1 TO CRAZY-A
                 MOVE EF-V2 TO CRAZY-B
                 PERFORM CRAZY
                 MOVE CRAZY-R TO EF-NXT
              ELSE
                 IF EF-I = EF-TAIL-END + 1
                    MOVE EF-P2 TO EF-V2
                    COMPUTE EF-IDX = EF-I - 1
                    IF EF-IDX >= 1
                       IF OV-PRESENT(EF-IDX) = 'Y'
                          MOVE OV-VAL(EF-IDX) TO EF-V2
                       END-IF
                    END-IF
                    MOVE EF-P1 TO CRAZY-A
                    MOVE EF-V2 TO CRAZY-B
                    PERFORM CRAZY
                    MOVE CRAZY-R TO EF-NXT
                 ELSE
                    MOVE EF-P1 TO CRAZY-A
                    MOVE EF-P2 TO CRAZY-B
                    PERFORM CRAZY
                    MOVE CRAZY-R TO EF-NXT
                 END-IF
              END-IF
              COMPUTE EF-IDX = EF-I + 1
              MOVE EF-NXT TO CHAIN-VAL(EF-IDX)
              MOVE EF-P1 TO EF-P2
              MOVE EF-NXT TO EF-P1
              ADD 1 TO EF-I
           END-PERFORM.
           MOVE EF-BLOCK-END TO CHAIN-UNTIL.
           EXIT PARAGRAPH.
      *> ==================== CRAZY ====================
       CRAZY.
           COMPUTE CRAZY-IDX =
                FUNCTION MOD(CRAZY-A, 243) * 243
              + FUNCTION MOD(CRAZY-B, 243) + 1.
MOVE C5(CRAZY-IDX) TO CRAZY-LOW.
            DIVIDE CRAZY-A BY 243 GIVING CRAZY-HA
            DIVIDE CRAZY-B BY 243 GIVING CRAZY-HB
            COMPUTE CRAZY-IDX =
                 CRAZY-HA * 243 + CRAZY-HB + 1.
            COMPUTE CRAZY-R = CRAZY-LOW + 243 * C5(CRAZY-IDX).
           EXIT PARAGRAPH.
      *> ==================== RUN ====================
       RUN-VM.
           PERFORM UNTIL HALTED = 'Y' OR STEPS >= MAX-STEPS
              ADD 1 TO STEPS
MOVE C-REG TO MEM-ADDR
               PERFORM MEM-GET
               MOVE MEM-RESULT TO RUN-INS
               IF RUN-INS < 33 OR RUN-INS > 126
                 MOVE 'Y' TO HALTED
                 MOVE 2 TO HALT-CODE
                 EXIT PERFORM
              END-IF
              COMPUTE RUN-V =
                 FUNCTION MOD(RUN-INS + C-REG, 94)
              EVALUATE RUN-V
                 WHEN 4
                    MOVE D-REG TO MEM-ADDR
                    PERFORM MEM-GET
                    MOVE MEM-RESULT TO C-REG
                 WHEN 5
                    IF OUT-LEN < OUT-CAP
                       COMPUTE RUN-BYTE =
                          FUNCTION MOD(A-REG, 256) + 1
                       ADD 1 TO OUT-LEN
                       MOVE FUNCTION CHAR(RUN-BYTE)
                          TO OUT-BUF(OUT-LEN:1)
                    END-IF
                 WHEN 23
                    IF INPUT-POS < IN-LEN
                       COMPUTE WS-K = INPUT-POS + 1
                       COMPUTE A-REG =
                          FUNCTION ORD(IN-BUF(WS-K:1)) - 1
                       ADD 1 TO INPUT-POS
                    ELSE
                       MOVE 'Y' TO HALTED
                       MOVE 3 TO HALT-CODE
                       EXIT PERFORM
                    END-IF
                 WHEN 39
                    MOVE D-REG TO MEM-ADDR
                    PERFORM MEM-GET
                    MOVE MEM-RESULT TO RUN-B
DIVIDE RUN-B BY 3 GIVING RUN-Q
                     COMPUTE RUN-R = POW9
                        * FUNCTION MOD(RUN-B, 3) + RUN-Q
                    MOVE D-REG TO MEM-ADDR
                    MOVE RUN-R TO MEM-RESULT
                    PERFORM MEM-SET-VALUE
                    MOVE RUN-R TO A-REG
                 WHEN 40
                    MOVE D-REG TO MEM-ADDR
                    PERFORM MEM-GET
                    MOVE MEM-RESULT TO D-REG
                 WHEN 62
                    MOVE D-REG TO MEM-ADDR
                    PERFORM MEM-GET
                    MOVE MEM-RESULT TO RUN-B
                    MOVE A-REG TO CRAZY-A
                    MOVE RUN-B TO CRAZY-B
                    PERFORM CRAZY
                    MOVE CRAZY-R TO RUN-R
                    MOVE D-REG TO MEM-ADDR
                    MOVE RUN-R TO MEM-RESULT
                    PERFORM MEM-SET-VALUE
                    MOVE RUN-R TO A-REG
                 WHEN 81
                    MOVE 'Y' TO HALTED
                    MOVE 1 TO HALT-CODE
                    EXIT PERFORM
              END-EVALUATE
              IF HALTED = 'Y'
                 EXIT PERFORM
              END-IF
      *>       encryption of the current cell
              MOVE C-REG TO MEM-ADDR
              PERFORM MEM-GET
              IF MEM-RESULT >= 33 AND MEM-RESULT <= 126
                 COMPUTE RUN-BYTE = MEM-RESULT - 32
                 COMPUTE RUN-BYTE =
                    FUNCTION ORD(ENC-STR(RUN-BYTE:1)) - 1
                 MOVE C-REG TO MEM-ADDR
                 MOVE RUN-BYTE TO MEM-RESULT
                 PERFORM MEM-SET-VALUE
              END-IF
              IF C-REG = LAST-POS
                 MOVE 0 TO C-REG
              ELSE
                 ADD 1 TO C-REG
              END-IF
              IF D-REG = LAST-POS
                 MOVE 0 TO D-REG
              ELSE
                 ADD 1 TO D-REG
              END-IF
           END-PERFORM.
           IF HALTED = 'N'
              MOVE 4 TO HALT-CODE
           END-IF.
           EXIT PARAGRAPH.
      *> ==================== MEM-SET-VALUE ====================
      *> writes overlay(MEM-ADDR) = MEM-RESULT
       MEM-SET-VALUE.
           COMPUTE MEM-IDX = MEM-ADDR + 1.
           MOVE 'Y' TO OV-PRESENT(MEM-IDX).
           MOVE MEM-RESULT TO OV-VAL(MEM-IDX).
           EXIT PARAGRAPH.
      *> ==================== EMIT OUTPUT ====================
       EMIT-OUTPUT.
           IF OUT-LEN > 0
              PERFORM VARYING WS-K FROM 1 BY 1 UNTIL WS-K > OUT-LEN
                 COMPUTE WS-N =
                    FUNCTION ORD(OUT-BUF(WS-K:1)) - 1
                 CALL "cobputc" USING BY VALUE WS-N END-CALL
              END-PERFORM
              CALL "cobputc" USING BY VALUE 10 END-CALL
           END-IF.
           CALL "cobflush" END-CALL.
           EXIT PARAGRAPH.
      *> ==================== HALT-NAME ====================
       HALT-NAME.
           EVALUATE HALT-CODE
              WHEN 1 MOVE "VInstruction" TO J-TOK
              WHEN 2 MOVE "InvalidCell"  TO J-TOK
              WHEN 3 MOVE "Eof"          TO J-TOK
              WHEN 4 MOVE "StepsExhausted" TO J-TOK
              WHEN 5 MOVE "RestoredHalted" TO J-TOK
              WHEN OTHER MOVE "StepsExhausted" TO J-TOK
           END-EVALUATE.
           COMPUTE JKEY-LEN =
              FUNCTION LENGTH(FUNCTION TRIM(J-TOK)).
           EXIT PARAGRAPH.
      *> ==================== JSON REPORT ====================
       EMIT-JSON-REPORT.
           MOVE 1 TO JPTR.
           STRING '{"final":{"a":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE A-REG TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"c":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE C-REG TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"d":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE D-REG TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  '},"halt_reason":"' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           PERFORM HALT-NAME
           STRING J-TOK(1:JKEY-LEN) DELIMITED BY SIZE
                  '","output_len":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE OUT-LEN TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"status":"' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           IF HALT-CODE = 4
              STRING 'TIMEOUT' DELIMITED BY SIZE
                 INTO JS-BUF WITH POINTER JPTR END-STRING
           ELSE
              STRING 'HALTED' DELIMITED BY SIZE
                 INTO JS-BUF WITH POINTER JPTR END-STRING
           END-IF
           STRING '","steps":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE STEPS TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  '}' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           COMPUTE WS-TOK-LEN = JPTR - 1
           CALL "cobwerr" USING
                BY REFERENCE JS-BUF
                BY VALUE WS-TOK-LEN
                RETURNING WS-GETC
           END-CALL.
           CALL "cobpterr" USING BY VALUE 10 END-CALL.
           EXIT PARAGRAPH.
      *> ==================== PLAIN REPORT ====================
       EMIT-PLAIN-REPORT.
           MOVE 1 TO JPTR.
           STRING 'steps: ' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE STEPS TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ' | status: ' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           IF HALT-CODE = 4
              STRING 'TIMEOUT' DELIMITED BY SIZE
                 INTO JS-BUF WITH POINTER JPTR END-STRING
           ELSE
              STRING 'HALTED' DELIMITED BY SIZE
                 INTO JS-BUF WITH POINTER JPTR END-STRING
           END-IF
           COMPUTE WS-TOK-LEN = JPTR - 1
           CALL "cobwerr" USING
                BY REFERENCE JS-BUF
                BY VALUE WS-TOK-LEN
                RETURNING WS-GETC
           END-CALL.
           CALL "cobpterr" USING BY VALUE 10 END-CALL.
           EXIT PARAGRAPH.
      *> ==================== WRITE SNAPSHOT ====================
      *> serde_json compact, field order:
      *> a,c,d,halted,steps,input_pos,output,fill_start,chain_until,
      *> chain([0,chain_until)), overlay(sorted by address)
WRITE-SNAPSHOT.
            MOVE 1 TO JPTR.
            STRING '{"a":' DELIMITED BY SIZE
                   INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE A-REG TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"c":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE C-REG TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"d":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE D-REG TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"halted":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           IF HALTED = 'Y'
              STRING 'true' DELIMITED BY SIZE
                 INTO JS-BUF WITH POINTER JPTR END-STRING
           ELSE
              STRING 'false' DELIMITED BY SIZE
                 INTO JS-BUF WITH POINTER JPTR END-STRING
           END-IF
           STRING ',"steps":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE STEPS TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"input_pos":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE INPUT-POS TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"output":[' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           IF OUT-LEN > 0
              PERFORM VARYING WS-K FROM 1 BY 1 UNTIL WS-K > OUT-LEN
                 COMPUTE WS-N =
                    FUNCTION ORD(OUT-BUF(WS-K:1)) - 1
                 MOVE WS-N TO NUM-IN
                 PERFORM NUM-TO-STR
                 IF WS-K > 1
                    STRING ',' DELIMITED BY SIZE
                       INTO JS-BUF WITH POINTER JPTR END-STRING
                 END-IF
                 STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                    INTO JS-BUF WITH POINTER JPTR END-STRING
              END-PERFORM
           END-IF
           STRING '],"fill_start":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE FILL-START TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"chain_until":' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE CHAIN-UNTIL TO NUM-IN
           PERFORM NUM-TO-STR
           STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                  ',"chain":[' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           IF CHAIN-UNTIL > 0
              PERFORM VARYING WS-K FROM 1 BY 1
                 UNTIL WS-K > CHAIN-UNTIL
                 MOVE CHAIN-VAL(WS-K) TO NUM-IN
                 PERFORM NUM-TO-STR
                 IF WS-K > 1
                    STRING ',' DELIMITED BY SIZE
                       INTO JS-BUF WITH POINTER JPTR END-STRING
                 END-IF
                 STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                    INTO JS-BUF WITH POINTER JPTR END-STRING
              END-PERFORM
           END-IF
           STRING '],"overlay":[' DELIMITED BY SIZE
                  INTO JS-BUF WITH POINTER JPTR END-STRING
           MOVE 'Y' TO WS-FIRST.
           PERFORM VARYING WS-K FROM 0 BY 1
              UNTIL WS-K >= MEM-SIZE
              COMPUTE MEM-IDX = WS-K + 1
              IF OV-PRESENT(MEM-IDX) = 'Y'
                 IF WS-FIRST = 'Y'
                    MOVE 'N' TO WS-FIRST
                 ELSE
                    STRING ',' DELIMITED BY SIZE
                       INTO JS-BUF WITH POINTER JPTR END-STRING
                 END-IF
                 STRING '[' DELIMITED BY SIZE
                    INTO JS-BUF WITH POINTER JPTR END-STRING
                 MOVE WS-K TO NUM-IN
                 PERFORM NUM-TO-STR
                 STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                    ',' DELIMITED BY SIZE
                    INTO JS-BUF WITH POINTER JPTR END-STRING
                 MOVE OV-VAL(MEM-IDX) TO NUM-IN
                 PERFORM NUM-TO-STR
                 STRING NUM-OUT(1:NUM-LEN) DELIMITED BY SIZE
                    ']' DELIMITED BY SIZE
                    INTO JS-BUF WITH POINTER JPTR END-STRING
              END-IF
END-PERFORM
STRING ']}' DELIMITED BY SIZE
                   INTO JS-BUF WITH POINTER JPTR END-STRING
            COMPUTE WS-TOK-LEN = JPTR - 1.
           COMPUTE WS-N =
              FUNCTION LENGTH(FUNCTION TRIM(SNAP-FILE)).
           CALL "cobfsave" USING
                BY REFERENCE SNAP-FILE
                BY VALUE WS-N
                BY REFERENCE JS-BUF
                BY VALUE WS-TOK-LEN
                RETURNING WS-GETC
           END-CALL.
           EXIT PARAGRAPH.
      *> ==================== NUM-TO-STR ====================
       NUM-TO-STR.
           IF NUM-IN = 0
              MOVE "0" TO NUM-OUT
              MOVE 1 TO NUM-LEN
              EXIT PARAGRAPH
           END-IF.
           MOVE NUM-IN TO NUM-TMP.
           MOVE 0 TO NUM-REV-LEN.
           MOVE SPACES TO NUM-REV.
PERFORM UNTIL NUM-TMP = 0
               DIVIDE NUM-TMP BY 10 GIVING NUM-NEW
                  REMAINDER NUM-REM
               MOVE NUM-NEW TO NUM-TMP
               ADD 1 TO NUM-REV-LEN
               COMPUTE NUM-K = NUM-REM + 49
               MOVE FUNCTION CHAR(NUM-K) TO
                  NUM-REV(NUM-REV-LEN:1)
            END-PERFORM.
            MOVE SPACES TO NUM-OUT.
            PERFORM VARYING NUM-K FROM 1 BY 1
               UNTIL NUM-K > NUM-REV-LEN
               COMPUTE WS-N = NUM-REV-LEN - NUM-K + 1
               MOVE NUM-REV(WS-N:1) TO NUM-OUT(NUM-K:1)
            END-PERFORM.
           MOVE NUM-REV-LEN TO NUM-LEN.
           EXIT PARAGRAPH.
      *> ==================== READ RESUME ====================
READ-RESUME.
            MOVE RESUME-FILE TO ARG-TRIM.
            COMPUTE WS-TOK-LEN =
               FUNCTION LENGTH(FUNCTION TRIM(RESUME-FILE)).
            CALL "cobfread" USING
                 BY REFERENCE RESUME-FILE
                 BY VALUE WS-TOK-LEN
                 BY REFERENCE JS-BUF
                 BY VALUE 4000000
                 RETURNING WS-GETC
            END-CALL.
            IF WS-GETC < 0
               MOVE 2 TO RETURN-CODE
               DISPLAY "error: cannot open snapshot "
                  FUNCTION TRIM(RESUME-FILE) UPON STDERR
               STOP RUN
            END-IF.
            MOVE WS-GETC TO JS-LEN.
            PERFORM PARSE-SNAPSHOT.
            EXIT PARAGRAPH.
      *> ==================== PARSE SNAPSHOT ====================
      *> lenient sequential parser for the snapshot JSON schema:
      *> {"a":..,"c":..,"d":..,"halted":..,"steps":..,"input_pos":..,
      *>  "output":[...],"fill_start":..,"chain_until":..,
      *>  "chain":[...],"overlay":[[a,v],...]}  (compact, may have spaces)
PARSE-SNAPSHOT.
            MOVE 1 TO JPTR.
            PERFORM SKIP-WS.
            IF JCH NOT = '{'
               MOVE 2 TO RETURN-CODE
               DISPLAY "error: malformed snapshot" UPON STDERR
               STOP RUN
            END-IF.
            ADD 1 TO JPTR.
            PERFORM UNTIL JPTR > JS-LEN
               PERFORM SKIP-WS
               IF JCH = '}'
                  ADD 1 TO JPTR
                  EXIT PERFORM
               END-IF
       *>       parse key
               MOVE SPACES TO JKEY
               MOVE 0 TO JKEY-LEN
               IF JCH = '"'
                  ADD 1 TO JPTR
                  PERFORM UNTIL JPTR > JS-LEN
                     MOVE JS-BUF(JPTR:1) TO JCH
                     IF JCH = '"'
                        ADD 1 TO JPTR
                        EXIT PERFORM
                     END-IF
                     IF JKEY-LEN < 32
                        ADD 1 TO JKEY-LEN
                        MOVE JCH TO JKEY(JKEY-LEN:1)
                     END-IF
                     ADD 1 TO JPTR
                  END-PERFORM
               END-IF
               PERFORM SKIP-WS
               IF JCH = ':'
                  ADD 1 TO JPTR
               END-IF
               PERFORM SKIP-WS
       *>       dispatch on key
               EVALUATE JKEY
                  WHEN "a"
                     PERFORM PARSE-NUM
                     MOVE JNUM TO A-REG
                  WHEN "c"
                     PERFORM PARSE-NUM
                     MOVE JNUM TO C-REG
                  WHEN "d"
                     PERFORM PARSE-NUM
                     MOVE JNUM TO D-REG
                  WHEN "halted"
                     PERFORM PARSE-BOOL
                     IF JBOOL = 'Y'
                        MOVE 'Y' TO HALTED
                        MOVE 5 TO HALT-CODE
                     ELSE
                        MOVE 'N' TO HALTED
                        MOVE 0 TO HALT-CODE
                     END-IF
                  WHEN "steps"
                     PERFORM PARSE-NUM
                     MOVE JNUM TO STEPS
                  WHEN "input_pos"
                     PERFORM PARSE-NUM
                     MOVE JNUM TO INPUT-POS
                  WHEN "output"
                     PERFORM PARSE-NUM-ARRAY
                     MOVE WS-K TO OUT-LEN
                     PERFORM VARYING J-I FROM 1 BY 1
                        UNTIL J-I > OUT-LEN OR J-I > 65536
                        MOVE NUM-ARR(J-I) TO WS-N
                        COMPUTE WS-N = WS-N + 1
                        MOVE FUNCTION CHAR(WS-N)
                           TO OUT-BUF(J-I:1)
                     END-PERFORM
                  WHEN "fill_start"
                     PERFORM PARSE-NUM
                     MOVE JNUM TO FILL-START
                  WHEN "chain_until"
                     PERFORM PARSE-NUM
                     MOVE JNUM TO CHAIN-UNTIL
                  WHEN "chain"
                     PERFORM PARSE-NUM-ARRAY
                     PERFORM VARYING J-I FROM 1 BY 1
                        UNTIL J-I > WS-K OR J-I > MEM-SIZE
                        MOVE NUM-ARR(J-I) TO CHAIN-VAL(J-I)
                     END-PERFORM
                  WHEN "overlay"
                     PERFORM PARSE-OVERLAY
                  WHEN OTHER
                     CONTINUE
               END-EVALUATE
               PERFORM SKIP-WS
               IF JCH = ','
                  ADD 1 TO JPTR
               END-IF
            END-PERFORM.
            EXIT PARAGRAPH.
      *> ---------------- SKIP-WS ----------------
       SKIP-WS.
           PERFORM UNTIL JPTR > JS-LEN
              MOVE JS-BUF(JPTR:1) TO JCH
              IF JCH = ' ' OR JCH = X'09'
                    OR JCH = X'0A' OR JCH = X'0D'
                 ADD 1 TO JPTR
              ELSE
                 EXIT PERFORM
              END-IF
           END-PERFORM.
           IF JPTR > JS-LEN
              MOVE SPACES TO JCH
           END-IF.
           EXIT PARAGRAPH.
      *> ---------------- PARSE-NUM ----------------
       PARSE-NUM.
           MOVE 0 TO JNUM.
           PERFORM SKIP-WS.
           PERFORM UNTIL JPTR > JS-LEN
              MOVE JS-BUF(JPTR:1) TO JCH
              IF JCH >= '0' AND JCH <= '9'
                 COMPUTE JNUM = JNUM * 10
                    + FUNCTION ORD(JCH) - 49
                 ADD 1 TO JPTR
              ELSE
                 EXIT PERFORM
              END-IF
           END-PERFORM.
           EXIT PARAGRAPH.
      *> ---------------- PARSE-BOOL ----------------
       PARSE-BOOL.
           MOVE 'N' TO JBOOL.
           MOVE SPACES TO J-TOK.
           PERFORM VARYING J-I FROM 1 BY 1 UNTIL J-I > 5
              IF JPTR <= JS-LEN
                 MOVE JS-BUF(JPTR:1) TO J-TOK(J-I:1)
                 ADD 1 TO JPTR
              END-IF
           END-PERFORM.
           IF FUNCTION TRIM(J-TOK) = "true"
              MOVE 'Y' TO JBOOL
           ELSE
              MOVE 'N' TO JBOOL
           END-IF.
           EXIT PARAGRAPH.
      *> ---------------- PARSE-NUM-ARRAY ----------------
      *> parses [n,n,...]; fills NUM-ARR(1..WS-K); leaves JPTR after ']'
       PARSE-NUM-ARRAY.
           MOVE 0 TO WS-K.
           PERFORM SKIP-WS.
           IF JCH = '['
              ADD 1 TO JPTR
           END-IF.
           PERFORM UNTIL JPTR > JS-LEN
              PERFORM SKIP-WS
              IF JCH = ']'
                 ADD 1 TO JPTR
                 EXIT PERFORM
              END-IF
              PERFORM PARSE-NUM
              IF WS-K < 59049
                 ADD 1 TO WS-K
                 MOVE JNUM TO NUM-ARR(WS-K)
              END-IF
              PERFORM SKIP-WS
              IF JCH = ','
                 ADD 1 TO JPTR
              END-IF
           END-PERFORM.
           EXIT PARAGRAPH.
      *> ---------------- PARSE-OVERLAY ----------------
      *> parses [[a,v],...]; leaves JPTR after ']'
       PARSE-OVERLAY.
           PERFORM SKIP-WS.
           IF JCH = '['
              ADD 1 TO JPTR
           END-IF.
           PERFORM UNTIL JPTR > JS-LEN
              PERFORM SKIP-WS
              IF JCH = ']'
                 ADD 1 TO JPTR
                 EXIT PERFORM
              END-IF
              IF JCH = '['
                 ADD 1 TO JPTR
              END-IF
              PERFORM PARSE-NUM
              MOVE JNUM TO EF-X
              PERFORM SKIP-WS
              IF JCH = ','
                 ADD 1 TO JPTR
              END-IF
              PERFORM PARSE-NUM
              MOVE JNUM TO EF-NXT
              PERFORM SKIP-WS
              IF JCH = ']'
                 ADD 1 TO JPTR
              END-IF
              IF EF-X < MEM-SIZE
                 COMPUTE MEM-IDX = EF-X + 1
                 MOVE 'Y' TO OV-PRESENT(MEM-IDX)
                 MOVE EF-NXT TO OV-VAL(MEM-IDX)
              END-IF
              PERFORM SKIP-WS
              IF JCH = ','
                 ADD 1 TO JPTR
              END-IF
           END-PERFORM.
           EXIT PARAGRAPH.
      *> ==================== USAGE ====================
       USAGE-DIE.
           MOVE 1 TO RETURN-CODE.
           DISPLAY "error: usage: cobolge <program.mal> [max_steps] "
              "[--snapshot-out f] [--resume f] [--json] < input"
              UPON STDERR.
           STOP RUN.