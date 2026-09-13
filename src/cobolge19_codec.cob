*> Local positional codec for Malbolge Unshackled 3^19.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. cobolge19-codec.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 OP PIC 99 COMP-5.
       01 POSN PIC 9(12) COMP-5.
       01 R PIC 9(3) COMP-5.
       01 A1 PIC 9(3) COMP-5.
       01 A2 PIC 9(3) COMP-5.
       01 O PIC 9(3) COMP-5.
       01 OUTCHAR PIC X.
       PROCEDURE DIVISION.
           ACCEPT OP
           ACCEPT POSN
           COMPUTE A1 = 94 - FUNCTION MOD((1162261467 - 1) / 6 - 29524, 94)
           COMPUTE A2 = 94 - FUNCTION MOD((1162261467 - 1) / 3 - 59048, 94)
           IF POSN < 387420489
              MOVE 0 TO O
           ELSE IF POSN < 774840978
              COMPUTE O = FUNCTION MOD(A1 - 387420489, 94) + 94
           ELSE
              COMPUTE O = A2 - FUNCTION MOD(774840978, 94) + 94
           END-IF
           COMPUTE R = FUNCTION MOD(OP - POSN - O, 94)
           IF R < 0 COMPUTE R = R + 94 END-IF
           IF R < 33 ADD 94 TO R END-IF
           MOVE FUNCTION CHAR(R) TO OUTCHAR
           DISPLAY "opcode=" OP " position=" POSN " ASCII=" R " char=" OUTCHAR
           GOBACK.
