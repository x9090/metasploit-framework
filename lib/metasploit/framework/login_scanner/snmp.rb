require 'snmp'
require 'metasploit/framework/login_scanner/base'

module Metasploit
  module Framework
    module LoginScanner

      # This is the LoginScanner class for dealing with SNMP.
      # It is responsible for taking a single target, and a list of credentials
      # and attempting them. It then saves the results.
      class SNMP
        include Metasploit::Framework::LoginScanner::Base

        DEFAULT_TIMEOUT      = 2
        DEFAULT_PORT         = 161
        DEFAULT_RETRIES      = 0
        DEFAULT_VERSION      = 'all'
        LIKELY_PORTS         = [ 161, 162 ]
        LIKELY_SERVICE_NAMES = [ 'snmp' ]
        PRIVATE_TYPES        = [ :password ]
        REALM_KEY            = nil

        # The number of retries per community string
        # @return [Fixnum]
        attr_accessor :retries

        # The SNMP version to scan
        # @return [String]
        attr_accessor :version

        validates :retries,
                  presence: true,
                  numericality: {
                    only_integer: true,
                    greater_than_or_equal_to: 0
                  }

        validates :version,
                  presence: true,
                  inclusion: {
                    in: ['1', '2c', 'all']
                  }

        # This method returns an array of versions to scan
        # @return [Array] An array of versions
        def versions
          case version
          when '1'
            [:SNMPv1]
          when '2c'
            [:SNMPv2c]
          when 'all'
            [:SNMPv1, :SNMPv2c]
          end
        end

        # This method attempts a single login with a single credential against the target
        # @param credential [Credential] The credential object to attmpt to login with
        # @return [Metasploit::Framework::LoginScanner::Result] The LoginScanner Result object
        def attempt_login(credential)
          result_options = {
              credential: credential,
              host: host,
              port: port,
              protocol: 'udp',
              service_name: 'snmp'
          }

          versions.each do |version|
            snmp_client = ::SNMP::Manager.new(
                :Host      => host,
                :Port      => port,
                :Community => credential.public,
                :Version => version,
                :Timeout => connection_timeout,
                :Retries => retries,
                :Transport => ::SNMP::RexUDPTransport,
                :Socket => ::Rex::Socket::Udp.create('Context' => { 'Msf' => framework, 'MsfExploit' => framework_module })
            )

            result_options[:proof] = test_read_access(snmp_client)
            if result_options[:proof].nil?
              result_options[:status] = Metasploit::Model::Login::Status::INCORRECT
            else
              result_options[:status] = Metasploit::Model::Login::Status::SUCCESSFUL
              if has_write_access?(snmp_client, result_options[:proof])
                result_options[:access_level] = "read-write"
              else
                result_options[:access_level] = "read-only"
              end
            end
          end

          ::Metasploit::Framework::LoginScanner::Result.new(result_options)
        end

        private

        # This method takes an snmp client and tests whether
        # it has write access to the remote system. It sets the
        # the sysDescr oid to the same value we already read.
        # @param snmp_client [SNMP::Manager] The SNMP client to use
        # @param value [String] the value to set sysDescr back to
        # @return [Boolean] Returns true or false for if we have write access
        def has_write_access?(snmp_client, value)
          var_bind = ::SNMP::VarBind.new("1.3.6.1.2.1.1.1.0", ::SNMP::OctetString.new(value))
          begin
            resp = snmp_client.set(var_bind)
            if resp.error_status == :noError
              return true
            end
          rescue RuntimeError
            return false
          end

        end

        # Sets the connection timeout appropriately for SNMP
        # if the user did not set it.
        def set_sane_defaults
          self.connection_timeout = DEFAULT_TIMEOUT if self.connection_timeout.nil?
          self.port = DEFAULT_PORT if self.port.nil?
          self.retries = DEFAULT_RETRIES if self.retries.nil?
          self.version = DEFAULT_VERSION if self.version.nil?
        end

        # This method takes an snmp client and tests whether
        # it has read access to the remote system. It checks
        # the sysDescr oid to use as proof
        # @param snmp_client [SNMP::Manager] The SNMP client to use
        # @return [String, nil] Returns a string if successful, nil if failed
        def test_read_access(snmp_client)
          proof = nil
          begin
            resp = snmp_client.get("sysDescr.0")
            resp.each_varbind { |var| proof = var.value }
          rescue RuntimeError
            proof = nil
          end
          proof
        end



      end

    end
  end
end
