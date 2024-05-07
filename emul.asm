format ELF64 executable 3

; System call numbers
SYS_read = 0
SYS_write = 1
SYS_open = 2
SYS_fstat = 5
SYS_mmap = 9
SYS_exit = 60

; Macros for system calls
macro read fd, size {
    mov rdi, fd               ; File descriptor
    mov rsi, rax              ; Base address of the allocated buffer
    mov rdx, size             ; Size to read (total file size)
    mov rax, SYS_read         ; System call number for read (SYS_read)
    syscall                   ; Read into the allocated buffer
}

macro open_file path, flags, mode, result {
    mov rdi, path
    mov rsi, flags
    mov rdx, mode
    mov rax, SYS_open
    syscall
    mov result, rax           ; Store the result (file descriptor or error)
}

macro fstat fd {
    mov rdi, fd
    mov rax, SYS_fstat
    lea rsi, [statbuf]
    syscall
}

macro mmap_allocate size, result {
    push r8
    push r9
    mov rax, SYS_mmap
    xor rdi, rdi              ; NULL (let the system choose the address)
    mov rsi, size             ; Size to allocate
    mov rdx, 0x3              ; PROT_READ | PROT_WRITE
    mov r10, 0x22             ; MAP_PRIVATE | MAP_ANONYMOUS
    xor r8, r8                ; File descriptor (for anonymous mapping)
    xor r9, r9                ; Offset
    syscall
    pop r9
    pop r8
    mov result, rax           ; Store the result (pointer or error)
}

macro write fd, buf, count {
    mov rdi, fd
    mov rsi, buf
    mov rdx, count
    mov rax, SYS_write
    syscall
}

macro exit exitCode {
    mov rdi, exitCode
    mov rax, SYS_exit
    syscall
}

macro print statement {
    push rdx
    push rsi
    push rdi
    push rax
    mov rdx, statement
    len rdx
    write 1, rdx, rax
    pop rax
    pop rdi
    pop rsi
    pop rdx
}

macro len buf {
    push rsi
    mov rsi, buf
    call _len
    pop rsi
}

macro read_file filename {
    mov rsi, filename
    call _read_file
}

macro read_arg num {
    mov rsi, [rsp + 8 * (num + 1)]  ; nth argument
    call _read_arg
}

macro debug reg, len {
    push rax
    push rdi
    push rbx
    push rcx
    mov rax, reg
    call _debug
    print bin_str + 64 - len
    pop rcx
    pop rbx
    pop rdi
    pop rax
}

opcode_mov = 34

; Entry point
segment readable executable
entry main

main:
    read_arg 1                ; Read the first command-line argument (file name)
    read_file rsi             ; Open and read the specified file
    add rdx, 2
.read_next:
    mov rax, opcode_mov
    xor rbx, rbx
    sub rdx, 2
    jz .end_program
    mov bl, byte [rsi]
    mov al, bl
    shr al, 2
    cmp al, opcode_mov        ; Compare first byte with the expected opcode
    je .opcode_mov            ; Jump to `.opcode_mov` if matched
    print unrecognized
    exit 1
.dw_read:
    mov cl, bl
    and cl, 1
    mov bl, byte [rsi + 1]
    mov al, bl
    and al, 56
    shr al, 2
    and bl, 7
    shl bl, 1
    cmp cl, 1
    jne .normal_table
    jmp .wide_table

.wide_table:
    add rax, ax_reg_str
    add rbx, ax_reg_str
    jmp .show
.normal_table:
    add rax, al_reg_str
    add rbx, al_reg_str
    jmp .show

.show:
    push rdx
    push rsi
    push rax
    write 1, rbx, 2
    pop rax
    print sep
    write 1, rax, 2
    print newline
    pop rsi
    pop rdx
    add rsi, 2
    jmp .read_next

.end_program:
    print normal_exit
    exit 0

.opcode_mov:
    print mov_str
    jmp .dw_read

; Read the contents of a file
_read_file:
    mov rbx, rsi              ; Store the filename pointer in `rbx`
    open_file rsi, 0, 0, r8   ; Open the file in read-only mode
    test r8, r8               ; Check if the file was opened successfully
    js .file_does_not_exist   ; Jump to error handling if it was not opened

    fstat r8                  ; Retrieve the file metadata (including size)
    mov r9, qword [statbuf + 48] ; Retrieve the file size

    mmap_allocate r9, rax     ; Allocate memory dynamically using mmap
    test rax, rax             ; Check if mmap was successful
    js .allocation_failed     ; Jump to error handling if mmap failed

    read r8, r9               ; Read the content of the file into allocated memory
    ret

.file_does_not_exist:
    print filen
    print rbx
    print does_not_exist
    exit 1

.allocation_failed:
    print allocation_failed_msg
    exit 1

_read_arg:
    test rsi, rsi             ; Check if the argument is NULL (no argument)
    jz .no_argument           ; Jump to error handling if none is given
    ret

.no_argument:
    print error_msg
    exit 1

_len:
    xor rax, rax
    not rax                   ; rax = -1
.next_char:
    inc rax
    cmp byte [rsi + rax], 0
    jne .next_char
    ret

_debug:
    mov rdi, bin_str            ; Pointer to the first byte of bin_str
    mov rcx, 64                 ; Number of bits to convert
    mov rsi, rdi                ; Reset pointer to the start of bin_str
    add rsi, rcx
    dec rsi
.convert_loop:
    mov rbx, rax                ; Copy the value of rax to rbx for shifting
    shr rbx, cl                 ; Shift right by the current bit index
    and rbx, 1                  ; Extract the rightmost bit
    add rbx, '0'                ; Convert to ASCII ('0' or '1')
    mov [rsi], bl               ; Store ASCII character in the binary string
    dec rsi
    inc cl                      ; Decrement bit counter
    cmp cl, 64
    jne .convert_loop           ; Repeat until all bits are converted
    ret

segment readable writable
  error_msg db 'No argument provided, please input a filename', 10, 0
  db_str db 10, 'Got here', 10, 0
  newline db 10, 0
  bin_str db '0000000000000000000000000000000000000000000000000000000000000000', 10, 0 ; 64-bit binary string
  filen db 'File "', 0
  does_not_exist db '" does not exist', 10, 0
  allocation_failed_msg db 'Memory allocation failed', 10, 0
  normal_exit db 'Program exited normally', 10, 0
  unrecognized db 'Unrecognized opcode', 10, 0
  mov_str db 'mov ', 0
  sep db ', ', 0
  al_reg_str db 'al'
  cl_reg_str db 'cl'
  dl_reg_str db 'dl'
  bl_reg_str db 'bl'
  ah_reg_str db 'ah'
  ch_reg_str db 'ch'
  dh_reg_str db 'dh'
  bh_reg_str db 'bh'
  ax_reg_str db 'ax'
  cx_reg_str db 'cx'
  dx_reg_str db 'dx'
  bx_reg_str db 'bx'
  sp_reg_str db 'sp'
  bp_reg_str db 'bp'
  si_reg_str db 'si'
  di_reg_str db 'di'
  statbuf rb 144              ; Buffer to hold the stat structure
