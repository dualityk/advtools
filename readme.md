
# Note: stage1.pdf is outdated!

    Stage 1 serial boot loader:

    Press Ctrl-C at LOAD SYSTEM prompt

    *DFF00

    FF00: 3E 80 D3 51 D3 51 3E 40 D3 51 3E 7F

    FF0C: D3 58 3E 4E D3 51 3E 37 D3 51 06 CB

    FF18: 0E 50 21 29 FF DB 50 DB 51 E6 02 28

    FF24: FA ED A2 20 F6

    (press return)

    *JFF00

    CB at FF17 = number of bytes to read (secondary loader size)

    FF at FF22 = high byte of origin

ian 2017

updated frank 2022
