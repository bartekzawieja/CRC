section .bss align=8
    lookup resq 256                   ; look-up table
    buffer resb 4096                  ; bufor na bajty z pliku
    fd     resq 1                     ; deskryptor pliku
    size   resq 1                     ; stopień wielomianu
    iter   resq 1                     ; iterator ogólny
    rcx_   resq 1                     ; przechowanie rejestru xor'owanego

section .text
    global _start

; w komenatarzach, jako:
;   "część" (pliku) - rozumie się część pliku braną do bufora o stałej wielkości,
;   "fragment" (pliku) - rozumie się fragment pliku, zgodnie z treścią zadania
;
; program "crc" po odebraniu argumentów i zapełnieniu look-up table wykorzystuje rejestry:
;   rdi - "indeks części" - odliczający bajty względem początku części pliku,
;   rax - "pozostałe w części" - odliczający bajty pozostające w części pliku,
;   rcx - "rejestr xor'owany" - trzymający bajty, które są xor'owane,
;   r9 - "do początku fragmentu" - odliczający bajtach odległość od początku fragmentu,
;   r10 - "bajty we fragmencie" - odliczający bajty pozostające we fragmencie pliku,
;   r11 - jako skok - trzmający w bajtach odległość od następnego fragment,
; pozostałe wykorzystywane rejestry (rsi oraz rdx) występują w krótkich rolach epizodycznych

_start:
; sprawdzenie liczby argumentów
    cmp    qword [rsp], 3             ; program ma 2 argumenty?
    jne    exit_w_error_no_file       ; jeżeli nie, zakończenie z błędem

; przygotowanie odbioru wielomianu
    mov    rsi, [rsp + 24]            ; wskaźnik na wielomian
    xor    rdx, rdx                   ; wielomian = 0
    xor    rcx, rcx                   ; stopień wielomianu, indeks = 0
convert_poly:
; iteracja dla bajtu
    mov    al, [rsi + rcx]            ; kolejny bajt stringa
    test   al, al                     ; koniec stringa?
    jz     done_convert               ; jeżeli tak, przejście dalej
    shl    rdx, 1                     ; left-shift na wielomianie o 1
    sub    al, '0'                    ; ASCII -> binary
    cmp    al, 1                      ; odebrany bajt > 1bit ?
    ja     exit_w_error_no_file       ; jeżeli tak, zakończenie z błędem
    or     rdx, rax                   ; dodanie bitu do wielomianu
    inc    rcx                        ; stopień wielomianu, indeks ++
    jmp    convert_poly               ; kolejna iteracja

done_convert:
; interpretacja wielomianu
    test   rcx, rcx                   ; wielomian stały?
    jz     exit_w_error_no_file       ; jeżeli tak, zakończenie z błędem
    cmp    rcx, 65                    ; stopień wielomianu > 64
    jae    exit_w_error_no_file       ; jeżeli tak, zakończenie z błędem
    mov    [size], rcx                ; stopień wielomianu -> .bss

; przesunięcie wielomianu
    mov    rcx, 64                    ; maksymalna wielkość right-shift
    sub    rcx, qword [size]          ; obliczenie wielkości right-shift
    shl    rdx, cl                    ; left-shift na wielomianie

; przygotowanie look-up table
    xor    rsi, rsi                   ; bajt, duży indeks = 0
init_loop:
; iteracja dla bajtu
    mov    rax, rsi                   ; kolejny bajt look-up table
    shl    rax, 56                    ; left-shift na bajcie
    mov    rdi, 8                     ; bit, mały indeks = 8
process_bit:
; iteracja dla bitu
    shl    rax, 1                     ; left-shift na bajcie o 1
    jnc    skip_xor                   ; carry?
    xor    rax, rdx                   ; jeżeli nie, xor
skip_xor:
    dec    rdi                        ; bit, mały indeks ++
    jnz    process_bit                ; jeżeli są bity, kolejna iteracja
    mov    [lookup + rsi * 8], rax    ; bajt look-up table -> .bss
    inc    rsi                        ; bajt, duży indeks ++
    cmp    rsi, 256                   ; wszystkie bajty ?
    jne    init_loop                  ; jeżeli nie, kolejna iteracja

; otworzenie pliku
    mov    rax, 2                     ; sys_open
    mov    rdi, [rsp + 16]            ; ścieżka do pliku
    xor    rsi, rsi                   ; read_only
    syscall                           ; wywołanie funkcji systemowej
    test   rax, rax                   ; zakończone błędem ?
    js     exit_w_error_no_file       ; jeżeli tak, zakończenie z błędem
    mov    [fd], rax                  ; deskryptor pliku -> .bss

; przygotowanie przejścia pliku
    mov    qword [iter], 0            ; iterator w .bss = 0
    xor    rcx, rcx                   ; rejestr xor'owany = 0
    xor    r10, r10                   ; bajty we fragmencie = 0
take_fixed_chunk:
; odebranie części
    cmp    qword [fd], 0              ; zakończenie programu ?
    je     exit                       ; jeżeli tak, zakończenie bez błędu
    mov    qword [rcx_], rcx          ; rejestr xor'owany -> .bss
    xor    rax, rax                   ; sys_read
    mov    rdi, [fd]                  ; deskryptor pliku
    mov    rsi, buffer                ; buffor części
    mov    rdx, 4096                  ; wielkość bufora
    syscall                           ; wywołanie funkcji systemowej
    cmp    rax, 0                     ; zakończone błędem ?
    jle    exit_w_error               ; jeżeli tak, zakończenie z błędem
    mov    rcx, qword [rcx_]          ; .bss -> rejestr xor'owany
    xor    rdi, rdi                   ; indeks części = 0
    test   r10, r10                   ; pozostałe we fragmencie = 0 ?
    jnz    take_x_mess_bytes          ; jeżeli nie, dobór bajtów

take_2_size_bytes:
; odebranie wielkości fragmentu
    xor    r9, r9                     ; do początku fragmentu = 0
    sub    r9, 2                      ; do początku fragmentu -= 2
    xor    r11, r11                   ; skok do kolejnego fragmentu = 0
    movzx  r10, word [buffer]         ; pozostałe we fragmencie = wielkość fragmentu
    add    r10, 4                     ; pozosytałe we fragmencie += wielkość skoku
    add    rdi, 2                     ; indeks części += 2
    sub    rax, 2                     ; pozostałe w części -= 2
    cmp    r10, 4                     ; wielkość fragmentu = 0 ?
    je     take_4_jump_bytes          ; jeżeli tak, ewaluujemy skok

take_x_mess_bytes:
; przygotowanie doboru bajtów
    cmp    rax, 0                     ; pozostałe w części = 0 ?
    je     take_fixed_chunk           ; jeżeli tak, odbieramy część

; przygotowanie xor
    cmp    qword [iter], 8            ; już 8 bajtów ?
    jb     skip_xor_preparation       ; jeżeli nie, przejście dalej
    mov    rsi, rcx                   ; kopia rejestru xor'owanego
    shr    rsi, 56                    ; left-shift na kopii
    mov    rdx, [lookup + rsi*8]      ; odpowiadająca wartość z look-up table
skip_xor_preparation:

; przygotowanie bajtu
    shl    rcx, 8                     ; left-shift rejestru xor'owanego o 8
    cmp    qword [fd], 0              ; jeszcze bajty w pliku ?
    je     skip_taking_data_byte      ; jeżeli nie, przejście dalej
    mov    cl, byte [buffer + rdi]    ; bajt do rejestru xor'owanego
    inc    rdi                        ; indeks części ++
    dec    r10                        ; wielkość fragmentu --
    dec    r9                         ; do początku fragmentu --
skip_taking_data_byte:

; przeprowadzenie xor
    cmp    qword [iter], 8            ; już 8 bajtów ?
    jb     no_xor                     ; jeżeli nie, przejście dalej
    xor    rcx, rdx                   ; xor rejestru xor'owanego z wartością z look-up table
    jmp    after_xor                  ; pominięcie zwiększenia iteratora w .bss
no_xor:
    inc    qword [iter]               ; iterator w .bss ++
after_xor:
    dec    rax                        ; pozostałe w części --
    cmp    qword [fd], 0              ; koniec bajtów w pliku ?
    je     take_x_mess_bytes          ; jeżeli tak, dobór bajtów
    cmp    r10, 4                     ; pozostałe we fragmencie <= wielkość skoku ?
    ja     take_x_mess_bytes          ; jeżeli nie, dobór bajtów

take_4_jump_bytes:
; przygotowanie odbioru skoku
    cmp    rax, 4                     ; pozostałe w części >= wielkość skoku ?
    jae    correct                    ; jeżeli tak, pomiń korektę

jump_bytes_correction:
; korekta odbioru skoku
    shl    r11d, 8                    ; left-shift skoku o 8
    mov    r11b, byte [buffer + rdi]  ; część skoku = z bufora
    inc    rdi                        ; indeks części ++
    dec    r10                        ; pozostałe we fragmencie --
    dec    r9                         ; do początku fragmentu --
    dec    rax                        ; pozostałe w części --
    jnz    jump_bytes_correction      ; jeżeli część się nie skończyła, kolejna iteracja

    cmp    r10, 0                     ; pozostałe we fragmencie == 0 ?
    je     corrected                  ; jeżeli tak, przejście dalej
                                      ; sys_read
    mov    rdi, [fd]                  ; deskryptor pliku
    mov    rsi, buffer                ; bufor części
    mov    rdx, r10                   ; liczba bajtów
    syscall                           ; wywołanie funkcji systemowej
    test   rax, rax                   ; zakończone błędem ?
    js     exit_w_error               ; jeżeli tak, zakończenie z błędem
    xor    rdi, rdi                   ; indeks części = 0
    jmp    jump_bytes_correction      ; kolejna iteracja

correct:
; odbiór skoku
    movsx  r11, dword [buffer + rdi]  ; skok do kolejnego fragmentu = z bufora
    sub    r10, 4                     ; pozostałe we fragmencie -= 4  
    add    rdi, 4                     ; indeks części += 4
    sub    r9, 4                      ; do początku fragmentu -= 4
    sub    rax, 4                     ; pozostałe w części -= 4

corrected:
; ewaluacja skoku 
    cmp    r11, r9                    ; skok do kolejnego fragmentu == do początku fragmentu ?
    je     last_8_bytes               ; jeżeli tak, dobór 8 pustych bajtów

shift:
; wykonanie skoku
    xor    rsi, rsi                   ; lseek offset = 0
    sub    rsi, rax                   ; lseek offset -= pozostałe w części
    add    rsi, r11                   ; lseek offset += skok
    mov    qword [rcx_], rcx          ; rejestr xor'owany -> .bss
    mov    rax, 8                     ; sys_lseek
    mov    rdi, [fd]                  ; deskryptor pliku
    mov    rdx, 1                     ; whence = względem aktualnego położenia
    syscall                           ; wywołanie funkcji systemowej
    test   rax, rax                   ; zakończone błędem ?
    js     exit_w_error               ; jeżeli tak, zakończenie z błędem
    mov    rcx, qword [rcx_]          ; .bss -> rejestr xor'owany
    jmp    take_fixed_chunk           ; odbiór części

last_8_bytes:
; dobór 8 pustych bajtów
    mov    qword [fd], 0              ; brak bajtów w pliku
    mov    rax, 8                     ; pozostałe w części (puste) = 8
    jmp    take_x_mess_bytes          ; dobór bajtów

exit:
;przygotowanie zakończenia
    xor    rsi, rsi                   ; indeks = 0
convert_loop:
    shl    rcx, 1                     ; left-shift rejestru xor'owanego o 1
    jc     set_one                    ; jeżeli carry, do bufora trafia '1'
    mov    byte [buffer + rsi], '0'   ; bufor[indeks] = '0'
    jmp    store_bit
set_one:
    mov    byte [buffer + rsi], '1'   ; bufor[indeks] = '1'
store_bit:
    inc    rsi                        ; indeks ++
    cmp    rsi, qword [size]          ; zaspis do bufora == stopień wielomianu ?
    jne    convert_loop               ; jeżeli nie, kolejna iteracja

    mov    byte [buffer + rsi], 10    ; bufor[indeks] = znak newline
    inc    rsi                        ; indeks ++

; wypisanie na stdout
    mov    rax, 1                     ; sys_write
    mov    rdi, 1                     ; deskryptor (stdout)
    mov    rdx, rsi                   ; długość stringa ze znakiem newline
    mov    rsi, buffer                ; bufor
    syscall                           ; wywołanie funkcji systemowej
    test   rax, rax                   ; zakończone błędem ?
    js     exit_w_error               ; jeżeli tak, zakończenie z błędem

;zamknięcie pliku
    mov    rax, 3                     ; sys_close
    mov    rdi, [fd]                  ; deskryptor pliku
    syscall                           ; wywołanie funkcji systemowej
    test   rax, rax                   ; zakończone błędem ?
    js     exit_w_error               ; jeżeli tak, zakończenie z błędem

; zakończenie bez błędu
    mov    rax, 60                    ; sys_exit
    xor    rdi, rdi                   ; kod zakończenia = 0
    syscall                           ; wywołanie funkcji systemowej

exit_w_error:
; zakończenie z błędem
    mov    rax, 3                     ; sys_close
    mov    rdi, [fd]                  ; deskryptor pliku
    syscall                           ; wywołanie funkcji systemowej
    test   rax, rax                   ; zakończone błędem ?
    js     exit_w_error               ; jeżeli tak, zakończenie z błędem

exit_w_error_no_file:
; po zamknięciu pliku
    mov    rax, 60                    ; sys_exit
    mov    rdi, 1                     ; kod zakończenia = 1
    syscall                           ; wywołanie funkcji systemowej