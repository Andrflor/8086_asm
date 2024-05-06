format ELF64 executable 3

; System call numbers
SYS_read = 0
SYS_write = 1
SYS_open = 2
SYS_fstat = 5
SYS_exit = 60
SYS_mmap = 9

; Macros for system calls
macro read fd, size {
    ; Read the file contents into the dynamically allocated buffer
    mov rdi, fd               ; File descriptor
    mov rsi, rax              ; Base address of the allocated buffer
    mov rdx, size             ; Size to read (total file size)
    mov rax, SYS_read         ; System call number for read (SYS_read)
    syscall                   ; Read into the allocated buffer
}

macro open_file path, flags, mode, result {
    ; Open a file with the given path, flags, and mode, storing the result in `result`
    mov rdi, path
    mov rsi, flags
    mov rdx, mode
    mov rax, SYS_open
    syscall
    mov result, rax           ; Store the result (file descriptor or error)
}

macro fstat fd {
    ; Retrieve file metadata and store it in the `statbuf`
    mov rdi, fd
    mov rax, SYS_fstat
    lea rsi, [statbuf]
    syscall
}

macro mmap_allocate size, result {
    ; Allocate memory dynamically using `mmap`, storing the resulting pointer in `result`
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
    ; Write `count` bytes from `buf` to the specified `fd`
    mov rdx, count
    mov rsi, buf
    mov rdi, fd
    mov rax, SYS_write
    syscall
}

macro exit exitCode {
    ; Exit with a given exit code
    mov rdi, exitCode
    mov rax, SYS_exit
    syscall
}

macro print statement {
    ; Print a null-terminated statement string to stdout
    push rdx
    push rsi
    push rdi
    push rax
    len statement
    write 1, statement, rax
    pop rax
    pop rdi
    pop rsi
    pop rdx
}

macro len buf {
    ; Get the length of a null-terminated string into `rax`
    push rsi
    mov rsi, buf
    call _len
    pop rsi
}

macro read_file filename {
    ; Read and print the contents of the specified file
    mov rsi, filename
    call _read_file
}

macro read_arg num {
    ; Get the address of the nth command-line argument
    mov rsi, [rsp + 8 * (num + 1)]  ; nth argument
    call _read_arg
}

; Entry point
segment readable executable
entry main

main:
    read_arg 1                ; Read the first command-line argument (file name)
    read_file rsi             ; Open and read the specified file
    ; Write the buffer contents to stdout
    write 1, rsi, rdx         ; fd = 1 (stdout), buffer = rsi, count = rdx
    ; TODO: process the file to parse the cpu instruction
    exit 0                    ; Exit successfully

; Read the contents of a file
_read_file:
    mov rbx, rsi              ; Store the filename pointer in `rbx`
    open_file rsi, 0, 0, r8   ; Open the file in read-only mode
    test r8, r8               ; Check if the file was opened successfully
    js .file_does_not_exist   ; Jump to error handling if it was not opened

    fstat r8                  ; Retrieve the file metadata (including size)
    ; Retrieve the file size (st_size field at offset 48 in the stat structure)
    mov r9, qword [statbuf + 48]

    ; Allocate memory using mmap
    mmap_allocate r9, rax     ; Size to allocate
    test rax, rax             ; Check if mmap was successful
    js .allocation_failed     ; Jump to error handling if mmap failed

    ; Read the content of the file into dynamically allocated memory
    read r8, rax
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
    ; Verify that the argument pointer is not NULL
    test rsi, rsi             ; Check if it is NULL (no argument provided)
    jz .no_argument           ; Jump to error handling if no argument was given
    ret

.no_argument:
    print error_msg
    exit 1

_len:
    ; Calculate the length of a null-terminated string into `rax`
    xor rax, rax
    not rax                   ; rax = -1
.next_char:
    inc rax
    cmp byte [rsi + rax], 0
    jne .next_char
    ret

segment readable writable
  error_msg db 'No argument provided, please input a filename', 10, 0
  debug db 10, 'Got here', 10, 0
  filen db 'File "', 0
  does_not_exist db '" does not exist', 10, 0
  allocation_failed_msg db 'Memory allocation failed', 10, 0
  statbuf rb 144                 ; Buffer to hold the stat structure
