# Use Savon SOAP client
# gem install savon
# See http://savonrb.com/version2/client.html
require 'savon'

module Bluecat

  class Api

    # An instance of Bluecat is running at:
    # BLUECAT_IP=172.17.0.10
    # So etiher tunnel to it or change the WsdlUrl
    WsdlUrl = 'http://localhost:3000/Services/API?wsdl'

    # Bluecat user with Api access enabled
    User = 'apiuser'
    Pass = 'apiuser'

    attr_accessor :auth_cookies
    attr_accessor :client

    def initialize
      # Connect to Bluecat SOAP Api
      @client = Savon.client(wsdl: WsdlUrl)
      unless client.nil?
        login
      else
        print "No client\n"
      end
      print "Got cookies %s\n" % auth_cookies
    end

    def login
      # Try to login using apiuser
      # Block style invocation
      response = client.call(:login) do
        message username: User, password: Pass
      end

      # Auth cookies needed for subsequent method invocations
      @auth_cookies = response.http.cookies
    end

    # Get system info
    def system_info
      print "In system_info\n"
      hash = {}
      begin
        print "Calling get_system_info\n"
        response = client.call(:get_system_info) do |ctx|
          ctx.cookies auth_cookies
        end
        print "Called get_system_info\n"

        payload = response.body[:get_system_info_response][:return]
        print "Got payload %s\n" % payload
        kvs = unserialize_properties(payload)
        kvs.each do |k,v|
          hash[k.to_sym] = v
        end
        print "--------------------\n"
      rescue Exception => e
        print "Got Exception %s\n" % e.message
      end
      return hash
    end
    
    def system_test
      # Check for some operations
      unless client.operations.include? :login
        print "Login method missing from Bluecat Api\n"
      end
      unless client.operations.include? :get_system_info
        print "getSystemInfo method missing from Bluecat Api\n"
      else
        unless ( system_info[:address] =~ /\d{1,4}\.\d{1,4}\.\d{1,4}\.\d{1,4}/ ) == 0
          raise 'Failed system sanity test'
        end
      end
    end

    def get_configurations
      response = client.call(:get_entities) do |ctx|
        ctx.cookies auth_cookies
        ctx.message parentId: 0, type: 'Configuration', start: 0, count: 10
      end
      items = canonical_items(response.body[:get_entities_response])
    end
    
    def get_ip4_blocks(parent_id, start=0, count=1)
      response = client.call(:get_entities) do |ctx|
        ctx.cookies auth_cookies
        ctx.message parentId: parent_id, type: 'IP4Block', start: 0, count: 10
      end
      items = canonical_items(response.body[:get_entities_response])
    end

    def get_ip4_networks(parent_id, start=0, count=1)
      response = client.call(:get_entities) do |ctx|
        ctx.cookies auth_cookies
        ctx.message parentId: parent_id, type: 'IP4Network', start: 0, count: 10
      end
      items = canonical_items(response.body[:get_entities_response])
    end
    
    # For the moment this is just one single method that
    # demonstrates some Api calls relevant to the POC
    def poc
      
      # List SOAP operations as a sanity test to be sure wsdl was parsed
      client.operations
      system_test

      # Dump system info
      print "Bluecat system info\n"
      print "--------------------\n"
      system_info.each do |k,v|
        print "  %s = %s\n" % [k,v]
      end
      print "--------------------\n"

      
      #  Some methods used below:
      #  :get_entities
      #  :get_entities_by_name
      #  :get_entities_by_name_using_options
      #  :get_entity_by_name
      #  :get_ip4_address
      #  :get_dependent_records( long entityId, int start, int count )

      # Get all IP4 entities tagged with 'ASM'
      # --------------------------------
      response = client.call(:search_by_category) do |ctx|
        ctx.cookies auth_cookies
        ctx.message keyword: 'ASM', category: 'ALL', start: 0, count: 10
      end
      print "Search found %s\n" % response.body
      
      # Harmonize sequence as array in case only 1 item
      items = response.body[:search_by_category_response][:return][:item]
      items = [ items ].flatten
      items.each do |ent|
        print "Discovered ASM tagged Entity [%s] with id %s\n" % [ent[:name], ent[:id]]
      end
      
      
      # Get all top-level Configurations
      # --------------------------------
      items = get_configurations
      items.each do |config|
        print "Discovered Configuration [%s] with id %s\n" % [config[:name], config[:id]]
      end
      
      config_name = 'AIDEV'
      # Get the Configuration by name
      # -----------------------------
      response = client.call(:get_entity_by_name) do |ctx|
        ctx.cookies auth_cookies
        ctx.message parentId: 0, name: config_name, type: 'Configuration'
      end
      config_id = response.xpath('//id').first.content
      print "Got Configuration [%s] with id %s\n" % [config_name, config_id ]
      
      # Get the IP Blocks under Configuration
      # -------------------------------------
      parent_id = config_id.to_i
      items = get_ip4_blocks(parent_id)
      items.each do |block|
        print "Discovered IP Block [%s] with id %s\n" % [block[:name], block[:id]]
      end
      
      block_name = 'Named Block'
      # Get the IP4 Block by name
      # -------------------------
      response = client.call(:get_entity_by_name) do |ctx|
        ctx.cookies auth_cookies
        ctx.message parentId: parent_id, name: block_name, type: 'IP4Block'
      end
      block_id = response.xpath('//id').first.content
      print "Got IP4 Block [%s] with id %s\n" % [block_name, block_id ]
      
      
      # Get the Networks under the named IP Block
      # -----------------------------------------
      parent_id = block_id.to_i
      items = get_ip4_networks(parent_id)            
      items.each do |network|
        print "Discovered IP4 Network [%s] with id %s\n" % [network[:name], network[:id]]
      end

      network_name = 'Named Network'
      # Get the IP4 Network by name
      # ---------------------------
      response = client.call(:get_entity_by_name) do |ctx|
        ctx.cookies auth_cookies
        ctx.message parentId: parent_id, name: network_name, type: 'IP4Network'
      end
      network_id = response.xpath('//id').first.content
      network_props_str = response.xpath('//properties').first.content
      network_props = unserialize_properties( network_props_str )

      # Grab the default view id for use in assigning host names below
      default_view_id = network_props[:defaultView]
      
      print "Got IP4 Network [%s] with id %s and properties %s\n" % [network_name, network_id, network_props_str ]

      # Get all IPs from Network
      # --------------------------------------
      parent_id = network_id.to_i
      # -------------------------
      response = client.call(:get_entities) do |ctx|
        ctx.cookies auth_cookies
        ctx.message parentId: parent_id, type: 'IP4Address', start: 0, count: 50
      end
      
      # Harmonize sequence in case only 1 item
      items = response.body[:get_entities_response][:return][:item]
      items = [ items ].flatten
      # Delete IP addresses that have a mac address assigned
      items.each do |ip|
        props = unserialize_properties( ip[:properties] )
        if props[:macAddress]
          print "Got IP addr %s with mac addr [%s]\n" % [ ip[:id], props[:macAddress] ]
          response = client.call(:delete) do |ctx|
            ctx.cookies auth_cookies
            ctx.message objectId: ip[:id]
          end
        end
      end
      
     
      # Request next available IP from Network
      # --------------------------------------
      parent_id = network_id.to_i
      # -------------------------
      response = client.call(:get_next_ip4_address) do |ctx|
        ctx.cookies auth_cookies
        ctx.message parentId: parent_id, properties: ''
      end
      ipaddr = response.body[:get_next_ip4_address_response][:return]
      print "Got IP addr %s\n" % ipaddr

      # Assign next available IP from Network
      # --------------------------------------
      parent_id = network_id.to_i
      mac_address = '00:00:00:00:00:03'
      properties_str = 'name=Dorado|asmGuid=FF2987FACC99097987'
      
      host_name = 'ASM760.ufo.com'
      view_id = default_view_id
      
      host_info = "%s,%s,%s,%s" % [ host_name, view_id, 'true', 'false' ]
      # host_info = ''
      
      print "Host info will be: %s\n" % host_info
      
      action = 'MAKE_STATIC'
      # action = 'MAKE_RESERVED'
      # action = 'MAKE_DHCP_RESERVED'

      # -------------------------
      response = client.call(:assign_next_available_ip4_address) do |ctx|
        ctx.cookies auth_cookies
        ctx.message configurationId: config_id, parentId: parent_id, mac_address: mac_address, hostInfo: host_info, action: action, properties: properties_str
      end
      ipaddr_id = response.body[:assign_next_available_ip4_address_response][:return]
      print "Assigned IP addr object id %s\n" % ipaddr_id

    end

    # Utility method to
    # Canonicalize SOAP sequences as array in case 0 or 1 item
    def canonical_items(hash)
      items = []
      unless hash[:return].nil?
        items = hash[:return][:item]
        items = [ items ].flatten
      end
      return items
    end

    # Utility methods to (un)serialize properties
    # Bluecat SOAP Api serializes properties as p1=v1|p2=v2|...
    def unserialize_properties(str)
      hash = {}
      str.split('|').each do |kvstr|
        k,v = kvstr.split('=')
        hash[ k.to_sym ] = v
      end
      hash
    end
    
    def serialize_properties(hash)
      str = ''
      first = true
      hash.each do |k,v|
        unless first
          str << '|'
        else
          first = false
        end
        str << "%s=%s" % [k,v]
      end
      str
    end
    
  end
end
