# Use rubytree gem for tree
require 'rubytree'
require './bluecat_api.rb'

# Customize the json format
module Tree
  class TreeNode
    def as_json(options={})
      json_hash = {
        "name" => name,
        "id" => content[:id],
        "type" => content[:type]
      }
      if has_children?
        json_hash["children"] = children
      end
      return json_hash
    end
  end
end

module Bluecat
  
  class Tree < Api

    attr_accessor :configurations

    def build_ip4_objects( parent_node )
      parent_id = parent_node.content[:id]
      # blocks
      items = get_ip4_blocks(parent_id)
      items.each do |block|
        node = ::Tree::TreeNode.new( block[:name], { :id => block[:id], :type => block[:type] } )
        build_ip4_objects( node )
        parent_node << node
      end
      # networks
      items = get_ip4_networks(parent_id)
      items.each do |network|
        #print "Got Network %s\n" % network
        network_name = network[:name]
        if network_name.nil?
          props = unserialize_properties(network[:properties])
          network_name = props[:CIDR]
        end          
        node = ::Tree::TreeNode.new( network_name, { :id => network[:id], :type => network[:type] } )
        # networks are leaves so stop recursing
        parent_node << node
      end
    end
    
    def build_tree
      @configurations = []
      items = get_configurations
      items.each do |config|
        node = ::Tree::TreeNode.new( config[:name], { :id => config[:id], :type => "Configuration" } )
        build_ip4_objects( node )
        @configurations << node
      end
      #print "In build_tree\n"
    end
    
  end

end

if __FILE__ == $0
  bam_tree = Bluecat::Tree.new
  # bam_tree.system_test

  bam_tree.build_tree

  print "JSON Tree: \n--------------\n %s\n" % bam_tree.configurations.to_json
end
